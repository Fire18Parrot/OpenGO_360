#!/usr/bin/env python3
"""
go_core.py  -  Insta360 GO (1st gen) PROTOCOL CORE.  No UI, no BLE library here.

This is the reference implementation of the wire protocol, meant to be ported almost
line-for-line to Kotlin (Android) and Swift (iOS). Everything platform-specific
(the actual BLE connect/write/subscribe) lives OUTSIDE this file, in a thin shim that
calls build_*() to get bytes to write, and feeds received notify bytes into
NotificationParser.feed().

Verified against a real GO 1 ("GO JKDHDY"): record_duration override, capture control,
and the notification stream all confirmed on-device.

WIRE FRAMING (16-byte header, from Packet::newMessagePacket in libOne.so):
   [0:4]  u32 LE total_length          (header + payload)
   [4]    u8  packet_type = 4 (Message)
   [5:7]  u16 LE padding_length
   [7:15] u64 LE packed:
             bits  0..15  command code  <-- CAMERA DISPATCHES ON THIS
             bits 16..23  secondary type (content-type indicator)
             bits 24..53  content length (30-bit)
             bit  54      end flag
             bit  55      direction (1 = phone->camera)
             bits 56..63  content type
   [15]   u8  content_type high byte
   [16:]  protobuf payload

GATT (GO 1): service 0000be80; write char 0000be81 (Write Request), notify char 0000be82.
"""

import struct

# ------------------------------------------------------------------ message codes
class Code:
    # capture / control
    TAKE_PICTURE            = 3
    START_CAPTURE           = 4
    STOP_CAPTURE            = 5
    TAKE_PICTURE_NOSTORE    = 14
    GET_CAPTURE_STATUS      = 15
    GET_TIMELAPSE_OPTIONS   = 17
    SET_TIMELAPSE_OPTIONS   = 18
    START_TIMELAPSE         = 22
    STOP_TIMELAPSE          = 23
    START_BULLETTIME        = 41
    STOP_BULLETTIME         = 48
    GET_OPTIONS             = 8
    SET_OPTIONS             = 7
    SET_PHOTOGRAPHY_OPTIONS = 9
    GET_PHOTOGRAPHY_OPTIONS = 10
    START_LIVE_STREAM       = 1
    STOP_LIVE_STREAM        = 2

# firmware-implemented set on the GO 1 (others answer "unknown msg code")
FW_IMPLEMENTED = {1,2,3,4,5,7,8,9,10,14,15,17,18,22,23,41,48}

# ------------------------------------------------------------------ notification codes
class Notif:
    BEGIN                 = 8192
    FIRMWARE_UPGRADE_DONE = 8193
    CAPTURE_AUTO_SPLIT    = 8194
    BATTERY_UPDATE        = 8195
    BATTERY_LOW           = 8196
    SHUTDOWN              = 8197
    STORAGE_UPDATE        = 8198
    STORAGE_FULL          = 8199
    KEY_PRESSED           = 8200
    CAPTURE_STOPPED       = 8201
    TAKE_PICTURE_STATE    = 8202
    DELETE_FILES_PROGRESS = 8203
    PHONE_INSERT          = 8204
    CURRENT_CAPTURE_STATUS= 8208
    TIMELAPSE_STATUS      = 8210
    CAM_TEMPERATURE       = 8214

NOTIF_NAME = {v: k for k, v in vars(Notif).items() if isinstance(v, int)}

# capture-state enum (capture_state.proto)
CAPTURE_STATE = {0:'idle',1:'recording',2:'timelapse',3:'interval_shooting',4:'single_shot',
                 5:'hdr_shoot',6:'self_timer',7:'bullet_time',8:'settings_changed',9:'hdr_capture',
                 10:'burst',11:'static_timelapse',12:'interval_video',13:'timeshift',14:'aeb_night'}
CARD_STATE = {0:'ok',1:'no_card',2:'no_space',3:'invalid_format',4:'write_protected',5:'error'}

# option enums for the control panel
CAPTURE_MODE  = {'normal':1,'bullettime':2,'hdr':3,'timeshift':4}
TIMELAPSE_MODE= {'mixed':0,'mobile_video':1,'interval_shooting':2,'static_video':3,'interval_video':4}
FUNCTION_MODE_NORMAL_VIDEO = 7
OPTION_RECORD_DURATION = 29

PACKET_TYPE_MESSAGE = 4

# ------------------------------------------------------------------ protobuf mini-encoder
def _varint(n):
    out=bytearray()
    while True:
        b=n&0x7f; n>>=7
        if n: out.append(b|0x80)
        else: out.append(b); return bytes(out)

def _dec_varint(buf,i):
    shift=0; val=0
    while True:
        b=buf[i]; i+=1; val|=(b&0x7f)<<shift
        if not b&0x80: return val,i
        shift+=7

