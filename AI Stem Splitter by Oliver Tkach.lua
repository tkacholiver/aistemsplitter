--[[
    REAPER LOCAL AI ENGINEER (ANTIGRAVITY CORE)
    Role: Professional Audio Separation Engine (High-Fidelity)

    NOTE:
    Demucs inference cannot run natively inside plain ReaScript Lua.
    This script runs Demucs through an external Python runtime.

    ONE-TIME SETUP:
    - Windows:
      1) Install Python 3 from python.org and check "Add Python to PATH".
      2) In Command Prompt, check which command works:
         python --version
         py -3 --version
         python3 --version
      3) Use the command that works with:
         <python-command> -m pip install --upgrade pip
         <python-command> -m pip install demucs soundfile==0.12.1
      4) If Demucs later reports "TorchCodec is required", run:
         <python-command> -m pip install torchcodec
      5) Install FFmpeg and add it to PATH.
         Easy option: winget install Gyan.FFmpeg
    - Mac:
      1) brew install python ffmpeg
      2) Check which command works:
         python3 --version
         python --version
      3) Use the command that works with:
         <python-command> -m pip install --upgrade pip
         <python-command> -m pip install demucs soundfile==0.12.1
      4) If Demucs later reports "TorchCodec is required", run:
         <python-command> -m pip install torchcodec
    - Linux (Ubuntu/Debian):
      1) sudo apt update && sudo apt install -y python3 python3-pip ffmpeg
      2) Check which command works:
         python3 --version
         python --version
      3) Use the command that works with:
         <python-command> -m pip install --upgrade pip
         <python-command> -m pip install demucs soundfile==0.12.1
      4) If Demucs later reports "TorchCodec is required", run:
         <python-command> -m pip install torchcodec
]]

local APP_NAME = "AI Stem Splitter by Oliver Tkach - Version 2.0"
local MODEL_NAME = "htdemucs_6s"
local STEM_OUTPUT_FOLDER = "audio_process"
local STEM_NAMES = {"vocals", "drums", "bass", "guitar", "piano", "other"}
local AUTO_SET_PROJECT_BPM_FROM_ANALYSIS = true
local BPM_SET_MIN = 40
local BPM_SET_MAX = 260

-- Demucs runtime options:
-- quality: "fast", "balanced", "high"
local DEMUCS_QUALITY_PROFILE = "balanced"
-- Set to a stem name like "vocals" for karaoke mode, or "off".
local DEMUCS_TWO_STEMS_TARGET = "off"
-- precision: "default", "float32", "int24"
local DEMUCS_OUTPUT_PRECISION = "default"
-- Optional clip mode: "rescale", "clamp", or "" to keep Demucs default.
local DEMUCS_CLIP_MODE = ""
-- Optional performance/memory controls:
-- device: "auto", "cpu", "cuda", "mps"
local DEMUCS_DEVICE = "auto"
-- Set >0 to limit segment seconds and reduce memory usage.
local DEMUCS_SEGMENT_SECONDS = 0
-- Set >0 to control worker jobs.
local DEMUCS_JOBS = 0

local AUTO_COLOR_STEM_TRACKS = true
local STEM_TRACK_COLORS = {
    folder = {180, 180, 180},
    vocals = {235, 92, 92},
    no_vocals = {84, 170, 250},
    drums = {247, 165, 59},
    bass = {90, 130, 245},
    guitar = {82, 201, 122},
    piano = {178, 129, 241},
    other = {145, 145, 145}
}

local function get_os_info()
    local os_str = reaper.GetOS()
    local is_windows = os_str:match("Win") ~= nil
    local sep = is_windows and "\\" or "/"
    return is_windows, sep
end

local IS_WINDOWS, SEP = get_os_info()

local function path_join(base, leaf)
    return base .. SEP .. leaf
end

local function normalize_token(value)
    local s = tostring(value or ""):lower()
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    return s
end

local function file_exists(path)
    local f = io.open(path, "r")
    if f then
        f:close()
        return true
    end
    return false
end

local function dir_exists(path)
    local ok, _, code = os.rename(path, path)
    if ok then
        return true
    end
    return code == 13
end

local function command_succeeded(cmd)
    local ok = os.execute(cmd)
    if type(ok) == "number" then
        return ok == 0
    end
    if type(ok) == "boolean" then
        return ok
    end
    return false
end

local function quote_arg_windows(value)
    value = tostring(value or "")
    value = value:gsub('"', '""')
    return '"' .. value .. '"'
end

