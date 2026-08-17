import Foundation

/**
 GoCore — Insta360 GO (1st gen) protocol layer.  (revision 2)

 Direct translation of GoCore.kt revision 2. No CoreBluetooth APIs here on purpose: this
 file is the single source of truth for the wire protocol and should stay logically
 identical to the Kotlin reference.

 What changed vs. revision 1, and why:

  1. STORAGE + BATTERY are not push-only. They are OPTIONS you poll:
     GetOptions{option_types=[BATTERY_STATUS(11), STORAGE_STATE(20)]} on code 8,
     answered with GetOptionsResp{option_types, value=Options}, where
     Options.battery_status = field 11 and Options.storage_state = field 20.
     The camera also emits 8195/8198 notifications, but only when something
     changes — so nothing ever appears until you ask once. Call cmdGetOptions()
     right after connecting and then on a timer.

  2. TEMPERATURE IS NOT DEGREES. temperature.proto: TempState{ temp_state } with
     enum TemperatureState { TEMP_LOW=0, TEMP_ALERT=1, TEMP_MIDDLE=2, TEMP_HIGH=3 }.
     Revision 1 tried to read a °C number and so always came back empty.

  3. FILE LISTING: GetFileList{media_type, start, limit} on code 13 ->
     GetFileListResp{ uri (repeated string), total_count }.

  4. Options.remaining_capture_time (#9) and capture_time_limit (#7) arrive in the
     same GetOptions reply, which is what the recording UI wants.

 Wire framing (16-byte header, from Packet::newMessagePacket in libOne.so):
   [0:4]  u32 LE total length     [4] u8 packet type = 4     [5:7] u16 LE padding
   [7:15] u64 LE packed: bits 0..15 command code, 16..23 secondary type,
          24..53 content length, 54 end, 55 direction, 56..63 content type
   [15]   u8 content type high     [16:] protobuf payload

 GATT: service 0000be80, write 0000be81 (Write Request), notify 0000be82.
 */
enum GoCore {

    static let packetTypeMessage: UInt8 = 4
    static let header = 16

    enum Code {
        static let startLiveStream = 1
        static let stopLiveStream = 2
        static let takePicture = 3
        static let startCapture = 4
        static let stopCapture = 5
        static let setOptions = 7
        static let getOptions = 8
        static let setPhotographyOptions = 9
        static let getPhotographyOptions = 10
        static let getFileExtra = 11
        static let deleteFiles = 12
        static let getFileList = 13
        static let takePictureNostore = 14
        static let getCaptureStatus = 15
        static let setFileExtra = 16
        static let getTimelapseOptions = 17
        static let setTimelapseOptions = 18
        static let startTimelapse = 22
        static let stopTimelapse = 23
        static let getFileinfoList = 38
        static let startBullettime = 41
        static let stopBullettime = 48
    }

    static let fwImplemented: Set<Int> =
        [1, 2, 3, 4, 5, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 22, 23, 38, 41, 48]

    enum Notif {
        static let captureAutoSplit = 8194
        static let batteryUpdate = 8195
        static let batteryLow = 8196
        static let shutdown = 8197
        static let storageUpdate = 8198
        static let storageFull = 8199
        static let keyPressed = 8200
        static let captureStopped = 8201
        static let takePictureState = 8202
        static let currentCaptureStatus = 8208
        static let timelapseStatus = 8210
        static let camTemperature = 8214
    }

    /// OptionType values (options.proto) used with GetOptions.
    enum Opt {
        static let captureTimeLimit = 7
        static let remainingCaptureTime = 9
        static let batteryStatus = 11
        static let storageState = 20
    }

    // Options message field numbers (same numbers as the OptionType values above)
    private static let fCaptureTimeLimit = 7
    private static let fRemainingCaptureTime = 9
    private static let fBatteryStatus = 11
    private static let fStorageState = 20

    static let functionModeNormalVideo = 7
    static let optionRecordDuration = 29

