#!/usr/bin/env python3
"""
Dump every protobuf-c message and enum descriptor from the Insta360 GO firmware.

protobuf-c stamps its descriptors with magic constants, which makes them findable
without knowing any string in advance:

  ProtobufCMessageDescriptor.magic = 0x28aaeef9
  ProtobufCEnumDescriptor.magic    = 0x114315af

32-bit layouts:

  message: magic, name*, short_name*, c_name*, package_name*, sizeof_message,
           n_fields, fields*, fields_sorted_by_name*, n_field_ranges, field_ranges*, ...
  enum:    magic, name*, short_name*, c_name*, package_name*, n_values, values*, ...

  field entry (44 bytes): name*, id, label:u8@+8, type:u8@+9, quantifier_offset,
                          offset, descriptor*, default_value*, flags, ...
  enum value (12 bytes):  name*, c_name*, value:i32
"""
import struct
import re
import sys
import json
import numpy as np

DELTA = 0xA0000E04
MSG_MAGIC = 0x28AAEEF9
ENUM_MAGIC = 0x114315AF
FIELD_SZ = 44
ENUMV_SZ = 12

LABEL = {0: "required", 1: "optional", 2: "repeated", 3: ""}
PTYPE = {0: "int32", 1: "sint32", 2: "sfixed32", 3: "int64", 4: "sint64", 5: "sfixed64",
         6: "uint32", 7: "fixed32", 8: "uint64", 9: "fixed64", 10: "float", 11: "double",
         12: "bool", 13: "enum", 14: "string", 15: "bytes", 16: "message"}
IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_.]*$")

d = open(sys.argv[1] if len(sys.argv) > 1 else "InstaGoFW.bin", "rb").read()
words = np.frombuffer(d[:len(d) // 4 * 4], dtype="<u4")


def cstr(o, limit=128):
    if o is None or o < 0 or o >= len(d):
        return None
    e = d.find(b"\x00", o, o + limit)
    if e < 0:
        return None
    try:
        return d[o:e].decode("ascii")
    except UnicodeDecodeError:
        return None


def s(ptr):
    return cstr(ptr - DELTA) if ptr else None


def find_magic(m):
    return (np.nonzero(words == np.uint32(m))[0] * 4).tolist()


def read_fields(ptr, n):
    base = ptr - DELTA
    out = []
    for k in range(min(n, 400)):
        o = base + k * FIELD_SZ
        if o < 0 or o + FIELD_SZ > len(d):
            break
        nptr, fid = struct.unpack_from("<II", d, o)
        label, ftype = d[o + 8], d[o + 9]
        nm = s(nptr)
        if nm is None:
            break
        out.append({"id": fid, "label": LABEL.get(label, str(label)),
                    "type": PTYPE.get(ftype, str(ftype)), "name": nm})
    return out


def read_enum_values(ptr, n):
    base = ptr - DELTA
    out = []
    for k in range(min(n, 400)):
        o = base + k * ENUMV_SZ
        if o < 0 or o + ENUMV_SZ > len(d):
            break
        nptr, cptr, val = struct.unpack_from("<IIi", d, o)
        nm = s(nptr)
        if nm is None:
            break
        out.append({"value": val, "name": nm})
    return out


messages, enums = [], []

for off in find_magic(MSG_MAGIC):
    try:
        (magic, name_p, short_p, cname_p, pkg_p, sizeof_msg,
         n_fields, fields_p) = struct.unpack_from("<8I", d, off)
    except struct.error:
        continue
    name = s(name_p)
    if not name or not IDENT.match(name) or n_fields > 400 or not fields_p:
        continue
    f = read_fields(fields_p, n_fields)
    if len(f) != n_fields:
        continue
    messages.append({"off": off, "name": name, "n_fields": n_fields, "fields": f})

for off in find_magic(ENUM_MAGIC):
    try:
        (magic, name_p, short_p, cname_p, pkg_p,
         n_values, values_p) = struct.unpack_from("<7I", d, off)
    except struct.error:
        continue
    name = s(name_p)
    if not name or not IDENT.match(name) or n_values > 400 or not values_p:
        continue
    v = read_enum_values(values_p, n_values)
    if len(v) != n_values:
        continue
    enums.append({"off": off, "name": name, "n_values": n_values, "values": v})

messages.sort(key=lambda m: m["name"])
enums.sort(key=lambda e: e["name"])
print(f"recovered {len(messages)} messages, {len(enums)} enums")

json.dump({"messages": messages, "enums": enums}, open("schema.json", "w"), indent=1)

with open("schema.proto.txt", "w") as fh:
    for m in messages:
        fh.write(f"message {m['name']} {{\n")
        for x in m["fields"]:
            fh.write(f"  {x['label']:<8} {x['type']:<8} {x['name']} = {x['id']};\n")
        fh.write("}\n\n")
    for e in enums:
        fh.write(f"enum {e['name']} {{\n")
        for v in e["values"]:
            fh.write(f"  {v['name']} = {v['value']};\n")
        fh.write("}\n\n")
print("wrote schema.json and schema.proto.txt")
