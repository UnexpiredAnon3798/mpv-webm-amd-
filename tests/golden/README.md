# Golden tests

Characterization tests for the built `build/webm.lua`. They pin down what the
script does today so a rewrite can be checked against it.

Run from the repository root after `make`, with Lua 5.1 or LuaJIT:

```sh
lua tests/golden/run.lua              # compare with expected/
lua tests/golden/run.lua --update     # rewrite expected/ after an intended change
lua tests/golden/run.lua encode_gif   # only scenarios whose name contains the text
```

## How it works

`run.lua` loads the built script into a sandbox where `mp`, `mp.msg`,
`mp.utils`, `mp.options`, `mp.assdraw`, `os` and `io` are fakes
(`fake_mpv.lua`). Each scenario in `scenarios.lua` sets up properties, files
and subprocess results, then drives the script only through its external
surface: key presses, script-messages, events, timers and asynchronous callbacks.
Steps name their values, for example `{ "range", start_time = 1.5, end_time = 4.25 }`.

Everything observable is written to a transcript: subprocess argv, popen
command lines, OSD text, emitted `webm-*` events, properties set, options read,
and files written or removed. The transcript is compared with
`expected/<scenario>.txt`. The built `webm.conf` is compared with
`expected/webm.conf.txt`.

Because internal functions are never called, the same goldens apply to any
implementation that behaves the same.

## Simplifications

- `pairs()` iterates in sorted key order inside the sandbox. Real hash order
  differs between PUC Lua and LuaJIT builds, and three outputs depend on it:
  the order of `--vid`/`--aid`/`--sid` arguments, the order in which the
  preview page restores properties, and the order of filename substitutions.
- Property observers fire synchronously and only when a scenario changes a
  property. mpv's initial observer notification is not emulated.
- Asynchronous commands and timers run only when a scenario asks
  (`run_pending_commands`, `timers`).
- `msg.verbose`/`debug` output is not recorded; the commands it prints are
  already captured from the subprocess calls.

These tests do not replace the integration tests in `tests/integration`, which
run the script in a real mpv.
