-- context-menu.lua
-- OSD 텍스트 기반 메뉴를 띄우고, 위/아래 키로 항목을 선택, ENTER로 실행,
-- 서브메뉴의 Back 항목 또는 ESC로 닫는 자체 제작 메뉴.
-- 메뉴 여닫는 키는 input.conf에서 script-binding context-menu-toggle 로 할당.
-- 외부 스크립트 의존성 없음 (mpv 내장 기능만 사용).

local mp = require 'mp'

-- ===== 메뉴 항목 정의 =====
-- label: 화면에 표시될 이름
-- command: 실행할 mpv 커맨드 (문자열, mp.command 로 실행)
-- submenu: 하위 메뉴가 있는 경우 항목 테이블
-- is_back: 이전 메뉴로 돌아가는 항목 표시
-- is_info: 현재 값 표시 전용 항목 (선택 불가, 커서가 건너뜀)
-- get_value: is_info 항목에서 현재 값을 문자열로 반환하는 함수
-- is_divider: 구분선/여백 전용 항목 (선택 불가, 값 표시 없음)

local BACK_ITEM = { label = "Back", is_back = true }
local DIVIDER = { label = "----------------", is_divider = true }
local SPACER = { label = " ", is_divider = true }

local color_submenu = {
    BACK_ITEM,
    SPACER,
    { label = "Contrast",   is_info = true, get_value = function() return mp.get_property("contrast") end },
    DIVIDER,
    { label = "Contrast +1",   command = "add contrast 1",  feedback_property = "contrast", feedback_label = "Contrast", repeatable = true },
    { label = "Contrast -1",   command = "add contrast -1", feedback_property = "contrast", feedback_label = "Contrast", repeatable = true },
    SPACER,
    { label = "Brightness", is_info = true, get_value = function() return mp.get_property("brightness") end },
    DIVIDER,
    { label = "Brightness +1", command = "add brightness 1",  feedback_property = "brightness", feedback_label = "Brightness", repeatable = true },
    { label = "Brightness -1", command = "add brightness -1", feedback_property = "brightness", feedback_label = "Brightness", repeatable = true },
    SPACER,
    { label = "Gamma",      is_info = true, get_value = function() return mp.get_property("gamma") end },
    DIVIDER,
    { label = "Gamma +1",      command = "add gamma 1",  feedback_property = "gamma", feedback_label = "Gamma", repeatable = true },
    { label = "Gamma -1",      command = "add gamma -1", feedback_property = "gamma", feedback_label = "Gamma", repeatable = true },
    SPACER,
    { label = "Saturation", is_info = true, get_value = function() return mp.get_property("saturation") end },
    DIVIDER,
    { label = "Saturation +1", command = "add saturation 1",  feedback_property = "saturation", feedback_label = "Saturation", repeatable = true },
    { label = "Saturation -1", command = "add saturation -1", feedback_property = "saturation", feedback_label = "Saturation", repeatable = true },
    SPACER,
    { label = "Reset Color",         command = "set contrast 0; set brightness 0; set gamma 0; set saturation 0", feedback_message = "Color Reset" },
    title = "Color",
}

local speed_submenu = {
    BACK_ITEM,
    SPACER,
    { label = "Speed",   is_info = true, get_value = function() return mp.get_property("speed") end },
    DIVIDER,
    { label = "Speed +0.1",  command = "add speed 0.1",       feedback_property = "speed", feedback_label = "Speed", repeatable = true },
    { label = "Speed -0.1",  command = "add speed -0.1",      feedback_property = "speed", feedback_label = "Speed", repeatable = true },
    { label = "Speed x2.0",  command = "multiply speed 2.0",  feedback_property = "speed", feedback_label = "Speed" },
    { label = "Speed x0.5",  command = "multiply speed 0.5",  feedback_property = "speed", feedback_label = "Speed" },
    SPACER,
    { label = "Reset Speed", command = "set speed 1.0", feedback_message = "Speed Reset" },
    title = "Speed",
}

