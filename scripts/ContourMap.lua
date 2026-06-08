-- ============================================================================
-- ContourMap.lua - 地形/等高线/深度分区系统
-- 从 main.lua 拆分出来的模块
-- ============================================================================
local M = {}

local IslandSystem = require "IslandSystem"

-- ============================================================================
-- 程序化噪声（水下等高线用）
-- ============================================================================
local CONTOUR_NOISE_SCALE = 0.0008  -- 世界坐标 → 噪声坐标缩放

-- 岛屿隆起缓存（BuildIslandBumps() 填充）
-- 每条: { x, y, r2inv, strength }
local _islandBumps = {}

-- 海沟凹陷（负高斯，压低地形 → 加深水深）
local _trenchPoints = {
    { x = -6000, y = 5200, rx = 1800, ry = 600,  strength = 0.52 },
    { x = -3800, y = 5600, rx = 2000, ry = 700,  strength = 0.58 },
    { x = -1200, y = 5900, rx = 2000, ry = 650,  strength = 0.56 },
    { x =  1400, y = 5700, rx = 1900, ry = 600,  strength = 0.55 },
    { x =  3600, y = 5300, rx = 1800, ry = 550,  strength = 0.53 },
    { x =  5800, y = 4800, rx = 1700, ry = 500,  strength = 0.50 },
}

local function _noiseHash2(ix, iy)
    local n = ix * 374761393 + iy * 668265263
    n = (n ~ (n >> 13)) * 1274126177
    return (n & 0x7fffffff) / 0x7fffffff
end

local function _noiseSmoothstep(t) return t * t * (3 - 2 * t) end

local function _vnoise(x, y)
    local ix, iy = math.floor(x), math.floor(y)
    local fx, fy = x - ix, y - iy
    local sx, sy = _noiseSmoothstep(fx), _noiseSmoothstep(fy)
    local v00 = _noiseHash2(ix,     iy)
    local v10 = _noiseHash2(ix + 1, iy)
    local v01 = _noiseHash2(ix,     iy + 1)
    local v11 = _noiseHash2(ix + 1, iy + 1)
    local a = v00 + (v10 - v00) * sx
    local b = v01 + (v11 - v01) * sx
    return a + (b - a) * sy
end

--- 分形噪声（3 层 octave）
local function contourFBM(wx, wy)
    local x, y = wx * CONTOUR_NOISE_SCALE, wy * CONTOUR_NOISE_SCALE
    local h = _vnoise(x, y) * 0.5
            + _vnoise(x * 2.03, y * 2.03) * 0.3
            + _vnoise(x * 4.07, y * 4.07) * 0.2

    -- 叠加岛屿高斯隆起：每座岛屿周围地形抬升，使其位于等高线高处
    for _, b in ipairs(_islandBumps) do
        local dx = wx - b.x
        local dy = wy - b.y
        h = h + b.strength * math.exp(-(dx * dx + dy * dy) * b.r2inv)
    end

    -- 叠加海沟凹陷（负椭圆高斯，压低地形使海沟更深）
    for _, t in ipairs(_trenchPoints) do
        local dx = (wx - t.x) / t.rx
        local dy = (wy - t.y) / t.ry
        h = h - t.strength * math.exp(-(dx * dx + dy * dy))
    end

    return math.max(0.0, math.min(h, 1.0))
end

--- 等高线阈值配置
local CONTOUR_THRESHOLDS = {
    { val = 0.12, r = 10, g = 25,  b = 70,  a = 65 },  -- 超深区边缘
    { val = 0.30, r = 35, g = 75,  b = 140, a = 55 },
    { val = 0.42, r = 45, g = 100, b = 165, a = 50 },
    { val = 0.54, r = 60, g = 130, b = 190, a = 45 },
    { val = 0.66, r = 75, g = 155, b = 210, a = 40 },
}

--- Marching Squares 等值线插值
local function _isoLerp(a, b, va, vb, iso)
    local t = 0.5
    if math.abs(va - vb) > 1e-6 then t = (iso - va) / (vb - va) end
    return a + t * (b - a)
end

--- 等高线梯度颜色带（从深到浅，噪声值越大 = 越浅水区）
local CONTOUR_GRADIENT = {
    { lo = 0.00, hi = 0.12, r = 5,  g = 12,  b = 45,  a = 60 },  -- 超深区（海沟）
    { lo = 0.12, hi = 0.30, r = 15, g = 40,  b = 90,  a = 50 },  -- 深海区
    { lo = 0.30, hi = 0.42, r = 25, g = 60,  b = 120, a = 45 },
    { lo = 0.42, hi = 0.54, r = 38, g = 85,  b = 150, a = 40 },
    { lo = 0.54, hi = 0.66, r = 50, g = 110, b = 175, a = 35 },
    { lo = 0.66, hi = 1.01, r = 65, g = 140, b = 200, a = 30 },  -- 最浅
}

