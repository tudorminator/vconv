# vconv

`vconv` is a small Windows/Git Bash utility for batch-converting video files to MP4 using Avidemux preset scripts. It is designed for workflows where you want to resize and re-encode MOV, MP4, and M4V files quickly while preserving rotation metadata and applying a repeatable conversion preset.

## What this project does

The main script, `vconv.sh`, does the following:

- accepts an input file or directory and an output directory
- finds all supported video files (`.mov`, `.mp4`, `.m4v`)
- resizes them by a configurable percentage (default: 100%)
- loads a preset file such as `HEVC.preset.py` or `H264.preset.py`
- runs Avidemux with the preset to render a new MP4 output
- detects rotation/orientation from EXIF metadata when available
- skips existing output files so it does not overwrite them accidentally

There is also a simpler (but unfinished) FFmpeg-based helper script, `vconv_ffmpeg.sh`, that converts directory contents using NVENC and AAC when those encoders are available.

## Included files

- `vconv.sh` — main conversion script
- `vconv_ffmpeg.sh` — FFmpeg-based conversion helper - not finished, not recommended
- `project.py` — Avidemux Python project, not used by the script, but as template/example for conversion presets
- `HEVC.preset.py` — HEVC preset
- `H264.preset.py` — H264 preset

## Requirements

This project expects a Windows environment with Git Bash installed.

Required:

- Git Bash / Bash shell with `cygpath`
- `ffprobe`
- Avidemux CLI (`avidemux_cli.exe` or `avidemux.exe`)
- A valid Avidemux installation on the machine

Optional but useful:

- `exiftool` for rotation metadata detection
- FFmpeg for `vconv_ffmpeg.sh`

## Usage

### Main script: `vconv.sh`

```bash
./vconv.sh -i "D:/Videos/Input" -o "D:/Videos/Output" -s 75 -p HEVC
```

Or with a single input file:

```bash
./vconv.sh --in "D:/Videos/source.mov" --out "D:/Videos/output" --scale 50 --preset H264
```

### Options

- `-i, --in` — input file or directory
- `-o, --out` — output directory
- `-s, --size, --scale` — resize percentage, for example `50`, `75`, `100`
- `-p, --preset` — preset name or preset file path (default: `HEVC`)
- `-h, --help` — display usage

The preset name is resolved to a matching file like `HEVC.preset.py` or `H264.preset.py` in the current directory or next to the script.

## Presets

The preset files are Python scripts executed by Avidemux. They configure video codec, bitrate, filters, audio track handling, and output container settings.

Examples in this repository:

- `HEVC.preset.py` — uses `ffNvEncHEVC`
- `H264.preset.py` — uses `ffNvEncH264`

These files can be edited to tune quality, scale, bitrate, and filter settings for your workflow.

## Notes

- Output filenames preserve the source base name with a `.mp4` extension.
- Output files are not overwritten automatically if they already exist.
- Only one audio track is considered, haven't tried with more, not really needed for my workflow.
- The script is oriented around a local Windows workstation workflow and expects Avidemux to be installed in the standard locations often used by the author.

## Example workflow

1. Put your source videos in a folder.
2. Run the conversion script with the desired preset and scale.
3. Check the output directory for generated MP4 files.

```bash
./vconv.sh -i "C:/Users/Tudor/Videos/Raw" -o "C:/Users/Tudor/Videos/Converted" -p HEVC -s 100
```

This will encode each source file into a new MP4 in the output folder using the HEVC preset.