local subdelay_submenu = {
    BACK_ITEM,
    SPACER,
    { label = "Subtitle Delay",   is_info = true, get_value = function() return mp.get_property("sub-delay") end },
    DIVIDER,
    { label = "Subtitle Delay +0.1", command = "add sub-delay 0.1",  feedback_property = "sub-delay", feedback_label = "Subtitle Delay", repeatable = true },
    { label = "Subtitle Delay -0.1", command = "add sub-delay -0.1", feedback_property = "sub-delay", feedback_label = "Subtitle Delay", repeatable = true },
    SPACER,
    { label = "Reset Subtitle Delay",    command = "set sub-delay 0;", feedback_message = "Subtitle Delay Reset"},
    title = "Subtitle Delay",
}

-- Loop 상태를 3단계로 순환: Loop Playlist (재생목록 전체 반복) ->
-- Loop File (현재 파일만 무한 반복) -> Loop Off -> Loop Playlist ...
-- 항목 자체의 label을 상태에 맞춰 바꾸는 방식(get_value 별도 표시가 아님).
-- mpv 속성 loop-playlist / loop-file 두 개를 조합해 표현한다.
local function get_loop_state()
    local loop_file = mp.get_property("loop-file")
    local loop_playlist = mp.get_property("loop-playlist")
    if loop_file == "inf" or loop_file == "yes" then
        return "loop-file"
    elseif loop_playlist == "inf" or loop_playlist == "yes" then
        return "loop-playlist"
    else
        return "off"
    end
end

local LOOP_LABELS = {
    ["loop-playlist"] = "Loop Playlist",
    ["loop-file"] = "Loop File",
    ["off"] = "Loop Off",
}

local function cycle_loop_state()
    local state = get_loop_state()
    if state == "off" then
        mp.set_property("loop-playlist", "inf")
        mp.set_property("loop-file", "no")
    elseif state == "loop-playlist" then
        mp.set_property("loop-playlist", "no")
        mp.set_property("loop-file", "inf")
    else -- "loop-file"
        mp.set_property("loop-playlist", "no")
        mp.set_property("loop-file", "no")
    end
    mp.osd_message(LOOP_LABELS[get_loop_state()])
end

-- 자동 다음 곡 재생 설정. mpv의 keep-open 옵션으로 구현한다.
--   "yes"    : 마지막 파일에서만 정지, 그 외에는 끝나면 자동으로 다음 곡 재생 (기본값, mpv.conf와 동일)
--   "always" : 모든 파일 끝에서 정지 (자동으로 넘어가지 않음)
-- "always"가 아닌 모든 값은 자동 재생(On)으로 간주한다.
local function is_auto_next()
    return mp.get_property("keep-open") ~= "always"
end

local function toggle_auto_next()
    if is_auto_next() then
        mp.set_property("keep-open", "always")
    else
        mp.set_property("keep-open", "yes")
    end
    mp.osd_message("Auto Next: " .. (is_auto_next() and "On" or "Off"))
end

local main_menu = {
    { label = "Shuffle",            command = "playlist-shuffle", feedback_message = "Playlist Shuffled" },
    { get_label = function() return LOOP_LABELS[get_loop_state()] end, custom_action = cycle_loop_state },
    { get_label = function() return "Auto Next: " .. (is_auto_next() and "On" or "Off") end, custom_action = toggle_auto_next },
    { label = "Subtitle Track",     command = "script-binding safe_track_cycle/safe-cycle-sub" },
    { label = "Color",              submenu = color_submenu },
    { label = "Speed",              submenu = speed_submenu },
    { label = "Subtitle Delay",     submenu = subdelay_submenu },
    title = "Shortcut Menu",
}

-- ===== 메뉴 상태 =====
local stack = {}          -- 메뉴 네비게이션 스택 (하위메뉴 진입 시 push)
local selected = 1
local overlay = mp.create_osd_overlay("ass-events")
local is_open = false

-- bind_nav_keys/unbind_nav_keys는 파일 하단(모든 조작 함수 정의 이후)에서
-- 정의되지만, close_menu/open_menu가 그보다 먼저 이 이름들을 호출해야
-- 하므로 여기서 local로 미리 선언해둔다. (아래에서 `local function`으로
-- 다시 선언하지 않고 `bind_nav_keys = function...` 형태로 값만 채울 것.
-- `local function`으로 재선언하면 별개의 지역변수가 되어 여기서 캡처한
-- upvalue가 항상 nil로 남는 버그가 생기므로 주의.)
local bind_nav_keys
local unbind_nav_keys

