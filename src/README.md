`tools/build.lua` bundles these files into the single `build/webm.lua` that users install. Each module is stored in `package.preload`, so `require("core.time")` and similar work inside that one file, and `main.lua` runs last.

- `main.lua` wires the script into mpv: options, key binding, events.
- `core/` is pure logic: options, filenames, filters, bitrates, timing, upload arguments, video geometry. No `mp` calls.
- `encode/` builds encode commands, parses progress and interprets errors. No `mp` calls either.
- `mpv/` is the code that talks to mpv: the property host used by `core/` and `encode/`, the live options, events, the encode flow, subprocesses and the clipboard.
- `ui/` holds the OSD pages.

A new module has to be added to `MODULES` in `tools/build.lua`.
