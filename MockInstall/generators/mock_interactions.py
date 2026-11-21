#!/usr/bin/env python3
"""Gives MockInstall interactions, all made up: the Mock Ball (0x4D4F4308), mockball.iff in
objiff.far with its lines in objecttable.xml and catalog.xml, and a main for the Mock Sim that
runs what's queued.

The ball has an interaction table (TTAB 128, version 10, field-encoded as TSO's are) with two
interactions, named in TTAs 128:

- 0, "Dance With" (BHAV 4098): Animate Sim plays the ball's animation 1 (STR# 129: mock-dance) on
  the Sim, looping back on each event, and returns true when it ends. No check tree.
- 1, "Pick Up" (BHAV 4099): Reach takes the ball in hand, then Drop puts it down beside the Sim.
  Its check tree is the semi-global's routine 8192, which returns true. It advertises one motive.

BHAV 4100, "CT - Grab", adds 1 to attribute 1: the tree an object runs when a reach takes it.
The ball's init and main are the other objects' (main counts its runs in attribute 0); it has no
sprites.

The Sim's main (BHAV 4096 in mocksim.iff) adds 1 to attribute 0, then waits for input with Idle
For Input, pushing allowed, counting from argument 0 (0, so it returns the same tick unless an
interaction is queued, which it runs first).

It rewrites mockball.iff and the Sim's main each run, byte for byte the same, and copies every
other entry and chunk as it is. Usage: mock_interactions.py MockInstall/TSOClient"""
import os, struct, sys

root = sys.argv[1]
far_path = os.path.join(root, "objectdata/objects/objiff.far")
GUID = 0x4D4F4308
TABLE = 128

# --- objiff.far (FAR 1b)
b = open(far_path, "rb").read()
assert b[:8] == b"FAR!byAZ"
version, manifest = struct.unpack_from("<II", b, 8)
count, = struct.unpack_from("<I", b, manifest)
p, entries = manifest + 4, []
for _ in range(count):
    size1, size2, offset, name_length = struct.unpack_from("<iiih", b, p)
    entries.append([b[p + 14:p + 14 + name_length], b[offset:offset + size1]])
    p += 14 + name_length

def chunks(iff):
    q, out = 64, []
    while q + 76 <= len(iff):
        size, = struct.unpack_from(">I", iff, q + 4)
        out.append(iff[q:q + size])
        q += size
    return out

def chunk_of(name, type_code, chunk_id):
    for entry in entries:
        if entry[0] == name:
            for c in chunks(entry[1]):
                if c[:4] == type_code and struct.unpack_from(">H", c, 8)[0] == chunk_id:
                    return c
    sys.exit(f"no {type_code} {chunk_id} in {name}")

def chunk(type_code, chunk_id, flags, label, data):
    return (type_code + struct.pack(">I", 76 + len(data)) + struct.pack(">HH", chunk_id, flags)
            + label.encode("ascii").ljust(64, b"\0") + data)

def strings(values):
    """STR# format -2: a count, then each string and an empty comment, NUL-terminated."""
    return struct.pack("<hH", -2, len(values)) + b"".join(t.encode("ascii") + b"\0\0" for t in values)

def bhav(instructions, arguments=4):
    """BHAV 0x8002: a header, then 12-byte instructions (opcode, true and false pointers, operand)."""
    out = struct.pack("<HHBBBBI", 0x8002, len(instructions), 0, arguments, 0, 0, 0)
    for opcode, true, false, operand in instructions:
        out += struct.pack("<HBB", opcode, true, false) + operand.ljust(8, b"\0")
    return out

class Fields:
    """Field-encoded values, as TTAB versions 9 and 10 store them: a 0 bit for zero, else a 1
    bit, two bits naming the width, and the value in that many bits, sign-extended on reading."""
    def __init__(self): self.bits = []
    def value(self, v, widths):
        if v == 0: self.bits.append(0); return
        for code, width in enumerate(widths):
            if -(1 << (width - 1)) <= v < (1 << (width - 1)): break
        else:
            sys.exit(f"{v} doesn't fit")
        self.bits += [1, code >> 1, code & 1] + [(v >> (width - 1 - i)) & 1 for i in range(width)]
    def short(self, v): self.value(v, [5, 8, 13, 16])
    def long(self, v): self.value(v, [6, 11, 21, 32])
    def bytes(self):
        bits = self.bits + [0] * (-len(self.bits) % 8)
        return bytes(int("".join(map(str, bits[i:i + 8])), 2) for i in range(0, len(bits), 8))