def pb_uint(f,v):  return _varint(f<<3|0)+_varint(v & 0xffffffffffffffff)
def pb_enum(f,v):  return _varint(f<<3|0)+_varint(v)
def pb_bool(f,v):  return _varint(f<<3|0)+_varint(1 if v else 0)
def pb_bytes(f,r): return _varint(f<<3|2)+_varint(len(r))+r

def pb_parse(buf):
    """Minimal protobuf field walker -> {field_no: [values]}. bytes-typed fields kept raw."""
    out={}; i=0; n=len(buf)
    while i<n:
        key,i=_dec_varint(buf,i); fno=key>>3; wt=key&7
        if wt==0:   v,i=_dec_varint(buf,i)
        elif wt==2: ln,i=_dec_varint(buf,i); v=buf[i:i+ln]; i+=ln
        elif wt==5: v=struct.unpack_from('<I',buf,i)[0]; i+=4
        elif wt==1: v=struct.unpack_from('<Q',buf,i)[0]; i+=8
        else: break
        out.setdefault(fno,[]).append(v)
    return out

# ------------------------------------------------------------------ payload builders
def build_set_record_duration(ms, function_mode=FUNCTION_MODE_NORMAL_VIDEO):
    inner = pb_uint(OPTION_RECORD_DURATION, ms)          # PhotographyOptions.record_duration
    body  = pb_enum(1, OPTION_RECORD_DURATION)           # option_types=[RECORD_DURAION]
    body += pb_bytes(2, inner)                           # value
    body += pb_enum(3, function_mode)                    # function_mode
    return body

def build_start_capture(mode='normal'):   return pb_enum(1, CAPTURE_MODE.get(mode,1))
def build_stop_capture(mode='normal'):    return pb_enum(2, CAPTURE_MODE.get(mode,1))
def build_take_picture(raw=False):        return pb_bool(4,True) if raw else b''
def build_start_timelapse(mode='mixed'):  return pb_enum(1, TIMELAPSE_MODE.get(mode,0))
def build_empty():                        return b''

# ------------------------------------------------------------------ frame build / parse
HEADER = 16

def build_frame(code, payload=b'', sec_type=9, content_type=0, end=1, direction=1, padding=0):
    clen=len(payload); total=HEADER+clen
    h=bytearray(HEADER)
    struct.pack_into('<I',h,0,total)
    h[4]=PACKET_TYPE_MESSAGE
    struct.pack_into('<H',h,5,padding)
    packed  = (code & 0xffff)
    packed |= (sec_type & 0xff)     << 16
    packed |= (clen & 0x3fffffff)   << 24
    packed |= (end & 1)             << 54
    packed |= (direction & 1)       << 55
    packed |= (content_type & 0xff) << 56
    struct.pack_into('<Q',h,7,packed)
    h[15]=(content_type>>8)&0xff
    return bytes(h)+payload

def parse_frame(buf):
    if len(buf)<HEADER: return None
    total=struct.unpack_from('<I',buf,0)[0]
    packed=struct.unpack_from('<Q',buf,7)[0]
    code=packed&0xffff; sec=(packed>>16)&0xff; clen=(packed>>24)&0x3fffffff
    return dict(total=total, packet_type=buf[4], code=code, sec_type=sec,
                content_len=clen, payload=buf[HEADER:HEADER+clen])

# high-level convenience: one call -> bytes to write on be81
def cmd_set_record_duration(ms): return build_frame(Code.SET_PHOTOGRAPHY_OPTIONS, build_set_record_duration(ms))
def cmd_start_capture(mode='normal'): return build_frame(Code.START_CAPTURE, build_start_capture(mode))
def cmd_stop_capture(mode='normal'):  return build_frame(Code.STOP_CAPTURE,  build_stop_capture(mode))
def cmd_take_picture(raw=False):      return build_frame(Code.TAKE_PICTURE,  build_take_picture(raw))
def cmd_start_timelapse(mode='mixed'):return build_frame(Code.START_TIMELAPSE,build_start_timelapse(mode))
def cmd_stop_timelapse():             return build_frame(Code.STOP_TIMELAPSE, build_empty())
def cmd_start_bullettime():           return build_frame(Code.START_BULLETTIME,build_empty())
def cmd_stop_bullettime():            return build_frame(Code.STOP_BULLETTIME, build_empty())
def cmd_get_status():                 return build_frame(Code.GET_CAPTURE_STATUS, build_empty())

# ------------------------------------------------------------------ notification decoder
class Event:
    """A decoded camera event, ready for the UI to consume."""
    def __init__(self, kind, **kw): self.kind=kind; self.data=kw
    def __repr__(self): return "Event(%s, %s)" % (self.kind, self.data)