--- 深度分区定义（与 CONTOUR_GRADIENT 一一对应）
M.DEPTH_BANDS = {
    { lo = 0.00, hi = 0.12, index = 1, name = "超深区", depthMin = 100, depthMax = 200, r = 5,  g = 12,  b = 45  },
    { lo = 0.12, hi = 0.30, index = 2, name = "深海区", depthMin = 40,  depthMax = 100, r = 15, g = 40,  b = 90  },
    { lo = 0.30, hi = 0.42, index = 3, name = "次深区", depthMin = 25,  depthMax = 40,  r = 25, g = 60,  b = 120 },
    { lo = 0.42, hi = 0.54, index = 4, name = "中层区", depthMin = 15,  depthMax = 25,  r = 38, g = 85,  b = 150 },
    { lo = 0.54, hi = 0.66, index = 5, name = "浅层区", depthMin = 5,   depthMax = 15,  r = 50, g = 110, b = 175 },
    { lo = 0.66, hi = 1.01, index = 6, name = "近岸区", depthMin = 0,   depthMax = 5,   r = 65, g = 140, b = 200 },
}

--- 深度网格（BuildDepthMap() 填充，供鱼种分布查询）
local depthGrid_ = nil

-- 等高线噪声网格缓存
local _contourGridCache = {}

function M.InvalidateContourCache() _contourGridCache = {} end

