-- keybind-help.lua
-- h 키를 누르면 현재 사용 중인 주요 단축키 목록을 화면에 표시.
-- input.conf 내용을 그대로 반영한 정적 텍스트 (자동 파싱 아님).

local mp = require 'mp'

local HELP_TEXT = table.concat({
    "{\\b1}[ Playback/System ]{\\b0}",
    "SPACE : Play/Pause",
    "F : Toggle Fullscreen",
    "Q : Quit",
    "",
    "{\\b1}[ Seek ]{\\b0}",
    "Left/Right : Seek 5s",
    "Shift+Left/Right : Seek 30s",
    "0-9 : Jump to 0%-90% of duration",
    "</> : Prev/Next Track",
    "",
    "{\\b1}[ Volume ]{\\b0}",
    "Up/Down : Volume +-5",
    "M : Mute",
    "",
    "{\\b1}[ Audio/Subtitle ]{\\b0}",
    "A : Audio Track (but no audio track = no effect)",
    "C : Subtitle Visibility",
    "",
    "{\\b1}[ Misc ]{\\b0}",
    "Shift+DEL : Delete to Recycle Bin",
    "L : Playlist",
    "H : Help",
    "",
    "{\\b1}[ Shortcut Menu ]{\\b0}",
    "/ : Shortcut Menu",
    "Shuffle | Loop Playlist/File/Off | Auto Next On/Off | Subtitle Track |",
    "Color -> Contrast/Brightness/Gamma/Saturation |",
    "Speed -> Speed +-0.1 / x0.5 / x2.0 |",
    "Subtitle Delay -> Sub Delay +-0.1 |",
}, "\\N")

local overlay = mp.create_osd_overlay("ass-events")
local is_open = false

local function show_help()
    mp.commandv("script-message", "overlay-panel-opening", "keybind_help")
    overlay.data = "{\\an7\\pos(40,40)\\fs23\\bord2\\shad1\\c&HFFFFFF&\\3c&H000000&}" .. HELP_TEXT
    overlay:update()
    is_open = true
end

local function hide_help()
    overlay:remove()
    is_open = false
    mp.commandv("script-message", "overlay-panel-closed", "keybind_help")
end

local function toggle_help()
    if is_open then
        hide_help()
    else
        show_help()
    end
end

-- 다른 오버레이 패널(메뉴/플레이리스트)이 열릴 때 이 도움말을 자동으로 닫음
mp.register_script_message("overlay-panel-opening", function(source)
    if source ~= "keybind_help" and is_open then
        hide_help()
    end
end)

mp.add_key_binding(nil, "keybind-help-toggle", toggle_help)
