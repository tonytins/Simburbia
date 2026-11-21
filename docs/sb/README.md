# Simburbia

This is Simburbia's Swift code, in packages at the repository root. At its core are libraries that
reimplement the parts of The Sims Online that don't depend on a game engine: the file formats, the
content system, and the SimAntics virtual machine that runs object behavior. Around them are
Simburbia's own client, `simburbia`, which shows a lot running, and the tools that check the
libraries against real installs. It all works on New & Improved (1.1097.1.0) and on older copies
of the game, the base game and a beta, whose files differ.

This folder describes how the code behaves today. For what's finished and the evidence for it, see
the [scorecard](../scorecard.md); for what comes next, the [roadmap](../roadmap.md). Unfamiliar
terms are explained in the [docs index](../README.md#terms).

These pages cover the libraries, the client, and the tools. [SimsScript](../../SimsScript/README.md),
the scripting language in progress, and [`sso-oracle`](../../ScriptOracle/README.md) have READMEs
of their own.

## The packages

Each package is an independent Swift package at the repository root. Dependencies
point one way:

```text
TSOFiles ──▶ TSOContent ──▶ SimAntics ──▶ SimsScript ──▶ ScriptOracle (sso-oracle)
                                │
                                ├──▶ SBOracle (sb-oracle)
                                └──▶ SBClient (simburbia) ◀── Hudini ◀── raylib-swift

TSOFiles and TSOContent ──▶ TSOFilesCheck (tsofiles-check)
```

TSOContent's `TSOConfig` product reads the installs through swift-configuration, for the tools and
the client; the libraries themselves take no configuration library.

| Package | What it does | Page |
| --- | --- | --- |
| TSOFiles | Reads the game's containers (FAR1, FAR3, DBPF, IFF), IFF chunks, tables, and PIFF patches | [files.md](files.md) |
| TSOContent | Finds an install and loads objects, globals, and patches from it | [content.md](content.md) |
| SimAntics | Runs object behavior: the VM, entities, threads, primitives, and variables | [simantics.md](simantics.md) |
| SimAntics (lot model) | Positions, the tile index, walls, floors, rooms, and blueprints | [lot.md](lot.md) |
| SimAntics (blueprints, planned) | TSO's lot format, read and written as Maxis intended, and Simburbia's extensions | [blueprints.md](blueprints.md) |
| SimsScript | Routines as readable listings and text assembly, and a small compiler; `simsscript list` | [tools.md](tools.md#simsscript) |
| Hudini (the owner's library, not in this repository) | The client's windows and controls on raylib-swift; it also reads TSO's `.uis` screens and `.cst` text | [client.md](client.md) |
| Client | `simburbia`: shows a lot running, or runs it headless and logs it | [client.md](client.md) |
| TSOFilesCheck | `tsofiles-check`, which opens everything in each install and compares two | [tools.md](tools.md) |
| SBOracle | `sb-oracle`: the randomized study, which samples objects onto lots and checks how they run, and the content census | [tools.md](tools.md#sb-oracle) |
| ScriptOracle | `sso-oracle`, which runs SimsScript scenarios on the VM and checks the values they leave | [tools.md](tools.md#sso-oracle) |

## How the code behaves

A few rules hold everywhere. Knowing them makes each package easier to follow.

- **A new implementation.** Simburbia is written from the game's files, public knowledge, and
  earlier open-source projects, FreeSO above all, which did much of the heavy lifting. The docs
  describe what Simburbia does in its own terms; the scorecard lists where it deliberately
  differs from FreeSO.
- **The libraries have no engine.** Only the client draws, takes input, or logs, and its drawing
  reads the simulation without changing it. The libraries decode to plain values and report through
  errors, so they test and run anywhere, the client's headless runs included.
- **Errors are values.** Readers throw typed errors (`FAR1Error`, `IFFChunkError`,
  `ContentError`, `SimAnticsError`) instead of crashing. Where a file would lead a reader past the
  end of its data, Simburbia throws. Nothing in the libraries uses `try!`, `as!`, or `fatalError`.
- **Values, not singletons.** Archives and chunks are immutable `Sendable` values, often over
  memory-mapped bytes. A `GameContent` is created and passed in, so tests and tools can load several installs side by side.
- **Degrade gracefully on older installs.** Where the base game's or the beta's files differ from
  New & Improved's, Simburbia skips what doesn't fit, reports it, and keeps going. For example,
  a PIFF patch that doesn't fit an object is skipped, not fatal. [`install-differences.md`](../results/install-differences.md)
  records how the production and beta installs differ.
- **Deterministic simulation.** SimAntics uses wrapping 16-bit arithmetic, never iterates a
  `Dictionary` or `Set` where order matters, and keeps entities in object ID order. Two VMs given
  the same lot and seed stay in step, which lockstep multiplayer needs.

## Trying it

Every package builds and tests on its own:

```sh
swift test --package-path SimAntics
```

You need Swift 6, and the X11 and GL headers on Linux for the client. You don't need the game:
without it, the tests use [`MockInstall`](../../MockInstall/README.md), a tiny
made-up install, and the tests that need the real game are skipped. To run those too, set these
environment variables:

| Variable | Points at |
| --- | --- |
| `TSO_GAME_DIR` | The main install's `TSOClient` folder: New & Improved (1.1097.1.0 on the owner's machine) |
| `TSO_CLASSIC_DIR` | An older production copy's `TSOClient` folder, such as the 2002 one (1.145.1.0) |
| `TSO_BETA_DIR` | The beta's `TSOClient` folder |
| `SB_USER_DIR` | Simburbia's user folder, whose `Mods` folder holds a player's custom objects and patches (default: the OS's usual Simburbia folder) |
| `FSO_CONTENT_DIR` | A FreeSO-style `Content` folder, for its patches and custom objects (default: `Content` beside the executable, else none) |

The snippets on these pages use the public API. Where a snippet needs an install, it assumes
`TSO_GAME_DIR` points at one.

## Compatibility

Simburbia reads TSO's own files, from the beta (1.3.2.121) through New & Improved (1.1097.1.0). It
also reads content made for FreeSO: its content folder's patches and custom objects, and lots
saved in its blueprint dialect (see [blueprints.md](blueprints.md)). It doesn't follow FreeSO's
later releases, so content made for the FreeSO Archive may not load.
