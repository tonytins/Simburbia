# The client: simburbia

`simburbia` is Simburbia's client, in [`Client`](../../Client/), which the repository's root
package builds. It loads a lot from an
install, runs it on SimAntics at TSO's 30 ticks a second, and shows it in a window. It doesn't play
the game yet: there are no Sims, no building, and no online play. It shows how far the libraries
have come, and it's the tool for watching a lot run.

```sh
swift run simburbia
```

On Linux the build needs the X11 and GL headers; [`AGENTS.md`](../../AGENTS.md) says where they come
from on the owner's machine.

## What it opens

Without `--game`, the install is `TSO_GAME_DIR`, then `TSO_CLASSIC_DIR`, then `TSO_BETA_DIR`
(TSOContent's `InstallKind` lists them), then [MockInstall](../../MockInstall/README.md),
so it runs anywhere. With `--lot`, the client goes straight to that lot. Without it, the client
opens the login window (below), the start of the flow TSO's client takes: loading and login, then
(when Sims and cities come) picking a Sim and entering a city, then entering a lot. Screenshots and
headless runs without `--lot` use the owner's lot, `tonys-lot.xml` ([`Lots`](../../Lots/)) on a
real install and the mock lot on MockInstall, so they never wait for a click. Objects the install
doesn't have, or can't load, are left out and reported.

It also loads a FreeSO-style content folder and Simburbia's mods (`FSO_CONTENT_DIR` and `SB_USER_DIR`; see
[content.md](content.md#content-folders-and-mods)). A custom object or patch that can't be read,
or a custom object whose GUID is taken, becomes a system message in MOMI and counts as an error in
the top bar.

## Loading

The window opens on a loading screen at once, as TSO's does, while the install and the lot load
on another thread; the session is handed to the window once, when it's ready. The screen is the
install's own loading art, TSO's `setup` graphic (New & Improved's, or the 2002 copies'), scaled
to the window's height and centred on TSO's dark blue (`#09182F`); without one, as on MockInstall, it's Simburbia's logo. Under it, a caption
and lines that slide in from the right one after another: each takes a second and comes in only when loading has reached its share, so the screen shows
for at least four seconds. The text is TSO's own when there's an install (the caption is table
154's entry 5, the lines table 155's entries 6 to 9, looked up with swift-cst's `UIText` in
`gamedata`'s text, in either install's layout), else Simburbia's
(`Interface/uitext/_1_loading.cst`, read with swift-cst's `CSTDirectory`). A problem in
Simburbia's table, such as a value never closed or a key used twice, is a warning naming its line.

Loading reports its progress: the install's content, its floors and walls, the lot and its first
tick, then the textures of what's in view, which the client makes by drawing a frame off screen
so the lot doesn't stutter as it appears. Half a second after the last line settles, the lot
appears. `--loading-screenshot FILE` saves a frame of the screen as its second line slides in.

## Login

Without `--lot`, the loading screen loads the install, then the login window opens over its art,
as TSO's login dialog opened over its own, with Simburbia's version at the bottom right
(TSO showed its own at the bottom left). The window follows the owner's mockup
([`docs/design/login-screen.png`](../design/login-screen.png)), from the UIScript documents
`Interface/login-start.uix` and `Interface/login-join.uix`: a movable window with two tabs.

- **Start** lists the lots to play: Simburbia's (`Lots`), the mock lots on MockInstall, then the
  player's own (`Lots` in the user folder, marked "yours"). Pick one and press Play (or Enter),
  and the loading screen comes back while the lot loads onto the install already loaded. Delete
  and New are shown but wait for their own step.
- **Join** has the address, port (54926), name, and password of a game to join, shown disabled
  until Simburbia has networking.

The window has no close button, its lot list is one of Hudini's selectable lists, and the
password field hides what's typed. `--login-screenshot FILE` saves a frame of the window once the
install has loaded.

## The window

The lot is drawn through raylib's 3D camera at TSO's view: looking down 30° from the horizon, at a
45° angle, with TSO's three zooms (near, medium, far) and two farther ones. Roadmap decision 7
explains why a 3D camera rather than 2D batches.

- **Objects** draw with their sprites, placed by their draw group's offsets. Each pixel has its
  depth from the sprite's depth frame, made global from the object's offset (Hyde Park's E2). So objects cover each other, and the walls, pixel by pixel: a television's
  screen shows in front of its own body, and a cut-down wall hides the base of what stands
  behind it. A GPU that can't compile the depth shader gets the sprites back to front instead.
- **Hidden objects** aren't drawn or picked: portals, the mailbox's second part, and other
  controllers hide themselves through object data 34, and TSO's job lots
  also mark theirs `hidden="1"` in the blueprint. That's the lot format's, not SimAntics': the
  client applies it, and the VM never sees it.
- **Floors** are textured tiles. Each floor's sprite
  is a texture that repeats across the lot: a tile's diamond takes its part of it, and the
  sprite's corners, filled from half a frame away when it's decoded,
  carry the neighboring tiles' halves. Pools and water take one of 16 shapes from the tiles
  beside them and stay upright on screen as the view turns. Floors are opaque, and texels
  under half alpha aren't drawn. Pool corners aren't drawn.
- **Walls** are sprites: each side and diagonal takes
  its pattern, masked by its style (a full wall, a cut-down one, a fence), turned with the view,
  and placed from its tile's top corner on screen. Each pixel's depth comes from generated
  gradients, so walls and objects hide each other where they should. Full-height
  walls are capped where they stop, and junction pieces cover where they meet. Doors and windows
  cut their openings with wall styles made from their own sprites. Diagonal tiles draw their two floor halves.
- **Wall modes** are TSO's, for the floor in view; floors below keep their walls up. Cutaway, the
  default, cuts walls down in front of the last three indoor rooms the pointer was over and
  around the pointer, slanting them where the cut ends; down cuts every wall down, leaving a door's wall out; up leaves them
  standing. W steps through them, and `--walls cutaway|down|up` picks one to start with. A
  screenshot has no pointer, so its cutaway follows the middle of the screen, which `--focus` sets.
- **The ground** is a flat shape for now; grass waits. Floors and the ground are drawn a little
  back and down, so the feet of objects standing on them show. If
  the install's floors or walls can't be read, they're drawn as plain tiles and boxes, and MOMI
  says why.
- **An object without a sprite** for the view is drawn as a box.

| Input | Does |
| --- | --- |
| Space | Pause and resume |
| 1 to 3, or the speed arrows | Normal, fast, and fastest speed (1, 3, and 10 times) |
| Q and E | Rotate the view a quarter turn |
| Mouse wheel | Zoom |
| Right-drag | Pan |
| Page Up and Page Down | Change the floor in view |
| W | The next wall mode: cutaway, down, up |
| Click an object | Inspect it |
| Ctrl+Shift+C | Open and close the terminal |
| Escape | Close the window in front |

The interface follows the owner's prototype mockup ([`docs/design`](../design/README.md)),
which also serves as Simburbia's fallback and debug interface:

- **The top bar** shows the lot, the speed, the game time, the floor in view, the object count, a
  red error count when there are errors, and a help button.
- **Help** lists the keys.
- **MOMI**, opened from the error count, shows Simburbia's system messages: for now, each error a
  thread reported, in words. MOMI was TSO's in-universe name for its game masters. Its input stays
  disabled until there's online play.
- **The inspector** shows a clicked object: what it is, where it is, and what it's running.
- **The terminal**, opened and closed with Ctrl+Shift+C, queues a Sim's interactions by hand
  until there's a pie menu. It drops down under the top bar, and while its input has the
  keyboard the game's keys wait. Its commands (`TerminalCommands`, tested without a window) join
  a Sim (the install's template person, or MockInstall's Sim) and act for it: `join`, `sim`,
  `sims`, `objects`, `menu` (what the Sim may choose on an object), `queue`, `cancel`, `show`
  (the Sim's queue), `clear`, and `help`. It goes through `VM`'s `availableInteractions`,
  `queueInteraction`, and `cancelInteraction`.

The windows over the lot (Help, MOMI, the inspector, and the terminal) live in Hudini's
`WindowManager`: it stacks them, brings one to the front when it's clicked, gives only the front
one the keyboard and the pointer, and draws them back to front. Each is a `ManagedWindow`, a
document in Hudini's frame that the client opens and closes; a click on any of them never reaches
the lot.

The windows and controls come from [Hudini](https://github.com/tonytins/Hudini), the owner's
interface library for raylib-swift, which grew out of the NSOInterface package this repository
used to have. Its `hudini-demo` shows them on their own. Simburbia's look is
`InterfaceTheme.simburbia`: for now Hudini's standard palette, with
[Comic Neue](https://github.com/crozynski/comicneue) for the interface's text and
[Fira Mono](https://github.com/mozilla/Fira) for fixed-width text such as the terminal's, both
under the SIL Open Font License, in [`Interface/fonts`](../../Interface/fonts/README.md). The
window loads them once it opens (`ClientWindow`), at 32 pixels with smooth scaling and the
Latin-1 characters TSO's text uses, and unloads them before it closes. A font that's missing or
unreadable is a warning, and its text uses raylib's own font.

The top bar and the Help, MOMI, inspector, and terminal windows are described in Hudini's
UIScript documents (`.uix`, an XML format), in [`Interface/`](../../Interface/): `topbar.uix`,
`help.uix`, `momi.uix`, `inspector.uix`, and `terminal.uix`. Each says where its controls go,
what fixed text they hold, and their colors;
the client fills in what changes (the lot, the time, the messages, the object) and draws what
UIScript has no control for (the speed arrows and the round help button, in regions the document
places). Each window's document is its content, under the title bar Hudini's `WindowFrame` draws.
The client reads them when its window opens: one that's missing, doesn't read, or lacks a control
the client uses (`InterfaceDocuments.required`) stops it with a message naming it. Moving a
control, or rewording the help, is an edit to a document, with no rebuild. The format is close to
TSO's own `.uis` screens, which Hudini also reads.

## Without a window

Three options run the lot without anyone at the screen, and a fourth rewrites its blueprint.

- **`--screenshot FILE`** opens a hidden window, runs `--ticks` ticks (300 by default), saves one
  frame, and quits. `--zoom` (1 to 5), `--focus x,y`, and `--rotation` (0 to 3) frame the shot.
- **`--headless`** opens no window at all and needs no display, after CityLimits' headless run. The
  lot runs `--ticks` ticks back to back, as fast as the machine allows: a game day (216,000 ticks)
  by default, a game week at most. It logs to standard error and exits.
- **`--check`**, with `--headless`, checks the lot's rules (`LotRule`, see
  [tools.md](tools.md)) after loading and every game minute, logs each rule an object breaks the
  first time it breaks it, and exits with a failure if any broke.
- **`--verbose`** logs the same as a headless run while the window is open.
- **`--rewrite-blueprint FILE`** writes the lot's blueprint in TSO's own dialect, with every object
  named, and quits without running it: how a lot saved by FreeSO becomes one people can read
  ([blueprints.md](blueprints.md)). It can name its own lot (`--lot`) to rewrite it in place.

A run's log, through swift-log, has Simburbia's version, the lot and the install's version, each system message as it
arrives, a line each game hour, and a summary. Every line is stamped with the tick and the game
time, never the clock, so two runs of the same lot log alike:

```text
info: tick 1, 0:00: lot tonys-lot, install .../TSOClient (1.1097.1.0)
info: tick 9000, 1:00: 175 entities, 18 errors so far
info: tick 216001, 0:00: ran 216000 ticks, 1 day of game time; 175 entities, 18 errors
```

Options that need a window are refused with `--headless`, and `--ticks` is refused outside
`--headless` and `--screenshot`.

## Time

TSO counts 150 ticks a game minute. At 30 ticks a second, a game
minute lasts 5 real seconds, a game hour 5 minutes, and a game day 2 hours at normal speed. A
headless run of the community lot covers a game day in about 9 seconds.

## Versions

`simburbia --version` prints Simburbia's version, which the owner's GitVersion plugin works out
as the client builds: the base in [`GitVersion.txt`](../../GitVersion.txt)
(`0.1.100`), plus each commit since, after the .NET SDK's
`major.minor.1xx` feature bands. The branch and commit follow it (`0.1.103+main.1a2b3c4d5e6f`), and `.dirty`
when the working tree has staged changes. A build needs the whole history: a shallow clone fails
on purpose, since its count would be wrong.

## Packages

`packaging/` builds the client into packages players download, so it runs without
`swift run`: an AppImage and a `.tar.gz` on Linux, and, once they've been tried on those systems,
a zip on Windows and an app on macOS ([its README](../../packaging/README.md)). A
packaged client finds its lots and the mock install beside itself (in `Contents/Resources` in the
Mac app), and a build run from the repository finds them at the repository root.

## How it's built

The client is one target, `simburbia`, in the repository's root package. It's the game, so any
part of it may draw with [raylib-swift](https://github.com/tonytins/raylib-swift); what can be
worked out without a window is kept that way, and its tests (`SimburbiaTests`, which import the
target) run without one. Its sources are grouped by job, in `Client/Sources`:

| Folder | Holds |
| --- | --- |
| `App` | The command line, the window, the frame loop, and the run's log |
| `Session` | The loaded install and lot, ticking the VM, the lots to choose from, and system messages |
| `Scene` | The lot's geometry, and which sprites go where: worked out without a window |
| `Drawing` | Drawing the lot through the 3D camera: floors, walls, sprites, and their depth |
| `Screens` | The loading screen and the login window |
| `Windows` | The interface documents, the top bar, and the windows over the lot, such as the inspector |
| `Terminal` | The drop-down terminal and its commands |

The rendering reads the VM's state and never changes it, so what's drawn can't affect the simulation.
