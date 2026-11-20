# Results

Simburbia is rebuilding the engine of *The Sims Online* (Maxis and EA, 2002) in Swift. This folder
records what it finds on real copies of the game.

The project doesn't ship the game's files, so the measurements are run on copies installed on the
maintainer's machine, and only the outcome is published here. Tools write the reports, not people;
the one page kept by hand, `install-notes.md`, explains what a report found.
They hold counts, object IDs (GUIDs), file and chunk names, and values, never the game's own data.

| File | What it shows | Written by | When |
| --- | --- | --- | --- |
| `sb-study-<install>.tsv` | Each object the randomized study has sampled on that copy, and its latest result: clean, a finding (a broken rule or a run that doesn't repeat), or what Simburbia doesn't support yet | `sb-oracle study --ledger` | When a study runs |
| [install-differences.md](install-differences.md) | How the copies of the game used here differ, file by file, from the oldest to the newest | `tsofiles-check` | Once, again when a copy is added |
| [install-notes.md](install-notes.md) | What those differences mean for Simburbia, and content that relies on something unusual | By hand | As findings come in |

The copies are named by their environment variables: 1.1097.1.0, which came after New & Improved
(`TSO_GAME_DIR`); the base game (1.145.1.0, `TSO_CLASSIC_DIR`); and the beta (1.3.2.121,
`TSO_BETA_DIR`). Results can differ from one copy of the game to another.

## install-differences.md

It compares each copy with the next newer one: the beta (1.3.2.121) with the base game
(1.145.1.0), then the base game with 1.1097.1.0. Each step lists the files only one of the two
has and, for files in both that differ, which objects and resources inside changed, so it shows
what the patches between them changed. When Simburbia behaves differently on two copies, it shows
what changed in the game's files, before anyone looks for a bug in the code. It's written once;
deleting it and running `tsofiles-check` with the copies set writes it again. Notes on what the
differences mean go in `install-notes.md`, which the tool doesn't touch.