-- 将噪声值 h 映射为 RGBA
local function _heightToColor(h)
    local bands = CONTOUR_GRADIENT
    local b0 = bands[1]
    if h <= b0.lo then return b0.r, b0.g, b0.b, b0.a end
    for i = 1, #bands - 1 do
        local b1, b2 = bands[i], bands[i + 1]
        if h >= b1.lo and h < b2.hi then
            local mid = b1.hi
            local t = h < mid
                and (h - b1.lo) / (mid - b1.lo) * 0.5
                or  0.5 + (h - mid) / (b2.hi - mid) * 0.5
            local function lp(a, b, tt) return math.floor(a + (b - a) * tt + 0.5) end
            return lp(b1.r,b2.r,t), lp(b1.g,b2.g,t), lp(b1.b,b2.b,t), lp(b1.a,b2.a,t)
        end
    end
    local bl = bands[#bands]
    return bl.r, bl.g, bl.b, bl.a
end

--- bilinear: 是否使用双线性渐变（大地图用 true，小地图用 false 以节省 draw call）
function M.DrawContourLines(wMinX, wMinY, wW, wH, gridN, w2s, bilinear, ctx)
    local g = ctx  -- 必须传入 NanoVG context
    local stepW = wW / gridN
    local stepH = wH / gridN

    -- ── 噪声网格：优先用缓存，避免每帧重采样 ──────────────────────────
    local cacheKey = gridN
    local grid = _contourGridCache[cacheKey]
    if not grid then
        grid = {}
        for gy = 0, gridN do
            local row = {}
            local wy = wMinY + gy * stepH
            for gx = 0, gridN do
                row[gx] = contourFBM(wMinX + gx * stepW, wy)
            end
            grid[gy] = row
        end
        _contourGridCache[cacheKey] = grid
    end

    -- ── Pass 1: 颜色填充 ────────────────────────────────────────────────
    if bilinear then
        -- 大地图：双线性插值（3 次 draw call/格，视觉平滑）
        for gy = 0, gridN - 1 do
            for gx = 0, gridN - 1 do
                local wx0, wy0 = wMinX + gx * stepW, wMinY + gy * stepH
                local sx0, sy0 = w2s(wx0, wy0)
                local sx1, sy1 = w2s(wx0 + stepW, wy0 + stepH)
                local sw, sh   = sx1 - sx0, sy1 - sy0

                local r00,g00,b00,a00 = _heightToColor(grid[gy][gx])
                local r10,g10,b10,a10 = _heightToColor(grid[gy][gx+1])
                local r01,g01,b01,a01 = _heightToColor(grid[gy+1][gx])
                local r11,g11,b11,a11 = _heightToColor(grid[gy+1][gx+1])

                local pTop = nvgLinearGradient(g, sx0, sy0, sx1, sy0,
                    nvgRGBA(r00,g00,b00,a00), nvgRGBA(r10,g10,b10,a10))
                nvgBeginPath(g); nvgRect(g, sx0, sy0, sw, sh*0.5)
                nvgFillPaint(g, pTop); nvgFill(g)

                local pBot = nvgLinearGradient(g, sx0, sy0, sx1, sy0,
                    nvgRGBA(r01,g01,b01,a01), nvgRGBA(r11,g11,b11,a11))
                nvgBeginPath(g); nvgRect(g, sx0, sy0+sh*0.5, sw, sh*0.5)
                nvgFillPaint(g, pBot); nvgFill(g)

                local function avg2(a,b) return math.floor((a+b)*0.5+0.5) end
                local rT,gT,bT,aT = avg2(r00,r10),avg2(g00,g10),avg2(b00,b10),avg2(a00,a10)
                local rB,gB,bB,aB = avg2(r01,r11),avg2(g01,g11),avg2(b01,b11),avg2(a01,a11)
                local pV = nvgLinearGradient(g, sx0, sy0, sx0, sy1,
                    nvgRGBA(rT,gT,bT,math.floor(aT*0.5+0.5)),
                    nvgRGBA(rB,gB,bB,math.floor(aB*0.5+0.5)))
                nvgBeginPath(g); nvgRect(g, sx0, sy0, sw, sh)
                nvgFillPaint(g, pV); nvgFill(g)
            end
        end
    else
        -- 小地图：单色平均（1 次 draw call/格，性能优先）
        for gy = 0, gridN - 1 do
            for gx = 0, gridN - 1 do
                local avg = (grid[gy][gx] + grid[gy][gx+1]
                           + grid[gy+1][gx] + grid[gy+1][gx+1]) * 0.25
                for _, band in ipairs(CONTOUR_GRADIENT) do
                    if avg >= band.lo and avg < band.hi then
                        local wx0, wy0 = wMinX + gx * stepW, wMinY + gy * stepH
                        local sx0, sy0 = w2s(wx0, wy0)
                        local sx1, sy1 = w2s(wx0 + stepW, wy0 + stepH)
                        nvgBeginPath(g)
                        nvgRect(g, sx0, sy0, sx1-sx0, sy1-sy0)
                        nvgFillColor(g, nvgRGBA(band.r, band.g, band.b, band.a))
                        nvgFill(g)
                        break
                    end
                end
            end
        end
    end

    -- ── Pass 2: 等高线描边 ──
    for _, th in ipairs(CONTOUR_THRESHOLDS) do
        local iso = th.val
        nvgBeginPath(g)

        for gy = 0, gridN - 1 do
            for gx = 0, gridN - 1 do
                local v0 = grid[gy][gx]
                local v1 = grid[gy][gx + 1]
                local v2 = grid[gy + 1][gx + 1]
                local v3 = grid[gy + 1][gx]

                local idx = 0
                if v0 >= iso then idx = idx + 1 end
                if v1 >= iso then idx = idx + 2 end
                if v2 >= iso then idx = idx + 4 end
                if v3 >= iso then idx = idx + 8 end

                if idx ~= 0 and idx ~= 15 then
                    local wx0 = wMinX + gx * stepW
                    local wy0 = wMinY + gy * stepH
                    local wx1 = wx0 + stepW
                    local wy1 = wy0 + stepH

                    local topX    = _isoLerp(wx0, wx1, v0, v1, iso)
                    local rightY  = _isoLerp(wy0, wy1, v1, v2, iso)
                    local bottomX = _isoLerp(wx0, wx1, v3, v2, iso)
                    local leftY   = _isoLerp(wy0, wy1, v0, v3, iso)

                    local eTop    = { topX,  wy0 }
                    local eRight  = { wx1,   rightY }
                    local eBottom = { bottomX, wy1 }
                    local eLeft   = { wx0,   leftY }

                    local segments = nil
                    if     idx == 1  then segments = { eTop, eLeft }
                    elseif idx == 2  then segments = { eTop, eRight }
                    elseif idx == 3  then segments = { eLeft, eRight }
                    elseif idx == 4  then segments = { eRight, eBottom }
                    elseif idx == 5  then segments = { eTop, eRight, eBottom, eLeft }
                    elseif idx == 6  then segments = { eTop, eBottom }
                    elseif idx == 7  then segments = { eLeft, eBottom }
                    elseif idx == 8  then segments = { eLeft, eBottom }
                    elseif idx == 9  then segments = { eTop, eBottom }
                    elseif idx == 10 then segments = { eTop, eLeft, eBottom, eRight }
                    elseif idx == 11 then segments = { eRight, eBottom }
                    elseif idx == 12 then segments = { eLeft, eRight }
                    elseif idx == 13 then segments = { eTop, eRight }
                    elseif idx == 14 then segments = { eTop, eLeft }
                    end

                    if segments then
                        for si = 1, #segments, 2 do
                            local p1 = segments[si]
                            local p2 = segments[si + 1]
                            if p1 and p2 then
                                local mx1, my1 = w2s(p1[1], p1[2])
                                local mx2, my2 = w2s(p2[1], p2[2])
                                nvgMoveTo(g, mx1, my1)
                                nvgLineTo(g, mx2, my2)
                            end
                        end
                    end
                end
            end
        end

        nvgStrokeColor(g, nvgRGBA(th.r, th.g, th.b, th.a))
        nvgStrokeWidth(g, 1.0)
        nvgStroke(g)
    end
end

-- ============================================================================
-- 地形工具
-- ============================================================================

--- 从 island_registry 读取所有岛屿，预计算高斯隆起参数
local BUMP_RADIUS_MULT = 3.0   -- 隆起半径倍率（相对于岛屿最大边长）
local BUMP_STRENGTH    = 0.38  -- 隆起强度（叠加到 FBM 高度）

function M.BuildIslandBumps()
    _islandBumps = {}
    local reg = require("island_registry")
    for _, isl in pairs(reg.islands) do
        local sz     = math.max(isl.w, isl.h)
        local radius = sz * BUMP_RADIUS_MULT
        _islandBumps[#_islandBumps + 1] = {
            x       = isl.x,
            y       = isl.y,
            r2inv   = 1.0 / (radius * radius),
            strength = BUMP_STRENGTH,
        }
    end
    print(string.format("[Terrain] Built %d island bumps (r_mult=%.1f, strength=%.2f)",
        #_islandBumps, BUMP_RADIUS_MULT, BUMP_STRENGTH))
end

--- 预采样深度网格
local DEPTH_MAP_RES    = 100
local DEPTH_MAP_BOUNDS = { minX = -9000, maxX = 9000, minY = -8000, maxY = 7000 }
M.DEPTH_MAP_BOUNDS = DEPTH_MAP_BOUNDS

function M.BuildDepthMap()
    local b    = DEPTH_MAP_BOUNDS
    local res  = DEPTH_MAP_RES
    local stepX = (b.maxX - b.minX) / res
    local stepY = (b.maxY - b.minY) / res

    local data = {}
    for gy = 0, res do
        local row = {}
        local wy  = b.minY + gy * stepY
        for gx = 0, res do
            local wx = b.minX + gx * stepX
            local h  = contourFBM(wx, wy)
            local idx = #M.DEPTH_BANDS  -- 默认最浅
            for i, band in ipairs(M.DEPTH_BANDS) do
                if h >= band.lo and h < band.hi then idx = i; break end
            end
            row[gx] = idx
        end
        data[gy] = row
    end

    depthGrid_ = { bounds = b, res = res, stepX = stepX, stepY = stepY, data = data }
    print(string.format("[DepthMap] Built %dx%d depth grid (world %.0f×%.0f)",
        res, res, b.maxX - b.minX, b.maxY - b.minY))
end

--- 查询世界坐标对应的深度分区索引 (1=超深区 … 6=近岸区)
---@param wx number 世界 X 坐标
---@param wy number 世界 Y 坐标
---@return integer bandIndex  深度分区索引 1~6
---@return table   band       DEPTH_BANDS 中对应的分区记录
function M.GetDepthBandAt(wx, wy)
    if not depthGrid_ then
        -- 回退：实时计算
        local h = contourFBM(wx, wy)
        for i, band in ipairs(M.DEPTH_BANDS) do
            if h >= band.lo and h < band.hi then return i, band end
        end
        return #M.DEPTH_BANDS, M.DEPTH_BANDS[#M.DEPTH_BANDS]
    end
    local b  = depthGrid_.bounds
    local gx = math.floor((wx - b.minX) / depthGrid_.stepX + 0.5)
    local gy = math.floor((wy - b.minY) / depthGrid_.stepY + 0.5)
    gx = math.max(0, math.min(depthGrid_.res, gx))
    gy = math.max(0, math.min(depthGrid_.res, gy))
    local idx = depthGrid_.data[gy][gx]
    return idx, M.DEPTH_BANDS[idx]
end

--- 根据世界坐标返回鱼类深度级别 (1~4)
-- 1级: 岛屿中心500世界单位以内（码头浅滩）
-- 2级: 0~5m（近岸区，bandIndex=6）
-- 3级: 5~25m（浅层/中层区，bandIndex=4~5）
-- 4级: 25m以上（次深/深海/超深区，bandIndex=1~3）
---@param wx number 世界X坐标
---@param wy number 世界Y坐标
---@return integer depthLevel 1~4
function M.GetFishDepthLevel(wx, wy)
    -- 1. 检查岛屿中心距离
    local allIslands = IslandSystem.GetIslands()
    if allIslands then
        for _, isl in pairs(allIslands) do
            local dx = wx - isl.x
            local dy = wy - isl.y
            if dx*dx + dy*dy < 500*500 then
                return 1
            end
        end
    end
    -- 2. 等高线深度分区
    local bandIdx = M.GetDepthBandAt(wx, wy)
    if bandIdx <= 3 then
        return 4   -- ≥25m 深海
    elseif bandIdx <= 5 then
        return 3   -- 5~25m 中层
    else
        return 2   -- 0~5m 近岸
    end
end

return M
