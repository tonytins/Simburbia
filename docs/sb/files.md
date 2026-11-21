# TSOFiles: reading the game's files

TSOFiles reads TSO's file formats and nothing else. It knows no game rules, finds no install, and
has no dependencies beyond Foundation. Everything above it (content, the VM, the checker) reads
files through it.

## Containers

TSO packs most of its data into four container formats. Each reader parses the header and the
list of entries up front, then reads an entry's data when asked.

| Type | Format | Used for |
| --- | --- | --- |
| `FAR1Archive` | FAR version 1 (layout 1b in TSO, 1a in The Sims 1) | objects, floors, walls, semi-globals |
| `FAR3Archive` | FAR version 3, entries optionally RefPack-compressed | avatars, UI, other assets |
| `DBPFArchive` | Database-packed file | audio |
| `IFFFile` | Maxis IFF | objects, behavior, strings, sprites |

`init(contentsOf:)` memory-maps the file instead of copying it, so opening `objiff.far` (about
17 MB) costs little until entries are read. Archives are values, so several threads can read one
without locking.

```swift
import TSOFiles

let objects = try FAR1Archive(contentsOf: install.appendingPathComponent("objectdata/objects/objiff.far"),
                              variant: .b)
for entry in objects.entries.prefix(3) {
    print(entry.fileName, entry.dataLength)        // e.g. "chairs.iff 48212"
}
if let chairs = objects.entry(named: "chairs.iff") {
    let iff = try IFFFile(bytes: try objects.data(for: chairs))
    print(iff.chunks.count)
}
```

FAR3 entries carry an `AssetID`, a file ID and a type ID. Content files refer to each other by
the packed 64-bit form, `(fileID << 32) | typeID`:

```swift
let id = AssetID(packed: 0x0000_0123_0000_0005)
print(id.fileID, id.typeID, id)                     // 291 5 0x12300000005
```

Compressed FAR3 entries are decompressed with `RefPack.decompress(_:decompressedSize:)`, which
reads valid data as the game wrote it and throws `RefPackError` on data that would run past either end.

## IFF files and chunks

An `IFFFile` keeps **every** chunk as an `IFFChunkRecord` (type code, ID, flags, label, and raw
data), even types it can't parse, so patches and tools never lose data. Typed parsing happens on demand:

```swift
let iff = try IFFFile(contentsOf: url)
if let definition = try iff.chunk(OBJD.self, id: 128) {
    print(String(definition.guid, radix: 16), definition.bhavMainID)
}
for routine in try iff.chunks(BHAV.self) {
    print(routine.id, routine.label, routine.instructions.count)
}
```

The typed chunks the VM needs so far:

