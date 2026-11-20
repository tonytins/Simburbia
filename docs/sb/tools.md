# Tools

## tsofiles-check

`tsofiles-check` (the TSOFilesCheck package) is the first test of the file readers against a real
install. It opens every FAR1, FAR3, DBPF, and IFF file, reads every archive entry, and parses every
supported chunk, then reports counts and failures.

```sh
swift run --package-path TSOFilesCheck -c release tsofiles-check
```

### Which installs it checks

- **With a folder argument,** it checks that folder.
- **Without one,** it checks every install named by `TSO_GAME_DIR` (1.1097.1.0 since 2026-10-28;
  the base game before that), `TSO_CLASSIC_DIR` (the base game), and `TSO_BETA_DIR` (the 2002
  beta), in that order, as TSOContent's `InstallKind` lists them, read through `TSOConfig`.
  `--install game`, `classic`, or `beta` picks one, and can be repeated. Two variables naming the
  same folder check it once. Each install's header shows the version its `version` file records.
- **The differences file** is written only when exactly two installs are checked, such as
  `--install classic --install beta`.

Each folder must contain an `objectdata` folder, in any letter case. One that doesn't is reported
and skipped, and the other install is still checked.

### What it prints

For each install, a header and a summary:

```text
== TSO_GAME_DIR: /home/user/Applications/tso/TSOClient
FAR1: 13 files
FAR3: 47 files
DBPF: 7 files
IFF: 29 files
entries read: 84912 (IFFs inside archives: 1578)
chunks parsed: 50798 (BCON 784, BHAV 15906, ..., anim 5454, ...)
other files: 1590
failures: 0
unreferenced chunks that don't parse (the game never loads them): 5
```

Every `.anim` entry in a FAR3 archive is decoded too, counted as `anim`. Failures name the file,
the archive entry, and the chunk (`objiff.far: chairs.iff: TTAB #128`).
`--max-failures N` limits how many are listed (all are counted), and `--headers-only` opens archives
without reading entries. `--far1-variant a` reads The Sims 1's FAR layout.

Exit codes: 0 when everything reads, 1 when anything fails, 2 when a folder isn't an install or
can't be listed.

### The differences report, once

The first time it checks two or more installs, it compares each with the next newer one (the
beta, then the classic copy, then the game) and writes
[`docs/results/install-differences.md`](../results/install-differences.md) (or the path in `--differences`), one
section per step. After that it only says the file exists. Delete the file to compare again.

The report lists files only in one install, then, for each file that differs:

- **IFFs and archives of IFFs** (such as `objiff.far`): one row per IFF, with the chunks only in
  each install and those that changed, grouped by type, and the GUIDs of changed objects.
- **Other archives** (avatars, audio): counts of entries added, removed, and changed.

It holds names, sizes, chunk IDs, and GUIDs, never game data, so it can be committed. It's the
reference for backwards compatibility: when something behaves differently on the beta, check
there what the files change before calling it a bug in Simburbia.

## sb-oracle

`sb-oracle` (the SBOracle package) checks Simburbia against a real install, without a window. It
has two commands:

| Command | What it does |
| --- | --- |
| `study` | The randomized study (below): sampled objects on lots, a game day each, for a time budget |
| `census` | What the buy-mode catalog and given lots reach: primitives, operand shapes, and variable scopes, without a VM |

Both take `--game` (default: `TSO_GAME_DIR`) and `--content`, a FreeSO-style content folder for
patches and custom objects (default: `FSO_CONTENT_DIR`, else none).

### The randomized study

`sb-oracle study` asks how objects behave over game time, without running every object of an
install. Until its time budget runs out (`--minutes`, five by default), it builds lots: about
thirty objects Simburbia loads, picked by a seed with those its ledger hasn't seen first, on a grid
of a floor plan, each facing a direction the seed picks. Among the untested, and then among the
rest, the pick is weighted toward code nothing has run yet (below). Up to `--sims` visitor Sims (2
by default, at most TSO's 18 visitors) join each lot, with no owner on it, as lots stay open
without their owner in Simburbia. The floor plans (`--floor-plan`, repeatable) are lots emptied of
their own objects, and the seed picks one per lot. The default is an empty lot, 77 tiles a side;
TSO's own job lots make good extra plans, so objects meet real walls, counters, and doors. Each
lot runs a game day, with a digest every game hour:

1. An object that reaches something Simburbia doesn't support yet is recorded as such and set
   aside, and the lot runs again without it. If the object isn't one the lot names, it's mapped
   to the multi-tile object it belongs to, or found by halving the lot.
2. The lot's rules (below) are checked every game minute, and the lot runs a second time, which
   must give the same digests. A broken rule (`broken`) or a run that doesn't repeat
   (`unrepeatable`) is a finding: the lot is halved, keeping every object's tile and facing, to
   the fewest objects that still show it.
3. A lot with neither is `clean`. A lot that can't be measured (every object set aside, or an
   error loading it) is `inconclusive`, counted by reason, never as clean.

The records go to `--out/study.tsv`, and the study ends with a summary of them. The ledger
(`--ledger`, such as `docs/results/sb-study-<install>.tsv`) keeps each object's latest result, so
each run samples what the last ones didn't. The seed defaults to the time, and is printed.

```sh
sb-oracle study --game "$TSO_GAME_DIR" --out /tmp/study --minutes 5
```

#### Coverage

While Simburbia runs a lot it records every instruction its threads reach (`VM.recordsCoverage`,
read back as `InstructionSite`s: the file, the routine, the index). The census works out the
routines each candidate's own behavior can reach (`Census.reach`, leaving interactions out until
Sims use objects in phase D), and each object's weight is 1 plus the instructions in its reach no
run has reached, shared out over the lots it has been on. `--coverage-file` carries what's been
reached between runs; keep it with the run's output, since it's large and changes every run.
`--unweighted` samples as before, to compare the two.