local function current_menu()
    return stack[#stack]
end

-- is_info/is_divider 항목은 선택 불가이므로 건너뛸 다음 인덱스를 계산
local function is_unselectable(item)
    return item.is_info or item.is_divider
end

local function next_selectable(menu, from, delta)
    local n = #menu
    local i = from
    for _ = 1, n do
        i = i + delta
        if i < 1 then i = n end
        if i > n then i = 1 end
        if not is_unselectable(menu[i]) then
            return i
        end
    end
    return from
end

local function render()
    local menu = current_menu()
    if not menu then return end

    local lines = {}
    if menu.title then
        table.insert(lines, string.format("{\\b1}[ %s ]{\\b0}", menu.title))
        table.insert(lines, "")
    end
    for i, item in ipairs(menu) do
        if item.is_divider then
            table.insert(lines, item.label)
        elseif item.is_info then
            local value = item.get_value and item.get_value() or "?"
            table.insert(lines, string.format("    %s: %s", item.label, tostring(value)))
        else
            local label = item.get_label and item.get_label() or item.label
            local display_label = item.submenu and (label .. "+") or label
            if i == selected then
                table.insert(lines, string.format("{\\c&H00D7FF&}[ %s ]{\\c}", display_label))
            else
                table.insert(lines, string.format("  %s", display_label))
            end
        end
    end

    overlay.data = string.format(
        "{\\an7\\pos(40,40)\\fs23\\bord2\\shad1\\c&HFFFFFF&\\3c&H000000&}%s",
        table.concat(lines, "\\N")
    )
    overlay:update()
end

local function close_menu()
    is_open = false
    stack = {}
    selected = 1
    overlay:remove()
    unbind_nav_keys()
    mp.commandv("script-message", "overlay-panel-closed", "context_menu")
end

local function open_menu()
    mp.commandv("script-message", "overlay-panel-opening", "context_menu")
    stack = { main_menu }
    selected = next_selectable(main_menu, 0, 1)
    is_open = true
    bind_nav_keys()
    render()
end

local function move(delta)
    local menu = current_menu()
    if not menu then return end
    selected = next_selectable(menu, selected, delta)
    render()
end

local function go_back()
    if #stack > 1 then
        table.remove(stack)
        local menu = current_menu()
        selected = next_selectable(menu, 0, 1)
        render()
    else
        close_menu()
    end
end

-- ENTER는 complex 바인딩으로 등록되어(아래 bind_nav_keys) 매 key 이벤트마다
-- event 테이블({event = "down"/"repeat"/"up", ...})을 받는다. 여기서는
-- "down"에서만 실제 동작을 실행하고, "repeat"는 현재 선택된 항목이
-- repeatable = true 일 때만 실행하며, "up"은 항상 무시한다.
-- (참고: mpv 공식 문서상 event 테이블은 complex = true 일 때만 전달된다.
-- simple + repeatable 조합으로는 event 종류를 구분할 수 없어서 이전에
-- 시도했던 "재등록 없는 simple" 방식은 실제로는 동작하지 않는 접근이었다.)
-- 바인딩을 지웠다 다시 거는 동작이 전혀 없으므로(고정된 단일 complex
-- 바인딩), 입력 섹션이 반복적으로 갱신되며 생기는 부작용 걱정도 없다.
local function activate(event_table)
    local event = event_table and event_table.event

    if event == "up" then
        return
    end

    local menu = current_menu()
    if not menu then return end
    local item = menu[selected]
    if not item or is_unselectable(item) then return end

    if event == "repeat" and not item.repeatable then
        -- 반복 불가 항목(Back, Reset, x2.0 등)에서 키를 꾹 눌러 발생한
        -- 반복 이벤트는 무시. 최초 down 이벤트는 항상 실행됨.
        return
    end

    if item.is_back then
        go_back()
    elseif item.submenu then
        table.insert(stack, item.submenu)
        selected = next_selectable(item.submenu, 0, 1)
        render()
    elseif item.custom_action then
        item.custom_action()
        render()
    elseif item.command then
        mp.command(item.command)
        if item.feedback_property then
            local value = mp.get_property(item.feedback_property)
            mp.osd_message(string.format("%s: %s", item.feedback_label, tostring(value)))
        elseif item.feedback_message then
            mp.osd_message(item.feedback_message)
        end
        render()
    end
end

local function toggle_menu()
    if is_open then
        close_menu()
    else
        open_menu()
    end
end

-- 다른 오버레이 패널(예: 플레이리스트)이 열리면 이 메뉴는 자동으로 닫는다.
mp.register_script_message("overlay-panel-opening", function(source)
    if source ~= "context_menu" and is_open then
        close_menu()
    end
end)

-- ===== 키 바인딩 =====
-- 메뉴 열기/닫기 (실제 키 할당은 input.conf에서 처리). 토글 키는 항상 등록.
mp.add_forced_key_binding(nil, "context-menu-toggle", toggle_menu)

--
-- UP/DOWN/ENTER/ESC는 "메뉴가 열려 있을 때만" bind_nav_keys()로 동적
-- 등록하고, 닫힐 때 unbind_nav_keys()로 완전히 제거한다 (위 open_menu/
-- close_menu 정의부에서 호출).
--
-- [이전 버그 기록] 예전에는 이 키들을 로드 시점에 한 번만 forced-bind 해두고
-- 내부에서 is_open으로 분기하는 방식이었다. 그런데 mpv는 여러 스크립트가
-- 같은 키에 forced binding을 걸어두면 "가장 최근에 활성화된 스크립트
-- 섹션"의 바인딩만 실행하고 다른 스크립트의 바인딩은 아예 호출되지 않는다
-- (mpv find_any_bind_for_key 참고). playlist-panel.lua도 UP/DOWN을 상시
-- 점유하고 있었기 때문에, 스크립트 로드 순서에 따라 이 메뉴가 열려 있어도
-- UP/DOWN이 playlist-panel 쪽으로 가서 아무 반응이 없거나(둘 다 닫혀있으면
-- 결국 input.conf 기본 볼륨 조절까지 새어나감) 하는 문제가 있었다.
-- 그래서 "열려 있을 때만 점유"하는 동적 등록/해제 방식으로 바꿨다.
--
-- bind_nav_keys/unbind_nav_keys의 실제 정의. move/activate/close_menu가
-- 전부 위에서 정의된 뒤이므로, 여기서는 `local function`이 아니라 위쪽
-- (bind_nav_keys/unbind_nav_keys 최초 local 선언부) 근처에서 미리
-- 선언해둔 local 변수에 값을 대입하는 형태로 채운다.
-- (`local function bind_nav_keys() ... end`로 쓰면 완전히 새로운 지역
-- 변수가 생겨서, open_menu/close_menu가 캡처한 upvalue는 계속 nil로
-- 남고 실제 호출 시 "attempt to call a nil value" 에러가 나 메뉴가
-- 알 수 없이 멈추는 버그로 이어지므로 반드시 이 형태를 유지할 것.)
bind_nav_keys = function()
    -- "repeatable" 플래그: 키를 꾹 누르고 있으면 mpv가 자동으로 반복 입력해줌.
    mp.add_forced_key_binding("UP", "context-menu-up", function() move(-1) end, "repeatable")
    mp.add_forced_key_binding("DOWN", "context-menu-down", function() move(1) end, "repeatable")
    -- ENTER는 complex + repeatable로 한 번만 등록한다. down/repeat/up
    -- 이벤트는 activate() 내부에서 직접 구분해 처리하므로, 선택이 바뀔 때마다
    -- 바인딩을 다시 걸 필요가 전혀 없다 (재등록 없음 = 입력 섹션 재구성 없음).
    mp.add_forced_key_binding("ENTER", "context-menu-select", activate, {repeatable = true, complex = true})
    mp.add_forced_key_binding("ESC", "context-menu-back", close_menu)
end

unbind_nav_keys = function()
    mp.remove_key_binding("context-menu-up")
    mp.remove_key_binding("context-menu-down")
    mp.remove_key_binding("context-menu-select")
    mp.remove_key_binding("context-menu-back")
end
