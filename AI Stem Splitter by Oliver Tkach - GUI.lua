--[[
    REAPER LOCAL AI ENGINEER (ANTIGRAVITY CORE)
    Role: Professional Audio Separation Engine (Universal V2.0 - Auto-Install)
    Target: Windows, macOS, Linux
    Features: 
    1. Dynamic Python 3.10+ Discovery
    2. Mandatory Path Quoting (Fixes "Me~1" & Spaces)
    3. Auto-Install Dependencies (Demucs, Librosa)
    4. Enhanced FFmpeg Pre-Flight Check
    5. Preserved Music Analysis (BPM, Key, @Hz)

    NOTE:
    Demucs inference cannot run natively inside plain ReaScript Lua.
    This script runs Demucs through an external Python runtime.

    ONE-TIME SETUP (The script now attempts to auto-install dependencies):
    - Windows:
      1) Install Python 3.10+ (recommend 3.12) from python.org.
         IMPORTANT: Check "Add Python to PATH" during installation.
      2) Install FFmpeg: Run 'winget install Gyan.FFmpeg' in Admin Terminal.
      3) RESTART REAPER.

    - macOS:
      1) Install Python 3, pip, and ffmpeg (e.g., brew install python ffmpeg).
      2) RESTART REAPER.

    - Linux:
      1) Install Python 3, pip, and ffmpeg (e.g., sudo apt install python3 python3-pip ffmpeg).
]]

local APP_NAME = "AI Stem Splitter by Oliver Tkach - Version 2.0"
local MODEL_NAME = "htdemucs_6s"
local STEM_OUTPUT_FOLDER = "audio_process"
local STEM_NAMES = {"vocals", "drums", "bass", "guitar", "piano", "other"}
local STEM_TWO_STEM_TARGETS = {"off", "vocals", "drums", "bass", "guitar", "piano", "other"}
local QUALITY_OPTIONS = {"fast", "balanced", "high"}
local PRECISION_OPTIONS = {"default", "float32", "int24"}
local CLIP_MODE_OPTIONS = {"", "rescale", "clamp"}
local DEVICE_OPTIONS = {"auto", "cpu", "cuda", "mps"}
local SEGMENT_OPTIONS = {0, 8, 12, 20}
local JOB_OPTIONS = {0, 2, 4, 8}
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
    local is_mac = os_str:match("OSX") ~= nil
    local is_linux = (not is_windows) and (not is_mac)
    local sep = is_windows and "\\" or "/"
    return is_windows, is_mac, is_linux, sep
end

local IS_WINDOWS, IS_MAC, IS_LINUX, SEP = get_os_info()

math.randomseed(os.time())

local ctx = {
    state = "init",
    status = "Initializing...",
    detail = "",
    error_message = nil,
    done_message = nil,
    log_file = nil,
    status_file = nil,
    runner_file = nil,
    launcher_file = nil,
    log_tail = "",
    last_log_poll = 0,
    prev_mouse_down = false,
    request_close = false,
    width = 760,
    height = 640,
    options = {
        quality_profile = "balanced",
        two_stems_target = "off",
        output_precision = "default",
        clip_mode = "",
        device = "auto",
        segment_seconds = 0,
        jobs = 0,
        auto_color_tracks = true,
        auto_set_project_bpm = true,
        bpm_set_min = 40,
        bpm_set_max = 260,
    },
}

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

-- Strictly quoting arguments for Windows cmd
local function quote_arg_windows(value)
    value = tostring(value or "")
    value = value:gsub('"', '""')
    return '"' .. value .. '"'
end

-- Strictly quoting arguments for Posix sh
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

-- Helper to force backslashes on Windows
local function normalize_win_path(path)
    if not path then return "" end
    return path:gsub("/", "\\")
end

-- Escape for Python -c '...' (single quoted string)
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

local function build_setup_help(python_cmd)
    if IS_WINDOWS then
        return table.concat({
            "One-time setup (Windows):",
            "1) Install Python 3.10+ from python.org.",
            "   IMPORTANT: Check 'Add Python to PATH'.",
            "2) Open Command Prompt, verify 'python --version'.",
            "3) Run:",
            "   pip install demucs soundfile==0.12.1 librosa numpy scipy",
            "4) Install FFmpeg: 'winget install Gyan.FFmpeg'",
            "5) RESTART REAPER."
        }, "\n")
    elseif IS_MAC then
        return table.concat({
            "One-time setup (macOS):",
            "1) Install Python and FFmpeg via Homebrew:",
            "   brew install python ffmpeg",
            "2) Install dependencies:",
            "   python3 -m pip install demucs soundfile==0.12.1 librosa numpy scipy",
            "3) RESTART REAPER."
        }, "\n")
    else
        return table.concat({
            "One-time setup (Linux):",
            "1) Install python3, pip, ffmpeg.",
            "2) pip3 install demucs soundfile==0.12.1 librosa numpy scipy",
        }, "\n")
    end