On 1.1097.1.0 from seed 100, four minutes each (2026-11-10, when the study also ran each lot on
FreeSO): weighted, 22 lots and 704 objects
tried reached 10,981 of the 50,855 instructions the candidates' own behavior can reach (12,975
in all); unweighted, 29 lots and 869 objects reached 10,089 (13,521 in all). Weighting reaches
more of the objects' own code with fewer objects, but its heavier objects run slower, so it tries
fewer and reaches slightly less shared global code. A first version that let weights override
"untested first", and counted interactions, reached less on both counts (9,692 in all).

#### Visitor Sims

Before the first lot, a Sim made from `--sim-template` (the template person, `7FD96B54`, or the
mock Sim on MockInstall) must run a game day on an empty floor plan; otherwise no Sims
join this run, and the study says why. On 1.1097.1.0 the template person reaches Push Interaction
(phase D), so Sims wait until then there. A Sim that reaches something unsupported during a lot
leaves it, and the objects carry on. Halving a broken rule or a disagreement takes Sims out as
well as objects, and names what's left by GUID and Sim count.

### The lot's rules

`VM.brokenRules()` in SimAntics lists what a running lot's state breaks of rules it should always
keep (`LotRule`), in object ID order. It reads the state and changes nothing, and it reports
rather than throws, so checking never stops a lot. The rules:

| Rule | What it says |
| --- | --- |
| motive range | A Sim's motives stay within −100 to 200. TSO let a motive go past 100 (the owner recalls up to 200); Simburbia keeps them within −100 to 100 for now. |
| online job ID | A Sim's online job ID stays at 4 or below, the most its setter takes. |
| on the lot | An object in the world is on a tile of the lot, on level 1 to 5. |
| object index | The object ID index finds each entity, and no deleted entity is still on the lot. |
| tile index | An object in the world is listed on the tile it's on. |
| slots | Containment points both ways: an object's container holds it in the slot it names, and what a slot holds names that container. |
| with its container | An object in a slot is where its container is. |
| multi-tile group | A group lists each of its parts, and has a lead. |

Objects out of the world are allowed, including a Sim left out when tile 3,3 is taken at join.
The study checks the rules every game minute, as does `simburbia --headless --check`. Rules wait
for what they check: "no Sim inside an obstacle" comes with routing (phase E).

### The content census

`sb-oracle census` measures the content Simburbia has to handle before running anything. It
starts from every buyable entry of `packingslips/catalog.xml`, takes each object's `OBJD`
behavior fields, `OBJf` entry points, and `TTAB` interactions, then follows subroutine calls
and `run_tree_by_name` through the object's file, its semi-global, and the global. It counts:

- **primitives:** how often each opcode below 256 appears, and whether Simburbia runs it (`runs`),
  knows it but doesn't run it yet (`pending`), or doesn't know it (`unknown`). The summary counts
  `pending` and `unknown` instructions.
- **operand shapes:** for each primitive, the scopes of the variables its operand names, in field
  order (`expression: local,temps`), or `-` for an operand that names none. A flag that makes a
  variable unused doesn't hide it: the file still holds it, and the flag can change.
- **variable scopes:** every variable in those operands, by scope (`local`, `temps`, `tuning`,
  and so on).

The `catalog` column counts every buyable object. Each `--lot` column counts only the objects
that lot places and the catalog lists, so it says what that lot exercises. By default the lots
are `Lots/tonys-lot.xml` (the realistic case) and `Lots/community-lot.xml`; `--lot` replaces them,
and `--catalog-only` leaves them out. A routine shared by many objects counts once per column,
while its instructions are still followed from each object that reaches it. No VM runs, so a real
install takes seconds.

The output is tab-separated: comments, a header (`kind`, `key`, and one column per source), then
summary, primitive, shape, and scope rows, and `# failure` lines for objects that didn't load. A
routine is resolved exactly as the VM resolves it: IDs below 4096 are global, 4096 to 8191 are
the object's, and 8192 and up are its semi-global's. `run_tree_by_name` is resolved in the
calling object's own file and semi-global, which is where the VM looks when the object is its own
stack object; a tree that runs on a different stack object may reach more.

```sh
sb-oracle census --game "$TSO_GAME_DIR"
sb-oracle census --game "$TSO_GAME_DIR" --lot Lots/community-lot.xml
```


## sso-oracle

`sso-oracle` (`ScriptOracle`) runs experiments written in SimsScript. A scenario is a
small object with a header saying how long to run it and which object variables it should leave
(`@ticks`, `@expect`); see [its README](../../ScriptOracle/README.md).

- `check` compiles each scenario.
- `run` runs each on Simburbia's VM, alone on an empty lot, and checks its expectations.
- `build DIR` writes each compiled object, and `scenarios.tsv`, as standalone objects.

```sh
swift run --package-path ScriptOracle sso-oracle run     # on MockInstall unless TSO_GAME_DIR is set, as CI runs it
```

A scenario pins down one behavior in a form anyone can read. The first two cover SimAntics'
16-bit arithmetic.

## simsscript

`simsscript list OBJECT` (`SimsScript`) prints an object's routines as SimsScript's
`Listing` writes them: one line per instruction, with routines, parameters, locals, attributes,
and constants named from the object's files, its semi-global, and the global file, and ported
primitives' operands in words. See [SimsScript's README](../../SimsScript/README.md).
Primitives Simburbia doesn't run yet still read in words: their operands are decoded.
