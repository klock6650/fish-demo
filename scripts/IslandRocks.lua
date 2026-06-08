-- ============================================================================
-- IslandRocks.lua - 岛屿礁石生成与绘制
-- 从 main.lua 拆分出来的模块
-- ============================================================================
local M = {}

-- 岛屿定义数据 (id, cx, cy, hw, hh)
local _ISLAND_DEFS = {
    {  1,  1340, -6320, 128, 112 },
    {  2, -4020, -5260, 608, 448 },
    {  3,  4940, -4720, 528, 400 },
    {  4,  1520, -3380, 288, 192 },
    {  5,  -740, -2680, 624, 384 },
    {  6, -3380, -1660, 368, 288 },
    {  7,  3760, -1520, 400, 336 },
    {  8,  6400, -1220, 224, 192 },
    {  9, -6340,  -940, 400, 272 },
    { 10,  -850,   -60, 552, 472 },
    { 11,  3720,  1420, 448, 320 },
    { 12, -2060,  1760, 256, 272 },
    { 13, -6340,  1860, 320, 272 },
    { 14,  7100,  1880, 592, 320 },
    { 15,  -560,  2520, 285, 261 },
    { 16,  4620,  3820, 512, 304 },
    { 18, -7340,  5080, 256, 256 },
}

-- 轻量伪随机（基于整数 seed，返回 0~1）
local function _rng(seed)
    seed = (seed * 1664525 + 1013904223) & 0x7fffffff
    return seed / 0x7fffffff, seed
end

-- 点是否在岛屿碰撞轮廓内（射线法）
local _ISLAND_TEXTURE_SCALE = 2
local function _pointInIslandContour(px, py, regDef, margin)
    local contour = regDef.contour
    local n = #contour
    local ix, iy = regDef.x, regDef.y
    local iw = regDef.w * _ISLAND_TEXTURE_SCALE
    local ih = regDef.h * _ISLAND_TEXTURE_SCALE
    margin = margin or 0
    local sfx = 1.0 + margin / (iw * 0.5)
    local sfy = 1.0 + margin / (ih * 0.5)
    local inside = false
    local j = n
    for i = 1, n do
        local xi = ix + contour[i][1] * iw * sfx
        local yi = iy + contour[i][2] * ih * sfy
        local xj = ix + contour[j][1] * iw * sfx
        local yj = iy + contour[j][2] * ih * sfy
        if ((yi > py) ~= (yj > py)) and
           (px < (xj - xi) * (py - yi) / (yj - yi) + xi) then
            inside = not inside
        end
        j = i
    end
    return inside
end

-- 预加载岛屿注册表（仅用于碰撞过滤）
local _rockRegistry = require("island_registry")