local function quote_arg_posix(value)
    value = tostring(value or "")
    value = value:gsub("'", "'\\''")
    return "'" .. value .. "'"
end

local function quote_arg(value)
    if IS_WINDOWS then
        return quote_arg_windows(value)
    end
    return quote_arg_posix(value)
end

local function escape_python_single_quoted(value)
    value = tostring(value or "")
    value = value:gsub("\\", "\\\\")
    value = value:gsub("'", "\\'")
    return value
end

local function escape_vbs_string(value)
    value = tostring(value or "")
    value = value:gsub('"', '""')
    return value
end

local function ensure_work_dir(path)
    if reaper.RecursiveCreateDirectory then
        reaper.RecursiveCreateDirectory(path, 0)
        return dir_exists(path)
    end

    if IS_WINDOWS then
        os.execute("mkdir " .. quote_arg(path) .. " > nul 2>&1")
    else
        os.execute("mkdir -p " .. quote_arg(path) .. " >/dev/null 2>&1")
    end
    return dir_exists(path)
end

local function can_write_dir(path)
    local probe = path_join(path, ".ai_stem_splitter_probe")
    local f = io.open(probe, "w")
    if not f then
        return false
    end
    f:write("ok")
    f:close()
    os.remove(probe)
    return true
end

local function run_preflight(work_dir)
    if not ensure_work_dir(work_dir) then
        return false, "Could not create temporary work directory:\n" .. work_dir
    end

    if not can_write_dir(work_dir) then
        return false, "Cannot write to temporary work directory:\n" .. work_dir
    end

    return true, nil
end

local function build_setup_help(python_cmd)
    local py = python_cmd or "<python-command>"
    if IS_WINDOWS then
        return table.concat({
            "One-time setup (Windows):",
            "1) Install Python 3 from https://www.python.org/downloads/",
            "   Important: check 'Add Python to PATH'.",
            "2) In Command Prompt, find your Python command:",
            "   python --version",
            "   py -3 --version",
            "   python3 --version",
            "3) Use the command that worked (example shown below):",
            "   " .. py .. " -m pip install --upgrade pip",
            "   " .. py .. " -m pip install demucs soundfile==0.12.1",
            "4) If you see 'TorchCodec is required', run:",
            "   " .. py .. " -m pip install torchcodec",
            "   If TorchCodec still fails to load, this script auto-falls back to MP3 stems.",
            "5) Install FFmpeg and add it to PATH.",
            "   Easy option: winget install Gyan.FFmpeg",
            "6) Restart REAPER and run the script again.",
            "If package install still fails on your Python build, install Python 3.11 and retry."
        }, "\n")
    end

    return table.concat({
        "One-time setup (Mac/Linux):",
        "1) Install Python and FFmpeg.",
        "   Mac: brew install python ffmpeg",
        "   Linux (Ubuntu/Debian): sudo apt update && sudo apt install -y python3 python3-pip ffmpeg",
        "2) Find your Python command in Terminal:",
        "   python3 --version",
        "   python --version",
        "3) Use the command that worked (example shown below):",
        "   " .. py .. " -m pip install --upgrade pip",
        "   " .. py .. " -m pip install demucs soundfile==0.12.1",
        "4) If you see 'TorchCodec is required', run:",
        "   " .. py .. " -m pip install torchcodec",
        "   If TorchCodec still fails to load, this script auto-falls back to MP3 stems.",
        "5) Restart REAPER and run the script again.",
        "If package install still fails on your Python build, install Python 3.11 and retry."
    }, "\n")
end

local function build_setup_message(reason, python_cmd)
    return reason .. "\n\n" .. build_setup_help(python_cmd)
end

local function read_file(path)
    local f = io.open(path, "r")
    if not f then
        return nil
    end
    local data = f:read("*a")
    f:close()
    return data
end

local function write_file(path, content)
    local f = io.open(path, "w")
    if not f then
        return false
    end
    f:write(content)
    f:close()
    return true
end