end

local function build_setup_message(reason, python_cmd)
    return reason .. "\n\n" .. build_setup_help(python_cmd)
end

local function set_error(message)
    ctx.state = "error"
    ctx.status = "Error"
    ctx.error_message = message
end

local function set_info(state, status, detail)
    ctx.state = state
    ctx.status = status
    ctx.detail = detail or ""
end

-- ----------------------------------------------------------------------
-- ANALYSIS SCRIPT GENERATOR
-- ----------------------------------------------------------------------
local function build_analysis_script(file_path, output_path, work_dir, debug_path)
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
                pass 

        import librosa
        import numpy as np
    except ImportError as e:
        # If librosa/numpy missing, just exit gracefully
        with open(r']] .. output_path .. [[', 'w') as f:
            f.write("||")
        with open(r']] .. debug_path .. [[', 'w') as f:
            f.write(f"ImportError: {e}")
        return

    input_path = r']] .. file_path .. [['
    output_path = r']] .. output_path .. [['
    
    # Force utf-8 for output where supported
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding='utf-8')
    
    try:
        # Load 60s for speed
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
        y_bpm = librosa.effects.percussive(y)
        onset_env = librosa.onset.onset_strength(y=y_bpm, sr=sr, aggregate=np.median)
        tempo = to_scalar(librosa.feature.tempo(onset_envelope=onset_env, sr=sr, aggregate=np.median), 0.0)
        if tempo <= 0:
            tempo_bt, _ = librosa.beat.beat_track(y=y_bpm, sr=sr)
            tempo = to_scalar(tempo_bt, 0.0)
        if tempo > 0:
            if tempo < 55:
                tempo = tempo * 2.0
            elif tempo > 205:
                tempo = tempo / 2.0
        bpm = int(round(tempo)) if tempo else 0
        
        # 2. Key
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
        with open(r']] .. debug_path .. [[', 'w') as f:
            f.write(f"RuntimeError: {e}")

if __name__ == '__main__':
    run_analysis()
]]
    return script
end

local function read_analysis_info(work_dir)
    local info_path = path_join(work_dir, "analysis_info.txt")
    local data = read_file(info_path)
    
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

local function get_demucs_two_stem_target(opts)
    local stem = normalize_token((opts and opts.two_stems_target) or "off")
    if stem == "" or stem == "off" then
        return nil
    end
    return stem
end

local function get_active_stem_names(opts)
    local two_stem = get_demucs_two_stem_target(opts)
    if two_stem then
        return { two_stem, "no_" .. two_stem }
    end
    return STEM_NAMES
end

local function get_demucs_quality_args(opts)
    local quality = normalize_token((opts and opts.quality_profile) or "balanced")
    if quality == "fast" then
        return { "--shifts", "1", "--overlap", "0.1" }
    end
    if quality == "high" then
        return { "--shifts", "2", "--overlap", "0.25" }
    end
    return {}
end

