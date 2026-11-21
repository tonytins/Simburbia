# Documentation

Simburbia is rebuilding the engine of *The Sims Online* in Swift, so the game can be played again:
small and LAN-first. Its Swift code is in the packages at the repository root. The libraries read
the game's files, load its content, and run its object behavior; the client, `simburbia`, shows a
lot running on them, or runs one with no window and logs what happens.

This folder also holds a copy of the community SimAntics reference, which explains the scripting
language the game's objects are written in.

New here? Read [Terms](#terms) below, then pick a starting point. The rules for changing the code
are in [`AGENTS.md`](../AGENTS.md); they apply to people and AI assistants alike.

## Where to start

- **To understand how Simburbia's code behaves:** [sb/README.md](sb/README.md).
- **To run the client:** [sb/client.md](sb/client.md).
- **To see where Simburbia stands:** the [scorecard](scorecard.md) for what's done and the evidence
  for it, the [roadmap](roadmap.md) for what comes next, and the [results](results/README.md) for
  what it finds on real copies of the game.

## Terms

| Term                        | Meaning                                                                                                                                                                                                                                              |
| --------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| *The Sims Online* (TSO)     | Maxis and EA's online Sims game, released in 2002 and renamed *EA-Land* before it closed in 2008                                                                                                                                                     |
| FreeSO                      | An open-source C# reimplementation of TSO, built on MonoGame, whose servers shut down in 2024. Its content folder, patches, and lots are formats Simburbia reads |
| Simburbia                   | TSO playable again, small and LAN-first: the Swift libraries that reimplement the game's engine-independent parts, the client, and the tools |
| SB                          | Short for Simburbia, and the prefix of its own packages and tools (`SBOracle`, `sb-oracle`); TSO's own formats keep the `TSO` prefix |
| `simburbia`                     | Simburbia's client. It shows a lot running; `--headless` runs one with no window and logs it                                                                                                                                                             |
| Install                     | A copy of TSO's game files on disk (a `TSOClient` folder). The repository holds none; tests that need one read the `TSO_GAME_DIR` environment variable, or use [`MockInstall`](../MockInstall/README.md), a tiny made-up install |
| SimAntics                   | The virtual machine that runs object behavior in The Sims games                                                                                                                                                                                      |
| Routine (`BHAV`), primitive | A routine is a small program an object runs; each of its instructions is either a call to another routine or a primitive, one of the VM's built-in operations                                                                                        |
| IFF, chunk                  | Maxis's resource file format. An object's IFF holds chunks: its definition (`OBJD`), routines (`BHAV`), strings (`STR#`), sprites, and so on                                                                                                         |
| FAR, DBPF                   | Archive formats that bundle many files, such as all the objects' IFFs                                                                                                                                                                                |
| PIFF                        | FreeSO's patch format, which fixes objects in place. Simburbia reads FreeSO's patches and a player's own |
| GUID                        | The 32-bit number that identifies an object type                                                                                                                                                                                                     |
| Semi-global                 | A library of routines shared by a family of objects, such as all chairs                                                                                                                                                                              |
| Lot, tick                   | A property Sims live on and objects are placed on; one step of the simulation                                                                                                                                                                        |
| Oracle                      | Simburbia's checking tools: `sb-oracle` runs the randomized study and the content census, and `sso-oracle` runs SimsScript scenarios |
| MOMI                        | TSO's in-universe name for its game masters; in `simburbia`, the window of system messages                                                                                                                                                               |
| Beta                        | An early retail copy (v1.3.2.121) that a select number people could get. Players at this time got founder's badge on their profile.                                                                                                                  |
| Base Game                   | v1.145.1.0, the earliest known retail copy available online.                                                                                                                                                                                         |
| New & Improved (N&I)        | An October 2003 re-release, likely at around 1.1097.1.0, that brought with it pets, jobs, and more. (Anything added since then, but before EA-Land, is known as New & Improved.)                                                                     |
| Betaville                   | A separate build of TSO, reached through the patcher, which brought settings such as free will (owner's account) |

- **To look up what a SimAntics primitive, scope, or data field means:**
  [simantics/README.md](simantics/README.md).

## Outline

### [roadmap.md](roadmap.md): the Simburbia plan

Scope, the alpha gate (the end-to-end jobs Simburbia must do before alpha), current focus,
milestones (named after The Sims Online's unused cities) with estimates and progress, the ranked
next milestones, the critical path, decisions for the maintainer, risks, and the revision history.

### [scorecard.md](scorecard.md): Simburbia status with evidence

One row per feature, each `done`, `partial`, or `missing`, with the code or test that proves it:
file formats, content, SimAntics, fidelity to the original game, determinism, reliability, tests
and tooling, and platforms. It also lists deliberate differences from earlier implementations and
open bugs. When the
scorecard and the roadmap disagree, the scorecard wins.

### [sb/](sb/README.md): how Simburbia works

How the Swift libraries, the client, and the tools behave today, with code examples. SimsScript
and `sso-oracle` have READMEs of their own ([SimsScript](../SimsScript/README.md),
[sso-oracle](../ScriptOracle/README.md)).

| Page | Covers |
| --- | --- |
| [README.md](sb/README.md) | The packages, how they depend on each other, and the rules every package follows |
| [files.md](sb/files.md) | TSOFiles: containers, IFF chunks, patches, tables, scanning and comparing installs |
| [content.md](sb/content.md) | TSOContent: finding an install, loading objects, globals, and patches |
| [simantics.md](sb/simantics.md) | SimAntics: the VM, entities, threads, variables, primitives, scheduling |
| [lot.md](sb/lot.md) | The lot model: positions, the tile index, walls, floors, rooms, blueprints |
| [client.md](sb/client.md) | `simburbia`: the window, its interface, screenshots, and headless and verbose runs |
| [tools.md](sb/tools.md) | `tsofiles-check`, the install differences report, `sb-oracle`, `sso-oracle`, and `simsscript` |

### [results/](results/README.md): what Simburbia finds on real installs

| Page | Covers |
| --- | --- |
| [install-differences.md](results/install-differences.md) | How the installs differ, step by step from the beta to 1.1097.1.0: files, archive entries, IFF chunks, and object GUIDs, with no game data. The reference for keeping Simburbia working on the beta |
| [install-notes.md](results/install-notes.md) | What the install differences mean for Simburbia, kept by hand: the skill objects' alpha, hidden objects |

### [simantics/](simantics/README.md): the SimAntics Wiki, in Markdown

A copy of the community wiki at simantics.wikidot.com, under its own license (CC BY-SA 3.0; see
[its README](simantics/README.md)). Each page ends with notes where FreeSO's code read it differently.

| Page | Covers |
| --- | --- |
| [introduction.md](simantics/introduction.md) | The model, terminology, Edith, interactions |
| [primitives.md](simantics/primitives.md) | Every TSO primitive, with operand layouts |
| [generic-sims-online-call.md](simantics/generic-sims-online-call.md) | The calls behind primitive 1 |
| [scopes.md](simantics/scopes.md) | Variable scopes and object definition fields |
| [object-data.md](simantics/object-data.md), [person-data.md](simantics/person-data.md), [motive-data.md](simantics/motive-data.md), [global-data.md](simantics/global-data.md) | The values objects, Sims, and the lot carry |
| [body-strings.md](simantics/body-strings.md), [walking-animations.md](simantics/walking-animations.md) | Sim appearance strings and walk animations |

## Elsewhere in the repository

- [`AGENTS.md`](../AGENTS.md): the workspace map and the rules for working in this repository.
- [`REVIEW.md`](../REVIEW.md): the checklist for reviewing a change.