    static let captureMode: [String: Int] = [
        "normal": 1, "bullettime": 2, "hdr": 3, "timeshift": 4
    ]
    static let timelapseMode: [String: Int] = [
        "mixed": 0, "mobile_video": 1, "interval_shooting": 2,
        "static_video": 3, "interval_video": 4
    ]
    static let captureState: [Int: String] = [
        0: "idle", 1: "recording", 2: "timelapse", 3: "interval_shooting",
        4: "single_shot", 5: "hdr_shoot", 6: "self_timer", 7: "bullet_time",
        8: "settings_changed", 9: "hdr_capture", 10: "burst",
        11: "static_timelapse", 12: "interval_video", 13: "timeshift", 14: "aeb_night"
    ]
    static let cardState: [Int: String] = [
        0: "ok", 1: "no card", 2: "no space",
        3: "bad format", 4: "write protected", 5: "error"
    ]
    /// TemperatureState — a state, not degrees.
    static let tempStateNames: [Int: String] = [0: "Normal", 1: "Alert", 2: "Warm", 3: "Hot"]

    /// MediaType (media.proto)
    enum Media {
        static let video = 0
        static let photo = 1
        static let videoAndPhoto = 2
        static let dng = 3
        static let mp4 = 4
        static let jpg = 5
    }

    // ---------------------------------------------------------------- protobuf
    static func varint(_ value: UInt64) -> [UInt8] {
        var n = value
        var out: [UInt8] = []
        out.reserveCapacity(10)
        while true {
            let b = UInt8(n & 0x7f)
            n >>= 7
            if n != 0 { out.append(b | 0x80) } else { out.append(b); break }
        }
        return out
    }

    static func tag(_ field: Int, _ wire: Int) -> [UInt8] {
        varint(UInt64((field << 3) | wire))
    }

    static func pbUInt(_ field: Int, _ v: UInt64) -> [UInt8] { tag(field, 0) + varint(v) }
    static func pbEnum(_ field: Int, _ v: Int) -> [UInt8] { tag(field, 0) + varint(UInt64(v)) }
    static func pbBool(_ field: Int, _ v: Bool) -> [UInt8] { tag(field, 0) + varint(v ? 1 : 0) }
    static func pbBytes(_ field: Int, _ raw: [UInt8]) -> [UInt8] {
        tag(field, 2) + varint(UInt64(raw.count)) + raw
    }

    /// A single decoded protobuf field value: either a varint/fixed number or a blob.
    enum PBValue {
        case num(UInt64)
        case bytes([UInt8])

        var asNum: UInt64? {
            if case .num(let n) = self { return n }
            return nil
        }
        var asBytes: [UInt8]? {
            if case .bytes(let b) = self { return b }
            return nil
        }
    }

    private struct Reader {
        let b: [UInt8]
        var i = 0

        mutating func varint() -> UInt64 {
            var shift: UInt64 = 0
            var v: UInt64 = 0
            while i < b.count {
                let x = UInt64(b[i])
                i += 1
                v |= (x & 0x7f) << shift
                if x & 0x80 == 0 { break }
                shift += 7
                if shift > 63 { break }
            }
            return v
        }
    }

    static func pbParse(_ buf: [UInt8]) -> [Int: [PBValue]] {
        var out: [Int: [PBValue]] = [:]
        var r = Reader(b: buf)
        while r.i < buf.count {
            let key = r.varint()
            let fno = Int(truncatingIfNeeded: key >> 3)
            if fno == 0 { return out }
            switch Int(key & 7) {
            case 0:
                out[fno, default: []].append(.num(r.varint()))
            case 2:
                let lenRaw = r.varint()
                let remaining = buf.count - r.i
                guard remaining >= 0, lenRaw <= UInt64(remaining) else { return out }
                let len = Int(lenRaw)
                out[fno, default: []].append(.bytes(Array(buf[r.i ..< (r.i + len)])))
                r.i += len
            case 5:
                guard r.i + 4 <= buf.count else { return out }
                out[fno, default: []].append(.num(le(buf, r.i, 4)))
                r.i += 4
            case 1:
                guard r.i + 8 <= buf.count else { return out }
                out[fno, default: []].append(.num(le(buf, r.i, 8)))
                r.i += 8
            default:
                return out
            }
        }
        return out
    }

    /// Little-endian read of `n` bytes (n <= 8) at offset `o`.
    static func le(_ b: [UInt8], _ o: Int, _ n: Int) -> UInt64 {
        var v: UInt64 = 0
        var k = n - 1
        while k >= 0 {
            v = (v << 8) | UInt64(b[o + k])
            k -= 1
        }
        return v
    }

