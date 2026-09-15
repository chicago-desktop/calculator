# windows/calculator — Calculator

The Windows 95 calculator for the terminal desktop: a module of the Windows
95 shell ([windows/shell](https://github.com/wippy-windows/windows) on
[windows/tui-desktop](https://github.com/wippy-windows/tui-desktop)). An
application that depends on it and runs the shell gets **Calculator** in
Start → Programs, with its icon; nothing else to wire.

It is the standard view: a display, the Back / CE / C row with the memory box,
and four rows of keys with the memory column (MC, MR, MS, M+) on the left —
digits, the four operations, `sqrt`, `%`, `1/x`, `+/-`, the decimal point and
`=`. Digits and functions are blue, operations red, as on the original. The
window is a fixed 29×16 cells (no "maximize"), and it draws in pixels through
the shell's shared renderer or in cells on a terminal without graphics — the
same keys and ids either way.

## How it counts

Like a desk calculator, not like an expression: an operation is applied to
the accumulated value immediately, so `2 + 3 × 4 =` gives **20**. Percent is
of the accumulated value (`50 + 10 % =` is 55); `CE` erases the entry but
keeps the pending operation; `C` clears everything but the memory. Division by
zero (and `1/x` of zero, the square root of a negative) puts a phrase on the
display — "Cannot divide by zero", "Invalid input" — and after it only `CE`
and `C` do anything: continuing to compute from a failure would produce a
number that never existed.

The display writes a whole number with a trailing dot, as Windows 95 does
(`0.`, `42.`), a fraction as typed, and a result too large for fifteen digits
in exponent form (`9.99999998e+17`).

Keys reach the same buttons as the mouse: digits, `.` or `,`, `+ - * /`, `=`
or Enter, `%`, `r` for `1/x`, `@` for `sqrt`, Backspace, Delete for `CE`, Esc
or `c` for `C`. A pressed key is highlighted for 150 ms by a one-shot timer.
The menu has only Help → About: the window cannot reach the terminal's
clipboard, so there is no Edit, and with a single view there is no View.

## Inside

- `windows.calculator:engine` — the arithmetic as a pure library with no
  screen and no runtime: `new()`, `press(state, id)`, `display(state)`,
  `format(value)` and `key(event)`, the map from a keyboard event to a
  button id. Buttons are named by identifiers (`add`, `sqrt`, `mplus`), not
  by captions; the tests exercise it without a compositor.
- `windows.calculator:images` — the module carries its own pictures, an image
  pack of the shell (`meta.type: windows.images`) under `assets/images/{32,16}`:
  `calculator`, named `windows.calculator:images/calculator` by the entry and
  the About sheet; copied from the shell's icon set (Microsoft's artwork from
  `shell32.dll`, see `assets/images/SOURCE.md`).
- `windows.calculator:window` — the process on the shell's SDK
  (`windows.shell.sdk:app`): the key grid as a component tree, one layout for
  pixels (the original's 4×2-cell keys) and one for cells (one-row keys in
  columns as wide as their longest caption), the highlight timer and the
  About sheet. Its registry entry (`meta.type: tui_desktop.window`) is what
  the Start menu reads.

The module depends on `windows/shell` (the SDK, the image packs) and
`windows/tui-desktop` (the compositor). It reads no files and asks nothing of
the application beyond the shell's `windows.shell.security:view_state` policy.

## Developing

```bash
make setup     # resolve the dependencies from the Hub (once, and after changing them)
make check     # the repository's invariants
make lint      # late locals, then wippy lint of this namespace and the harness
make test      # the harness in test/: the engine, the window, a shot in test/shots/
make publish   # to the Hub, after `wippy auth login`
```

`make test` runs `wippy test --host wippy.terminal:host` in `test/`, a tiny
application that boots the module together with the shell from the Hub (the
harness's gateway listens on :19241 so it can run beside the other modules'
harnesses). `test/src/engine_test.lua` checks the arithmetic, the key map,
the grid in pixels and in cells, every caption drawn whole at 8 to 10 px
cells and the About sheet; `test/src/window_test.lua` checks the registry
entry, the icon, the process running the engine, and writes
`test/shots/calculator.png` — the window as the shell's renderer drew it
after `12 × 3.5 =`. Look at the picture: the geometry checks do not see a
wrong colour.

**A local build of the runtime fork is required**
([wippy-windows/runtime](https://github.com/wippy-windows/runtime), branch
`wippy-projects`): the shell declares the `gfx` module, which the release
runtime does not have, and `wippy` from PATH does not load the shell at all.
The Makefile's `WIPPY` names the build; override it with `make test WIPPY=…`.

The window SDK is documented in [docs/sdk.md](docs/sdk.md), a copy of the
shell's guide, and the skill for agents in
[skills/wippy-window-app/SKILL.md](skills/wippy-window-app/SKILL.md); the
rules of this repository are in [AGENTS.md](AGENTS.md).

Extracted from the shell (`windows.shell.calc`, windows/shell 0.1.0) into a
module of its own, made from
[the Windows module template](https://github.com/wippy-windows/module-template).
Repository: https://github.com/wippy-windows/calculator.

## Licence

MIT. The calculator's icon in `assets/images` is Microsoft's artwork
(`shell32.dll`), copied from the shell's icon set, and is not covered by the
licence.