| Chunk | Holds |
| --- | --- |
| `OBJD` | An object definition: GUID, entry point routine IDs, tree table ID, master ID for multi-tile parts, and about 100 other fields. Kept as raw 16-bit words with named accessors, so any version reads the same way |
| `OBJf` | An object's event table: condition and action routines per entry point |
| `BHAV` | A routine: header (argument and local counts) and instructions (opcode, true and false pointers, 8-byte operand). Four header versions |
| `TPRP` | Names for a routine's parameters and locals |
| `BCON`, `TRCN` | Behavior constants and their labels |
| `GLOB` | The name of the semi-global file an object shares code with |
| `SLOT` | Where Sims stand or sit and where objects go |
| `TTAB`, `TTAs` | Interactions (pie menu entries and their routines) and their text |
| `STR#`, `CTSS` | Localized strings |
| `FWAV` | Sound event names |
| `PIFF` | Patches (FreeSO's format; see [Patches](#patches)) |

A malformed chunk throws `IFFChunkError`, either `.truncated(typeCode:id:_:)` or `.invalid(typeCode:id:reason:)`,
wherever its data can't be what the chunk says.

`BHAV` can also be built and written, for tools that generate behavior. Reading the result gives
back an equal routine:

```swift
let routine = BHAV(id: 4096, label: "main", instructions: [
    BHAV.Instruction(opcode: 2, truePointer: 254, falsePointer: 255,
                     operand: Data([0, 0, 7, 0, 0, 0, 5, 8])),  // an Expression operand
])
let bytes = routine.encoded()
```

String tables (`STR#`, `CTSS`, `TTAs`) share `StringTable`, which reads all five formats and
looks strings up by language, falling back to English (US):

```swift
if let names = try iff.chunk(STR.self, id: 128) {
    print(names.table.string(at: 0) ?? "")
}
```

## Patches

PIFF patches (`.piff` files) fix objects in place. The format is FreeSO's: it shipped patches in
its content folder's `Patch`, and players make their own. `PatchRegistry` collects them by the IFF they patch; a patch under a
`User/` folder replaces the shipped ones for that IFF.

```swift
let registry = try PatchRegistry(directory: freeSOContent.appendingPathComponent("Patch"))
let outcome = registry.applyingPatches(to: iff, fileName: "chairs.iff")
print(outcome.applied)                                   // patches that fit, in order
for skipped in outcome.skipped { print(skipped.name, skipped.reason) }
let patched = outcome.file
```

A patch is applied whole or not at all. It's kept only if it applies cleanly and every chunk it
touches still parses. On 1.1097.1.0 every patch that targets an object in `objiff.far` fits (all 32).
On the beta, a patch that doesn't fit is skipped and reported, and the object loads unpatched.

## Tables and text formats

| Type | File | Notes |
| --- | --- | --- |
| `OTFFile` | object tuning (`.otf`), XML | tables of named constants; the VM reads them when a `BCON` lacks a key |
| `TuningFile` | `tuning.dat` | global tuning: obfuscated, RefPack-compressed key and value strings |
| `INIFile` | `sys/*.ini` | sections of `key = value` lines |
| `DataDefinition` | `TSOData_datadefinition.dat` | the data service's schema |

```swift
let tuning = try TuningFile(bytes: Data(contentsOf: install.appendingPathComponent("tuning.dat")))
for entry in tuning.entries.prefix(3) {
    print(entry.name, entry.values.count)           // entry(named:) matches names in any case
}

let otf = try OTFFile(contentsOf: chairsOTF)
print(otf.table(id: 4096)?.key(id: 0)?.value ?? 0)
```

## Images

`BMPImage` and `TargaImage` (`Images/RasterImage.swift`) decode the picture files TSO's interface
uses into a `RasterImage`: red, green, blue, and alpha for each pixel, top row first.

| Reader | Reads |
| --- | --- |
| `BMPImage` | 8-bit with a palette, plain or run-length (RLE8), and 24-bit; the 40-byte header; bottom-up, or top-down with a negative height |
| `TargaImage` | 24- and 32-bit truecolor, plain (type 2) or run-length (type 10); bottom-up or top-down by the descriptor; `hasFooter` finds the 2.0 footer |

Every size, offset, and run is checked against the bytes, and a picture past 64 million pixels is
refused. A 32-bit Targa whose descriptor declares no alpha bits is opaque, and a run-length bitmap
that ends before its last row leaves the rest transparent. Every interface graphic of all three
installs decodes as Pillow decodes it, pixel for pixel, but such short bitmaps, which Pillow
refuses (three on 1.1097.1.0, one on each 2002 copy; checked 2026-11-04).

## Animations

`Animation` (`Avatars/Animation.swift`) reads a Sim's `.anim` file from the FAR3 archives under
`avatardata/animations`. An animation is a set of motions, one per bone it moves, each a run of
frames at 30 a second that index into shared tables of translations and rotations. A motion can
carry timed properties: events, keyed by their time in milliseconds (signed: some are negative), such as `xevt` (an event the
animating routine hears), `sound`, `lefthand`, and `righthand`.

```swift
let animation = try Animation(bytes: data)
animation.frameCount                 // the longest motion's frames
animation.timedProperties.map(\.time) // [500, 800]
animation.timedProperties[0].properties["xevt"]  // "1"
```

The file is big-endian, but its floats are little-endian.
Translations and rotations are kept as the file stores them; turning them into a renderer's
coordinates is the renderer's job. Every count is checked against the bytes that remain.

Most animations write each property list as a count of sets, each a count of pairs. Five of TSO's
(`a2o-test-animation2` to `6`, which the DJ booth, jukebox, stereos, and speakers name) write a
single set with no set count. Simburbia reads a file that doesn't fit the
usual layout again in that one, and keeps it only if it then ends exactly at the end of the data;
`propertyLayout` says which layout it took (DIFF-35). All 5,454 animations on 1.1097.1.0, 5,249 on
the base game, and 5,240 on the beta decode (checked 2026-11-20).

A typical animation (50 KB) decodes in about 1.4 ms in a release build; the largest is 900 KB.

## Scanning and comparing installs

`InstallScanner` opens every container under a folder, reads every entry, and parses every
supported chunk, collecting failures instead of stopping:

```swift
let report = try InstallScanner().scan(directory: install)
print(report.containerCounts[.far1] ?? 0, report.entriesRead, report.failures.count)
```

Chunks that fail to parse but that nothing in their file refers to (an old `TTAB` no `OBJD` points
at) are listed separately in `unreferencedChunkFailures`. The game never loads them.

`InstallComparison` compares two installs file by file, then entry by entry inside containers that
differ, then chunk by chunk inside IFFs. It records names, sizes, chunk IDs, and object GUIDs, never
contents:

```swift
let differences = try InstallComparison().compare(production, beta)
for file in differences.changedFiles {
    for entry in file.entries where entry.change == .onlyInSecond {
        print(file.path, entry.name)                 // e.g. "objectdata/objects/objiff.far chairs.iff: TRCN #4097"
    }
}
```

`tsofiles-check` puts both to work; see [tools.md](tools.md).

## Lower-level pieces

- `ByteReader` reads little- or big-endian integers and strings, checking the length before every
  read and throwing `EndOfDataError` instead of reading out of bounds.
- `FieldEncodedReader` reads the bit-packed fields of `TTAB` versions 9 and 10.
- `ASCII` decodes names as .NET's `Encoding.ASCII` does (bytes above 0x7F become `?`), so names
  look up the same whatever their bytes.
- `DirectoryListing` lists files in sorted order, so results never depend on the file system's own
  order.