# Interactions: action, check, flags, TTA index, joining index, motive entries, TSO flags.
interactions = [(4098, 0, 0x1, 0, -1, [], 0x1F),
                (4099, 8192, 0x1, 1, -1, [(0, 20, 0)], 0x16)]
fields = Fields()
for action, check, flags, index, joining, motives, tso in interactions:
    fields.short(action); fields.short(check); fields.long(len(motives))
    fields.long(flags); fields.long(index); fields.long(0)   # attenuation code
    fields.long(0); fields.long(0); fields.long(joining)      # attenuation, autonomy threshold
    for low, high, personality in motives:
        fields.short(low); fields.short(high); fields.short(personality)
    fields.long(tso)
ttab = struct.pack("<HHB", len(interactions), 10, 1) + fields.bytes()

# OBJD: the register's, with the ball's GUID and interaction table.
objd = bytearray(chunk_of(b"mockregister.iff", b"OBJD", 128))
words = 76
struct.pack_into("<H", objd, words + 2 * 7, TABLE)                       # TreeTableID
struct.pack_into("<HH", objd, words + 2 * 14, GUID & 0xFFFF, GUID >> 16)  # GUID
objd[12:76] = b"mockball".ljust(64, b"\0")

expression = lambda lhs, rhs, op, lhs_owner, rhs_owner: struct.pack("<HHBBBB", lhs, rhs, 0, op, lhs_owner, rhs_owner)
iff = bytearray(b"IFF FILE 2.5:TYPE FOLLOWED BY SIZE\0 JAMIE DOORNBOS & MAXIS 1".ljust(64, b"\0"))
iff += bytes(objd)
iff += chunk_of(b"mockregister.iff", b"GLOB", 128)
iff += chunk_of(b"mockregister.iff", b"BHAV", 4097)                      # init
iff += chunk_of(b"mockchair.iff", b"BHAV", 4096)                         # main
iff += chunk(b"BHAV", 4098, 0, "dance with",
             bhav([(44, 254, 0, struct.pack("<HBBBBB", 1, 0, 0, 0, 0, 0))]))           # Animate Sim
iff += chunk(b"BHAV", 4099, 0, "pick up",
             bhav([(47, 1, 255, struct.pack("<HHH", 0, 1, 0)),                         # Reach, mode 0
                   (5, 254, 255, b"")]))                                               # Drop
iff += chunk(b"BHAV", 4100, 0, "CT - Grab", bhav([(2, 254, 255, expression(1, 1, 3, 0, 7))]))
iff += chunk(b"TTAB", TABLE, 0, "mock ball interactions", ttab)
iff += chunk(b"TTAs", TABLE, 0x10, "mock ball interactions", strings(["Dance With", "Pick Up"]))
iff += chunk(b"STR#", 129, 0x10, "mock ball animations", strings(["", "mock-dance"]))

# The Sim's main: attribute 0 += 1, then Idle For Input (argument 0, pushing allowed).
sim_main = chunk(b"BHAV", 4096, 0, "main",
                 bhav([(2, 1, 1, expression(0, 1, 3, 0, 7)), (17, 254, 254, struct.pack("<hH", 0, 1))]))
for entry in entries:
    if entry[0] != b"mocksim.iff": continue
    sim = bytearray(entry[1][:64])
    for c in chunks(entry[1]):
        sim += sim_main if c[:4] == b"BHAV" and struct.unpack_from(">H", c, 8)[0] == 4096 else c
    entry[1] = bytes(sim)
    break
else:
    sys.exit("no mocksim.iff")

entries = [e for e in entries if e[0] != b"mockball.iff"] + [[b"mockball.iff", bytes(iff)]]
body = b"".join(e[1] for e in entries)
out = bytearray(b"FAR!byAZ" + struct.pack("<II", version, 16 + len(body)) + body)
out += struct.pack("<I", len(entries))
offset = 16
for name, contents in entries:
    out += struct.pack("<iiih", len(contents), len(contents), offset, len(name)) + name
    offset += len(contents)
open(far_path, "wb").write(out)

# --- The packing slips: add the ball's line once.
def add_line(relative, marker, line):
    path = os.path.join(root, relative)
    text = open(path).read()
    if "0x4D4F4308" in text: return
    i = text.index(marker)
    open(path, "w").write(text[:i] + line + "\n" + text[i:])

add_line("packingslips/objecttable.xml", "</ObjectInfoTable>", '  <I g="0x4D4F4308" n="mockball" o="Mock Ball" m="0" i="0"/>')
add_line("packingslips/catalog.xml", "</Catalog>", '<P g="0x4D4F4308" s="6" p="10" n="Mock Ball"></P>')
print(f"mockball.iff: {len(iff)} bytes, {len(interactions)} interactions")