    // ---------------------------------------------------------------- payloads
    static func payloadSetRecordDuration(
        ms: UInt64,
        functionMode: Int = GoCore.functionModeNormalVideo
    ) -> [UInt8] {
        let inner = pbUInt(optionRecordDuration, ms)
        return pbEnum(1, optionRecordDuration) + pbBytes(2, inner) + pbEnum(3, functionMode)
    }

    static func payloadStartCapture(mode: String = "normal") -> [UInt8] {
        pbEnum(1, captureMode[mode] ?? 1)
    }
    static func payloadStopCapture(mode: String = "normal") -> [UInt8] {
        pbEnum(2, captureMode[mode] ?? 1)
    }
    static func payloadTakePicture(raw: Bool = false) -> [UInt8] {
        raw ? pbBool(4, true) : []
    }
    static func payloadStartTimelapse(mode: String = "mixed") -> [UInt8] {
        pbEnum(1, timelapseMode[mode] ?? 0)
    }

    /// GetOptions { option_types = [...] } — repeated enum, one tag per value.
    static func payloadGetOptions(_ types: [Int]) -> [UInt8] {
        var out: [UInt8] = []
        for t in types { out += pbEnum(1, t) }
        return out
    }

    /// GetFileList { media_type, start, limit }
    static func payloadGetFileList(
        mediaType: Int = Media.videoAndPhoto,
        start: Int = 0,
        limit: Int = 50
    ) -> [UInt8] {
        pbEnum(1, mediaType) + pbUInt(2, UInt64(start)) + pbUInt(3, UInt64(limit))
    }

    /// DeleteFiles { uri repeated string }
    static func payloadDeleteFiles(_ uris: [String]) -> [UInt8] {
        var out: [UInt8] = []
        for u in uris { out += pbBytes(1, Array(u.utf8)) }
        return out
    }

    // ---------------------------------------------------------------- frames
    static func buildFrame(
        code: Int,
        payload: [UInt8] = [],
        secType: Int = 9,
        contentType: Int = 0,
        end: Int = 1,
        direction: Int = 1,
        padding: Int = 0
    ) -> Data {
        let clen = payload.count
        let total = header + clen
        var out = [UInt8](repeating: 0, count: total)
        out[0] = UInt8(total & 0xff)
        out[1] = UInt8((total >> 8) & 0xff)
        out[2] = UInt8((total >> 16) & 0xff)
        out[3] = UInt8((total >> 24) & 0xff)
        out[4] = packetTypeMessage
        out[5] = UInt8(padding & 0xff)
        out[6] = UInt8((padding >> 8) & 0xff)
        var packed = UInt64(code) & 0xffff
        packed |= (UInt64(secType) & 0xff) << 16
        packed |= (UInt64(clen) & 0x3fff_ffff) << 24
        packed |= (UInt64(end) & 1) << 54
        packed |= (UInt64(direction) & 1) << 55
        packed |= (UInt64(contentType) & 0xff) << 56
        for k in 0 ..< 8 {
            out[7 + k] = UInt8((packed >> (8 * UInt64(k))) & 0xff)
        }
        out[15] = UInt8((contentType >> 8) & 0xff)
        for (k, b) in payload.enumerated() {
            out[header + k] = b
        }
        return Data(out)
    }

    struct FrameInfo {
        let total: Int
        let packetType: Int
        let code: Int
        let secType: Int
        let contentLen: Int
        let payload: [UInt8]
    }

    static func parseFrame(_ buf: [UInt8]) -> FrameInfo? {
        guard buf.count >= header else { return nil }
        let total = Int(le(buf, 0, 4))
        var packed: UInt64 = 0
        var k = 7
        while k >= 0 {
            packed = (packed << 8) | UInt64(buf[7 + k])
            k -= 1
        }
        let code = Int(packed & 0xffff)
        let sec = Int((packed >> 16) & 0xff)
        let clen = Int((packed >> 24) & 0x3fff_ffff)
        let endIdx = min(header + clen, buf.count)
        let start = min(header, endIdx)
        return FrameInfo(
            total: total,
            packetType: Int(buf[4]),
            code: code,
            secType: sec,
            contentLen: clen,
            payload: Array(buf[start ..< endIdx])
        )
    }

