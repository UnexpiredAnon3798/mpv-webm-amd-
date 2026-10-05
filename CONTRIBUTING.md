# Contributing

## Setup

You need:

- **LuaJIT** (what mpv uses) or Lua 5.1, to build and run the tests.
- **LuaRocks**, for [busted](https://lunarmodules.github.io/busted/) (unit tests) and [luacheck](https://github.com/lunarmodules/luacheck) (lint).
- [**StyLua**](https://github.com/JohnnyMorganz/StyLua) 2.5.2, for formatting.
- [**lua-language-server**](https://github.com/LuaLS/lua-language-server) 3.19.1, for the type check.
- **GNU make**, optional. Every target is a short command you can also run by hand.

CI uses the same versions, so pin them to avoid formatting or type check differences.

### Linux and macOS

```sh
sudo apt install luajit luarocks make     # or: brew install luajit luarocks
luarocks install --local busted
luarocks install --local luacheck
```

Add `~/.luarocks/bin` to `PATH` for `busted` and `luacheck`. Then download StyLua and lua-language-server from their release pages and put them on `PATH` too.

### Windows

LuaRocks needs a C compiler for some of busted's dependencies, and Windows has none by default. A setup that works without installing anything system-wide:

1. Unpack [w64devkit](https://github.com/skeeto/w64devkit) (GCC and make) into a tools folder.
2. Build LuaJIT from the [v2.1 branch](https://github.com/LuaJIT/LuaJIT/tree/v2.1) with `make HOST_MSYS=mingw` inside its `src` folder, from a shell where w64devkit's `bin` is on `PATH`.
3. Copy `luajit.exe`, `lua51.dll` and the headers (`lua.h`, `luaconf.h`, `lualib.h`, `lauxlib.h`, `lua.hpp`, `luajit.h`) into a `bin`/`include`/`lib` layout.
4. Get the LuaRocks Windows binary and point it at that layout with a config file that sets `LUA_DIR`, `LUA_INCDIR`, `LUA_LIBDIR`, `LUALIB = "lua51.dll"` and `CC = "gcc"`, then `luarocks install busted luacheck`.
5. Download the StyLua and lua-language-server Windows binaries.

With w64devkit on `PATH`, `make` also works from PowerShell.

## Commands

| Command | What it does |
|---|---|
| `make` | builds `build/webm.lua` and `build/webm.conf` (same as `luajit tools/build.lua`) |
| `make check` | everything below: lint, type check, unit tests, golden tests |
| `make lint` | `stylua --check .` and `luacheck .` |
| `make format` | formats the code with StyLua |
| `make typecheck` | lua-language-server's check, failing on warnings |
| `make test` | unit tests (`busted`) and golden tests |
| `make install` | builds and copies `webm.lua` into `~/.config/mpv/scripts` |

Set `LUA=lua5.1` (or another interpreter) to build with something other than `luajit`.

To try a change in mpv, run `make` and copy `build/webm.lua` into your `scripts` folder.

## Tests

- **Unit tests** in `tests/unit/` cover the modules in `src/core` and `src/encode`. They use `tests/unit/fake_host.lua` instead of mpv.
- **Golden tests** in `tests/golden/` load the built `webm.lua` with a fake mpv API, drive it through key presses and script-messages, and compare everything it does (commands, OSD text, files, events) with `tests/golden/expected/`. See [tests/golden/README.md](tests/golden/README.md).
- **Integration tests** in `tests/integration/` run the built script in a real, headless mpv and check the encoded files. They need Linux. See [tests/integration/README.md](tests/integration/README.md).

When a change is supposed to alter behavior, run `luajit tests/golden/run.lua --update`, read the diff of `tests/golden/expected/`, and include it in the same commit. A golden that changes when you didn't mean to change behavior is a bug in your change.

## Code layout

- `src/main.lua` wires the script into mpv: options, key binding, events.
- `src/core/` is pure logic: options, filenames, filters, bitrates, timing, upload arguments, video geometry.
- `src/encode/` builds encode commands, parses progress and interprets errors.
- `src/mpv/` talks to mpv: the property host, the live options, events, the encode flow, subprocesses, the clipboard.
- `src/ui/` holds the OSD pages.
- `tools/` has the build: the bundler and the `webm.conf` generator.
- `types/` declares mpv's Lua API for the type check.

`src/core` and `src/encode` never call `mp` directly. They take a host (see `src/mpv/host.lua`) so they can be unit tested. Every new module must be added to `MODULES` in `tools/build.lua`; the build bundles everything into one file because mpv does not put a single-file script's folder on `package.path`.

Options are defined once, in `src/core/options.lua`, with their defaults and the comments that go into `webm.conf`.

## Style

- Code must run on Lua 5.1 and LuaJIT, since that is what mpv embeds. No `goto`, integer division (`//`), bitwise operators or the `utf8` library.
- StyLua decides formatting. luacheck and the type check must pass without warnings.
- Write comments and commit messages in plain sentences. Use commas instead of dashes for asides.
- Keep commits small and focused, with the subject in the imperative ("Add avc-amf format").

## Releasing

1. In `CHANGELOG.md`, rename `Unreleased` to the version and date, for example `## [1.0.0] - 2026-10-20`.
2. Commit that, then tag and push it: `git tag v1.0.0` and `git push origin v1.0.0`.
3. The release workflow builds the script, runs the golden tests, and publishes a GitHub release with `webm.lua`, `webm.conf` and the changelog section as notes. It fails if the changelog has no section for the tag.
