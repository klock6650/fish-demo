-- ============================================================================
-- MapSampler: 地图数据采样模块
-- ============================================================================
-- 从 Lua 数据文件中采样世界信息（鱼群密度、分区、建筑点等）。
-- 数据直接嵌入 Lua 字符串，绕过纹理压缩管线，保证像素值完整。
-- ============================================================================

local MapSampler = {}

-- ── 图层注册表 ──────────────────────────────────────────────────────────────
-- 每个图层: { data, w, h, centerX, centerY, scale, originX, originY }
local layers = {}

--- 注册一个采样图层（从 Lua 数据文件加载）
--- @param name      string   图层名称（如 "fish_density"）
--- @param dataFile  string   Lua 数据模块路径（如 "fish_density_data"）
--- @param centerX   number   图片中心对应的世界坐标 X
--- @param centerY   number   图片中心对应的世界坐标 Y
--- @param scale     number   每像素对应的世界单位数（如 200 表示 1px = 200 世界单位）
function MapSampler.Register(name, dataFile, centerX, centerY, scale)
    local mod = require(dataFile)
    if not mod or not mod.data then
        log:Write(LOG_ERROR, "[MapSampler] Failed to load data: " .. dataFile)
        return
    end
    local w = mod.w
    local h = mod.h
    layers[name] = {
        data    = mod.data,
        w       = w,
        h       = h,
        centerX = centerX,
        centerY = centerY,
        scale   = scale,
        originX = centerX - (w / 2) * scale,
        originY = centerY - (h / 2) * scale,
    }
    local worldW = w * scale
    local worldH = h * scale
    log:Write(LOG_INFO, string.format(
        "[MapSampler] Registered '%s': %dx%d (scale=%d/px), center=(%g,%g), world=%dx%d, dataLen=%d",
        name, w, h, scale, centerX, centerY, worldW, worldH, #mod.data))

    -- 启动诊断：采样几个位置验证数据完整性
    local probes = {
        { 0, 0, "top-left" },
        { math.floor(w/2), math.floor(h/2), "center" },
        { w-1, h-1, "bottom-right" },
    }
    for _, p in ipairs(probes) do
        local idx = p[2] * w + p[1] + 1  -- Lua 1-based
        local byte = string.byte(mod.data, idx)
        log:Write(LOG_INFO, string.format(
            "[MapSampler]   probe(%d,%d) %s: R_byte=%d (gray=%.3f)",
            p[1], p[2], p[3], byte, byte / 255.0))
    end
end

--- 读取图层在像素 (px, py) 处的 R 通道字节值
--- @param layer table 图层数据
--- @param px number 像素 X (0-based)
--- @param py number 像素 Y (0-based)
--- @return number R 通道 0~255
local function getPixelByte(layer, px, py)
    local idx = py * layer.w + px + 1  -- Lua 1-based string index
    return string.byte(layer.data, idx) or 0
end

--- 采样单通道灰度值（归一化 0~1）
--- @param name   string   图层名称
--- @param wx     number   世界坐标 X
--- @param wy     number   世界坐标 Y
--- @return number 0~1，超出范围返回 0
function MapSampler.Sample(name, wx, wy)
    local layer = layers[name]
    if not layer then return 0 end

    local px = math.floor((wx - layer.originX) / layer.scale)
    local py = math.floor((wy - layer.originY) / layer.scale)

    if px < 0 or px >= layer.w or py < 0 or py >= layer.h then
        return 0
    end

    return getPixelByte(layer, px, py) / 255.0
end

-- ── 鱼群密度专用 ────────────────────────────────────────────────────────────
-- 10 级灰度 → 系数映射（白=1.0 最高，每级降低 0.09，黑=0.19 最低）
local DENSITY_LEVELS = 10
local DENSITY_STEP   = 0.09
local DENSITY_MAX    = 1.0

--- 将 0~1 灰度值量化为 1~10 的密度等级
--- 白(1.0)=等级1(最高)，黑(0.0)=等级10(最低)
--- @param  gray number   灰度值 0~1
--- @return number level  1~10
function MapSampler.GrayToLevel(gray)
    local level = DENSITY_LEVELS - math.floor(gray * (DENSITY_LEVELS - 1) + 0.5)
    return math.max(1, math.min(DENSITY_LEVELS, level))
end

--- 根据密度等级返回系数
--- 等级1=1.0, 等级2=0.91, ..., 等级10=0.19
--- @param  level number  1~10
--- @return number coefficient
function MapSampler.LevelToCoeff(level)
    return DENSITY_MAX - (level - 1) * DENSITY_STEP
end

--- 一步到位：世界坐标 → 鱼群密度系数
--- @param  wx number  世界坐标 X
--- @param  wy number  世界坐标 Y
--- @return number coefficient  0.19~1.0
--- @return number level        1~10
function MapSampler.GetFishDensity(wx, wy)
    local gray = MapSampler.Sample("fish_density", wx, wy)
    local level = MapSampler.GrayToLevel(gray)
    local coeff = MapSampler.LevelToCoeff(level)
    return coeff, level
end

--- 获取已注册的图层（供调试用）
function MapSampler.GetLayer(name)
    return layers[name]
end

--- 调试采样：返回所有中间值，用于 HUD 显示定位问题
--- @param wx number 世界坐标 X
--- @param wy number 世界坐标 Y
--- @return table
function MapSampler.DebugFishDensity(wx, wy)
    local info = {
        px = 0, py = 0,
        inBounds = false,
        rawR = -1,
        gray = 0,
        level = 10,
        coeff = 0.19,
        layerW = 0, layerH = 0,
        originX = 0, originY = 0,
        scale = 0,
        layerExists = false,
    }

    local layer = layers["fish_density"]
    if not layer then return info end

    info.layerExists = true
    info.layerW = layer.w
    info.layerH = layer.h
    info.originX = layer.originX
    info.originY = layer.originY
    info.scale = layer.scale

    local px = math.floor((wx - layer.originX) / layer.scale)
    local py = math.floor((wy - layer.originY) / layer.scale)
    info.px = px
    info.py = py
    info.inBounds = (px >= 0 and px < layer.w and py >= 0 and py < layer.h)

    if info.inBounds then
        local byte = getPixelByte(layer, px, py)
        info.rawR = byte / 255.0
        info.gray = info.rawR
        info.level = MapSampler.GrayToLevel(info.rawR)
        info.coeff = MapSampler.LevelToCoeff(info.level)
    end

    return info
end

return MapSampler
