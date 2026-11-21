<p align="center">
    <picture>
      <img alt="Simburbia" src="docs/assets/logo.svg" width="200">
    </picture>
</p>

<h1 align="center">Simburbia</h1>

<p align="center">
  <b>an open-source reimplementation of The Sims Online in Swift and Raylib.</b><br>
  Designed for LAN and small scale use<br>
  Support for Beta, Base Game, and New & Improved
</p>

## Getting Around

| Folder | Holds |
| --- | --- |
| `TSOFiles/`, `TSOContent/`, `SimAntics/`, and the others | The Swift code: independent Swift packages for the file formats, content, and the SimAntics VM, plus tools and SimsScript |
| `Client/` | The client, `simburbia`, which the repository's root package builds: `swift run simburbia` |
| [`docs/`](./docs/README.md) | How Simburbia works, the plan, and the results, with a glossary of terms |

To build and test, you need Swift 6. You don't need the game: tests run on
[`MockInstall`](./MockInstall/README.md), a tiny made-up install, and skip what needs the real one.

```sh
swift test --package-path SimAntics
```

Start with [docs/README.md](./docs/README.md). The rules for changing the code, for people and AI
assistants alike, are in [AGENTS.md](./AGENTS.md). The game's files are EA's and never go in the
repository.

## History

Simburbia grew out of [SimsCraft](https://github.com/tonytins/SimsCraft), which began as an effort
to document [FreeSO](https://github.com/riperiperi/FreeSO), the open-source C# reimplementation of
The Sims Online, and then checked Simburbia against FreeSO's code until November 2026. SimsCraft
keeps that history, and FreeSO's source with credit to its contributors.

## Licensing

Simburbia is licensed under the [GNU Affero General Public License v3.0](./LICENSE). The SimAntics
Wiki copy in [`docs/simantics/`](./docs/simantics/README.md) keeps its own licence (CC BY-SA 3.0).

---

<p align="center">
  <i>It's all coming back to you! 🪃</i>
</p>
