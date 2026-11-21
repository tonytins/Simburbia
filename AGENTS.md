# Project Guidelines

Simburbia rebuilds the engine of [The Sims Online](https://en.wikipedia.org/wiki/The_Sims_Online)
(TSO) in Swift, so the game can be played again. It's a new implementation with a client and a
lot server of its own, meant for small groups and LAN play. It reads the game's own files from an
install you supply; the repository holds none of them.

The goals:

- **Play The Sims Online again**. Simburbia, playable with friends, is the end goal.
- **Explain the codebase** in `docs/sb/`, so others can tinker with it and run their own server
  or client.
- **Go past the original:** SimAntics extensions, scripting, and older games' data such as The
  Sims 1.

### Small and LAN first

Simburbia is built for small, self-hosted servers: LAN and Internet play, co-operative and
competitive, for about 1 to 50 players, and at most 255, while keeping TSO's core MMO features.
It should scale up to a large server when someone needs one, but it doesn't require one from the
start. Design references include [Luanti](https://github.com/luanti-org),
[Space Station 14](https://github.com/space-wizards), and [OpenTTD](https://github.com/OpenTTD/OpenTTD).

## Project Structure

Each package is independent, at the repository root. Dependencies point one way: TSOFiles, then
TSOContent, then SimAntics, then SimsScript, with the client and tools on top.

| Path | Contents |
| --- | --- |
| `TSOFiles/` | File format readers: FAR, DBPF, IFF and its chunks, patches, tables, images |
| `TSOFilesC/` | A C ABI over TSOFiles |
| `TSOFilesCheck/` | `tsofiles-check`, which scans a real install and reports what it can't read |
| `TSOContent/` | The content system and the list of installs (`InstallKind`); its `TSOConfig` product reads them through swift-configuration |
| `SimAntics/` | The VM that runs object behavior, and the lot model |
| `SimsScript/` | BHAV text assembly and an LSL-like compiler (proof of concept) |
| `SBClient/` | `simburbia`, the client, which loads, runs, and shows a lot |
| `SBOracle/` | `sb-oracle`: the randomized study and the content census |
| `ScriptOracle/` | `sso-oracle`: small experiments written in SimsScript, run on the VM |
| `MockInstall/` | A tiny made-up TSO install for tests and CI |
| `Interface/` | The client's top bar and windows, in Hudini's UIScript XML |
| `Lots/` | The owner's lots as blueprint XML: `tonys-lot.xml` (a recreation of their original TSO lot) and `community-lot.xml` (a lot for group events) |
| `Tuning/` | Simburbia's default global tuning (`tuning.xml`), laid under an install's `tuning.dat` |
| `packaging/` | The scripts that build the client into packages players download |
| `scripts/` | `extract.sh`, which unpacks TSO's installer cabinets into a game folder |
| `docs/` | The documentation and the plan (see below) |
| `.agents/skills/` | The `swift-guidelines`, `raylib-swift`, and `c-guidelines` skills |

In `docs/`:

- `roadmap.md`: milestones, the alpha gate, and the owner's decisions.
- `scorecard.md`: status per feature with evidence. It wins over the roadmap.
- `sb/`: how Simburbia behaves, package by package.
- `results/`: how the installs differ, and what that means for Simburbia.
- `simantics/`: the SimAntics Wiki in Markdown (CC BY-SA 3.0).

Build output (`.build/`, `dist/`) is never committed.

## Build and Test

```sh
for package in TSOFiles TSOContent; do   # the packages you changed and those that depend on them (CI builds them all)
    swift build -j 2 --package-path "$package" && swift test -j 2 --package-path "$package"
done
grep -rnE 'try!|as!|fatalError|precondition|preconditionFailure' */Sources  # must print nothing
swift run --package-path TSOFilesCheck -c release tsofiles-check            # scans every TSO_*_DIR install that's set
swift run --package-path SBClient -c release simburbia --headless --ticks 9000    # run a lot a game hour with no window; read the log
swift run --package-path SBClient -c release simburbia --headless --check         # the same over a game day, checking the lot's rules
swift run --package-path SBOracle -c release sb-oracle study --out /tmp/study     # sample lots for five minutes; needs TSO_GAME_DIR
swift run --package-path ScriptOracle sso-oracle run                              # the SimsScript scenarios, on MockInstall unless TSO_GAME_DIR is set
packaging/linux/package.sh                                                   # the client as an AppImage and a .tar.gz, in dist/release
```

- Build and test only the packages you changed and those that depend on them, one package at a
  time (`-j 2`). Building everything at once has run the owner's machine out of memory. Don't
  clear `.build` folders without need.
- Tests don't need the game. They run on `MockInstall` and skip what needs a real install.
- Run the program when a change affects what it does: passing tests don't show that a lot runs
  or a window draws. `--headless` runs a game day in seconds.
- Building the client on Linux needs the X11 and GL headers (`libx11-dev` and friends, as in CI).

### The study and the scenarios

`sb-oracle study` samples the install's objects onto lots by seed, runs each lot a game day, and
checks the lot's rules every game minute. It runs each lot twice. A broken rule, or two runs that
differ, is a finding, halved to the fewest objects that still show it. `sb-oracle census` counts
what the buy catalog's code reaches, without running it. `sso-oracle` runs small objects written
in SimsScript, each with the values it should leave.

- **Prefer seeded, sampled checks** to hand-written cases. Every lot repeats from its seed.
- **Inconclusive isn't clean**. A lot the study couldn't measure is counted by reason, never as
  a pass.

## Golden Rules

Two rules are strict: never crash, and determinism. Use judgment for the rest.

### Design Process

- **Iterate**. A first design or name is a draft. Rebuild clumsy parts as understanding improves.
- **Ask when a decision is open**, and explain the reasoning behind what you suggest. A request
  that starts a discussion ("discuss", "brainstorm", a question) gets an answer, not code.
- **Keep it simple**. The simplest approach that matches what the game does wins.
- **Say what you're unsure of**: assumptions, unverified behavior, and what needs play-testing.

### Learn from Available Sources

TSO's servers shut down long ago, so how the game worked has to be pieced together from what's
public: [FreeSO](https://github.com/riperiperi/FreeSO),
[FreeSims](https://github.com/francot514/FreeSims),
[plumbob-engine](https://github.com/testinglol/plumbob-engine) (a The Sims 1 engine; its comments
cite addresses in TS1's executable, so verify what it says rather than copying it), the
[SimAntics Wiki](http://simantics.wikidot.com/wiki:introduction-to-simantics) (copied in
`docs/simantics/`), [SimsWiki](https://simswiki.info/wiki.php?title=Main_Page) (The Sims 2's AI
extends SimAntics), [Don Hopkins](https://github.com/SimHacker),
[SimObliterator Suite](https://github.com/DnfJeff/SimObliterator_Suite),
[TS1 Compiler](https://github.com/mixiate/ts1-compiler),
[TS1 Renderer](https://github.com/mixiate/ts1-renderer) ([IO](https://github.com/mixiate/ts1-blender-io)),
[TheSimsOpenTechDoc](https://github.com/DnfJeff/TheSimsOpenTechDoc), and
[The Modding Guide](https://cyndersanity.github.io/sims-legacy-mod-guide/index.html).

Treat them as leads to verify against the game's files and Simburbia's own tests, not as an
answer key. They were often wrong.

**For gameplay, check [TSO Mania](https://www.tsomania.net/)**, the players' guide to TSO in its
heyday: property categories, skills, jobs, pets, objects, and how each felt to play. Code tells
you how something works; TSO Mania tells you how it played. Search it whenever a change touches
gameplay or balance, and especially where the installs disagree or lack data.

- **Cite it** where it informs a number or a behavior (a doc comment, the scorecard, a tuning
  file's comments), as the default tuning cites its category difficulties.
- **Mind the era.** Its guides span TSO, New & Improved, EA-Land, and FreeSO. Say which a claim
  is from when it matters, and mark it **Unverified** when the page doesn't.
- **It describes, it doesn't specify.** "Easy" or "50% overfill" is a target to match, not a
  value to copy. Simburbia's own numbers meet it.

### Never Crash (Outranks Feature Work)

Simburbia reads files nobody controls: original installs, patched objects, user mods, and lot
saves. A truncated archive, a corrupt chunk, or a hostile save must produce an error the caller
can act on, never a trap. Fix a crash before building on top of it.

- **Library code never traps**. No force unwraps, `try!`, `as!`, implicitly unwrapped optionals,
  `fatalError`, `precondition`, or `assert`-based control flow in `Sources/`. Throw a typed error.
  Unfinished features throw rather than trap.
- **No silent fallbacks for bad data**. Report invalid input; don't quietly replace it. The
  exception is a tolerance real files rely on: keep it and say so in the doc comment.
- **File-derived numbers are hostile**. Check every size, offset, and count against the bytes
  that remain before slicing or allocating, and watch for overflow.
- **Bound what data can drive:** decompression output, nested containers, call depth, graph
  walks, and BHAV execution.
- **Failures change nothing**. A reader that throws returns nothing partial.
- **Contain failures**. One bad file or entry doesn't stop a scan or a content load, and an
  error in one entity's thread stays in that entity.
- **Prove it**. Every crash or bad-input fix comes with a regression test that failed before the
  fix.
- **Generated code is a temporary exception**. Force unwraps and asserts are byproducts of a code
  generator, not licenses. Fix each case by refactoring the output.

### Forward Compatibility

Simburbia was first built against the TSO beta (1.3.2.121), then the 2002 retail copy
(1.145.1.0), and then the Mystic Tree update (1.1097.1.0). It will still meet data newer than any
of them: FreeSO-style content folders and patches, mods, and its own later saves.

- **Port the versions real files use**. Add the rest when a file or mod needs them.
- **Unknown isn't corrupt**. Data newer than a reader knows is skipped or kept raw and reported
  where the format allows. Data that is actually broken is still an error.
- **Keep what you can when rewriting a file**. If a rewrite drops something it couldn't read, say
  so.
- **Older Simburbia reads newer saves (strict)**. Version Simburbia's own formats. Add new data
  as parts an older build can skip. A change it can't skip takes a new major version, which older
  builds refuse with a clear message.

### Library Rules

These apply to the Simburbia libraries. Tools (`tsofiles-check`, `sb-oracle`, `sso-oracle`) may
print, and are freer.

- **Engine-free**. No rendering, audio playback, UI, logging, or printing in library targets.
  Decode to plain values and report through errors and results.
- **Deterministic (strict)**. SimAntics must give the same results on every machine for lockstep
  play: wrap 16-bit arithmetic (`&+`, `&-`, `&*`), never iterate a `Dictionary` or `Set` in VM
  logic, process entities in object ID order, take randomness only from the VM's seed, never read
  the clock, and review any floating point that feeds simulation state.
- **Values, not singletons**. Pass dependencies in rather than reaching for a global.
- **Simburbia in its own terms**. Docs and comments say what Simburbia does and why, from the
  game's files, its tests, and how TSO played. Name FreeSO or another engine only where it truly
  matters: a format Simburbia reads that FreeSO defined (PIFF patches, the content folder,
  FreeSO's blueprint dialect), compatibility with content made for it, or a deliberate difference
  the scorecard lists. Don't attribute every mechanism to the engine it was first read in.
- **Independent packages**. Each package builds and tests on its own, and dependencies point one
  way. Libraries don't declare `platforms:`.
- **Dependencies as needed**. Take one when it earns its place, and say why.
- **No EA data in the repository (strict)**. Tests build synthetic files in code or use
  `MockInstall`. Results files hold names, sizes, chunk IDs, and GUIDs only. Document formats and
  how the code reads them, but never paste or reconstruct game data.
- **Test what matters**, with Swift Testing (`import Testing`), never XCTest: crash fixes, and
  quirks real content relies on.
- **Say breaking changes out loud**. Renaming public API, or adding a case to a public enum,
  breaks callers in the other packages: update them and call it out.
- **Measure before optimizing,** with a release build against a real install.
- **Follow the `swift-guidelines` skill** (and `c-guidelines` for `TSOFilesC`) as a guide. Match
  the surrounding code when they disagree.

### The Client

- **TSO's interface**. Simburbia's windows and controls are its take on TSO's `.uis` screens.
  They come from [Hudini](https://github.com/tonytins/Hudini), the owner's interface library;
  its `hudini-demo` shows them on their own.
- **Seeing it**. `simburbia --screenshot <file.png>` draws a few frames in a hidden window and
  saves the last, for checking a change without anyone at the screen; `--loading-screenshot` and
  `--login-screenshot` save the loading screen or the login window instead. Without `--lot` the
  client opens on the login window; `--lot` goes straight to a lot.
- **Use the `raylib-swift` skill** for any work that imports Raylib. These rules win where the
  two disagree.
- **The libraries never import raylib**. Rendering reads simulation state and never writes it.
  If something can't be tested without a window, it belongs in the client.
- **raylib's examples are the reference**. Read the one closest to what you're writing. A frame
  is `BeginDrawing`, the drawing, `EndDrawing`; textures load after `InitWindow` and unload before
  `CloseWindow`, never inside the frame loop.
- **Check visual changes off the owner's desktop**: `simburbia --screenshot` on a private
  display, never driving their real one.

## Working with the Owner

- One person maintains Simburbia. Make review easy: say what you did, what you skipped, and every
  claim you couldn't verify. Call out anything that breaks compatibility (saves and lots, reading
  the original files, or an older Simburbia reading newer data), new dependencies, and deliberate
  differences from how the original game behaved.
- Commit locally when a piece of work is ready, one commit per piece rather than per step, and
  wait for review. Never push, amend, or rewrite history unless asked.
- The working tree often holds the owner's own unfinished edits. Leave files you didn't change
  alone, and stage only your own work.
- Keep private notes and anything in `*.local` out of tracked files, and don't mention them there.

## Before You Finish

- Every package you touched, and every package that depends on it, builds and passes its tests.
  Leave the rest to CI. If you touched a reader and an install is set, run the scan.
- Look over your diff for force unwraps by eye; the search can't tell `!` from `!=`.
- When a step finishes, update the [scorecard](docs/scorecard.md) and the
  [roadmap](docs/roadmap.md).
- Update this file if the layout changes. Markdown in `docs/`: plain short sentences, relative
  links, lowercase kebab-case file names.

Keep every package building and its tests green at every step, since sessions can end abruptly.

## Personal Configuration

Keep personal preferences and machine-specific guidance in git-ignored `*.local` files or
directories (such as `AGENTS.local.md`), rather than in shared project instructions. Check for
relevant local guidance before environment-specific work. You can create or update these files
for details such as:

- Coding preferences
- Local build and development environment
- Personal shortcuts or workflows

See [REVIEW.md](REVIEW.md) for the project's review checklist.
