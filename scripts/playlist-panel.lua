-- playlist-panel.lua
-- l 키로 현재 재생목록을 실시간(동적)으로 보여주는 오버레이.
-- playlist 속성이 바뀔 때마다(재생목록 추가/삭제/순서변경/셔플 등) 자동 갱신됨.
-- 열려 있는 동안 Up/Down으로 커서를 움직여 탐색하고, ENTER로 해당 항목을 재생할 수 있음.
-- 패널을 다시 열면 커서는 항상 현재 재생 중인 트랙 위치로 리셋됨.

local mp = require 'mp'
local utils = require 'mp.utils'

local overlay = mp.create_osd_overlay("ass-events")
local is_open = false
local cursor = 1  -- 현재 커서(탐색 위치)의 playlist 인덱스

-- 파일명을 ASS 오버레이 텍스트에 그대로 넣으면, 파일명에 포함된 '{', '}', '\'가
-- ASS 오버라이드 태그 문법(예: {\c...}, {tag})으로 오인되어 해당 부분이 화면에서
-- 사라지거나 이후 줄의 스타일까지 깨지는 문제가 있다 (실제 재현 확인됨: 파일명
-- "video{with}braces.mp4"에서 "with"가 렌더링 시 사라짐).
-- ASS 포맷 자체에는 이 문자들을 리터럴로 표시할 공식 이스케이프 문법이 없으므로,
-- 시각적으로 유사한 전각(fullwidth) 문자로 치환해 원래 문자를 최대한 그대로
-- 알아볼 수 있게 하면서 ASS 파서가 오버라이드 태그로 오인하지 않도록 한다.
local function sanitize_for_ass(text)
    text = text:gsub("\\", "＼")  -- U+FF3C FULLWIDTH REVERSE SOLIDUS
    text = text:gsub("{", "｛")   -- U+FF5B FULLWIDTH LEFT CURLY BRACKET
    text = text:gsub("}", "｝")   -- U+FF5D FULLWIDTH RIGHT CURLY BRACKET
    return text
end

-- bind_nav_keys/unbind_nav_keys는 move_cursor/play_at_cursor 정의 이후
-- (파일 하단)에서 값이 채워지지만, 그보다 앞에 있는 open_panel/close_panel이
-- 이 이름들을 먼저 호출해야 하므로 여기서 local로 선언만 해둔다.
-- (나중에 `local function`으로 다시 선언하면 별개의 지역변수가 되어 여기서
-- 캡처한 upvalue가 nil로 남는 버그가 생기므로, 아래에서는 반드시
-- `bind_nav_keys = function...` 형태로 값만 채울 것.)
local bind_nav_keys
local unbind_nav_keys

-- 화면에 한번에 보여줄 항목 수 (위/아래 합쳐서). 파일이 많을 때 커서 위치가
-- 항상 보이도록, 전체 목록 대신 커서 주변만 스크롤 윈도우로 표시함.
local WINDOW_SIZE = 15

local function get_current_index(playlist)
    for i, item in ipairs(playlist) do
        if item.current then
            return i
        end
    end
    return 1
end

local function render_playlist()
    if not is_open then return end

    local playlist = mp.get_property_native("playlist") or {}
    local total = #playlist
    if cursor > total then cursor = total end
    if cursor < 1 then cursor = 1 end

    -- 커서가 가운데쯤 오도록 윈도우 범위 계산
    local half = math.floor(WINDOW_SIZE / 2)
    local start_i = math.max(1, cursor - half)
    local end_i = math.min(total, start_i + WINDOW_SIZE - 1)
    start_i = math.max(1, end_i - WINDOW_SIZE + 1)

    local lines = {}
    table.insert(lines, string.format("{\\b1}[ Playlist %d/%d ]{\\b0}", cursor, total))
    if start_i > 1 then
        table.insert(lines, "  ...")
    end
    for i = start_i, end_i do
        local item = playlist[i]
        local name = item.filename or "?"
        name = name:match("([^\\/]+)$") or name
        name = sanitize_for_ass(name)

        local number_and_name = string.format("%d. %s", i, name)
        -- 재생 중인 곡: []로 감싸서 표시. 커서 위치: ">"로 표시.
        -- (요청에 따라 기존 표기를 서로 맞바꿈)
        local body = item.current
            and string.format("[ %s ]", number_and_name)
            or number_and_name

        if i == cursor then
            -- 커서 위치는 ">" + 색상 강조로 표시 (재생 중인 트랙과는 별개로 구분됨)
            table.insert(lines, string.format("{\\c&H00D7FF&}> %s{\\c}", body))
        elseif item.current then
            table.insert(lines, string.format("{\\c&H00FF00&}  %s{\\c}", body))
        else
            table.insert(lines, "  " .. body)
        end
    end
    if end_i < total then
        table.insert(lines, "  ...")
    end

    overlay.data = string.format(
        "{\\an7\\pos(40,40)\\fs23\\bord2\\shad1\\c&HFFFFFF&\\3c&H000000&}%s",
        table.concat(lines, "\\N")
    )
    overlay:update()
