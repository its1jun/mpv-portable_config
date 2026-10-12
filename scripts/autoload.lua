local MAX_ENTRIES = 5000

local utils = require 'mp.utils'

local o = {
    disabled = false,
    ignore_hidden = true,
    same_type = true
}

local function Set(t)
    local set = {}
    for _, v in pairs(t) do set[v] = true end
    return set
end

local EXTENSIONS_VIDEO = Set {
    '3g2', '3gp', 'avi', 'flv', 'm2ts', 'm4v', 'mj2', 'mkv', 'mov',
    'mp4', 'mpeg', 'mpg', 'ogv', 'rmvb', 'webm', 'wmv', 'y4m'
}

local EXTENSIONS_AUDIO = Set {
    'aac', 'ac3', 'aiff', 'ape', 'au', 'dts', 'flac', 'm4a', 'mka',
    'mp3', 'oga', 'ogg', 'opus', 'wav', 'wma'
}

local EXTENSIONS = {}
for k in pairs(EXTENSIONS_VIDEO) do EXTENSIONS[k] = true end
for k in pairs(EXTENSIONS_AUDIO) do EXTENSIONS[k] = true end

local function add_files(files)
    local oldcount = mp.get_property_number("playlist-count", 1)
    for i = 1, #files do
        mp.commandv("loadfile", files[i][1], "append")
        mp.commandv("playlist-move", oldcount + i - 1, files[i][2])
    end
end

local function get_extension(path)
    return path:match("%.([^%.]+)$") or "nomatch"
end

