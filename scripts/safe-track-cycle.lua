-- safe-track-cycle.lua
-- 오디오/자막 트랙이 1개 이하인 파일에서 cycle audio, cycle sub를 실행하면
-- mpv가 디코더를 껐다 켜는 과정에서 EOF로 오인되어 다음 트랙으로
-- 자동 전환되는 문제가 있음. 이를 막기 위해 트랙 개수를 먼저 확인하고
-- 2개 이상일 때만 순환하도록 함. 트랙이 1개 이하일 때는 아무 반응 없이
-- 넘어가지 않도록 OSD로 안내 메시지를 표시한다.
-- c(sub-visibility 토글)는 트랙 재시작이 아니라 표시 여부만 바꾸므로 대상 아님.

local mp = require 'mp'

local function count_tracks(track_type)
    local tracks = mp.get_property_native("track-list") or {}
    local count = 0
    for _, track in ipairs(tracks) do
        if track.type == track_type then
            count = count + 1
        end
    end
    return count
end

local function safe_cycle_audio()
    if count_tracks("audio") > 1 then
        mp.command("cycle audio")
        local aid = mp.get_property("aid") or "off"
        mp.osd_message("Audio Track: " .. aid)
    else
        mp.osd_message("Audio Track: only one track available")
    end
end

local function safe_cycle_sub()
    if count_tracks("sub") > 1 then
        mp.command("cycle sub")
        local sid = mp.get_property("sid") or "off"
        mp.osd_message("Subtitle Track: " .. sid)
    else
        mp.osd_message("Subtitle Track: only one track available")
    end
end

mp.add_key_binding(nil, "safe-cycle-audio", safe_cycle_audio)
mp.add_key_binding(nil, "safe-cycle-sub", safe_cycle_sub)