local function get_last_nonempty_lines(path, max_lines)
    local data = read_file(path)
    if not data or data == "" then
        return ""
    end

    local lines = {}
    for line in data:gmatch("[^\r\n]+") do
        if line and line ~= "" then
            lines[#lines + 1] = line
        end
    end

    if #lines == 0 then
        return ""
    end

    local start_idx = math.max(1, #lines - (max_lines or 20) + 1)
    local out = {}
    for i = start_idx, #lines do
        out[#out + 1] = lines[i]
    end
    return table.concat(out, "\n")
end

local function build_analysis_script(file_path, output_path, work_dir)
    -- This Python script is injected into the runner
    local script = [[
import sys
import os

def run_analysis():
    try:
        # MONKEY PATCH: Fix for old librosa vs new scipy (Missing 'hann')
        import scipy.signal
        if not hasattr(scipy.signal, 'hann'):
            try:
                scipy.signal.hann = scipy.signal.windows.hann
            except AttributeError:
                pass # If this fails, we let it crash naturally later

        import librosa
        import numpy as np
    except ImportError as e:
        # If librosa/numpy missing, just exit gracefully
        with open(r']] .. output_path .. [[', 'w') as f:
            f.write("||")
        with open(r']] .. path_join(work_dir, "analysis_debug.log") .. [[', 'w') as f:
            f.write(f"ImportError: {e}")
        return

    input_path = r']] .. file_path .. [['
    output_path = r']] .. output_path .. [['
    
    # Force utf-8 for output where supported
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding='utf-8')
    
    try:
        # Load 60s for speed
        # If loading fails, just write empty
        y, sr = librosa.load(input_path, sr=None, duration=60)
        
        def to_scalar(x, default=0.0):
            try:
                arr = np.asarray(x)
                if arr.size == 0:
                    return float(default)
                return float(arr.reshape(-1)[0])
            except Exception:
                try:
                    return float(x)
                except Exception:
                    return float(default)

        # 1. BPM
        # Percussive/onset-based tempo is usually more stable than beat_track
        # directly on a full mix with heavy harmonic content.
        y_bpm = librosa.effects.percussive(y)
        onset_env = librosa.onset.onset_strength(y=y_bpm, sr=sr, aggregate=np.median)
        tempo = to_scalar(librosa.feature.tempo(onset_envelope=onset_env, sr=sr, aggregate=np.median), 0.0)
        if tempo <= 0:
            tempo_bt, _ = librosa.beat.beat_track(y=y_bpm, sr=sr)
            tempo = to_scalar(tempo_bt, 0.0)
        if tempo > 0:
            # Resolve the most common half/double-time ambiguity.
            if tempo < 55:
                tempo = tempo * 2.0
            elif tempo > 205:
                tempo = tempo / 2.0
        bpm = int(round(tempo)) if tempo else 0
        
        # 2. Key
        # Simple key detection using chroma
        chroma = librosa.feature.chroma_cqt(y=y, sr=sr)
        chroma_vals = np.sum(chroma, axis=1)
        maj_profile = np.array([6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88])
        min_profile = np.array([6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17])
        
        maj_corrs = []
        min_corrs = []
        for i in range(12):
            maj_corrs.append(np.corrcoef(np.roll(maj_profile, i), chroma_vals)[0, 1])
            min_corrs.append(np.corrcoef(np.roll(min_profile, i), chroma_vals)[0, 1])
            
        key_names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']
        if np.max(maj_corrs) > np.max(min_corrs):
            key = key_names[np.argmax(maj_corrs)]
        else:
            key = key_names[np.argmax(min_corrs)] + "m"
            
        # 3. Tuning (Hz)
        tuning_offset = to_scalar(librosa.estimate_tuning(y=y, sr=sr), 0.0)
        detected_hz = 440 * (2 ** (tuning_offset / 12))
        detected_hz = int(round(detected_hz))
        
        with open(output_path, 'w') as f:
            f.write(f"{bpm}|{key}|{detected_hz}")
            
    except Exception as e:
        with open(r']] .. output_path .. [[', 'w') as f:
            f.write(f"||")
        with open(r']] .. path_join(work_dir, "analysis_debug.log") .. [[', 'w') as f:
            f.write(f"RuntimeError: {e}")

if __name__ == '__main__':
    run_analysis()
]]
    return script
end

local function read_analysis_info(work_dir)
    local info_path = path_join(work_dir, "analysis_info.txt")
    local data = read_file(info_path)
    
    -- Try to read debug log if info is empty or invalid
    if not data or data == "||" or data == "" then 
        local debug_path = path_join(work_dir, "analysis_debug.log")
        local err = read_file(debug_path)
        if err and err ~= "" then
            reaper.ShowConsoleMsg("\n[Analysis Error] " .. err .. "\n")
        end
        return nil 
    end
    
    local parts = {}
    for str in string.gmatch(data, "([^|]+)") do
        table.insert(parts, str)
    end
    
    if #parts >= 3 then
        return {
            bpm = parts[1],
            key = parts[2],
            hz = parts[3]
        }
    end
    return nil
end

local function get_demucs_two_stem_target()
    local stem = normalize_token(DEMUCS_TWO_STEMS_TARGET)
    if stem == "" or stem == "off" then
        return nil
    end
    return stem
end

local function get_active_stem_names()
    local two_stem = get_demucs_two_stem_target()
    if two_stem then
        return { two_stem, "no_" .. two_stem }
    end
    return STEM_NAMES
end

local function get_demucs_quality_args()
    local quality = normalize_token(DEMUCS_QUALITY_PROFILE)
    if quality == "fast" then
        return { "--shifts", "1", "--overlap", "0.1" }, "fast"
    end
    if quality == "high" then
        return { "--shifts", "2", "--overlap", "0.25" }, "high"
    end
    return {}, "balanced"
end

local function build_demucs_static_args()
    local args = {}

    local quality_args = get_demucs_quality_args()
    for i = 1, #quality_args do
        args[#args + 1] = quality_args[i]
    end

    local two_stem = get_demucs_two_stem_target()
    if two_stem then
        args[#args + 1] = "--two-stems"
        args[#args + 1] = two_stem
    end

    local precision = normalize_token(DEMUCS_OUTPUT_PRECISION)
    if precision == "float32" then
        args[#args + 1] = "--float32"
    elseif precision == "int24" then
        args[#args + 1] = "--int24"
    end

    local clip_mode = normalize_token(DEMUCS_CLIP_MODE)
    if clip_mode == "rescale" or clip_mode == "clamp" then
        args[#args + 1] = "--clip-mode"
        args[#args + 1] = clip_mode
    end

    local device = normalize_token(DEMUCS_DEVICE)
    if device == "cpu" or device == "cuda" or device == "mps" then
        args[#args + 1] = "-d"
        args[#args + 1] = device
    end

    local segment_seconds = tonumber(DEMUCS_SEGMENT_SECONDS) or 0
    if segment_seconds > 0 then
        args[#args + 1] = "--segment"
        args[#args + 1] = tostring(math.floor(segment_seconds + 0.5))
    end

    local jobs = tonumber(DEMUCS_JOBS) or 0
    if jobs > 0 then
        args[#args + 1] = "-j"
        args[#args + 1] = tostring(math.floor(jobs + 0.5))
    end

    return table.concat(args, " ")
end

local function build_demucs_command_for_runner(file_path, work_dir, demucs_static_args)
    local filename_template = STEM_OUTPUT_FOLDER .. "/{stem}.{ext}"
    local static_args = tostring(demucs_static_args or "")
    if static_args ~= "" then
        static_args = " " .. static_args .. " "
    else
        static_args = " "
    end

    if IS_WINDOWS then
        return table.concat({
            "!PY_CMD! -m demucs.separate",
            " -n ", MODEL_NAME,
            " --filename ", quote_arg(filename_template),
            static_args,
            " !EXTRA_ARGS! ",
            quote_arg(file_path),
            " -o ", quote_arg(work_dir)
        })
    end

    return table.concat({
        "$PY_CMD -m demucs.separate",
        " -n ", MODEL_NAME,
        " --filename ", quote_arg(filename_template),
        static_args,
        " $EXTRA_ARGS ",
        quote_arg(file_path),
        " -o ", quote_arg(work_dir)
    })
end



local function find_stem_path(stems_dir, stem_name)
    local wav = path_join(stems_dir, stem_name .. ".wav")
    if file_exists(wav) then
        return wav
    end

    local mp3 = path_join(stems_dir, stem_name .. ".mp3")
    if file_exists(mp3) then
        return mp3
    end

    return nil
end

local function resolve_stems_dir(work_dir, song_name)
    local base = path_join(work_dir, MODEL_NAME)
    local candidates = {
        path_join(base, STEM_OUTPUT_FOLDER),
        path_join(base, song_name)
    }
    local primary_stem = get_active_stem_names()[1] or "vocals"

    for _, dir in ipairs(candidates) do
        if find_stem_path(dir, primary_stem) then
            return dir
        end
    end

    return candidates[1]
end

local function set_track_color_rgb(tr, rgb)
    if not AUTO_COLOR_STEM_TRACKS then return end
    if not tr or type(rgb) ~= "table" then return end
    if not reaper.SetTrackColor or not reaper.ColorToNative then return end
    local r = tonumber(rgb[1] or 0) or 0
    local g = tonumber(rgb[2] or 0) or 0
    local b = tonumber(rgb[3] or 0) or 0
    local native = reaper.ColorToNative(r, g, b) + 0x1000000
    reaper.SetTrackColor(tr, native)
end

local function parse_detected_bpm(analysis)
    if type(analysis) ~= "table" then return nil end
    local bpm = tonumber(analysis.bpm or "")
    if not bpm then return nil end
    if bpm < BPM_SET_MIN or bpm > BPM_SET_MAX then return nil end
    return bpm
end

local function apply_project_bpm_from_analysis(analysis)
    if not AUTO_SET_PROJECT_BPM_FROM_ANALYSIS then
        return false, nil, "disabled"
    end
    if not reaper.SetCurrentBPM then
        return false, nil, "api_unavailable"
    end

    local bpm = parse_detected_bpm(analysis)
    if not bpm then
        return false, nil, "invalid_or_out_of_range"
    end

    local ok = reaper.SetCurrentBPM(0, bpm, false)
    if not ok then
        return false, nil, "set_failed"
    end
    if reaper.UpdateTimeline then
        reaper.UpdateTimeline()
    end
    return true, bpm, nil
end

local function import_stems(song_name, pos, stems_dir, analysis)
    reaper.Undo_BeginBlock()
    local active_stems = get_active_stem_names()

    local bpm_applied, bpm_value = apply_project_bpm_from_analysis(analysis)
    if bpm_applied then
        reaper.ShowConsoleMsg(string.format("Set project tempo to %.2f BPM\n", bpm_value))
    end

    local folder_index = reaper.GetNumTracks()
    reaper.InsertTrackAtIndex(folder_index, true)
    local folder_tr = reaper.GetTrack(0, folder_index)
    
    local track_title = "STEMS: " .. song_name
    if analysis and analysis.bpm and analysis.key and analysis.hz then
        track_title = track_title .. " [" .. analysis.bpm .. "bpm " .. analysis.key .. " @" .. analysis.hz .. "Hz]"
    end
    
    reaper.GetSetMediaTrackInfo_String(folder_tr, "P_NAME", track_title, true)
    set_track_color_rgb(folder_tr, STEM_TRACK_COLORS.folder)
    reaper.SetMediaTrackInfo_Value(folder_tr, "I_FOLDERDEPTH", 1)

    reaper.Main_OnCommand(40297, 0)

    for _, stem_name in ipairs(active_stems) do
        local stem_path = find_stem_path(stems_dir, stem_name)
        if stem_path then
            local tr_idx = reaper.GetNumTracks()
            reaper.InsertTrackAtIndex(tr_idx, true)
            local tr = reaper.GetTrack(0, tr_idx)

            local stem_title = string.upper(stem_name)
            if analysis and analysis.bpm and analysis.key and analysis.hz then
                stem_title = stem_title .. " [" .. analysis.bpm .. "bpm " .. analysis.key .. " @" .. analysis.hz .. "Hz]"
            end

            reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", stem_title, true)
            set_track_color_rgb(tr, STEM_TRACK_COLORS[stem_name] or STEM_TRACK_COLORS.other)
            reaper.SetOnlyTrackSelected(tr)
            reaper.SetEditCurPos(pos, false, false)

            local inserted = reaper.InsertMedia(stem_path, 0)
            if inserted then
                -- Since we inserted into a new track, the item is at index 0 of that track
                local new_item = reaper.GetTrackMediaItem(tr, 0)
                if new_item then
                    local new_take = reaper.GetActiveTake(new_item)
                    if new_take then
                        local take_name = song_name
                        if analysis and analysis.bpm and analysis.key and analysis.hz then
                             take_name = take_name .. " (" .. analysis.bpm .. "bpm " .. analysis.key .. " @" .. analysis.hz .. "Hz)"
                        end
                        take_name = take_name .. " - " .. stem_name
                        reaper.GetSetMediaItemTakeInfo_String(new_take, "P_NAME", take_name, true)
                    end
                end
            else
                reaper.ShowConsoleMsg("Error importing: " .. stem_path .. "\n")
            end
        end
    end

    local last_tr = reaper.GetTrack(0, reaper.GetNumTracks() - 1)
    reaper.SetMediaTrackInfo_Value(last_tr, "I_FOLDERDEPTH", -1)

    reaper.Undo_EndBlock("Import AI Stems", -1)
    reaper.UpdateArrange()
end

local function build_windows_runner(work_dir, song_name, file_path, log_path, demucs_static_args)
    local demucs_cmd = build_demucs_command_for_runner(file_path, work_dir, demucs_static_args)
    local probe_path = path_join(work_dir, "torchaudio_write_probe.wav")
    local analysis_script_path = path_join(work_dir, "analyze_audio.py")
    local analysis_output_path = path_join(work_dir, "analysis_info.txt")
    
    local analysis_script_content = build_analysis_script(file_path, analysis_output_path, work_dir)
    write_file(analysis_script_path, analysis_script_content)

    return table.concat({
        "@echo off",
        "setlocal EnableDelayedExpansion",
        "chcp 65001 > nul",
        "set \"CODE=0\"",
        "set \"PY_CMD=\"",
        "set \"EXTRA_ARGS=\"",
        "call :run > " .. quote_arg(log_path) .. " 2>&1",
        "exit /b !CODE!",
        "",
        ":run",
        "echo [preflight] Detecting Python command...",
        "python --version > nul 2>&1 && set \"PY_CMD=python\"",
        "if not defined PY_CMD py -3 --version > nul 2>&1 && set \"PY_CMD=py -3\"",
        "if not defined PY_CMD py --version > nul 2>&1 && set \"PY_CMD=py\"",
        "if not defined PY_CMD python3 --version > nul 2>&1 && set \"PY_CMD=python3\"",
        "if not defined PY_CMD (",
        "  echo [error] No working Python command was found in PATH.",
        "  set \"CODE=11\"",
        "  goto :eof",
        ")",
        "echo [preflight] Using !PY_CMD!",
        "echo [preflight] Checking Python dependencies...",
        "!PY_CMD! -c \"import demucs, torch, torchaudio, soundfile\" > nul 2>&1",
        "if errorlevel 1 (",
        "  echo [error] Demucs dependencies are missing.",
        "  set \"CODE=12\"",
        "  goto :eof",
        ")",
        "echo [preflight] Checking Analysis libraries...",
        "!PY_CMD! -c \"import librosa; v=librosa.__version__.split('.'); assert int(v[0]) > 0 or int(v[1]) >= 10\" > nul 2>&1",
        "if errorlevel 1 (",
        "  echo [preflight] Installing/Upgrading librosa/numpy/scipy from PyPI...",
        "  !PY_CMD! -m pip install --upgrade librosa numpy scipy > nul 2>&1",
        ")",
        "echo [preflight] Checking FFmpeg...",
        "ffmpeg -version > nul 2>&1",
        "if errorlevel 1 (",
        "  echo [error] FFmpeg was not found in PATH.",
        "  set \"CODE=13\"",
        "  goto :eof",
        ")",
        "echo [preflight] Clearing previous output folders...",
        "rmdir /S /Q " .. quote_arg(path_join(path_join(work_dir, MODEL_NAME), STEM_OUTPUT_FOLDER)) .. " > nul 2>&1",
        "rmdir /S /Q " .. quote_arg(path_join(path_join(work_dir, MODEL_NAME), song_name)) .. " > nul 2>&1",
        "echo [preflight] Probing WAV export support...",
        "!PY_CMD! -c \"import os, torch, torchaudio as ta; p='"
            .. escape_python_single_quoted(probe_path)
            .. "'; x=torch.zeros(2, 512); ta.save(p, x, 44100); os.remove(p)\" > nul 2>&1",
        "if errorlevel 1 (",
        "  set \"EXTRA_ARGS=--mp3 --mp3-bitrate 320 --mp3-preset 2\"",
        "  echo [preflight] WAV export probe failed. MP3 stem fallback is active.",
        ")",
        "echo [analysis] Analyzing audio (BPM/Key/Hz)...",
        "!PY_CMD! " .. quote_arg(analysis_script_path),
        "echo [run] Starting Demucs...",
        demucs_cmd,
        "if errorlevel 1 (",
        "  set \"CODE=!ERRORLEVEL!\"",
        "  echo [error] Demucs failed with exit code !CODE!.",
        "  goto :eof",
        ")",
        "echo [ok] Demucs finished.",
        "set \"CODE=0\"",
        "goto :eof",
        ""
    }, "\r\n")
end

local function build_posix_runner(work_dir, song_name, file_path, log_path, demucs_static_args)
    local demucs_cmd = build_demucs_command_for_runner(file_path, work_dir, demucs_static_args)
    local probe_path = path_join(work_dir, "torchaudio_write_probe.wav")
    local old_named = path_join(path_join(work_dir, MODEL_NAME), song_name)
    local old_template = path_join(path_join(work_dir, MODEL_NAME), STEM_OUTPUT_FOLDER)

    local analysis_script_path = path_join(work_dir, "analyze_audio.py")
    local analysis_output_path = path_join(work_dir, "analysis_info.txt")
    local analysis_script_content = build_analysis_script(file_path, analysis_output_path, work_dir)
    write_file(analysis_script_path, analysis_script_content)

    return table.concat({
        "#!/bin/sh",
        "PATH=\"$PATH:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin\"",
        "export PATH",
        "CODE=0",
        "PY_CMD=\"\"",
        "EXTRA_ARGS=\"\"",
        "run() {",
        "  echo \"[preflight] Detecting Python command...\"",
        "  if command -v python3 >/dev/null 2>&1; then PY_CMD=python3; fi",
        "  if [ -z \"$PY_CMD\" ] && command -v python >/dev/null 2>&1; then PY_CMD=python; fi",
        "  if [ -z \"$PY_CMD\" ]; then",
        "    echo \"[error] No working Python command was found in PATH.\"",
        "    CODE=11",
        "    return",
        "  fi",
        "  echo \"[preflight] Using $PY_CMD\"",
        "  echo \"[preflight] Checking Python dependencies...\"",
        "  \"$PY_CMD\" -c \"import demucs, torch, torchaudio, soundfile\" >/dev/null 2>&1",
        "  if [ $? -ne 0 ]; then",
        "    echo \"[error] Demucs dependencies are missing.\"",
        "    CODE=12",
        "    return",
        "  fi",
        "  echo \"[preflight] Checking Analysis libraries...\"",
        "  \"$PY_CMD\" -c \"import librosa; v=librosa.__version__.split('.'); assert int(v[0]) > 0 or int(v[1]) >= 10\" >/dev/null 2>&1",
        "  if [ $? -ne 0 ]; then",
        "    echo \"[preflight] Installing/Upgrading librosa/numpy/scipy (required >= 0.10.0)...\"",
        "    \"$PY_CMD\" -m pip install --upgrade librosa numpy scipy >/dev/null 2>&1",
        "  fi",
        "  echo \"[preflight] Checking FFmpeg...\"",
        "  command -v ffmpeg >/dev/null 2>&1",
        "  if [ $? -ne 0 ]; then",
        "    echo \"[error] FFmpeg was not found in PATH.\"",
        "    CODE=13",
        "    return",
        "  fi",
        "  echo \"[preflight] Clearing previous output folders...\"",
        "  rm -rf " .. quote_arg(old_template) .. " " .. quote_arg(old_named),
        "  echo \"[preflight] Probing WAV export support...\"",
        "  \"$PY_CMD\" -c \"import os, torch, torchaudio as ta; p='"
            .. escape_python_single_quoted(probe_path)
            .. "'; x=torch.zeros(2, 512); ta.save(p, x, 44100); os.remove(p)\" >/dev/null 2>&1",
        "  if [ $? -ne 0 ]; then",
        "    EXTRA_ARGS=\"--mp3 --mp3-bitrate 320 --mp3-preset 2\"",
        "    echo \"[preflight] WAV export probe failed. MP3 stem fallback is active.\"",
        "  fi",
        "  echo \"[analysis] Analyzing audio (BPM/Key/Hz)...\"",
        "  \"$PY_CMD\" " .. quote_arg(analysis_script_path),
        "  echo \"[run] Starting Demucs...\"",
        "  " .. demucs_cmd,
        "  if [ $? -ne 0 ]; then",
        "    CODE=$?",
        "    echo \"[error] Demucs failed with exit code $CODE.\"",
        "    return",
        "  fi",
        "  echo \"[ok] Demucs finished.\"",
        "  CODE=0",
        "}",
        "run > " .. quote_arg(log_path) .. " 2>&1",
        "exit \"$CODE\"",
        ""
    }, "\n")
end

function main()
    local item = reaper.GetSelectedMediaItem(0, 0)
    if not item then
        reaper.ShowMessageBox("Please select an audio clip first.", APP_NAME, 0)
        return
    end

    local take = reaper.GetActiveTake(item)
    if not take then
        reaper.ShowMessageBox("The selected item does not have an active take.", APP_NAME, 0)
        return
    end

    local source = reaper.GetMediaItemTake_Source(take)
    local file_path = reaper.GetMediaSourceFileName(source, "")
    if not file_path or file_path == "" then
        reaper.ShowMessageBox("Could not read source file.", APP_NAME, 0)
        return
    end

    local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local filename_ext = file_path:match(".*[/\\](.*)") or file_path
    local song_name = filename_ext:match("(.+)%.[^%.]+") or filename_ext

    -- Use REAPER persistent Data path to avoid permission issues and allow caching
    local res_path = reaper.GetResourcePath()
    local sep = IS_WINDOWS and "\\" or "/"
    if IS_WINDOWS then
        res_path = res_path:gsub("/", "\\")
    end
    
    local data_path = path_join(res_path, "Data")
    ensure_work_dir(data_path)
    
    local work_dir = path_join(data_path, "AI_Stems_Data")

    local ok, preflight_error = run_preflight(work_dir)
    if not ok then
        reaper.ShowMessageBox(build_setup_message(preflight_error, nil), APP_NAME, 0)
        return
    end

    local log_path = path_join(work_dir, "demucs_last_run.log")
    local runner_ext = IS_WINDOWS and ".cmd" or ".sh"
    local runner_path = path_join(work_dir, "demucs_run" .. runner_ext)
    local launcher_path = path_join(work_dir, "demucs_run.vbs")
    local demucs_static_args = build_demucs_static_args()
    local two_stem = get_demucs_two_stem_target()

    local runner = io.open(runner_path, "w")
    if not runner then
        reaper.ShowMessageBox("Could not create temporary runner file:\n" .. runner_path, APP_NAME, 0)
        return
    end

    if IS_WINDOWS then
        runner:write(build_windows_runner(work_dir, song_name, file_path, log_path, demucs_static_args))
    else
        runner:write(build_posix_runner(work_dir, song_name, file_path, log_path, demucs_static_args))
    end
    runner:close()

    local cmd
    if IS_WINDOWS then
        local launcher = io.open(launcher_path, "w")
        if not launcher then
            os.remove(runner_path)
            reaper.ShowMessageBox("Could not create temporary launcher file:\n" .. launcher_path, APP_NAME, 0)
            return
        end
        launcher:write('Set shell = CreateObject("WScript.Shell")' .. "\r\n")
        launcher:write('code = shell.Run("cmd /C ""' .. escape_vbs_string(runner_path) .. '""", 0, True)' .. "\r\n")
        launcher:write("WScript.Quit code\r\n")
        launcher:close()
        cmd = "wscript //nologo " .. quote_arg(launcher_path)
    else
        cmd = "sh " .. quote_arg(runner_path)
    end

    reaper.ShowConsoleMsg("\n" .. APP_NAME .. "\n")
    reaper.ShowConsoleMsg("OS: " .. reaper.GetOS() .. "\n")
    reaper.ShowConsoleMsg("Demucs profile: " .. normalize_token(DEMUCS_QUALITY_PROFILE) .. "\n")
    if two_stem then
        reaper.ShowConsoleMsg("Two-stem mode: " .. two_stem .. " + no_" .. two_stem .. "\n")
    end
    reaper.ShowConsoleMsg("Running Demucs pipeline on source file...\n")
    reaper.ShowConsoleMsg("Cmd: " .. cmd .. "\n")

    if not command_succeeded(cmd) then
        local tail = get_last_nonempty_lines(log_path, 20)
        local extra = ""
        if tail ~= "" then
            extra = "\n\nLast log lines:\n" .. tail
        end
        if IS_WINDOWS then
            os.remove(launcher_path)
        end
        os.remove(runner_path)
        reaper.ShowMessageBox(
            build_setup_message("Demucs failed to run.\nLog: " .. log_path, nil) .. extra,
            APP_NAME,
            0
        )
        return
    end

    if IS_WINDOWS then
        os.remove(launcher_path)
    end
    os.remove(runner_path)

    local tail = get_last_nonempty_lines(log_path, 8)
    if tail:find("MP3 stem fallback is active", 1, true) then
        reaper.ShowConsoleMsg("WAV export is unavailable in this Python audio stack. Using MP3 stem fallback.\n")
    end

    local stems_dir = resolve_stems_dir(work_dir, song_name)
    local primary_stem = get_active_stem_names()[1] or "vocals"
    local check_file = find_stem_path(stems_dir, primary_stem)
    if not check_file then
        reaper.ShowMessageBox(
            "AI finished, but files were not found.\nSearched path:\n" .. stems_dir,
            APP_NAME,
            0
        )
        return
    end

    reaper.ShowConsoleMsg("Processing finished. Importing tracks...\n")
    
    local analysis = read_analysis_info(work_dir)
    import_stems(song_name, pos, stems_dir, analysis)
    
    reaper.ShowConsoleMsg("Done.\n")
end

main()
