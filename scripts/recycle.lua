local mp = require "mp"
local utils = require "mp.utils"

-- OS 판별: mpv 내장 플랫폼 프로퍼티 사용
local function get_platform()
    local platform = mp.get_property_native("platform")
    if platform then return platform end
    -- 구버전 mpv 대비 fallback
    if os.getenv("windir") then return "windows" end
    return "linux"
end

local function delete_windows(file_path)
    local ps_command = string.format([[
        Add-Type -AssemblyName Microsoft.VisualBasic;
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile('%s', 'OnlyErrorDialogs', 'SendToRecycleBin')
    ]], file_path:gsub("'", "''"))

    return mp.command_native({
        name = "subprocess",
        playback_only = false,
        capture_stdout = true,
        capture_stderr = true,
        args = {"powershell", "-NoProfile", "-Command", ps_command}
    })
end

local function delete_linux(file_path)
    -- 리눅스 민트 Cinnamon은 GLib/GIO 기반 데스크톱(Nemo 파일관리자)이라
    -- freedesktop.org trash 표준을 따르는 `gio trash`가 기본 설치되어 있음.
    return mp.command_native({
        name = "subprocess",
        playback_only = false,
        capture_stdout = true,
        capture_stderr = true,
        args = {"gio", "trash", file_path}
    })
end

local function send_to_recycle_bin()
    local file_path = mp.get_property("path")

    if file_path == nil then
        return
    end

    mp.commandv("playlist-next")

    local platform = get_platform()
    local result

    if platform == "windows" then
        result = delete_windows(file_path)
    else
        result = delete_linux(file_path)
    end

    if result == nil or result.status ~= 0 then
        mp.osd_message("Failed to send to Recycle Bin: " .. (result and result.stderr or "unknown error"))
        return
    end

    mp.osd_message("Sent to Recycle Bin")
end

mp.add_key_binding(nil, "delete-file", send_to_recycle_bin)
