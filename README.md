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
| `TSOFiles/`, `TSOContent/`, `SimAntics/`, `SBClient/` | The Swift code: independent Swift packages at the repository root for the file formats, content, and the SimAntics VM, plus the client, tools, and SimsScript |
| [`docs/`](./docs/README.md) | How Simburbia works, the plan, and the results, with a glossary of terms |

To build and test, you need Swift 6. You don't need the game: tests run on
[`MockInstall`](./MockInstall/README.md), a tiny made-up install, and skip what needs the real one.

```sh
swift test --package-path SimAntics
```

Start with [docs/README.md](./docs/README.md). The rules for changing the code, for people and AI
assistants alike, are in [AGENTS.md](./AGENTS.md). The game's files are EA's and never go in the
repository.

## Licensing

Simburbia is licensed under the [GNU Affero General Public License v3.0](./LICENSE). The SimAntics
Wiki copy in [`docs/simantics/`](./docs/simantics/README.md) keeps its own licence (CC BY-SA 3.0).

---

<p align="center">
  <i>It's all coming back to you! 🪃</i>
</p>