local function build_demucs_static_args(opts)
    local args = {}
    local quality_args = get_demucs_quality_args(opts)
    for i = 1, #quality_args do
        args[#args + 1] = quality_args[i]
    end

    local two_stem = get_demucs_two_stem_target(opts)
    if two_stem then
        args[#args + 1] = "--two-stems"
        args[#args + 1] = two_stem
    end

    local precision = normalize_token((opts and opts.output_precision) or "default")
    if precision == "float32" then
        args[#args + 1] = "--float32"
    elseif precision == "int24" then
        args[#args + 1] = "--int24"
    end

    local clip_mode = normalize_token((opts and opts.clip_mode) or "")
    if clip_mode == "rescale" or clip_mode == "clamp" then
        args[#args + 1] = "--clip-mode"
        args[#args + 1] = clip_mode
    end

    local device = normalize_token((opts and opts.device) or "auto")
    if device == "cpu" or device == "cuda" or device == "mps" then
        args[#args + 1] = "-d"
        args[#args + 1] = device
    end

    local segment_seconds = tonumber(opts and opts.segment_seconds or 0) or 0
    if segment_seconds > 0 then
        args[#args + 1] = "--segment"
        args[#args + 1] = tostring(math.floor(segment_seconds + 0.5))
    end

    local jobs = tonumber(opts and opts.jobs or 0) or 0
    if jobs > 0 then
        args[#args + 1] = "-j"
        args[#args + 1] = tostring(math.floor(jobs + 0.5))
    end

    return table.concat(args, " ")
end

local function parse_detected_bpm(analysis, opts)
    if type(analysis) ~= "table" then return nil end
    local bpm = tonumber(analysis.bpm or "")
    if not bpm then return nil end
    local min_bpm = tonumber(opts and opts.bpm_set_min or 40) or 40
    local max_bpm = tonumber(opts and opts.bpm_set_max or 260) or 260
    if bpm < min_bpm or bpm > max_bpm then return nil end
    return bpm
end

local function apply_project_bpm_from_analysis(analysis, opts)
    if not (opts and opts.auto_set_project_bpm) then
        return false, nil, "disabled"
    end
    if not reaper.SetCurrentBPM then
        return false, nil, "api_unavailable"
    end
    local bpm = parse_detected_bpm(analysis, opts)
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

local function set_track_color_rgb(track, rgb, opts)
    if not (opts and opts.auto_color_tracks) then return end
    if not track or type(rgb) ~= "table" then return end
    if not reaper.SetTrackColor or not reaper.ColorToNative then return end
    local r = tonumber(rgb[1] or 0) or 0
    local g = tonumber(rgb[2] or 0) or 0
    local b = tonumber(rgb[3] or 0) or 0
    local native = reaper.ColorToNative(r, g, b) + 0x1000000
    reaper.SetTrackColor(track, native)
end

-- ----------------------------------------------------------------------
-- EXECUTION BUILDERS
-- ----------------------------------------------------------------------

local function build_demucs_command_line(is_win, model, filename_tmpl, file_path, work_dir, demucs_static_args)
    local static_args = tostring(demucs_static_args or "")
    if static_args ~= "" then
        static_args = static_args .. " "
    end

    if is_win then
        -- Windows: Double Quotes for paths
        return table.concat({
            "-m demucs.separate",
            "-n " .. model,
            "--filename \"" .. filename_tmpl .. "\"",
            static_args,
            "!EXTRA_ARGS!",
            "\"" .. file_path .. "\"",
            "-o \"" .. work_dir .. "\""
        }, " ")
    else
        -- POSIX: Single Quoting
        return table.concat({
            "-m demucs.separate",
            "-n " .. model,
            "--filename " .. quote_arg_posix(filename_tmpl),
            static_args,
            "$EXTRA_ARGS",
            quote_arg_posix(file_path),
            "-o " .. quote_arg_posix(work_dir)
        }, " ")
    end
end

local function build_windows_runner_async(work_dir, song_name, file_path, log_path, status_path, opts)
    -- 1. WINDOWS PATH NORMALIZATION (Backslashes)
    local safe_file_path = normalize_win_path(file_path)
    local safe_work_dir = normalize_win_path(work_dir)
    local safe_log = normalize_win_path(log_path)
    local safe_status = normalize_win_path(status_path)
    
    local probe_path = normalize_win_path(path_join(work_dir, "torchaudio_write_probe.wav"))
    local analysis_script = normalize_win_path(path_join(work_dir, "analyze_audio.py"))
    local analysis_output = normalize_win_path(path_join(work_dir, "analysis_info.txt"))
    local analysis_debug = normalize_win_path(path_join(work_dir, "analysis_debug.log"))
    
    -- 2. CREATE ANALYSIS SCRIPT
    local analysis_content = build_analysis_script(safe_file_path, analysis_output, safe_work_dir, analysis_debug)
    write_file(analysis_script, analysis_content)

    -- 3. BUILD DEMUCS ARGS
    local filename_tmpl = STEM_OUTPUT_FOLDER .. "/{stem}.{ext}"
    filename_tmpl = filename_tmpl:gsub("/", "\\")
    local demucs_static_args = build_demucs_static_args(opts)
    local demucs_args = build_demucs_command_line(true, MODEL_NAME, filename_tmpl, safe_file_path, safe_work_dir, demucs_static_args)

    -- 4. BATCH SCRIPT
    return table.concat({
        "@echo off",
        "setlocal EnableDelayedExpansion",
        "chcp 65001 > nul", -- UTF-8 support
        "set \"CODE=0\"",
        "set \"PY_CMD=\"",
        "set \"EXTRA_ARGS=\"",
        "",
        ":: redirect output",
        "call :run > \"" .. safe_log .. "\" 2>&1",
        "echo !CODE! > \"" .. safe_status .. "\"",
        "exit /b !CODE!",
        "",
        ":run",
        "echo [preflight] Searching for Python 3.10+...",
        "",
        ":: DYNAMIC SEARCH LOOP",
        ":: Checks: python, python3, py -3, py",
        "for %%C in (python python3 \"py -3\" py) do (",
        "  if not defined PY_CMD (",
        "    %%~C -c \"import sys; print(sys.version_info[:2] >= (3, 10))\" | findstr \"True\" > nul",
        "    if !errorlevel! equ 0 set \"PY_CMD=%%~C\"",
        "  )",
        ")",
        "",
        "if not defined PY_CMD (",
        "  echo [error] No valid Python 3.10+ found in PATH.",
        "  set \"CODE=11\"",
        "  goto :eof",
        ")",
        "",
        "echo [preflight] Selected Python: !PY_CMD!",
        "",
        "echo [preflight] Verifying Demucs...",
        "\"!PY_CMD!\" -m demucs --help > nul",
        "if errorlevel 1 (",
        "  echo [preflight] Demucs not found. Attempting AUTO-INSTALL...",
        "  echo [install] Installing demucs soundfile librosa numpy scipy...",
        "  \"!PY_CMD!\" -m pip install demucs soundfile==0.12.1 librosa numpy scipy > nul 2>&1",
        "  if errorlevel 1 (",
        "    echo [error] Auto-install failed.",
        "    echo [hint] Please run manually: pip install demucs soundfile librosa numpy scipy",
        "    set \"CODE=12\"",
        "    goto :eof",
        "  )",
        "  echo [install] Installation successful.",
        ")",
        "",
        "echo [preflight] Checking FFmpeg...",
        "ffmpeg -version > nul 2>&1",
        "if errorlevel 1 (",
        "  echo [error] FFmpeg not found in PATH.",
        "  echo [hint] Please run: winget install Gyan.FFmpeg in ADMIN terminal and RESTART REAPER.",
        "  set \"CODE=13\"",
        "  goto :eof",
        ")",
        "",
        "echo [preflight] Clearing old stems...",
        "rmdir /S /Q \"" .. normalize_win_path(path_join(path_join(work_dir, MODEL_NAME), STEM_OUTPUT_FOLDER)) .. "\" > nul 2>&1",
        "rmdir /S /Q \"" .. normalize_win_path(path_join(path_join(work_dir, MODEL_NAME), song_name)) .. "\" > nul 2>&1",
        "",
        "echo [preflight] Probing export...",
        "\"!PY_CMD!\" -c \"import os, torch, torchaudio as ta; p=r'" .. probe_path .. "'; x=torch.zeros(2, 512); ta.save(p, x, 44100); os.remove(p)\" > nul 2>&1",
        "if errorlevel 1 (",
        "  set \"EXTRA_ARGS=--mp3 --mp3-bitrate 320\"",
        "  echo [info] WAV export unavailable. Fallback to MP3.",
        ")",
        "",
        "echo [analysis] Analyzing audio...",
        "\"!PY_CMD!\" \"" .. analysis_script .. "\"",
        "",
        "echo [run] Running Demucs...",
        ":: STRICT QUOTING for Execution",
        "\"!PY_CMD!\" " .. demucs_args,
        "",
        "if errorlevel 1 (",
        "  set \"CODE=!ERRORLEVEL!\"",
        "  echo [error] Demucs failed.",
        "  goto :eof",
        ")",
        "",
        "echo [ok] Processing finished.",
        "set \"CODE=0\"",
        "goto :eof"
    }, "\r\n")
end

local function build_linux_runner_async(work_dir, song_name, file_path, log_path, status_path, opts)
    -- POSIX runner (macOS/Linux)
    local analysis_script = path_join(work_dir, "analyze_audio.py")
    local analysis_output = path_join(work_dir, "analysis_info.txt")
    local analysis_debug = path_join(work_dir, "analysis_debug.log")
    
    local analysis_content = build_analysis_script(file_path, analysis_output, work_dir, analysis_debug)
    write_file(analysis_script, analysis_content)

    local filename_tmpl = STEM_OUTPUT_FOLDER .. "/{stem}.{ext}"
    local demucs_static_args = build_demucs_static_args(opts)
    local demucs_args = build_demucs_command_line(false, MODEL_NAME, filename_tmpl, file_path, work_dir, demucs_static_args)
    
    local probe_path = path_join(work_dir, "torchaudio_write_probe.wav")
    local old_template = path_join(path_join(work_dir, MODEL_NAME), STEM_OUTPUT_FOLDER)
    local old_named = path_join(path_join(work_dir, MODEL_NAME), song_name)

    return table.concat({
        "#!/bin/sh",
        "PATH=\"$PATH:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin\"",
        "export PATH",
        "CODE=0",
        "PY_CMD=\"\"",
        "EXTRA_ARGS=\"\"",
        "run() {",
        "  echo \"[preflight] Searching for Python 3.10+...\"",
        "  for cmd in python3 python; do",
        "    if command -v $cmd >/dev/null 2>&1; then",
        "       $cmd -c \"import sys; print(sys.version_info[:2] >= (3, 10))\" | grep \"True\" >/dev/null 2>&1",
        "       if [ $? -eq 0 ]; then",
        "         PY_CMD=$cmd",
        "         break",
        "       fi",
        "    fi",
        "  done",
        "",
        "  if [ -z \"$PY_CMD\" ]; then",
        "    echo \"[error] No Python 3.10+ found.\"",
        "    CODE=11",
        "    return",
        "  fi",
        "  echo \"[preflight] Using Python: $PY_CMD\"",
        "",
        "  echo \"[preflight] Checking Demucs...\"",
        "  \"$PY_CMD\" -m demucs --help >/dev/null 2>&1",
        "  if [ $? -ne 0 ]; then",
        "    echo \"[preflight] Demucs missing. Auto-installing...\"",
        "    \"$PY_CMD\" -m pip install demucs soundfile==0.12.1 librosa numpy scipy >/dev/null 2>&1",
        "    if [ $? -ne 0 ]; then",
        "      echo \"[error] Auto-install failed.\"",
        "      CODE=12",
        "      return",
        "    fi",
        "  fi",
        "",
        "  echo \"[preflight] Checking FFmpeg...\"",
        "  command -v ffmpeg >/dev/null 2>&1",
        "  if [ $? -ne 0 ]; then",
        "    echo \"[error] FFmpeg not found.\"",
        "    CODE=13",
        "    return",
        "  fi",
        "",
        "  echo \"[preflight] Cleaning...\"",
        "  rm -rf " .. quote_arg_posix(old_template) .. " " .. quote_arg_posix(old_named),
        "",
        "  echo \"[preflight] Probing export...\"",
        "  \"$PY_CMD\" -c \"import os, torch, torchaudio as ta; p='" .. escape_python_single_quoted(probe_path) .. "'; x=torch.zeros(2, 512); ta.save(p, x, 44100); os.remove(p)\" >/dev/null 2>&1",
        "  if [ $? -ne 0 ]; then",
        "    EXTRA_ARGS=\"--mp3 --mp3-bitrate 320\"",
        "    echo \"[info] WAV export unavailable. Fallback to MP3.\"",
        "  fi",
        "",
        "  echo \"[analysis] Analyzing audio...\"",
        "  \"$PY_CMD\" " .. quote_arg_posix(analysis_script),
        "",
        "  echo \"[run] Running Demucs...\"",
        "  \"$PY_CMD\" " .. demucs_args,
        "  if [ $? -ne 0 ]; then",
        "    CODE=$?",
        "    echo \"[error] Demucs failed.\"",
        "    return",
        "  fi",
        "  echo \"[ok] Done.\"",
        "  CODE=0",
        "}",
        "run > " .. quote_arg_posix(log_path) .. " 2>&1",
        "echo \"$CODE\" > " .. quote_arg_posix(status_path),
        "exit \"$CODE\"",
        ""
    }, "\n")
end

local function start_demucs_async(opts)
    local run_id = tostring(math.floor(reaper.time_precise() * 1000)) .. "_" .. tostring(math.random(1000, 9999))
    ctx.log_file = path_join(ctx.work_dir, "demucs_" .. run_id .. ".log")
    ctx.status_file = path_join(ctx.work_dir, "demucs_" .. run_id .. ".status")
    
    os.remove(ctx.log_file)
    os.remove(ctx.status_file)
    
    ctx.done_message = nil
    ctx.error_message = nil
    ctx.log_tail = ""

    local runner_script
    local launch_cmd
    
    if IS_WINDOWS then
        ctx.runner_file = path_join(ctx.work_dir, "demucs_" .. run_id .. ".cmd")
        ctx.launcher_file = path_join(ctx.work_dir, "demucs_" .. run_id .. ".vbs")
        
        runner_script = build_windows_runner_async(ctx.work_dir, ctx.song_name, ctx.file_path, ctx.log_file, ctx.status_file, opts)
        
        local launch_vbs = table.concat({
            'Set shell = CreateObject("WScript.Shell")',
            'shell.Run "cmd /C ""' .. escape_vbs_string(ctx.runner_file) .. '""", 0, False',
            ""
        }, "\r\n")
        
        write_file(ctx.launcher_file, launch_vbs)
        launch_cmd = "wscript //nologo " .. quote_arg_windows(ctx.launcher_file)
    else
        ctx.runner_file = path_join(ctx.work_dir, "demucs_" .. run_id .. ".sh")
        ctx.launcher_file = nil
        
        runner_script = build_linux_runner_async(ctx.work_dir, ctx.song_name, ctx.file_path, ctx.log_file, ctx.status_file, opts)
        
        launch_cmd = "sh " .. quote_arg_posix(ctx.runner_file) .. " >/dev/null 2>&1 &"
    end

    if not write_file(ctx.runner_file, runner_script) then
        set_error("Could not write runner script:\n" .. ctx.runner_file)
        return
    end

    if not command_succeeded(launch_cmd) then
        set_error("Failed to launch process.")
        return
    end

    ctx.started_at = reaper.time_precise()
    ctx.last_log_poll = 0
    local two_stem = get_demucs_two_stem_target(opts)
    local detail = "Using external Python environment. Profile: " .. tostring(opts.quality_profile or "balanced")
    if two_stem then
        detail = detail .. ", Two-stem: " .. two_stem
    end
    set_info("running", "Processing...", detail)
end

local function find_stem_path(stems_dir, stem_name)
    local wav = path_join(stems_dir, stem_name .. ".wav")
    if file_exists(wav) then return wav end
    local mp3 = path_join(stems_dir, stem_name .. ".mp3")
    if file_exists(mp3) then return mp3 end
    return nil
end

local function resolve_stems_dir(work_dir, song_name, opts)
    local base = path_join(work_dir, MODEL_NAME)
    local candidates = {
        path_join(base, STEM_OUTPUT_FOLDER),
        path_join(base, song_name)
    }
    local primary_stem = get_active_stem_names(opts)[1] or "vocals"
    for _, dir in ipairs(candidates) do
        if find_stem_path(dir, primary_stem) then return dir end
    end
    return candidates[1]
end

local function import_stems(song_name, pos, stems_dir, analysis, opts)
    reaper.Undo_BeginBlock()
    local active_stems = get_active_stem_names(opts)

    local bpm_applied, bpm_value = apply_project_bpm_from_analysis(analysis, opts)
    if bpm_applied then
        reaper.ShowConsoleMsg(string.format("Set project tempo to %.2f BPM\n", bpm_value))
    end
    
    local folder_index = reaper.GetNumTracks()
    reaper.InsertTrackAtIndex(folder_index, true)
    local folder_tr = reaper.GetTrack(0, folder_index)
    
    local title = "STEMS: " .. song_name
    if analysis then
        title = title .. " [" .. analysis.bpm .. "bpm " .. analysis.key .. " @" .. analysis.hz .. "Hz]"
    end
    reaper.GetSetMediaTrackInfo_String(folder_tr, "P_NAME", title, true)
    set_track_color_rgb(folder_tr, STEM_TRACK_COLORS.folder, opts)
    reaper.SetMediaTrackInfo_Value(folder_tr, "I_FOLDERDEPTH", 1)
    
    reaper.Main_OnCommand(40297, 0) -- Unselect all
    
    for _, stem_name in ipairs(active_stems) do
        local path = find_stem_path(stems_dir, stem_name)
        if path then
            local idx = reaper.GetNumTracks()
            reaper.InsertTrackAtIndex(idx, true)
            local tr = reaper.GetTrack(0, idx)
            local stem_title = string.upper(stem_name)
            
            reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", stem_title, true)
            set_track_color_rgb(tr, STEM_TRACK_COLORS[stem_name] or STEM_TRACK_COLORS.other, opts)
            reaper.SetOnlyTrackSelected(tr)
            reaper.SetEditCurPos(pos, false, false)
            
            if reaper.InsertMedia(path, 0) then
                local item = reaper.GetTrackMediaItem(tr, 0)
                if item then
                    local take = reaper.GetActiveTake(item)
                    if take then
                         local take_name = song_name .. " - " .. stem_name
                         reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", take_name, true)
                    end
                end
            end
        end
    end
    
    local last = reaper.GetTrack(0, reaper.GetNumTracks()-1)
    reaper.SetMediaTrackInfo_Value(last, "I_FOLDERDEPTH", -1)
    
    reaper.Undo_EndBlock("Import AI Stems", -1)
    reaper.UpdateArrange()
end

local function get_last_nonempty_lines(path, max_lines)
    local data = read_file(path)
    if not data or data == "" then return "" end
    local lines = {}
    for line in data:gmatch("[^\r\n]+") do
        if line and line ~= "" then lines[#lines+1] = line end
    end
    if #lines == 0 then return "" end
    local start = math.max(1, #lines - (max_lines or 20) + 1)
    local out = {}
    for i=start, #lines do out[#out+1] = lines[i] end
    return table.concat(out, "\n")
end

local function get_last_line(path)
    local data = read_file(path)
    if not data or data == "" then return "" end
    local last = ""
    for line in data:gmatch("[^\r\n]+") do
        if line and line ~= "" then last = line end
    end
    return last
end

local function finalize_processing()
    local code_raw = read_file(ctx.status_file) or ""
    local exit_code = tonumber(code_raw:match("(-?%d+)")) or 1

    if exit_code ~= 0 then
        local msg = "Demucs failed (Code " .. exit_code .. ")."
        local tail = get_last_nonempty_lines(ctx.log_file, 15)
        if tail ~= "" then msg = msg .. "\n\nLog tail:\n" .. tail end
        
        if exit_code == 11 then
            msg = build_setup_message("No Python 3.10+ found.", nil)
        elseif exit_code == 12 then
            msg = build_setup_message("Dependencies missing (demucs/librosa).", nil)
        elseif exit_code == 13 then
            if IS_WINDOWS then
                msg = build_setup_message("FFmpeg missing. Run in ADMIN cmd:\nwinget install Gyan.FFmpeg\nThen Restart REAPER.", nil)
            elseif IS_MAC then
                msg = build_setup_message("FFmpeg missing. Run in Terminal:\nbrew install ffmpeg\nThen Restart REAPER.", nil)
            else
                msg = build_setup_message("FFmpeg missing. Install ffmpeg with your package manager, then restart REAPER.", nil)
            end
        end
        
        set_error(msg)
        return
    end

    local stems_dir = resolve_stems_dir(ctx.work_dir, ctx.song_name, ctx.options)
    local primary_stem = get_active_stem_names(ctx.options)[1] or "vocals"
    if not find_stem_path(stems_dir, primary_stem) then
        set_error("Finished but no stems found at:\n" .. stems_dir)
        return
    end

    set_info("importing", "Importing...", "Please wait.")
    local analysis = read_analysis_info(ctx.work_dir)
    import_stems(ctx.song_name, ctx.pos, stems_dir, analysis, ctx.options)

    ctx.done_message = "Done. Stems imported."
    set_info("done", "Done", "You can close this window.")
    
    if ctx.runner_file then os.remove(ctx.runner_file) end
    if ctx.launcher_file then os.remove(ctx.launcher_file) end
    if ctx.status_file then os.remove(ctx.status_file) end
end

local function update_running_state()
    if ctx.state ~= "running" then return end
    
    local now = reaper.time_precise()
    if (now - ctx.last_log_poll) > 0.75 then
        ctx.last_log_poll = now
        if ctx.log_file then
            ctx.log_tail = get_last_line(ctx.log_file)
            if ctx.log_tail and ctx.log_tail:find("Fallback to MP3", 1, true) then
                if not (ctx.detail or ""):find("MP3", 1, true) then
                    ctx.detail = (ctx.detail or "") .. " (MP3 Mode)"
                end
            end
        end
    end
    
    if ctx.status_file and file_exists(ctx.status_file) then
        finalize_processing()
    end
end

local function initialize_context()
    local item = reaper.GetSelectedMediaItem(0, 0)
    if not item then
        set_error("Select an audio item first.")
        return
    end
    local take = reaper.GetActiveTake(item)
    if not take then set_error("No active take.") return end
    local src_path = reaper.GetMediaSourceFileName(reaper.GetMediaItemTake_Source(take), "")
    if not src_path or src_path == "" then set_error("Bad source file.") return end

    ctx.item = item
    ctx.file_path = src_path
    ctx.pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    
    local name = src_path:match(".*[/\\](.*)") or src_path
    ctx.song_name = name:match("(.+)%.[^%.]+") or name

    local res_path = reaper.GetResourcePath() -- Get Reaper path
    if IS_WINDOWS then res_path = res_path:gsub("/", "\\") end
    
    local work_dir = path_join(path_join(res_path, "Data"), "AI_Stems_Data")
    ensure_work_dir(work_dir)
    
    if not can_write_dir(work_dir) then
        set_error("Cannot write to:\n" .. work_dir)
        return
    end
    
    ctx.work_dir = work_dir
    set_info("ready", "Ready", "Review options below, then click Start.")
end

-- GUI
local function wrap_text(text, max_w)
    local out = {}
    local line = ""
    for word in tostring(text):gmatch("%S+") do
        local cand = (line == "") and word or (line .. " " .. word)
        if gfx.measurestr(cand) <= max_w then line = cand
        else
            if line ~= "" then out[#out+1] = line end
            line = word
        end
    end
    if line ~= "" then out[#out+1] = line end
    return out
end

local function point_in_rect(px, py, x, y, w, h)
    return px >= x and px <= (x + w) and py >= y and py <= (y + h)
end

local function draw_button(x, y, w, h, label, mouse_clicked)
    local hover = point_in_rect(gfx.mouse_x, gfx.mouse_y, x, y, w, h)
    if hover then
        gfx.set(0.36, 0.36, 0.36, 1)
    else
        gfx.set(0.26, 0.26, 0.26, 1)
    end
    gfx.rect(x, y, w, h, 1)
    gfx.set(1, 1, 1, 1)
    local tw, th = gfx.measurestr(label)
    gfx.x = x + (w - tw) / 2
    gfx.y = y + (h - th) / 2
    gfx.drawstr(label)
    return mouse_clicked and hover
end

local function cycle_value(current, list)
    if type(list) ~= "table" or #list == 0 then return current end
    for i = 1, #list do
        if tostring(list[i]) == tostring(current) then
            return list[(i % #list) + 1]
        end
    end
    return list[1]
end

local function format_clip_mode(value)
    local v = tostring(value or "")
    if v == "" then return "default" end
    return v
end

local function draw_gui()
    local mouse_down = (gfx.mouse_cap & 1) == 1
    local mouse_clicked = mouse_down and not ctx.prev_mouse_down

    gfx.set(0.08, 0.09, 0.11, 1)
    gfx.rect(0, 0, gfx.w, gfx.h, 1)

    gfx.setfont(1, "Arial", 20)
    gfx.set(0.9, 0.9, 0.9, 1)
    gfx.x, gfx.y = 20, 20
    gfx.drawstr(APP_NAME)
    
    gfx.setfont(1, "Arial", 16)
    gfx.set(0.7, 0.8, 1, 1)
    gfx.x, gfx.y = 20, 50
    gfx.drawstr("Status: " .. (ctx.status or ""))

    local y = 80
    gfx.setfont(1, "Arial", 14)
    gfx.set(0.75, 0.75, 0.75, 1)
    gfx.x, gfx.y = 20, y
    gfx.drawstr("Source: " .. tostring(ctx.song_name or "<none>"))
    y = y + 20

    gfx.set(0.8, 0.8, 0.8, 1)
    if ctx.detail and ctx.detail ~= "" then
        for _, l in ipairs(wrap_text(ctx.detail, gfx.w - 40)) do
            gfx.x, gfx.y = 20, y
            gfx.drawstr(l)
            y = y + 16
        end
    end

    if ctx.log_tail and ctx.log_tail ~= "" then
        y = y + 10
        gfx.set(0.5, 0.5, 0.5, 1)
        gfx.x, gfx.y = 20, y
        gfx.drawstr("Log: " .. ctx.log_tail)
        y = y + 16
    end

    if ctx.work_dir and ctx.file_path and ctx.state ~= "running" and ctx.state ~= "importing" then
        y = y + 14
        gfx.set(0.75, 0.85, 1, 1)
        gfx.x, gfx.y = 20, y
        gfx.drawstr("Options")
        y = y + 24

        local row_h = 28
        local label_x = 20
        local btn_x = 320
        local btn_w = 220
        local btn_h = 22

        local function option_row(label, value_text, on_click)
            gfx.set(0.84, 0.84, 0.84, 1)
            gfx.x, gfx.y = label_x, y + 3
            gfx.drawstr(label)
            if draw_button(btn_x, y, btn_w, btn_h, value_text, mouse_clicked) then
                on_click()
            end
            y = y + row_h
        end

        option_row("Quality profile", tostring(ctx.options.quality_profile), function()
            ctx.options.quality_profile = cycle_value(ctx.options.quality_profile, QUALITY_OPTIONS)
        end)

        option_row("Two-stem mode", tostring(ctx.options.two_stems_target), function()
            ctx.options.two_stems_target = cycle_value(ctx.options.two_stems_target, STEM_TWO_STEM_TARGETS)
        end)

        option_row("Output precision", tostring(ctx.options.output_precision), function()
            ctx.options.output_precision = cycle_value(ctx.options.output_precision, PRECISION_OPTIONS)
        end)

        option_row("Clip mode", format_clip_mode(ctx.options.clip_mode), function()
            ctx.options.clip_mode = cycle_value(ctx.options.clip_mode, CLIP_MODE_OPTIONS)
        end)

        option_row("Device", tostring(ctx.options.device), function()
            ctx.options.device = cycle_value(ctx.options.device, DEVICE_OPTIONS)
        end)

        option_row("Segment seconds", tostring(ctx.options.segment_seconds), function()
            ctx.options.segment_seconds = cycle_value(ctx.options.segment_seconds, SEGMENT_OPTIONS)
        end)

        option_row("Jobs", tostring(ctx.options.jobs), function()
            ctx.options.jobs = cycle_value(ctx.options.jobs, JOB_OPTIONS)
        end)

        option_row("Auto set project BPM", ctx.options.auto_set_project_bpm and "on" or "off", function()
            ctx.options.auto_set_project_bpm = not ctx.options.auto_set_project_bpm
        end)

        option_row("Auto color stem tracks", ctx.options.auto_color_tracks and "on" or "off", function()
            ctx.options.auto_color_tracks = not ctx.options.auto_color_tracks
        end)

        local start_x, start_y, start_w, start_h = 20, gfx.h - 90, 180, 34
        if draw_button(start_x, start_y, start_w, start_h, "Start Split", mouse_clicked) then
            start_demucs_async(ctx.options)
        end
    end

    if ctx.error_message then
        y = y + 10
        gfx.set(1, 0.4, 0.4, 1)
        for _, l in ipairs(wrap_text(ctx.error_message, gfx.w - 40)) do
            gfx.x, gfx.y = 20, y
            gfx.drawstr(l)
            y = y + 16
        end
    elseif ctx.done_message then
        y = y + 10
        gfx.set(0.4, 1, 0.4, 1)
        gfx.x, gfx.y = 20, y
        gfx.drawstr(ctx.done_message)
    end

    -- Close button
    local bw, bh = 80, 30
    local bx, by = gfx.w - bw - 20, gfx.h - bh - 20
    if draw_button(bx, by, bw, bh, "Close", mouse_clicked) then
        ctx.request_close = true
    end

    ctx.prev_mouse_down = mouse_down
end

local function loop()
    if gfx.getchar() < 0 or ctx.request_close then return end
    update_running_state()
    draw_gui()
    gfx.update()
    reaper.defer(loop)
end

gfx.init(APP_NAME, ctx.width, ctx.height)
initialize_context()
loop()
