--[[
    REAPER LOCAL AI ENGINEER (ANTIGRAVITY CORE)
    Role: Professional Audio Separation Engine (High-Fidelity, GUI)

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

local APP_NAME = "AI Stem Splitter by Oliver Tkach (GUI)"
local MODEL_NAME = "htdemucs_6s"
local STEM_OUTPUT_FOLDER = "audio_process"
local STEM_NAMES = {"vocals", "drums", "bass", "guitar", "piano", "other"}

local function get_os_info()
    local os_str = reaper.GetOS()
    local is_windows = os_str:match("Win") ~= nil
    local sep = is_windows and "\\" or "/"
    return is_windows, sep
end

local IS_WINDOWS, SEP = get_os_info()

math.randomseed(os.time())

local ctx = {
    state = "init",
    status = "Initializing...",
    detail = "",
    error_message = nil,
    done_message = nil,
    log_tail = "",
    last_log_poll = 0,
    prev_mouse_down = false,
    request_close = false,
    width = 760,
    height = 500,
}

local function path_join(base, leaf)
    return base .. SEP .. leaf
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

local function build_demucs_command_for_runner(file_path, work_dir)
    local filename_template = STEM_OUTPUT_FOLDER .. "/{stem}.{ext}"
    if IS_WINDOWS then
        return table.concat({
            "!PY_CMD! -m demucs.separate",
            " -n ", MODEL_NAME,
            " --filename ", quote_arg(filename_template),
            " !EXTRA_ARGS! ",
            quote_arg(file_path),
            " -o ", quote_arg(work_dir)
        })
    end

    return table.concat({
        "$PY_CMD -m demucs.separate",
        " -n ", MODEL_NAME,
        " --filename ", quote_arg(filename_template),
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

local function import_stems(song_name, pos, stems_dir)
    reaper.Undo_BeginBlock()

    local folder_index = reaper.GetNumTracks()
    reaper.InsertTrackAtIndex(folder_index, true)
    local folder_tr = reaper.GetTrack(0, folder_index)
    reaper.GetSetMediaTrackInfo_String(folder_tr, "P_NAME", "STEMS: " .. song_name, true)
    reaper.SetMediaTrackInfo_Value(folder_tr, "I_FOLDERDEPTH", 1)

    reaper.Main_OnCommand(40297, 0)

    for _, stem_name in ipairs(STEM_NAMES) do
        local stem_path = find_stem_path(stems_dir, stem_name)
        if stem_path then
            local tr_idx = reaper.GetNumTracks()
            reaper.InsertTrackAtIndex(tr_idx, true)
            local tr = reaper.GetTrack(0, tr_idx)

            reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", string.upper(stem_name), true)
            reaper.SetOnlyTrackSelected(tr)
            reaper.SetEditCurPos(pos, false, false)

            local inserted = reaper.InsertMedia(stem_path, 0)
            if inserted == 1 then
                local new_item = reaper.GetSelectedMediaItem(0, 0)
                if new_item then
                    local new_take = reaper.GetActiveTake(new_item)
                    if new_take then
                        reaper.GetSetMediaItemTakeInfo_String(new_take, "P_NAME", song_name .. " - " .. stem_name, true)
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

local function run_preflight(work_dir)
    if not ensure_work_dir(work_dir) then
        return false, "Could not create temporary work directory:\n" .. work_dir
    end

    if not can_write_dir(work_dir) then
        return false, "Cannot write to temporary work directory:\n" .. work_dir
    end

    return true, nil
end

local function get_last_log_line(path)
    local data = read_file(path)
    if not data or data == "" then
        return ""
    end

    local last = ""
    for line in data:gmatch("[^\r\n]+") do
        if line and line ~= "" then
            last = line
        end
    end
    return last
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

local function resolve_stems_dir(work_dir, song_name)
    local base = path_join(work_dir, MODEL_NAME)
    local candidates = {
        path_join(base, STEM_OUTPUT_FOLDER),
        path_join(base, song_name)
    }

    for _, dir in ipairs(candidates) do
        if find_stem_path(dir, "vocals") then
            return dir
        end
    end

    return candidates[1]
end

local function build_windows_runner_async(work_dir, song_name, file_path, log_path, status_path)
    local demucs_cmd = build_demucs_command_for_runner(file_path, work_dir)
    local probe_path = path_join(work_dir, "torchaudio_write_probe.wav")

    return table.concat({
        "@echo off",
        "setlocal EnableDelayedExpansion",
        "chcp 65001 > nul",
        "set \"CODE=0\"",
        "set \"PY_CMD=\"",
        "set \"EXTRA_ARGS=\"",
        "call :run > " .. quote_arg(log_path) .. " 2>&1",
        "echo !CODE! > " .. quote_arg(status_path),
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

local function build_posix_runner_async(work_dir, song_name, file_path, log_path, status_path)
    local demucs_cmd = build_demucs_command_for_runner(file_path, work_dir)
    local probe_path = path_join(work_dir, "torchaudio_write_probe.wav")
    local old_named = path_join(path_join(work_dir, MODEL_NAME), song_name)
    local old_template = path_join(path_join(work_dir, MODEL_NAME), STEM_OUTPUT_FOLDER)

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
        "echo \"$CODE\" > " .. quote_arg(status_path),
        "exit \"$CODE\"",
        ""
    }, "\n")
end

local function start_demucs_async()
    local run_id = tostring(math.floor(reaper.time_precise() * 1000)) .. "_" .. tostring(math.random(1000, 9999))
    ctx.log_file = path_join(ctx.work_dir, "demucs_" .. run_id .. ".log")
    ctx.status_file = path_join(ctx.work_dir, "demucs_" .. run_id .. ".status")
    ctx.runner_file = path_join(ctx.work_dir, "demucs_" .. run_id .. (IS_WINDOWS and ".cmd" or ".sh"))
    ctx.launcher_file = IS_WINDOWS and path_join(ctx.work_dir, "demucs_" .. run_id .. ".vbs") or nil

    os.remove(ctx.log_file)
    os.remove(ctx.status_file)

    local runner_script
    if IS_WINDOWS then
        runner_script = build_windows_runner_async(ctx.work_dir, ctx.song_name, ctx.file_path, ctx.log_file, ctx.status_file)
    else
        runner_script = build_posix_runner_async(ctx.work_dir, ctx.song_name, ctx.file_path, ctx.log_file, ctx.status_file)
    end

    if not write_file(ctx.runner_file, runner_script) then
        set_error("Could not create temporary runner file:\n" .. ctx.runner_file)
        return
    end

    local launch_cmd
    if IS_WINDOWS then
        local launch_vbs = table.concat({
            'Set shell = CreateObject("WScript.Shell")',
            'shell.Run "cmd /C ""' .. escape_vbs_string(ctx.runner_file) .. '""", 0, False',
            ""
        }, "\r\n")
        if not write_file(ctx.launcher_file, launch_vbs) then
            set_error("Could not create temporary launcher file:\n" .. ctx.launcher_file)
            return
        end
        launch_cmd = "wscript //nologo " .. quote_arg(ctx.launcher_file)
    else
        launch_cmd = "sh " .. quote_arg(ctx.runner_file) .. " >/dev/null 2>&1 &"
    end

    if not command_succeeded(launch_cmd) then
        set_error("Could not launch Demucs process.")
        return
    end

    ctx.started_at = reaper.time_precise()
    ctx.last_log_poll = 0
    set_info("running", "Demucs is processing audio...", "This can take a few minutes.")
end

local function finalize_processing()
    local code_raw = read_file(ctx.status_file) or ""
    local exit_code = tonumber(code_raw:match("(-?%d+)")) or 1

    if exit_code ~= 0 then
        local msg = build_setup_message("Demucs failed to run.", nil)
        local tail = get_last_nonempty_lines(ctx.log_file, 20)
        if ctx.log_file then
            msg = msg .. "\n\nLog file:\n" .. ctx.log_file
        end
        if tail ~= "" then
            msg = msg .. "\n\nLast log lines:\n" .. tail
        end
        set_error(msg)
        return
    end

    local stems_dir = resolve_stems_dir(ctx.work_dir, ctx.song_name)
    local check_file = find_stem_path(stems_dir, "vocals")
    if not check_file then
        local msg = "AI finished, but files were not found.\nSearched path:\n" .. stems_dir
        if ctx.log_file then
            msg = msg .. "\n\nLog file:\n" .. ctx.log_file
        end
        local tail = get_last_nonempty_lines(ctx.log_file, 20)
        if tail ~= "" then
            msg = msg .. "\n\nLast log lines:\n" .. tail
        end
        set_error(msg)
        return
    end

    set_info("importing", "Importing stems into REAPER...", "Please wait.")
    import_stems(ctx.song_name, ctx.pos, stems_dir)

    ctx.done_message = "Processing complete. Stems were imported into your project."
    set_info("done", "Done", "You can close this window.")

    if ctx.runner_file then os.remove(ctx.runner_file) end
    if ctx.launcher_file then os.remove(ctx.launcher_file) end
    if ctx.status_file then os.remove(ctx.status_file) end
end

local function initialize_context()
    local item = reaper.GetSelectedMediaItem(0, 0)
    if not item then
        set_error("Please select an audio clip first.")
        return
    end

    local take = reaper.GetActiveTake(item)
    if not take then
        set_error("The selected item does not have an active take.")
        return
    end

    local source = reaper.GetMediaItemTake_Source(take)
    local file_path = reaper.GetMediaSourceFileName(source, "")
    if not file_path or file_path == "" then
        set_error("Could not read source file.")
        return
    end

    ctx.item = item
    ctx.file_path = file_path
    ctx.pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")

    local filename_ext = file_path:match(".*[/\\](.*)") or file_path
    ctx.song_name = filename_ext:match("(.+)%.[^%.]+") or filename_ext

    local temp_root
    if IS_WINDOWS then
        temp_root = os.getenv("TEMP") or "C:\\Windows\\Temp"
    else
        temp_root = os.getenv("TMPDIR") or "/tmp"
    end
    ctx.work_dir = path_join(temp_root, "AI_Stems_Temp")

    set_info("preflight", "Checking prerequisites...", "Validating temporary folder access.")
    local ok, preflight_error = run_preflight(ctx.work_dir)
    if not ok then
        set_error(build_setup_message(preflight_error, nil))
        return
    end

    set_info("launching", "Launching Demucs...", "Starting one background command process.")
    start_demucs_async()
end

local function wrap_line_to_width(text, max_w)
    local out = {}
    local line = ""

    for word in tostring(text):gmatch("%S+") do
        local candidate = (line == "") and word or (line .. " " .. word)
        local w = gfx.measurestr(candidate)
        if w <= max_w then
            line = candidate
        else
            if line ~= "" then
                out[#out + 1] = line
            end
            line = word
        end
    end

    if line ~= "" then
        out[#out + 1] = line
    end

    if #out == 0 then
        out[1] = ""
    end

    return out
end

local function draw_wrapped_text(text, x, y, max_w, line_h)
    local cy = y
    for raw in tostring(text):gmatch("[^\n]*") do
        if raw == "" then
            gfx.x = x
            gfx.y = cy
            gfx.drawstr("")
            cy = cy + line_h
        else
            local lines = wrap_line_to_width(raw, max_w)
            for _, line in ipairs(lines) do
                gfx.x = x
                gfx.y = cy
                gfx.drawstr(line)
                cy = cy + line_h
            end
        end
    end
    return cy
end

local function draw_button(label, x, y, w, h)
    local mouse_down = (gfx.mouse_cap & 1) == 1
    local hovered = gfx.mouse_x >= x and gfx.mouse_x <= (x + w) and gfx.mouse_y >= y and gfx.mouse_y <= (y + h)

    if hovered then
        gfx.set(0.22, 0.24, 0.28, 1)
    else
        gfx.set(0.16, 0.18, 0.22, 1)
    end
    gfx.rect(x, y, w, h, 1)

    gfx.set(1, 1, 1, 1)
    local tw, th = gfx.measurestr(label)
    gfx.x = x + (w - tw) * 0.5
    gfx.y = y + (h - th) * 0.5
    gfx.drawstr(label)

    local clicked = hovered and mouse_down and (not ctx.prev_mouse_down)
    return clicked, mouse_down
end

local function update_running_state()
    if ctx.state ~= "running" then
        return
    end

    local now = reaper.time_precise()
    if (now - ctx.last_log_poll) > 0.75 then
        ctx.last_log_poll = now
        if ctx.log_file then
            ctx.log_tail = get_last_log_line(ctx.log_file)
            if ctx.log_tail and ctx.log_tail:find("MP3 stem fallback is active", 1, true) then
                if not (ctx.detail or ""):find("MP3 stem fallback is active", 1, true) then
                    ctx.detail = (ctx.detail or "") .. " MP3 stem fallback is active."
                end
            end
        end
    end

    if ctx.status_file and file_exists(ctx.status_file) then
        finalize_processing()
    end
end

local function draw_ui()
    gfx.set(0.08, 0.09, 0.11, 1)
    gfx.rect(0, 0, gfx.w, gfx.h, 1)

    gfx.setfont(1, "Arial", 21)
    gfx.set(0.94, 0.95, 0.98, 1)
    gfx.x = 20
    gfx.y = 16
    gfx.drawstr(APP_NAME)

    gfx.setfont(1, "Arial", 16)
    gfx.set(0.72, 0.82, 0.98, 1)
    gfx.x = 20
    gfx.y = 48
    gfx.drawstr("Status: " .. (ctx.status or ""))

    local detail = ctx.detail or ""
    if ctx.state == "running" and ctx.started_at then
        local elapsed = math.max(0, reaper.time_precise() - ctx.started_at)
        local spinner = {"|", "/", "-", "\\"}
        local idx = (math.floor(elapsed * 6) % #spinner) + 1
        detail = detail .. "\nElapsed: " .. string.format("%.1f", elapsed) .. "s  " .. spinner[idx]
    end

    gfx.setfont(1, "Arial", 14)
    gfx.set(0.88, 0.9, 0.95, 1)
    local y = draw_wrapped_text(detail, 20, 78, gfx.w - 40, 18)

    if ctx.log_file then
        y = y + 8
        gfx.set(0.75, 0.8, 0.9, 1)
        y = draw_wrapped_text("Log: " .. ctx.log_file, 20, y, gfx.w - 40, 18)

        if ctx.log_tail and ctx.log_tail ~= "" then
            y = y + 4
            gfx.set(0.85, 0.9, 1, 1)
            y = draw_wrapped_text("Latest output: " .. ctx.log_tail, 20, y, gfx.w - 40, 18)
        end
    end

    if ctx.error_message then
        y = y + 14
        gfx.set(1, 0.68, 0.68, 1)
        draw_wrapped_text(ctx.error_message, 20, y, gfx.w - 40, 18)
    elseif ctx.done_message then
        y = y + 14
        gfx.set(0.67, 0.96, 0.71, 1)
        draw_wrapped_text(ctx.done_message, 20, y, gfx.w - 40, 18)
    end

    local close_clicked, mouse_down = draw_button("Close", gfx.w - 120, gfx.h - 46, 96, 30)
    if close_clicked then
        ctx.request_close = true
    end

    ctx.prev_mouse_down = mouse_down
end

local function loop()
    if gfx.getchar() < 0 or ctx.request_close then
        return
    end

    update_running_state()
    draw_ui()
    gfx.update()
    reaper.defer(loop)
end

gfx.init(APP_NAME, ctx.width, ctx.height)
initialize_context()
loop()