local function alphanumsort(filenames)
    local function padnum(n, d)
        return #d > 0 and ("%03d%s%.12f"):format(#n, n, tonumber(d) / (10 ^ #d))
            or ("%03d%s"):format(#n, n)
    end

    local tuples = {}
    for i, f in ipairs(filenames) do
        tuples[i] = {f:lower():gsub("0*(%d+)%.?(%d*)", padnum), f}
    end
    table.sort(tuples, function(a, b)
        return a[1] == b[1] and #b[2] < #a[2] or a[1] < b[1]
    end)
    for i, tuple in ipairs(tuples) do filenames[i] = tuple[2] end
    return filenames
end

local autoloaded
local added_entries = {}
local autoloaded_dir

-- pl_count > 1 상태(트랙이 이미 autoload로 채워진 재생목록 안에서 다음/이전
-- 곡으로 넘어가는 매 전환)에서는 스캔 결과의 모든 항목이 이미 added_entries
-- 에 있어 재스캔해도 최종 결과에 영향이 없다. 따라서 같은 디렉토리에 한해
-- 직전 스캔 결과를 캐싱해 매 트랙 전환마다 readdir + 정렬을 반복하지 않는다.
-- pl_count == 1 로 재진입(=새 autoload 세션 시작)할 때는 무조건 캐시를 버리고
-- 새로 스캔해 디렉토리 변경 사항(파일 추가/삭제)을 반영한다.
local scan_cache_dir
local scan_cache_extensions
local scan_cache_files

local function scan_dir(path, current_file, total_files, extensions)
    local files = utils.readdir(path, "files") or {}
    local prefix = path == "." and "" or path

    local function filter(t, iter)
        for i = #t, 1, -1 do
            if not iter(t[i]) then table.remove(t, i) end
        end
    end

    filter(files, function(v)
        local current = prefix .. v == current_file
        if current then return true end
        if o.ignore_hidden and v:match("^%.") then return false end
        local ext = get_extension(v)
        return extensions[ext:lower()]
    end)

    alphanumsort(files)

    for i, file in ipairs(files) do
        files[i] = prefix .. file
    end

    local function append(t1, t2)
        local t1_size = #t1
        for i = 1, #t2 do t1[t1_size + i] = t2[i] end
    end

    append(total_files, files)
end

local function find_and_add_entries()
    local aborted = mp.get_property_native("playback-abort")
    if aborted then return end

    local path = mp.get_property("path", "")
    local dir, filename = utils.split_path(path)
    if o.disabled or #dir == 0 then return end

    local pl_count = mp.get_property_number("playlist-count", 1)
    if pl_count > 1 and autoloaded == nil then return
    elseif pl_count == 1 then
        autoloaded = true
        autoloaded_dir = dir
        added_entries = {}
    end

    local extensions = EXTENSIONS
    if o.same_type then
        local this_ext = get_extension(filename):lower()
        if EXTENSIONS_VIDEO[this_ext] then
            extensions = EXTENSIONS_VIDEO
        elseif EXTENSIONS_AUDIO[this_ext] then
            extensions = EXTENSIONS_AUDIO
        end
    end

    local pl = mp.get_property_native("playlist", {})
    local pl_current = mp.get_property_number("playlist-pos-1", 1)

    local files
    if pl_count > 1 and scan_cache_dir == autoloaded_dir
       and scan_cache_extensions == extensions then
        -- 이미 autoload로 채워진 재생목록 안에서 트랙만 전환된 경우:
        -- 재스캔해도 added_entries에 의해 전부 스킵되므로 캐시 재사용.
        files = scan_cache_files
    else
        files = {}
        scan_dir(autoloaded_dir, path, files, extensions)
        scan_cache_dir = autoloaded_dir
        scan_cache_extensions = extensions
        scan_cache_files = files
    end

    if next(files) == nil then return end

    local current
    for i = 1, #files do
        if files[i] == path then
            current = i
            break
        end
    end
    if not current then return end

    -- added_entries를 현재 재생목록 기준으로 매번 새로 구성한다.
    -- (기존 방식은 여기서 계속 누적만 하고 재생목록에서 빠진 과거 항목의
    -- 키를 지우지 않아, pl_count > 1 상태가 유지되는 긴 세션에서
    -- added_entries가 무한정 커지는 문제가 있었다. 재생목록 크기에
    -- 맞춰 매번 재구성하면 테이블 크기가 항상 유한하게 유지된다.)
    added_entries = {}
    for _, entry in ipairs(pl) do
        added_entries[entry.filename] = true
    end
    added_entries[path] = true

    local append = {[-1] = {}, [1] = {}}
    for direction = -1, 1, 2 do
        for i = 1, MAX_ENTRIES do
            local pos = current + i * direction
            local file = files[pos]
            if file == nil then break end

            if not added_entries[file] then
                if direction == -1 then
                    -- target(두 번째 필드)은 아래에서 append[-1]이 다 채워진 뒤
                    -- 한 번에 다시 계산하므로 여기서는 자리만 채워둔다.
                    table.insert(append[-1], 1, {file, nil})
                else
                    if pl_count > 1 then
                        table.insert(append[1], {file, pl_current + i * direction - 1})
                    else
                        mp.commandv("loadfile", file, "append")
                    end
                end
                added_entries[file] = true
            end
        end
        if pl_count == 1 and direction == -1 and #append[-1] > 0 then
            local load = append[-1]
            for i = 1, #load do mp.commandv("loadfile", load[i][1], "append") end
            mp.commandv("playlist-move", 0, current)
        end
    end

    -- append[-1]은 현재 재생 파일(pl_current, 1-indexed)보다 앞쪽에 있던 파일들을
    -- 파일시스템 순서 그대로(먼 파일부터) 담고 있다. add_files가 이 리스트를
    -- 순서대로 하나씩 "추가 후 이동"하므로, k번째로 처리되는 파일의 목표 위치는
    -- (현재 파일의 0-indexed 위치) + (k - 1) 이어야 순서와 위치가 모두 맞는다.
    -- (이전 버전은 이 목표 위치 계산에 상수 오프셋이 하나 어긋나 있어, 파일들이
    -- 현재 재생 파일 바로 앞이 아니라 재생목록 맨 앞쪽으로 밀려 들어가는 버그가 있었다.)
    if pl_count > 1 then
        local anchor = pl_current - 1
        for k = 1, #append[-1] do
            append[-1][k][2] = anchor + (k - 1)
        end
    end

    if pl_count > 1 then
        add_files(append[1])
        add_files(append[-1])
    end
end

mp.register_event("start-file", find_and_add_entries)