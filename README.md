# AI Stem Splitter by Oliver Tkach

A professional ReaScript for REAPER that utilizes Artificial Intelligence (Demucs) to separate audio into 6 high-fidelity tracks directly within your project.

## ✨ Features

* **6 Stems:** Separate audio into Vocals, Drums, Bass, Guitar, Piano, and Other.
* **Privacy:** Processes everything locally on your PC; nothing is uploaded to the cloud.
* **Organization:** Automatically creates folders, names tracks, and aligns them to the original item's position.
* **Efficiency:** Uses system temporary directories to avoid permission errors and keep your project folder clean.

## 🛠️ Requirements

Before using the script, ensure you have the following installed:

1. **Python 3.10+**: Download it from [python.org]().
* **Important:** During installation, check the box **"Add Python to PATH"**.


2. **FFmpeg**: Essential for audio encoding.
* **Windows:** Must be installed and added to your **System PATH**.
* **Mac:** Install via Homebrew (`brew install ffmpeg`).


3. **Libraries**: Open your terminal (CMD or PowerShell) and run these commands:
`python -m pip install --upgrade pip`
`python -m pip install demucs soundfile==0.12.1`
`python -m pip install torchcodec`

📌 IMPORTANT NOTES (PLEASE READ):  
**Both main scripts are now cross-platform (Windows, macOS, Linux). You do not need a separate universal file anymore.**

* **GPU vs CPU:** You don't need an NVIDIA card to run this.
* **NVIDIA Users:** The script will use CUDA and process songs in seconds.
* **Everyone else:** The script will automatically use your CPU. It works perfectly and with the same high quality, but it will take longer (around 3-7 minutes per song). Just be patient while the AI does its magic!
* **The "TorchCodec" & Backend Fix:** If you get a "TorchCodec is required" error, run `python -m pip install torchcodec`.
* **First Run:** The very first time you use the script, it will download the AI models (about 2GB). This only happens once!

## 🚀 Installation

1. **Download** the `.lua` file from this repository.
2. In **REAPER**, open the **Action List** (shortcut key `?`).
3. Click **New Action > Load ReaScript...** and select the downloaded file.
4. **(Optional)** To add it to your right-click menu:
Go to **Options > Customize menus/toolbars**, select **Media item context** from the dropdown, click **Add... > Action...**, find this script, and click **Save**.

---

## ❓ FAQ

**Q: Is it true that Demucs only works on Python 3.8 and is no longer available via pip?**
A: No, that is a common misconception. Demucs is actively maintained and works perfectly on Python 3.10 and 3.11. The script is designed to call Python globally, making it compatible with any modern stable version.

**Q: Why am I getting "command not found" or "pip is not recognized"?**
A: This usually happens if Python was installed without checking the "Add Python to PATH" box. Without this, your computer doesn't know where to find Python or the Demucs library.

**Q: How do I fix the installation easily?**
A: Follow these steps to ensure a perfect setup:

1. **Clean Start:** Uninstall any old versions of Python.
2. **Stable Version:** Install Python 3.10.11 from python.org.
3. **The "Secret" Step:** During installation, you MUST check the box that says "Add Python to PATH".
4. **Run these commands in your terminal (CMD) one by one:**
* `python -m pip install --upgrade pip`
* `python -m pip install demucs soundfile==0.12.1`
* `python -m pip install torchcodec`



**Q: I get a "RuntimeError: Couldn't find appropriate backend" error.**
A: This is fixed by installing the `soundfile` library. Run: `pip install soundfile==0.12.1` and make sure **FFmpeg** is correctly installed in your system's PATH.

**Q: What if I have permission errors when processing?**
A: You don't have to worry about that. This script uses the system's TEMP folder and a custom Lua binary copy function to bypass Windows permission restrictions and handle special characters in file names automatically.

---

## 🙌 Support this project

Hi! If this script has helped improve your workflow or your productions, I would greatly appreciate your support to keep creating free tools for the community.

If you want to stay updated on more tools, music, and reactions, feel free to follow me on my social media:

* 📸 **Instagram:** [@olivertkachmusic]()
* 🎥 **YouTube:** [@olivertkachreactions]()
* 📱 **TikTok:** [@olivertkachmusic]()

If you feel this work has added value to your life and would like to kindly buy me a coffee to support the development of future projects, you can do so here:

☕ **[Donate (tecito.app/olivertkachmusic)]()**

Thank you so much for valuing my work, and I hope you enjoy your new stems! 🤘