end

local function open_panel()
    mp.commandv("script-message", "overlay-panel-opening", "playlist_panel")
    is_open = true
    -- 열 때마다 커서를 현재 재생 중인 트랙 위치로 리셋
    local playlist = mp.get_property_native("playlist") or {}
    cursor = get_current_index(playlist)
    bind_nav_keys()
    render_playlist()
end

local function close_panel()
    is_open = false
    overlay:remove()
    unbind_nav_keys()
    mp.commandv("script-message", "overlay-panel-closed", "playlist_panel")
end

local function toggle_panel()
    if is_open then
        close_panel()
    else
        open_panel()
    end
end

local function move_cursor(delta)
    if not is_open then return end
    local total = #(mp.get_property_native("playlist") or {})
    if total == 0 then return end
    cursor = cursor + delta
    if cursor < 1 then cursor = total end
    if cursor > total then cursor = 1 end
    render_playlist()
end

local function play_at_cursor()
    if not is_open then return end
    local playlist = mp.get_property_native("playlist") or {}
    if #playlist == 0 then return end
    local target = playlist[cursor]
    if not target then return end

    -- 재생 시도 전에 파일 존재 여부를 직접 확인한다. end-file 이벤트의
    -- reason/error 필드에 의존하는 방식은 keep-open 옵션이나 재생목록
    -- 자동 전환 동작과 타이밍이 얽혀 신뢰하기 어려워, 대신 utils.file_info로
    -- 파일 시스템을 직접 확인하는 더 단순하고 확실한 방식을 쓴다.
    -- (참고: 스트리밍 URL 등 로컬 파일이 아닌 항목은 file_info가 nil을
    -- 반환하므로 존재 여부 확인을 건너뛰고 바로 재생을 시도한다.)
    local filename = target.filename
    local is_local_path = filename and not filename:match("^%a[%w+.-]*://")
    if is_local_path and not utils.file_info(filename) then
        mp.osd_message("File not found: " .. filename)
        return
    end

    mp.set_property_number("playlist-pos-1", cursor)
end

-- 다른 오버레이 패널(예: 단축키 메뉴)이 열릴 때 이 패널을 자동으로 닫아
-- 화면에서 서로 겹치지 않도록 함. 자기 자신이 보낸 메시지는 무시.
mp.register_script_message("overlay-panel-opening", function(source)
    if source ~= "playlist_panel" and is_open then
        close_panel()
    end
end)

-- 재생목록 내용이 바뀔 때(셔플 포함)와, 재생 위치(현재 트랙)가 바뀔 때 모두 갱신
mp.observe_property("playlist", "native", function()
    render_playlist()
end)
mp.observe_property("playlist-pos", "number", function()
    render_playlist()
end)

mp.add_key_binding(nil, "playlist-panel-toggle", toggle_panel)

-- 패널이 열려 있을 때만 UP/DOWN/ENTER를 동적으로 점유한다. 닫히면 바인딩을
-- 완전히 제거해서 다른 오버레이(context-menu 등)의 동일 키 바인딩이나
-- input.conf의 기본 동작(볼륨 조절 등)과 충돌하지 않도록 한다.
--
-- [이전 버그 기록] 예전에는 이 키들을 로드 시점에 한 번만 forced-bind 해두고
-- 내부에서 is_open으로 분기하는 방식이었다. mpv는 여러 스크립트가 같은
-- 키에 forced binding을 걸어두면 "가장 최근에 활성화된 스크립트 섹션"의
-- 바인딩만 실행하므로, context-menu.lua도 UP/DOWN을 상시 점유하고 있어
-- 스크립트 로드 순서에 따라 한쪽 패널이 열려 있어도 반응이 없는 문제가
-- 있었다. 그래서 "열려 있을 때만 점유"하는 동적 등록/해제 방식으로
-- 바꿨다 (bind_nav_keys/unbind_nav_keys, 위 open_panel/close_panel에서 호출).
bind_nav_keys = function()
    -- "repeatable" 플래그: 키를 꾹 누르고 있으면 mpv가 자동으로 반복 입력해줌.
    mp.add_forced_key_binding("UP", "playlist-panel-up", function() move_cursor(-1) end, "repeatable")
    mp.add_forced_key_binding("DOWN", "playlist-panel-down", function() move_cursor(1) end, "repeatable")
    mp.add_forced_key_binding("ENTER", "playlist-panel-select", function() play_at_cursor() end)
end

unbind_nav_keys = function()
    mp.remove_key_binding("playlist-panel-up")
    mp.remove_key_binding("playlist-panel-down")
    mp.remove_key_binding("playlist-panel-select")
end