-- 尝试将礁石加入列表（碰撞过滤 + fade 计算）
local function _tryAddRock(rocks, wx, wy, r, ang, seedVal, cx, cy, hw, hh, regDef)
    if regDef and _pointInIslandContour(wx, wy, regDef, 50) then
        return
    end
    local ddx = wx - cx
    local ddy = wy - cy
    local d = math.sqrt(ddx * ddx + ddy * ddy)
    local maxDist = math.sqrt(hw * hw + hh * hh)
    local fade = math.min(1.0, d / (maxDist * 2.2))
    rocks[#rocks + 1] = { x = wx, y = wy, r = r, a = ang, s = seedVal, f = fade }
end

-- 按岛屿生成礁石列表（多簇随机分布，确定性，只算一次）
local _ALL_ROCKS = (function()
    local rocks = {}
    local gseed = 42

    for _, isl in ipairs(_ISLAND_DEFS) do
        local id, cx, cy, hw, hh = isl[1], isl[2], isl[3], isl[4], isl[5]
        local regDef = _rockRegistry.islands[id]
        local baseR  = 13 + math.floor(hw / 28)

        gseed = gseed + id * 137 + 19
        local nClusters = 2 + (gseed % 3)

        for c = 1, nClusters do
            gseed = gseed + c * 71 + 43
            local va, sa = _rng(gseed)
            local vd, sd = _rng(sa + 17)
            local clusterAng  = va * math.pi * 2
            local clusterDist = hw * (1.0 + vd * 1.4)
            local ccx = cx + math.cos(clusterAng) * clusterDist
            local ccy = cy + math.sin(clusterAng) * clusterDist * (hh / hw)

            gseed = sd + c * 53
            local nRocks = 3 + (gseed % 5)
            local clusterR = hw * (0.18 + (c % 3) * 0.07)

            for k = 1, nRocks do
                gseed = gseed + k * 31 + 7
                local v1, s1 = _rng(gseed)
                local v2, s2 = _rng(s1 + 13)
                local v3, s3 = _rng(s2 + 29)
                local v4,  _ = _rng(s3 + 53)

                local offAng  = v1 * math.pi * 2
                local offDist = v2 * clusterR
                local wx = ccx + math.cos(offAng) * offDist
                local wy = ccy + math.sin(offAng) * offDist * 0.65

                local r = baseR + math.floor(v3 * (baseR * 0.8))
                local seedVal = (id * 17 + c * 41 + k * 13) % 255 + 1

                _tryAddRock(rocks, wx, wy, r, v4 * math.pi * 2, seedVal,
                            cx, cy, hw, hh, regDef)
            end
        end

        -- 额外 2~3 块孤立礁石
        gseed = gseed + id * 59 + 3
        local nLone = 2 + (id % 2)
        for k = 1, nLone do
            gseed = gseed + k * 97
            local v1, s1 = _rng(gseed)
            local v2, s2 = _rng(s1 + 23)
            local v3, s3 = _rng(s2 + 47)
            local v4,  _ = _rng(s3 + 61)

            local ang  = v1 * math.pi * 2
            local dist = hw * (1.8 + v2 * 1.2)
            local wx = cx + math.cos(ang) * dist
            local wy = cy + math.sin(ang) * dist * (hh / hw)
            local r  = baseR + math.floor(v3 * (baseR * 0.5))
            local seedVal = (id * 23 + k * 19) % 255 + 1

            _tryAddRock(rocks, wx, wy, r, v4 * math.pi * 2, seedVal,
                        cx, cy, hw, hh, regDef)
        end
    end
    return rocks
end)()

-- 生成石头的顶点列表
local function _rockPts(sx, sy, sz, baseAng, seed)
    local N = 5 + (seed % 3)
    local cx = sx
    local cy = sy - sz * 0.09
    local pts = {}
    for i = 1, N do
        local a  = baseAng + (i - 1) * (math.pi * 2 / N) + math.sin(seed * 1.73 + i) * 0.28
        local rf = 0.62 + 0.38 * (((seed * 13 + i * 7) % 10) / 10.0)
        pts[i] = {
            x = sx + math.cos(a) * sz * rf,
            y = sy + math.sin(a) * sz * rf * 0.58,
        }
    end
    return pts, cx, cy, N
end

-- 只绘制阴影层
local function _drawRockShadow(g, sx, sy, sz, baseAng, seed, fade)
    local pts, cx, cy, N = _rockPts(sx, sy, sz, baseAng, seed)
    local shadowAlpha = 1.0 - fade * 0.75
    nvgBeginPath(g)
    for i = 1, N do
        local px = cx + (pts[i].x - cx) * 1.1 + sz * 0.10
        local py = cy + (pts[i].y - cy) * 1.1 + sz * 0.12
        if i == 1 then nvgMoveTo(g, px, py) else nvgLineTo(g, px, py) end
    end
    nvgClosePath(g)
    nvgFillColor(g, nvgRGBA(10, 18, 30, math.floor(55 * shadowAlpha)))
    nvgFill(g)
end

-- 只绘制石头本体
local function _drawRockBody(g, sx, sy, sz, baseAng, seed, fade)
    local pts, cx, cy, N = _rockPts(sx, sy, sz, baseAng, seed)

    local function blendToSea(r0, g0, b0, a0)
        local wr, wg, wb = 57, 125, 164
        local r = math.floor(r0 + (wr - r0) * fade)
        local g2 = math.floor(g0 + (wg - g0) * fade)
        local b = math.floor(b0 + (wb - b0) * fade)
        return nvgRGBA(r, g2, b, a0)
    end

    -- 三角面
    for i = 1, N do
        local j   = (i % N) + 1
        local emx = (pts[i].x + pts[j].x) * 0.5 - cx
        local emy = (pts[i].y + pts[j].y) * 0.5 - cy
        local len = math.sqrt(emx * emx + emy * emy) + 0.001
        local lf  = math.max(0.0, math.min(1.0, (-emx * 0.6 - emy * 1.0) / len * 0.45 + 0.55))
        local r0 = math.floor(38 + lf * 48)
        local g0 = math.floor(52 + lf * 54)
        local b0 = math.floor(78 + lf * 58)
        nvgBeginPath(g)
        nvgMoveTo(g, cx, cy)
        nvgLineTo(g, pts[i].x, pts[i].y)
        nvgLineTo(g, pts[j].x, pts[j].y)
        nvgClosePath(g)
        nvgFillColor(g, blendToSea(r0, g0, b0, 255))
        nvgFill(g)
    end

    -- 轮廓线
    nvgBeginPath(g)
    for i = 1, N do
        if i == 1 then nvgMoveTo(g, pts[i].x, pts[i].y)
        else            nvgLineTo(g, pts[i].x, pts[i].y) end
    end
    nvgClosePath(g)
    nvgStrokeColor(g, nvgRGBA(20, 35, 55, math.floor(80 * (1.0 - fade * 0.75))))
    nvgStrokeWidth(g, 0.9)
    nvgStroke(g)

    -- 高光面
    local ha  = baseAng - math.pi * 0.55
    local hx1 = cx + math.cos(ha - 0.4)  * sz * 0.38
    local hy1 = cy + math.sin(ha - 0.4)  * sz * 0.22
    local hx2 = cx + math.cos(ha + 0.1)  * sz * 0.46
    local hy2 = cy + math.sin(ha + 0.1)  * sz * 0.20
    local hx3 = cx + math.cos(ha + 0.55) * sz * 0.32
    local hy3 = cy + math.sin(ha + 0.55) * sz * 0.18
    nvgBeginPath(g)
    nvgMoveTo(g, hx1, hy1)
    nvgLineTo(g, hx2, hy2)
    nvgLineTo(g, hx3, hy3)
    nvgClosePath(g)
    nvgFillColor(g, blendToSea(100, 135, 175, 85))
    nvgFill(g)
end

--- 绘制所有岛屿礁石
---@param g userdata NanoVG context
---@param WorldToScreen function 世界坐标转屏幕坐标
---@param screenW number 屏幕宽度
---@param screenH number 屏幕高度
function M.DrawAll(g, WorldToScreen, screenW, screenH)
    -- 第一遍：所有阴影
    for _, def in ipairs(_ALL_ROCKS) do
        local sx, sy = WorldToScreen(def.x, def.y)
        if sx > -200 and sx < screenW + 200 and sy > -200 and sy < screenH + 200 then
            _drawRockShadow(g, sx, sy, def.r, def.a, def.s, def.f or 0)
        end
    end
    -- 第二遍：所有石头本体
    for _, def in ipairs(_ALL_ROCKS) do
        local sx, sy = WorldToScreen(def.x, def.y)
        if sx > -200 and sx < screenW + 200 and sy > -200 and sy < screenH + 200 then
            _drawRockBody(g, sx, sy, def.r, def.a, def.s, def.f or 0)
        end
    end
end

return M