def _decode_battery(payload):
    # NotificationBatteryUpdate { battery_status = BatteryStatus{power_type, battery_level, battery_scale} }
    top=pb_parse(payload)
    bs = top.get(1,[b''])[0]
    if isinstance(bs,(bytes,bytearray)):
        f=pb_parse(bs)
        level=f.get(2,[None])[0]; scale=f.get(3,[100])[0]; ptype=f.get(1,[None])[0]
        pct = int(level*100/scale) if (level is not None and scale) else level
        return dict(percent=pct, level=level, scale=scale, power_type=ptype)
    return dict(raw=payload.hex())

def _decode_storage(payload):
    f=pb_parse(payload)
    cs=f.get(1,[0])[0]; free=f.get(2,[None])[0]; total=f.get(3,[None])[0]
    return dict(card_state=CARD_STATE.get(cs,cs), free_space=free, total_space=total)

def _decode_capture_status(payload):
    # CaptureStatus{state, capture_time} or CameraCaptureStatus{state, capture_time, capture_nums}
    f=pb_parse(payload)
    st=f.get(1,[0])[0]; t=f.get(2,[None])[0]; nums=f.get(3,[None])[0]
    return dict(state=CAPTURE_STATE.get(st,st), capture_time=t, capture_nums=nums)

def _decode_capture_stopped(payload):
    # NotificationCaptureStopped{err_code, video=Video{uri}}
    f=pb_parse(payload)
    err=f.get(1,[0])[0]; uri=None
    if 2 in f and isinstance(f[2][0],(bytes,bytearray)):
        vf=pb_parse(f[2][0]); 
        if 1 in vf and isinstance(vf[1][0],(bytes,bytearray)):
            uri=vf[1][0].decode('latin1',errors='replace')
    return dict(err_code=err, uri=uri)

def _decode_temperature(payload):
    f=pb_parse(payload); return dict(raw=payload.hex(), fields=f)

_DECODERS = {
    Notif.BATTERY_UPDATE:    ('battery',        _decode_battery),
    Notif.BATTERY_LOW:       ('battery_low',    _decode_battery),
    Notif.STORAGE_UPDATE:    ('storage',        _decode_storage),
    Notif.STORAGE_FULL:      ('storage_full',   _decode_storage),
    Notif.CURRENT_CAPTURE_STATUS: ('capture_status', _decode_capture_status),
    Notif.CAPTURE_STOPPED:   ('capture_stopped',_decode_capture_stopped),
    Notif.CAPTURE_AUTO_SPLIT:('auto_split',     lambda p: dict(raw=p.hex())),
    Notif.CAM_TEMPERATURE:   ('temperature',    _decode_temperature),
    Notif.KEY_PRESSED:       ('key_pressed',    lambda p: dict(raw=p.hex())),
    Notif.SHUTDOWN:          ('shutdown',       lambda p: dict()),
}

class NotificationParser:
    """Feed raw BLE notify chunks in; get decoded Events out.

    The camera fragments frames across BLE notifications and also emits 7-byte
    keepalives (packet_type 5). This reassembles by the length field and yields
    one Event per complete message.
    """
    def __init__(self):
        self.buf=bytearray()

    def feed(self, chunk):
        events=[]
        self.buf += bytes(chunk)
        while len(self.buf) >= 4:
            total=struct.unpack_from('<I',self.buf,0)[0]
            # sanity: total must be plausible; if not, drop a byte and resync
            if total < HEADER or total > 4096:
                # 7-byte keepalive (type 5) or garbage: try to skip it
                if len(self.buf)>=7 and self.buf[4]==5:
                    self.buf=self.buf[7:]; continue
                self.buf.pop(0); continue
            if len(self.buf) < total:
                break  # wait for more chunks
            frame=bytes(self.buf[:total]); self.buf=self.buf[total:]
            ev=self._decode_frame(frame)
            if ev: events.append(ev)
        return events

    def _decode_frame(self, frame):
        info=parse_frame(frame)
        if not info: return None
        code=info['code']; payload=info['payload']
        if info['packet_type']==5:   # keepalive
            return None
        dec=_DECODERS.get(code)
        if dec:
            kind,fn=dec
            try: return Event(kind, code=code, **fn(payload))
            except Exception as ex: return Event(kind, code=code, error=str(ex), raw=payload.hex())
        # command reply (echoes the code we sent) or unknown notification
        name=NOTIF_NAME.get(code)
        if name: return Event('notification', code=code, name=name, raw=payload.hex())
        return Event('reply', code=code, raw=payload.hex())

# quick self-test with the real bytes we captured on-device
if __name__ == '__main__':
    p=NotificationParser()
    # capture_stopped fragment carrying the .insv path (from a real stop_capture)
    real = bytes.fromhex('49000000040000c80009020000c020420a370a2e') + b'/DCIM/Camera01/VID_20260729_200605_00_021.insv'
    # (illustrative; real reassembly happens across chunks)
    print("record-duration frame:", cmd_set_record_duration(1200000).hex())
    print("start_capture frame  :", cmd_start_capture().hex())
    print("take_picture frame   :", cmd_take_picture().hex())
    print("get_status frame     :", cmd_get_status().hex())