    // ---- one-call commands ----
    static func cmdSetRecordDuration(ms: UInt64) -> Data {
        buildFrame(code: Code.setPhotographyOptions, payload: payloadSetRecordDuration(ms: ms))
    }
    static func cmdStartCapture(mode: String = "normal") -> Data {
        buildFrame(code: Code.startCapture, payload: payloadStartCapture(mode: mode))
    }
    static func cmdStopCapture(mode: String = "normal") -> Data {
        buildFrame(code: Code.stopCapture, payload: payloadStopCapture(mode: mode))
    }
    static func cmdTakePicture(raw: Bool = false) -> Data {
        buildFrame(code: Code.takePicture, payload: payloadTakePicture(raw: raw))
    }
    static func cmdStartTimelapse(mode: String = "mixed") -> Data {
        buildFrame(code: Code.startTimelapse, payload: payloadStartTimelapse(mode: mode))
    }
    static func cmdStopTimelapse() -> Data { buildFrame(code: Code.stopTimelapse) }
    static func cmdStartBulletTime() -> Data { buildFrame(code: Code.startBullettime) }
    static func cmdStopBulletTime() -> Data { buildFrame(code: Code.stopBullettime) }
    static func cmdGetStatus() -> Data { buildFrame(code: Code.getCaptureStatus) }

    /// Poll battery + storage + remaining/limit. Send after connect and on a timer.
    static func cmdGetOptions(
        types: [Int] = [
            Opt.batteryStatus, Opt.storageState,
            Opt.remainingCaptureTime, Opt.captureTimeLimit
        ]
    ) -> Data {
        buildFrame(code: Code.getOptions, payload: payloadGetOptions(types))
    }

    static func cmdGetFileList(
        mediaType: Int = Media.videoAndPhoto,
        start: Int = 0,
        limit: Int = 50
    ) -> Data {
        buildFrame(
            code: Code.getFileList,
            payload: payloadGetFileList(mediaType: mediaType, start: start, limit: limit)
        )
    }

    static func cmdDeleteFiles(_ uris: [String]) -> Data {
        buildFrame(code: Code.deleteFiles, payload: payloadDeleteFiles(uris))
    }

    // ---------------------------------------------------------------- events
    enum Event {
        case battery(percent: Int?, charging: Bool)
        case storage(cardState: String, free: UInt64?, total: UInt64?)
        case captureStatus(state: String, captureTime: UInt64?, nums: UInt64?)
        case captureStopped(errCode: UInt64, uri: String?)
        /// TemperatureState, e.g. "Normal" / "Warm" / "Hot" — not degrees.
        case temperature(state: String, level: Int)
        case remaining(remainingSec: UInt64?, limitSec: UInt64?)
        case fileList(uris: [String], totalCount: Int)
        case notification(code: Int, raw: String)
        case reply(code: Int, raw: String)
    }

    static func hex(_ b: [UInt8]) -> String {
        b.map { String(format: "%02x", $0) }.joined()
    }

    private static func batteryFrom(_ f: [Int: [PBValue]]) -> Event {
        let level = f[2]?.first?.asNum
        let scale = f[3]?.first?.asNum ?? 100
        let type = f[1]?.first?.asNum ?? 0
        let pct = (level != nil && scale > 0) ? Int(level! * 100 / scale) : nil
        return .battery(percent: pct, charging: type == 1)
    }

    private static func storageFrom(_ f: [Int: [PBValue]]) -> Event {
        let cs = Int(f[1]?.first?.asNum ?? 0)
        return .storage(
            cardState: cardState[cs] ?? "?",
            free: f[2]?.first?.asNum,
            total: f[3]?.first?.asNum
        )
    }

    /// NotificationBatteryUpdate wraps BatteryStatus in field 1; the option form is flat.
    private static func decodeBatteryNotif(_ p: [UInt8]) -> Event {
        let top = pbParse(p)
        if let sub = top[1]?.first?.asBytes {
            return batteryFrom(pbParse(sub))
        }
        return batteryFrom(top)
    }

