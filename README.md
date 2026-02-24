# AI Stem Splitter by Oliver Tkach - Version 2.0

A ReaScript for REAPER that uses Demucs to split audio into high-fidelity stems directly in your project.

## Features

- 6 stems: vocals, drums, bass, guitar, piano, other
- Quality profiles: fast, balanced, high
- Two-stem mode (target + no_target)
- BPM/key/Hz analysis and project tempo sync
- Automatic track naming, foldering, and colors
- Local processing (no cloud upload)

## System Requirements

1. Python 3.10+  
   Windows users should enable "Add Python to PATH" during install.
2. FFmpeg  
   - Windows: `winget install Gyan.FFmpeg`  
   - macOS: `brew install ffmpeg`
3. Python dependencies  
   `pip install demucs soundfile==0.12.1 librosa numpy scipy torchcodec`

## Installation and Usage (Manual)

1. Download your preferred script:
   - `AI Stem Splitter by Oliver Tkach - GUI.lua` (recommended)
   - `AI Stem Splitter by Oliver Tkach.lua`
2. In REAPER, open Action List -> New Action -> Load ReaScript.
3. Select an audio item and run the script.
4. First run may download model files.

## ReaPack Installation (Recommended)

Use ReaPack to install and keep scripts updated from this repo.

1. In REAPER, open `Extensions > ReaPack > Import repositories...`
2. Add:
   `https://raw.githubusercontent.com/tkacholiver/aistemsplitter/main/index.xml`
3. Open `Extensions > ReaPack > Browse packages`
4. Search for `AI Stem Splitter by Oliver Tkach - GUI.lua`
5. Install and click `Apply`

Known-good fallback index:

`https://raw.githubusercontent.com/tkacholiver/aistemsplitter/reapack-working-2026-02-24/index.xml`

## Power User Options

- Device: auto, cpu, cuda, mps
- Segment size tuning for low RAM/VRAM systems
- Worker job count tuning

## Troubleshooting

- Python not found: reinstall Python and enable PATH integration
- Out-of-memory: lower segment seconds
- FFmpeg missing: install and restart REAPER

## Support

- Instagram: https://www.instagram.com/olivertkachmusic
- YouTube: https://www.youtube.com/@olivertkachreactions
- Donate: https://tecito.app/olivertkachmusic
