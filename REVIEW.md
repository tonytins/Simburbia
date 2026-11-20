# Review Guide

Use this checklist when reviewing a change to Simburbia, by a person or an agent. It is adapted
from the contributor and review practices in
[NVIDIA FLARE's contribution guide](https://github.com/NVIDIA/NVFlare/blob/main/CONTRIBUTING.md),
by way of [Hudini](https://github.com/tonytins/Hudini), with checks tailored to Simburbia's
packages, its VM, and its client. The rules it checks against are in [AGENTS.md](AGENTS.md). One
person maintains Simburbia, so a review is often the only other pair of eyes a change gets.

## Before Reviewing

- Read the change description, its diff, and the code and tests it affects, including callers in
  Simburbia's other packages.
- Work out what the change is meant to do and check it does that. For a bug fix, check it fixes
  the cause, everywhere the cause reaches.
- Check what ran: each touched package's build and tests (and those that depend on it), the
  install scan, a headless run of the client, the study, and CI. Run focused checks where you
  can. For changes to the window, input, or drawing, take a screenshot on a private display.
  Report checks that could not be run.

## Review Checklist

- **Reading files:** Can a truncated, corrupt, or hostile file (an archive, a chunk, a
  blueprint, a mod) reach a trap? Is a size, offset, or count from a file checked before it's
  used? Does a reader that throws leave something half done? Is unknown data dropped without a
  report, or bad data quietly replaced?
- **The simulation:** Could results differ between machines: a `Dictionary` or `Set` iterated
  in VM logic, the clock read, randomness not from the VM's seed, 16-bit arithmetic that doesn't
  wrap, floating point feeding state? Can one entity's error escape into others?
- **Formats Simburbia writes:** Can an older Simburbia still read a blueprint or save this change
  writes? Is a new section one an older build can skip, and is the version raised for a change it
  can't? Does a rewrite carry through the parts it should?
- **Behavior real content relies on:** Does the change alter what real objects do on a lot? Is
  that recorded in the scorecard, with the source it's based on?
- **The client:** Is raylib called only on the main thread, while the window is open? Does
  rendering stay out of simulation state? Does any library import raylib? Does an interface
  document carry every control the client uses, and does a package carry its files?
- **The study and scenarios:** Is each run repeatable from its seed? Is an inconclusive lot
  counted as clean, or a finding hidden?
- **Tests:** Does a crash or bad-input fix come with a regression test that failed before it? Do
  focused tests cover the changed behavior, with Swift Testing?
- **Docs and records:** Do the scorecard, the roadmap, and `docs/` still say what the code does?
  Is a result claimed that wasn't measured?
- **Data and licences:** Is any of the game's data committed? Is a dependency added without a
  reason, or one whose licence doesn't fit?

## Not Worth a Finding

- Style alone. Formatting and naming are the guidelines' concern, and a change matching the code
  around it is fine.
- Speculative refactors, and missing tests with no concrete risk behind them.
- Process details AGENTS.md doesn't mark strict.
- Build output (`.build/`, `dist/`), unless a change tracks it.
- Bad input in a test that's meant to be rejected: check it's rejected as intended.

## Writing Review Comments

- Start with how many findings there are, such as `2 findings` or `0 findings`. Then say what was
  reviewed, which checks ran and what they showed, and what remains uncertain. A clean review
  isn't proof the change is right.
- Make each comment specific, constructive, and actionable: a short title, the file and line,
  what triggers it, what goes wrong, and what that leads to. Gather repeats of one cause into one
  finding. Keep open questions apart from verified findings.
- Prioritize findings by impact:
  - **Blocking**: a package doesn't build or its tests fail, game data is committed, or normal
    use fails badly and unavoidably.
  - **High**: a reader traps on bad input, the simulation stops being deterministic, a format
    stops being readable by older builds, or an existing behavior or common flow breaks.
  - **Medium**: a limited but real defect in behavior or reliability, or docs describing
    something that isn't true.
  - **Low**: a small edge case, or an improvement that shouldn't block the change.
- If no actionable issues remain, say so and note any important checks that were not run.

## Reviewing Again

- Check earlier findings are fixed or answered, and don't repeat ones that are. Look at what's
  new and what it touches.
- After three rounds of review and fixes on one change, sum up what's still open and ask whether
  the approach should change, rather than going round again.
- When the same feedback keeps coming back, suggest a rule in `AGENTS.md` or a check that
  catches it.
