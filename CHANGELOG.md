# Changelog

All notable changes to this fork of [ekisu/mpv-webm](https://github.com/ekisu/mpv-webm) are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

To release, rename `Unreleased` to the new version with the date, for example `## [1.0.0] - 2026-10-20`, then push the tag `v1.0.0`. The release workflow uses that section as the release notes.

## [Unreleased]

### Added

- AMD hardware encoding formats: `avc-vaapi` (h264_vaapi) and `hevc-vaapi` (hevc_vaapi) for AMD and Intel GPUs on Linux, and `avc-amf` (h264_amf) for AMD GPUs on Windows. Two-pass encoding is off for all three. The VAAPI formats are experimental, see the README.
- Releases: pushing a `v*` tag builds `webm.lua` and `webm.conf` and attaches them to a GitHub release.

### Changed

- The script is rewritten from MoonScript to plain Lua. It is still a single `webm.lua`, installed the same way, with the same options, keys and output.
- The encode command now always lists the track options as video, audio, then subtitles. mpv treats these independently, so the encoded file is the same; before, the order depended on the Lua runtime.
- Leaving the preview restores the video filters, then the playback position, then the pause state. Before, the order depended on the Lua runtime.
- Downloads moved from the rolling `latest` build to tagged releases.
- Building needs only Lua 5.1 or LuaJIT (`make`, or `luajit tools/build.lua`). MoonScript is no longer used.

### Known issues

These are kept as they were in the MoonScript version, and are pinned by the golden tests until they are fixed.

1. An unknown `output_format` in `webm.conf` makes encoding fail with a Lua error and no message on screen.
2. `display_progress=no` in `webm.conf` does not turn the progress display off.
3. In filenames, text that comes from the media (the filename or title) can be expanded again by later substitutions, so a file called `50%Foo.mkv` can produce a broken name.
4. For audio-only formats (MP3) the bitrate is not rounded, and an unused `crf` flag is passed.
5. Only the first clipboard tool is tried (`wl-copy` on Linux), and the upload page says the link was copied even when copying failed.
6. Times are truncated instead of rounded (1.005 s becomes `.004`), and `%wT`/`%mT` in filenames round where `%s`/`%e` truncate.
7. On the "Upload failed" page, `o` ("change upload options") goes back to the main page instead of opening the options.