    private static func decodeTemp(_ p: [UInt8]) -> Event {
        let f = pbParse(p)
        var v = f[1]?.first?.asNum
        if v == nil, let sub = f[1]?.first?.asBytes {
            v = pbParse(sub)[1]?.first?.asNum
        }
        let lvl = Int(v ?? 0)
        return .temperature(state: tempStateNames[lvl] ?? "?", level: lvl)
    }

    private static func decodeCaptureStatus(_ p: [UInt8]) -> Event {
        let f = pbParse(p)
        let st = Int(f[1]?.first?.asNum ?? 0)
        return .captureStatus(
            state: captureState[st] ?? String(st),
            captureTime: f[2]?.first?.asNum,
            nums: f[3]?.first?.asNum
        )
    }

    private static func decodeCaptureStopped(_ p: [UInt8]) -> Event {
        let f = pbParse(p)
        let err = f[1]?.first?.asNum ?? 0
        var uri: String? = nil
        if let v = f[2]?.first?.asBytes {
            if let u = pbParse(v)[1]?.first?.asBytes {
                uri = String(decoding: u, as: UTF8.self)
            }
        }
        return .captureStopped(errCode: err, uri: uri)
    }

    /// GetOptionsResp { option_types, value = Options } -> possibly several events.
    private static func decodeGetOptionsResp(_ p: [UInt8]) -> [Event] {
        var out: [Event] = []
        let top = pbParse(p)
        // some builds answer flat
        let opts = top[2]?.first?.asBytes.map { pbParse($0) } ?? top
        if let b = opts[fBatteryStatus]?.first?.asBytes {
            out.append(batteryFrom(pbParse(b)))
        }
        if let s = opts[fStorageState]?.first?.asBytes {
            out.append(storageFrom(pbParse(s)))
        }
        let rem = opts[fRemainingCaptureTime]?.first?.asNum
        let lim = opts[fCaptureTimeLimit]?.first?.asNum
        if rem != nil || lim != nil {
            out.append(.remaining(remainingSec: rem, limitSec: lim))
        }
        if out.isEmpty {
            out.append(.reply(code: Code.getOptions, raw: hex(p)))
        }
        return out
    }

    /// GetFileListResp { uri repeated string, total_count }
    private static func decodeFileList(_ p: [UInt8]) -> Event {
        let f = pbParse(p)
        let uris = (f[1] ?? []).compactMap { v -> String? in
            guard let b = v.asBytes else { return nil }
            return String(decoding: b, as: UTF8.self)
        }
        let total = Int(f[2]?.first?.asNum ?? UInt64(uris.count))
        return .fileList(uris: uris, totalCount: total)
    }

    final class NotificationParser {
        private var buf: [UInt8] = []

        func feed(_ chunk: [UInt8]) -> [Event] {
            var events: [Event] = []
            buf.append(contentsOf: chunk)
            while buf.count >= 4 {
                let total = Int(GoCore.le(buf, 0, 4))
                if total < GoCore.header || total > 65536 {
                    if buf.count >= 7 && buf[4] == 5 {
                        buf.removeFirst(7)
                    } else {
                        buf.removeFirst(1)
                    }
                    continue
                }
                if buf.count < total { break }
                let frame = Array(buf[0 ..< total])
                buf.removeFirst(total)
                events.append(contentsOf: GoCore.decode(frame))
            }
            return events
        }
    }

    fileprivate static func decode(_ frame: [UInt8]) -> [Event] {
        guard let info = parseFrame(frame) else { return [] }
        if info.packetType == 5 { return [] }
        let p = info.payload
        switch info.code {
        case Notif.batteryUpdate, Notif.batteryLow:
            return [decodeBatteryNotif(p)]
        case Notif.storageUpdate, Notif.storageFull:
            return [storageFrom(pbParse(p))]
        case Notif.currentCaptureStatus:
            return [decodeCaptureStatus(p)]
        case Notif.captureStopped:
            return [decodeCaptureStopped(p)]
        case Notif.camTemperature:
            return [decodeTemp(p)]
        case Code.getOptions:
            return decodeGetOptionsResp(p)
        case Code.getFileList:
            return [decodeFileList(p)]
        case Code.getCaptureStatus:
            return [decodeCaptureStatus(p)]
        default:
            return [info.code >= 8192
                ? .notification(code: info.code, raw: hex(p))
                : .reply(code: info.code, raw: hex(p))]
        }
    }
}
