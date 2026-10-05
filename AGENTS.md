# Notes for coding agents

mpv-webm is an mpv script that encodes clips of the playing video by starting a second mpv as the encoder. Users install one file, `webm.lua`, built from `src/` by `tools/build.lua`. Human-oriented setup and commands are in [CONTRIBUTING.md](CONTRIBUTING.md); this file is the short version plus the rules.

## Architecture

- `src/main.lua`: entry point. Reads options, creates the main page, binds the key, registers events and the testing script-messages.
- `src/core/`: pure logic, no `mp` calls. `options.lua` is the single source of option names, defaults and `webm.conf` comments.
- `src/encode/`: building and interpreting encodes, no `mp` calls. `command.lua` builds the whole command line, `formats.lua` holds the output formats.
- `src/mpv/`: everything that talks to mpv. `host.lua` is the property and filesystem interface that `core/` and `encode/` receive. `encoder.lua` runs an encode end to end. `options.lua` is the live options table shared by all modules.
- `src/ui/`: OSD pages built on `ui/page.lua`.
- `tools/build.lua`: bundles modules into `package.preload` and appends `main.lua`. New modules must be added to its `MODULES` list.
- `types/`: LuaLS declarations for mpv's Lua API.

## Checks

Run `make check` before calling a change done. It runs StyLua, luacheck, the lua-language-server check, busted, the build and the golden tests. Run the golden tests on both runtimes when you touch code that formats numbers or iterates tables: `luajit tests/golden/run.lua` and `lua5.1 tests/golden/run.lua`.

## Rules

- Target Lua 5.1 and LuaJIT. Nothing from Lua 5.2+ (`goto`, `//`, bitwise operators, `utf8`, `table.unpack`).
- Keep `mp.*` calls out of `src/core` and `src/encode`. Pass what they need through the host or as arguments.
- Don't depend on `pairs()` order for anything that ends up in a command, a filename or the OSD. Use arrays when order matters.
- The golden tests in `tests/golden/expected/` define current behavior. Never run `--update` to make a failure go away. Update them only for an intended behavior change, read the diff, and say in your summary exactly what changed and why.
- The "Known issues" in `CHANGELOG.md` are pinned on purpose. Don't fix them unless asked; a fix changes goldens and needs the maintainer's approval.
- User-facing behavior (options, defaults, key bindings, output names, commands) only changes with the maintainer's approval.
- Don't send repository contents to external services.
- Don't commit or push unless the maintainer asks. Commit messages are plain, with no AI attribution or co-author trailers.
- In comments and commit messages, use commas rather than dashes for asides, and write plain sentences.
