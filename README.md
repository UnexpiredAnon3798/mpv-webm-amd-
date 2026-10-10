# mpv-webm

Simple WebM maker for [mpv][mpv], with no external dependencies. This fork of [ekisu/mpv-webm][upstream] adds hardware encoding for AMD GPUs.

![sample](/img/sample.jpg)

## Installation

Download [`webm.lua`][build] and place it in your mpv `scripts` folder. The `scripts` folder can be found (or created, if it does not already exist) in the following paths:

- Linux/macOS: `~/.config/mpv/scripts`, where `~` is your user's home folder;
- Windows: mpv will try to load scripts from `%APPDATA%\mpv\scripts`, followed by `<mpv binary folder>\portable_config\scripts` and `<mpv binary folder>\mpv\scripts`; where `%APPDATA%` is a Windows-specific directory (typing `%APPDATA%` on Windows + R should take you to that folder), and `<mpv binary folder>` is the folder that contains the `mpv.exe` binary.

Additional details about the folder structure can be found in the [mpv's manual][file locations].

### Encoder executable

Encoding starts a separate `mpv` process. The `mpv` executable must be available on the `PATH` inherited by the player, including when the player is opened from a desktop shortcut or file manager.

- **Windows:** follow the [Windows encoder setup guide](docs/windows-encoder-setup.md) for step-by-step instructions to add mpv to `Path`, verify it, and troubleshoot desktop launches.
- **Linux/macOS:** run `command -v mpv` to check your shell's `PATH`. If encoding reports `mpv: command not found` when launched from the desktop, ensure that launch environment also includes the executable's directory. Homebrew commonly installs it in `/opt/homebrew/bin` on Apple Silicon and `/usr/local/bin` on Intel Macs.

If encoding instead reports a missing codec, check `mpv --ovc=help` for video encoders or `mpv --oac=help` for audio encoders. These lists come from the FFmpeg libraries used by **mpv**; installing a separate `ffmpeg` executable does not necessarily add codecs to mpv. On macOS, the Homebrew formula (`brew install mpv`) is one source of an encoder-enabled build.

## Usage

By default, the script is activated by the W (shift+w) key. Follow the on-screen instructions:

| Key | Action |
|---|---|
| `1` / `2` | set the start / end of the clip to the current position |
| `!` / `@` | jump to the start / end |
| `c` | crop: `1` and `2` set the corners under the mouse, `r` resets, `ENTER` confirms |
| `o` | encode options: arrow keys to change, `ENTER` to confirm |
| `p` | preview the clip on a loop |
| `e` | encode |
| `u` | encode and upload (shown only when `curl` is available) |
| `ESC` | close |

Encoded files will have audio/subs based on the current playback options (i.e. will be muted if no audio, won't have hardcoded subs if subs aren't visible).

### Output formats

Set the format on the options page or with `output_format` in `webm.conf`. The Device row under it shows the CPU or GPU that format encodes on, and while encoding, the progress shows in the top left corner.

| `output_format` | Video / audio | Notes |
|---|---|---|
| `webm-vp8` (default) | VP8 / Vorbis | |
| `webm-vp9` | VP9 / Opus | |
| `avc` | H.264 (x264) / AAC | |
| `hevc` | H.265 (x265) / AAC | |
| `av1` | AV1 (libaom) / AAC | |
| `avc-nvenc` | H.264 on NVIDIA GPUs / AAC | |
| `avc-vaapi` | H.264 on AMD/Intel GPUs (Linux) / AAC | experimental, no two-pass |
| `hevc-vaapi` | H.265 on AMD/Intel GPUs (Linux) / AAC | experimental, no two-pass |
| `avc-amf` | H.264 on AMD GPUs (Windows) / AAC | no two-pass |
| `webp` | animated WebP | |
| `gif` | GIF | |
| `mp3` | audio only, MP3 | |
| `raw` | uncompressed video / PCM audio | |

The hardware formats only work when your mpv build includes the encoder (`mpv --ovc=help` lists them) and the GPU driver supports it. The VAAPI encoders expect frames in GPU memory, and mpv's encoding mode may not upload them there, so the VAAPI formats can fail with a pixel format error. When an encode fails, the on-screen message shows the encoder's error, and the console (the ` key) has the details.

For these formats the GPU also decodes the source, so the CPU stays mostly idle. The `hwdec` option in `webm.conf` controls this: `auto` (the default) does it for GPU formats only, `no` always decodes on the CPU, and `auto-copy` always decodes on the GPU.

The `avc-amf` and VAAPI formats convert the video to 8-bit first. HDR and Dolby Vision sources are not tone mapped in the process, so their colors may look washed out or wrong.

### Uploading

Press `u` (encode & upload) on the WebM maker page to encode a clip and upload it in one step. The destination is set in the options (`o`) and stored in `webm.conf`:

- `upload_host`: `catbox` (permanent) or `litterbox` (temporary).
- `litterbox_time`: expiry for litterbox uploads, `1h`, `12h`, `24h` or `72h`.
- `catbox_userhash`: optional Catbox account hash. Account uploads are permanent and manageable.
- `upload_curl_path`: the `curl` executable used for the multipart upload.
- `open_after_upload`: open the link in the browser as soon as it is ready.

Uploads use `curl`; when it is not on `PATH`, the `u` line is hidden. The resulting URL is copied to the clipboard, through mpv's `clipboard/text` property when available, otherwise with the system's clipboard tool (`wl-copy` on Linux, `pbcopy` on macOS, `clip` on Windows). Only the Catbox services are supported: Streamable requires an account for uploads, so it is not offered.

## Configuration

Place a `webm.conf` inside mpv's `script-opts` folder to change the defaults. The [sample `webm.conf`][conf] lists every option with its default and a description. You only need to include the options you want to change.

## Known issues

See the [changelog](CHANGELOG.md#known-issues) for bugs that are known and not fixed yet.

## Development

The script is written in plain Lua and built into the single `webm.lua` with `make`. See [CONTRIBUTING.md](CONTRIBUTING.md) for the setup, tests and checks.

[upstream]: https://github.com/ekisu/mpv-webm
[build]: https://github.com/UnexpiredAnon3798/mpv-webm-amd-/releases/latest/download/webm.lua
[file locations]: https://mpv.io/manual/master/#files
[conf]: https://github.com/UnexpiredAnon3798/mpv-webm-amd-/releases/latest/download/webm.conf
[mpv]: http://mpv.io
