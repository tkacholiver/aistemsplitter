# 🤖 AI Stem Splitter by Oliver Tkach - Version 2.0

A professional ReaScript for **REAPER** that utilizes Artificial Intelligence (**Demucs**) to separate audio into high-fidelity tracks directly within your project.

> **Note:** I'm primarily an **audio guy**, not a professional developer. This tool was born out of a personal workflow need and built using AI assistance (Antigravity). I'm sharing it so other producers can benefit from it!

---

## ✨ Features (New in v2.0!)

* **6 Stems:** Separate audio into Vocals, Drums, Bass, Guitar, Piano, and Other.
* **Quality Profiles:** Choose between **Fast** (speed), **Balanced** (default), or **High** (best quality) to trade render time for fidelity.
* **Two-stem Mode:** Perfect for karaoke or acapellas. Create just two outputs: your **Target** (e.g., Vocals) and **No_Target** (everything else).
* **Smart BPM Sync:** Automatically detects the audio's tempo and writes it to the REAPER project grid.
* **Automatic Organization:** Automatically creates folders, names tracks, and applies consistent colors for a clean session.
* **Technical Precision:** Choose your output format (**32-bit float** or **24-bit int**) and use **Clip Modes** (Rescale/Clamp) to prevent distortion.
* **100% Private:** Everything processes locally on your machine; no cloud uploads required.

---

## 🛠️ System Requirements

1. **Python 3.10+:** Download from [python.org](https://www.python.org/).
* **CRITICAL:** During installation, check the box **"Add Python to PATH"**.


2. **FFmpeg:** Essential for audio encoding.
* **Windows:** `winget install Gyan.FFmpeg`
* **macOS:** `brew install ffmpeg` (Script now includes explicit macOS support paths).


3. **Libraries:** Run this in your terminal to install necessary dependencies:
`pip install demucs soundfile==0.12.1 librosa numpy scipy torchcodec`

---

## 🚀 Installation & Usage

1. **Download** your preferred script:
* `AI Stem Splitter by Oliver Tkach - GUI.lua` (**Recommended:** Features a progress bar and configuration window).
* `AI Stem Splitter by Oliver Tkach.lua` (Standard non-GUI version).


2. **In REAPER:** Open **Action List (?) > New Action > Load ReaScript...** and select the file.
3. **Run:** Select an audio item, run the script, and configure your settings.
* *First run:* The script will download the AI models (approx. 2GB).



---

## ⚙️ Power User Options (v2.0)

* **Device:** Auto-detects **NVIDIA (CUDA)** or **Apple Silicon (MPS)** for lightning-fast processing. You can force **CPU** if your GPU is unstable.
* **Segment Seconds:** If you encounter memory crashes (low RAM/VRAM), set this to 10 or 20 to process the audio in smaller chunks.
* **Jobs:** Increase the number of worker jobs to speed up processing on high-end CPUs.

---

## 🤝 Community Collaboration

Since I'm not a coder, the community has been vital in making this script robust:

* **Project Lead:** Oliver Tkach (Audio/Workflow logic).
* **Major Contributor:** A huge thanks to **SifuInTheShell** for the professional v2.0 refactoring, unifying cross-platform support (Win/Mac/Linux), and implementing the smart fallback and logging systems.

---

## 🛠️ Troubleshooting (FAQ)

* **"Python not recognized":** You likely forgot to check "Add Python to PATH" during installation. Reinstall Python.
* **Memory Crashes:** Lower your **Segment Seconds** to 8 or 12.
* **NVIDIA vs CPU:** CUDA users will process in seconds. Everyone else will use CPU (3-7 minutes), but the **quality remains professional grade**.

---

## 🙌 Support the Project

If this script has improved your workflow, feel free to support its development!

📸 **Instagram:** [@olivertkachmusic](https://www.instagram.com/olivertkachmusic)
🎥 **YouTube:** [@olivertkachreactions](https://www.youtube.com/@olivertkachreactions)

If you'd like to buy me a coffee (or a "tecito" 🍵):
☕ **[Donate / Tecito](https://tecito.app/olivertkachmusic)**
