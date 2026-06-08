---@diagnostic disable: assign-type-mismatch
-- ============================================================================
-- 海上钓鱼 - 2D 俯视角拖钓游戏
-- 玩法: 开船在海面上行驶, 拖钓触发鱼咬钩, 力度条遛鱼
-- 渲染: 纯 NanoVG 矢量绘制 + 2D 水面 shader 效果
-- ============================================================================

require "LuaScripts/Utilities/Sample"
local PlatformUtils = require "urhox-libs.Platform.PlatformUtils"
local PlayerData = require "PlayerData"
local Inventory = require "Inventory"
local IslandMenu = require "IslandMenu"
local MapSampler = require "MapSampler"
local IslandSystem = require "IslandSystem"
local QuestSystem = require "QuestSystem"
local QuestPanel  = require "QuestPanel"
local FishAtlas   = require "FishAtlas"
local RodShop        = require "RodShop"
local HookSelector   = require "HookSelector"
local BaitSelector   = require "BaitSelector"
local BezierFrame   = require "BezierFrame"
local TimeWeather   = require "TimeWeather"
local LightEditor   = require "LightEditor"
local UICanvas      = require "UICanvas"
local UIPanel2      = require "UIPanel2"
local UISelector    = require "UISelector"
local Warehouse     = require "Warehouse"
BoatUpgrade         = require "BoatUpgrade"   -- 全局，避免 local-limit
CabinSystem         = require "CabinSystem"  -- 船舱装备系统
local FISH_DIST     = require "fish_dist_data"

-- ============================================================================
-- 平台标志（Start() 中初始化一次，全局复用）
-- ============================================================================
---@type boolean
local IS_MOBILE = false   -- true = Android/iOS，false = PC/Web

-- ============================================================================
-- NanoVG 上下文（前置声明，供等高线等函数引用）
-- ============================================================================
local vg = nil

-- ============================================================================
-- 程序化噪声（水下等高线用）
-- ============================================================================
local CONTOUR_NOISE_SCALE = 0.0008  -- 世界坐标 → 噪声坐标缩放

-- 岛屿隆起缓存（Start() 中由 BuildIslandBumps() 填充）
-- 每条: { x, y, r2inv, strength }
local _islandBumps = {}

-- 海沟凹陷（负高斯，压低地形 → 加深水深）
-- 用多个控制点连成弧形海沟，沿地图下部横向延伸
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
--- lo/hi 与 contourFBM 返回值对应；depth 为对应水深（米）供鱼种分布配置使用
DEPTH_BANDS = {
    { lo = 0.00, hi = 0.12, index = 1, name = "超深区", depthMin = 100, depthMax = 200, r = 5,  g = 12,  b = 45  },
    { lo = 0.12, hi = 0.30, index = 2, name = "深海区", depthMin = 40,  depthMax = 100, r = 15, g = 40,  b = 90  },
    { lo = 0.30, hi = 0.42, index = 3, name = "次深区", depthMin = 25,  depthMax = 40,  r = 25, g = 60,  b = 120 },
    { lo = 0.42, hi = 0.54, index = 4, name = "中层区", depthMin = 15,  depthMax = 25,  r = 38, g = 85,  b = 150 },
    { lo = 0.54, hi = 0.66, index = 5, name = "浅层区", depthMin = 5,   depthMax = 15,  r = 50, g = 110, b = 175 },
    { lo = 0.66, hi = 1.01, index = 6, name = "近岸区", depthMin = 0,   depthMax = 5,   r = 65, g = 140, b = 200 },
}

--- 深度网格（BuildDepthMap() 填充，供鱼种分布查询）
--- 格式: depthGrid_.data[gy][gx] = bandIndex (1~5)
---       depthGrid_.bounds, .res, .stepX, .stepY
local depthGrid_ = nil

-- 等高线噪声网格缓存（key = gridN，避免每帧重采样）
-- 世界范围固定时永久有效；岛屿变动时调用 InvalidateContourCache() 清除
local _contourGridCache = {}

local function InvalidateContourCache() _contourGridCache = {} end

-- 将噪声值 h 映射为 RGBA（颜色带间线性插值，模块级缓存）
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
local function DrawContourLines(wMinX, wMinY, wW, wH, gridN, w2s, bilinear, ctx)
    local g = ctx or vg   -- 允许传入离屏 context，默认使用主 vg
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
-- NanoVG 上下文（续）
-- ============================================================================
local fontId = -1

-- ── 对话框系统 ────────────────────────────────────────────────────────────
-- 使用方式：
--   Dialogue.Show("NPC名", "台词内容")   -- 弹出对话框
--   Dialogue.Hide()                       -- 关闭
--   Dialogue.IsOpen()                     -- 当前是否打开
local _dlgComp = require "saves.DialogueBox"   -- 贝塞尔 composite 存档
local _dlg = { open = false, speaker = "", text = "" }

Dialogue = {}
function Dialogue.Show(speaker, text)
    _dlg.open    = true
    _dlg.speaker = speaker or ""
    _dlg.text    = text    or ""
end
function Dialogue.Hide()  _dlg.open = false  end
function Dialogue.IsOpen() return _dlg.open  end

-- ============================================================================
-- 游戏配置
-- ============================================================================
local CFG = {
    -- 小船
    BOAT_MAX_SPEED   = 130,
    BOAT_ACCEL       = 90,
    BOAT_DECEL       = 30,
    BOAT_TURN_SPEED  = 0.7,
    BOAT_LENGTH      = 42,
    BOAT_WIDTH       = 21,
    BOAT_SCALE       = 2,          -- 船只显示缩放 (1=原始, 2=两倍)

    -- 拖钓
    LINE_LENGTH      = 250,
    ROPE_SEGMENTS    = 36,       -- 绳索节点数
    BITE_AVG_TIME    = 10.0,  -- 咬钩平均时间(秒)
    BITE_MIN_PCT     = 0.10,  -- 最小倍率: 平均值的10%
    BITE_MAX_PCT     = 3.00,  -- 最大倍率: 平均值的300%
    BITE_WINDOW      = 2.5,   -- 咬钩后反应时间
    ROD_COUNT        = 2,     -- 鱼竿数量
    BAG_SIZE         = 20,    -- 背包格子数（每格一条鱼，不叠加）

    -- 遛鱼系统 (基于 Godot 参考实现的弹性张力 + 极坐标鱼AI)
    FIGHT_LINE_MAX     = 750,    -- 最大线容量(米), 超过=清杯
    FIGHT_LINE_STRENGTH = 100,   -- 鱼线强度(kg), 张力超过此值=断线
    FIGHT_CATCH_DIST   = 40,     -- 鱼距 <= 此值 = 成功(米)
    FIGHT_STRETCH_MAX  = 25.0,   -- 最大弹性拉伸距离(米), 超过此距离张力=MAX

    -- 刹车 (档位制: 0~29 对应 0%~40%, 30档=锁死)
    FIGHT_DRAG_GEARS     = 30,   -- 总档数(不含锁死档)
    FIGHT_DRAG_MAX_RATIO = 0.40, -- 最高档(29)对应的张力比例
    FIGHT_DRAG_DEFAULT_GEAR = 15,-- 默认起始档位
    -- (静/动摩擦力已被约束解算替代, 不再需要)

    -- 卷轮 (收线 + 放线惯性)
    FIGHT_REEL_ACCEL   = 20.0,   -- 收线加速度(米/秒²)
    FIGHT_REEL_MAX     = 35.0,   -- 最大收线速度(米/秒)
    FIGHT_SLIP_MASS      = 0.0004, -- 卷轮虚拟质量(kg), 越大惯性越大加速越慢
    FIGHT_SLIP_DAMPING   = 0.01,  -- 粘性阻尼系数, 越大抖动越小但惯性感越弱
    FIGHT_SLIP_SPEED_MAX = 120,  -- 放线速度安全上限(米/秒)

    -- 打滑 (惯性模型)
    -- (打滑加速度/质量/最小持续已被约束解算替代, 不再需要)

    -- 视觉平滑
    FIGHT_SLIP_MEMORY  = 1.0,    -- 打滑记忆持续时间(秒, 仅用于显示)

    -- 鱼AI物理
    FISH_MASS          = 0.1,    -- 鱼的质量
    FISH_DRAG_COEFF    = 0.5,    -- 线性水阻力系数 (F = dragC * v)
    FISH_QUAD_DRAG     = 0.001,  -- 二次方水阻力系数基准值 (参考100g鱼); 实际值按 wMax^(2/3) 缩放
    FISH_SPEED_CAP     = 160,    -- 径向最大速度
    FISH_TAN_SPEED_CAP = 600,    -- 切向最大速度
    FISH_MAX_ANGLE     = 60,     -- 最大偏转角度(度)
    FISH_ANGLE_DAMP_START = 30,  -- 开始阻尼的角度(度)
    FISH_RESTORE_STR   = 2.0,    -- 角度恢复力强度

    -- 虚拟摇杆
    JOYSTICK_R       = 65,   -- 摇杆外圈半径
    JOYSTICK_INNER   = 24,   -- 摇杆内圈（摇头）半径
    ACTION_BTN_R     = 50,   -- 动作按钮半径
    INTERACT_BTN_R   = 44,   -- 互动按钮（靠岸/拾取）半径

    -- 抛竿蓄力
    CAST_CHARGE_TIME  = 1.5,    -- 满蓄力时间(秒)
    CAST_MIN_DIST     = 60,     -- 最小抛投距离(米)
    CAST_MAX_DIST     = 300,    -- 最大抛投距离(米)
    CAST_FLY_SPEED    = 600,    -- 鱼线飞行速度(米/秒)
    CAST_ARC_HEIGHT   = 50,     -- 抛物线高度(像素, 仅视觉)

    -- 抬杆 (提竿)
    STRIKE_DURATION   = 0.35,   -- 抬杆动画总时长(秒)
    STRIKE_LIFT_PX    = 12,     -- 鱼竿抬起最大高度(像素, sprite stack 偏移)
    STRIKE_SHAKE_AMP  = 3,      -- 鱼线抖动振幅(像素)
    STRIKE_ZOOM_PUNCH = 0.08,   -- 镜头缩放脉冲增量

    -- 抬杆 (蓄力抛竿)
    CAST_LIFT_MAX_ANGLE  = math.rad(110), -- 蓄力满格时最大抬起角度 (>90°=越顶后向对侧延伸，投石机效果)
    CAST_LIFT_PX         = 9,            -- 竿尖最大抬起像素偏移 (sprite stack)
    CAST_LIFT_DROP_SPEED = 9.0,          -- 抛出后回落速度 (1/秒)

    -- 抬杆 (fight 状态下右键压杆)
    FIGHT_LIFT_MAX_ANGLE = math.rad(55), -- 最大抬起角度(弧度), 55° ≈ 0.96 rad
    FIGHT_LIFT_SPEED_UP  = 1.4,          -- 抬杆基础速度 (慢抬, 1/秒)
    FIGHT_LIFT_SPEED_DOWN = 5.0,         -- 放杆基础速度 (快放, 1/秒)
    FIGHT_LIFT_TENSION_DRAG = 0.7,       -- 张力对抬杆的阻力系数 (0=无阻力, 1=满张力时速度归零)
    FIGHT_LIFT_PX        = 10,           -- 竿尖最大抬起像素偏移 (sprite stack 叠加)

    -- sprite stacking
    STACK_OFFSET         = 2.25,        -- 层间垂直偏移 (像素)
    ROD_STACK_LAYER      = 6.5,         -- 鱼竿所在 sprite-stack 层
}

-- ============================================================================
-- 钓竿数据
-- ============================================================================
-- 五档钓竿，按目标鱼体重分级。
-- lineStrength: 断线张力(kg)；stretchMax: 最大弹性伸展(m)，越小线越软。
-- dragMaxRatio 已移除，由渔线轮的 maxDragForce / lineStrength 动态计算。
-- 竿身颜色: secBase = 深色基调 RGB，secHighlight = 高光 RGB。
local ROD_TYPES = {
    {
        id   = 1,
        name = "溪钓竿",
        desc = "微小型鱼",
        lineStrength = 2.7,
        stretchMax   = 6.0,
        -- 竹绿色
        secBase      = { {20,50,20},{28,58,25},{38,68,32},{50,80,42},{68,95,55} },
        secHighlight = {120,180,100},
    },
    {
        id   = 2,
        name = "矶钓竿",
        desc = "微小&小型鱼",
        lineStrength = 9,
        stretchMax   = 12.0,
        -- 海蓝色
        secBase      = { {20,38,60},{26,46,72},{34,56,85},{44,68,100},{58,84,118} },
        secHighlight = {100,160,220},
    },
    {
        id   = 3,
        name = "路亚竿",
        desc = "小型&中型鱼",
        lineStrength = 36,
        stretchMax   = 20.0,
        -- 橙棕色
        secBase      = { {55,30,10},{68,38,14},{82,48,18},{98,60,24},{118,76,32} },
        secHighlight = {200,140,70},
    },
    {
        id   = 4,
        name = "船钓竿",
        desc = "中型大型鱼",
        lineStrength = 95,
        stretchMax   = 30.0,
        -- 深红/炭黑色
        secBase      = { {50,15,15},{62,20,18},{76,26,22},{92,34,28},{112,44,36} },
        secHighlight = {200,80,60},
    },
    {
        id   = 5,
        name = "重竿",
        desc = "大型巨型鱼",
        lineStrength = 205,
        stretchMax   = 55.0,
        -- 深紫/钛黑色
        secBase      = { {30,18,50},{38,24,62},{48,32,76},{60,42,92},{76,54,112} },
        secHighlight = {160,100,220},
    },
}

-- ============================================================================
-- 渔线轮数据
-- ============================================================================
-- maxDragForce : 最大刹车力(kg，绝对值)，与鱼竿 lineStrength 的比值即 dragMaxRatio
-- lineCapacity : 鱼线容量(米)，超过此值=清杯
-- 配套关系示例：溪钓竿(0.8kg)+溪钓轮 → dragMaxRatio=0.6/0.8=0.75
--              重竿(150kg)+重型轮     → dragMaxRatio=60/150=0.40
local REEL_TYPES = {
    {
        id           = 1,
        name         = "溪钓轮",
        desc         = "轻量纺车轮，适配溪钓竿",
        maxDragForce = 2,      -- kg
        lineCapacity = 300,    -- 米
        mechStrength = 5,      -- kg，渔轮机械强度上限
        reelSpeedMax = 15,     -- 最大收线速度(m/s)
        reelAccel    = 6,      -- 收线加速度(m/s²)
    },
    {
        id           = 2,
        name         = "矶钓轮",
        desc         = "通用纺车轮，适配矶钓竿",
        maxDragForce = 6,      -- kg
        lineCapacity = 450,    -- 米
        mechStrength = 20,     -- kg，渔轮机械强度上限
        reelSpeedMax = 20,     -- 最大收线速度(m/s)
        reelAccel    = 10,     -- 收线加速度(m/s²)
    },
    {
        id           = 3,
        name         = "路亚轮",
        desc         = "中型纺车轮，适配路亚竿",
        maxDragForce = 15,     -- kg
        lineCapacity = 550,    -- 米
        mechStrength = 40,     -- kg，渔轮机械强度上限
        reelSpeedMax = 25,     -- 最大收线速度(m/s)
        reelAccel    = 15,     -- 收线加速度(m/s²)
    },
    {
        id           = 4,
        name         = "船钓轮",
        desc         = "鼓形轮，适配船钓竿",
        maxDragForce = 35,     -- kg
        lineCapacity = 750,    -- 米
        mechStrength = 105,    -- kg，渔轮机械强度上限
        reelSpeedMax = 35,     -- 最大收线速度(m/s)
        reelAccel    = 15,     -- 收线加速度(m/s²)
    },
    {
        id           = 5,
        name         = "重型轮",
        desc         = "大容量海钓轮，适配重竿",
        maxDragForce = 36,     -- kg
        lineCapacity = 1500,   -- 米
        mechStrength = 300,    -- kg，渔轮机械强度上限
        reelSpeedMax = 45,     -- 最大收线速度(m/s)
        reelAccel    = 25,     -- 收线加速度(m/s²)
    },
}

-- ============================================================================
-- 鱼种数据
-- ============================================================================
local FISH_TYPES = {
    -- 翻车鱼
    { name="翻车鱼", diff=5,
      wMin=150, wMax=2300, wBias=0, wSpread=0.5,  wSample1=1067.4429,
      forceAtMax=700, forceExp=0.45,
      tanCoeff=1, radSpeedMax=130, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.7, label="calm", ampLo=0.1, ampHi=0.3, durMin=2, durMax=7 },
          { weight=0.25, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0.05, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=3 },
      }},
    -- 蓝鳍金枪鱼
    { name="蓝鳍金枪鱼", diff=5,
      wMin=30, wMax=680, wBias=0.2, wSpread=0.27,  wSample1=307.3665,
      forceAtMax=680, forceExp=0.45,
      tanCoeff=4, radSpeedMax=260, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.5, label="calm", ampLo=0.1, ampHi=0.3, durMin=4, durMax=7 },
          { weight=0.25, label="active", ampLo=0.35, ampHi=0.55, durMin=2, durMax=4.5 },
          { weight=0.25, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=7 },
      }},
    -- 大王乌贼
    { name="大王乌贼", diff=5,
      wMin=37.5, wMax=500, wBias=0.2, wSpread=0.27,  wSample1=234.8569,
      forceAtMax=500, forceExp=0.45,
      tanCoeff=0.5, radSpeedMax=130, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.25, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=4 },
          { weight=0.3, label="active", ampLo=0.35, ampHi=0.55, durMin=2, durMax=4.5 },
          { weight=0.45, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=3 },
      }},
    -- 长尾鲨
    { name="长尾鲨", diff=5,
      wMin=6, wMax=240, wBias=0.2, wSpread=0.27,  wSample1=105.8519,
      forceAtMax=240, forceExp=0.45,
      tanCoeff=2, radSpeedMax=260, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.6, label="calm", ampLo=0.1, ampHi=0.3, durMin=2, durMax=7 },
          { weight=0.3, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0.1, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=3 },
      }},
    -- 巨石斑鱼
    { name="巨石斑鱼", diff=5,
      wMin=7.5, wMax=300, wBias=0.2, wSpread=0.27,  wSample1=132.3149,
      forceAtMax=300, forceExp=0.45,
      tanCoeff=0.5, radSpeedMax=60, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.9, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=4 },
          { weight=0.1, label="active", ampLo=0.35, ampHi=0.55, durMin=2, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=3 },
      }},
    -- 魔鬼鱼
    { name="魔鬼鱼", diff=5,
      wMin=15, wMax=300, wBias=0.2, wSpread=0.27,  wSample1=136.6145,
      forceAtMax=300, forceExp=0.45,
      tanCoeff=1, radSpeedMax=130, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.9, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=4 },
          { weight=0.1, label="active", ampLo=0.35, ampHi=0.55, durMin=2, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=3 },
      }},
    -- 皇带鱼
    { name="皇带鱼", diff=5,
      wMin=15, wMax=270, wBias=0.2, wSpread=0.27,  wSample1=123.813,
      forceAtMax=270, forceExp=0.45,
      tanCoeff=0.5, radSpeedMax=60, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.9, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=4 },
          { weight=0.1, label="active", ampLo=0.35, ampHi=0.55, durMin=2, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=3 },
      }},
    -- 鼠鲨
    { name="鼠鲨", diff=5,
      wMin=18, wMax=250, wBias=0.2, wSpread=0.27,  wSample1=116.9985,
      forceAtMax=250, forceExp=0.45,
      tanCoeff=2, radSpeedMax=260, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.6, label="calm", ampLo=0.1, ampHi=0.3, durMin=2, durMax=7 },
          { weight=0.3, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0.1, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=3 },
      }},
    -- 青鲨
    { name="青鲨", diff=4,
      wMin=12, wMax=200, wBias=0.2, wSpread=0.27,  wSample1=92.2229,
      forceAtMax=200, forceExp=0.45,
      tanCoeff=2, radSpeedMax=260, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.6, label="calm", ampLo=0.1, ampHi=0.3, durMin=2, durMax=7 },
          { weight=0.3, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0.1, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=3 },
      }},
    -- 旗鱼
    { name="旗鱼", diff=4,
      wMin=12, wMax=150, wBias=0.2, wSpread=0.27,  wSample1=70.887,
      forceAtMax=150, forceExp=0.45,
      tanCoeff=4, radSpeedMax=260, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.5, label="calm", ampLo=0.1, ampHi=0.3, durMin=4, durMax=7 },
          { weight=0.25, label="active", ampLo=0.35, ampHi=0.55, durMin=2, durMax=4.5 },
          { weight=0.25, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=7 },
      }},
    -- 皱筛鲨
    { name="皱筛鲨", diff=4,
      wMin=6, wMax=100, wBias=0.2, wSpread=0.27,  wSample1=46.1115,
      forceAtMax=100, forceExp=0.45,
      tanCoeff=1, radSpeedMax=60, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.6, label="calm", ampLo=0.1, ampHi=0.3, durMin=2, durMax=7 },
          { weight=0.4, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=3 },
      }},
    -- 刺魟
    { name="刺魟", diff=4,
      wMin=4.5, wMax=100, wBias=0.2, wSpread=0.27,  wSample1=45.2515,
      forceAtMax=100, forceExp=0.45,
      tanCoeff=0.5, radSpeedMax=60, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.9, label="calm", ampLo=0.1, ampHi=0.3, durMin=2, durMax=7 },
          { weight=0.1, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=2.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=3 },
      }},
    -- 牛港鲹
    { name="牛港鲹", diff=4,
      wMin=2.25, wMax=80, wBias=0.2, wSpread=0.27,  wSample1=35.4273,
      forceAtMax=80, forceExp=0.45,
      tanCoeff=4, radSpeedMax=130, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.5, label="calm", ampLo=0.1, ampHi=0.3, durMin=2, durMax=7 },
          { weight=0.25, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0.25, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=3 },
      }},
    -- 犁头鳐
    { name="犁头鳐", diff=4,
      wMin=3, wMax=70, wBias=0.2, wSpread=0.27,  wSample1=31.5901,
      forceAtMax=70, forceExp=0.45,
      tanCoeff=0.5, radSpeedMax=60, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.9, label="calm", ampLo=0.1, ampHi=0.3, durMin=2, durMax=7 },
          { weight=0.1, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=2.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=3 },
      }},
    -- 长鳍金枪鱼
    { name="长鳍金枪鱼", diff=4,
      wMin=5.25, wMax=70, wBias=0.2, wSpread=0.27,  wSample1=32.88,
      forceAtMax=70, forceExp=0.45,
      tanCoeff=4, radSpeedMax=260, dragScale=0.5385, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.5, label="calm", ampLo=0.1, ampHi=0.3, durMin=2, durMax=7 },
          { weight=0.25, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=2.5 },
          { weight=0.25, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=3 },
      }},
    -- 月鱼
    { name="月鱼", diff=4,
      wMin=3, wMax=200, wBias=0.2, wSpread=0.27,  wSample1=87.0634,
      forceAtMax=200, forceExp=0.45,
      tanCoeff=1, radSpeedMax=60, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.9, label="calm", ampLo=0.1, ampHi=0.3, durMin=2, durMax=7 },
          { weight=0.1, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=3 },
      }},
    -- 海湾鲟
    { name="海湾鲟", diff=4,
      wMin=2.25, wMax=145, wBias=0.2, wSpread=0.27,  wSample1=63.1639,
      forceAtMax=145, forceExp=0.45,
      tanCoeff=4, radSpeedMax=260, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.5, label="calm", ampLo=0.1, ampHi=0.3, durMin=4, durMax=7 },
          { weight=0.25, label="active", ampLo=0.35, ampHi=0.55, durMin=2, durMax=4.5 },
          { weight=0.25, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=7 },
      }},
    -- 高体鰤
    { name="高体鰤", diff=4,
      wMin=1.2, wMax=72, wBias=0.2, wSpread=0.27,  wSample1=31.4116,
      forceAtMax=72, forceExp=0.45,
      tanCoeff=2, radSpeedMax=260, dragScale=0.5538, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.5, label="calm", ampLo=0.1, ampHi=0.3, durMin=2, durMax=7 },
          { weight=0.25, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0.25, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=3 },
      }},
    -- 红尾梭鱼
    { name="红尾梭鱼", diff=1,
      wMin=0.09, wMax=1.5, wBias=0.2, wSpread=0.27,  wSample1=0.6917,
      forceAtMax=1.5, forceExp=0.45,
      tanCoeff=2, radSpeedMax=130, dragScale=0.02308, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.9, label="calm", ampLo=0.1, ampHi=0.3, durMin=2, durMax=7 },
          { weight=0.1, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=3 },
      }},
    -- 真蛸
    { name="真蛸", diff=1,
      wMin=0.3, wMax=5, wBias=0.2, wSpread=0.27,  wSample1=2.3056,
      forceAtMax=5, forceExp=0.45,
      tanCoeff=2, radSpeedMax=130, dragScale=0.07692, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.9, label="calm", ampLo=0.1, ampHi=0.3, durMin=2, durMax=7 },
          { weight=0.1, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=3 },
      }},
    -- 裸胸鳝
    { name="裸胸鳝", diff=3,
      wMin=0.45, wMax=24, wBias=0.2, wSpread=0.27,  wSample1=10.4992,
      forceAtMax=24, forceExp=0.45,
      tanCoeff=0.5, radSpeedMax=60, dragScale=0.8, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.4, label="calm", ampLo=0.1, ampHi=0.3, durMin=4, durMax=7 },
          { weight=0.1, label="active", ampLo=0.35, ampHi=0.55, durMin=2, durMax=4.5 },
          { weight=0.5, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=7 },
      }},
    -- 海狼鱼
    { name="海狼鱼", diff=3,
      wMin=0.75, wMax=45, wBias=0.2, wSpread=0.27,  wSample1=19.6323,
      forceAtMax=45, forceExp=0.45,
      tanCoeff=2, radSpeedMax=130, dragScale=0.6923, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.5, label="calm", ampLo=0.1, ampHi=0.3, durMin=4, durMax=7 },
          { weight=0.25, label="active", ampLo=0.35, ampHi=0.55, durMin=2, durMax=4.5 },
          { weight=0.25, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=7 },
      }},
    -- 海鲇
    { name="海鲇", diff=2,
      wMin=0.45, wMax=20, wBias=0.2, wSpread=0.27,  wSample1=8.7923,
      forceAtMax=20, forceExp=0.45,
      tanCoeff=0.5, radSpeedMax=60, dragScale=0.6667, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.9, label="calm", ampLo=0.1, ampHi=0.3, durMin=2, durMax=7 },
          { weight=0.1, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 马鲛鱼
    { name="马鲛鱼", diff=4,
      wMin=1.8, wMax=140, wBias=0.2, wSpread=0.27,  wSample1=60.7724,
      forceAtMax=140, forceExp=0.45,
      tanCoeff=2, radSpeedMax=260, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.5, label="calm", ampLo=0.1, ampHi=0.3, durMin=4, durMax=7 },
          { weight=0.25, label="active", ampLo=0.35, ampHi=0.55, durMin=2, durMax=4.5 },
          { weight=0.25, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=7 },
      }},
    -- 真鲷
    { name="真鲷", diff=2,
      wMin=0.15, wMax=10, wBias=0.2, wSpread=0.27,  wSample1=4.3532,
      forceAtMax=10, forceExp=0.45,
      tanCoeff=1, radSpeedMax=130, dragScale=0.1538, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.6, label="calm", ampLo=0.1, ampHi=0.3, durMin=2, durMax=7 },
          { weight=0.3, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0.1, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 东星斑
    { name="东星斑", diff=2,
      wMin=0.375, wMax=20, wBias=0.2, wSpread=0.27,  wSample1=8.7493,
      forceAtMax=20, forceExp=0.45,
      tanCoeff=0.5, radSpeedMax=60, dragScale=0.6667, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.9, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0.1, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 牙鲆
    { name="牙鲆", diff=2,
      wMin=0.225, wMax=10, wBias=0.2, wSpread=0.27,  wSample1=4.3962,
      forceAtMax=10, forceExp=0.45,
      tanCoeff=0.5, radSpeedMax=25, dragScale=0.8, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.9, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0.1, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 金眼鲈
    { name="金眼鲈", diff=3,
      wMin=1.8, wMax=50, wBias=0.2, wSpread=0.27,  wSample1=22.3678,
      forceAtMax=50, forceExp=0.45,
      tanCoeff=4, radSpeedMax=260, dragScale=0.3846, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.4, label="calm", ampLo=0.1, ampHi=0.3, durMin=4, durMax=7 },
          { weight=0.35, label="active", ampLo=0.35, ampHi=0.55, durMin=2, durMax=4.5 },
          { weight=0.25, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=7 },
      }},
    -- 河豚
    { name="河豚", diff=1,
      wMin=0.15, wMax=3, wBias=0.2, wSpread=0.27,  wSample1=1.3661,
      forceAtMax=3, forceExp=0.45,
      tanCoeff=0.5, radSpeedMax=60, dragScale=0.1, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.9, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0.1, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 黑鲷
    { name="黑鲷", diff=2,
      wMin=0.12, wMax=6, wBias=0.2, wSpread=0.27,  wSample1=2.6291,
      forceAtMax=6, forceExp=0.45,
      tanCoeff=1, radSpeedMax=130, dragScale=0.09231, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.6, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0.3, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0.1, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 带鱼
    { name="带鱼", diff=2,
      wMin=0.3, wMax=12, wBias=0.2, wSpread=0.27,  wSample1=5.2926,
      forceAtMax=12, forceExp=0.45,
      tanCoeff=0.5, radSpeedMax=60, dragScale=0.4, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.6, label="calm", ampLo=0.1, ampHi=0.3, durMin=4, durMax=7 },
          { weight=0.3, label="active", ampLo=0.35, ampHi=0.55, durMin=2, durMax=4.5 },
          { weight=0.1, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=7 },
      }},
    -- 鲈鱼
    { name="鲈鱼", diff=2,
      wMin=0.255, wMax=7, wBias=0.2, wSpread=0.27,  wSample1=3.1332,
      forceAtMax=7, forceExp=0.45,
      tanCoeff=4, radSpeedMax=130, dragScale=0.1077, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.6, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0.3, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0.1, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 椰子海螺
    { name="椰子海螺", diff=1,
      wMin=0.15, wMax=2.5, wBias=0.2, wSpread=0.27,  wSample1=1.1528,
      forceAtMax=2.5, forceExp=0.45,
      tanCoeff=0.1, radSpeedMax=15, dragScale=0.3333, tanSpeedMax=600,
      radialStateTable = {
          { weight=1, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 金鲳鱼
    { name="金鲳鱼", diff=3,
      wMin=0.6, wMax=25, wBias=0.2, wSpread=0.27,  wSample1=11.0119,
      forceAtMax=25, forceExp=0.45,
      tanCoeff=4, radSpeedMax=260, dragScale=0.1923, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.6, label="calm", ampLo=0.1, ampHi=0.3, durMin=4, durMax=7 },
          { weight=0.3, label="active", ampLo=0.35, ampHi=0.55, durMin=2, durMax=4.5 },
          { weight=0.1, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=7 },
      }},
    -- 帆蜥
    { name="帆蜥", diff=3,
      wMin=0.6, wMax=22, wBias=0.2, wSpread=0.27,  wSample1=9.7318,
      forceAtMax=22, forceExp=0.45,
      tanCoeff=0.5, radSpeedMax=60, dragScale=0.7333, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.4, label="calm", ampLo=0.1, ampHi=0.3, durMin=4, durMax=7 },
          { weight=0.35, label="active", ampLo=0.35, ampHi=0.55, durMin=2, durMax=4.5 },
          { weight=0.25, label="active", ampLo=0.55, ampHi=0.85, durMin=6, durMax=7 },
      }},
    -- 灰仙鱼
    { name="灰仙鱼", diff=2,
      wMin=0.12, wMax=6, wBias=0.2, wSpread=0.27,  wSample1=2.6291,
      forceAtMax=6, forceExp=0.45,
      tanCoeff=1, radSpeedMax=60, dragScale=0.2, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.9, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0.1, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 鹦鹉螺
    { name="鹦鹉螺", diff=1,
      wMin=0.12, wMax=1.5, wBias=0.2, wSpread=0.27,  wSample1=0.7089,
      forceAtMax=1.5, forceExp=0.45,
      tanCoeff=0.5, radSpeedMax=15, dragScale=0.2, tanSpeedMax=600,
      radialStateTable = {
          { weight=1, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 鼠尾鳕
    { name="鼠尾鳕", diff=1,
      wMin=0.15, wMax=5, wBias=0.2, wSpread=0.27,  wSample1=2.2196,
      forceAtMax=5, forceExp=0.45,
      tanCoeff=0.5, radSpeedMax=25, dragScale=0.4, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.6, label="calm", ampLo=0.1, ampHi=0.3, durMin=4, durMax=7 },
          { weight=0.3, label="active", ampLo=0.35, ampHi=0.55, durMin=2, durMax=4.5 },
          { weight=0.1, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=7 },
      }},
    -- 褐拟鳞鲀
    { name="褐拟鳞鲀", diff=2,
      wMin=0.9, wMax=20, wBias=0.2, wSpread=0.27,  wSample1=9.0503,
      forceAtMax=20, forceExp=0.45,
      tanCoeff=1, radSpeedMax=130, dragScale=0.3077, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.5, label="calm", ampLo=0.1, ampHi=0.3, durMin=4, durMax=7 },
          { weight=0.25, label="active", ampLo=0.35, ampHi=0.55, durMin=2, durMax=4.5 },
          { weight=0.25, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=7 },
      }},
    -- 枪鱿
    { name="枪鱿", diff=1,
      wMin=0.09, wMax=4, wBias=0.2, wSpread=0.27,  wSample1=1.7585,
      forceAtMax=4, forceExp=0.45,
      tanCoeff=1, radSpeedMax=260, dragScale=0.03077, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.9, label="calm", ampLo=0.1, ampHi=0.3, durMin=4, durMax=7 },
          { weight=0.1, label="active", ampLo=0.35, ampHi=0.55, durMin=2, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=7 },
      }},
    -- 香蕉鱼
    { name="香蕉鱼", diff=1,
      wMin=0.045, wMax=0.8, wBias=0.2, wSpread=0.27,  wSample1=0.3672,
      forceAtMax=0.8, forceExp=0.45,
      tanCoeff=1, radSpeedMax=60, dragScale=0.02667, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.9, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0.1, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 鲭鱼
    { name="鲭鱼", diff=1,
      wMin=0.09, wMax=1.4, wBias=0.2, wSpread=0.27,  wSample1=0.649,
      forceAtMax=1.4, forceExp=0.45,
      tanCoeff=1, radSpeedMax=130, dragScale=0.02154, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.6, label="calm", ampLo=0.1, ampHi=0.3, durMin=4, durMax=7 },
          { weight=0.3, label="active", ampLo=0.35, ampHi=0.55, durMin=2, durMax=4.5 },
          { weight=0.1, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=7 },
      }},
    -- 绿毒鲉
    { name="绿毒鲉", diff=1,
      wMin=0.045, wMax=0.8, wBias=0.2, wSpread=0.27,  wSample1=0.3672,
      forceAtMax=0.8, forceExp=0.45,
      tanCoeff=0.5, radSpeedMax=25, dragScale=0.064, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.9, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0.1, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 鲍
    { name="鲍", diff=1,
      wMin=0.022, wMax=0.5, wBias=0.2, wSpread=0.27,  wSample1=0.226,
      forceAtMax=0.5, forceExp=0.45,
      tanCoeff=0.1, radSpeedMax=15, dragScale=0.06667, tanSpeedMax=600,
      radialStateTable = {
          { weight=1, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 刺尻鱼
    { name="刺尻鱼", diff=1,
      wMin=0.03, wMax=0.5, wBias=0.2, wSpread=0.27,  wSample1=0.2306,
      forceAtMax=0.5, forceExp=0.45,
      tanCoeff=0.5, radSpeedMax=60, dragScale=0.01667, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.9, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0.1, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 竹荚鱼
    { name="竹荚鱼", diff=1,
      wMin=0.09, wMax=2.4, wBias=0.2, wSpread=0.27,  wSample1=1.0757,
      forceAtMax=2.4, forceExp=0.45,
      tanCoeff=2, radSpeedMax=130, dragScale=0.03692, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.9, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0.1, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 棘海星
    { name="棘海星", diff=1,
      wMin=0.03, wMax=0.5, wBias=0.2, wSpread=0.27,  wSample1=0.2306,
      forceAtMax=0.5, forceExp=0.45,
      tanCoeff=0.1, radSpeedMax=15, dragScale=0.06667, tanSpeedMax=600,
      radialStateTable = {
          { weight=1, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 马夫鱼
    { name="马夫鱼", diff=1,
      wMin=0.022, wMax=0.6, wBias=0.2, wSpread=0.27,  wSample1=0.2686,
      forceAtMax=0.6, forceExp=0.45,
      tanCoeff=0.5, radSpeedMax=60, dragScale=0.02, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.9, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0.1, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 红海星
    { name="红海星", diff=1,
      wMin=0.022, wMax=0.4, wBias=0.2, wSpread=0.27,  wSample1=0.1833,
      forceAtMax=0.4, forceExp=0.45,
      tanCoeff=0.1, radSpeedMax=15, dragScale=0.05333, tanSpeedMax=600,
      radialStateTable = {
          { weight=1, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 黑蝴蝶鱼
    { name="黑蝴蝶鱼", diff=1,
      wMin=0.018, wMax=0.35, wBias=0.2, wSpread=0.27,  wSample1=0.1597,
      forceAtMax=0.35, forceExp=0.45,
      tanCoeff=1, radSpeedMax=60, dragScale=0.01167, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.9, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0.1, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 蓝指海星
    { name="蓝指海星", diff=1,
      wMin=0.015, wMax=0.3, wBias=0.2, wSpread=0.27,  wSample1=0.1366,
      forceAtMax=0.3, forceExp=0.45,
      tanCoeff=0.1, radSpeedMax=15, dragScale=0.04, tanSpeedMax=600,
      radialStateTable = {
          { weight=1, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 拟花鮨
    { name="拟花鮨", diff=1,
      wMin=0.022, wMax=0.3, wBias=0.2, wSpread=0.27,  wSample1=0.1406,
      forceAtMax=0.3, forceExp=0.45,
      tanCoeff=1, radSpeedMax=60, dragScale=0.01, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.9, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0.1, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 蓝圆鲹
    { name="蓝圆鲹", diff=2,
      wMin=0.3, wMax=7, wBias=0.2, wSpread=0.27,  wSample1=3.159,
      forceAtMax=7, forceExp=0.45,
      tanCoeff=2, radSpeedMax=130, dragScale=0.1077, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.6, label="calm", ampLo=0.1, ampHi=0.3, durMin=4, durMax=7 },
          { weight=0.3, label="active", ampLo=0.35, ampHi=0.55, durMin=2, durMax=4.5 },
          { weight=0.1, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=7 },
      }},
    -- 扇贝
    { name="扇贝", diff=1,
      wMin=0.015, wMax=0.3, wBias=0.2, wSpread=0.27,  wSample1=0.1366,
      forceAtMax=0.3, forceExp=0.45,
      tanCoeff=0.1, radSpeedMax=15, dragScale=0.04, tanSpeedMax=600,
      radialStateTable = {
          { weight=1, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 蝴蝶鱼
    { name="蝴蝶鱼", diff=1,
      wMin=0.015, wMax=0.3, wBias=0.2, wSpread=0.27,  wSample1=0.1366,
      forceAtMax=0.3, forceExp=0.45,
      tanCoeff=1, radSpeedMax=60, dragScale=0.01, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.9, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0.1, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 小丑鱼（伯爵）
    { name="小丑鱼（伯爵）", diff=1,
      wMin=0.003, wMax=0.07, wBias=0.2, wSpread=0.27,  wSample1=0.0316,
      forceAtMax=0.07, forceExp=0.45,
      tanCoeff=0.5, radSpeedMax=60, dragScale=0.0023, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.9, label="calm", ampLo=0.1, ampHi=0.3, durMin=4, durMax=7 },
          { weight=0.1, label="active", ampLo=0.35, ampHi=0.55, durMin=2, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=7 },
      }},
    -- 紫海胆
    { name="紫海胆", diff=1,
      wMin=0.003, wMax=0.25, wBias=0.2, wSpread=0.27,  wSample1=0.1084,
      forceAtMax=0.25, forceExp=0.45,
      tanCoeff=0.1, radSpeedMax=15, dragScale=0.03333, tanSpeedMax=600,
      radialStateTable = {
          { weight=1, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 小丑鱼
    { name="小丑鱼", diff=1,
      wMin=0.003, wMax=0.07, wBias=0.2, wSpread=0.27,  wSample1=0.0316,
      forceAtMax=0.07, forceExp=0.45,
      tanCoeff=0.5, radSpeedMax=60, dragScale=0.0023, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.9, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0.1, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 大鳍弹涂鱼
    { name="大鳍弹涂鱼", diff=1,
      wMin=0.012, wMax=0.15, wBias=0.2, wSpread=0.27,  wSample1=0.0709,
      forceAtMax=0.15, forceExp=0.45,
      tanCoeff=0.1, radSpeedMax=15, dragScale=0.02, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.9, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0.1, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 秋刀鱼
    { name="秋刀鱼", diff=1,
      wMin=0.012, wMax=0.15, wBias=0.2, wSpread=0.27,  wSample1=0.0709,
      forceAtMax=0.15, forceExp=0.45,
      tanCoeff=4, radSpeedMax=130, dragScale=0.0023, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.6, label="calm", ampLo=0.1, ampHi=0.3, durMin=4, durMax=7 },
          { weight=0.3, label="active", ampLo=0.35, ampHi=0.55, durMin=2, durMax=4.5 },
          { weight=0.1, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=7 },
      }},
    -- 文蛤
    { name="文蛤", diff=1,
      wMin=0.007, wMax=0.15, wBias=0.2, wSpread=0.27,  wSample1=0.068,
      forceAtMax=0.15, forceExp=0.45,
      tanCoeff=0.1, radSpeedMax=15, dragScale=0.02, tanSpeedMax=600,
      radialStateTable = {
          { weight=1, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 蛤蜊
    { name="蛤蜊", diff=1,
      wMin=0.004, wMax=0.1, wBias=0.2, wSpread=0.27,  wSample1=0.045,
      forceAtMax=0.1, forceExp=0.45,
      tanCoeff=0.1, radSpeedMax=15, dragScale=0.01333, tanSpeedMax=600,
      radialStateTable = {
          { weight=1, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 弹涂鱼
    { name="弹涂鱼", diff=1,
      wMin=0.007, wMax=0.1, wBias=0.2, wSpread=0.27,  wSample1=0.0467,
      forceAtMax=0.1, forceExp=0.45,
      tanCoeff=0.1, radSpeedMax=15, dragScale=0.01333, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.9, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0.1, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 沙丁鱼
    { name="沙丁鱼", diff=1,
      wMin=0.006, wMax=0.15, wBias=0.2, wSpread=0.27,  wSample1=0.0674,
      forceAtMax=0.15, forceExp=0.45,
      tanCoeff=2, radSpeedMax=130, dragScale=0.0023, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.6, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0.3, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0.1, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 贻贝
    { name="贻贝", diff=1,
      wMin=0.003, wMax=0.07, wBias=0.2, wSpread=0.27,  wSample1=0.0316,
      forceAtMax=0.07, forceExp=0.45,
      tanCoeff=0.1, radSpeedMax=15, dragScale=0.0093, tanSpeedMax=600,
      radialStateTable = {
          { weight=1, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 鞭冠鱼
    { name="鞭冠鱼", diff=2,
      wMin=0.3, wMax=6, wBias=0.2, wSpread=0.27,  wSample1=2.7323,
      forceAtMax=6, forceExp=0.45,
      tanCoeff=0.5, radSpeedMax=25, dragScale=0.48, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.6, label="calm", ampLo=0.1, ampHi=0.3, durMin=4, durMax=7 },
          { weight=0.3, label="active", ampLo=0.35, ampHi=0.55, durMin=2, durMax=4.5 },
          { weight=0.1, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=7 },
      }},
    -- 银斧鱼
    { name="银斧鱼", diff=1,
      wMin=0.003, wMax=0.07, wBias=0.2, wSpread=0.27,  wSample1=0.0316,
      forceAtMax=0.07, forceExp=0.45,
      tanCoeff=0.5, radSpeedMax=25, dragScale=0.0056, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.6, label="calm", ampLo=0.1, ampHi=0.3, durMin=4, durMax=7 },
          { weight=0.3, label="active", ampLo=0.35, ampHi=0.55, durMin=2, durMax=4.5 },
          { weight=0.1, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=7 },
      }},
    -- 测试鱼（保留）
    { name="测试鱼", diff=3, wMin=5, wMax=5, wBias=0.5, wSpread=0.3,
      forceAtMax=70, forceExp=0, tanCoeff=1, radSpeedMax=160, dragScale=0.875, tanSpeedMax=600,
      testFixed=true,
      radialStateTable = {
          { weight=1, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=3 },
      }},
}


-- 为每个鱼种注入自身索引（供精灵图查找使用）
do
    for i, ft in ipairs(FISH_TYPES) do
        ft.id = i
    end
end

-- 各竿兜底鱼：当实际钓获重量低于竿对应基础线时，替换为此类型
-- testFixed=true → 恒定力度，不受波动/体力影响
local FLOOR_FISH_TYPES = {
    -- 竿1 兜底 500g  (力量=重量/4)
    { name="小鱼", diff=1,
      wMin=0.5, wMax=0.5, wBias=0.5, wSpread=0,
      forceAtMax=0.125, forceExp=0,
      tanCoeff=0.8, radSpeedMax=60,  dragScale=0.06, tanSpeedMax=200,
      testFixed=true,
      radialStateTable = {
          { weight=1, label="active", ampLo=0.45, ampHi=0.75, durMin=1, durMax=3 },
      }},
    -- 竿2 兜底 1.5kg  (力量=重量/4)
    { name="小鱼", diff=2,
      wMin=1.5, wMax=1.5, wBias=0.5, wSpread=0,
      forceAtMax=0.375, forceExp=0,
      tanCoeff=1.0, radSpeedMax=80,  dragScale=0.19, tanSpeedMax=300,
      testFixed=true,
      radialStateTable = {
          { weight=1, label="active", ampLo=0.5,  ampHi=0.8,  durMin=1, durMax=3 },
      }},
    -- 竿3 兜底 5kg  (力量=重量/4)
    { name="小鱼", diff=3,
      wMin=5.0, wMax=5.0, wBias=0.5, wSpread=0,
      forceAtMax=1.25, forceExp=0,
      tanCoeff=1.0, radSpeedMax=100, dragScale=0.63, tanSpeedMax=400,
      testFixed=true,
      radialStateTable = {
          { weight=1, label="active", ampLo=0.5,  ampHi=0.8,  durMin=1, durMax=3 },
      }},
    -- 竿4 兜底 10kg  (力量=重量/4)
    { name="小鱼", diff=4,
      wMin=10.0, wMax=10.0, wBias=0.5, wSpread=0,
      forceAtMax=2.5, forceExp=0,
      tanCoeff=1.5, radSpeedMax=130, dragScale=1.25, tanSpeedMax=500,
      testFixed=true,
      radialStateTable = {
          { weight=1, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=3 },
      }},
    -- 竿5 兜底 20kg  (复用竿4力学参数，判定门槛提升)
    { name="小鱼", diff=4,
      wMin=20.0, wMax=20.0, wBias=0.5, wSpread=0,
      forceAtMax=2.5, forceExp=0,
      tanCoeff=1.5, radSpeedMax=130, dragScale=1.25, tanSpeedMax=500,
      testFixed=true,
      radialStateTable = {
          { weight=1, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=3 },
      }},
}
local ROD_MIN_FIGHT_WEIGHT = { 0.5, 1.5, 5.0, 10.0, 20.0 }

-- ============================================================================
-- 音效
-- ============================================================================
---@type Scene
local audioScene = nil
---@type Node
local audioNode = nil
---@type SoundSource
local sfxSlip = nil       -- 出线音效播放源
---@type SoundSource
local sfxReel = nil       -- 收线音效播放源
---@type Sound
local sndSlip = nil       -- 出线音效资源
---@type Sound
local sndReel = nil       -- 收线音效资源
---@type SoundSource
local sfxCast = nil       -- 抛投音效播放源
---@type SoundSource
local sfxNet = nil        -- 抄网/钓获音效播放源
---@type SoundSource
local sfxReelClicks = nil -- 出线咔哒音效播放源
---@type SoundSource
local sfxReelTurning = nil -- 收线转轮音效播放源
---@type SoundSource
local sfxShiftRatchet = nil -- 棘轮换挡音效播放源
---@type Sound
local sndCast = nil
---@type Sound
local sndNet = nil
---@type Sound
local sndReelClicks = nil
---@type Sound
local sndReelTurning = nil
---@type Sound
local sndShiftRatchet = nil
---@type SoundSource
local bgmSource = nil

-- ============================================================================
-- 游戏状态
-- ============================================================================
local STATE = "menu"     -- menu / sailing / trolling / bite / fight / catch / fail
local gameTime = 0

-- 竿线调试面板
local rodDebugMode    = false   -- 是否开启调试面板
local rodDebugLogTimer = 0       -- 日志打印节流计时器
local twStars_       = nil    -- 星星列表（首次使用时生成）
local twSliderDrag_  = false  -- 时间滑条是否正在拖拽
local TimeSliderHitTest  -- 前向声明，函数体在 DrawTimeSlider 附近定义
local screenW, screenH = 0, 0

-- 小船
local boat = {
    x = 0, y = 0,           -- 世界坐标
    angle = 0,               -- 朝向弧度 (0=上)
    speed = 0,
    cruise = false,          -- 巡航模式(持续行驶)
}

-- 相机 (跟随小船, 世界坐标偏移 + 缩放)
local camX, camY = 0, 0
local camScale = 1.0         -- 当前缩放 (1.0=正常, >1=放大/鱼看起来更快)
local camScaleTarget = 1.0   -- 目标缩放 (平滑过渡)

-- 尾流粒子
local wakeParticles = {}

-- 海浪精灵粒子
local waveSprites = {}
local waveImages = {}       -- nvgCreateImage handles
local imgFishShadow = -1    -- 鱼影贴图
local imgFishSheets = { -1, -1, -1, -1 }  -- [1]=fish_01.png, [2]=fish_02ui.png, [3]=fish_03ui.png, [4]=fish_04ui.png
local imgFishFull2  = -1    -- 鱼类高清图集 fish_02.png  (256×256, 64×64/格)
-- NPC 头像贴图 (切片1/2/3 对应 岛屿10/2/11)
local imgNpcAvatars  = { -1, -1, -1 }
local imgNpcShadows  = { -1, -1, -1 }  -- 预生成阴影图（跟随透明通道形状）
-- NPC 头像与岛屿的绑定 { islandId, avatarIndex }
local NPC_ISLAND_MAP = {
    { islandId = 10, avatarIdx = 1, offX =  100, offY = -100 },  -- 切片1: 右移100 上移100
    { islandId = 2,  avatarIdx = 2, offX =  -26, offY =  -70 },
    { islandId = 11, avatarIdx = 3, offX =  144, offY = -114 },
}
local WAVE_MAX = 18         -- 同时最大海浪数
local WAVE_SPAWN_CD = 0.8   -- 生成间隔(秒)
local waveSpawnTimer = 0
local WAVE_CURRENT_ANGLE = math.pi * 0.5  -- 向下

-- 双鱼竿系统
-- 每根鱼竿独立状态: "idle" / "trolling" / "bite"
local rods = {
    [1] = { state = "idle", timer = 0, biteAt = 0, biteTimer = 0, side = -1, rope = {}, aimAngle = 0, durability = 100 },  -- 左舷
    [2] = { state = "idle", timer = 0, biteAt = 0, biteTimer = 0, side =  1, rope = {}, aimAngle = 0, durability = 100 },  -- 右舷
}
local activeRod = 1     -- 当前选中的鱼竿 (1 或 2)
local equippedRodId  = 2  -- 当前装备的竿型 ID (1=溪钓竿 2=矶钓竿 3=船钓竿 4=重竿)
local equippedReelId = 2  -- 当前装备的渔线轮 ID (1=溪钓轮 2=矶钓轮 3=船钓轮 4=重型轮)

-- 鱼竿弯曲后竿尖世界坐标缓存 (每帧由 DrawBoat 更新)
local rodBentTips = {}

-- 抛竿蓄力状态
local castState = {
    charging = false,   -- 正在蓄力
    power    = 0,       -- 蓄力值 0~1
    liftT    = 0,       -- 抬杆进度 0~1 (蓄力时随 power 上升, 抛出后快速回落)
}

-- 抬杆动画状态
local strikeState = {
    active   = false,   -- 正在播放抬杆动画
    timer    = 0,       -- 动画计时器
    rodIndex = 0,       -- 哪根竿在抬
    fish     = nil,     -- 缓存待进入遛鱼的鱼
    splashX  = 0,       -- 水花世界坐标
    splashY  = 0,
}

-- 开发者鱼种选择菜单
local devFishSelect = false
local devFishInput  = ""      -- 正在输入的数字字符串 (支持1~99)
local devFishInputTimer = 0   -- 无操作超时确认计时器
-- 开发者批量钓鱼（N 键触发，选鱼种后直接入包10条）
local devBatch = { active = false, input = "", timer = 0 }
local inventoryOpen = false
local islandMenuOpen = false   -- false 或当前停靠的岛屿 landmark 引用
local dockedIsland = nil       -- 停靠中的岛屿对象
local questPanelOpen = false   -- 鱼铺面板开关
local fishAtlasOpen  = false   -- 鱼类图册开关（调试用，F2）
local rodShopOpen      = false   -- 鱼竿升级坊开关
local hookSelectorOpen = false   -- 鱼钩选择界面开关
local baitSelectorOpen = false   -- 鱼饵选择界面开关
warehouseOpen          = false   -- 仓库界面开关（全局，避免 local-limit）
boatUpgradeOpen        = false   -- 船只升级界面开关
cabinOpen              = false   -- 船舱装备界面开关

-- ── 垂钓模拟器（调试用）────────────────────────────────────────────────────
local fishSim = {
    running  = false,   -- 当前是否显示结果
    results  = nil,     -- 排序后的统计数组 { {name,count,pct}, ... }
    total    = 0,       -- 总钓鱼次数
    condStr  = "",      -- 条件摘要字符串
    scroll   = 0,       -- 滚动偏移（行数）
}

-- ── 天气系统 ────────────────────────────────────────────────────────────────
local weatherMode_    = "sunny"  -- "sunny" | "rain"
local rainIntensity_  = 0        -- 0.0 ~ 1.0 过渡权重
local rainDrops_      = {}       -- 雨滴粒子表
local RAIN_COUNT      = 180
local weatherTimer_   = 0        -- 当前天气剩余秒数
local weatherInited_  = false    -- 首次初始化标志
local mapOpen = false          -- 航海图是否打开
local mapClickPos = nil        -- 点击的世界坐标 {wx, wy}，nil 表示未点击
local mapLayout_  = nil        -- 当前帧地图布局参数（用于鼠标→世界坐标转换）
local zoneOverlayCache_ = nil  -- 海域分区色块缓存（首次打开地图时构建）
local zoneLabelCache_   = nil  -- 海域分区质心标签缓存

-- 小地图（直接实时绘制，无离屏缓存）

-- 深度标注点（大地图上显示深度区间）
local MAP_DEPTH_MARKERS = {
    { wx = -7365, wy = -4913 },
    { wx = -4891, wy =  3690 },
    { wx =   -36, wy =  3911 },
    { wx =  1109, wy =  -261 },
    { wx =  2419, wy =  -962 },
    { wx =  5170, wy = -2365 },
    { wx =  6333, wy = -6814 },
    { wx =  1976, wy =  5185 },
    { wx =  6148, wy =  2379 },
    { wx =  7514, wy =  3819 },
    { wx = -2491, wy = -3325 },
}

-- 诊断记录器
local diagEnabled = false       -- 是否正在记录
local diagLog = {}              -- { {t, tension, slipSpeed, lineLen, drag}, ... }
local diagStartTime = 0         -- 记录起始时间
local diagInfiniteLine = false  -- 无限线长模式
local diagFileCount = 0         -- 导出文件计数器

-- 实时波形图
local diagChartOn = false        -- 波形图开关
local DIAG_CHART_LEN = 480      -- 缓冲帧数 (~8秒@60fps)
local diagChartBuf = {}          -- 滚动缓冲 { tension, dragF }
local diagChartIdx = 0           -- 写入位置 (0-based 循环)

-- 遛鱼面板折叠 (Tab 切换)
local fightDetailOpen = false

-- 鱼影
local fishShadows = {}
local floatingPlanks = {}       -- 海面漂浮木板 {x, y, angle, drift, wobbleT, woodAmount}

-- ── 热点系统（气泡 + 鱼影聚集） ──────────────────────────────────────────
-- hotspots[i] = { wx, wy, bubbles={...}, fish={...} }
-- 直接复用 MAP_DEPTH_MARKERS 坐标作为热点位置
local hotspots = {}             -- 初始化后由 InitHotspots() 填充
local HOTSPOT_BUBBLE_MAX = 12   -- 每个热点同屏最多气泡数
local HOTSPOT_FISH_COUNT = 5    -- 每个热点鱼影数量
local HOTSPOT_RADIUS    = 160   -- 热点鱼的活动半径（世界单位）
local PLANK_PICKUP_DIST = 40    -- 拾取距离(米)
local PLANK_COUNT = 8           -- 初始木板数量
local PLANK_RESPAWN_DIST = 600  -- 离船太远时回收重生
local ISLAND_DOCK_DIST = 120   -- 岛屿停靠交互半径

-- ── 海域分区系统 ─────────────────────────────────────────────────────────
-- R 通道值 → { 颜色1(亮), 颜色2(暗), 代号 }
local ZONE_TABLE = {
    [0]   = { {23,74,119},  {18,60,100},  "外海" },
    [30]  = { {29,78,121},  {24,64,102},  "外海" },
    [50]  = { {40,150,172}, {32,126,148}, "热带海" },
    [70]  = { {40,141,172}, {32,118,148}, "热带海" },
    [90]  = { {45,95,117},  {36,78,100},  "沙漠海" },
    [110] = { {45,90,117},  {36,74,100},  "沙漠海" },
    [130] = { {73,122,175}, {58,102,148}, "寒带海" },
    [150] = { {77,114,179}, {62,96,152},  "寒带海" },
    [170] = { {89,125,187}, {72,105,160}, "寒带海" },
    [190] = { {57,125,164}, {45,110,150}, "浅海" },   -- 默认/当前
    [210] = { {29,88,149},  {24,72,126},  "外海" },
}
-- 区域 R 值 → 海域类型索引 (1=浅海 2=热带海 3=沙漠海 4=寒带海 5=外海)
local ZONE_TYPE_MAP = {
    [0]=5, [30]=5, [50]=2, [70]=2, [90]=3, [110]=3,
    [130]=4, [150]=4, [170]=4, [190]=1, [210]=5,
}
local currentZoneR = 190          -- 当前区域 R 值
local targetZoneR  = 190          -- 目标区域 R 值
local zoneColorT   = 1.0          -- 颜色过渡进度 0→1
local ZONE_FADE_SPEED = 1.5       -- 过渡速度（秒⁻¹）
local zoneNotify = { text = "", timer = 0, alpha = 0 }  -- 区域切换通知
local pendingZoneR = 190          -- 候选区域 R 值（去抖用）
local pendingZoneTime = 0         -- 候选区域驻留时间
local ZONE_DEBOUNCE = 1.0         -- 需持续驻留 1 秒才确认切换

-- 遛鱼系统 (极坐标鱼AI + 弹性张力)
local fight = {
    -- 竿型快照 (StartFight 时从 equippedRodId 写入)
    rodId        = 2,
    lineStrength = 8,          -- 断线张力(kg), 由竿型决定
    stretchMax   = 12.0,       -- 最大弹性伸展(m), 由竿型决定

    -- 线与张力
    lineLength   = 0,          -- 当前鱼线长度(米) = 卷轮上放出的线
    tension      = 0,          -- 实际张力(kg)
    tensionVisual = 0,         -- 显示用张力(kg)
    dragGear     = 15,         -- 刹车档位 0~30 (30=锁死)
    drag         = 0,          -- 刹车比例 (由 dragGear 派生)

    -- 鱼极坐标 (相对于竿尖)
    fishRadius   = 0,          -- 鱼到竿尖的距离(米)
    fishAngle    = 0,          -- 鱼的角度(弧度, 相对初始方向)
    fishInitAngle = 0,         -- 咬钩时的初始角度(弧度)
    fishRadVel   = 0,          -- 径向速度(米/秒, 正=远离)
    fishAngVel   = 0,          -- 角速度(弧度/秒)

    -- 径向波动
    radWaveTime  = 0,          -- 当前波形已持续时间
    radWaveDur   = 1,          -- 当前波形总周期
    radWaveBase  = 0,          -- 波形基础值 (0-1)

    -- 径向振幅状态 (calm/active 双状态机)
    radState     = "calm",     -- "calm" / "active"
    radStateTimer = 0,         -- 当前状态已持续时间
    radStateDur  = 0,          -- 当前状态目标时长
    radAmpPctTarget = 0,       -- 目标振幅 (基线的百分比)
    radAmpPct    = 0,          -- 当前振幅百分比 (平滑过渡)

    -- 切向波动
    tanWaveTime  = 0,
    tanWaveDur   = 1,
    tanWaveAmp   = 0,
    tanWaveBase  = 0,
    tanState     = "calm",     -- "calm" / "active"
    tanTimer     = 0,          -- 当前切向状态持续时间
    tanDuration  = 0,          -- 当前切向状态目标时长

    -- 挣扎微力 (tremor + jerk)
    tremorPhase  = 0,          -- 颤动相位(弧度, 持续累加)
    tremorPhase2 = 0,          -- 第二谐波相位(更自然)
    jerkTimer    = 0,          -- 甩头剩余时间
    jerkDurTotal = 0,          -- 甩头总时长(用于包络计算)
    jerkCooldown = 0,          -- 甩头冷却计时
    jerkAmp      = 0,          -- 当前甩头振幅系数

    -- 打滑 (卷轮惯性模型)
    slipping     = false,      -- 本帧是否发生放线
    slipSpeed    = 0,          -- 当前放线速度(米/秒, >=0)

    -- 收线
    reeling      = false,      -- 玩家是否按住收线键
    reelSpeed    = 0,          -- 当前收线速度(加速度模型)
    effectiveReel = 0,         -- 有效收线速度(受张力衰减, 供UI显示)
    reelAngle    = 0,          -- 卷轮图标累积旋转角度(弧度)

    -- 视觉平滑
    slipRecentTimer = 0,       -- 最近打滑记忆计时器

    -- 断线延迟
    breakTimer   = 0,          -- 断线倒计时(秒)
    breakDelay   = 0,          -- 断线延迟时长(随机 0.2~0.7秒)
    -- 渔线轮损坏延迟
    reelBreakTimer = 0,        -- 渔线轮损坏倒计时(秒)

    -- 鱼体力
    fishStamina  = 100,
    fishMaxStam  = 100,

    -- 元数据
    fightTime    = 0,
    resultTimer  = 0,
}

-- 当前钓到的鱼
local curFish = nil
local curFightType = nil  -- 兜底替换时的战斗参数类型，nil 表示使用 curFish.type

-- 收获
local caughtList = {}
local totalWeight = 0.0

-- 浮标 / 岛屿 (世界坐标)
local landmarks = {}

-- 水面时间
local waterTime = 0

-- 通知
local notify = { text = "", timer = 0, color = {255,255,255,255} }

-- 启动封面
local splash = {
    active = true,    -- 封面是否激活
    fadeOut = false,   -- 是否正在淡出
    alpha  = 1.0,     -- 当前不透明度 (1.0 = 完全遮挡)
    dotTimer = 0,     -- 加载动画计时
}

-- 虚拟摇杆
local vJoy = {
    active = false,
    baseX = 0, baseY = 0,
    stickX = 0, stickY = 0,
    dx = 0, dy = 0,
}

-- 动作按钮
local actionJustPressed = false
local actionDown = false
local prevActionDown = false

-- 互动按钮（靠岸 / 拾取漂浮物）
local interactBtnDown      = false
local prevInteractBtnDown  = false
local interactBtnJustPress = false

-- 移动端 HUD 工具条（每帧 DrawMobileToolbar 填充，UpdateVirtualInput rising-edge 消费）
local hudBtns_       = {}    -- { id, x, y, w, h }
local lastMouseDown_ = false  -- 上一帧触摸状态，用于 rising-edge 检测

-- ============================================================================
-- 地形工具
-- ============================================================================

--- 从 island_registry 读取所有岛屿，预计算高斯隆起参数
--- 隆起半径 = max(w, h) × BUMP_RADIUS_MULT，强度固定 0.38
--- exp(-d²/r²) 在 d=0 时 = strength，d=r 时 ≈ 0.37×strength，d=2r 时 ≈ 0.018×strength
local BUMP_RADIUS_MULT = 3.0   -- 隆起半径倍率（相对于岛屿最大边长）
local BUMP_STRENGTH    = 0.38  -- 隆起强度（叠加到 FBM 高度）

function BuildIslandBumps()
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

--- 预采样深度网格，构建坐标→深度分区的查询数组
--- 在 Start() 中 BuildIslandBumps() 之后调用（需要 _islandBumps 已就绪）
--- 分辨率 DEPTH_MAP_RES×DEPTH_MAP_RES，覆盖整个世界范围
local DEPTH_MAP_RES    = 100   -- 网格精度（越高越准，启动稍慢）
local DEPTH_MAP_BOUNDS = { minX = -9000, maxX = 9000, minY = -8000, maxY = 7000 }

function BuildDepthMap()
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
            local idx = #DEPTH_BANDS  -- 默认最浅
            for i, band in ipairs(DEPTH_BANDS) do
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

--- 查询世界坐标对应的深度分区索引 (1=深海区 … 5=近岸区)
--- 使用预采样网格，O(1) 速度，适合鱼种生成时高频调用
---@param wx number 世界 X 坐标
---@param wy number 世界 Y 坐标
---@return integer bandIndex  深度分区索引 1~5
---@return table   band       DEPTH_BANDS 中对应的分区记录
function GetDepthBandAt(wx, wy)
    if not depthGrid_ then
        -- 回退：实时计算
        local h = contourFBM(wx, wy)
        for i, band in ipairs(DEPTH_BANDS) do
            if h >= band.lo and h < band.hi then return i, band end
        end
        return #DEPTH_BANDS, DEPTH_BANDS[#DEPTH_BANDS]
    end
    local b  = depthGrid_.bounds
    local gx = math.floor((wx - b.minX) / depthGrid_.stepX + 0.5)
    local gy = math.floor((wy - b.minY) / depthGrid_.stepY + 0.5)
    gx = math.max(0, math.min(depthGrid_.res, gx))
    gy = math.max(0, math.min(depthGrid_.res, gy))
    local idx = depthGrid_.data[gy][gx]
    return idx, DEPTH_BANDS[idx]
end

--- 根据世界坐标返回鱼类深度级别 (1~4)
-- 1级: 岛屿中心500世界单位以内（码头浅滩）
-- 2级: 0~5m（近岸区，bandIndex=6）
-- 3级: 5~25m（浅层/中层区，bandIndex=4~5）
-- 4级: 25m以上（次深/深海/超深区，bandIndex=1~3）
---@param wx number 世界X坐标
---@param wy number 世界Y坐标
---@return integer depthLevel 1~4
local function GetFishDepthLevel(wx, wy)
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
    local bandIdx = GetDepthBandAt(wx, wy)
    if bandIdx <= 3 then
        return 4   -- ≥25m 深海
    elseif bandIdx <= 5 then
        return 3   -- 5~25m 中层
    else
        return 2   -- 0~5m 近岸
    end
end

-- ============================================================================
-- 生命周期
-- ============================================================================

function Start()
    SampleStart()
    graphics.windowTitle = "海上钓鱼"

    vg = nvgCreate(1)
    if not vg then
        print("ERROR: nvgCreate failed")
        return
    end
    fontId = nvgCreateFont(vg, "sans", "Fonts/MiSans-Regular.ttf")
    local fontIdBold = nvgCreateFont(vg, "sans-bold", "Fonts/MiSans-Bold.ttf")
    BezierFrame.SetFont(vg, fontId)
    BezierFrame.SetBoldFont(vg, fontIdBold)   -- 对话框使用 MiSans Bold

    -- 海浪帧动画贴图 (8帧)
    waveImages = {}
    for i = 0, 7 do
        local id = nvgCreateImage(vg, "image/wave_frame_" .. i .. ".png", 0)
        if id == 0 then print("[WARN] wave frame not loaded: #" .. i) end
        table.insert(waveImages, id)
    end

    imgFishShadow = nvgCreateImage(vg, "image/fish_shadow.png", 0)
    imgFishSheets[1] = nvgCreateImage(vg, "image/fish_01.png",   NVG_IMAGE_NEAREST)  -- 512×96,  32×32/格
    imgFishSheets[2] = nvgCreateImage(vg, "image/fish_02ui.png", NVG_IMAGE_NEAREST)  -- 128×128, 32×32/格
    imgFishSheets[3] = nvgCreateImage(vg, "image/fish_03ui.png", NVG_IMAGE_NEAREST)  -- 160×32,  32×32/格
    imgFishSheets[4] = nvgCreateImage(vg, "image/fish_04ui.png", NVG_IMAGE_NEAREST)  -- 128×96,  32×32/格
    imgFishFull2  = nvgCreateImage(vg, "image/fish_02.png",   NVG_IMAGE_NEAREST)  -- 256×256, 64×64/格，全图展示用
    if imgFishSheets[1] == 0 then print("[WARN] fish_01.png not loaded")   end
    if imgFishSheets[2] == 0 then print("[WARN] fish_02ui.png not loaded") end
    if imgFishSheets[3] == 0 then print("[WARN] fish_03ui.png not loaded") end
    if imgFishSheets[4] == 0 then print("[WARN] fish_04ui.png not loaded") end
    if imgFishFull2  == 0 then print("[WARN] fish_02.png not loaded")   end
    -- NPC 头像
    imgNpcAvatars[1] = nvgCreateImage(vg, "image/npc/切片1.png", 0)
    imgNpcAvatars[2] = nvgCreateImage(vg, "image/npc/切片2.png", 0)
    imgNpcAvatars[3] = nvgCreateImage(vg, "image/npc/切片3.png", 0)
    imgNpcShadows[1] = nvgCreateImage(vg, "image/npc/shadow1.png", 0)
    imgNpcShadows[2] = nvgCreateImage(vg, "image/npc/shadow2.png", 0)
    imgNpcShadows[3] = nvgCreateImage(vg, "image/npc/shadow3.png", 0)
    for i = 1, 3 do
        if imgNpcAvatars[i] == 0 then print("[WARN] npc avatar " .. i .. " not loaded") end
        if imgNpcShadows[i] == 0 then print("[WARN] npc shadow " .. i .. " not loaded") end
    end
    IslandMenu.Init(vg)
    RodShop.Init(vg)
    Inventory.Init(vg)
    FishAtlas.Init(vg)

    -- (旧岛屿/装饰贴图已移除，由 IslandSystem 统一管理)

    -- 平台检测（只调用一次，后续用 IS_MOBILE 判断）
    IS_MOBILE = PlatformUtils.IsMobilePlatform()
    print("[Platform] " .. PlatformUtils.GetPlatform() .. "  IS_MOBILE=" .. tostring(IS_MOBILE))

    SampleInitMouseMode(MM_FREE)

    -- 音效初始化
    audioScene = Scene()
    audioNode = audioScene:CreateChild("SFX")
    sfxSlip = audioNode:CreateComponent("SoundSource")
    sfxSlip.soundType = "Effect"
    sndSlip = cache:GetResource("Sound", "audio/sfx/reel_slip.ogg")
    sndSlip.looped = true

    sfxReel = audioNode:CreateComponent("SoundSource")
    sfxReel.soundType = "Effect"
    sndReel = cache:GetResource("Sound", "audio/sfx/reel_wind.ogg")
    sndReel.looped = true

    sfxCast = audioNode:CreateComponent("SoundSource")
    sfxCast.soundType = "Effect"
    sndCast = cache:GetResource("Sound", "audio/sfx/cast_whoosh.mp3")

    sfxNet = audioNode:CreateComponent("SoundSource")
    sfxNet.soundType = "Effect"
    sndNet = cache:GetResource("Sound", "audio/sfx/net_splash.mp3")

    sfxReelClicks = audioNode:CreateComponent("SoundSource")
    sfxReelClicks.soundType = "Effect"
    sndReelClicks = cache:GetResource("Sound", "audio/sfx/reel_clicks.ogg")
    sndReelClicks.looped = true

    sfxReelTurning = audioNode:CreateComponent("SoundSource")
    sfxReelTurning.soundType = "Effect"
    sfxReelTurning.gain = 0.35
    sndReelTurning = cache:GetResource("Sound", "audio/sfx/reel_turning.ogg")
    sndReelTurning.looped = true

    sfxShiftRatchet = audioNode:CreateComponent("SoundSource")
    sfxShiftRatchet.soundType = "Effect"
    sndShiftRatchet = cache:GetResource("Sound", "audio/sfx/shift_ratchet.ogg")

    -- BGM（无缝循环）
    local bgmSound = cache:GetResource("Sound", "audio/music_1778898689971.ogg")
    if bgmSound then
        bgmSound.looped = true
        bgmSource = audioNode:CreateComponent("SoundSource")
        bgmSource.soundType = "Music"
        bgmSource.gain = 0.55
        bgmSource:Play(bgmSound)
    end

    -- 初始化地标
    -- 注册地图采样图层（图片中心 = 船出生点 (0,0)）
    -- 1200px × 20 = 24000 世界单位覆盖，Lua 数据绕过纹理压缩管线
    MapSampler.Register("fish_density", "fish_density_data", 0, 0, 20)
    MapSampler.Register("zone", "zone_partition_data", 0, 0, 20)

    IslandSystem.Init(vg)
    BuildIslandBumps()
    BuildDepthMap()
    -- 预计算各深度标注点的水深区间
    for _, m in ipairs(MAP_DEPTH_MARKERS) do
        local _, band = GetDepthBandAt(m.wx, m.wy)
        m.band = band
    end
    InitLandmarks()
    InitWaveSprites()
    InitFishShadows()
    InitHotspots()
    InitFloatingPlanks()

    SubscribeToEvent(vg, "NanoVGRender", "HandleRender")
    UICanvas.Init(vg)
    UIPanel2.Init(vg, imgFishSheets[1], imgFishFull2,
        nvgCreateImage(vg, "image/fish_03.png", NVG_IMAGE_NEAREST),
        nvgCreateImage(vg, "image/fish_04.png", NVG_IMAGE_NEAREST))
    UIPanel2.SetOnClose(function()
        if STATE == "catch" or STATE == "fail" then
            STATE = "sailing"
        end
    end)

    -- UI 选择器：1=对话框，2=UIPanel2
    UISelector.Init({
        { label = "对话框",  open = function() Dialogue.Show("渔夫老张", "今天风浪不小，小心点出海！前方海域发现了一片珍稀鱼群。") end,
                             close = function() Dialogue.Hide() end,
                             isOpen = function() return Dialogue.IsOpen() end },
        { label = "UI 面板 2", open = function() UIPanel2.Open() end,
                               close = function() UIPanel2.Close() end,
                               isOpen = function() return UIPanel2.IsOpen() end },
    })

    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("KeyDown", "HandleKeyDown")
    SubscribeToEvent("MouseButtonDown", "HandleMouseButtonDown")
    SubscribeToEvent("MouseButtonUp",   "HandleMouseButtonUp")
    SubscribeToEvent("MouseMove",       "HandleMouseMove")
    SubscribeToEvent("MouseWheel",      "HandleMouseWheel")
    SubscribeToEvent("TextInput",       "HandleTextInput")

    -- 初始数值（测试用，后续由存档系统替代）
    PlayerData.AddMoney(150)
    PlayerData.AddResource("wood", 30)

    print("=== 海上钓鱼 ===")
end

function Stop()
    if vg then nvgDelete(vg) end
end

-- ============================================================================
-- 初始化
-- ============================================================================

function InitLandmarks()
    landmarks = {}
    islandDecos = {}

    -- ════════════════════════════════════════════════════════════════════════
    -- 从 IslandSystem 填充 landmarks 表（保持与 IslandMenu / 停靠系统兼容）
    -- 岛屿图层渲染由 IslandSystem 独立处理，landmarks 仅提供功能数据
    -- ════════════════════════════════════════════════════════════════════════
    for id, island in pairs(IslandSystem.GetIslands()) do
        local lm = {
            kind     = "island",
            id       = island.id,
            name     = "岛屿 " .. island.id,
            x        = island.x,
            y        = island.y,
            drawW    = island.w * 2,   -- TEXTURE_SCALE = 2
            drawH    = island.h * 2,
            angle    = 0,
            features = {},
        }
        table.insert(landmarks, lm)
    end

    print("[Landmarks] Loaded " .. #landmarks .. " islands (via IslandSystem)")
end

-- ============================================================================
-- 海浪精灵系统 (手绘风浪花漂浮在海面上)
-- ============================================================================

function InitWaveSprites()
    waveSprites = {}
    -- 预生成一批初始海浪, 散布在相机周围
    for _ = 1, WAVE_MAX do
        SpawnWaveSprite(true)
    end
end

function SpawnWaveSprite(randomAge)
    if #waveImages == 0 then return end
    -- 原图比例 155:61 ≈ 2.54:1, 缩小3倍
    local baseW = 167
    local baseH = 66
    local scaleMul = 0.8 + math.random() * 0.6  -- 0.8~1.4

    -- 帧动画: 淡入 → 播放一个周期 → 淡出
    local frameCount = #waveImages
    local animSpeed = 4 + math.random() * 3  -- 4~7 fps (慢一点更自然)
    local cycleDur = frameCount / animSpeed
    local fi = 0.5   -- 淡入时长
    local fo = 1.0   -- 淡出时长
    local maxLife = fi + cycleDur + fo
    local age = randomAge and (math.random() * maxLife) or 0

    -- 生成在相机可见区域附近
    local spawnRange = 900
    local wx = camX + (math.random() - 0.5) * spawnRange * 2
    local wy = camY + (math.random() - 0.5) * spawnRange * 2

    -- 统一洋流方向, 统一朝向
    local driftAngle = WAVE_CURRENT_ANGLE
    local driftSpeed = 7.5 + math.random() * 9

    -- 所有海浪朝向一致
    local facing = 0

    table.insert(waveSprites, {
        x = wx, y = wy,
        w = baseW * scaleMul,
        h = baseH * scaleMul,
        angle = facing,
        dx = math.cos(driftAngle) * driftSpeed,
        dy = math.sin(driftAngle) * driftSpeed,
        life = maxLife,
        age = age,
        fadeIn = fi,
        fadeOut = fo,
        frameTimer = math.random() * frameCount / animSpeed,  -- 随机起始相位
        animSpeed = animSpeed,
    })
end

function UpdateWaveSprites(dt)
    -- 更新现有海浪
    for i = #waveSprites, 1, -1 do
        local w = waveSprites[i]
        w.age = w.age + dt
        if w.age >= w.life then
            table.remove(waveSprites, i)
        else
            -- 漂移
            w.x = w.x + w.dx * dt
            w.y = w.y + w.dy * dt
            -- 帧动画推进
            w.frameTimer = w.frameTimer + dt
        end
    end

    -- 补充新海浪
    waveSpawnTimer = waveSpawnTimer + dt
    if waveSpawnTimer >= WAVE_SPAWN_CD and #waveSprites < WAVE_MAX then
        waveSpawnTimer = 0
        SpawnWaveSprite(false)
    end
end

function DrawWaveSprites()
    local frameCount = #waveImages
    if frameCount == 0 then return end

    for _, w in ipairs(waveSprites) do
        local sx, sy = WorldToScreen(w.x, w.y)
        local margin = math.max(w.w, w.h)
        if sx > -margin and sx < screenW + margin and sy > -margin and sy < screenH + margin then
            -- 淡入淡出 alpha
            local alpha = 1.0
            if w.age < w.fadeIn then
                alpha = w.age / w.fadeIn
            elseif w.age > w.life - w.fadeOut then
                alpha = (w.life - w.age) / w.fadeOut
            end
            alpha = math.max(0, math.min(1, alpha)) * 0.7

            -- 帧动画: 播放一个周期后停在最后一帧
            local rawFrame = math.floor(w.frameTimer * w.animSpeed)
            local frameIdx = math.min(rawFrame, frameCount - 1) + 1
            local imgId = waveImages[frameIdx]
            if imgId and imgId > 0 then
                nvgSave(vg)
                nvgTranslate(vg, sx, sy)
                nvgRotate(vg, w.angle)
                nvgGlobalAlpha(vg, alpha)

                local pat = nvgImagePattern(vg, -w.w/2, -w.h/2, w.w, w.h, 0, imgId, 1.0)
                nvgBeginPath(vg)
                nvgRect(vg, -w.w/2, -w.h/2, w.w, w.h)
                nvgFillPaint(vg, pat)
                nvgFill(vg)

                nvgRestore(vg)
            end
        end
    end
end

function InitFishShadows()
    fishShadows = {}
    for i = 1, 12 do
        table.insert(fishShadows, {
            x = boat.x + math.random(-400, 400),
            y = boat.y + math.random(-400, 400),
            angle = math.random() * math.pi * 2,
            speed = 20 + math.random(30),
            size = 8 + math.random(12),
            wobble = math.random() * 10,
            attracted = false,
        })
    end
end

-- ── 热点系统 ─────────────────────────────────────────────────────────────────

--- 按 MAP_DEPTH_MARKERS 坐标建立热点，每个热点拥有独立气泡池和鱼影群
local HOTSPOT_RING_INTERVAL = 1.4  -- 每隔多少秒生成一个新环
local HOTSPOT_RING_MAX_R    = 70   -- 最大扩散半径（世界单位）
local HOTSPOT_RING_LIFE     = 3.4  -- 每个环的存活时间（秒）

function InitHotspots()
    hotspots = {}
    for _, m in ipairs(MAP_DEPTH_MARKERS) do
        local hp = {
            wx = m.wx, wy = m.wy,
            bubbles = {}, fish = {},
            rings = {},                         -- 扩散水波环
            ringTimer = math.random() * HOTSPOT_RING_INTERVAL,  -- 随机错开生成时机
        }

        -- 预填 2 个不同进度的环，避免进入热点时空等
        for k = 1, 2 do
            local progress = k / 2.5
            table.insert(hp.rings, {
                wx      = m.wx + (math.random() - 0.5) * 60,
                wy      = m.wy + (math.random() - 0.5) * 60,
                life    = HOTSPOT_RING_LIFE * progress,
                maxLife = HOTSPOT_RING_LIFE,
            })
        end

        -- 预填鱼影（固定在热点附近巡游）
        for _ = 1, HOTSPOT_FISH_COUNT do
            local ang = math.random() * math.pi * 2
            local r   = math.random() * HOTSPOT_RADIUS * 0.6
            table.insert(hp.fish, {
                x      = m.wx + math.cos(ang) * r,
                y      = m.wy + math.sin(ang) * r,
                angle  = math.random() * math.pi * 2,
                speed  = 15 + math.random(20),
                size   = 7 + math.random(10),
                wobble = math.random() * 10,
            })
        end

        table.insert(hotspots, hp)
    end
end

--- 更新所有热点的气泡粒子（生成 + 上浮 + 消亡）
local function UpdateHotspotBubbles(dt)
    for _, hp in ipairs(hotspots) do
        -- 按概率新增气泡（每帧约 30% 几率冒一颗）
        if #hp.bubbles < HOTSPOT_BUBBLE_MAX and math.random() < 0.30 then
            local spreadX = (math.random() - 0.5) * HOTSPOT_RADIUS * 1.2
            local spreadY = (math.random() - 0.5) * HOTSPOT_RADIUS * 1.2
            table.insert(hp.bubbles, {
                wx      = hp.wx + spreadX,
                wy      = hp.wy + spreadY,
                r       = 2 + math.random() * 4,        -- 半径 2~6px
                life    = 0,
                maxLife = 1.2 + math.random() * 1.8,    -- 存活 1.2~3.0 秒
                riseSpeed = 18 + math.random() * 20,    -- 上浮速度（世界单位/s）
                driftX  = (math.random() - 0.5) * 8,   -- 横向漂移
            })
        end

        -- 更新 + 清理消亡气泡
        for i = #hp.bubbles, 1, -1 do
            local b = hp.bubbles[i]
            b.life  = b.life + dt
            b.wy    = b.wy - b.riseSpeed * dt   -- 向上（Y 轴负方向）
            b.wx    = b.wx + b.driftX * dt
            if b.life >= b.maxLife then
                table.remove(hp.bubbles, i)
            end
        end
    end
end

--- 更新所有热点的鱼影（在热点半径内随机游动，不跟随船）
local function UpdateHotspotFish(dt)
    for _, hp in ipairs(hotspots) do
        for _, fs in ipairs(hp.fish) do
            fs.wobble = fs.wobble + dt * 3
            -- 缓慢转向漂移
            fs.angle = fs.angle + (math.random() - 0.5) * 1.5 * dt
            fs.x = fs.x + math.cos(fs.angle) * fs.speed * dt
            fs.y = fs.y + math.sin(fs.angle) * fs.speed * dt
            -- 超出热点半径则转向热点中心
            local dx   = fs.x - hp.wx
            local dy   = fs.y - hp.wy
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist > HOTSPOT_RADIUS then
                fs.angle = math.atan(hp.wy - fs.y, hp.wx - fs.x)
                    + (math.random() - 0.5) * 0.6
            end
        end
    end
end

--- 更新热点的扩散水波环（定时生成 + 扩大 + 消亡）
local function UpdateHotspotRings(dt)
    for _, hp in ipairs(hotspots) do
        -- 定时生成新环（位置在热点中心小范围随机偏移）
        hp.ringTimer = hp.ringTimer + dt
        if hp.ringTimer >= HOTSPOT_RING_INTERVAL then
            hp.ringTimer = hp.ringTimer - HOTSPOT_RING_INTERVAL
            table.insert(hp.rings, {
                wx      = hp.wx + (math.random() - 0.5) * 80,
                wy      = hp.wy + (math.random() - 0.5) * 80,
                life    = 0,
                maxLife = HOTSPOT_RING_LIFE,
            })
        end

        -- 更新 + 清理
        for i = #hp.rings, 1, -1 do
            local rg = hp.rings[i]
            rg.life = rg.life + dt
            if rg.life >= rg.maxLife then
                table.remove(hp.rings, i)
            end
        end
    end
end

--- 绘制所有热点（只绘制距相机一定范围内的，超远的跳过）
local HOTSPOT_CULL_DIST = 900   -- 超过此世界距离不绘制
function DrawHotspots()
    for _, hp in ipairs(hotspots) do
        -- 视锥剔除：热点中心离相机太远则跳过
        local cx = hp.wx - camX
        local cy = hp.wy - camY
        if math.abs(cx) > HOTSPOT_CULL_DIST or math.abs(cy) > HOTSPOT_CULL_DIST then
            goto continue_hp
        end

        -- ── 扩散水波环 ──
        for _, rg in ipairs(hp.rings) do
            local t   = rg.life / rg.maxLife           -- 0 → 1
            local rad = HOTSPOT_RING_MAX_R * t         -- 半径随时间线性扩大

            -- 透明度：先快速升至峰值，再缓慢淡出（sin 曲线偏头部）
            local alpha = math.sin(t * math.pi) ^ 0.6 * 130

            -- 线宽：从粗到细（2.5 → 0.6）
            local lw = 5.0 - t * 3.8

            local sx, sy = WorldToScreen(rg.wx, rg.wy)
            -- 椭圆形状模拟俯视水波（宽:高 ≈ 1:0.45）
            local rx = rad
            local ry = rad * 0.45

            -- 外层淡光晕（径向渐变椭圆，增强视觉冲击）
            if t < 0.6 then
                local glowA = math.floor((1 - t / 0.6) * 25)
                local glow = nvgRadialGradient(vg, sx, sy, rx * 0.7, rx * 1.15,
                    nvgRGBA(120, 220, 255, glowA),
                    nvgRGBA(80, 180, 240, 0))
                nvgSave(vg)
                nvgTranslate(vg, sx, sy)
                nvgScale(vg, 1.0, 0.45)
                nvgBeginPath(vg)
                nvgCircle(vg, 0, 0, rx * 1.15)
                nvgFillPaint(vg, glow)
                nvgFill(vg)
                nvgRestore(vg)
            end

            -- 主环描边
            nvgSave(vg)
            nvgTranslate(vg, sx, sy)
            nvgScale(vg, 1.0, 0.45)   -- Y 轴压缩，形成俯视椭圆
            nvgBeginPath(vg)
            nvgCircle(vg, 0, 0, rx)
            nvgStrokeColor(vg, nvgRGBA(160, 230, 255, math.floor(alpha)))
            nvgStrokeWidth(vg, lw)
            nvgStroke(vg)
            nvgRestore(vg)
        end

        -- ── 气泡 ──
        for _, b in ipairs(hp.bubbles) do
            local sx, sy = WorldToScreen(b.wx, b.wy)
            if sx > -20 and sx < screenW + 20 and sy > -20 and sy < screenH + 20 then
                local t     = b.life / b.maxLife            -- 0→1
                local alpha = math.sin(t * math.pi) * 160   -- 淡入淡出
                local grow  = 1 + t * 0.4                   -- 轻微膨胀
                local rad   = b.r * grow

                -- 外圈高光（模拟气泡反光）
                local glow = nvgRadialGradient(vg, sx - rad * 0.3, sy - rad * 0.3,
                    rad * 0.1, rad,
                    nvgRGBA(220, 245, 255, math.floor(alpha * 0.9)),
                    nvgRGBA(140, 200, 240, 0))
                nvgBeginPath(vg)
                nvgCircle(vg, sx, sy, rad)
                nvgFillPaint(vg, glow)
                nvgFill(vg)

                -- 气泡轮廓（细描边）
                nvgBeginPath(vg)
                nvgCircle(vg, sx, sy, rad)
                nvgStrokeColor(vg, nvgRGBA(180, 230, 255, math.floor(alpha * 0.6)))
                nvgStrokeWidth(vg, 0.8)
                nvgStroke(vg)
            end
        end

        -- ── 热点鱼影 ──
        for _, fs in ipairs(hp.fish) do
            local sx, sy = WorldToScreen(fs.x, fs.y)
            if sx > -50 and sx < screenW + 50 and sy > -50 and sy < screenH + 50 then
                local w = fs.size * 2.8
                local h = w / 4.478

                nvgSave(vg)
                nvgTranslate(vg, sx, sy)
                nvgRotate(vg, fs.angle)
                nvgGlobalAlpha(vg, 0.45)    -- 热点鱼影比跟船鱼影稍淡

                if imgFishShadow and imgFishShadow > 0 then
                    local pat = nvgImagePattern(vg, -w/2, -h/2, w, h, 0, imgFishShadow, 1.0)
                    nvgBeginPath(vg)
                    nvgRect(vg, -w/2, -h/2, w, h)
                    nvgFillPaint(vg, pat)
                    nvgFill(vg)
                else
                    nvgBeginPath(vg)
                    nvgEllipse(vg, 0, 0, fs.size, fs.size * 0.35)
                    nvgFillColor(vg, nvgRGBA(20, 40, 60, 180))
                    nvgFill(vg)
                end

                nvgRestore(vg)
            end
        end

        ::continue_hp::
    end
end

-- ── 漂浮木板 ────────────────────────────────────────────────────────────────

--- 在船周围随机位置生成一块木板
local function SpawnPlank(near)
    local ang = math.random() * math.pi * 2
    local dist = 150 + math.random(300)
    return {
        x = near.x + math.cos(ang) * dist,
        y = near.y + math.sin(ang) * dist,
        angle = math.random() * math.pi * 2,
        drift = 0.3 + math.random() * 0.5,     -- 漂流速度
        driftAngle = math.random() * math.pi * 2,
        wobbleT = math.random() * 10,
        woodAmount = 2 + math.random(4),         -- 拾取获得 2~6 木料
        length = 16 + math.random(10),            -- 木板长度 16~26
        width = 4 + math.random(3),               -- 木板宽度 4~7
    }
end

function InitFloatingPlanks()
    floatingPlanks = {}
    for i = 1, PLANK_COUNT do
        table.insert(floatingPlanks, SpawnPlank(boat))
    end
end

function UpdateFloatingPlanks(dt)
    for _, p in ipairs(floatingPlanks) do
        -- 缓慢漂流 + 轻微晃动
        p.wobbleT = p.wobbleT + dt
        p.angle = p.angle + math.sin(p.wobbleT * 0.7) * 0.15 * dt
        p.driftAngle = p.driftAngle + (math.random() - 0.5) * 0.3 * dt
        p.x = p.x + math.cos(p.driftAngle) * p.drift * dt
        p.y = p.y + math.sin(p.driftAngle) * p.drift * dt

        -- 离船太远则重新在船附近生成
        local dx = p.x - boat.x
        local dy = p.y - boat.y
        if math.sqrt(dx * dx + dy * dy) > PLANK_RESPAWN_DIST then
            local newP = SpawnPlank(boat)
            p.x, p.y = newP.x, newP.y
            p.angle = newP.angle
            p.driftAngle = newP.driftAngle
            p.wobbleT = newP.wobbleT
            p.woodAmount = newP.woodAmount
            p.length = newP.length
            p.width = newP.width
        end
    end
end

--- 寻找最近的可拾取木板，返回 index 或 nil
function FindNearestPlank()
    local bestIdx, bestDist = nil, PLANK_PICKUP_DIST
    for i, p in ipairs(floatingPlanks) do
        local dx = p.x - boat.x
        local dy = p.y - boat.y
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist < bestDist then
            bestDist = dist
            bestIdx = i
        end
    end
    return bestIdx
end

function FindNearestIsland()
    -- 构建船体碰撞探测点（与碰撞检测共用逻辑）
    local sinA = math.sin(boat.angle)
    local cosA = math.cos(boat.angle)
    local halfL = CFG.BOAT_LENGTH * CFG.BOAT_SCALE * 0.5
    local halfW = CFG.BOAT_WIDTH  * CFG.BOAT_SCALE * 0.5
    local probes = {
        { boat.x,                    boat.y },
        { boat.x + sinA * halfL,     boat.y - cosA * halfL },
        { boat.x - sinA * halfL,     boat.y + cosA * halfL },
        { boat.x + cosA * halfW,     boat.y + sinA * halfW },
        { boat.x - cosA * halfW,     boat.y - sinA * halfW },
    }
    -- 委托给 IslandSystem 查找最近岛屿（基于碰撞点到轮廓线段距离）
    local island, dist = IslandSystem.FindNearest(probes, ISLAND_DOCK_DIST)
    if not island then return nil end
    -- 映射回 landmarks 条目（IslandMenu 等依赖 landmark 字段）
    for _, lm in ipairs(landmarks) do
        if lm.id == island.id then return lm end
    end
    return nil
end

-- 鱼重量格式化: 内部单位为 kg
-- >=1kg 显示 kg(两位小数), >=0.001kg 显示 g(整数), <0.001kg 显示 mg(整数)
function FormatWeight(kgWeight)
    if kgWeight >= 1.0 then
        return string.format("%.2f kg", kgWeight)
    elseif kgWeight >= 0.001 then
        local g = math.floor(kgWeight * 1000 + 0.5)
        if g < 1 then g = 1 end
        return string.format("%d g", g)
    else
        local mg = math.floor(kgWeight * 1000000 + 0.5)
        if mg < 1 then mg = 1 end
        return string.format("%d mg", mg)
    end
end

function ShowNotify(text, r, g, b)
    notify.text = text
    notify.timer = 2.5
    notify.color = {r or 255, g or 255, b or 255, 255}
end

--- 生成随机咬钩时间: 平均值的 10%~300%，受鱼群密度系数影响
--- 密度系数越高(白区) → 等待时间越短 → 上鱼越快
function RandomBiteTime()
    local avg = CFG.BITE_AVG_TIME
    local minT = avg * CFG.BITE_MIN_PCT
    local maxT = avg * CFG.BITE_MAX_PCT
    local baseTime = minT + math.random() * (maxT - minT)

    -- 鱼群密度系数：系数越大 → 除以后时间越短
    local densityCoeff = MapSampler.GetFishDensity(boat.x, boat.y)
    return baseTime / math.max(0.1, densityCoeff)
end

--- 获取任一鱼竿是否处于拖钓或咬钩状态
function AnyRodActive()
    for i = 1, CFG.ROD_COUNT do
        if rods[i].state ~= "idle" then return true end
    end
    return false
end

-- ============================================================================
-- 绳索物理 (Verlet 积分)
-- ============================================================================

--- 获取鱼竿在船尾的锚点世界坐标
--- 鱼竿座在船体上的位置 (甲板层，竿根)
function GetRodBaseLocal()
    local L = CFG.BOAT_LENGTH * CFG.BOAT_SCALE
    local W = CFG.BOAT_WIDTH  * CFG.BOAT_SCALE
    -- 竿根在船尾两侧: 纵向0.4L (船尾方向), 横向0.35W
    return W * 0.35, L * 0.4
end

--- 鱼竿尖端在船体上的位置 (竿尖，鱼线起点)
--- 竿尖 = 竿根 + 5倍 (原始竿根→竿尖方向向量)
function GetRodTipLocal()
    local L = CFG.BOAT_LENGTH * CFG.BOAT_SCALE
    local W = CFG.BOAT_WIDTH  * CFG.BOAT_SCALE
    -- 竿根: (0.35W, 0.4L),  原始竿尖: (0.85W, 0.55L)
    -- 方向向量: (0.5W, 0.15L), ×5 → (2.5W, 0.75L)
    -- 新竿尖: (0.35W + 2.5W, 0.4L + 0.75L) = (2.85W, 1.15L)
    return W * 2.85, L * 1.15
end

--- 获取鱼竿物理长度 (竿根到竿尖的直线距离, 世界单位)
function GetRodPhysicalLength()
    local bx, by = GetRodBaseLocal()
    local tx, ty = GetRodTipLocal()
    local dx = tx - bx
    local dy = ty - by
    return math.sqrt(dx * dx + dy * dy)
end

--- 获取鱼竿尖端的世界坐标 (鱼线锚点)
--- 优先返回弯曲后的竿尖位置 (由 DrawBoat 每帧缓存)
function GetRodAnchor(rodIndex)
    -- 始终返回直线竿尖位置 (物理锚点, 不受弯曲影响)
    -- 弯曲仅影响视觉, 由 rodBentTips 在 DrawFishingLine 中使用
    local rod = rods[rodIndex]
    local tipX, tipY = GetRodTipLocal()
    tipX = tipX * rod.side  -- 左舷/右舷镜像

    local cosA = math.cos(boat.angle)
    local sinA = math.sin(boat.angle)
    local wx = boat.x + tipX * cosA - tipY * sinA
    local wy = boat.y + tipX * sinA + tipY * cosA
    return wx, wy
end

--- 获取鱼竿旋转后竿尖的世界坐标 (唯一真值源)
--- 将竿尖绕竿根旋转 rod.aimAngle, 再应用抬杆压缩, 最后转为世界坐标
function GetRotatedTipWorld(rodIndex)
    local rod = rods[rodIndex]
    local bx, by = GetRodBaseLocal()
    local tx, ty = GetRodTipLocal()
    bx = bx * rod.side
    tx = tx * rod.side
    -- 竿根→竿尖 方向向量 (本地坐标)
    local dx = tx - bx
    local dy = ty - by
    -- 绕竿根旋转 aimAngle
    local cosR = math.cos(rod.aimAngle)
    local sinR = math.sin(rod.aimAngle)
    local rx = dx * cosR - dy * sinR
    local ry = dx * sinR + dy * cosR
    -- 抬杆伪透视压缩: 竿身绕竿根向上旋转, 水平投影 = cos(liftAngle)
    if STATE == "fight" and rodIndex == activeRod and (fight.liftT or 0) > 0.001 then
        local liftAngle = fight.liftT * CFG.FIGHT_LIFT_MAX_ANGLE
        local cosLift = math.cos(liftAngle)
        rx = rx * cosLift
        ry = ry * cosLift
    end
    -- 旋转后的竿尖本地坐标
    local rtx = bx + rx
    local rty = by + ry
    -- 本地→世界
    local cosA = math.cos(boat.angle)
    local sinA = math.sin(boat.angle)
    local wx = boat.x + rtx * cosA - rty * sinA
    local wy = boat.y + rtx * sinA + rty * cosA
    return wx, wy
end

--- 统一计算所有鱼竿的朝向角度 (每帧在 UpdateRopes 之前调用)
--- rod.aimAngle: 相对于默认竿身方向的旋转增量 (弧度)
function UpdateRodAim(dt)
    for i = 1, CFG.ROD_COUNT do
        local rod_i = rods[i]
        local targetAngle = 0  -- 默认: 不旋转

        -- 竿根→竿尖的默认方向角 (本地坐标)
        local bx, by = GetRodBaseLocal()
        local tx, ty = GetRodTipLocal()
        bx = bx * rod_i.side
        tx = tx * rod_i.side
        local rodAngle = math.atan(ty - by, tx - bx)

        if STATE == "fight" and activeRod == i then
            -- fight: 跟随鱼的拉力方向 (70%)
            local straightTipX, straightTipY = GetRodTipLocal()
            straightTipX = straightTipX * rod_i.side
            local cosB = math.cos(boat.angle)
            local sinB = math.sin(boat.angle)
            local tipWX = boat.x + straightTipX * cosB - straightTipY * sinB
            local tipWY = boat.y + straightTipX * sinB + straightTipY * cosB
            local fx, fy = GetFishWorldPos()
            local dx, dy = fx - tipWX, fy - tipWY
            local dlen = math.sqrt(dx * dx + dy * dy)
            if dlen > 0.1 then
                local wPullX, wPullY = dx / dlen, dy / dlen
                local cosA = math.cos(-boat.angle)
                local sinA = math.sin(-boat.angle)
                local localPullX = wPullX * cosA - wPullY * sinA
                local localPullY = wPullX * sinA + wPullY * cosA
                local pullAngle = math.atan(localPullY, localPullX)
                local delta = pullAngle - rodAngle
                while delta >  math.pi do delta = delta - 2 * math.pi end
                while delta < -math.pi do delta = delta + 2 * math.pi end
                targetAngle = delta * 0.7
            end
        elseif castState.charging and STATE == "sailing" and activeRod == i then
            -- 蓄力: 跟随鼠标瞄准方向 (100%)
            local mx = input:GetMousePosition().x
            local my = input:GetMousePosition().y
            local mwx, mwy = ScreenToWorld(mx, my)
            local cosB = math.cos(boat.angle)
            local sinB = math.sin(boat.angle)
            local straightTipX, straightTipY = GetRodTipLocal()
            straightTipX = straightTipX * rod_i.side
            local tipWX = boat.x + straightTipX * cosB - straightTipY * sinB
            local tipWY = boat.y + straightTipX * sinB + straightTipY * cosB
            local adx, ady = mwx - tipWX, mwy - tipWY
            local adist = math.sqrt(adx * adx + ady * ady)
            if adist > 1 then
                local cosA = math.cos(-boat.angle)
                local sinA = math.sin(-boat.angle)
                local localAimX = adx / adist * cosA - ady / adist * sinA
                local localAimY = adx / adist * sinA + ady / adist * cosA
                local aimAngle = math.atan(localAimY, localAimX)
                local delta = aimAngle - rodAngle
                while delta >  math.pi do delta = delta - 2 * math.pi end
                while delta < -math.pi do delta = delta + 2 * math.pi end
                targetAngle = delta
            end
        elseif rod_i.state ~= "idle" and rod_i.rope and #rod_i.rope >= 2 then
            -- trolling/bite/casting: 跟随鱼饵方向 (100%)
            local ldx, ldy, ldist
            if rod_i.state == "casting" and rod_i.flyTargetX then
                -- casting 阶段: 直接用飞行方向，避免用绳节坐标（初始绳节在旋转竿尖，直线竿尖偏差会导致角度跳变）
                ldx = rod_i.flyTargetX - rod_i.flyStartX
                ldy = rod_i.flyTargetY - rod_i.flyStartY
                ldist = math.sqrt(ldx * ldx + ldy * ldy)
            else
                local lureNode = rod_i.rope[#rod_i.rope]
                -- 使用旋转后的竿尖（与 UpdateRopes 锚点一致），避免参考点不一致导致角度跳变
                local tipWX, tipWY = GetRotatedTipWorld(i)
                ldx = lureNode.x - tipWX
                ldy = lureNode.y - tipWY
                ldist = math.sqrt(ldx * ldx + ldy * ldy)
            end
            if ldist > 1 then
                local cosA = math.cos(-boat.angle)
                local sinA = math.sin(-boat.angle)
                local localLureX = ldx / ldist * cosA - ldy / ldist * sinA
                local localLureY = ldx / ldist * sinA + ldy / ldist * cosA
                local lureAngle = math.atan(localLureY, localLureX)
                local delta = lureAngle - rodAngle
                while delta >  math.pi do delta = delta - 2 * math.pi end
                while delta < -math.pi do delta = delta + 2 * math.pi end
                targetAngle = delta
            end
        end
        -- else idle → targetAngle = 0

        -- ── 蓄力状态角度限制（船尾90°扇形） ──────────────────────────────────
        -- 坐标系: +Y = 船尾, -Y = 船头, +X = 右舷, -X = 左舷
        -- 右竿(side= 1): 船尾(+π/2) → 顺时针90° → 右舷(0)   → absTarget ∈ [0, π/2]
        -- 左竿(side=-1): 船尾(+π/2) → 逆时针90° → 左舷(π)   → absTarget ∈ [π/2, π]
        local rotSpeed = 10.0
        local isTrolling = rod_i.state == "trolling" or rod_i.state == "idle"
        local isFighting = STATE == "fight" and activeRod == i
        local isBiting = rod_i.state == "bite"
        local isCasting = castState.charging and activeRod == i
        if isCasting then
            local absTarget = rodAngle + targetAngle
            if rod_i.side == -1 then
                -- 左竿有效区 [π/2, π] 不含 ±π 断点，归一化到 [0, 2π) 避免越界后跳到负值
                while absTarget <  0            do absTarget = absTarget + 2 * math.pi end
                while absTarget >= 2 * math.pi  do absTarget = absTarget - 2 * math.pi end
            else
                -- 右竿有效区 [0, π/2]，标准 (-π, π] 归一化即可
                while absTarget >  math.pi do absTarget = absTarget - 2 * math.pi end
                while absTarget < -math.pi do absTarget = absTarget + 2 * math.pi end
            end
            local minA = (rod_i.side == -1) and (math.pi * 0.5) or (0)
            local maxA = (rod_i.side == -1) and (math.pi)       or (math.pi * 0.5)
            local clamped = math.max(minA, math.min(maxA, absTarget))
            targetAngle = clamped - rodAngle
            while targetAngle >  math.pi do targetAngle = targetAngle - 2 * math.pi end
            while targetAngle < -math.pi do targetAngle = targetAngle + 2 * math.pi end
        end

        if isTrolling and not isFighting and not isBiting and not isCasting then
            local absTarget = rodAngle + targetAngle
            while absTarget >  math.pi do absTarget = absTarget - 2 * math.pi end
            while absTarget < -math.pi do absTarget = absTarget + 2 * math.pi end
            local sideAlign = math.cos(absTarget) * rod_i.side
            local threshold = 0.15
            if sideAlign < threshold then
                local clamped
                if rod_i.side == 1 then
                    -- 右舷: 有效区 [-limit, limit], 连续 clamp 无跳变
                    local limit = math.acos(threshold)
                    clamped = math.max(-limit, math.min(limit, absTarget))
                else
                    -- 左舷: 有效区 [limit, π] ∪ [-π, -limit], 按符号选边
                    local limit = math.acos(-threshold)
                    clamped = absTarget >= 0 and limit or -limit
                end
                targetAngle = clamped - rodAngle
                while targetAngle >  math.pi do targetAngle = targetAngle - 2 * math.pi end
                while targetAngle < -math.pi do targetAngle = targetAngle + 2 * math.pi end
            end
        end

        -- 角度差归一化: 始终取最短旋转路径, 避免反向绕行
        local angleDiff = targetAngle - rod_i.aimAngle
        while angleDiff >  math.pi do angleDiff = angleDiff - 2 * math.pi end
        while angleDiff < -math.pi do angleDiff = angleDiff + 2 * math.pi end

        local lerpT = 1.0 - math.exp(-rotSpeed * dt)
        rod_i.aimAngle = rod_i.aimAngle + angleDiff * lerpT

        -- 归一化 aimAngle 防止无限增长
        while rod_i.aimAngle >  math.pi do rod_i.aimAngle = rod_i.aimAngle - 2 * math.pi end
        while rod_i.aimAngle < -math.pi do rod_i.aimAngle = rod_i.aimAngle + 2 * math.pi end

        -- trolling/idle 时硬性限制旋转幅度: 防止鱼饵漂到船头后竿子跟着转过去
        -- aimAngle 是相对默认竿身方向的增量, 超过 ±MAX_TROLL_AIM 时强制钳位
        if isTrolling and not isFighting and not isBiting and not isCasting then
            local MAX_TROLL_AIM = math.rad(75)  -- 最大允许旋转幅度 (75°)
            rod_i.aimAngle = math.max(-MAX_TROLL_AIM, math.min(MAX_TROLL_AIM, rod_i.aimAngle))
        end
    end
end

--- 获取鱼的世界坐标 (极坐标转直角坐标)
function GetFishWorldPos()
    local ax, ay = GetRotatedTipWorld(activeRod)
    local totalAngle = fight.fishInitAngle + fight.fishAngle
    local fx = ax + math.sin(totalAngle) * fight.fishRadius
    local fy = ay - math.cos(totalAngle) * fight.fishRadius
    return fx, fy
end

--- 初始化绳索节点链 (抛竿时调用)
function InitRope(rodIndex)
    local rod = rods[rodIndex]
    local segments = CFG.ROPE_SEGMENTS
    local segLen = CFG.LINE_LENGTH / segments

    local ax, ay = GetRodAnchor(rodIndex)
    -- 方向: 从竿尖向船尾后方延伸 (略微偏向外侧)
    local outAngle = boat.angle + rod.side * 0.3
    local dirX = math.sin(outAngle)
    local dirY = -math.cos(outAngle)

    rod.rope = {}
    for i = 1, segments + 1 do
        local t = (i - 1) / segments
        local nx = ax + dirX * t * CFG.LINE_LENGTH
        local ny = ay + dirY * t * CFG.LINE_LENGTH
        rod.rope[i] = { x = nx, y = ny, px = nx, py = ny }
    end
end

--- 更新所有活跃鱼竿的绳索
function UpdateRopes(dt)
    -- followSpeed: 节点跟随前一节点的速度，越大越紧，越小越拖沓
    local followSpeed = 10.0
    -- 帧率无关的平滑因子
    local t = 1.0 - math.exp(-followSpeed * dt)

    for ri = 1, CFG.ROD_COUNT do
        local rod = rods[ri]
        if rod.state ~= "idle" and #rod.rope > 0 then
            local rope = rod.rope
            local n = #rope

            -- 1) 锚点 = 旋转后竿尖世界坐标 (由 UpdateRodAim 计算 aimAngle, 此处读取)
            --    含 sprite-stack 高度偏移: 竿尖物理上在水面之上 (层 6.5 的真实高度)
            local stackYOff = CFG.STACK_OFFSET * CFG.BOAT_SCALE * CFG.ROD_STACK_LAYER
            local ax, ay = GetRotatedTipWorld(ri)
            rope[1].x = ax
            rope[1].y = ay - stackYOff

            -- 2) 判断是否在 fight 状态 (且是当前活跃鱼竿)
            local isFighting = (STATE == "fight" and ri == activeRod)

            if isFighting then
                -- ═══ fight 模式: 双端锚定 + 节点数随线长动态变化 ═══
                -- 末端锚定到鱼的世界坐标
                local fx, fy = GetFishWorldPos()

                -- 固定段长, 根据当前线长动态调整节点数
                local fixedSegLen = CFG.LINE_LENGTH / CFG.ROPE_SEGMENTS
                local targetN = math.max(2,
                    math.min(CFG.ROPE_SEGMENTS + 1, math.ceil(fight.lineLength / fixedSegLen) + 1))
                if targetN > n then
                    -- 收到更多线: 在鱼端追加节点 (初始化在鱼位置)
                    for k = n + 1, targetN do
                        rope[k] = { x = fx, y = fy, px = fx, py = fy }
                    end
                elseif targetN < n then
                    -- 收线变短: 从鱼端移除节点
                    for k = targetN + 1, n do
                        rope[k] = nil
                    end
                end
                n = #rope

                rope[n].x = fx
                rope[n].y = fy

                -- 段长 = 实际线长 / 段数 (随放线/收线动态变化)
                local segLen = math.max(1, fight.lineLength / (n - 1))
                local maxStretch = segLen * 1.15

                -- PBD 双向解算: 迭代内用高刚度直接修正, 帧间用 t 控制柔软度
                local iterations = 4
                -- 帧间阻尼: 先将所有中间节点向"上一帧位置"混合, 产生柔软延迟感
                for i = 2, n - 1 do
                    local node = rope[i]
                    local oldX, oldY = node.x, node.y
                    -- t 越小线越柔软(跟随越慢), 越大越紧绷(即时响应)
                    node.x = node.x + (node.x - (node.prevX or node.x)) * (1.0 - t)
                    node.y = node.y + (node.y - (node.prevY or node.y)) * (1.0 - t)
                    node.prevX, node.prevY = oldX, oldY
                end

                for iter = 1, iterations do
                    -- 每次迭代重新锚定两端
                    rope[1].x, rope[1].y = ax, ay - stackYOff
                    rope[n].x, rope[n].y = fx, fy

                    -- 正向: 从竿尖向鱼端 (直接修正到 segLen 位置)
                    for i = 2, n - 1 do
                        local prev = rope[i - 1]
                        local node = rope[i]
                        local dx = node.x - prev.x
                        local dy = node.y - prev.y
                        local dist = math.sqrt(dx * dx + dy * dy)
                        if dist > segLen and dist > 0.001 then
                            local dirX = dx / dist
                            local dirY = dy / dist
                            node.x = prev.x + dirX * segLen
                            node.y = prev.y + dirY * segLen
                        end
                    end

                    -- 反向: 从鱼端向竿尖 (半修正, 避免正反向完全覆盖)
                    for i = n - 1, 2, -1 do
                        local nxt = rope[i + 1]
                        local node = rope[i]
                        local dx = node.x - nxt.x
                        local dy = node.y - nxt.y
                        local dist = math.sqrt(dx * dx + dy * dy)
                        if dist > segLen and dist > 0.001 then
                            local dirX = dx / dist
                            local dirY = dy / dist
                            local targetX = nxt.x + dirX * segLen
                            local targetY = nxt.y + dirY * segLen
                            -- 0.5 混合: 正反两个 pass 各承担一半修正, 结果对称
                            node.x = node.x + (targetX - node.x) * 0.5
                            node.y = node.y + (targetY - node.y) * 0.5
                        end
                    end
                end

                -- Pass 3: 张力拉直 — 有张力时将中间节点拉向两端直线
                -- tensionRatio: 0=完全松弛(保持自然弧线), 1=最大张力(完全绷直)
                local tensionRatio = math.min(1, fight.tension / fight.lineStrength)
                if tensionRatio > 0.01 then
                    -- 张力越大拉直越快, 低张力保留弧度
                    local straighten = tensionRatio * tensionRatio  -- 二次曲线, 低张力几乎不拉
                    local r1x, r1y = rope[1].x, rope[1].y  -- 弯曲竿尖位置
                    for i = 2, n - 1 do
                        local frac = (i - 1) / (n - 1)  -- 0→1 在线上的位置
                        local lx = r1x + (fx - r1x) * frac
                        local ly = r1y + (fy - r1y) * frac
                        node = rope[i]
                        node.x = node.x + (lx - node.x) * straighten
                        node.y = node.y + (ly - node.y) * straighten
                    end
                end
            elseif rod.state == "casting" and rod.flyT ~= nil then
                -- ═══ casting 模式: 鱼线飞行中, 节点数随线长动态增长 ═══
                local ft = math.min(1, rod.flyT)
                -- 当前鱼饵世界位置 (沿起点→目标线性插值)
                local lureX = rod.flyStartX + (rod.flyTargetX - rod.flyStartX) * ft
                local lureY = rod.flyStartY + (rod.flyTargetY - rod.flyStartY) * ft
                -- 当前已飞出的线长 (米)
                local castDist = math.sqrt(
                    (rod.flyTargetX - rod.flyStartX)^2 + (rod.flyTargetY - rod.flyStartY)^2)
                local currentLen = castDist * ft
                -- 固定段长, 按当前线长决定节点数 (至少 2 个: 竿尖+鱼饵)
                local segLen = CFG.LINE_LENGTH / CFG.ROPE_SEGMENTS
                local targetN = math.max(2,
                    math.min(CFG.ROPE_SEGMENTS + 1, math.ceil(currentLen / segLen) + 1))
                -- 增加节点 (新节点初始化在鱼饵处)
                local curN = #rope
                if targetN > curN then
                    for k = curN + 1, targetN do
                        rope[k] = { x = lureX, y = lureY, px = lureX, py = lureY }
                    end
                elseif targetN < curN then
                    -- 减少节点 (收短线时从末端移除)
                    for k = targetN + 1, curN do
                        rope[k] = nil
                    end
                end
                -- 将全部节点均匀分布在竿尖→鱼饵之间
                local r1x, r1y = rope[1].x, rope[1].y
                local newN = #rope
                for k = 2, newN do
                    local frac = (k - 1) / (newN - 1)
                    rope[k].x = r1x + (lureX - r1x) * frac
                    rope[k].y = r1y + (lureY - r1y) * frac
                end
            else
                -- ═══ 非 fight 模式: 单向链式 (原逻辑) ═══
                local segLen = CFG.LINE_LENGTH / CFG.ROPE_SEGMENTS
                local maxStretch = segLen * 1.15
                for i = 2, n do
                    local prev = rope[i - 1]
                    local node = rope[i]
                    local dx = node.x - prev.x
                    local dy = node.y - prev.y
                    local dist = math.sqrt(dx * dx + dy * dy)
                    if dist > 0.001 then
                        local dirX = dx / dist
                        local dirY = dy / dist
                        local targetX = prev.x + dirX * segLen
                        local targetY = prev.y + dirY * segLen
                        if dist > segLen then
                            node.x = node.x + (targetX - node.x) * t
                            node.y = node.y + (targetY - node.y) * t
                        end
                        local dx2 = node.x - prev.x
                        local dy2 = node.y - prev.y
                        local dist2 = math.sqrt(dx2 * dx2 + dy2 * dy2)
                        if dist2 > maxStretch then
                            node.x = prev.x + (dx2 / dist2) * maxStretch
                            node.y = prev.y + (dy2 / dist2) * maxStretch
                        end
                    end
                end
            end
        end
    end
end

-- ============================================================================
-- 鱼选择
-- ============================================================================

-- 截断正态分布采样鱼的体重 (Box-Muller), 结果在 [wMin, wMax] 内
function SampleFishWeight(ft)
    local mu    = ft.wMin + (ft.wBias or 0.5) * (ft.wMax - ft.wMin)
    local sigma = (ft.wSpread or 0.3) * (ft.wMax - ft.wMin) / 2
    if sigma <= 0 then
        return math.floor(mu * 1000 + 0.5) / 1000
    end
    for _ = 1, 20 do
        local u1 = math.max(1e-10, math.random())
        local u2 = math.random()
        local z  = math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
        local w  = mu + sigma * z
        if w >= ft.wMin and w <= ft.wMax then
            return math.floor(w * 1000 + 0.5) / 1000
        end
    end
    return math.floor(mu * 1000 + 0.5) / 1000  -- 超出重试次数时回退到均值
end

function PickRandomFish()
    -- 多因素加权选鱼
    -- 各维度权重独立相乘，稀有度作为独立系数

    -- 当前上下文（targetZoneR = 已确认的当前区域，currentZoneR 是颜色过渡起点）
    local seaType    = ZONE_TYPE_MAP[targetZoneR] or 1
    local depthLevel = GetFishDepthLevel(boat.x, boat.y)
    local hookLevel  = PlayerData.data.equippedHook or 3
    local baitLevel  = PlayerData.data.equippedBait or 0
    local hour       = TimeWeather.GetHour()
    local timeIdx    = (hour >= 6 and hour < 18) and 1 or 2   -- 1=白天 2=夜晚
    local weatherIdx = (weatherMode_ == "sunny") and 1 or 2    -- 1=晴天 2=雨天

    -- 调试日志
    print(string.format("[PickFish] seaType=%d depth=%d hook=%d bait=%d time=%d weather=%d",
        seaType, depthLevel, hookLevel, baitLevel, timeIdx, weatherIdx))

    local weights = {}
    local totalW = 0
    for i, f in ipairs(FISH_TYPES) do
        local d = FISH_DIST[f.name]
        local w
        if d then
            -- 多因素乘积 × 稀有度
            local wZone    = d.zone[seaType]     or 0.01
            local wDepth   = d.depth[depthLevel] or 0.01
            local wHook    = d.hook[hookLevel]   or 0.01
            local wTime    = d.time[timeIdx]     or 0.5
            local wWeather = d.weather[weatherIdx] or 0.5
            local rarity   = d.rarity or 1.0
            -- 鱼饵加成：使用鱼饵时乘以该鱼对该饵的偏好权重（归一化值，0~1）
            -- 无鱼饵（baitLevel=0）时 wBait=1 不影响概率
            local wBait = 1.0
            if baitLevel > 0 and d.bait then
                local raw = d.bait[baitLevel] or 0
                -- 偏好值 > 0 才给加成，偏好=0 的鱼仍可上钩（概率×0.15兜底）
                wBait = raw > 0 and (0.5 + raw * 3.0) or 0.15
            end
            w = wZone * wDepth * wHook * wTime * wWeather * rarity * wBait
        else
            -- 兜底：无分布数据时用 diff 权重（极低基础概率）
            -- testFixed 标记的鱼（如测试鱼）不参与随机选鱼
            if f.testFixed then
                w = 0
            else
                w = math.max(0.001, (6 - f.diff) * 0.005)
            end
        end
        weights[i] = (w > 0) and math.max(w, 1e-6) or 0
        totalW = totalW + weights[i]
    end

    local r = math.random() * totalW
    local acc = 0
    for i, w in ipairs(weights) do
        acc = acc + w
        if r <= acc then
            local f = FISH_TYPES[i]
            return { type = f, weight = SampleFishWeight(f) }
        end
    end
    local f = FISH_TYPES[1]
    return { type = f, weight = SampleFishWeight(f) }
end

-- ============================================================================
-- 遛鱼系统
-- ============================================================================

-- ── 波动生成辅助函数 ──

--- 随机生成径向波动参数 (控制鱼的逃跑力度变化)
function GenerateRadialWave()
    local ft = curFish and curFish.type or FISH_TYPES[1]
    local d = (ft.diff - 1) / 4  -- 难度系数: diff1=0, diff5=1

    fight.radWaveTime = 0
    if fight.radState == "active" then
        fight.radWaveDur = 0.7 + math.random() * 1.3        -- 大振幅: 0.7~2.0秒
    else
        fight.radWaveDur = 1.5 + math.random() * 3.0        -- 小振幅: 1.5~4.5秒
    end
    fight.radWaveBase = 0.65 + math.random() * 0.2 - 0.2 * d -- diff1: 0.65~0.85, diff5: 0.45~0.65
    -- 振幅由 ChangeRadialState 控制, 不再在此生成
end

--- 切换径向振幅状态 (calm=小幅波动, active=大幅波动)
function ChangeRadialState()
    local ft = curFish and curFish.type or FISH_TYPES[1]
    local d = (ft.diff - 1) / 4  -- 难度系数: diff1=0, diff5=1

    -- 支持三态加权随机: radialStateTable = { {weight, ampLo, ampHi, durMin, durMax}, ... }
    if ft.radialStateTable then
        -- 加权随机选取状态
        local totalW = 0
        for _, s in ipairs(ft.radialStateTable) do totalW = totalW + s.weight end
        local r = math.random() * totalW
        local chosen = ft.radialStateTable[#ft.radialStateTable]
        local acc = 0
        for _, s in ipairs(ft.radialStateTable) do
            acc = acc + s.weight
            if r <= acc then chosen = s; break end
        end
        fight.radState        = chosen.label or "active"
        fight.radStateDur     = chosen.durMin + math.random() * (chosen.durMax - chosen.durMin)
        fight.radAmpPctTarget = chosen.ampLo  + math.random() * (chosen.ampHi  - chosen.ampLo)
        fight.radStateTimer   = 0
        return
    end

    if math.random() < (ft.calmProb or 0.6) then
        fight.radState = "calm"
        fight.radStateDur = 3.0 + math.random() * 4.0    -- 平静期 3~7秒
        -- 小振幅: 基线的 10%~50%, 按难度缩放
        local lo = 0.10 + 0.10 * d  -- diff1: 10%, diff5: 20%
        local hi = 0.30 + 0.20 * d  -- diff1: 30%, diff5: 50%
        fight.radAmpPctTarget = lo + math.random() * (hi - lo)
    else
        fight.radState = "active"
        fight.radStateDur = 1.5 + math.random() * 3.0    -- 暴走期 1.5~4.5秒
        -- 大振幅: 基线的 35%~75%, 按难度缩放
        local lo = 0.35 + 0.10 * d  -- diff1: 35%, diff5: 45%
        local hi = 0.50 + 0.25 * d  -- diff1: 50%, diff5: 75%
        fight.radAmpPctTarget = lo + math.random() * (hi - lo)
    end
    fight.radStateTimer = 0
end

--- 切换切向行为状态 (CALM=温和摆动, ACTIVE=剧烈横游)
function ChangeTangentialState()
    local ft = curFish and curFish.type or FISH_TYPES[1]
    if math.random() < (ft.calmProb or 0.6) then
        fight.tanState = "calm"
        fight.tanDuration = 2.0 + math.random() * 4.0  -- CALM持续 2~6秒
        fight.tanWaveAmp  = 1 + math.random() * 3      -- 小振幅 1~4
        fight.tanWaveBase = (math.random() - 0.5) * 2   -- 基础偏移 -1~1
    else
        fight.tanState = "active"
        fight.tanDuration = 1.0 + math.random() * 2.0  -- ACTIVE持续 1~3秒
        fight.tanWaveAmp  = 38 + math.random() * 4     -- 大振幅 38~42
        fight.tanWaveBase = (math.random() - 0.5) * 10  -- 基础偏移 -5~5
    end
    fight.tanTimer    = 0
    fight.tanWaveTime = 0
    fight.tanWaveDur  = 0.8 + math.random() * 2.0  -- 切向波形周期 0.8~2.8秒
end

function StartFight(fish)
    STATE = "fight"

    -- 兜底替换：若实际重量低于该竿基础线，使用兜底鱼的战斗参数
    -- curFish 保留原始鱼（显示用），curFightType 决定实际力学表现
    local rodId = equippedRodId or 2
    local minW  = ROD_MIN_FIGHT_WEIGHT[rodId] or 0.5
    if fish.weight < minW then
        curFightType = FLOOR_FISH_TYPES[rodId]
    else
        curFightType = nil  -- nil = 正常使用 curFish.type
    end

    curFish = fish
    local ft = curFightType or fish.type  -- 兜底时用替换类型初始化战斗参数

    -- 装备的竿型参数 (快照到 fight, 遛鱼过程中不随切换变化)
    local rt  = ROD_TYPES[equippedRodId]   or ROD_TYPES[2]
    local rl  = REEL_TYPES[equippedReelId] or REEL_TYPES[2]
    fight.rodId        = rt.id
    fight.reelId       = rl.id
    fight.lineStrength = rt.lineStrength
    fight.stretchMax   = rt.stretchMax
    -- dragMaxRatio 由渔线轮最大刹车力 / 鱼竿断线张力计算
    -- 可以超过 1.0：重型轮配轻竿时，高档位刹车力会超过断线张力，玩家需要控制在低档位
    fight.dragMaxRatio    = rl.maxDragForce / rt.lineStrength
    -- lineCapacity 由渔线轮鱼线容量决定
    fight.lineCapacity    = rl.lineCapacity
    -- reelMechStrength：渔线轮机械强度上限 (kg)
    -- 当 lineStrength > reelMechStrength 时，超出部分的力度条被锁定
    -- 当张力突破 reelMechStrength 时，判定渔线轮损坏，钓鱼失败
    fight.reelMechStrength = rl.mechStrength
    -- 收线参数（按渔线轮型号不同）
    fight.reelSpeedMax = rl.reelSpeedMax
    fight.reelAccel    = rl.reelAccel

    -- 线与张力
    fight.tension      = 0
    fight.tensionVisual = 0
    fight.dragGear     = CFG.FIGHT_DRAG_DEFAULT_GEAR
    fight.drag         = fight.dragGear / CFG.FIGHT_DRAG_GEARS * fight.dragMaxRatio

    -- 极坐标: 从绳索末端实际位置反算, 确保拖钓→遛鱼无缝衔接
    local rod = rods[activeRod]
    local ax, ay = GetRotatedTipWorld(activeRod)
    local endX, endY = ax, ay
    if #rod.rope > 0 then
        local last = rod.rope[#rod.rope]
        endX, endY = last.x, last.y
    end
    local dx = endX - ax
    local dy = endY - ay
    local dist = math.sqrt(dx * dx + dy * dy)
    fight.fishRadius    = math.max(20, dist)  -- 不小于20, 避免零距离
    fight.fishInitAngle = math.atan(dx, -dy)  -- 与 GetFishWorldPos 的角度约定一致
    fight.fishAngle     = 0                   -- 偏转角 = 0 (在初始方向上)
    -- lineLength = 绳索实际路径总长度
    -- 不重新分布节点 (保留拖钓形态), 使 fight segLen ≈ trolling segLen, PBD 首帧不触发
    -- 避免上钩瞬间线形跳变: 绳索从拖钓形态自然过渡到遛鱼形态
    -- lineLength 与现有节点数严格对齐, 防止 UpdateRopes 首帧增删节点导致视觉跳变
    local rp = rod.rope
    local fixedSegLen = CFG.LINE_LENGTH / CFG.ROPE_SEGMENTS
    fight.lineLength    = math.max(20, (#rp - 1) * fixedSegLen)
    fight.fishRadVel    = 0
    fight.fishAngVel    = 0

    -- 仅清空节点速度 (prevX/prevY = 当前位置), 避免拖钓惯性带入遛鱼
    for i = 1, #rp do
        rp[i].prevX = rp[i].x
        rp[i].prevY = rp[i].y
    end

    -- 波动初始化
    GenerateRadialWave()
    ChangeRadialState()
    fight.radAmpPct = fight.radAmpPctTarget  -- 初始无需过渡
    ChangeTangentialState()

    -- 挣扎微力
    fight.tremorPhase   = math.random() * math.pi * 2  -- 基频初始相位
    fight.tremorPhase2  = math.random() * math.pi * 2  -- 二次谐波初始相位
    fight.jerkTimer     = 0
    fight.jerkDurTotal  = 0                             -- 甩头总时长(包络用)
    fight.jerkCooldown  = 0.5 + math.random() * 1.0    -- 更短初始冷却, 让玩家更快感受到
    fight.jerkAmp       = 0

    -- 打滑 (约束派生)
    fight.slipping      = false
    fight.slipSpeed     = 0

    -- 收线
    fight.reeling       = false
    fight.reelSpeed     = 0

    -- 视觉平滑
    fight.slipRecentTimer = 0

    -- 体力上限：优先使用鱼种 stamina 字段，否则按 wMax 分档
    local function StaminaByWeight(w)
        if     w < 1   then return 70
        elseif w < 10  then return 100
        elseif w < 40  then return 200
        elseif w < 100 then return 300
        else                return 500
        end
    end
    local stamina = ft.stamina or StaminaByWeight(ft.wMax or 1)
    fight.fishStamina   = stamina
    fight.fishMaxStam   = stamina

    -- 体力计时器
    fight.fightStartTime    = gameTime   -- 战斗开始时刻
    fight.staminaDepletedAt = nil        -- 体力归零时的已耗时（秒），nil=尚未归零

    -- 断线延迟
    fight.breakTimer    = 0
    fight.breakDelay    = 0
    -- 渔线轮损坏延迟
    fight.reelBreakTimer = 0

    -- 抬杆 (右键压杆)
    fight.liftT         = 0    -- 抬起进度 0~1
    fight.liftHeight    = 0    -- 当前抬起的世界空间高度 (米)

    -- 元数据
    fight.fightTime     = 0
    fight.resultTimer   = 0

    -- 初始化世界坐标缓存 (供船位移补偿)
    fight.fishWorldX, fight.fishWorldY = GetFishWorldPos()
    fight.fishHeading = fight.fishInitAngle  -- 鱼影初始朝向 = 初始极角方向

    -- 进入 fight 时保留巡航状态 (巡航限速25%, 玩家可转向或S退出)

    if boat.cruise then
        ShowNotify("鱼上钩了! 按住左键收线 | 巡航25%限速 | AD转向追鱼", 255, 220, 50)
    else
        ShowNotify("鱼上钩了! 按住左键收线 | AD转向", 255, 220, 50)
    end
end

-- ============================================================================
-- 更新逻辑
-- ============================================================================

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    gameTime = gameTime + dt

    BoatUpgrade.Update(dt)

    -- 竿线调试日志 (每 0.2 秒打印一次)
    if rodDebugMode then
        rodDebugLogTimer = rodDebugLogTimer + dt
        if rodDebugLogTimer >= 0.2 then
            rodDebugLogTimer = 0
            local r1, r2 = rods[1], rods[2]
            print(string.format(
                "[ROD] STATE=%s active=%d | rod1={st=%s aim=%.2f° rope=%d} | rod2={st=%s aim=%.2f° rope=%d}",
                STATE, activeRod,
                r1.state, math.deg(r1.aimAngle), #r1.rope,
                r2.state, math.deg(r2.aimAngle), #r2.rope
            ))
            print(string.format(
                "[CAST] charging=%s power=%.2f liftT=%.2f | fly: flyT=%.2f flyDur=%.2f",
                tostring(castState.charging), castState.power, castState.liftT,
                rods[activeRod].flyT or 0, rods[activeRod].flyDuration or 0
            ))
            if STATE == "fight" then
                print(string.format(
                    "[FIGHT] liftT=%.2f tension=%.1fkg radius=%.1fm lineLen=%.1fm",
                    fight.liftT or 0, fight.tension, fight.fishRadius, fight.lineLength
                ))
            end
            local rod = rods[activeRod]
            if rod.rope and #rod.rope >= 2 then
                local head = rod.rope[1]
                local tail = rod.rope[#rod.rope]
                print(string.format(
                    "[ROPE] nodes=%d head=(%.1f,%.1f) tail=(%.1f,%.1f)",
                    #rod.rope, head.x, head.y, tail.x, tail.y
                ))
            end
        end
    end

    -- 时间滑条拖拽持续跟踪
    if twSliderDrag_ then
        if input:GetMouseButtonDown(MOUSEB_LEFT) then
            local mx = input.mousePosition.x
            local my = input.mousePosition.y
            local t = TimeSliderHitTest(mx, my)
            if t then TimeWeather.SetTOD(t) end
        else
            twSliderDrag_ = false
        end
    end

    if not twSliderDrag_ then
        TimeWeather.Update(dt)
    end
    UpdateRain(dt)
    waterTime = waterTime + dt

    -- 开发者选鱼: 输入超时自动确认
    if devFishInputTimer > 0 and devFishInput ~= "" then
        devFishInputTimer = devFishInputTimer - dt
        if devFishInputTimer <= 0 then
            local idx = tonumber(devFishInput)
            devFishInput = ""; devFishInputTimer = 0
            if idx and idx >= 1 and idx <= #FISH_TYPES and STATE == "sailing" then
                devFishSelect = false
                local rod = rods[activeRod]
                if rod.state == "idle" then
                    rod.state = "trolling"; rod.timer = 0; rod.biteAt = 999; InitRope(activeRod)
                end
                rod.state = "trolling"
                local ft = FISH_TYPES[idx]
                StartFight({ type = ft, weight = SampleFishWeight(ft) })
                ShowNotify("[DEV] 选择: " .. ft.name .. " (★" .. ft.diff .. ")", 255, 150, 255)
            end
        end
    end

    -- 开发者批量钓鱼: 输入超时自动确认
    if devBatch.timer > 0 and devBatch.input ~= "" then
        devBatch.timer = devBatch.timer - dt
        if devBatch.timer <= 0 then
            local idx = tonumber(devBatch.input)
            devBatch.input = ""; devBatch.timer = 0
            if idx and idx >= 1 and idx <= #FISH_TYPES and STATE == "sailing" then
                devBatch.active = false
                local ft = FISH_TYPES[idx]
                local added = 0
                for _ = 1, 10 do
                    if #caughtList >= CFG.BAG_SIZE then break end
                    local w = SampleFishWeight(ft)
                    caughtList[#caughtList + 1] = { type = ft, weight = w }
                    totalWeight = totalWeight + w
                    added = added + 1
                end
                ShowNotify(string.format("[DEV] 批量入包: %s ×%d", ft.name, added), 100, 255, 200)
            end
        end
    end

    screenW = graphics:GetWidth()
    screenH = graphics:GetHeight()

    -- ── 启动封面更新 ──
    if splash.active then
        splash.dotTimer = splash.dotTimer + dt
        if not splash.fadeOut and IslandSystem.IsReady() then
            splash.fadeOut = true
        end
        if splash.fadeOut then
            splash.alpha = splash.alpha - dt / 1.0  -- 1 秒淡出
            if splash.alpha <= 0 then
                splash.alpha = 0
                splash.active = false
            end
        end
        return  -- 封面期间冻结游戏逻辑
    end

    -- 海浪精灵 (全状态更新)
    UpdateWaveSprites(dt)

    -- 通知倒计时
    if notify.timer > 0 then notify.timer = notify.timer - dt end

    -- ── 海域分区检测（带去抖：持续驻留 1 秒才确认切换）──────────────
    local zoneGray = MapSampler.Sample("zone", boat.x, boat.y)
    local rawR = math.floor(zoneGray * 255 + 0.5)
    -- 量化到最近的已知 R 值
    local bestR, bestDiff = 190, 999
    for r, _ in pairs(ZONE_TABLE) do
        local diff = math.abs(rawR - r)
        if diff < bestDiff then bestDiff = diff; bestR = r end
    end
    if bestR ~= targetZoneR then
        -- 采样到的区域与当前已确认区域不同
        if bestR == pendingZoneR then
            -- 与候选区域一致，累加驻留时间
            pendingZoneTime = pendingZoneTime + dt
            if pendingZoneTime >= ZONE_DEBOUNCE then
                -- 驻留达标，确认切换
                currentZoneR = targetZoneR   -- 旧区域，用于颜色过渡起点
                targetZoneR = bestR          -- 新区域，颜色过渡终点 & 当前实际区域
                zoneColorT = 0
                local info = ZONE_TABLE[bestR]
                if info then
                    zoneNotify.text = info[3]
                    zoneNotify.timer = 3.0
                    zoneNotify.alpha = 255
                end
                pendingZoneTime = 0
            end
        else
            -- 新的候选区域，重置计时
            pendingZoneR = bestR
            pendingZoneTime = dt
        end
    else
        -- 回到当前区域，清除候选
        pendingZoneR = targetZoneR
        pendingZoneTime = 0
    end
    -- 颜色过渡
    if zoneColorT < 1.0 then
        zoneColorT = math.min(1.0, zoneColorT + dt * ZONE_FADE_SPEED)
    end
    -- 区域通知淡出
    if zoneNotify.timer > 0 then
        zoneNotify.timer = zoneNotify.timer - dt
        if zoneNotify.timer < 1.0 then
            zoneNotify.alpha = math.floor(255 * zoneNotify.timer)
        end
    end

    -- 处理虚拟输入
    UpdateVirtualInput(dt)

    -- 按状态更新
    if STATE == "menu" then
        -- 等待按键
    elseif STATE == "sailing" then
        UpdateBoat(dt)
        UpdateWake(dt)
        UpdateFishShadows(dt)
        UpdateHotspotBubbles(dt)
        UpdateHotspotFish(dt)
        UpdateHotspotRings(dt)
        UpdateFloatingPlanks(dt)
        UpdateCasting(dt)
        UpdateRods(dt)
        UpdateStrike(dt)
        UpdateRodAim(dt)
        UpdateRopes(dt)
    elseif STATE == "fight" then
        UpdateBoat(dt)
        UpdateWake(dt)
        UpdateRodAim(dt)
        UpdateRopes(dt)
        UpdateFight(dt)
    elseif STATE == "catch" or STATE == "fail" then
        -- 等待确认
    end
end

-- 任意 UI 面板打开时返回 true（用于屏蔽钓鱼操作）
function AnyUIOpen()
    return islandMenuOpen or questPanelOpen or inventoryOpen or fishAtlasOpen or mapOpen or rodShopOpen or hookSelectorOpen or baitSelectorOpen or warehouseOpen or boatUpgradeOpen or cabinOpen
end

function UpdateBoat(dt)
    -- 任意 UI 面板打开时禁止开船操作（含岛屿菜单、商店、鱼铺等所有界面）
    if AnyUIOpen() then return end
    local inFight = (STATE == "fight")

    -- 键盘输入
    local turnDir = 0
    local accel = false
    if input:GetKeyDown(KEY_A) or input:GetKeyDown(KEY_LEFT) then turnDir = turnDir - 1 end
    if input:GetKeyDown(KEY_D) or input:GetKeyDown(KEY_RIGHT) then turnDir = turnDir + 1 end

    -- W 键: 遛鱼时禁止主动加速
    if not inFight then
        if input:GetKeyDown(KEY_W) or input:GetKeyDown(KEY_UP) then accel = true end
    end

    -- S 键: 倒挡 (反向行驶) + 退出巡航
    local reverse = false
    if input:GetKeyDown(KEY_S) or input:GetKeyDown(KEY_DOWN) then
        boat.cruise = false
        reverse = true
    end

    -- 巡航模式
    if boat.cruise then
        if inFight then
            accel = true
        else
            accel = true
        end
    end

    -- 虚拟摇杆输入
    if vJoy.active then
        local jLen = math.sqrt(vJoy.dx * vJoy.dx + vJoy.dy * vJoy.dy)
        if jLen > 0.2 then
            if not inFight then
                accel = true
            end
            local targetAngle = math.atan(vJoy.dx, -vJoy.dy)
            local diff = targetAngle - boat.angle
            while diff > math.pi do diff = diff - 2 * math.pi end
            while diff < -math.pi do diff = diff + 2 * math.pi end
            if math.abs(diff) > 0.05 then
                turnDir = diff > 0 and 1 or -1
            end
        end
    end



    -- 加速 / 减速
    local maxSpd = CFG.BOAT_MAX_SPEED
    local accelRate = CFG.BOAT_ACCEL
    if inFight then
        maxSpd = CFG.BOAT_MAX_SPEED * 0.25
        accelRate = CFG.BOAT_ACCEL * 0.5
    elseif boat.cruise then
        maxSpd = CFG.BOAT_MAX_SPEED * 0.5
    end

    -- 转向 (角速度按速度比例缩放, 保持转弯半径一致; 倒挡时转向反转)
    local absSpd = math.abs(boat.speed)
    if turnDir ~= 0 and absSpd > 5 then
        local spdRatio = math.min(1, absSpd / CFG.BOAT_MAX_SPEED)
        local turnSpd = CFG.BOAT_TURN_SPEED * math.max(0.2, spdRatio)
        -- 倒挡时转向反转, 符合真实船操作
        local turnSign = boat.speed >= 0 and 1 or -1
        boat.angle = boat.angle + turnDir * turnSpd * turnSign * dt
    end

    local reverseMax = maxSpd * 0.60  -- 倒挡最大速度 = 前进的 60%
    if accel then
        -- 前进加速: 若在倒挡中先刹停再加速
        if boat.speed < 0 then
            boat.speed = math.min(0, boat.speed + accelRate * dt)
        else
            boat.speed = math.min(maxSpd, boat.speed + accelRate * dt)
        end
    elseif reverse then
        -- 倒挡: 若在前进中先刹停再倒退
        if boat.speed > 0 then
            boat.speed = math.max(0, boat.speed - CFG.BOAT_DECEL * 2 * dt)
        else
            boat.speed = math.max(-reverseMax, boat.speed - accelRate * 0.5 * dt)
        end
    else
        -- 无输入: 自然减速归零
        if boat.speed > 0 then
            boat.speed = math.max(0, boat.speed - CFG.BOAT_DECEL * dt)
        elseif boat.speed < 0 then
            boat.speed = math.min(0, boat.speed + CFG.BOAT_DECEL * dt)
        end
    end
    -- 如果当前速度超过限速(刚进入fight), 平滑减到限速
    if boat.speed > maxSpd then
        boat.speed = math.max(maxSpd, boat.speed - CFG.BOAT_DECEL * dt)
    end

    -- 移动
    local dx = math.sin(boat.angle) * boat.speed * dt
    local dy = -math.cos(boat.angle) * boat.speed * dt
    local prevX, prevY = boat.x, boat.y
    boat.x = boat.x + dx
    boat.y = boat.y + dy

    -- ── 岛屿碰撞检测 & 推回（多点检测：船头/船尾/左舷/右舷） ──
    local sinA = math.sin(boat.angle)
    local cosA = math.cos(boat.angle)
    local halfL = CFG.BOAT_LENGTH * CFG.BOAT_SCALE * 0.5
    local halfW = CFG.BOAT_WIDTH  * CFG.BOAT_SCALE * 0.5
    -- 沿船体方向的 4 个探测点 + 中心
    local probes = {
        { boat.x,                        boat.y },                          -- 中心
        { boat.x + sinA * halfL,         boat.y - cosA * halfL },           -- 船头
        { boat.x - sinA * halfL,         boat.y + cosA * halfL },           -- 船尾
        { boat.x + cosA * halfW,         boat.y + sinA * halfW },           -- 右舷
        { boat.x - cosA * halfW,         boat.y - sinA * halfW },           -- 左舷
    }
    local hitIsland = nil
    for _, p in ipairs(probes) do
        hitIsland = IslandSystem.CheckCollision(p[1], p[2])
        if hitIsland then break end
    end
    if hitIsland then
        -- 回退到碰撞前位置, 沿岛屿中心反方向推开
        boat.x = prevX
        boat.y = prevY
        local pushDx = prevX - hitIsland.x
        local pushDy = prevY - hitIsland.y
        local pushDist = math.sqrt(pushDx * pushDx + pushDy * pushDy)
        if pushDist > 0.1 then
            local pushStrength = 40 * dt
            boat.x = boat.x + (pushDx / pushDist) * pushStrength
            boat.y = boat.y + (pushDy / pushDist) * pushStrength
        end
        -- 碰撞后大幅减速
        boat.speed = boat.speed * 0.3
    end

    -- 相机跟随
    if inFight then
        -- 遛鱼时: 相机偏移到船和鱼的中点方向, 保持两者都在视野内
        local fx, fy = GetFishWorldPos()
        -- 相机目标 = 船位 + 30%偏移向鱼 (偏向船, 鱼在视野边缘)
        local camTargetX = boat.x + (fx - boat.x) * 0.3
        local camTargetY = boat.y + (fy - boat.y) * 0.3
        local lerpSpeed = 3.0 * dt
        camX = camX + (camTargetX - camX) * lerpSpeed
        camY = camY + (camTargetY - camY) * lerpSpeed
    else
        local lerpSpeed = 5.0 * dt
        camX = camX + (boat.x - camX) * lerpSpeed
        camY = camY + (boat.y - camY) * lerpSpeed
    end

    -- 相机缩放
    if inFight then
        -- 固定2倍放大, 让鱼的运动在屏幕上显得更快
        camScaleTarget = 2.0
    else
        camScaleTarget = 1.0
    end
    camScale = camScale + (camScaleTarget - camScale) * 3.0 * dt
end

function UpdateWake(dt)
    -- 生成尾流
    if boat.speed > 15 then
        local backX = boat.x - math.sin(boat.angle) * CFG.BOAT_LENGTH * CFG.BOAT_SCALE * 0.7
        local backY = boat.y + math.cos(boat.angle) * CFG.BOAT_LENGTH * CFG.BOAT_SCALE * 0.7
        local spread = 5
        table.insert(wakeParticles, {
            x = backX + (math.random() - 0.5) * spread,
            y = backY + (math.random() - 0.5) * spread,
            life = 1.5,
            maxLife = 1.5,
            size = 3 + math.random() * 3,
        })
    end

    -- 更新
    for i = #wakeParticles, 1, -1 do
        local p = wakeParticles[i]
        p.life = p.life - dt
        p.size = p.size + dt * 2
        if p.life <= 0 then
            table.remove(wakeParticles, i)
        end
    end

    -- 限制数量
    while #wakeParticles > 200 do
        table.remove(wakeParticles, 1)
    end
end

function UpdateFishShadows(dt)
    for _, fs in ipairs(fishShadows) do
        fs.wobble = fs.wobble + dt * 3
        fs.attracted = false

        -- 检查所有正在拖钓的鱼竿，鱼影被最近的鱼饵吸引
        if boat.speed > 10 then
            for ri = 1, CFG.ROD_COUNT do
                if rods[ri].state == "trolling" then
                    local lureX, lureY = GetLurePosition(ri)
                    local dx = lureX - fs.x
                    local dy = lureY - fs.y
                    local dist = math.sqrt(dx * dx + dy * dy)
                    if dist < 200 then
                        fs.attracted = true
                        local attract = math.max(0, 1 - dist / 200) * 40
                        fs.x = fs.x + (dx / dist) * attract * dt
                        fs.y = fs.y + (dy / dist) * attract * dt
                    end
                end
            end
        end

        -- 随机游动
        fs.angle = fs.angle + (math.random() - 0.5) * 2 * dt
        fs.x = fs.x + math.cos(fs.angle) * fs.speed * dt
        fs.y = fs.y + math.sin(fs.angle) * fs.speed * dt

        -- 离太远则拉回来
        local dx = fs.x - boat.x
        local dy = fs.y - boat.y
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist > 500 then
            fs.angle = math.atan(boat.y - fs.y, boat.x - fs.x)
        end
    end
end

function UpdateRods(dt)
    for i = 1, CFG.ROD_COUNT do
        local rod = rods[i]
        if rod.state == "trolling" then
            rod.timer = rod.timer + dt
            if rod.timer >= rod.biteAt then
                -- 鱼咬钩!
                rod.state = "bite"
                rod.biteTimer = CFG.BITE_WINDOW
                activeRod = i  -- 自动切换到咬钩的鱼竿
                ShowNotify("鱼竿" .. i .. " 鱼咬钩了! 快按空格提竿!", 255, 220, 50)
            end
        elseif rod.state == "bite" then
            rod.biteTimer = rod.biteTimer - dt
            if rod.biteTimer <= 0 then
                -- 超时未反应, 鱼跑了
                rod.state = "trolling"
                rod.timer = 0
                rod.biteAt = RandomBiteTime()
                ShowNotify("鱼竿" .. i .. " 鱼跑了...反应太慢!", 255, 100, 100)
            end
        end
    end
end

-- ── 抬杆动画 ──
function UpdateStrike(dt)
    if not strikeState.active then return end

    strikeState.timer = strikeState.timer + dt

    -- 动画结束 → 进入遛鱼
    if strikeState.timer >= CFG.STRIKE_DURATION then
        strikeState.active = false

        local rod = rods[strikeState.rodIndex]
        rod.state = "trolling"  -- 保持线在水中
        rod.timer = 0

        -- 恢复镜头缩放
        camScaleTarget = camScaleTarget - CFG.STRIKE_ZOOM_PUNCH

        -- 进入遛鱼
        activeRod = strikeState.rodIndex
        StartFight(strikeState.fish)
        strikeState.fish = nil
    end
end

-- ── 抛竿蓄力/飞行/落水 ──
function UpdateCasting(dt)
    local rod = rods[activeRod]

    -- ── 1. 飞行中: 推进鱼线飞行进度 ──
    if rod.state == "casting" then
        rod.flyT = rod.flyT + dt / rod.flyDuration
        if rod.flyT >= 1.0 then
            -- 落水! 转入拖钓
            rod.flyT = 1.0
            rod.state = "trolling"
            rod.timer = 0
            rod.biteAt = RandomBiteTime()
            ShowNotify("鱼竿" .. activeRod .. " 落水! 等待咬钩", 100, 200, 255)
        end
        -- 飞行/落水后继续回落抬杆
        if castState.liftT > 0 then
            castState.liftT = math.max(0, castState.liftT - CFG.CAST_LIFT_DROP_SPEED * dt)
        end
        return  -- 飞行中不处理蓄力输入
    end

    -- ── 2. 蓄力输入 (仅 sailing + rod idle) ──
    if STATE ~= "sailing" or rod.state ~= "idle" then
        castState.charging = false
        castState.power = 0
        return
    end

    -- UI 打开时禁止蓄力（立即中断已有蓄力）
    if AnyUIOpen() then
        castState.charging = false
        castState.power = 0
        return
    end

    local mouseDown = input:GetMouseButtonDown(MOUSEB_LEFT)
    local mx = input:GetMousePosition().x
    local my = input:GetMousePosition().y

    -- 移动端排除虚拟摇杆和按钮区域，PC 端无虚拟控件不需要排除
    local joyZone, btnZone, ibZone = false, false, false
    if IS_MOBILE then
        joyZone = (mx < screenW * 0.5)
        local btnCX = screenW - 90
        local btnCY = screenH - 110
        local btnDist = math.sqrt((mx - btnCX)^2 + (my - btnCY)^2)
        btnZone = btnDist < CFG.ACTION_BTN_R * 1.4
        local ibCX = screenW - 90
        local ibCY = screenH - 220
        local ibDist = math.sqrt((mx - ibCX)^2 + (my - ibCY)^2)
        ibZone = ibDist < CFG.INTERACT_BTN_R * 1.4
    end

    -- 抬杆进度: 蓄力中跟随 power, 松手后立刻回落
    if castState.charging then
        castState.liftT = castState.power  -- 与蓄力进度同步
    elseif castState.liftT > 0 then
        castState.liftT = math.max(0, castState.liftT - CFG.CAST_LIFT_DROP_SPEED * dt)
    end

    if castState.charging then
        -- ── 已在蓄力中: 只看鼠标是否仍按下, 不再检查区域 ──
        if mouseDown then
            castState.power = math.min(1.0, castState.power + dt / CFG.CAST_CHARGE_TIME)
            castState.liftT  = castState.power  -- 实时同步
        else
            -- 松开鼠标 → 释放抛投!
            castState.charging = false

            -- 计算方向: 沿竿身方向飞出（竿根 → 竿尖，鱼线与竿始终同向）
            local ax, ay = GetRotatedTipWorld(activeRod)
            -- 竿根世界坐标
            local bx_l, by_l = GetRodBaseLocal()
            bx_l = bx_l * rod.side
            local cosA = math.cos(boat.angle)
            local sinA = math.sin(boat.angle)
            local baseWX = boat.x + bx_l * cosA - by_l * sinA
            local baseWY = boat.y + bx_l * sinA + by_l * cosA
            local dx = ax - baseWX
            local dy = ay - baseWY
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist < 0.001 then dx, dy = 0, -1; dist = 1 end
            dx, dy = dx / dist, dy / dist

            -- 抛投距离 = 最小 + (最大-最小) * 力度
            local castDist = CFG.CAST_MIN_DIST + (CFG.CAST_MAX_DIST - CFG.CAST_MIN_DIST) * castState.power

            -- 设置飞行参数
            rod.flyStartX = ax
            rod.flyStartY = ay
            rod.flyTargetX = ax + dx * castDist
            rod.flyTargetY = ay + dy * castDist
            rod.flyT = 0
            rod.flyDuration = castDist / CFG.CAST_FLY_SPEED

            -- 初始化绳索: 只创建 2 个节点(竿尖+鱼饵), UpdateRopes 按飞出线长动态增加
            rod.rope = {}
            rod.rope[1] = { x = ax, y = ay, px = ax, py = ay }
            rod.rope[2] = { x = ax, y = ay, px = ax, py = ay }

            rod.state = "casting"
            castState.power = 0
            -- 抛投消耗耐久
            rod.durability = math.max(0, rod.durability - 1)
            -- 抛投音效
            sfxCast:Play(sndCast)
        end
    elseif mouseDown and not joyZone and not btnZone and not ibZone then
        -- ── 开始新的蓄力 (仅在非摇杆/按钮/互动按钮区域才能开始) ──
        castState.charging = true
        castState.power = 0
    end
end

-- ── 鱼 AI (极坐标物理: 径向逃跑 + 切向游动) ──
function UpdateFishAI(dt)
    if not curFish then return end
    local ft = curFightType or curFish.type  -- 兜底时用替换类型，否则用鱼本身类型
    -- dragScale 同比缩放 mass 和 dragC, 保持 tau=mass/drag 恒定 (~0.2s)
    -- 这样小鱼和大鱼加速时间一致, 只是终端速度不同
    local scale = ft.dragScale or 1.0
    local mass  = CFG.FISH_MASS * scale
    local dragC = CFG.FISH_DRAG_COEFF * scale

    -- 体力衰减因子: 前25%体力（75%~100%）无衰减，75%以下线性衰减至20%
    local stamRatio = fight.fishStamina / fight.fishMaxStam
    local staminaFactor
    if stamRatio >= 0.75 then
        staminaFactor = 1.0
    else
        -- stamRatio: 0.75→1.0, 0→0.2 线性插值
        staminaFactor = 0.2 + 0.8 * (stamRatio / 0.75)
    end

    -- ════════════════════════════════════════
    -- 径向力 (radial: 鱼试图远离竿尖)
    -- ════════════════════════════════════════

    -- 波形周期更新
    fight.radWaveTime = fight.radWaveTime + dt
    if fight.radWaveTime >= fight.radWaveDur then
        GenerateRadialWave()
    end

    -- 径向状态更新 (calm/active 切换)
    fight.radStateTimer = fight.radStateTimer + dt
    if fight.radStateTimer >= fight.radStateDur then
        ChangeRadialState()
    end

    -- 振幅百分比平滑过渡 (约2秒完成切换)
    local ampSmoothT = 1.0 - math.exp(-2.0 * dt)
    fight.radAmpPct = fight.radAmpPct +
        (fight.radAmpPctTarget - fight.radAmpPct) * ampSmoothT

    -- sin 波形: 基础值 + 基线*振幅百分比 * sin(相位)
    local radPhase = (fight.radWaveTime / fight.radWaveDur) * math.pi * 2
    local actualAmp = fight.radWaveBase * fight.radAmpPct
    local radialPullPct = fight.radWaveBase + actualAmp * math.sin(radPhase)
    -- >1.0 → 力超maxForce(断线风险), <0 → 负径向力/鱼朝你游(空力期)

    -- 个体有效拉力: forceAtMax × (体重/wMax)^forceExp
    local effectiveForce = (ft.forceAtMax or ft.maxForce or 60)
        * ((curFish.weight / math.max(0.001, ft.wMax)) ^ (ft.forceExp or 0))
    fight.effectiveForce = effectiveForce  -- 缓存供外层体力消耗使用

    local forceRadial
    if ft.testFixed then
        forceRadial = effectiveForce  -- 测试鱼: 恒定力, 不受波动/体力影响
    else
        forceRadial = effectiveForce * radialPullPct * staminaFactor
    end

    -- ════════════════════════════════════════
    -- 挣扎微力 (tremor: 持续颤动 + jerk: 随机甩头)
    -- ════════════════════════════════════════
    if not ft.testFixed then
        local d = (ft.diff - 1) / 4   -- 0~1 难度系数

        -- (1) 颤动: 双频正弦叠加, 模拟鱼尾/身体摆动
        local freq1 = 8 + d * 6                     -- 基频 8~14 Hz
        local freq2 = freq1 * 2.3 + 1.7             -- 二次谐波(非整数倍, 更自然)
        fight.tremorPhase  = fight.tremorPhase  + freq1 * math.pi * 2 * dt
        fight.tremorPhase2 = fight.tremorPhase2 + freq2 * math.pi * 2 * dt
        local tremorAmpPct = 0.06 + d * 0.06        -- 6%~12% of maxForce (原来2%~5%)
        if fight.radState == "active" then
            tremorAmpPct = tremorAmpPct * 2.0        -- active 时颤动翻倍
        end
        local tremorWave = math.sin(fight.tremorPhase) * 0.7
                         + math.sin(fight.tremorPhase2) * 0.3   -- 双频叠加
        local tremorForce = effectiveForce * tremorAmpPct * tremorWave * staminaFactor

        -- (2) 甩头: 不定时短促脉冲, 模拟猛甩头/冲刺
        local jerkForce = 0
        if fight.jerkTimer > 0 then
            -- 甩头进行中: 半正弦包络 (快起快落)
            fight.jerkTimer = fight.jerkTimer - dt
            if fight.jerkTimer <= 0 then
                fight.jerkTimer = 0
                fight.jerkCooldown = 0.3 + math.random() * (1.5 - d * 0.8)  -- 冷却更短
            else
                local progress = 1.0 - fight.jerkTimer / fight.jerkDurTotal  -- 用存储的总时长
                local envelope = math.sin(progress * math.pi)  -- 0→1→0 包络
                local jerkAmpPct = 0.12 + d * 0.13             -- 12%~25% of maxForce (原来5%~15%)
                jerkForce = effectiveForce * jerkAmpPct * fight.jerkAmp * envelope * staminaFactor
            end
        else
            -- 冷却中
            fight.jerkCooldown = fight.jerkCooldown - dt
            if fight.jerkCooldown <= 0 then
                -- 触发新的甩头
                local dur = 0.12 + math.random() * 0.25        -- 持续 0.12~0.37 秒
                fight.jerkTimer    = dur
                fight.jerkDurTotal = dur                        -- 存下总时长给包络用
                fight.jerkAmp = math.random() > 0.5 and 1 or -1  -- 随机方向
                if fight.radState == "active" then
                    fight.jerkAmp = fight.jerkAmp * 1.6         -- active 时更猛
                end
            end
        end

        forceRadial = forceRadial + tremorForce + jerkForce
    end

    -- ════════════════════════════════════════
    -- 切向力 (tangential: 鱼左右摆动/横游)
    -- ════════════════════════════════════════

    -- 状态计时
    fight.tanTimer = fight.tanTimer + dt
    if fight.tanTimer >= fight.tanDuration then
        ChangeTangentialState()
    end
    -- sin 波形
    fight.tanWaveTime = fight.tanWaveTime + dt
    if fight.tanWaveTime >= fight.tanWaveDur then
        fight.tanWaveTime = fight.tanWaveTime - fight.tanWaveDur
    end
    local tanPhase = (fight.tanWaveTime / fight.tanWaveDur) * math.pi * 2
    local tangentialPull = fight.tanWaveBase + fight.tanWaveAmp * math.sin(tanPhase)
    tangentialPull = math.max(-1, math.min(1, tangentialPull)) * staminaFactor

    -- ════════════════════════════════════════
    -- 角度限制 (余弦阻尼 + 恢复力)
    -- ════════════════════════════════════════

    local maxAngleRad = math.rad(CFG.FISH_MAX_ANGLE)
    local dampStartRad = math.rad(CFG.FISH_ANGLE_DAMP_START)
    local angleDiff = math.abs(fight.fishAngle)

    -- 超过阻尼起始角度后, 切向力逐渐被削弱
    if angleDiff > dampStartRad then
        local t = math.min(1, (angleDiff - dampStartRad) / (maxAngleRad - dampStartRad))
        local damping = math.cos(t * math.pi * 0.5)  -- 1→0 余弦衰减
        tangentialPull = tangentialPull * damping
    end

    -- 恢复力: 偏转角越大, 越强的回正力
    local restoreForce = 0
    if angleDiff > dampStartRad then
        local sign = fight.fishAngle > 0 and -1 or 1
        restoreForce = sign * CFG.FISH_RESTORE_STR *
            ((angleDiff - dampStartRad) / (maxAngleRad - dampStartRad))
    end

    local forceTangential = tangentialPull * effectiveForce * 0.5 * (ft.tanCoeff or 1.0) + restoreForce

    -- ════════════════════════════════════════
    -- 径向物理 (牛顿力学)
    -- ════════════════════════════════════════

    local radius = math.max(1, fight.fishRadius)  -- 防止除零

    -- 离心力 (角运动产生的径向分量)
    local centrifugal = mass * fight.fishAngVel * fight.fishAngVel * radius

    -- 张力对径向的抑制 (线拉住鱼, 阻止远离)
    local tensionRadial = fight.tension  -- 张力直接抵消径向速度

    -- 径向合力 = 逃跑力 + 离心力 - 张力阻抗 - 线性阻力 - 二次方阻力
    -- 二次方阻力按鱼体截面积缩放: A ∝ L² ∝ wMax^(2/3)
    -- 参考体重 100g → (wMax/100)^(2/3); 大鱼阻力更大, 符合物理直觉
    local qd = CFG.FISH_QUAD_DRAG * ((ft.wMax or 1.0) / 100.0) ^ (2/3)
    local netRadial = forceRadial + centrifugal - tensionRadial
        - fight.fishRadVel * dragC
        - math.abs(fight.fishRadVel) * fight.fishRadVel * qd

    -- 加速度 → 速度 → 位置
    fight.fishRadVel = fight.fishRadVel + (netRadial / mass) * dt
    -- 速度限制: 逃跑方向(正)受鱼种上限约束, 被拉近方向(负)用全局上限
    -- 避免低速上限的小鱼在收线时产生虚假阻力
    local rCap = ft.radSpeedMax or CFG.FISH_SPEED_CAP
    fight.fishRadVel = math.min(rCap, fight.fishRadVel)                      -- 逃跑方向限速
    fight.fishRadVel = math.max(-CFG.FISH_SPEED_CAP, fight.fishRadVel)       -- 被拉近方向用全局上限
    fight.fishRadius = fight.fishRadius + fight.fishRadVel * dt
    fight.fishRadius = math.max(0, fight.fishRadius)  -- 不能为负

    -- ════════════════════════════════════════
    -- 切向物理 (线速度模型)
    -- ════════════════════════════════════════

    -- 角速度 → 线速度
    local tangentialSpeed = fight.fishAngVel * radius

    -- 切向合力 = 横游力 - 线性阻力 - 二次方阻力
    local netTangent = forceTangential - tangentialSpeed * dragC
        - math.abs(tangentialSpeed) * tangentialSpeed * qd
    tangentialSpeed = tangentialSpeed + (netTangent / mass) * dt
    -- 速度限制 (优先使用鱼种自定义上限)
    local tCap = ft.tanSpeedMax or CFG.FISH_TAN_SPEED_CAP
    tangentialSpeed = math.max(-tCap, math.min(tCap, tangentialSpeed))

    -- 线速度 → 角速度
    fight.fishAngVel = tangentialSpeed / radius
    fight.fishAngle = fight.fishAngle + fight.fishAngVel * dt

    -- 硬约束角度范围
    fight.fishAngle = math.max(-maxAngleRad, math.min(maxAngleRad, fight.fishAngle))
end

-- ── 遛鱼主更新 (弹性张力 + 惯性打滑 + 加速度收线) ──
function UpdateFight(dt)
    fight.fightTime = fight.fightTime + dt

    -- 0. 船位移补偿: 鱼在世界空间中保持不动, 重算极坐标
    --    上一帧末尾缓存了鱼的世界坐标, 本帧 UpdateBoat 已跑完 (船已移动)
    --    从新竿尖到缓存位置反算 fishRadius / fishAngle
    if fight.fishWorldX then
        local ax, ay = GetRotatedTipWorld(activeRod)
        local dx = fight.fishWorldX - ax
        local dy = fight.fishWorldY - ay
        local newRadius = math.sqrt(dx * dx + dy * dy)
        if newRadius > 0.01 then
            fight.fishRadius = newRadius
            -- 反算世界角度, 然后减去 fishInitAngle 得到偏转量
            local worldAngle = math.atan(dx, -dy)
            local newAngle = worldAngle - fight.fishInitAngle
            -- 归一化到 [-pi, pi]
            while newAngle >  math.pi do newAngle = newAngle - 2 * math.pi end
            while newAngle < -math.pi do newAngle = newAngle + 2 * math.pi end
            fight.fishAngle = newAngle
        end
    end

    -- 1. 鱼 AI (极坐标物理, 更新 fishRadius/fishAngle)
    UpdateFishAI(dt)

    -- 2. 玩家输入（UI 打开时禁止收线）
    fight.reeling = (not AnyUIOpen()) and (input:GetMouseButtonDown(MOUSEB_LEFT) or actionDown)

    -- 2b. 右键抬杆 (伪透视压杆) —— 物理节奏优化
    local lifting = input:GetMouseButtonDown(MOUSEB_RIGHT)
    if lifting then
        -- 抬杆: 起步快 → 越高越吃力 (easing), 张力大时更费力
        local easeFactor = 0.3 + 0.7 * (1.0 - fight.liftT)              -- 顶端只剩 30% 速度
        local tensionNorm = math.min(1.0, (fight.tension or 0) / fight.lineStrength)
        local tensionBrake = 1.0 - CFG.FIGHT_LIFT_TENSION_DRAG * tensionNorm -- 满张力时速度 × 0.3
        local upSpeed = CFG.FIGHT_LIFT_SPEED_UP * easeFactor * tensionBrake
        fight.liftT = math.min(1.0, fight.liftT + upSpeed * dt)
    else
        -- 放杆: 重力加速，杆越高下落越快 (模拟自由落体感)
        local gravFactor = 0.4 + 0.6 * fight.liftT                      -- 低位 40% 速度, 高位 100%
        local downSpeed = CFG.FIGHT_LIFT_SPEED_DOWN * gravFactor
        fight.liftT = math.max(0.0, fight.liftT - downSpeed * dt)
    end
    -- 计算抬起高度: 鱼竿长度 × sin(抬起角度)
    local liftAngle = fight.liftT * CFG.FIGHT_LIFT_MAX_ANGLE
    local rodLen = GetRodPhysicalLength()
    fight.liftHeight = rodLen * math.sin(liftAngle)

    -- 3. 刹车调节 (鼠标滚轮换档, 每次±1档)
    local wheel = input.mouseMoveWheel
    if wheel ~= 0 then
        local step = wheel > 0 and 1 or -1
        fight.dragGear = math.max(0, math.min(CFG.FIGHT_DRAG_GEARS, fight.dragGear + step))
        -- 棘轮换挡音效
        sfxShiftRatchet:Play(sndShiftRatchet)
    end
    -- 派生刹车比例: 0~29 → 0%~dragMaxRatio, 30 → 锁死(用1.0保证不打滑)
    if fight.dragGear >= CFG.FIGHT_DRAG_GEARS then
        fight.drag = 1.0  -- 锁死: dragForce = LINE_STRENGTH, 永不打滑
    else
        fight.drag = fight.dragGear / (CFG.FIGHT_DRAG_GEARS - 1) * fight.dragMaxRatio
    end

    -- ════════════════════════════════════════
    -- 4. 收线 (张力越大越费力, 有效速度衰减)
    -- ════════════════════════════════════════
    if fight.reeling then
        fight.reelSpeed = math.min(fight.reelSpeedMax,
            fight.reelSpeed + fight.reelAccel * dt)
        -- 张力衰减: 满载时只剩 10% 效率, 空载 100%
        local tensionRatio = fight.tension / fight.lineStrength
        local efficiency = 1.0 - tensionRatio * 0.9
        fight.effectiveReel = fight.reelSpeed * efficiency
        fight.lineLength = fight.lineLength - fight.effectiveReel * dt
    else
        fight.reelSpeed = 0
        fight.effectiveReel = 0
    end
    fight.lineLength = math.max(0, fight.lineLength)

    -- 收线音效: 播放/停止 + 频率随有效速度变化
    if fight.reeling and fight.effectiveReel > 0.5 then
        if not sfxReelTurning:IsPlaying() then
            sfxReelTurning:Play(sndReelTurning)
        end
    else
        if sfxReelTurning:IsPlaying() then
            sfxReelTurning:Stop()
        end
    end

    -- 卷轮旋转角度累积 (非线性映射, 无张力~5圈/秒, 满张力~0.6圈/秒)
    -- 幂曲线 ratio^1.75 把 3.3x 速度差放大到 ~8x 视觉差, 慢速时更明显
    local reelRatio = fight.effectiveReel / (fight.reelSpeedMax or CFG.FIGHT_REEL_MAX)
    local reelRPS = 2.5 * (reelRatio ^ 1.75)
    fight.reelAngle = fight.reelAngle + reelRPS * 2 * math.pi * dt
    -- 打滑反转
    local slipRatio = math.min(1, fight.slipSpeed / 30)  -- 30m/s 对应满速反转
    local slipRPS = 2.5 * (slipRatio ^ 1.75)
    fight.reelAngle = fight.reelAngle - slipRPS * 2 * math.pi * dt

    -- ════════════════════════════════════════
    -- 5. 统一约束解算 (卷轮惯性模型)
    -- ════════════════════════════════════════
    -- 物理模型: 卷轮有虚拟质量, 张力与刹车力的差值产生加速度.
    --   netForce = tension - dragForce
    --   正 → 加速放线(鱼拉力 > 刹车摩擦)
    --   负 → 减速制动(刹车摩擦 > 当前张力)
    --   slipSpeed 持续积累, 模拟真实卷轮的惯性响应.

    local dragForce = fight.drag * fight.lineStrength  -- 刹车力(kg)

    -- (a) 当前拉伸量和张力
    -- 抬杆时用 3D 距离: 水平鱼距 + 竖直抬起高度 → 实际线长
    local dist3D = math.sqrt(fight.fishRadius * fight.fishRadius + fight.liftHeight * fight.liftHeight)
    local rawStretch = math.max(0, dist3D - fight.lineLength)
    local rawTension = math.min(fight.lineStrength,
        (rawStretch / fight.stretchMax) * fight.lineStrength)

    -- (b) 卷轮力学: F=ma, 含粘性阻尼
    --   netForce = (tension - drag) - damping * speed
    --   阻尼力与速度成正比, 抑制阈值附近的过冲振荡
    local dampingForce = CFG.FIGHT_SLIP_DAMPING * fight.slipSpeed
    local netForce = rawTension - dragForce - dampingForce
    if netForce > 0 then
        -- 净力为正: 卷轮加速放线
        fight.slipSpeed = fight.slipSpeed + (netForce / CFG.FIGHT_SLIP_MASS) * dt
    elseif fight.slipSpeed > 0 then
        -- 净力为负但卷轮仍在转: 减速制动
        local decel = math.abs(netForce) / CFG.FIGHT_SLIP_MASS
        fight.slipSpeed = math.max(0, fight.slipSpeed - decel * dt)
    end
    -- 安全上限
    fight.slipSpeed = math.min(fight.slipSpeed, CFG.FIGHT_SLIP_SPEED_MAX)

    -- (c) 应用放线
    local slipDelta = fight.slipSpeed * dt
    fight.lineLength = fight.lineLength + slipDelta

    -- (d) 重算实际张力 (放线后拉伸量变化, 含抬杆3D距离)
    local dist3D_post = math.sqrt(fight.fishRadius * fight.fishRadius + fight.liftHeight * fight.liftHeight)
    local actualStretch = math.max(0, dist3D_post - fight.lineLength)
    fight.tension = math.min(fight.lineStrength,
        (actualStretch / fight.stretchMax) * fight.lineStrength)

    -- 线长上限钳位
    fight.lineLength = math.max(0, fight.lineLength)

    -- (e) 打滑状态 (基于放线速度判定)
    fight.slipping = fight.slipSpeed > 0.1
    if fight.slipping then
        fight.slipRecentTimer = CFG.FIGHT_SLIP_MEMORY
        if not sfxReelClicks:IsPlaying() then
            sfxReelClicks:Play(sndReelClicks)
        end
    else
        if sfxReelClicks:IsPlaying() then
            sfxReelClicks:Stop()
        end
    end

    -- ════════════════════════════════════════
    -- 5b. 诊断记录 (每帧采样)
    -- ════════════════════════════════════════
    if diagEnabled then
        local elapsed = fight.fightTime - diagStartTime
        diagLog[#diagLog + 1] = {
            t        = elapsed,
            tension  = fight.tension,
            slipSpd  = fight.slipSpeed,
            lineLen  = fight.lineLength,
            dragF    = dragForce,
            fishR    = fight.fishRadius,
        }
    end

    -- 波形图缓冲 (始终采样, 开关只控制显示)
    diagChartIdx = (diagChartIdx % DIAG_CHART_LEN) + 1
    diagChartBuf[diagChartIdx] = { tension = fight.tension, dragF = dragForce }

    -- ════════════════════════════════════════
    -- 6. 显示值直接同步 (约束解算已消除振荡, 无需平滑)
    -- ════════════════════════════════════════
    fight.slipRecentTimer = math.max(0, fight.slipRecentTimer - dt)
    fight.tensionVisual = fight.tension

    -- ════════════════════════════════════════
    -- 8. 鱼体力消耗
    -- ════════════════════════════════════════
    -- 底数1.0（时间消耗）+ 压制比（张力/鱼本身最大拉力）× 1.75
    local tensionToForceRatio = fight.tension / math.max(0.001, fight.effectiveForce or 1)
    local staminaDrain = 1.0 + tensionToForceRatio * 1.75
    if fight.reeling and not fight.slipping then
        staminaDrain = staminaDrain + 1.5  -- 被拉向岸边更累
    end
    local prevStamina = fight.fishStamina
    fight.fishStamina = math.max(0, fight.fishStamina - staminaDrain * dt)
    -- 首次归零时记录耗时
    if prevStamina > 0 and fight.fishStamina <= 0 and not fight.staminaDepletedAt then
        fight.staminaDepletedAt = gameTime - fight.fightStartTime
    end

    -- ════════════════════════════════════════
    -- 9. 胜负判定
    -- ════════════════════════════════════════
    -- 9a. 渔线轮机械强度超限 → 渔线轮损坏（0.1秒延迟）
    if fight.reelMechStrength and fight.tension >= fight.reelMechStrength then
        fight.reelBreakTimer = fight.reelBreakTimer + dt
        if fight.reelBreakTimer >= 0.1 then
            sfxReelClicks:Stop()
            sfxReelTurning:Stop()
            STATE = "fail"
            local rod = rods[activeRod]
            rod.state = "idle"; rod.timer = 0; rod.rope = {}
            ShowNotify("渔线轮损坏! 张力超过机械强度!", 255, 100, 60)
            return
        end
    else
        fight.reelBreakTimer = 0
    end

    if fight.tension >= fight.lineStrength then
        -- 张力满载, 开始/继续断线倒计时
        if fight.breakTimer <= 0 then
            fight.breakDelay = 0.2 + math.random() * 0.5  -- 随机 0.2~0.7秒
        end
        fight.breakTimer = fight.breakTimer + dt
        if fight.breakTimer >= fight.breakDelay then
            -- 断线!
            sfxReelClicks:Stop()
            sfxReelTurning:Stop()
            STATE = "fail"
            local rod = rods[activeRod]
            rod.durability = math.max(0, rod.durability - 50)
            rod.state = "idle"; rod.timer = 0; rod.rope = {}
            ShowNotify("断线了! 张力过大!", 255, 80, 80)
            return
        end
    else
        -- 张力回落, 重置倒计时
        fight.breakTimer = 0
    end
    if fight.lineLength >= fight.lineCapacity and not diagInfiniteLine then
        -- 清杯!
        sfxReelClicks:Stop()
        sfxReelTurning:Stop()
        STATE = "fail"
        local rod = rods[activeRod]
        rod.durability = math.max(0, rod.durability - 50)
        rod.state = "idle"; rod.timer = 0; rod.rope = {}
        ShowNotify("清杯了! 线被拽完!", 255, 80, 80)
        return
    end
    if fight.fishRadius <= CFG.FIGHT_CATCH_DIST then
        -- 鱼被拉到手边, 成功!
        sfxReelClicks:Stop()
        sfxReelTurning:Stop()
        sfxNet:Play(sndNet)   -- 抄网入水音效
        STATE = "catch"
        local rod = rods[activeRod]
        rod.state = "idle"; rod.timer = 0; rod.rope = {}
        if #caughtList >= CFG.BAG_SIZE then
            -- 背包已满，鱼跑掉
            ShowNotify("背包已满！" .. curFish.type.name .. " 逃跑了", 255, 100, 80)
        else
            table.insert(caughtList, curFish)
            totalWeight = totalWeight + curFish.weight
            ShowNotify("钓到了 " .. curFish.type.name .. "! " ..
                FormatWeight(curFish.weight), 50, 255, 100)
            -- 显示钓获详情面板
            UIPanel2.Show(curFish)
        end
        return
    end

    -- 帧末缓存鱼的世界坐标, 供下帧船位移补偿使用
    local newFX, newFY = GetFishWorldPos()

    -- 计算鱼影朝向: 基于帧间位移方向, 平滑过渡
    if fight.fishWorldX then
        local moveDX = newFX - fight.fishWorldX
        local moveDY = newFY - fight.fishWorldY
        local moveDist = math.sqrt(moveDX * moveDX + moveDY * moveDY)
        if moveDist > 0.5 then  -- 有足够位移才更新朝向, 避免静止时抖动
            local targetHeading = math.atan(moveDX, -moveDY)  -- 与 boat.angle 同系
            -- 平滑过渡朝向, 避免瞬间转头
            local diff = targetHeading - (fight.fishHeading or targetHeading)
            while diff >  math.pi do diff = diff - 2 * math.pi end
            while diff < -math.pi do diff = diff + 2 * math.pi end
            fight.fishHeading = (fight.fishHeading or targetHeading) + diff * math.min(1, 8.0 * dt)
        end
    end
    if not fight.fishHeading then
        fight.fishHeading = fight.fishInitAngle + fight.fishAngle  -- 初始用极坐标方向
    end

    fight.fishWorldX, fight.fishWorldY = newFX, newFY
end

function GetLurePosition(rodIndex)
    rodIndex = rodIndex or activeRod
    local rod = rods[rodIndex]
    -- 如果有绳索物理数据，返回末端节点位置
    if #rod.rope > 0 then
        local last = rod.rope[#rod.rope]
        return last.x, last.y
    end
    -- 回退: 无绳索时从竿尖向后计算
    local ax, ay = GetRodAnchor(rodIndex)
    local outAngle = boat.angle + rod.side * 0.3
    local lx = ax + math.sin(outAngle) * CFG.LINE_LENGTH
    local ly = ay - math.cos(outAngle) * CFG.LINE_LENGTH
    return lx, ly
end

-- ============================================================================
-- 虚拟输入
-- ============================================================================

function UpdateVirtualInput(dt)
    local isDown = input:GetMouseButtonDown(MOUSEB_LEFT)

    -- ── HUD 工具条 rising-edge 检测（在 AnyUIOpen 之前处理，背包按钮需要在开着时也能响应）
    local freshPress = isDown and not lastMouseDown_
    if freshPress and #hudBtns_ > 0 then
        local mx0 = input:GetMousePosition().x
        local my0 = input:GetMousePosition().y
        for _, btn in ipairs(hudBtns_) do
            if mx0 >= btn.x and mx0 <= btn.x + btn.w
            and my0 >= btn.y and my0 <= btn.y + btn.h then
                HandleMobileBtn(btn.id)
                lastMouseDown_ = isDown
                return  -- 消耗触摸，不传给摇杆/动作按钮
            end
        end
    end
    lastMouseDown_ = isDown

    -- 滚动各按钮状态
    prevActionDown        = actionDown
    prevInteractBtnDown   = interactBtnDown
    actionDown            = false
    actionJustPressed     = false
    interactBtnDown       = false
    interactBtnJustPress  = false

    -- PC 端无虚拟摇杆和虚拟按钮，直接跳过（输入由键盘/鼠标独立处理）
    if not IS_MOBILE then
        vJoy.active = false
        vJoy.dx     = 0
        vJoy.dy     = 0
        UIPanel2.Update(dt, screenW, screenH)
        UISelector.Update(dt)
        return
    end

    -- UI 面板打开或时间滑条拖拽时不处理虚拟摇杆和动作按钮
    if AnyUIOpen() or twSliderDrag_ then
        vJoy.active = false
        vJoy.dx = 0
        vJoy.dy = 0
        return
    end

    -- 互动按钮圆心（右侧中部，当有靠岸/拾取目标时显示）
    local ibCX = screenW - 90
    local ibCY = screenH - 220
    local ibR  = CFG.INTERACT_BTN_R

    -- 动作按钮圆心（右下，固定）
    local abCX = screenW - 90
    local abCY = screenH - 110
    local abR  = CFG.ACTION_BTN_R

    if isDown then
        local mx = input:GetMousePosition().x
        local my = input:GetMousePosition().y

        -- 蓄力抛竿期间只允许互动按钮，跳过摇杆和动作按钮
        if castState.charging then
            -- 不处理（蓄力由 UpdateCasting 独立处理）

        -- fight 状态：全屏右半区触摸 = 持续收线（不需要精准点按钮）
        elseif STATE == "fight" then
            if mx > screenW * 0.45 then
                actionDown = true
                if not prevActionDown then actionJustPressed = true end
            end

        else
            -- 互动按钮区检测（优先级最高，在右侧）
            local ibDist = math.sqrt((mx - ibCX)^2 + (my - ibCY)^2)
            local ibZone = ibDist < ibR * 1.4

            -- 动作按钮区检测
            local abDist = math.sqrt((mx - abCX)^2 + (my - abCY)^2)
            local abZone = abDist < abR * 1.4

            -- 摇杆区：左半屏（互动/动作按钮不在左半屏，无冲突）
            local joyZone = mx < screenW * 0.5

            if ibZone then
                interactBtnDown = true
                if not prevInteractBtnDown then
                    interactBtnJustPress = true
                end
            elseif abZone then
                actionDown = true
                if not prevActionDown then
                    actionJustPressed = true
                end
            elseif joyZone then
                -- 摇杆跟手（第一次触摸记录基点）
                if not vJoy.active then
                    vJoy.active = true
                    vJoy.baseX  = mx
                    vJoy.baseY  = my
                    vJoy.stickX = mx
                    vJoy.stickY = my
                end
                local jdx   = mx - vJoy.baseX
                local jdy   = my - vJoy.baseY
                local jdist = math.sqrt(jdx * jdx + jdy * jdy)
                local maxD  = CFG.JOYSTICK_R
                if jdist > maxD then
                    jdx = jdx / jdist * maxD
                    jdy = jdy / jdist * maxD
                end
                vJoy.stickX = vJoy.baseX + jdx
                vJoy.stickY = vJoy.baseY + jdy
                if jdist > 10 then
                    vJoy.dx = jdx / maxD
                    vJoy.dy = jdy / maxD
                else
                    vJoy.dx = 0
                    vJoy.dy = 0
                end
            end
        end
    else
        vJoy.active = false
        vJoy.dx     = 0
        vJoy.dy     = 0
    end

    -- 动作按钮触发
    if actionJustPressed and STATE ~= "fight" then
        HandleAction()
    end

    -- 互动按钮触发（等效 E 键）
    if interactBtnJustPress and STATE == "sailing" then
        local nearIsland = FindNearestIsland()
        if nearIsland then
            islandMenuOpen = true
            dockedIsland   = nearIsland
            IslandMenu.Reset(nearIsland)
            boat.speed  = 0
            boat.cruise = false
        else
            local idx = FindNearestPlank()
            if idx then
                local plank  = floatingPlanks[idx]
                local amount = plank.woodAmount
                PlayerData.AddResource("wood", amount)
                ShowNotify("拾取木料 +" .. amount, 210, 175, 110)
                table.remove(floatingPlanks, idx)
                table.insert(floatingPlanks, SpawnPlank(boat))
            end
        end
    end

    -- UI 面板淡入淡出更新
    UIPanel2.Update(dt, screenW, screenH)
    UISelector.Update(dt)
end

-- ============================================================================
-- 输入处理
-- ============================================================================

---@param eventType string
---@param eventData MouseButtonDownEventData
function HandleMouseButtonDown(eventType, eventData)
    if eventData["Button"]:GetInt() ~= MOUSEB_LEFT then return end

    local mx = input.mousePosition.x
    local my = input.mousePosition.y

    -- 竿线调试按钮（右上角）
    do
        local bw, bh = 72, 22
        local bx = screenW - bw - 6
        local by = 6
        if mx >= bx and mx <= bx + bw and my >= by and my <= by + bh then
            rodDebugMode = not rodDebugMode
            print("[ROD DEBUG] 调试模式 " .. (rodDebugMode and "开启" or "关闭"))
            return
        end
    end

    -- 灯光编辑器（优先处理，避免穿透）
    if LightEditor.OnMouseDown(mx, my) then return end

    -- 鱼类图册点击
    if FishAtlas.IsOpen() then
        FishAtlas.HandleClick(mx, my, screenW, screenH)
        return
    end

    -- UI 选择器点击
    if UISelector.IsOpen() then
        UISelector.HandleMouseDown(mx, my)
        return
    end

    -- 时间滑条命中
    if STATE ~= "menu" then
        local t = TimeSliderHitTest(mx, my)
        if t then
            twSliderDrag_ = true
            TimeWeather.SetTOD(t)
            return
        end
    end

    -- 岛屿菜单鼠标点击
    if islandMenuOpen and dockedIsland then
        local result = IslandMenu.HandleMouseClick(mx, my, {
            island = dockedIsland,
        })
        if result and result.openQuest then
            islandMenuOpen = false
            questPanelOpen = true
            QuestSystem.GenerateQuests(dockedIsland.id, FISH_TYPES)
            QuestPanel.Reset()
        elseif result and result.openRodShop then
            islandMenuOpen = false
            rodShopOpen = true
            RodShop.Open()
        elseif result and result.openWarehouse then
            islandMenuOpen = false
            warehouseOpen = true
            Warehouse.Open()
        elseif result and result.openBoatUpgrade then
            islandMenuOpen = false
            boatUpgradeOpen = true
            BoatUpgrade.Open()
        elseif result and result.close then
            islandMenuOpen = false
            dockedIsland = nil
            IslandMenu.Reset()
        end
        return
    end

    -- 背包鼠标点击
    if inventoryOpen then
        if Inventory.HandleClick(mx, my) then return end
    end

    -- 鱼竿升级坊鼠标点击
    if rodShopOpen then
        local consumed, result = RodShop.HandleMouseClick(mx, my, {
            PlayerData    = PlayerData,
            rodTypes      = ROD_TYPES,
            equippedRodId = equippedRodId,
        })
        if result then
            if result.close then
                rodShopOpen = false
                if dockedIsland then
                    islandMenuOpen = true
                    IslandMenu.Reset(dockedIsland)
                end
            elseif result.bought ~= nil then
                -- bought=true 购买成功；bought=false 表示失败
                if result.bought then
                    ShowNotify(result.message or "购买成功！", 100, 230, 120)
                else
                    ShowNotify(result.message or "金钱不足", 240, 100, 80)
                end
            elseif result.crafted ~= nil then
                -- 兼容旧逻辑（保留字段名 crafted）
                if result.crafted then
                    ShowNotify(result.message or "制作成功！", 100, 230, 120)
                else
                    ShowNotify(result.message or "材料不足", 240, 100, 80)
                end
            elseif result.equip then
                local rodId = result.equip
                equippedRodId = rodId
                PlayerData.data.equippedRodId = rodId
                local rt = ROD_TYPES[rodId]
                ShowNotify("已装备 " .. (rt and rt.name or "鱼竿"), 110, 160, 255)
            end
        end
        if consumed then return end
        return
    end

    -- 仓库鼠标点击
    if warehouseOpen then
        local consumed, result = Warehouse.HandleMouseClick(mx, my, {
            PlayerData = PlayerData,
            caughtList = caughtList,
        })
        if result then
            if result.close then
                warehouseOpen = false
                if dockedIsland then
                    islandMenuOpen = true
                    IslandMenu.Reset(dockedIsland)
                end
            end
        end
        if consumed then return end
        return
    end

    -- 船只升级鼠标点击
    if boatUpgradeOpen then
        local consumed, result = BoatUpgrade.HandleMouseClick(mx, my, {
            PlayerData = PlayerData,
        })
        if result then
            if result.close then
                boatUpgradeOpen = false
                if dockedIsland then
                    islandMenuOpen = true
                    IslandMenu.Reset(dockedIsland)
                end
            elseif result.message then
                ShowNotify(result.message)
            end
        end
        if consumed then return end
        return
    end

    -- 船舱鼠标点击
    if cabinOpen then
        local consumed, result = CabinSystem.HandleMouseClick(mx, my, {
            PlayerData = PlayerData,
        })
        if result then
            if result.close then
                cabinOpen = false
            elseif result.message then
                ShowNotify(result.message)
            end
        end
        if consumed then return end
        return
    end

    -- 鱼钩选择器鼠标点击
    if hookSelectorOpen then
        local consumed, result = HookSelector.HandleMouseClick(mx, my, {
            equippedHook = PlayerData.data.equippedHook,
        })
        if result then
            if result.close then
                hookSelectorOpen = false
            elseif result.equip then
                local level = result.equip
                PlayerData.data.equippedHook = level
                hookSelectorOpen = false
                local hk = HookSelector.HOOK_TYPES[level]
                ShowNotify("已装备 " .. (hk and hk.name or "鱼钩") .. " 鱼钩", 100, 200, 255)
            end
        end
        if consumed then return end
        return
    end

    -- 鱼饵选择器鼠标点击
    if baitSelectorOpen then
        local consumed, result = BaitSelector.HandleMouseClick(mx, my, {
            equippedBait = PlayerData.data.equippedBait,
        })
        if result then
            if result.close then
                baitSelectorOpen = false
            elseif result.equip ~= nil then
                local level = result.equip
                PlayerData.data.equippedBait = level
                baitSelectorOpen = false
                if level == 0 then
                    ShowNotify("已卸下鱼饵（空钩）", 180, 180, 180)
                else
                    local bt = BaitSelector.BAIT_TYPES[level]
                    ShowNotify("已装备 " .. (bt and bt.name or "鱼饵"), 100, 220, 180)
                end
            end
        end
        if consumed then return end
        return
    end

    -- 鱼铺面板鼠标点击
    if questPanelOpen and dockedIsland then
        local consumed, result = QuestPanel.HandleMouseClick(mx, my, {
            quests      = QuestSystem.GenerateQuests(dockedIsland.id, FISH_TYPES),
            QuestSystem = QuestSystem,
            caughtList  = caughtList,
            PlayerData  = PlayerData,
        })
        if result then
            if result.close then
                questPanelOpen = false
                if dockedIsland then
                    islandMenuOpen = true
                    IslandMenu.Reset(dockedIsland)
                end
            elseif result.submitted ~= nil then
                -- 重新计算背包总重
                totalWeight = 0
                for _, f in ipairs(caughtList) do totalWeight = totalWeight + f.weight end
                if result.submitted then
                    ShowNotify(result.message or "任务完成！获得 " .. (result.income or 0) .. " 💰", 100, 230, 120)
                else
                    ShowNotify(result.message or "背包鱼不足", 240, 100, 80)
                end
            elseif result.sold then
                -- 直接售卖成功
                totalWeight = 0
                for _, f in ipairs(caughtList) do totalWeight = totalWeight + f.weight end
                ShowNotify("售出 " .. (result.fishName or "鱼") .. " +" .. result.price .. " 💰", 210, 175, 55)
            elseif result.returned then
                -- 退回鱼到背包
                totalWeight = 0
                for _, f in ipairs(caughtList) do totalWeight = totalWeight + f.weight end
                ShowNotify((result.fishName or "鱼") .. " 已退回背包", 130, 180, 220)
            elseif result.refundFail then
                ShowNotify("余额不足，无法退回", 240, 100, 80)
            end
        end
        if consumed then return end
        return
    end

    -- 地图点击
    if not mapOpen then return end
    local lay = mapLayout_
    if not lay then return end

    -- 点击在地图范围内才响应
    if mx < lay.ox or mx > lay.ox + lay.drawW or
       my < lay.oy or my > lay.oy + lay.drawH then
        -- 点在地图外，清除标记
        mapClickPos = nil
        return
    end

    -- 屏幕坐标 → 世界坐标
    local wx = lay.minX + (mx - lay.ox) / lay.drawW * lay.worldW
    local wy = lay.minY + (my - lay.oy) / lay.drawH * lay.worldH
    mapClickPos = { wx = wx, wy = wy, sx = mx, sy = my }
end

function HandleMouseButtonUp(eventType, eventData)
    local btn = eventData["Button"]:GetInt()
    LightEditor.OnMouseUp(btn)
end

function HandleMouseMove(eventType, eventData)
    local mx = input.mousePosition.x
    local my = input.mousePosition.y
    LightEditor.OnMouseMove(mx, my)
end

function HandleMouseWheel(eventType, eventData)
    local wheel = eventData["Wheel"]:GetInt()
    if rodShopOpen and wheel ~= 0 then
        RodShop.HandleScroll(wheel)
    end
    if warehouseOpen and wheel ~= 0 then
        Warehouse.HandleScroll(wheel)
    end
end

function HandleTextInput(eventType, eventData)
    local char = eventData["Text"]:GetString()
    LightEditor.OnTextInput(char)
end

-- ============================================================================
-- 垂钓模拟器
-- ============================================================================

--- 运行 n 次 PickRandomFish()，统计鱼种分布并写入 fishSim
local function RunFishSimulation(n)
    -- 采集当前垂钓条件（用于结果标注）
    local seaType    = ZONE_TYPE_MAP[targetZoneR] or 1
    local seaNames   = { "浅海", "热带海", "沙漠海", "寒带海", "外海" }
    local zoneEntry  = ZONE_TABLE[targetZoneR] or ZONE_TABLE[190]
    local seaName    = zoneEntry[3] or "未知"
    local depthLevel = GetFishDepthLevel(boat.x, boat.y)
    local hookLevel  = PlayerData.data.equippedHook or 3
    local hookNames  = { "微小", "小型", "中型", "大型", "巨大" }
    local baitLevel  = PlayerData.data.equippedBait or 0
    local baitData   = baitLevel > 0 and BaitSelector.BAIT_TYPES[baitLevel] or nil
    local baitLabel  = baitData and (baitData.name .. "(" .. baitLevel .. ")") or "空钩(0)"
    local hour       = TimeWeather.GetHour()
    local timeLabel  = (hour >= 6 and hour < 18) and "白天" or "夜晚"
    local weatherLabel = (weatherMode_ == "sunny") and "晴天" or "雨天"

    fishSim.condStr = string.format(
        "N=%d  海域=%s(T%d)  深度=%d级  鱼钩=%s(%d)  饵=%s  %s  %s",
        n, seaName, seaType, depthLevel,
        hookNames[hookLevel] or "?", hookLevel,
        baitLabel, timeLabel, weatherLabel
    )

    -- 快速循环 n 次选鱼，只计数不做其他操作
    local counts = {}
    for _ = 1, n do
        local fish = PickRandomFish()
        local name = fish.type.name
        counts[name] = (counts[name] or 0) + 1
    end

    -- 转为有序数组（按次数降序）
    local sorted = {}
    for name, cnt in pairs(counts) do
        table.insert(sorted, {
            name = name,
            count = cnt,
            pct = cnt / n * 100,
        })
    end
    table.sort(sorted, function(a, b) return a.count > b.count end)

    fishSim.results = sorted
    fishSim.total   = n
    fishSim.scroll  = 0
    fishSim.running = true

    -- 同步打印到控制台（方便复制到期望计算器对比）
    print(string.rep("=", 62))
    print("垂钓模拟统计  " .. fishSim.condStr)
    print(string.rep("-", 62))
    print(string.format("  %-20s  %7s  %9s", "鱼名", "次数", "实测占比"))
    print(string.rep("-", 62))
    for _, e in ipairs(sorted) do
        print(string.format("  %-20s  %7d  %8.4f%%", e.name, e.count, e.pct))
    end
    print(string.rep("=", 62))
    print("[FishSim] 结果已同步显示在屏幕（I键关闭，↑↓滚动）")
end

---@param eventType string
---@param eventData KeyDownEventData
function HandleKeyDown(eventType, eventData)
    local key = eventData["Key"]:GetInt()

    -- 灯光编辑器（L 键及编辑状态下的文字输入优先处理）
    if LightEditor.OnKeyDown(key) then return end

    -- 对话框打开时拦截所有输入，空格/E/回车关闭
    if _dlg.open then
        if key == KEY_SPACE or key == KEY_RETURN or key == KEY_KP_ENTER or key == KEY_E then
            Dialogue.Hide()
        end
        return
    end

    -- I 键: 垂钓模拟器（调试用）
    -- I         → 运行 10000 次模拟 / 关闭结果面板
    -- Shift+I   → 运行 100000 次（高精度，稍慢）
    -- ↑↓        → 结果面板滚动
    if key == KEY_I then
        if fishSim.running then
            fishSim.running = false   -- 再按一次关闭
        else
            local n = input:GetKeyDown(KEY_LSHIFT) and 100000 or 10000
            RunFishSimulation(n)
        end
        return
    end
    if fishSim.running then
        if key == KEY_UP then
            fishSim.scroll = math.max(0, fishSim.scroll - 1); return
        elseif key == KEY_DOWN then
            local maxScroll = fishSim.results and math.max(0, #fishSim.results - 20) or 0
            fishSim.scroll = math.min(maxScroll, fishSim.scroll + 1); return
        end
    end

    -- T 键: 鱼类图册开关（调试用）
    if key == KEY_T then
        fishAtlasOpen = not fishAtlasOpen
        if fishAtlasOpen then
            FishAtlas.Open(FISH_TYPES, imgFishSheets[1], imgFishSheets[2], imgFishSheets[3], imgFishSheets[4])
        else
            FishAtlas.Close()
        end
        return
    end

    -- Y 键: UI 选择器（1=对话框，2=UI面板2，...）
    if key == KEY_Y then
        -- 如果有面板已打开，先让选择器处理；否则切换选择器
        if UISelector.IsOpen() then
            UISelector.HandleKey(key)
        else
            UISelector.Toggle()
        end
        return
    end

    -- UI 选择器打开时拦截输入
    if UISelector.IsOpen() then
        UISelector.HandleKey(key)
        return
    end

    -- UIPanel2 打开时拦截输入
    if UIPanel2.IsOpen() then
        UIPanel2.HandleKey(key)
        return
    end

    -- 图册打开时拦截所有按键
    if fishAtlasOpen then
        FishAtlas.HandleKey(key)
        if not FishAtlas.IsOpen() then fishAtlasOpen = false end
        return
    end

    -- B 键: 背包开关（同时关闭岛屿菜单和鱼铺面板）
    if key == KEY_B then
        if islandMenuOpen then
            islandMenuOpen = false
            dockedIsland = nil
            IslandMenu.Reset()
        end
        if questPanelOpen then
            questPanelOpen = false
        end
        inventoryOpen = not inventoryOpen
        if not inventoryOpen then Inventory.Reset() end
        return
    end

    -- 背包打开时拦截按键
    if inventoryOpen then
        if key == KEY_ESCAPE then
            inventoryOpen = false
            Inventory.Reset()
        else
            Inventory.HandleKey(key)
        end
        return
    end

    -- 仓库打开时拦截按键
    if warehouseOpen then
        if key == KEY_ESCAPE then
            warehouseOpen = false
            if dockedIsland then
                islandMenuOpen = true
                IslandMenu.Reset(dockedIsland)
            end
        else
            Warehouse.HandleKey(key)
        end
        return
    end

    -- 船只升级打开时拦截按键
    if boatUpgradeOpen then
        if key == KEY_ESCAPE then
            boatUpgradeOpen = false
            if dockedIsland then
                islandMenuOpen = true
                IslandMenu.Reset(dockedIsland)
            end
        end
        return
    end

    -- 船舱打开时拦截按键
    if cabinOpen then
        if key == KEY_ESCAPE or key == KEY_O then
            cabinOpen = false
            CabinSystem.Close()
        end
        return
    end

    -- 鱼竿升级坊打开时拦截按键
    if rodShopOpen then
        if key == KEY_ESCAPE or key == KEY_E or key == KEY_Q then
            rodShopOpen = false
            if dockedIsland then
                islandMenuOpen = true
                IslandMenu.Reset(dockedIsland)
            end
        end
        return
    end

    -- 鱼钩选择器打开时拦截按键
    if hookSelectorOpen then
        if key == KEY_ESCAPE or key == KEY_J then
            hookSelectorOpen = false
            HookSelector.Close()
        end
        return
    end

    -- 鱼饵选择器打开时拦截按键
    if baitSelectorOpen then
        if key == KEY_ESCAPE or key == KEY_K then
            baitSelectorOpen = false
            BaitSelector.Close()
        end
        return
    end

    -- 鱼铺面板打开时拦截按键
    if questPanelOpen then
        local consumed, result = QuestPanel.HandleKey(key, {
            quests      = QuestSystem.GenerateQuests(dockedIsland and dockedIsland.id or "?", FISH_TYPES),
            QuestSystem = QuestSystem,
            caughtList  = caughtList,
            PlayerData  = PlayerData,
        })
        if result and result.close then
            questPanelOpen = false
            -- 关闭后重新打开岛屿菜单
            if dockedIsland then
                islandMenuOpen = true
                IslandMenu.Reset(dockedIsland)
            end
        elseif result and result.submitted ~= nil then
            -- 重新计算背包总重
            totalWeight = 0
            for _, f in ipairs(caughtList) do totalWeight = totalWeight + f.weight end
            if result.submitted then
                ShowNotify(result.message or "任务完成！获得 " .. (result.income or 0) .. " 💰", 100, 230, 120)
            else
                ShowNotify(result.message or "背包鱼不足", 240, 100, 80)
            end
        end
        return
    end

    -- 岛屿菜单打开时拦截按键
    if islandMenuOpen then
        if key == KEY_ESCAPE or key == KEY_E then
            islandMenuOpen = false
            dockedIsland = nil
            IslandMenu.Reset()
        elseif key == KEY_Q then
            -- Q 键: 打开鱼铺面板
            islandMenuOpen = false
            questPanelOpen = true
            QuestSystem.GenerateQuests(dockedIsland.id, FISH_TYPES)
            QuestPanel.Reset()
        else
            local consumed, result = IslandMenu.HandleKey(key, {
                island = dockedIsland,
            })
            if result and result.close then
                islandMenuOpen = false
                dockedIsland = nil
                IslandMenu.Reset()
            elseif result and result.openQuest then
                islandMenuOpen = false
                questPanelOpen = true
                QuestSystem.GenerateQuests(dockedIsland.id, FISH_TYPES)
                QuestPanel.Reset()
            end

        end
        return
    end

    -- J 键: 鱼钩选择界面开关
    if key == KEY_J then
        hookSelectorOpen = not hookSelectorOpen
        if hookSelectorOpen then
            HookSelector.Open()
        else
            HookSelector.Close()
        end
        return
    end

    -- K 键: 鱼饵选择界面开关
    if key == KEY_K then
        baitSelectorOpen = not baitSelectorOpen
        if baitSelectorOpen then
            BaitSelector.Open()
        else
            BaitSelector.Close()
        end
        return
    end


    -- O 键: 船舱开关
    if key == KEY_O then
        cabinOpen = not cabinOpen
        if cabinOpen then
            CabinSystem.Open()
        else
            CabinSystem.Close()
        end
        return
    end

    -- M 键: 航海图开关
    if key == KEY_M then
        mapOpen = not mapOpen
        return
    end

    -- 航海图打开时拦截按键
    if mapOpen then
        if key == KEY_ESCAPE then
            mapOpen = false
        end
        return
    end

    -- E 键: 岛屿停靠 (优先) 或拾取漂浮木板
    if key == KEY_E and STATE == "sailing" then
        local nearIsland = FindNearestIsland()
        if nearIsland then
            islandMenuOpen = true
            dockedIsland = nearIsland
            IslandMenu.Reset(nearIsland)
            boat.speed = 0
            boat.cruise = false
            return
        end

        local idx = FindNearestPlank()
        if idx then
            local plank = floatingPlanks[idx]
            local amount = plank.woodAmount
            PlayerData.AddResource("wood", amount)
            ShowNotify("拾取木料 +" .. amount, 210, 175, 110)
            table.remove(floatingPlanks, idx)
            table.insert(floatingPlanks, SpawnPlank(boat))
        end
    end

    if key == KEY_SPACE then
        HandleAction()
    end

    -- G 键: 开发者鱼种选择菜单
    if key == KEY_G and STATE == "sailing" then
        devFishSelect = not devFishSelect
        if devFishSelect then
            ShowNotify(string.format("[DEV] 选择鱼种 (1-%d) | G/ESC取消", #FISH_TYPES), 255, 150, 255)
        end
    end

    -- 开发者鱼种选择: 数字键缓冲输入 (支持两位数序号), Enter 或超时确认
    if devFishSelect and STATE == "sailing" then
        local digitMap = {
            [KEY_0]="0",[KEY_1]="1",[KEY_2]="2",[KEY_3]="3",[KEY_4]="4",
            [KEY_5]="5",[KEY_6]="6",[KEY_7]="7",[KEY_8]="8",[KEY_9]="9",
        }
        local digit = digitMap[key]
        if digit then
            devFishInput = devFishInput .. digit
            devFishInputTimer = 1.2   -- 1.2秒无操作后自动确认
            -- 超过两位就立即截断并确认
            if #devFishInput >= 2 then
                local idx = tonumber(devFishInput)
                devFishInput = ""
                devFishInputTimer = 0
                if idx and idx >= 1 and idx <= #FISH_TYPES then
                    devFishSelect = false
                    local rod = rods[activeRod]
                    if rod.state == "idle" then
                        rod.state = "trolling"; rod.timer = 0; rod.biteAt = 999; InitRope(activeRod)
                    end
                    rod.state = "trolling"
                    local ft = FISH_TYPES[idx]
                    StartFight({ type = ft, weight = SampleFishWeight(ft) })
                    ShowNotify("[DEV] 选择: " .. ft.name .. " (★" .. ft.diff .. ")", 255, 150, 255)
                end
            else
                ShowNotify(string.format("[DEV] 输入: %s  (再输一位或等待确认)", devFishInput), 255, 200, 100)
            end
            return
        end
        -- Enter/Return: 立即确认当前输入
        if key == KEY_RETURN and devFishInput ~= "" then
            local idx = tonumber(devFishInput)
            devFishInput = ""; devFishInputTimer = 0
            if idx and idx >= 1 and idx <= #FISH_TYPES then
                devFishSelect = false
                local rod = rods[activeRod]
                if rod.state == "idle" then
                    rod.state = "trolling"; rod.timer = 0; rod.biteAt = 999; InitRope(activeRod)
                end
                rod.state = "trolling"
                local ft = FISH_TYPES[idx]
                StartFight({ type = ft, weight = SampleFishWeight(ft) })
                ShowNotify("[DEV] 选择: " .. ft.name .. " (★" .. ft.diff .. ")", 255, 150, 255)
            end
            return
        end
    end

    -- N 键: 开发者批量钓鱼（直接入包10条指定鱼种，跳过溜鱼）
    if key == KEY_N and STATE == "sailing" then
        devBatch.active = not devBatch.active
        devBatch.input = ""
        devBatch.timer = 0
        if devBatch.active then
            ShowNotify(string.format("[DEV] 批量入包 (输入鱼种1-%d) | N/ESC取消", #FISH_TYPES), 255, 200, 100)
        end
    end

    if devBatch.active and STATE == "sailing" then
        local digitMap = {
            [KEY_0]="0",[KEY_1]="1",[KEY_2]="2",[KEY_3]="3",[KEY_4]="4",
            [KEY_5]="5",[KEY_6]="6",[KEY_7]="7",[KEY_8]="8",[KEY_9]="9",
        }
        local digit = digitMap[key]
        if digit then
            devBatch.input = devBatch.input .. digit
            devBatch.timer = 1.2
            if #devBatch.input >= 2 then
                local idx = tonumber(devBatch.input)
                devBatch.input = ""; devBatch.timer = 0
                if idx and idx >= 1 and idx <= #FISH_TYPES then
                    devBatch.active = false
                    local ft = FISH_TYPES[idx]
                    local added = 0
                    for _ = 1, 10 do
                        if #caughtList >= CFG.BAG_SIZE then break end
                        local w = SampleFishWeight(ft)
                        caughtList[#caughtList + 1] = { type = ft, weight = w }
                        totalWeight = totalWeight + w
                        added = added + 1
                    end
                    ShowNotify(string.format("[DEV] 批量入包: %s ×%d", ft.name, added), 100, 255, 200)
                end
            else
                ShowNotify(string.format("[DEV] 批量输入: %s  (再输一位或Enter确认)", devBatch.input), 255, 200, 100)
            end
            return
        end
        if key == KEY_RETURN and devBatch.input ~= "" then
            local idx = tonumber(devBatch.input)
            devBatch.input = ""; devBatch.timer = 0
            if idx and idx >= 1 and idx <= #FISH_TYPES then
                devBatch.active = false
                local ft = FISH_TYPES[idx]
                local added = 0
                for _ = 1, 10 do
                    if #caughtList >= CFG.BAG_SIZE then break end
                    local w = SampleFishWeight(ft)
                    caughtList[#caughtList + 1] = { type = ft, weight = w }
                    totalWeight = totalWeight + w
                    added = added + 1
                end
                ShowNotify(string.format("[DEV] 批量入包: %s ×%d", ft.name, added), 100, 255, 200)
            end
            return
        end
        if key == KEY_ESCAPE then
            devBatch.active = false
            devBatch.input = ""; devBatch.timer = 0
            return
        end
    end

    -- H 键: 实时波形图开关 (遛鱼中)
    -- Tab 键: 展开/折叠遛鱼详情面板
    if key == KEY_TAB and STATE == "fight" then
        fightDetailOpen = not fightDetailOpen
    end

    if key == KEY_H and STATE == "fight" then
        diagChartOn = not diagChartOn
        if diagChartOn then
            ShowNotify("[DIAG] 波形图 ON", 100, 255, 200)
        else
            ShowNotify("[DIAG] 波形图 OFF", 180, 180, 180)
        end
    end

    -- L 键: 无限线长模式 (遛鱼中)
    if key == KEY_L and STATE == "fight" then
        diagInfiniteLine = not diagInfiniteLine
        if diagInfiniteLine then
            ShowNotify("[DIAG] 无限线长 ON - 不会清杯", 255, 220, 100)
        else
            ShowNotify("[DIAG] 无限线长 OFF", 180, 180, 180)
        end
    end

    -- F 键切换巡航
    if key == KEY_F and STATE == "sailing" then
        boat.cruise = not boat.cruise
        if boat.cruise then
            ShowNotify("巡航开启 - 按S或再按F关闭", 100, 220, 255)
        else
            ShowNotify("巡航关闭", 180, 180, 180)
        end
    end

    -- 数字键 1/2 切换鱼竿
    if key == KEY_1 and STATE == "sailing" then
        activeRod = 1
        ShowNotify("切换到鱼竿 1", 200, 220, 255)
    end
    if key == KEY_2 and STATE == "sailing" then
        activeRod = 2
        ShowNotify("切换到鱼竿 2", 200, 220, 255)
    end

    -- Q / R 键: 切换竿型 (非遛鱼状态均可切换；遛鱼中已快照竿型，无需禁止拖钓时切换)
    if STATE == "sailing" then
        if key == KEY_Q then
            equippedRodId = equippedRodId - 1
            if equippedRodId < 1 then equippedRodId = #ROD_TYPES end
            local rt = ROD_TYPES[equippedRodId]
            ShowNotify("竿型: " .. rt.name .. " (" .. rt.desc .. ")", 200, 220, 180)
        elseif key == KEY_R then
            equippedRodId = equippedRodId + 1
            if equippedRodId > #ROD_TYPES then equippedRodId = 1 end
            local rt = ROD_TYPES[equippedRodId]
            ShowNotify("竿型: " .. rt.name .. " (" .. rt.desc .. ")", 200, 220, 180)
        end
    end

    -- 6 / 7 键: 切换渔线轮
    if STATE == "sailing" then
        if key == KEY_6 then
            equippedReelId = equippedReelId - 1
            if equippedReelId < 1 then equippedReelId = #REEL_TYPES end
            local rl = REEL_TYPES[equippedReelId]
            ShowNotify("渔线轮: " .. rl.name .. "  刹车" .. rl.maxDragForce .. "kg  线容" .. rl.lineCapacity .. "m", 180, 220, 200)
        elseif key == KEY_7 then
            equippedReelId = equippedReelId + 1
            if equippedReelId > #REEL_TYPES then equippedReelId = 1 end
            local rl = REEL_TYPES[equippedReelId]
            ShowNotify("渔线轮: " .. rl.name .. "  刹车" .. rl.maxDragForce .. "kg  线容" .. rl.lineCapacity .. "m", 180, 220, 200)
        end
    end

    if key == KEY_ESCAPE then
        if devFishSelect then
            devFishSelect = false
            devFishInput = ""; devFishInputTimer = 0
        elseif STATE ~= "menu" then
            STATE = "menu"
        end
    end
end

-- 移动端工具条按钮响应（等效对应的键盘快捷键）
function HandleMobileBtn(id)
    if id == "bag" then
        -- B 键：背包开关
        if islandMenuOpen then islandMenuOpen = false; dockedIsland = nil; IslandMenu.Reset() end
        if questPanelOpen  then questPanelOpen  = false end
        inventoryOpen = not inventoryOpen
        if not inventoryOpen then Inventory.Reset() end

    elseif id == "map" then
        -- M 键：航海图开关
        mapOpen = not mapOpen

    elseif id == "atlas" then
        -- T 键：鱼类图册开关
        fishAtlasOpen = not fishAtlasOpen
        if fishAtlasOpen then
            FishAtlas.Open(FISH_TYPES, imgFishSheets[1], imgFishSheets[2], imgFishSheets[3], imgFishSheets[4])
        else
            FishAtlas.Close()
        end

    elseif id == "pause" then
        -- ESC：返回主菜单
        if STATE ~= "menu" then STATE = "menu" end

    elseif id == "detail" then
        -- Tab：遛鱼详情面板开关
        fightDetailOpen = not fightDetailOpen

    elseif id == "cruise" then
        -- F 键：巡航切换
        if STATE == "sailing" then
            boat.cruise = not boat.cruise
            if boat.cruise then
                ShowNotify("巡航开启 - 按S或点击关闭", 100, 220, 255)
            else
                ShowNotify("巡航关闭", 180, 180, 180)
            end
        end

    elseif id == "rod1" then
        activeRod = 1; ShowNotify("切换到鱼竿 1", 200, 220, 255)
    elseif id == "rod2" then
        activeRod = 2; ShowNotify("切换到鱼竿 2", 200, 220, 255)

    elseif id == "rodtype_prev" then
        -- Q 键：竿型向前
        if STATE == "sailing" then
            equippedRodId = equippedRodId - 1
            if equippedRodId < 1 then equippedRodId = #ROD_TYPES end
            local rt = ROD_TYPES[equippedRodId]
            ShowNotify("竿型: " .. rt.name .. " (" .. rt.desc .. ")", 200, 220, 180)
        end
    elseif id == "rodtype_next" then
        -- R 键：竿型向后
        if STATE == "sailing" then
            equippedRodId = equippedRodId + 1
            if equippedRodId > #ROD_TYPES then equippedRodId = 1 end
            local rt = ROD_TYPES[equippedRodId]
            ShowNotify("竿型: " .. rt.name .. " (" .. rt.desc .. ")", 200, 220, 180)
        end

    elseif id == "reeltype_prev" then
        -- 6 键：渔线轮向前
        if STATE == "sailing" then
            equippedReelId = equippedReelId - 1
            if equippedReelId < 1 then equippedReelId = #REEL_TYPES end
            local rl = REEL_TYPES[equippedReelId]
            ShowNotify("渔线轮: " .. rl.name .. "  刹车" .. rl.maxDragForce .. "kg  线容" .. rl.lineCapacity .. "m", 180, 220, 200)
        end
    elseif id == "reeltype_next" then
        -- 7 键：渔线轮向后
        if STATE == "sailing" then
            equippedReelId = equippedReelId + 1
            if equippedReelId > #REEL_TYPES then equippedReelId = 1 end
            local rl = REEL_TYPES[equippedReelId]
            ShowNotify("渔线轮: " .. rl.name .. "  刹车" .. rl.maxDragForce .. "kg  线容" .. rl.lineCapacity .. "m", 180, 220, 200)
        end
    end
end

function HandleAction()
    if STATE == "menu" then
        -- 开始游戏
        STATE = "sailing"
        boat.x = 0
        boat.y = 0
        boat.angle = 0
        boat.speed = 0
        boat.cruise = false
        camX = 0
        camY = 0
        caughtList = {}
        totalWeight = 0
        wakeParticles = {}
        activeRod = 1
        for i = 1, CFG.ROD_COUNT do
            rods[i].state = "idle"
            rods[i].timer = 0
            rods[i].biteAt = 0
            rods[i].biteTimer = 0
            rods[i].rope = {}
        end
        InitLandmarks()
        InitFishShadows()
        if IS_MOBILE then
            ShowNotify("摇杆开船 | 工具条巡航/抛竿/切竿", 200, 220, 255)
        else
            ShowNotify("WASD开船 | F巡航 | 按住左键蓄力抛竿 | 1/2切竿", 200, 220, 255)
        end

    elseif STATE == "sailing" then
        local rod = rods[activeRod]

        if rod.state == "idle" then
            -- 提示用鼠标蓄力抛竿
            ShowNotify("按住左键蓄力, 瞄准方向松开抛竿!", 255, 220, 100)
        elseif rod.state == "casting" then
            -- 飞行中不做操作
        elseif rod.state == "strike" then
            -- 抬杆动画中不做操作
        elseif rod.state == "trolling" then
            -- 收线
            rod.state = "idle"
            rod.timer = 0
            rod.rope = {}
            ShowNotify("鱼竿" .. activeRod .. " 收线了", 200, 200, 200)
        elseif rod.state == "bite" then
            -- 有鱼咬钩, 直接进入遛鱼
            rod.state = "trolling"  -- 保持线在水中
            rod.timer = 0
            local fish = PickRandomFish()
            StartFight(fish)
        end

    elseif STATE == "fight" then
        -- 遛鱼时空格/动作键=收线, 由 UpdateFight 持续检测
        -- 此处不做额外处理

    elseif STATE == "catch" then
        UIPanel2.Close()   -- Close() 内部回调会重置 STATE = "sailing"
    elseif STATE == "fail" then
        STATE = "sailing"  -- DrawFailResult 是纯 NanoVG 面板，直接重置状态
    end
end

-- ============================================================================
-- 渲染
-- ============================================================================

function HandleRender(eventType, eventData)
    if not vg then return end

    screenW = graphics:GetWidth()
    screenH = graphics:GetHeight()

    -- 每帧重置 HUD 工具条热区（DrawHUD + DrawMobileToolbar 会重新填充）
    hudBtns_ = {}

    nvgBeginFrame(vg, screenW, screenH, 1.0)
    UICanvas.Update(screenW, screenH)

    -- ── 世界空间层 (统一缩放, 以屏幕中心为锚点) ──
    nvgSave(vg)
    nvgTranslate(vg, screenW / 2, screenH / 2)
    nvgScale(vg, camScale, camScale)
    nvgTranslate(vg, -screenW / 2, -screenH / 2)

    -- 1. 水面
    DrawWater()

    -- 1.2 水下礁石（岛屿10 周围，绘于水面之上、海浪之下）
    DrawAllIslandRocks()

    -- 1.5 海浪精灵 (水面上层, 地标下层)
    DrawWaveSprites()

    -- 2. 世界物体 (尾流、鱼影、木板、停靠提示、上钩鱼影)
    DrawWorldObjects()

    -- 2.5 岛屿底层 (浅水光晕 + 浮沫 + 岛屿底图) → 在船之下
    IslandSystem.DrawBelow(vg, WorldToScreen, screenW, screenH, gameTime)

    -- 3. 船
    DrawBoat()

    -- 3.5 岛屿上层 (石头/宝箱/植物/建筑) → 在船之上
    IslandSystem.DrawAbove(vg, WorldToScreen, screenW, screenH, gameTime)

    -- 3.6 NPC 头像气泡 (靠近岛屿时显示)
    DrawNpcAvatars()

    -- 4. 钓鱼线 (每根活跃的鱼竿)
    for i = 1, CFG.ROD_COUNT do
        if rods[i].state ~= "idle" then
            DrawFishingLine(i)
        end
    end

    -- 5. 抬杆水花特效 (世界空间)
    if strikeState.active then
        DrawStrikeSplash()
    end

    -- 6. 蓄力抛竿方向指示 (世界空间)
    if castState.charging and STATE == "sailing" then
        DrawCastAim()
    end

    nvgRestore(vg)
    -- ── 屏幕空间层 (不缩放, UI/HUD/菜单) ──

    -- 0. 天空叠加层（昼夜色调，在所有 UI 之下）
    if STATE ~= "menu" then
        DrawSkyOverlay()
        DrawRainEffect()
    end

    -- 0.3 全局绿光叠层（相减渐变，独立于时间系统）
    DrawGlobalGreenFilter()

    -- 0.35 全局暖黄光照（加法渐变，左亮右暗）
    DrawGlobalWarmLight()

    -- 0.4 灯光（夜晚渐亮）
    LightEditor.DrawLights(vg, boat, IslandSystem.GetIslands(), camScale,
        WorldToScreen, TimeWeather.GetNightIntensity())

    -- 0.45 灯光编辑器覆盖层（L 键开关）
    LightEditor.DrawEditor(vg, screenW, screenH)

    -- 4.5 岛屿停靠提示 UI（屏幕空间，在岛屿绘制之上）
    if not AnyUIOpen() and STATE == "sailing" then
        local nearIsland = FindNearestIsland()
        if nearIsland then
            local panelW = 200
            local panelH = 56
            local panelX = (screenW - panelW) / 2
            local panelY = screenH * 0.72
            local cornerR = 10
            local pulse = 0.7 + 0.3 * math.sin(gameTime * 3)

            -- 面板背景
            nvgBeginPath(vg)
            nvgRoundedRect(vg, panelX, panelY, panelW, panelH, cornerR)
            nvgFillColor(vg, nvgRGBA(15, 20, 35, 190))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(120, 180, 255, math.floor(120 * pulse)))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)

            local cx = panelX + panelW / 2
            local keySize = 20

            -- 岛屿名称
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 14)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(180, 200, 230, 200))
            nvgText(vg, cx, panelY + 15, nearIsland.name or "未知岛屿", nil)

            -- 按键图标 [E] + 提示文字
            local keyY = panelY + 38
            local keyX = cx - 30

            nvgBeginPath(vg)
            nvgRoundedRect(vg, keyX - keySize/2, keyY - keySize/2, keySize, keySize, 4)
            nvgFillColor(vg, nvgRGBA(60, 80, 120, math.floor(220 * pulse)))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(160, 200, 255, math.floor(200 * pulse)))
            nvgStrokeWidth(vg, 1.2)
            nvgStroke(vg)

            nvgFontSize(vg, 13)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(230, 240, 255, math.floor(255 * pulse)))
            nvgText(vg, keyX, keyY, "E", nil)

            nvgFontSize(vg, 14)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(220, 230, 245, math.floor(220 * pulse)))
            nvgText(vg, keyX + keySize/2 + 8, keyY, "停靠", nil)
        end
    end

    -- 5. UI 层
    if STATE == "menu" then
        DrawMenu()
    elseif STATE == "fight" then
        DrawFight()
    elseif STATE == "catch" then
        -- DrawCatchResult() 已由 UIPanel2 替代
    elseif STATE == "fail" then
        DrawFailResult()
    end

    -- 5.5. 小地图（所有岛屿 UI 之下）
    DrawMinimap()

    -- 6. HUD
    if STATE ~= "menu" then
        DrawHUD()
    end

    -- 6b. 蓄力力度条 (屏幕空间)
    if castState.charging and STATE == "sailing" then
        DrawCastPowerBar()
    end

    -- 7. 开发者鱼种选择菜单
    DrawDevFishSelect()

    -- 8. 通知
    DrawNotification()

    -- 9. 虚拟控件（sailing + fight 都需要）
    if STATE == "sailing" or STATE == "fight" then
        DrawVirtualControls()
    end

    -- 9.5 移动端工具条（在虚拟控件之上，附加 HUD 工具条热区）
    DrawMobileToolbar()

    -- 10. 海域分区切换通知
    if zoneNotify.timer > 0 and zoneNotify.alpha > 0 then
        nvgSave(vg)
        local a = zoneNotify.alpha
        -- 进入动画：从上方滑入
        local slideIn = math.min(1.0, (3.0 - zoneNotify.timer) * 4)  -- 0.25s 滑入
        local yOff = (1 - slideIn) * (-30)
        local cy = screenH * 0.22 + yOff

        -- 背景条
        nvgBeginPath(vg)
        local barW = 200
        nvgRoundedRect(vg, (screenW - barW) * 0.5, cy - 16, barW, 32, 4)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(a * 0.4)))
        nvgFill(vg)

        -- 区域名称
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 18)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(220, 235, 255, a))
        nvgText(vg, screenW * 0.5, cy, zoneNotify.text, nil)
        nvgRestore(vg)
    end

    -- 11.1. 商店
    if rodShopOpen then
        RodShop.Draw(vg, screenW, screenH, {
            PlayerData    = PlayerData,
            rodTypes      = ROD_TYPES,
            equippedRodId = equippedRodId,
            caughtList    = caughtList,
            fishSheet     = imgFishSheets[1],
            fishSheet2    = imgFishSheets[2],
            fishSheet3    = imgFishSheets[3],
            fishSheet4    = imgFishSheets[4],
        })
        RodShop.DrawBackButton(vg, screenW, screenH)
    end

    -- 11.1b. 仓库
    if warehouseOpen then
        Warehouse.Draw(vg, screenW, screenH, {
            PlayerData = PlayerData,
            caughtList = caughtList,
            fishSheet  = imgFishSheets[1],
            fishSheet2 = imgFishSheets[2],
            fishSheet3 = imgFishSheets[3],
            fishSheet4 = imgFishSheets[4],
        })
    end

    -- 11.1c. 船只升级
    if boatUpgradeOpen then
        BoatUpgrade.Draw(vg, screenW, screenH, {
            PlayerData = PlayerData,
        })
    end

    -- 11.1d. 船舱装备
    if cabinOpen then
        CabinSystem.Draw(vg, screenW, screenH, {
            PlayerData = PlayerData,
        })
    end

    -- 11.2. 时间调试滑条（已隐藏）
    -- DrawTimeSlider()

    -- 11.5. 对话框（覆盖在 HUD 上方，地图打开时被遮挡）
    DrawDialogue()

    -- 11.6. UI 面板 2（9 切片测试面板）
    UIPanel2.Draw(vg, screenW, screenH)

    -- 11.7. UI 选择器（Y 键呼出）
    UISelector.Draw(vg, screenW, screenH,
        input.mousePosition.x, input.mousePosition.y)

    -- 12. 航海图（最顶层覆盖）
    DrawMap()

    -- 13. 启动封面（最顶层，遮挡加载过程）
    if splash.active then
        local a = splash.alpha
        local ai = math.floor(a * 255)

        -- 全屏渐变背景（深海蓝）
        local bgGrad = nvgLinearGradient(vg, 0, 0, 0, screenH,
            nvgRGBA(8, 18, 38, ai),
            nvgRGBA(12, 35, 65, ai))
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, screenW, screenH)
        nvgFillPaint(vg, bgGrad)
        nvgFill(vg)

        -- 水面波光装饰线
        for i = 1, 5 do
            local wy = screenH * (0.55 + i * 0.06)
            local waveOff = math.sin(gameTime * 0.5 + i * 1.3) * 20
            nvgBeginPath(vg)
            nvgMoveTo(vg, -10, wy + waveOff)
            for wx = 0, screenW, 30 do
                local wvy = wy + math.sin(wx * 0.015 + gameTime * 0.8 + i) * (8 + i * 2) + waveOff
                nvgLineTo(vg, wx, wvy)
            end
            nvgStrokeColor(vg, nvgRGBA(80, 160, 220, math.floor(ai * (0.08 - i * 0.012))))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)
        end

        -- 标题
        nvgFontFace(vg, "sans")
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

        -- 标题阴影
        nvgFontSize(vg, 42)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(ai * 0.5)))
        nvgText(vg, screenW / 2 + 2, screenH * 0.38 + 2, "海上钓鱼", nil)

        -- 标题前景
        local titleGlow = 0.85 + 0.15 * math.sin(gameTime * 2.0)
        nvgFillColor(vg, nvgRGBA(200, 230, 255, math.floor(ai * titleGlow)))
        nvgText(vg, screenW / 2, screenH * 0.38, "海上钓鱼", nil)

        -- 副标题
        nvgFontSize(vg, 16)
        nvgFillColor(vg, nvgRGBA(140, 180, 210, math.floor(ai * 0.7)))
        nvgText(vg, screenW / 2, screenH * 0.46, "驾船出海  拖钓冒险", nil)

        -- 加载提示（带动画省略号）
        if not splash.fadeOut then
            local dots = string.rep(".", math.floor(splash.dotTimer % 4))
            nvgFontSize(vg, 14)
            nvgFillColor(vg, nvgRGBA(160, 200, 230, math.floor(ai * (0.5 + 0.3 * math.sin(gameTime * 3)))))
            nvgText(vg, screenW / 2, screenH * 0.62, "加载中" .. dots, nil)
        end
    end

    -- ── 垂钓模拟器结果面板 ──────────────────────────────────────────────────
    if fishSim.running and fishSim.results then
        local pw, ph = 520, math.min(600, screenH - 60)
        local px, py = (screenW - pw) / 2, (screenH - ph) / 2

        -- 半透明背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, px, py, pw, ph, 10)
        nvgFillColor(vg, nvgRGBA(10, 20, 35, 220))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(80, 160, 220, 200))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)

        nvgFontFace(vg, "sans")
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)

        -- 标题
        local ty = py + 12
        nvgFontSize(vg, 14)
        nvgFillColor(vg, nvgRGBA(100, 200, 255, 255))
        nvgText(vg, px + 14, ty, "垂钓模拟器  [I关闭  ↑↓滚动]", nil)
        ty = ty + 20

        -- 条件摘要
        nvgFontSize(vg, 12)
        nvgFillColor(vg, nvgRGBA(180, 220, 180, 220))
        nvgText(vg, px + 14, ty, fishSim.condStr, nil)
        ty = ty + 18

        -- 分割线
        nvgBeginPath(vg)
        nvgMoveTo(vg, px + 10, ty); nvgLineTo(vg, px + pw - 10, ty)
        nvgStrokeColor(vg, nvgRGBA(80, 120, 160, 150)); nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
        ty = ty + 8

        -- 表头
        nvgFontSize(vg, 12)
        nvgFillColor(vg, nvgRGBA(150, 190, 230, 200))
        nvgText(vg, px + 14,        ty, "鱼名", nil)
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
        nvgText(vg, px + pw - 100,  ty, "次数", nil)
        nvgText(vg, px + pw - 14,   ty, "占比%", nil)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        ty = ty + 18

        -- 数据行（可滚动，每页最多显示 20 行）
        local lineH    = 18
        local maxRows  = math.floor((py + ph - ty - 10) / lineH)
        local startIdx = fishSim.scroll + 1
        local endIdx   = math.min(#fishSim.results, startIdx + maxRows - 1)

        for i = startIdx, endIdx do
            local e = fishSim.results[i]
            -- 交替背景
            if (i % 2) == 0 then
                nvgBeginPath(vg)
                nvgRect(vg, px + 6, ty - 2, pw - 12, lineH)
                nvgFillColor(vg, nvgRGBA(255, 255, 255, 12))
                nvgFill(vg)
            end
            -- 占比色条
            local barW = (e.pct / 100) * (pw - 160)
            nvgBeginPath(vg)
            nvgRect(vg, px + 130, ty, barW, lineH - 4)
            nvgFillColor(vg, nvgRGBA(60, 140, 200, 60))
            nvgFill(vg)
            -- 文字
            nvgFontSize(vg, 12)
            nvgFillColor(vg, nvgRGBA(220, 235, 250, 230))
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            nvgText(vg, px + 14, ty, e.name, nil)
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(200, 220, 240, 200))
            nvgText(vg, px + pw - 100, ty, tostring(e.count), nil)
            nvgFillColor(vg, nvgRGBA(100, 220, 140, 220))
            nvgText(vg, px + pw - 14,  ty, string.format("%.3f%%", e.pct), nil)
            ty = ty + lineH
        end

        -- 滚动提示
        if #fishSim.results > maxRows then
            nvgFontSize(vg, 11)
            nvgFillColor(vg, nvgRGBA(120, 160, 200, 160))
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
            nvgText(vg, px + pw / 2, py + ph - 6,
                string.format("%d/%d  ↑↓滚动", endIdx, #fishSim.results), nil)
        end
    end

    -- ── 竿线调试面板 ──
    do
        -- 右上角按钮
        local bw, bh = 72, 22
        local bx = screenW - bw - 6
        local by = 6
        local btnAlpha = rodDebugMode and 220 or 130
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx, by, bw, bh, 4)
        nvgFillColor(vg, rodDebugMode and nvgRGBA(220, 80, 60, btnAlpha) or nvgRGBA(30, 30, 50, btnAlpha))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(200, 200, 220, 160))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
        nvgFontSize(vg, 12)
        nvgFillColor(vg, nvgRGBA(240, 240, 240, 230))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgText(vg, bx + bw / 2, by + bh / 2, rodDebugMode and "● 竿线调试" or "○ 竿线调试", nil)

        -- 调试信息面板（左上角）
        if rodDebugMode then
            local r1, r2   = rods[1], rods[2]
            local rod      = rods[activeRod]
            local lines = {
                string.format("STATE: %s   activeRod: %d", STATE, activeRod),
                string.format("rod1  st=%-10s aim=%6.1f°  rope=%d", r1.state, math.deg(r1.aimAngle), #r1.rope),
                string.format("rod2  st=%-10s aim=%6.1f°  rope=%d", r2.state, math.deg(r2.aimAngle), #r2.rope),
                string.format("cast  chg=%-5s pwr=%.2f liftT=%.2f",
                    tostring(castState.charging), castState.power, castState.liftT),
                string.format("fly   flyT=%.2f  flyDur=%.2f",
                    rod.flyT or 0, rod.flyDuration or 0),
            }
            if STATE == "fight" then
                lines[#lines+1] = string.format(
                    "fight liftT=%.2f  ten=%.1fkg  r=%.1fm  len=%.1fm",
                    fight.liftT or 0, fight.tension, fight.fishRadius, fight.lineLength)
            end
            if rod.rope and #rod.rope >= 2 then
                local h, t = rod.rope[1], rod.rope[#rod.rope]
                lines[#lines+1] = string.format(
                    "rope  n=%d  head=(%.0f,%.0f)  tail=(%.0f,%.0f)",
                    #rod.rope, h.x, h.y, t.x, t.y)
            end

            local pw = 340
            local ph = #lines * 16 + 12
            local px, py = 6, 6
            nvgBeginPath(vg)
            nvgRoundedRect(vg, px, py, pw, ph, 5)
            nvgFillColor(vg, nvgRGBA(10, 10, 20, 200))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(220, 80, 60, 180))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)

            nvgFontSize(vg, 12)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            for i, line in ipairs(lines) do
                local iy = py + 6 + (i - 1) * 16
                -- 行号标签
                nvgFillColor(vg, nvgRGBA(220, 80, 60, 180))
                nvgText(vg, px + 6, iy, tostring(i), nil)
                -- 内容
                nvgFillColor(vg, nvgRGBA(200, 230, 200, 230))
                nvgText(vg, px + 22, iy, line, nil)
            end
        end
    end

    nvgEndFrame(vg)
end

-- ============================================================================
-- 全岛屿 水下低多边形礁石（程序化生成，基于伪随机偏移）
-- ============================================================================
-- 每个岛屿定义若干"礁石团"，每团在岛屿中心周围随机散开
-- 使用基于 seed 的确定性伪随机，确保每次渲染一致

local _ISLAND_DEFS = {
    -- id, cx, cy, hw, hh  (岛屿中心世界坐标, 显示半宽, 显示半高 = 原始w/h × TEXTURE_SCALE / 2)
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
-- contour 归一化基于显示尺寸（原始 w/h × TEXTURE_SCALE=2），必须对齐
-- margin: 轮廓向外膨胀的世界单位距离
local _ISLAND_TEXTURE_SCALE = 2   -- 与 IslandSystem.lua 中 TEXTURE_SCALE 保持一致
local function _pointInIslandContour(px, py, regDef, margin)
    local contour = regDef.contour
    local n = #contour
    local ix, iy = regDef.x, regDef.y
    local iw = regDef.w * _ISLAND_TEXTURE_SCALE   -- 显示尺寸，与 contour 归一化一致
    local ih = regDef.h * _ISLAND_TEXTURE_SCALE
    margin = margin or 0
    -- 把 margin 转换为归一化缩放因子，让轮廓向外均匀膨胀
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
        return  -- 落在岛内，过滤
    end
    local ddx = wx - cx
    local ddy = wy - cy
    local d = math.sqrt(ddx * ddx + ddy * ddy)
    local maxDist = math.sqrt(hw * hw + hh * hh)
    local fade = math.min(1.0, d / (maxDist * 2.2))
    rocks[#rocks + 1] = { x = wx, y = wy, r = r, a = ang, s = seedVal, f = fade }
end

-- 按岛屿生成礁石列表（多簇随机分布，确定性，只算一次）
-- 每个岛屿生成 2~4 个"簇中心"，每簇再密集散布若干礁石，使分布更自然
local _ALL_ROCKS = (function()
    local rocks = {}
    local gseed = 42  -- 全局种子

    for _, isl in ipairs(_ISLAND_DEFS) do
        local id, cx, cy, hw, hh = isl[1], isl[2], isl[3], isl[4], isl[5]
        local regDef = _rockRegistry.islands[id]
        local baseR  = 13 + math.floor(hw / 28)

        -- ── 决定该岛簇数量（2~4）──────────────────────────────────────────
        gseed = gseed + id * 137 + 19
        local nClusters = 2 + (gseed % 3)  -- 2, 3 或 4 簇

        for c = 1, nClusters do
            -- ── 簇中心：在岛屿外缘（1.0~2.4× 半径）随机一个方向 ───────────
            gseed = gseed + c * 71 + 43
            local va, sa = _rng(gseed)
            local vd, sd = _rng(sa + 17)
            local clusterAng  = va * math.pi * 2
            local clusterDist = hw * (1.0 + vd * 1.4)  -- 1.0~2.4×
            local ccx = cx + math.cos(clusterAng) * clusterDist
            local ccy = cy + math.sin(clusterAng) * clusterDist * (hh / hw)

            -- ── 该簇内礁石数量（3~7）─────────────────────────────────────
            gseed = sd + c * 53
            local nRocks = 3 + (gseed % 5)  -- 3~7 块

            -- 簇半径：与岛屿大小相关，让小岛簇更紧凑
            local clusterR = hw * (0.18 + (c % 3) * 0.07)

            for k = 1, nRocks do
                gseed = gseed + k * 31 + 7
                local v1, s1 = _rng(gseed)
                local v2, s2 = _rng(s1 + 13)
                local v3, s3 = _rng(s2 + 29)
                local v4,  _ = _rng(s3 + 53)

                -- 簇内散布（小半径随机偏移）
                local offAng  = v1 * math.pi * 2
                local offDist = v2 * clusterR
                local wx = ccx + math.cos(offAng) * offDist
                local wy = ccy + math.sin(offAng) * offDist * 0.65

                -- 石头大小
                local r = baseR + math.floor(v3 * (baseR * 0.8))
                local seedVal = (id * 17 + c * 41 + k * 13) % 255 + 1

                _tryAddRock(rocks, wx, wy, r, v4 * math.pi * 2, seedVal,
                            cx, cy, hw, hh, regDef)
            end
        end

        -- ── 额外 2~3 块孤立礁石，增加稀疏感 ─────────────────────────────
        gseed = gseed + id * 59 + 3
        local nLone = 2 + (id % 2)
        for k = 1, nLone do
            gseed = gseed + k * 97
            local v1, s1 = _rng(gseed)
            local v2, s2 = _rng(s1 + 23)
            local v3, s3 = _rng(s2 + 47)
            local v4,  _ = _rng(s3 + 61)

            local ang  = v1 * math.pi * 2
            local dist = hw * (1.8 + v2 * 1.2)  -- 稍远，1.8~3.0×
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

-- fade: 0=近岛（深色不透明）, 1=远离（浅色融入海水）
-- 生成石头的顶点列表（阴影和本体共用同一套顶点）
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
local function _drawRockShadow(sx, sy, sz, baseAng, seed, fade)
    local pts, cx, cy, N = _rockPts(sx, sy, sz, baseAng, seed)
    local shadowAlpha = 1.0 - fade * 0.75
    nvgBeginPath(vg)
    for i = 1, N do
        local px = cx + (pts[i].x - cx) * 1.1 + sz * 0.10
        local py = cy + (pts[i].y - cy) * 1.1 + sz * 0.12
        if i == 1 then nvgMoveTo(vg, px, py) else nvgLineTo(vg, px, py) end
    end
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(10, 18, 30, math.floor(55 * shadowAlpha)))
    nvgFill(vg)
end

-- 只绘制石头本体（面 + 轮廓 + 高光），无阴影
local function _drawRockBody(sx, sy, sz, baseAng, seed, fade)
    local pts, cx, cy, N = _rockPts(sx, sy, sz, baseAng, seed)

    local function blendToSea(r0, g0, b0, a0)
        local wr, wg, wb = 57, 125, 164
        local r = math.floor(r0 + (wr - r0) * fade)
        local g = math.floor(g0 + (wg - g0) * fade)
        local b = math.floor(b0 + (wb - b0) * fade)
        return nvgRGBA(r, g, b, a0)
    end

    -- 三角面：方向光照 + 距离色融合
    for i = 1, N do
        local j   = (i % N) + 1
        local emx = (pts[i].x + pts[j].x) * 0.5 - cx
        local emy = (pts[i].y + pts[j].y) * 0.5 - cy
        local len = math.sqrt(emx * emx + emy * emy) + 0.001
        local lf  = math.max(0.0, math.min(1.0, (-emx * 0.6 - emy * 1.0) / len * 0.45 + 0.55))
        local r0 = math.floor(38 + lf * 48)
        local g0 = math.floor(52 + lf * 54)
        local b0 = math.floor(78 + lf * 58)
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx, cy)
        nvgLineTo(vg, pts[i].x, pts[i].y)
        nvgLineTo(vg, pts[j].x, pts[j].y)
        nvgClosePath(vg)
        nvgFillColor(vg, blendToSea(r0, g0, b0, 255))
        nvgFill(vg)
    end

    -- 轮廓线
    nvgBeginPath(vg)
    for i = 1, N do
        if i == 1 then nvgMoveTo(vg, pts[i].x, pts[i].y)
        else            nvgLineTo(vg, pts[i].x, pts[i].y) end
    end
    nvgClosePath(vg)
    nvgStrokeColor(vg, nvgRGBA(20, 35, 55, math.floor(80 * (1.0 - fade * 0.75))))
    nvgStrokeWidth(vg, 0.9)
    nvgStroke(vg)

    -- 高光面
    local ha  = baseAng - math.pi * 0.55
    local hx1 = cx + math.cos(ha - 0.4)  * sz * 0.38
    local hy1 = cy + math.sin(ha - 0.4)  * sz * 0.22
    local hx2 = cx + math.cos(ha + 0.1)  * sz * 0.46
    local hy2 = cy + math.sin(ha + 0.1)  * sz * 0.20
    local hx3 = cx + math.cos(ha + 0.55) * sz * 0.32
    local hy3 = cy + math.sin(ha + 0.55) * sz * 0.18
    nvgBeginPath(vg)
    nvgMoveTo(vg, hx1, hy1)
    nvgLineTo(vg, hx2, hy2)
    nvgLineTo(vg, hx3, hy3)
    nvgClosePath(vg)
    nvgFillColor(vg, blendToSea(100, 135, 175, 85))
    nvgFill(vg)
end

function DrawAllIslandRocks()
    -- 第一遍：所有阴影
    for _, def in ipairs(_ALL_ROCKS) do
        local sx, sy = WorldToScreen(def.x, def.y)
        if sx > -200 and sx < screenW + 200 and sy > -200 and sy < screenH + 200 then
            _drawRockShadow(sx, sy, def.r, def.a, def.s, def.f or 0)
        end
    end
    -- 第二遍：所有石头本体（整层压在阴影之上）
    for _, def in ipairs(_ALL_ROCKS) do
        local sx, sy = WorldToScreen(def.x, def.y)
        if sx > -200 and sx < screenW + 200 and sy > -200 and sy < screenH + 200 then
            _drawRockBody(sx, sy, def.r, def.a, def.s, def.f or 0)
        end
    end
end

-- ============================================================================
-- 水面渲染 (2D Water Shader)
-- ============================================================================

function DrawWater()
    local w, h = screenW, screenH
    local t = waterTime

    -- 1) 基础海色（随海域分区变化，平滑过渡）
    local fromZone = ZONE_TABLE[currentZoneR] or ZONE_TABLE[190]
    local toZone   = ZONE_TABLE[targetZoneR]  or ZONE_TABLE[190]
    local t_z = zoneColorT
    local function lerpC(a, b, f) return math.floor(a + (b - a) * f + 0.5) end
    local c1r = lerpC(fromZone[1][1], toZone[1][1], t_z)
    local c1g = lerpC(fromZone[1][2], toZone[1][2], t_z)
    local c1b = lerpC(fromZone[1][3], toZone[1][3], t_z)
    local c2r = lerpC(fromZone[2][1], toZone[2][1], t_z)
    local c2g = lerpC(fromZone[2][2], toZone[2][2], t_z)
    local c2b = lerpC(fromZone[2][3], toZone[2][3], t_z)

    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    local baseGrad = nvgLinearGradient(vg, 0, 0, w * 0.3, h,
        nvgRGBA(c1r, c1g, c1b, 255),
        nvgRGBA(c2r, c2g, c2b, 255))
    nvgFillPaint(vg, baseGrad)
    nvgFill(vg)

    -- 2) 大波浪色带 (模拟水面光照变化, 世界坐标)
    local WB_STEP = 8  -- 波浪路径采样步长(px)
    for i = 1, 5 do
        local phase = t * (0.3 + i * 0.08) + i * 1.7
        local yOff = math.sin(phase) * 40
        local worldBaseY = i * 120 + yOff
        local bandY = ((worldBaseY - camY * 0.6) % (h + 120)) - 60
        local bandH = 60 + math.sin(t * 0.5 + i) * 20

        local alpha = math.floor(18 + math.sin(t * 0.4 + i * 2) * 8)
        -- 每条带独立的波浪参数，随时间和摄像机X滚动
        local wFreq  = 0.007 + i * 0.0012
        local wAmp   = 9 + i * 2.5
        local wPhase = t * (0.4 + i * 0.06) + i * 2.1 + camX * 0.004

        local grad = nvgLinearGradient(vg, 0, bandY - bandH/2, 0, bandY + bandH/2,
            nvgRGBA(40, 100, 170, 0),
            nvgRGBA(30, 85, 155, alpha))
        -- 上半段：顶边波浪 → 中线波浪
        nvgBeginPath(vg)
        for x = 0, w, WB_STEP do
            local topY = bandY - bandH/2 + math.sin(x * wFreq + wPhase) * wAmp
            if x == 0 then nvgMoveTo(vg, x, topY) else nvgLineTo(vg, x, topY) end
        end
        for x = w, 0, -WB_STEP do
            local midY = bandY + math.sin(x * wFreq + wPhase) * wAmp
            nvgLineTo(vg, x, midY)
        end
        nvgClosePath(vg)
        nvgFillPaint(vg, grad)
        nvgFill(vg)

        local grad2 = nvgLinearGradient(vg, 0, bandY - bandH/2, 0, bandY + bandH/2,
            nvgRGBA(30, 85, 155, alpha),
            nvgRGBA(40, 100, 170, 0))
        -- 下半段：中线波浪 → 底边波浪
        nvgBeginPath(vg)
        for x = 0, w, WB_STEP do
            local midY = bandY + math.sin(x * wFreq + wPhase) * wAmp
            if x == 0 then nvgMoveTo(vg, x, midY) else nvgLineTo(vg, x, midY) end
        end
        for x = w, 0, -WB_STEP do
            local botY = bandY + bandH/2 + math.sin(x * wFreq + wPhase) * wAmp
            nvgLineTo(vg, x, botY)
        end
        nvgClosePath(vg)
        nvgFillPaint(vg, grad2)
        nvgFill(vg)
    end

    -- 3) 波纹线条 (sin 曲线模拟水波, 视差滚动)
    local waveCount = 10
    local waveSpacing = (h + 40) / waveCount
    local waveScroll = (camY * 0.7) % waveSpacing
    local waveCamX = camX * 0.7

    for i = 0, waveCount - 1 do
        local baseY = i * waveSpacing - waveScroll
        local seed = i + 1
        local waveFreq = 0.008 + seed * 0.002
        local waveAmp = 4 + seed * 0.8
        local waveSpeed = t * (0.6 + seed * 0.12) + seed * 0.9

        nvgBeginPath(vg)
        local startY = baseY + math.sin(waveSpeed) * waveAmp
        nvgMoveTo(vg, 0, startY)
        for x = 10, w, 10 do
            local yy = baseY + math.sin((x + waveCamX) * waveFreq + waveSpeed) * waveAmp
            nvgLineTo(vg, x, yy)
        end
        local lineAlpha = 15 + seed * 3
        nvgStrokeColor(vg, nvgRGBA(70, 140, 210, lineAlpha))
        nvgStrokeWidth(vg, 1.2)
        nvgStroke(vg)
    end

    -- 4) 焦散光斑 (Caustics)
    for i = 1, 35 do
        local phase = waterTime * 1.8 + i * 5.37
        local lifePhase = math.sin(phase)
        if lifePhase > 0 then
            local wx = i * 173 + math.sin(waterTime * 0.25 + i * 0.7) * 30
            local wy = i * 119 + math.cos(waterTime * 0.3 + i * 0.9) * 25
            local cx = ((wx - camX * 0.8) % (w + 40)) - 20
            local cy = ((wy - camY * 0.8) % (h + 40)) - 20
            local sz = 2 + lifePhase * 3
            local alpha = lifePhase * 60

            nvgBeginPath(vg)
            nvgCircle(vg, cx, cy, sz)
            nvgFillColor(vg, nvgRGBA(150, 210, 255, alpha))
            nvgFill(vg)
        end
    end

    -- 5) 太阳反光斑 (Specular highlights)
    for i = 1, 8 do
        local phase = waterTime * 0.7 + i * 3.14
        local blink = math.max(0, math.sin(phase))
        if blink > 0.3 then
            local wx = i * 211 + math.sin(waterTime * 0.15 + i) * 50
            local wy = i * 157 + math.cos(waterTime * 0.2 + i) * 40
            local ssx = ((wx - camX * 0.7) % (w + 60)) - 30
            local ssy = ((wy - camY * 0.7) % (h + 60)) - 30
            local sz = 1.5 + blink * 2

            local glow = nvgRadialGradient(vg, ssx, ssy, 0, sz * 3,
                nvgRGBA(255, 255, 220, blink * 120),
                nvgRGBA(255, 255, 220, 0))
            nvgBeginPath(vg)
            nvgCircle(vg, ssx, ssy, sz * 3)
            nvgFillPaint(vg, glow)
            nvgFill(vg)
        end
    end

    -- (浅水光晕已移至 IslandSystem.DrawBelow)
end

-- ============================================================================
-- 世界物体渲染
-- ============================================================================

function WorldToScreen(wx, wy)
    return screenW / 2 + (wx - camX),
           screenH / 2 + (wy - camY)
end

function ScreenToWorld(sx, sy)
    return camX + (sx - screenW / 2) / camScale,
           camY + (sy - screenH / 2) / camScale
end

-- NPC 头像：当玩家进入停靠范围时，在对应岛屿上方浮现头像气泡
function DrawNpcAvatars()
    if STATE == "menu" then return end

    -- 复用停靠检测：FindNearestIsland 检测的是船体到岛屿轮廓的距离，与停靠提示一致
    local nearIsland = FindNearestIsland()
    if not nearIsland then return end

    -- 查找该岛屿是否有绑定的 NPC 头像（同时取出位移偏移）
    local avatarIdx, offX, offY = nil, 0, 0
    for _, entry in ipairs(NPC_ISLAND_MAP) do
        if entry.islandId == nearIsland.id then
            avatarIdx = entry.avatarIdx
            offX = entry.offX or 0
            offY = entry.offY or 0
            break
        end
    end
    if not avatarIdx then return end

    local imgId = imgNpcAvatars[avatarIdx]
    if not imgId or imgId <= 0 then return end

    local island = IslandSystem.GetIsland(nearIsland.id)
    if not island then return end

    -- 图片原始比例 470×558，按高度缩放到 AVATAR_H
    local AVATAR_H      = 100  -- 显示高度(px)
    local AVATAR_W      = math.floor(AVATAR_H * 470 / 558)  -- 保持原始宽高比
    local AVATAR_OFFSET = 140  -- 头像底部在岛屿中心上方的世界单位偏移

    -- 浮动动画
    local bobY = math.sin(gameTime * 2.0) * 4
    -- sx,sy 对应头像底部中心，再叠加单独偏移
    local sx, sy = WorldToScreen(island.x, island.y - AVATAR_OFFSET + bobY)
    sx = sx + offX
    sy = sy + offY

    nvgSave(vg)
    nvgTranslate(vg, sx, sy)

    -- 阴影：预生成 shadow PNG（跟随透明通道形状，偏移已内嵌在像素里）
    local shId = imgNpcShadows[avatarIdx]
    if shId and shId > 0 then
        local shPat = nvgImagePattern(vg, -AVATAR_W / 2, -AVATAR_H, AVATAR_W, AVATAR_H, 0, shId, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, -AVATAR_W / 2, -AVATAR_H, AVATAR_W, AVATAR_H)
        nvgFillPaint(vg, shPat)
        nvgFill(vg)
    end

    -- 图片本体（PNG 含透明通道，形状由图片本身决定）
    local pat = nvgImagePattern(vg, -AVATAR_W / 2, -AVATAR_H, AVATAR_W, AVATAR_H, 0, imgId, 1.0)
    nvgBeginPath(vg)
    nvgRect(vg, -AVATAR_W / 2, -AVATAR_H, AVATAR_W, AVATAR_H)
    nvgFillPaint(vg, pat)
    nvgFill(vg)

    nvgRestore(vg)
end

function DrawWorldObjects()
    -- 尾流
    for _, p in ipairs(wakeParticles) do
        local sx, sy = WorldToScreen(p.x, p.y)
        if sx > -50 and sx < screenW + 50 and sy > -50 and sy < screenH + 50 then
            local alpha = (p.life / p.maxLife) * 100
            nvgBeginPath(vg)
            nvgCircle(vg, sx, sy, p.size)
            nvgFillColor(vg, nvgRGBA(180, 220, 255, alpha))
            nvgFill(vg)
        end
    end

    -- 鱼影
    for _, fs in ipairs(fishShadows) do
        local sx, sy = WorldToScreen(fs.x, fs.y)
        if sx > -50 and sx < screenW + 50 and sy > -50 and sy < screenH + 50 then
            local alpha = fs.attracted and 0.9 or 0.65
            local w = fs.size * 2.8
            local h = w / 4.478   -- 103×23 px, 保持原始比例

            nvgSave(vg)
            nvgTranslate(vg, sx, sy)
            nvgRotate(vg, fs.angle)
            nvgGlobalAlpha(vg, alpha)

            if imgFishShadow and imgFishShadow > 0 then
                local pat = nvgImagePattern(vg, -w/2, -h/2, w, h, 0, imgFishShadow, 1.0)
                nvgBeginPath(vg)
                nvgRect(vg, -w/2, -h/2, w, h)
                nvgFillPaint(vg, pat)
                nvgFill(vg)
            else
                -- 回退：原始手绘
                local fishLen = fs.size
                local fishW   = fs.size * 0.35
                nvgBeginPath(vg)
                nvgEllipse(vg, 0, 0, fishLen, fishW)
                nvgFillColor(vg, nvgRGBA(20, 40, 60, 255))
                nvgFill(vg)
            end

            nvgRestore(vg)
        end
    end

    -- 热点气泡 + 聚集鱼影
    DrawHotspots()

    -- 漂浮木板
    for idx, p in ipairs(floatingPlanks) do
        local sx, sy = WorldToScreen(p.x, p.y)
        if sx > -60 and sx < screenW + 60 and sy > -60 and sy < screenH + 60 then
            nvgSave(vg)
            nvgTranslate(vg, sx, sy)
            nvgRotate(vg, p.angle)

            local halfL = p.length / 2
            local halfW = p.width / 2
            local wobble = math.sin(p.wobbleT * 1.2) * 1.5  -- 水波颠簸

            -- 木板阴影（水下）
            nvgBeginPath(vg)
            nvgRoundedRect(vg, -halfL + 1, -halfW + 1 + wobble, p.length, p.width, 2)
            nvgFillColor(vg, nvgRGBA(15, 30, 50, 50))
            nvgFill(vg)

            -- 木板本体
            nvgBeginPath(vg)
            nvgRoundedRect(vg, -halfL, -halfW + wobble, p.length, p.width, 2)
            nvgFillColor(vg, nvgRGBA(160, 120, 65, 210))
            nvgFill(vg)

            -- 木纹线
            nvgBeginPath(vg)
            nvgMoveTo(vg, -halfL + 3, wobble)
            nvgLineTo(vg, halfL - 3, wobble)
            nvgStrokeColor(vg, nvgRGBA(130, 95, 45, 100))
            nvgStrokeWidth(vg, 0.8)
            nvgStroke(vg)

            -- 靠近时显示拾取提示光圈
            local dx = p.x - boat.x
            local dy = p.y - boat.y
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist < PLANK_PICKUP_DIST then
                nvgBeginPath(vg)
                local pulseR = (halfL + 6) + math.sin(p.wobbleT * 3) * 2
                nvgCircle(vg, 0, wobble, pulseR)
                nvgStrokeColor(vg, nvgRGBA(255, 230, 130, 140))
                nvgStrokeWidth(vg, 1.5)
                nvgStroke(vg)
            end

            nvgRestore(vg)

            -- 拾取提示文字（光圈外面画，不受旋转影响）
            if dist < PLANK_PICKUP_DIST then
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, 12)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(255, 240, 180, 220))
                nvgText(vg, sx, sy - 18, "[E] 拾取", nil)
            end
        end
    end

    -- 遛鱼中的上钩鱼影 (使用 fish_shadow.png 贴图, 鱼嘴对准鱼线终点)
    if STATE == "fight" and curFish and fight.fishWorldX then
        local fsx, fsy = WorldToScreen(fight.fishWorldX, fight.fishWorldY)
        if fsx > -200 and fsx < screenW + 200 and fsy > -200 and fsy < screenH + 200 then
            local wt = curFish.weight or 1
            local shadowLen = 18 + math.min(47, wt * 1.5)
            local w = shadowLen * 2.8
            local h = w / 4.478                 -- 103×23 原始比例

            local staminaRatio = fight.fishStamina / fight.fishMaxStam
            local wobbleFreq = 4.0 + staminaRatio * 6.0
            local wobbleAmp = 0.12 + staminaRatio * 0.08
            local wobble = math.sin(gameTime * wobbleFreq) * wobbleAmp
            local rot = fight.fishHeading - math.pi * 0.5 + wobble

            -- 鱼嘴在图片中的本地偏移 (100,11) → 令嘴对准 fsx,fsy
            -- 图片左上角相对于嘴的偏移: (-100/103*w, -11/23*h)
            local ox = -(100/103) * w   -- 图片左边缘 X (相对于嘴)
            local oy = -(11/23)  * h    -- 图片顶边缘 Y (相对于嘴)

            nvgSave(vg)
            nvgTranslate(vg, fsx, fsy)
            nvgRotate(vg, rot)
            nvgGlobalAlpha(vg, 0.9)

            if imgFishShadow and imgFishShadow > 0 then
                local pat = nvgImagePattern(vg, ox, oy, w, h, 0, imgFishShadow, 1.0)
                nvgBeginPath(vg)
                nvgRect(vg, ox, oy, w, h)
                nvgFillPaint(vg, pat)
                nvgFill(vg)
            else
                -- 回退: 手绘水滴形
                local headR = shadowLen * 0.32
                local hcx   = shadowLen * 0.35
                nvgBeginPath(vg)
                nvgArc(vg, hcx, 0, headR, -math.pi*0.5, math.pi*0.5, NVG_CW)
                nvgQuadTo(vg, -shadowLen*0.3,  headR*0.35, -shadowLen, 0)
                nvgQuadTo(vg, -shadowLen*0.3, -headR*0.35,  hcx, -headR)
                nvgClosePath(vg)
                nvgFillColor(vg, nvgRGBA(15, 30, 50, 200))
                nvgFill(vg)
            end

            nvgRestore(vg)
        end
    end

    -- (旧地标岛屿贴图/浮沫/装饰物渲染已移至 IslandSystem.DrawBelow / DrawAbove)
end

-- ============================================================================
-- 小船渲染 (Sprite Stacking 伪 3D)
-- ============================================================================

-- 层间垂直偏移 (像素), 控制立体感强度
local STACK_OFFSET = CFG.STACK_OFFSET * CFG.BOAT_SCALE

-- 绘制船体截面轮廓的通用函数 (贝塞尔船形)
-- wScale: 宽度缩放, lScale: 长度缩放, sternScale: 船尾宽度比
local function DrawHullPath(L, W, wScale, lScale, sternScale)
    local w = W * wScale
    local l = L * lScale
    local stern = sternScale or 0.85
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, -l)                                                        -- 船头尖端
    nvgBezierTo(vg, w * 0.6, -l * 0.3, w * 0.55, l * 0.15, w * 0.45, l * 0.5) -- 右弧
    nvgLineTo(vg, w * 0.4 * stern, l * 0.65)                                    -- 右船尾
    nvgLineTo(vg, -w * 0.4 * stern, l * 0.65)                                   -- 左船尾
    nvgLineTo(vg, -w * 0.45, l * 0.5)                                           -- 左舷
    nvgBezierTo(vg, -w * 0.55, l * 0.15, -w * 0.6, -l * 0.3, 0, -l)           -- 左弧
    nvgClosePath(vg)
end

function DrawBoat()
    local sx, sy = WorldToScreen(boat.x, boat.y)
    local L = CFG.BOAT_LENGTH * CFG.BOAT_SCALE
    local W = CFG.BOAT_WIDTH  * CFG.BOAT_SCALE

    -- ── 层 0: 水面阴影 (不参与堆叠, 固定在水面) ──
    local BS = CFG.BOAT_SCALE
    nvgSave(vg)
    nvgTranslate(vg, sx + 3 * BS, sy + 3 * BS)
    nvgRotate(vg, boat.angle)
    DrawHullPath(L, W, 1.05, 1.0)
    nvgFillColor(vg, nvgRGBA(0, 15, 40, 50))
    nvgFill(vg)
    nvgRestore(vg)

    -- ── 层 1: 龙骨 (水下最底层, 窄而长) ──
    nvgSave(vg)
    nvgTranslate(vg, sx, sy - STACK_OFFSET * 1)
    nvgRotate(vg, boat.angle)
    DrawHullPath(L, W, 0.45, 0.88, 0.6)
    nvgFillColor(vg, nvgRGBA(60, 35, 15, 255))
    nvgFill(vg)
    nvgRestore(vg)

    -- ── 层 2: 下船体 ──
    nvgSave(vg)
    nvgTranslate(vg, sx, sy - STACK_OFFSET * 2)
    nvgRotate(vg, boat.angle)
    DrawHullPath(L, W, 0.62, 0.92, 0.7)
    nvgFillColor(vg, nvgRGBA(80, 48, 20, 255))
    nvgFill(vg)
    nvgRestore(vg)

    -- ── 层 3: 中船体 ──
    nvgSave(vg)
    nvgTranslate(vg, sx, sy - STACK_OFFSET * 3)
    nvgRotate(vg, boat.angle)
    DrawHullPath(L, W, 0.78, 0.95, 0.8)
    nvgFillColor(vg, nvgRGBA(105, 65, 28, 255))
    nvgFill(vg)
    nvgRestore(vg)

    -- ── 层 4: 上船体 (水线面, 最宽) ──
    nvgSave(vg)
    nvgTranslate(vg, sx, sy - STACK_OFFSET * 4)
    nvgRotate(vg, boat.angle)
    DrawHullPath(L, W, 0.92, 0.98, 0.88)
    nvgFillColor(vg, nvgRGBA(130, 82, 35, 255))
    nvgFill(vg)
    nvgRestore(vg)

    -- ── 层 5: 船舷 (带深色描边的外壳顶部) ──
    nvgSave(vg)
    nvgTranslate(vg, sx, sy - STACK_OFFSET * 5)
    nvgRotate(vg, boat.angle)
    DrawHullPath(L, W, 1.0, 1.0, 0.92)
    nvgFillColor(vg, nvgRGBA(155, 105, 50, 255))
    nvgFill(vg)
    -- 船舷边线
    DrawHullPath(L, W, 1.0, 1.0, 0.92)
    nvgStrokeColor(vg, nvgRGBA(90, 55, 22, 220))
    nvgStrokeWidth(vg, 1.2)
    nvgStroke(vg)
    nvgRestore(vg)

    -- ── 层 6: 甲板 ──
    nvgSave(vg)
    nvgTranslate(vg, sx, sy - STACK_OFFSET * 6)
    nvgRotate(vg, boat.angle)
    DrawHullPath(L, W, 0.88, 0.93, 0.85)
    nvgFillColor(vg, nvgRGBA(195, 165, 115, 255))
    nvgFill(vg)
    -- 甲板木纹线
    for i = 1, 4 do
        local lx = -W * 0.3 + (i / 5) * W * 0.6
        nvgBeginPath(vg)
        nvgMoveTo(vg, lx, -L * 0.7)
        nvgLineTo(vg, lx, L * 0.5)
        nvgStrokeColor(vg, nvgRGBA(170, 140, 90, 80))
        nvgStrokeWidth(vg, 0.6)
        nvgStroke(vg)
    end
    -- 船头设备 (绞盘)
    nvgBeginPath(vg)
    nvgCircle(vg, 0, -L * 0.65, 2.5)
    nvgFillColor(vg, nvgRGBA(120, 120, 130, 220))
    nvgFill(vg)
    -- 船尾鱼竿座 (金属底座)
    local baseX, baseY = GetRodBaseLocal()
    for i = 1, 2 do
        local side = (i == 1) and -1 or 1
        nvgBeginPath(vg)
        nvgCircle(vg, baseX * side, baseY, 2.5)
        nvgFillColor(vg, nvgRGBA(90, 90, 100, 220))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(60, 60, 70, 180))
        nvgStrokeWidth(vg, 0.8)
        nvgStroke(vg)
    end
    nvgRestore(vg)

    -- ── 层 6.5: 鱼竿 (甲板与舱室之间) ──
    local tipX, tipY = GetRodTipLocal()
    for i = 1, 2 do
        local side = rods[i].side

        -- 抬杆偏移: 快速上升 → 缓慢回落 (ease-out)
        local strikeLift = 0
        if strikeState.active and strikeState.rodIndex == i then
            local t = strikeState.timer / CFG.STRIKE_DURATION  -- 0→1
            if t < 0.3 then
                strikeLift = (t / 0.3)
            else
                strikeLift = 1.0 - ((t - 0.3) / 0.7)
            end
            strikeLift = strikeLift * CFG.STRIKE_LIFT_PX
        end

        nvgSave(vg)
        nvgTranslate(vg, sx, sy - STACK_OFFSET * 6.5 - strikeLift)
        nvgRotate(vg, boat.angle)

        local bx = baseX * side
        local by = baseY
        local tx = tipX * side
        local ty = tipY

        -- ── 鱼竿弯曲: 根据鱼线张力 + 方向，累积角度旋转 ──
        local ROD_SECTIONS = 5
        local pts = {}
        for s = 0, ROD_SECTIONS do
            local t = s / ROD_SECTIONS
            pts[s + 1] = {
                x = bx + (tx - bx) * t,
                y = by + (ty - by) * t,
            }
        end

        local rod_i = rods[i]
        local bendFactor = 0
        local localPullX, localPullY = 0, 0

        if rod_i.rope and #rod_i.rope >= 2 and rod_i.state ~= "idle" then
            local straightTipX, straightTipY = GetRodTipLocal()
            straightTipX = straightTipX * rod_i.side
            local cosB = math.cos(boat.angle)
            local sinB = math.sin(boat.angle)
            local sax = boat.x + straightTipX * cosB - straightTipY * sinB
            local say = boat.y + straightTipX * sinB + straightTipY * cosB

            -- fight 状态用鱼的世界坐标做拉力参考，避免 rope 节点被旋转反馈污染
            local pullRefX, pullRefY
            if STATE == "fight" and activeRod == i then
                pullRefX, pullRefY = GetFishWorldPos()
            else
                local r2 = rod_i.rope[math.min(3, #rod_i.rope)]
                pullRefX, pullRefY = r2.x, r2.y
            end
            local dx, dy = pullRefX - sax, pullRefY - say
            local dlen = math.sqrt(dx * dx + dy * dy)
            if dlen > 0.1 then
                local wPullX, wPullY = dx / dlen, dy / dlen
                local cosA = math.cos(-boat.angle)
                local sinA = math.sin(-boat.angle)
                localPullX = wPullX * cosA - wPullY * sinA
                localPullY = wPullX * sinA + wPullY * cosA
            end

            if STATE == "fight" and activeRod == i then
                bendFactor = math.min(1.0, (fight.tension or 0) / fight.lineStrength)
            elseif rod_i.state == "bite" then
                bendFactor = 0.25
            elseif rod_i.state == "trolling" then
                bendFactor = 0.08
            end
        end

        -- ── 鱼竿跟随方向旋转 (读取 UpdateRodAim 计算的 aimAngle) ──
        local rotAngle = rod_i.aimAngle

        if math.abs(rotAngle) > 0.001 then
            local cosF = math.cos(rotAngle)
            local sinF = math.sin(rotAngle)
            for j = 2, ROD_SECTIONS + 1 do
                local ox = pts[j].x - pts[1].x
                local oy = pts[j].y - pts[1].y
                pts[j].x = pts[1].x + ox * cosF - oy * sinF
                pts[j].y = pts[1].y + ox * sinF + oy * cosF
            end
            tx = pts[ROD_SECTIONS + 1].x
            ty = pts[ROD_SECTIONS + 1].y
        end

        if false and bendFactor > 0.005 then  -- 暂时关闭弯曲, 只保留抬杆+转动
            local rodDX = tx - bx
            local rodDY = ty - by
            local rodLen = math.sqrt(rodDX * rodDX + rodDY * rodDY)
            if rodLen > 0.1 then
                local rodNX, rodNY = rodDX / rodLen, rodDY / rodLen
                local perpSign = rodNX * localPullY - rodNY * localPullX

                -- 计算拉力方向与鱼竿方向的夹角, 限制竿尖弯曲不超过此角度
                local pullLen = math.sqrt(localPullX * localPullX + localPullY * localPullY)
                local maxAngle = math.pi * 0.45  -- 默认上限 81°
                if pullLen > 0.01 then
                    local dot = rodNX * (localPullX / pullLen) + rodNY * (localPullY / pullLen)
                    dot = math.max(-1, math.min(1, dot))
                    local angleBetween = math.acos(dot)  -- 拉力与鱼竿的夹角
                    maxAngle = math.min(maxAngle, angleBetween * 0.85)  -- 弯到夹角的 85%, 不超过
                end

                local jointFlex = { 0.025, 0.05, 0.10, 0.18, 0.30 }
                local BEND_SCALE = 5.0
                local flexSum = 0.555  -- jointFlex 总和
                local rawTotal = math.abs(perpSign) * bendFactor * flexSum * BEND_SCALE
                -- 如果原始总角度超过 maxAngle, 等比缩放
                local scale = 1.0
                if rawTotal > maxAngle and rawTotal > 0.001 then
                    scale = maxAngle / rawTotal
                end

                for j = 1, ROD_SECTIONS do
                    local angle = perpSign * bendFactor * jointFlex[j] * BEND_SCALE * scale
                    local pivX, pivY = pts[j].x, pts[j].y
                    local cosR = math.cos(angle)
                    local sinR = math.sin(angle)
                    for k = j + 1, ROD_SECTIONS + 1 do
                        local ox = pts[k].x - pivX
                        local oy = pts[k].y - pivY
                        pts[k].x = pivX + ox * cosR - oy * sinR
                        pts[k].y = pivY + ox * sinR + oy * cosR
                    end
                end
            end
        end

        -- ── 伪透视压缩: 抬杆时竿身均匀收缩 (模拟俯视投影) ──
        local liftT_now = 0
        local liftMaxAngle = CFG.FIGHT_LIFT_MAX_ANGLE
        if STATE == "fight" and activeRod == i and (fight.liftT or 0) > 0.001 then
            liftT_now   = fight.liftT
            liftMaxAngle = CFG.FIGHT_LIFT_MAX_ANGLE
        elseif (castState.charging and activeRod == i) or
               (rod_i.state == "casting" and activeRod == i) then
            -- 蓄力或飞行中: 使用抛竿抬杆进度
            if (castState.liftT or 0) > 0.001 then
                liftT_now   = castState.liftT
                liftMaxAngle = CFG.CAST_LIFT_MAX_ANGLE
            end
        end
        if liftT_now > 0.001 then
            local liftAngle = liftT_now * liftMaxAngle
            -- cos(0~90°) > 0: 竿身收缩（抬起压缩）
            -- cos(90°) = 0: 竿身消失（越顶瞬间）
            -- cos(90~180°) < 0: 竿身向对侧延伸（投石机效果）
            local cosLift = math.cos(liftAngle)
            for j = 2, ROD_SECTIONS + 1 do
                local dx = pts[j].x - pts[1].x
                local dy = pts[j].y - pts[1].y
                pts[j].x = pts[1].x + dx * cosLift
                pts[j].y = pts[1].y + dy * cosLift
            end
        end

        -- 缓存弯曲+压缩后竿尖的屏幕坐标 (直接复用当前 NanoVG 变换)
        -- 当前变换: translate(sx, sy - stackOff - strikeLift) + rotate(boat.angle)
        do
            local lx = pts[ROD_SECTIONS + 1].x
            local ly = pts[ROD_SECTIONS + 1].y
            local cosB = math.cos(boat.angle)
            local sinB = math.sin(boat.angle)
            rodBentTips[i] = {
                sx = sx + lx * cosB - ly * sinB,
                sy = sy - STACK_OFFSET * 6.5 - strikeLift + lx * sinB + ly * cosB,
            }
        end

        -- ── 5节竿身绘制 ──
        local secWidths  = { 3.6*BS, 2.8*BS, 2.0*BS, 1.4*BS, 0.8*BS }
        -- 抬杆时竿尖段变粗 (透视近大远小: 竿尖离"镜头"更近)
        if liftT_now > 0.001 then
            for s = 1, ROD_SECTIONS do
                -- 从根→尖, 缩放递增: 根节不变, 尖节最大放大1.5倍
                local frac = (s - 1) / (ROD_SECTIONS - 1)  -- 0, 0.25, 0.5, 0.75, 1.0
                secWidths[s] = secWidths[s] * (1.0 + liftT_now * frac * 0.5)
            end
        end
        -- 竿身颜色: 由装备的竿型决定 (fight 中用 fight.rodId, 非 fight 中用 equippedRodId)
        local rodColorId = (STATE == "fight" and activeRod == i) and (fight.rodId or equippedRodId) or equippedRodId
        local rodType    = ROD_TYPES[rodColorId] or ROD_TYPES[2]
        local secColors  = rodType.secBase
        local hlColor    = rodType.secHighlight
        for s = 1, ROD_SECTIONS do
            local p0 = pts[s]
            local p1 = pts[s + 1]
            local c = secColors[s]
            nvgBeginPath(vg)
            nvgMoveTo(vg, p0.x, p0.y)
            nvgLineTo(vg, p1.x, p1.y)
            nvgStrokeColor(vg, nvgRGBA(c[1], c[2], c[3], 240))
            nvgStrokeWidth(vg, secWidths[s])
            nvgStroke(vg)
            -- 高光线 (使用竿型专属高光色)
            nvgBeginPath(vg)
            nvgMoveTo(vg, p0.x, p0.y)
            nvgLineTo(vg, p1.x, p1.y)
            nvgStrokeColor(vg, nvgRGBA(hlColor[1], hlColor[2], hlColor[3], 50 + s * 8))
            nvgStrokeWidth(vg, secWidths[s] * 0.3)
            nvgStroke(vg)
            if s < ROD_SECTIONS then
                nvgBeginPath(vg)
                nvgCircle(vg, p1.x, p1.y, secWidths[s] * 0.55)
                nvgFillColor(vg, nvgRGBA(c[1] + 20, c[2] + 20, c[3] + 20, 200))
                nvgFill(vg)
            end
        end
        -- 竿尖导环
        local tipPt = pts[ROD_SECTIONS + 1]
        nvgBeginPath(vg)
        nvgCircle(vg, tipPt.x, tipPt.y, 1.2)
        nvgFillColor(vg, nvgRGBA(200, 200, 210, 230))
        nvgFill(vg)
        -- 竿根握把
        nvgBeginPath(vg)
        nvgCircle(vg, bx, by, 2.5)
        nvgFillColor(vg, nvgRGBA(60, 55, 50, 220))
        nvgFill(vg)

        nvgRestore(vg)
    end

    -- ── 层 7: 舱室底部 ──
    nvgSave(vg)
    nvgTranslate(vg, sx, sy - STACK_OFFSET * 7)
    nvgRotate(vg, boat.angle)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -W * 0.3, -L * 0.25, W * 0.6, L * 0.48, 3)
    nvgFillColor(vg, nvgRGBA(210, 190, 160, 255))
    nvgFill(vg)
    nvgRestore(vg)

    -- ── 层 8: 舱室中部 ──
    nvgSave(vg)
    nvgTranslate(vg, sx, sy - STACK_OFFSET * 8)
    nvgRotate(vg, boat.angle)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -W * 0.28, -L * 0.22, W * 0.56, L * 0.44, 3)
    nvgFillColor(vg, nvgRGBA(220, 200, 172, 255))
    nvgFill(vg)
    -- 侧面窗户
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -W * 0.27, -L * 0.1, W * 0.12, L * 0.12, 1.5)
    nvgFillColor(vg, nvgRGBA(140, 195, 230, 200))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, W * 0.15, -L * 0.1, W * 0.12, L * 0.12, 1.5)
    nvgFillColor(vg, nvgRGBA(140, 195, 230, 200))
    nvgFill(vg)
    nvgRestore(vg)

    -- ── 层 9: 舱室上部 ──
    nvgSave(vg)
    nvgTranslate(vg, sx, sy - STACK_OFFSET * 9)
    nvgRotate(vg, boat.angle)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -W * 0.26, -L * 0.20, W * 0.52, L * 0.40, 3)
    nvgFillColor(vg, nvgRGBA(230, 212, 185, 255))
    nvgFill(vg)
    -- 前窗 (大窗)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -W * 0.18, -L * 0.18, W * 0.36, L * 0.1, 2)
    nvgFillColor(vg, nvgRGBA(120, 185, 225, 220))
    nvgFill(vg)
    -- 窗框
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, -L * 0.18)
    nvgLineTo(vg, 0, -L * 0.08)
    nvgStrokeColor(vg, nvgRGBA(180, 160, 130, 180))
    nvgStrokeWidth(vg, 0.8)
    nvgStroke(vg)
    nvgRestore(vg)

    -- ── 层 10: 舱顶 ──
    nvgSave(vg)
    nvgTranslate(vg, sx, sy - STACK_OFFSET * 10)
    nvgRotate(vg, boat.angle)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -W * 0.24, -L * 0.18, W * 0.48, L * 0.36, 4)
    nvgFillColor(vg, nvgRGBA(200, 185, 160, 255))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(160, 140, 110, 180))
    nvgStrokeWidth(vg, 0.8)
    nvgStroke(vg)
    nvgRestore(vg)

    -- ── 层 11: 天线/桅杆 ──
    nvgSave(vg)
    nvgTranslate(vg, sx, sy - STACK_OFFSET * 11)
    nvgRotate(vg, boat.angle)
    -- 桅杆
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, -L * 0.05)
    nvgLineTo(vg, 0, -L * 0.35)
    nvgStrokeColor(vg, nvgRGBA(160, 140, 100, 240))
    nvgStrokeWidth(vg, 1.8)
    nvgStroke(vg)
    nvgRestore(vg)

    -- ── 层 12: 桅杆顶部 + 旗帜 ──
    nvgSave(vg)
    nvgTranslate(vg, sx, sy - STACK_OFFSET * 12)
    nvgRotate(vg, boat.angle)
    -- 横杆
    nvgBeginPath(vg)
    nvgMoveTo(vg, -W * 0.2, -L * 0.28)
    nvgLineTo(vg, W * 0.2, -L * 0.28)
    nvgStrokeColor(vg, nvgRGBA(150, 130, 90, 220))
    nvgStrokeWidth(vg, 1.2)
    nvgStroke(vg)
    -- 旗子
    local flagWave = math.sin(gameTime * 4) * 2
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, -L * 0.35)
    nvgLineTo(vg, 8 + flagWave, -L * 0.32)
    nvgLineTo(vg, 0, -L * 0.28)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(220, 55, 40, 230))
    nvgFill(vg)
    nvgRestore(vg)

    -- ── 方向指示 (最顶层, 不参与堆叠深度) ──
    nvgSave(vg)
    nvgTranslate(vg, sx, sy - STACK_OFFSET * 13)
    nvgRotate(vg, boat.angle)
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, -L - 4)
    nvgLineTo(vg, 3.5, -L + 2)
    nvgLineTo(vg, -3.5, -L + 2)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 130))
    nvgFill(vg)
    nvgRestore(vg)
end

-- ============================================================================
-- 钓鱼线渲染
-- ============================================================================

-- ── 蓄力抛竿: 方向指示线 + 落点标记 (世界空间层, canvas zoom 内) ──
-- ── 抬杆水花特效 ──
function DrawStrikeSplash()
    local sx, sy = WorldToScreen(strikeState.splashX, strikeState.splashY)
    local t = strikeState.timer / CFG.STRIKE_DURATION  -- 0→1

    -- 水花: 从中心爆发的径向线条 + 水滴圆点
    local alpha = math.floor(255 * math.max(0, 1.0 - t * 1.5))  -- 快速淡出
    if alpha <= 0 then return end

    local numRays = 8
    for i = 1, numRays do
        local angle = (i / numRays) * math.pi * 2 + t * 2  -- 微旋转
        local innerR = 4 + t * 15
        local outerR = 10 + t * 35
        local ix = sx + math.cos(angle) * innerR
        local iy = sy + math.sin(angle) * innerR
        local ox = sx + math.cos(angle) * outerR
        local oy = sy + math.sin(angle) * outerR

        -- 水花线
        nvgBeginPath(vg)
        nvgMoveTo(vg, ix, iy)
        nvgLineTo(vg, ox, oy)
        nvgStrokeWidth(vg, 2.0 * (1.0 - t))
        nvgStrokeColor(vg, nvgRGBA(200, 230, 255, alpha))
        nvgStroke(vg)

        -- 水滴点
        nvgBeginPath(vg)
        nvgCircle(vg, ox, oy, 1.5 * (1.0 - t * 0.7))
        nvgFillColor(vg, nvgRGBA(220, 240, 255, alpha))
        nvgFill(vg)
    end

    -- 中心白色闪光 (极短)
    if t < 0.15 then
        local flashA = math.floor(200 * (1.0 - t / 0.15))
        local flashR = 8 + t * 40
        local glow = nvgRadialGradient(vg, sx, sy, 0, flashR,
            nvgRGBA(255, 255, 255, flashA),
            nvgRGBA(255, 255, 255, 0))
        nvgBeginPath(vg)
        nvgCircle(vg, sx, sy, flashR)
        nvgFillPaint(vg, glow)
        nvgFill(vg)
    end
end

function DrawCastAim()
    -- 方向沿竿身: 竿根 → 旋转后竿尖 (蓄力期间鱼线与竿同向, 不跟鼠标)
    local rod = rods[activeRod]
    local bx_l, by_l = GetRodBaseLocal()
    bx_l = bx_l * rod.side
    local cosA = math.cos(boat.angle)
    local sinA = math.sin(boat.angle)
    local baseWX = boat.x + bx_l * cosA - by_l * sinA
    local baseWY = boat.y + bx_l * sinA + by_l * cosA
    local ax, ay = GetRotatedTipWorld(activeRod)

    -- 方向向量: 竿根 → 旋转后竿尖
    local dx = ax - baseWX
    local dy = ay - baseWY
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < 0.001 then return end
    dx, dy = dx / dist, dy / dist

    -- 抛投距离 (根据当前蓄力)
    local power = castState.power
    local castDist = CFG.CAST_MIN_DIST + (CFG.CAST_MAX_DIST - CFG.CAST_MIN_DIST) * power

    -- 起点/终点的屏幕坐标
    -- 补偿 sprite stack 偏移: 鱼竿在第 6.5 层, 视觉上向上抬高
    local rodStackOff = STACK_OFFSET * 6.5
    local sx, sy = WorldToScreen(ax, ay)
    sy = sy - rodStackOff
    local tx = ax + dx * castDist
    local ty = ay + dy * castDist
    local ex, ey = WorldToScreen(tx, ty)

    -- 箭头方向 (屏幕空间)
    local totalLen = math.sqrt((ex - sx)^2 + (ey - sy)^2)
    if totalLen < 2 then return end
    local ndx = (ex - sx) / totalLen
    local ndy = (ey - sy) / totalLen
    -- 法向量 (用于箭头宽度)
    local nx = -ndy
    local ny = ndx

    -- ── 颜色: 绿(0) → 黄(0.5) → 红(1.0) ──
    local cr, cg, cb
    if power < 0.5 then
        local t = power / 0.5
        cr = math.floor(60 + 195 * t)   -- 60→255
        cg = math.floor(220 - 20 * t)   -- 220→200
        cb = 50
    else
        local t = (power - 0.5) / 0.5
        cr = 255
        cg = math.floor(200 - 160 * t)  -- 200→40
        cb = math.floor(50 - 20 * t)    -- 50→30
    end
    local alpha = math.floor(150 + 105 * power)  -- 150→255

    -- ── 箭头尺寸: 随蓄力从小到大 ──
    local arrowHeadLen = 12 + 18 * power   -- 箭头头部长度 12→30
    local arrowHeadW   = 6 + 10 * power    -- 箭头头部半宽 6→16
    local shaftW       = 2 + 3 * power     -- 箭杆半宽 2→5

    -- 箭杆终点 (箭头三角形前面留出空间)
    local shaftEndLen = math.max(0, totalLen - arrowHeadLen)

    -- ── 绘制箭杆 (渐变矩形: 起点透明→终点实色) ──
    if shaftEndLen > 2 then
        local s0x, s0y = sx, sy
        local s1x = sx + ndx * shaftEndLen
        local s1y = sy + ndy * shaftEndLen

        -- 用线条简化绘制，宽度随蓄力增大
        nvgLineCap(vg, NVG_ROUND)
        nvgStrokeWidth(vg, shaftW * 2)

        -- 渐变: 起点半透明 → 终点实色
        local paint = nvgLinearGradient(vg, s0x, s0y, s1x, s1y,
            nvgRGBA(cr, cg, cb, math.floor(alpha * 0.15)),
            nvgRGBA(cr, cg, cb, alpha))
        nvgBeginPath(vg)
        nvgMoveTo(vg, s0x, s0y)
        nvgLineTo(vg, s1x, s1y)
        nvgStrokePaint(vg, paint)
        nvgStroke(vg)
    end

    -- ── 绘制箭头三角形 (实心) ──
    local tipX, tipY = ex, ey  -- 箭尖 = 落点
    local baseX = ex - ndx * arrowHeadLen
    local baseY = ey - ndy * arrowHeadLen
    local leftX  = baseX + nx * arrowHeadW
    local leftY  = baseY + ny * arrowHeadW
    local rightX = baseX - nx * arrowHeadW
    local rightY = baseY - ny * arrowHeadW

    nvgBeginPath(vg)
    nvgMoveTo(vg, tipX, tipY)
    nvgLineTo(vg, leftX, leftY)
    nvgLineTo(vg, rightX, rightY)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(cr, cg, cb, alpha))
    nvgFill(vg)

    -- 箭头边框 (微亮轮廓增加可读性)
    nvgStrokeWidth(vg, 1.2)
    nvgStrokeColor(vg, nvgRGBA(255, 255, 255, math.floor(alpha * 0.4)))
    nvgStroke(vg)

    -- ── 距离文字 (箭尖旁侧) ──
    local distText = string.format("%.0fm", castDist)
    local labelX = tipX + nx * (arrowHeadW + 10)
    local labelY = tipY + ny * (arrowHeadW + 10)
    nvgFontSize(vg, 11 + 3 * power)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    -- 阴影
    nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(alpha * 0.6)))
    nvgText(vg, labelX + 1, labelY + 1, distText, nil)
    -- 前景
    nvgFillColor(vg, nvgRGBA(255, 255, 230, alpha))
    nvgText(vg, labelX, labelY, distText, nil)
end

-- DrawCastPowerBar 已合并到 DrawCastAim 箭头中, 不再需要独立力度条
function DrawCastPowerBar()
    -- 保留空函数, 避免调用处报错
end

function DrawFishingLine(rodIndex)
    local rod = rods[rodIndex]
    local rope = rod.rope
    if #rope == 0 then return end

    -- 线颜色：选中的鱼竿更亮
    local lineAlpha = (rodIndex == activeRod) and 200 or 120
    local lineR, lineG, lineB = 220, 220, 220
    if rodIndex == 1 then lineR, lineG, lineB = 220, 230, 255
    elseif rodIndex == 2 then lineR, lineG, lineB = 255, 220, 200 end

    -- 将所有绳索节点转换为屏幕坐标
    -- 鱼竿在 sprite stack 层 6.5，需要对鱼线起点施加相同的垂直偏移
    local rodStackOffset = STACK_OFFSET * 6.5
    local isCasting = (rod.state == "casting" and rod.flyT ~= nil)
    local isStriking = (rod.state == "strike" and strikeState.active and strikeState.rodIndex == rodIndex)
    local pts = {}
    -- 弯曲后竿尖的屏幕坐标 (由 DrawBoat 每帧直接缓存, 无需二次转换)
    local bentTip = rodBentTips[rodIndex]
    local bentTipSX = bentTip and bentTip.sx
    local bentTipSY = bentTip and bentTip.sy
    -- 计算物理竿尖与视觉竿尖的屏幕偏移量 (用于平滑过渡)
    local tipOffsetX, tipOffsetY = 0, 0
    if bentTipSX then
        local physSX, physSY = WorldToScreen(rope[1].x, rope[1].y)
        tipOffsetX = bentTipSX - physSX
        tipOffsetY = bentTipSY - (physSY - rodStackOffset)
    end
    for i = 1, #rope do
        local sx, sy = WorldToScreen(rope[i].x, rope[i].y)
        if isCasting then
            -- 飞行中: 所有节点在空中, 用抛物线偏移模拟高度
            local frac = (i - 1) / (#rope - 1)  -- 节点在线上的位置 0~1
            -- 从 stackYOff 高度过渡到水面
            local tipBlend = math.max(0, 1.0 - frac * 4)  -- 前 25% 过渡
            sy = sy - rodStackOffset * tipBlend
            -- 视觉竿尖偏移: 从竿尖处全量应用, 向鱼饵端衰减到零
            local bendBlend = math.max(0, 1.0 - frac * 3)  -- 前 33% 过渡
            sx = sx + tipOffsetX * bendBlend
            sy = sy + tipOffsetY * bendBlend
            -- 抛物线弧度: 中间高两端低
            local arcH = CFG.CAST_ARC_HEIGHT * rod.flyT  -- 飞得越远弧越高
            local arc = 4 * frac * (1 - frac) * arcH
            sy = sy - arc
        elseif isStriking then
            -- 抬杆中: 鱼线绷直 + 高频抖动
            local frac = (i - 1) / (#rope - 1)
            local st = strikeState.timer / CFG.STRIKE_DURATION
            local liftNow = 0
            if st < 0.3 then liftNow = st / 0.3
            else liftNow = 1.0 - ((st - 0.3) / 0.7) end
            if i == 1 and bentTipSX then
                -- 竿尖: 直接使用缓存的屏幕坐标 (已含 strikeLift)
                sx, sy = bentTipSX, bentTipSY
            elseif i == 1 then
                sy = sy - liftNow * CFG.STRIKE_LIFT_PX
            else
                local tipOffset = rodStackOffset + liftNow * CFG.STRIKE_LIFT_PX
                local tipBlend = math.max(0, 1.0 - frac * 3)  -- 前 33% 过渡
                sy = sy - tipOffset * tipBlend
            end
            -- 高频抖动 (衰减: 靠近竿尖和鱼饵的两端少抖, 中间多)
            local shakeEnv = 4 * frac * (1 - frac)  -- 中间最大
            local shakeDecay = math.max(0, 1.0 - st * 2)  -- 快速衰减
            local shake = math.sin(gameTime * 80 + i * 1.7) * CFG.STRIKE_SHAKE_AMP * shakeEnv * shakeDecay
            sy = sy + shake
        else
            -- 常态: 竿尖使用弯曲后视觉位置
            if i == 1 and bentTipSX then
                sx, sy = bentTipSX, bentTipSY
            end
        end
        pts[i] = { x = sx, y = sy }
    end

    -- 逐段绘制鱼线，水面下部分透明度渐变
    -- 节点 1-4 在水面上 (100% alpha)，节点 5+ 在水面下 (70% → 25% alpha)
    local waterEntry = 4  -- 入水分界节点
    local underwaterStart = 0.70  -- 入水处透明度比例
    local underwaterEnd   = 0.25  -- 末端透明度比例
    local totalUnderwater = #pts - waterEntry  -- 水下节点数

    for i = 1, #pts - 1 do
        -- 计算本段起点和终点的透明度
        local function nodeAlpha(idx)
            if isCasting or isStriking then
                return lineAlpha  -- 飞行中/抬杆中全程不透明
            end
            if idx <= waterEntry then
                return lineAlpha
            else
                local t = (idx - waterEntry) / totalUnderwater  -- 0→1
                local ratio = underwaterStart + (underwaterEnd - underwaterStart) * t
                return math.floor(lineAlpha * ratio)
            end
        end
        local a1 = nodeAlpha(i)
        local a2 = nodeAlpha(i + 1)
        local aMid = math.floor((a1 + a2) / 2)

        -- Catmull-Rom 控制点 (首尾虚拟引导点, 避免端点急转弯)
        local p0, p1, p2, p3
        p1 = pts[i]
        p2 = pts[i + 1]
        if i == 1 then
            -- 虚拟 p0: 沿 p1→p2 反向延伸, 让首段切线平滑指向线的方向
            p0 = { x = p1.x * 2 - p2.x, y = p1.y * 2 - p2.y }
        else
            p0 = pts[i - 1]
        end
        if i + 2 <= #pts then
            p3 = pts[i + 2]
        else
            -- 虚拟 p3: 沿 p1→p2 方向延伸
            p3 = { x = p2.x * 2 - p1.x, y = p2.y * 2 - p1.y }
        end
        local cp1x = p1.x + (p2.x - p0.x) / 6
        local cp1y = p1.y + (p2.y - p0.y) / 6
        local cp2x = p2.x - (p3.x - p1.x) / 6
        local cp2y = p2.y - (p3.y - p1.y) / 6

        -- 绘制本段
        nvgBeginPath(vg)
        nvgMoveTo(vg, p1.x, p1.y)
        nvgBezierTo(vg, cp1x, cp1y, cp2x, cp2y, p2.x, p2.y)
        nvgStrokeColor(vg, nvgRGBA(lineR, lineG, lineB, aMid))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)

        -- 阴影 (水面下逐渐消失)
        local shadowAlpha = math.floor(30 * aMid / lineAlpha)
        nvgBeginPath(vg)
        nvgMoveTo(vg, p1.x + 1.5, p1.y + 1.5)
        nvgBezierTo(vg, cp1x + 1.5, cp1y + 1.5, cp2x + 1.5, cp2y + 1.5, p2.x + 1.5, p2.y + 1.5)
        nvgStrokeColor(vg, nvgRGBA(0, 0, 0, shadowAlpha))
        nvgStrokeWidth(vg, 2.0)
        nvgStroke(vg)
    end

    -- 鱼饵位置 (末端节点)
    local endX, endY = pts[#pts].x, pts[#pts].y

    -- 鱼饵: 咬钩闪烁
    if rod.state == "bite" then
        local flash = math.sin(gameTime * 12) * 0.5 + 0.5
        local glowR = 15 + flash * 10
        local glow = nvgRadialGradient(vg, endX, endY, 2, glowR,
            nvgRGBA(255, 200, 50, 180 * flash),
            nvgRGBA(255, 200, 50, 0))
        nvgBeginPath(vg)
        nvgCircle(vg, endX, endY, glowR)
        nvgFillPaint(vg, glow)
        nvgFill(vg)
    end

    -- 鱼饵圆点
    nvgBeginPath(vg)
    nvgCircle(vg, endX, endY, 4)
    nvgFillColor(vg, nvgRGBA(230, 60, 40, 230))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 150))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 鱼竿编号标识
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, lineAlpha))
    nvgText(vg, endX, endY - 12, tostring(rodIndex), nil)

    -- 拖钓进度指示 (小圆弧)
    if rod.state == "trolling" and rod.biteAt > 0 then
        local progress = math.min(1.0, rod.timer / rod.biteAt)
        if progress > 0.01 then
            nvgBeginPath(vg)
            nvgArc(vg, endX, endY, 10, -math.pi / 2, -math.pi / 2 + progress * math.pi * 2, 1)
            nvgStrokeColor(vg, nvgRGBA(100, 255, 100, 180))
            nvgStrokeWidth(vg, 2.5)
            nvgStroke(vg)
        end
    end
end

-- ============================================================================
-- 遛鱼 HUD 渲染
-- ============================================================================

function DrawFight()
    if not curFish then return end
    local cx = screenW / 2
    nvgFontFace(vg, "sans")

    -- ════════════════════════════════════════════════════════════════
    -- A. 底部浮动张力条 (始终可见, 紧凑)
    -- ════════════════════════════════════════════════════════════════
    local barW = math.min(840, screenW - 40)
    local barH = 14
    local barX = cx - barW / 2
    local barY = screenH - 50

    -- 张力值
    local tensionRatio = fight.tensionVisual / fight.lineStrength
    local dragKg = fight.drag * fight.lineStrength

    -- 渐变色: 绿→橙→红
    local tr, tg, tb
    if tensionRatio <= 0.30 then
        tr, tg, tb = 50, 180, 80
    elseif tensionRatio <= 0.60 then
        local t = (tensionRatio - 0.30) / 0.30
        tr = math.floor(50  + (230 - 50)  * t)
        tg = math.floor(180 + (150 - 180) * t)
        tb = math.floor(80  + (40  - 80)  * t)
    elseif tensionRatio <= 0.90 then
        local t = (tensionRatio - 0.60) / 0.30
        tr = math.floor(230 + (220 - 230) * t)
        tg = math.floor(150 + (50  - 150) * t)
        tb = math.floor(40  + (40  - 40)  * t)
    else
        tr, tg, tb = 220, 50, 40
    end

    -- ── 扇形刹车进度条 (张力条上方, 始终可见) ──
    do
        local totalGears = CFG.FIGHT_DRAG_GEARS
        local isLocked = fight.dragGear >= totalGears
        local knobNorm = fight.dragGear / totalGears   -- 0~1

        local arcR  = 40                               -- 扇形半径
        local arcW  = 6                                -- 弧线宽度
        local arcCX = barX + barW / 2                  -- 水平: 张力条正中
        local arcCY = barY - 56                        -- 垂直: 张力条上方

        -- 背景圆弧 (完整360°)
        nvgBeginPath(vg)
        nvgArc(vg, arcCX, arcCY, arcR, 0, math.pi * 2, NVG_CW)
        nvgStrokeColor(vg, nvgRGBA(40, 45, 60, 160))
        nvgStrokeWidth(vg, arcW)
        nvgStroke(vg)

        -- 前景扇形弧 (从12点方向顺时针)
        local startAng = -math.pi / 2
        local sweepAng = knobNorm * math.pi * 2
        if sweepAng > 0.01 then
            -- 渐变色: 绿 → 橙 → 红(锁死)
            local ar, ag, ab
            if knobNorm < 0.5 then
                local t = knobNorm / 0.5
                ar = math.floor(80  + (230 - 80)  * t)
                ag = math.floor(200 + (170 - 200) * t)
                ab = math.floor(120 + (50  - 120) * t)
            else
                local t = (knobNorm - 0.5) / 0.5
                ar = math.floor(230 + (240 - 230) * t)
                ag = math.floor(170 + (60  - 170) * t)
                ab = math.floor(50  + (50  - 50)  * t)
            end
            if isLocked then ar, ag, ab = 255, 80, 50 end

            nvgBeginPath(vg)
            nvgArc(vg, arcCX, arcCY, arcR, startAng, startAng + sweepAng, NVG_CW)
            nvgStrokeColor(vg, nvgRGBA(ar, ag, ab, 230))
            nvgStrokeWidth(vg, arcW + 1)
            nvgStroke(vg)

            -- 弧线末端小圆点
            local endAng = startAng + sweepAng
            local dotX = arcCX + math.cos(endAng) * arcR
            local dotY = arcCY + math.sin(endAng) * arcR
            nvgBeginPath(vg)
            nvgCircle(vg, dotX, dotY, arcW * 0.8)
            nvgFillColor(vg, nvgRGBA(ar, ag, ab, 255))
            nvgFill(vg)
        end

        -- 中心文字: 档位 / LOCK
        nvgFontSize(vg, 18)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        if isLocked then
            nvgFillColor(vg, nvgRGBA(255, 100, 80, 240))
            nvgText(vg, arcCX, arcCY - 2, "LOCK", nil)
        else
            nvgFillColor(vg, nvgRGBA(200, 210, 225, 220))
            nvgText(vg, arcCX, arcCY - 7, tostring(fight.dragGear), nil)
            nvgFontSize(vg, 11)
            -- 刹车力超过断线张力时显示红色警告
            if fight.drag >= 1.0 then
                nvgFillColor(vg, nvgRGBA(255, 80, 60, 220))
            else
                nvgFillColor(vg, nvgRGBA(160, 170, 190, 170))
            end
            nvgText(vg, arcCX, arcCY + 10, string.format("%.0fkg", dragKg), nil)
        end
    end

    -- 标题行: 鱼名 + 状态 + 张力数值
    local fc = curFish.type.color or {180, 200, 220}
    local behavText, behavR, behavG, behavB = "", 200, 200, 200
    if fight.slipping then
        behavText = " 出线!"
        behavR, behavG, behavB = 255, 100, 60
    elseif fight.reeling then
        behavText = " 收线"
        behavR, behavG, behavB = 100, 220, 160
    elseif fight.fishStamina <= 0 then
        behavText = " 疲惫"
        behavR, behavG, behavB = 120, 200, 120
    elseif fight.tanState == "active" then
        behavText = " 挣扎"
        behavR, behavG, behavB = 255, 200, 80
    end

    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(fc[1], fc[2], fc[3], 230))
    nvgText(vg, barX, barY - 10, curFish.type.name, nil)
    if behavText ~= "" then
        -- 状态紧跟鱼名后
        local nameW = nvgTextBounds(vg, 0, 0, curFish.type.name)
        nvgFillColor(vg, nvgRGBA(behavR, behavG, behavB, 220))
        nvgText(vg, barX + nameW + 2, barY - 10, behavText, nil)
    end

    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(220, 220, 230, 200))
    nvgFontSize(vg, 11)
    nvgText(vg, barX + barW, barY - 10,
        string.format("%.1fkg / %.0fkg", fight.tensionVisual, fight.lineStrength), nil)

    -- [调试] 收线速度
    do
        local spd = fight.effectiveReel or 0
        local maxSpd = fight.reelSpeedMax or 0
        local r, g, b = 120, 200, 255
        if spd <= 0 then r, g, b = 100, 100, 120 end
        nvgFontSize(vg, 16)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(r, g, b, 220))
        nvgText(vg, barX + 100, barY - 10,
            string.format("收线 %.1f/%.0f m/s", spd, maxSpd), nil)
    end

    -- 背景槽
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, barW, barH, 4)
    nvgFillColor(vg, nvgRGBA(15, 20, 35, 200))
    nvgFill(vg)

    -- 镜像双向填充
    local halfW = barW * 0.5
    local midX = barX + halfW
    local fillPx = tensionRatio * halfW
    if fillPx > 0 then
        nvgBeginPath(vg)
        nvgRect(vg, midX, barY, fillPx, barH)
        nvgRect(vg, midX - fillPx, barY, fillPx, barH)
        nvgFillColor(vg, nvgRGBA(tr, tg, tb, 220))
        nvgFill(vg)
    end

    -- ── 渔轮机械强度上限：灰色锁定区 ──
    -- mechRatio = reelMechStrength / lineStrength，若 < 1.0 则有锁定段
    local mechRatio = fight.reelMechStrength and (fight.reelMechStrength / fight.lineStrength) or 1.0
    if mechRatio < 1.0 then
        local lockStartPx = mechRatio * halfW        -- 锁定区起始像素（从中心量起）
        local lockW = (1.0 - mechRatio) * halfW      -- 锁定区宽度
        -- 双向锁定覆盖（灰色斜线纹理用纯色代替，更清晰）
        nvgBeginPath(vg)
        nvgRect(vg, midX + lockStartPx, barY, lockW, barH)
        nvgRect(vg, midX - lockStartPx - lockW, barY, lockW, barH)
        nvgFillColor(vg, nvgRGBA(40, 42, 55, 190))
        nvgFill(vg)
        -- 锁定区边框（斜线纹理感）
        nvgBeginPath(vg)
        nvgRect(vg, midX + lockStartPx, barY, lockW, barH)
        nvgRect(vg, midX - lockStartPx - lockW, barY, lockW, barH)
        nvgStrokeColor(vg, nvgRGBA(100, 80, 60, 160))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
        -- 机械强度分界线（橙红竖线）
        local mechLineX_r = midX + lockStartPx
        local mechLineX_l = midX - lockStartPx
        nvgBeginPath(vg)
        nvgMoveTo(vg, mechLineX_r, barY - 3)
        nvgLineTo(vg, mechLineX_r, barY + barH + 3)
        nvgMoveTo(vg, mechLineX_l, barY - 3)
        nvgLineTo(vg, mechLineX_l, barY + barH + 3)
        nvgStrokeColor(vg, nvgRGBA(255, 140, 60, 220))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
        -- 机械强度标注文字
        nvgFontSize(vg, 9)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(255, 140, 60, 180))
        nvgText(vg, mechLineX_r, barY + barH + 2,
            string.format("%.0fkg", fight.reelMechStrength), nil)
    end

    -- 中线
    nvgBeginPath(vg)
    nvgMoveTo(vg, midX, barY - 2)
    nvgLineTo(vg, midX, barY + barH + 2)
    nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 100))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 张力超限闪烁
    if tensionRatio > 0.85 then
        local flash = math.sin(gameTime * 10) * 0.5 + 0.5
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX - 1, barY - 1, barW + 2, barH + 2, 5)
        nvgStrokeColor(vg, nvgRGBA(255, 50, 30, math.floor(flash * 180)))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
    end

    -- ── 卷轮旋转图标 + 环形线长条 (张力条左侧) ──
    do
        local reelR = 14                     -- 卷轮内圈半径
        local ringR = reelR + 5              -- 环形进度条半径
        local reelCX = barX - ringR - 6      -- 条左侧留间距
        local reelCY = barY + barH / 2       -- 垂直居中

        -- 环形线长进度条 (外环)
        local lineRatio = math.min(1, fight.lineLength / (fight.lineCapacity or CFG.FIGHT_LINE_MAX))
        local startAng = -math.pi / 2        -- 12点方向起始
        local fullAng = math.pi * 2
        -- 底圈 (暗色满环)
        nvgBeginPath(vg)
        nvgArc(vg, reelCX, reelCY, ringR, startAng, startAng + fullAng, 1)
        nvgStrokeColor(vg, nvgRGBA(40, 50, 70, 150))
        nvgStrokeWidth(vg, 3)
        nvgStroke(vg)
        -- 前景弧 (线长比例, 颜色随余量变化)
        if lineRatio > 0.01 then
            local lr, lg, lb
            local remain = 1.0 - lineRatio
            if remain > 0.4 then
                lr, lg, lb = 80, 180, 220    -- 充足: 蓝色
            elseif remain > 0.15 then
                lr, lg, lb = 220, 180, 50    -- 偏少: 黄色
            else
                lr, lg, lb = 220, 60, 40     -- 危险: 红色
            end
            nvgBeginPath(vg)
            nvgArc(vg, reelCX, reelCY, ringR, startAng, startAng + lineRatio * fullAng, 1)
            nvgStrokeColor(vg, nvgRGBA(lr, lg, lb, 220))
            nvgStrokeWidth(vg, 3)
            nvgStroke(vg)
        end

        -- 卷轮外圈
        nvgBeginPath(vg)
        nvgCircle(vg, reelCX, reelCY, reelR)
        nvgStrokeColor(vg, nvgRGBA(160, 170, 190, 180))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)

        -- 轴心
        nvgBeginPath(vg)
        nvgCircle(vg, reelCX, reelCY, 3)
        nvgFillColor(vg, nvgRGBA(180, 190, 210, 200))
        nvgFill(vg)

        -- 旋转辐条 (4根, 随 reelAngle 旋转)
        nvgSave(vg)
        nvgTranslate(vg, reelCX, reelCY)
        nvgRotate(vg, fight.reelAngle)
        for s = 0, 3 do
            local a = s * math.pi / 2
            local cosA = math.cos(a)
            local sinA = math.sin(a)
            nvgBeginPath(vg)
            nvgMoveTo(vg, cosA * 4, sinA * 4)
            nvgLineTo(vg, cosA * (reelR - 2), sinA * (reelR - 2))
            -- 收线时辐条高亮, 打滑时橙色, 空闲时暗淡
            if fight.slipping then
                nvgStrokeColor(vg, nvgRGBA(255, 140, 50, 200))
            elseif fight.reeling then
                nvgStrokeColor(vg, nvgRGBA(100, 220, 180, 220))
            else
                nvgStrokeColor(vg, nvgRGBA(120, 130, 150, 120))
            end
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)
        end
        nvgRestore(vg)
    end

    -- ── 体力条 (张力条正下方, 细条) ──
    do
        local stamY  = barY + barH + 5
        local stamH  = 5
        local stamRatio = fight.fishStamina / fight.fishMaxStam

        -- 背景槽
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, stamY, barW, stamH, 2)
        nvgFillColor(vg, nvgRGBA(15, 20, 35, 160))
        nvgFill(vg)

        -- 体力填充: 高体力橙黄, 低体力转绿(疲惫色)
        local sr, sg, sb
        if stamRatio > 0.5 then
            local t = (stamRatio - 0.5) / 0.5
            sr = math.floor(80  + (230 - 80)  * t)
            sg = math.floor(200 + (160 - 200) * t)
            sb = math.floor(100 + (50  - 100) * t)
        else
            sr, sg, sb = 80, 200, 100
        end
        local fw = math.max(0, stamRatio) * barW
        if fw > 1 then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, barX, stamY, fw, stamH, 2)
            nvgFillColor(vg, nvgRGBA(sr, sg, sb, 190))
            nvgFill(vg)
        end

        -- 标签
        nvgFontSize(vg, 9)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(160, 170, 190, 150))
        nvgText(vg, barX, stamY + stamH + 9, "体力", nil)
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgText(vg, barX + barW, stamY + stamH + 9,
            string.format("%d%%", math.ceil(stamRatio * 100)), nil)
    end

    -- 操作提示 (体力标签下方)
    nvgFontSize(vg, 10)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(140, 150, 170, 140))
    local reelHint = fight.reeling and "[收线中]" or "[左键]收线"
    nvgText(vg, cx, barY + barH + 28,
        reelHint .. "  [滚轮]刹车  [Tab]详情", nil)

    -- ════════════════════════════════════════════════════════════════
    -- B. 可折叠详情面板 (Tab 切换)
    -- ════════════════════════════════════════════════════════════════
    if fightDetailOpen then
        local pW = math.min(340, screenW - 20)
        local pH = 180
        local pX = screenW - pW - 10
        local pY = screenH - pH - 80

        -- 面板背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, pX, pY, pW, pH, 8)
        nvgFillColor(vg, nvgRGBA(8, 16, 32, 200))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(60, 120, 180, 80))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

        local dBarX = pX + 10
        local dBarW = pW - 20
        local dBarH = 12

        -- 通用条形
        local function DrawDetailBar(y, label, ratio, r, g, b, showText)
            nvgFontSize(vg, 10)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(160, 170, 190, 190))
            nvgText(vg, dBarX, y - 7, label, nil)
            if showText then
                nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(200, 210, 220, 190))
                nvgText(vg, dBarX + dBarW, y - 7, showText, nil)
            end
            nvgBeginPath(vg)
            nvgRoundedRect(vg, dBarX, y, dBarW, dBarH, 3)
            nvgFillColor(vg, nvgRGBA(20, 25, 40, 180))
            nvgFill(vg)
            local fw = math.max(0, math.min(1, ratio)) * dBarW
            if fw > 1 then
                nvgBeginPath(vg)
                nvgRoundedRect(vg, dBarX, y, fw, dBarH, 3)
                nvgFillColor(vg, nvgRGBA(r, g, b, 200))
                nvgFill(vg)
            end
        end

        -- 1. 出线量
        local curY = pY + 14
        local lineCap   = fight.lineCapacity or CFG.FIGHT_LINE_MAX
        local lineRatio = fight.lineLength / lineCap
        local lr, lg, lb = 80, 160, 230
        if lineRatio > 0.8 then lr, lg, lb = 230, 140, 40 end
        if lineRatio > 0.92 then lr, lg, lb = 230, 60, 40 end
        DrawDetailBar(curY, "线长", lineRatio, lr, lg, lb,
            string.format("%.0fm / %dm", fight.lineLength, lineCap))

        -- 2. 鱼距
        curY = curY + dBarH + 14
        local fishDistRatio = math.min(1, fight.fishRadius / lineCap)
        local fdr, fdg, fdb = 100, 180, 230
        if fight.fishRadius < CFG.FIGHT_CATCH_DIST * 2 then fdr, fdg, fdb = 80, 220, 120 end
        DrawDetailBar(curY, "鱼距", fishDistRatio, fdr, fdg, fdb,
            string.format("%.0fm", fight.fishRadius))

        -- 3. 鱼体力
        curY = curY + dBarH + 14
        local stamRatio = fight.fishStamina / fight.fishMaxStam
        local sr, sg, sb = 230, 160, 50
        if stamRatio < 0.3 then sr, sg, sb = 80, 200, 100 end
        DrawDetailBar(curY, "鱼力", stamRatio, sr, sg, sb,
            string.format("%d%%", math.ceil(stamRatio * 100)))

        -- 4. 刹车档位
        curY = curY + dBarH + 14
        local totalGears = CFG.FIGHT_DRAG_GEARS
        local isLocked = fight.dragGear >= totalGears
        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(160, 170, 190, 190))
        nvgText(vg, dBarX, curY, "刹车", nil)

        local kTrackX = dBarX + 32
        local kTrackW = dBarW - 70
        nvgBeginPath(vg)
        nvgRoundedRect(vg, kTrackX, curY + 3, kTrackW, 3, 1.5)
        nvgFillColor(vg, nvgRGBA(50, 55, 70, 180))
        nvgFill(vg)

        local knobNorm = fight.dragGear / totalGears
        local knobX = kTrackX + knobNorm * kTrackW
        nvgBeginPath(vg)
        nvgCircle(vg, knobX, curY + 4.5, 5)
        nvgFillColor(vg, isLocked and nvgRGBA(255, 100, 80, 230) or nvgRGBA(190, 200, 220, 230))
        nvgFill(vg)

        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(190, 200, 220, 190))
        local gearText = isLocked and "LOCK"
            or string.format("%d/%d (%.0fkg)", fight.dragGear, totalGears - 1, dragKg)
        nvgText(vg, dBarX + dBarW, curY + 1, gearText, nil)

        -- 打滑/收线 动态边框
        if fight.slipping then
            local pulse = math.sin(gameTime * 8) * 0.3 + 0.7
            nvgBeginPath(vg)
            nvgRoundedRect(vg, pX + 2, pY + 2, pW - 4, pH - 4, 7)
            nvgStrokeColor(vg, nvgRGBA(255, 80, 50, math.floor(pulse * 120)))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)
        elseif fight.reeling then
            local pulse = math.sin(gameTime * 6) * 0.3 + 0.7
            nvgBeginPath(vg)
            nvgRoundedRect(vg, pX + 2, pY + 2, pW - 4, pH - 4, 7)
            nvgStrokeColor(vg, nvgRGBA(100, 220, 160, math.floor(pulse * 80)))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)
        end
    end

    -- ════════════════════════════════════════════════════════════════
    -- C. 诊断 (不受折叠影响)
    -- ════════════════════════════════════════════════════════════════
    if diagInfiniteLine then
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 13)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(255, 220, 100, 220))
        nvgText(vg, 10, 60, "[L]无限线长 ON")
    end

    -- 实时张力波形图
    if diagChartOn and #diagChartBuf > 1 then
        local chartW = math.min(480, screenW - 40)
        local chartH = 120
        local chartX = (screenW - chartW) / 2
        local chartY = 10

        nvgBeginPath(vg)
        nvgRoundedRect(vg, chartX - 4, chartY - 4, chartW + 8, chartH + 24, 6)
        nvgFillColor(vg, nvgRGBA(10, 15, 30, 200))
        nvgFill(vg)

        local yMax = fight.lineStrength
        -- dragRatio 可能超过 1.0（重轮配轻竿），钳位到图表范围内显示
        local dragRatio = math.min(1.0, fight.drag)
        local dragY = chartY + chartH - dragRatio * chartH
        -- 刹车力超过断线张力时变红警告
        local dragLineR = fight.drag >= 1.0 and 255 or 255
        local dragLineG = fight.drag >= 1.0 and 80  or 200
        local dragLineB = fight.drag >= 1.0 and 60  or 80
        nvgBeginPath(vg)
        nvgStrokeColor(vg, nvgRGBA(dragLineR, dragLineG, dragLineB, 200))
        nvgStrokeWidth(vg, 1)
        local dashLen = 6
        local ix = 0
        while ix < chartW do
            local segEnd = math.min(ix + dashLen, chartW)
            nvgMoveTo(vg, chartX + ix, dragY)
            nvgLineTo(vg, chartX + segEnd, dragY)
            ix = ix + dashLen * 2
        end
        nvgStroke(vg)

        local bufLen = math.min(#diagChartBuf, DIAG_CHART_LEN)
        local points = math.min(bufLen, math.floor(chartW))
        local step = bufLen / points

        nvgBeginPath(vg)
        local tMin, tMax = 999, -999
        for i = 0, points - 1 do
            local bufIdx = math.floor(i * step) + 1
            local readIdx = ((diagChartIdx - bufLen + bufIdx - 1) % DIAG_CHART_LEN) + 1
            local sample = diagChartBuf[readIdx]
            if sample then
                local px = chartX + (i / (points - 1)) * chartW
                local py = chartY + chartH - (sample.tension / yMax) * chartH
                py = math.max(chartY, math.min(chartY + chartH, py))
                if i == 0 then
                    nvgMoveTo(vg, px, py)
                else
                    nvgLineTo(vg, px, py)
                end
                if sample.tension < tMin then tMin = sample.tension end
                if sample.tension > tMax then tMax = sample.tension end
            end
        end
        nvgStrokeColor(vg, nvgRGBA(80, 200, 255, 220))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 11)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(180, 180, 180, 200))
        nvgText(vg, chartX + 2, chartY + 2, string.format("%.0fkg", yMax))
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_BOTTOM)
        nvgText(vg, chartX + 2, chartY + chartH - 2, "0")
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
        local actualDragKg = fight.drag * fight.lineStrength
        -- 刹车力超过断线张力时标注红色警告
        if fight.drag >= 1.0 then
            nvgFillColor(vg, nvgRGBA(255, 80, 60, 230))
            nvgText(vg, chartX + chartW - 2, dragY - 2,
                string.format("阈值%.0fkg ⚠超线强", actualDragKg))
        else
            nvgFillColor(vg, nvgRGBA(255, 200, 80, 200))
            nvgText(vg, chartX + chartW - 2, dragY - 2,
                string.format("阈值%.0fkg", actualDragKg))
        end
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(100, 255, 200, 220))
        if tMin < 900 then
            nvgText(vg, chartX + chartW / 2, chartY + chartH + 2,
                string.format("张力 %.1fkg  范围 %.1f~%.1f  振幅 %.1f  [H]关闭",
                    fight.tension, tMin, tMax, tMax - tMin))
        end
    end
end

-- ============================================================================
-- 结果界面
-- ============================================================================

function DrawCatchResult()
    local cx = screenW / 2
    local cy = screenH / 2

    -- 背景（加高以容纳鱼图）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - 160, cy - 120, 320, 240, 14)
    nvgFillColor(vg, nvgRGBA(10, 30, 20, 230))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(50, 200, 100, 180))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    -- 标题
    nvgFontSize(vg, 28)
    nvgFillColor(vg, nvgRGBA(50, 255, 120, 255))
    nvgText(vg, cx, cy - 88, "钓到了!", nil)

    if curFish then
        local fc2 = curFish.type.color or {180, 200, 220}

        -- 鱼名
        nvgFontSize(vg, 22)
        nvgFillColor(vg, nvgRGBA(fc2[1], fc2[2], fc2[3], 255))
        nvgText(vg, cx, cy - 60, curFish.type.name, nil)

        -- 鱼图区域背景
        local sprX, sprY, sprSize = cx, cy - 5, 80
        nvgBeginPath(vg)
        nvgRoundedRect(vg, sprX - 46, sprY - 46, 92, 92, 8)
        nvgFillColor(vg, nvgRGBA(5, 20, 12, 200))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(40, 160, 80, 120))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

        -- 鱼的精灵图（fish_01 / fish_02）
        local sheets = { imgFishSheets[1], imgFishSheets[2], imgFishSheets[3], imgFishSheets[4] }
        local drawn = FishAtlas.DrawSprite(vg, curFish.type.id, sheets, sprX, sprY, sprSize, 1.0)
        if not drawn then
            -- 无贴图时回退到色块
            nvgBeginPath(vg)
            nvgEllipse(vg, sprX, sprY + 4, 22, 10)
            nvgFillColor(vg, nvgRGBA(fc2[1], fc2[2], fc2[3], 200))
            nvgFill(vg)
        end

        -- 重量
        nvgFontSize(vg, 18)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 220))
        nvgText(vg, cx, cy + 55, "重量: " .. FormatWeight(curFish.weight), nil)

        -- 体力耗尽耗时（仅体力归零时显示）
        if fight.staminaDepletedAt then
            local t = fight.staminaDepletedAt
            local mins = math.floor(t / 60)
            local secs = math.floor(t % 60)
            local timeStr = mins > 0
                and string.format("体力耗尽: %d分%02d秒", mins, secs)
                or  string.format("体力耗尽: %d秒", secs)
            nvgFontSize(vg, 13)
            nvgFillColor(vg, nvgRGBA(120, 200, 120, 200))
            nvgText(vg, cx, cy + 73, timeStr, nil)
        end
    end

    -- 提示
    nvgFontSize(vg, 14)
    nvgFillColor(vg, nvgRGBA(180, 180, 180, 200))
    nvgText(vg, cx, cy + 90, "按空格键继续", nil)
end

function DrawFailResult()
    local cx = screenW / 2
    local cy = screenH / 2

    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - 140, cy - 60, 280, 120, 14)
    nvgFillColor(vg, nvgRGBA(30, 15, 15, 230))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(200, 80, 60, 150))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    nvgFontSize(vg, 24)
    nvgFillColor(vg, nvgRGBA(255, 100, 80, 255))
    nvgText(vg, cx, cy - 20, "鱼跑了...", nil)

    nvgFontSize(vg, 14)
    nvgFillColor(vg, nvgRGBA(180, 180, 180, 200))
    nvgText(vg, cx, cy + 20, "按空格键继续", nil)
end

-- ============================================================================
-- 对话框渲染
-- ============================================================================

function DrawDialogue()
    if not _dlg.open then return end

    -- 将动态文字写入 composite（composite 本身结构不变，只更新 label）
    _dlgComp.frames[1].label = _dlg.text
    _dlgComp.frames[2].label = _dlg.speaker

    -- 整体缩小至 85%，水平居中，底部贴屏幕边
    local scale = 0.85
    local dw    = screenW * scale
    local dh    = screenH * scale
    local dx    = (screenW - dw) * 0.5
    local dy    = screenH - dh

    nvgSave(vg)
    BezierFrame.Draw(vg, _dlgComp, dx, dy, dw, dh)
    nvgRestore(vg)

    -- 操作提示（随对话框右下角）
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
    nvgFillColor(vg, nvgRGBA(140, 140, 140, 180))
    nvgText(vg, dx + dw * 0.96, dy + dh * 0.99, "[空格 / E] 关闭", nil)
end

-- ============================================================================
-- 全局绿光叠层（相减模式，独立于时间系统）
-- ============================================================================
-- 混合公式：result = dst × (1 - src)   近似 OpenGL FUNC_REVERSE_SUBTRACT
-- 颜色：#70ff21，float=0.4，顶部 alpha=0 → 底部 alpha 最高

function DrawGlobalGreenFilter()
    nvgSave(vg)
    -- (ZERO, ONE_MINUS_SRC_COLOR): result = dst_color × (1 - src_color)
    nvgGlobalCompositeBlendFunc(vg, NVG_ZERO, NVG_ONE_MINUS_SRC_COLOR)
    local paint = nvgLinearGradient(vg, 0, 0, 0, screenH,
        nvgRGBA(0x70, 0xff, 0x21,   0),   -- 顶部：完全透明
        nvgRGBA(0x70, 0xff, 0x21,  61))   -- 底部：alpha = 0.24 × 255
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, screenW, screenH)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
    nvgRestore(vg)
end

-- 全局暖黄光照（加法模式，左亮右暗）
-- 颜色：#fffa6c，float=0.17，左 alpha=43 → 右 alpha=0
function DrawGlobalWarmLight()
    nvgSave(vg)
    -- 加法混合：result = src + dst
    nvgGlobalCompositeBlendFunc(vg, NVG_ONE, NVG_ONE)
    local paint = nvgLinearGradient(vg, 0, 0, screenW, 0,
        nvgRGBA(0xff, 0xfa, 0x6c,  43),   -- 左：alpha = 0.17 × 255
        nvgRGBA(0xff, 0xfa, 0x6c,   0))   -- 右：完全透明
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, screenW, screenH)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
    nvgRestore(vg)
end

-- ============================================================================
-- 天空叠加层（时间/昼夜效果）
-- ============================================================================

function DrawSkyOverlay()
    -- 延迟初始化星星
    if not twStars_ then
        twStars_ = TimeWeather.GenStars(80)
    end

    local phase = TimeWeather.GetPhase()
    local r, g, b, a = TimeWeather.GetOverlay()

    -- ── 夜晚星星 ───────────────────────────────────────────────────────
    if phase == "night" or phase == "dawn" or phase == "dusk" then
        -- 夜晚全亮，黎明/黄昏渐隐
        local starAlpha = 1.0
        if phase == "dawn" then
            starAlpha = math.max(0, 1 - (TimeWeather.GetHour() - 5) / 2)
        elseif phase == "dusk" then
            starAlpha = math.max(0, (TimeWeather.GetHour() - 17) / 2)
        end

        if starAlpha > 0.02 then
            for _, s in ipairs(twStars_) do
                local twinkle = 0.5 + 0.5 * math.sin(gameTime * 1.8 + s.phase)
                local sa = math.floor(starAlpha * twinkle * 200)
                nvgBeginPath(vg)
                nvgCircle(vg, s.x * screenW, s.y * screenH, s.size)
                nvgFillColor(vg, nvgRGBA(240, 245, 255, sa))
                nvgFill(vg)
            end
        end
    end

    -- ── 全屏色调叠加层（上下渐变）──────────────────────────────────────
    local hr, hg, hb, ha = TimeWeather.GetHorizonOverlay()
    if a > 2 or ha > 2 then
        local paint = nvgLinearGradient(vg, 0, 0, 0, screenH,
            nvgRGBA(r,  g,  b,  a),
            nvgRGBA(hr, hg, hb, ha))
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, screenW, screenH)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
    end
end

-- ============================================================================
-- 天气：雨天粒子与环境
-- ============================================================================

local function InitRainDrops()
    math.randomseed(os.time and os.time() or 12345)
    rainDrops_ = {}
    for i = 1, RAIN_COUNT do
        rainDrops_[i] = {
            x     = math.random() * 1920,
            y     = math.random() * 1080,
            spd   = math.random() * 260 + 340,   -- 340~600 px/s
            len   = math.random() * 13 + 7,       -- 7~20 px
            alpha = math.random() * 55 + 65,      -- 65~120
        }
    end
end

-- 抽取下一段天气并重置计时器（内部调用）
local function RollWeather()
    -- 晴天 2/3，雨天 1/3
    if math.random() < 1 / 3 then
        weatherMode_ = "rain"
        weatherTimer_ = 180 + math.random() * 180  -- 雨天 3~6 分钟
        ShowNotify("开始下雨了 🌧", 130, 170, 230)
    else
        weatherMode_ = "sunny"
        weatherTimer_ = 360 + math.random() * 240  -- 晴天 6~10 分钟（约 2× 雨天均值）
        if rainIntensity_ > 0.05 then
            ShowNotify("雨停了，天晴了 ☀", 255, 220, 80)
        end
    end
end

-- 每帧更新雨滴位置和过渡强度
function UpdateRain(dt)
    -- ── 首次初始化：开局先晴天 60~120 秒 ────────────────────────────
    if not weatherInited_ then
        weatherInited_ = true
        weatherMode_   = "sunny"
        weatherTimer_  = 300 + math.random() * 300  -- 初始晴天 5~10 分钟
    end

    -- ── 天气状态机计时 ────────────────────────────────────────────────
    weatherTimer_ = weatherTimer_ - dt
    if weatherTimer_ <= 0 then
        RollWeather()
    end

    -- ── 平滑过渡（约 2 秒完成切换）───────────────────────────────────
    local target = weatherMode_ == "rain" and 1.0 or 0.0
    rainIntensity_ = rainIntensity_ + (target - rainIntensity_) * math.min(1, dt * 1.5)

    if rainIntensity_ < 0.01 then return end

    if #rainDrops_ == 0 then InitRainDrops() end

    local WIND = 0.20
    for _, d in ipairs(rainDrops_) do
        d.y = d.y + d.spd * dt
        d.x = d.x + d.spd * WIND * dt
        if d.y > screenH + 24 or d.x > screenW + 24 then
            d.x   = math.random() * (screenW + 80) - 40
            d.y   = -d.len - math.random() * 50
            d.spd = math.random() * 260 + 340
            d.len = math.random() * 13 + 7
            d.alpha = math.random() * 55 + 65
        end
    end
end

-- 渲染雨天效果（在天空叠加层之后调用）
function DrawRainEffect()
    if rainIntensity_ < 0.01 then return end
    local t = rainIntensity_

    -- ── 1. 雨天压暗叠加层 ─────────────────────────────────────────────
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, screenW, screenH)
    nvgFillColor(vg, nvgRGBA(18, 28, 52, math.floor(t * 115)))
    nvgFill(vg)

    -- ── 2. 底部雾气（地平线湿气感）────────────────────────────────────
    local fogPaint = nvgLinearGradient(vg,
        0, screenH * 0.52, 0, screenH,
        nvgRGBA(35, 50, 75, 0),
        nvgRGBA(25, 40, 65, math.floor(t * 95)))
    nvgBeginPath(vg)
    nvgRect(vg, 0, screenH * 0.52, screenW, screenH * 0.48)
    nvgFillPaint(vg, fogPaint)
    nvgFill(vg)

    -- ── 3. 雨滴条纹 ───────────────────────────────────────────────────
    if #rainDrops_ == 0 then return end
    local WIND = 0.20
    nvgLineCap(vg, NVG_ROUND)
    for _, d in ipairs(rainDrops_) do
        local a = math.floor(d.alpha * t)
        nvgBeginPath(vg)
        nvgMoveTo(vg, d.x, d.y)
        nvgLineTo(vg, d.x + d.len * WIND, d.y + d.len)
        nvgStrokeColor(vg, nvgRGBA(195, 218, 248, a))
        nvgStrokeWidth(vg, 0.85)
        nvgStroke(vg)
    end
    nvgLineCap(vg, NVG_BUTT)   -- 恢复默认

    -- ── 4. 顶部暗云压顶渐变 ───────────────────────────────────────────
    local cloudPaint = nvgLinearGradient(vg,
        0, 0, 0, screenH * 0.30,
        nvgRGBA(10, 18, 38, math.floor(t * 80)),
        nvgRGBA(10, 18, 38, 0))
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, screenW, screenH * 0.30)
    nvgFillPaint(vg, cloudPaint)
    nvgFill(vg)
end

-- ============================================================================
-- 夜晚灯光


-- ============================================================================
-- 时间调试滑条
-- ============================================================================

-- 滑条布局（全局供鼠标判断用）
local TW_SLIDER = {
    w = 240, h = 24, cornerR = 12,
    trackH = 6, handleR = 9,
}
function TW_SLIDER:rect()
    local x = (screenW - self.w) / 2
    local y = screenH - 52
    return x, y
end

function DrawTimeSlider()
    if STATE == "menu" then return end
    local sl = TW_SLIDER
    local sx, sy = sl:rect()
    local tod = TimeWeather.GetTOD()

    nvgSave(vg)

    -- 背景胶囊
    nvgBeginPath(vg)
    nvgRoundedRect(vg, sx, sy, sl.w, sl.h, sl.cornerR)
    nvgFillColor(vg, nvgRGBA(10, 15, 30, 180))
    nvgFill(vg)

    -- 轨道
    local trackY = sy + sl.h / 2
    local trackX0 = sx + sl.handleR + 4
    local trackX1 = sx + sl.w - sl.handleR - 4
    local trackW  = trackX1 - trackX0

    nvgBeginPath(vg)
    nvgRoundedRect(vg, trackX0, trackY - sl.trackH / 2, trackW, sl.trackH, sl.trackH / 2)
    nvgFillColor(vg, nvgRGBA(60, 70, 100, 200))
    nvgFill(vg)

    -- 已走过的高亮段
    local fillW = trackW * tod
    if fillW > 2 then
        local phase = TimeWeather.GetPhase()
        local fr, fg, fb = 255, 200, 80   -- 白天：黄
        if phase == "night" then fr, fg, fb = 100, 130, 220 end
        if phase == "dawn"  then fr, fg, fb = 255, 140, 60  end
        if phase == "dusk"  then fr, fg, fb = 230, 100, 40  end
        nvgBeginPath(vg)
        nvgRoundedRect(vg, trackX0, trackY - sl.trackH / 2, fillW, sl.trackH, sl.trackH / 2)
        nvgFillColor(vg, nvgRGBA(fr, fg, fb, 220))
        nvgFill(vg)
    end

    -- 把手
    local hx = trackX0 + trackW * tod
    nvgBeginPath(vg)
    nvgCircle(vg, hx, trackY, sl.handleR)
    nvgFillColor(vg, nvgRGBA(240, 245, 255, 240))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(180, 200, 255, 160))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 时间标签
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 215, 255, 200))
    nvgText(vg, sx + sl.w / 2, sy + sl.h + 10, TimeWeather.GetClockStr(), nil)

    nvgRestore(vg)
end

-- 判断鼠标是否在滑条轨道内，返回对应 tod（nil 表示不在）
TimeSliderHitTest = function(mx, my)
    local sl = TW_SLIDER
    local sx, sy = sl:rect()
    -- 扩大一点点点击区域
    if mx < sx - 4 or mx > sx + sl.w + 4 then return nil end
    if my < sy - 4 or my > sy + sl.h + 4 then return nil end
    local trackX0 = sx + sl.handleR + 4
    local trackX1 = sx + sl.w - sl.handleR - 4
    local t = (mx - trackX0) / (trackX1 - trackX0)
    return math.max(0, math.min(0.9999, t))
end

-- ============================================================================
-- 菜单
-- ============================================================================

function DrawMenu()
    local cx = screenW / 2
    local cy = screenH / 2

    -- 标题阴影
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 42)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0, 20, 50, 180))
    nvgText(vg, cx + 2, cy - 48, "海上钓鱼", nil)

    -- 标题
    nvgFillColor(vg, nvgRGBA(230, 245, 255, 255))
    nvgText(vg, cx, cy - 50, "海上钓鱼", nil)

    -- 副标题
    nvgFontSize(vg, 18)
    nvgFillColor(vg, nvgRGBA(150, 200, 230, 220))
    nvgText(vg, cx, cy, "2D 俯视角拖钓游戏", nil)

    -- 操作提示（按平台显示对应说明）
    nvgFontSize(vg, 15)
    nvgFillColor(vg, nvgRGBA(200, 220, 240, 180))
    if IS_MOBILE then
        nvgText(vg, cx, cy + 30, "摇杆 - 开船 | 工具条 - 巡航/抛竿", nil)
        nvgText(vg, cx, cy + 50, "点击鱼标 - 收线 | 工具条切换鱼竿", nil)
    else
        nvgText(vg, cx, cy + 30, "WASD / 摇杆 - 开船 | F - 巡航", nil)
        nvgText(vg, cx, cy + 50, "左键 - 收线 | 1/2 - 切换鱼竿", nil)
    end
    nvgText(vg, cx, cy + 70, "双鱼竿独立拖钓, 等待鱼咬钩!", nil)

    -- 闪烁提示
    local blink = math.sin(gameTime * 3) * 0.3 + 0.7
    nvgFontSize(vg, 20)
    nvgFillColor(vg, nvgRGBA(255, 220, 100, 255 * blink))
    nvgText(vg, cx, cy + 110, "按空格键开始", nil)

    -- 装饰: 小船图标
    nvgSave(vg)
    nvgTranslate(vg, cx, cy - 120)
    local wobble = math.sin(gameTime * 2) * 5
    nvgRotate(vg, math.sin(gameTime * 1.5) * 0.1)
    nvgTranslate(vg, 0, wobble)

    -- 简单船形
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, -18)
    nvgLineTo(vg, 10, 10)
    nvgLineTo(vg, -10, 10)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(180, 130, 70, 220))
    nvgFill(vg)

    -- 桅杆
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, -15)
    nvgLineTo(vg, 0, -35)
    nvgStrokeColor(vg, nvgRGBA(200, 160, 100, 220))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 旗子
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, -35)
    nvgLineTo(vg, 12, -30)
    nvgLineTo(vg, 0, -25)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(230, 70, 50, 220))
    nvgFill(vg)

    nvgRestore(vg)
end

-- ============================================================================
-- 航海图 (全屏地图)
-- ============================================================================

-- ============================================================================
-- (离屏纹理方案已完全移除，小地图改为实时绘制)
-- (HandleEndAllViewsRender 已随离屏纹理方案一同移除)

-- ============================================================================
-- 小地图 (右上角常驻)
-- ============================================================================
function DrawMinimap()
    if mapOpen then return end  -- 大地图打开时隐藏小地图

    local allIslands = IslandSystem.GetIslands()

    -- ── 以船只为中心的局部视野 ──
    -- 先算全图范围，再取 1/5 宽度作为小地图可视范围
    local fMinX, fMinY =  math.huge,  math.huge
    local fMaxX, fMaxY = -math.huge, -math.huge
    for _, isl in pairs(allIslands) do
        local hw, hh = isl.w * 0.5, isl.h * 0.5
        if isl.x - hw < fMinX then fMinX = isl.x - hw end
        if isl.y - hh < fMinY then fMinY = isl.y - hh end
        if isl.x + hw > fMaxX then fMaxX = isl.x + hw end
        if isl.y + hh > fMaxY then fMaxY = isl.y + hh end
    end
    local fullW = (fMaxX - fMinX) * 1.16   -- 含 8% padding
    local viewHalf = fullW / 5 / 2          -- 缩小 5 倍后的半宽

    local minX = boat.x - viewHalf
    local minY = boat.y - viewHalf
    local worldW = viewHalf * 2
    local worldH = viewHalf * 2

    -- ── 小地图尺寸和位置 ──
    local mmSize   = 140
    local mmMargin = 12
    local mmX      = screenW - mmSize - mmMargin
    local mmY      = mmMargin
    local cornerR  = 8

    local function W2MM(wx, wy)
        return mmX + (wx - minX) / worldW * mmSize,
               mmY + (wy - minY) / worldH * mmSize
    end

    nvgSave(vg)

    -- ── 背景框 ──
    nvgBeginPath(vg)
    nvgRoundedRect(vg, mmX - 2, mmY - 2, mmSize + 4, mmSize + 4, cornerR + 2)
    nvgFillColor(vg, nvgRGBA(10, 22, 45, 200))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(80, 140, 210, 100))
    nvgStrokeWidth(vg, 1.2)
    nvgStroke(vg)

    -- ── 裁剪区域 ──
    nvgScissor(vg, mmX, mmY, mmSize, mmSize)

    -- ── 海洋背景 ──
    nvgBeginPath(vg)
    nvgRect(vg, mmX, mmY, mmSize, mmSize)
    nvgFillColor(vg, nvgRGBA(18, 40, 75, 255))
    nvgFill(vg)

    -- ── 等高线（实时绘制） ──
    DrawContourLines(minX, minY, worldW, worldH, 18, W2MM, true)

    -- ── 岛屿轮廓 ──
    for _, isl in pairs(allIslands) do
        local contour = isl.contour
        if contour and #contour >= 3 then
            nvgBeginPath(vg)
            for ci, pt in ipairs(contour) do
                local wx = isl.x + pt[1] * isl.w
                local wy = isl.y + pt[2] * isl.h
                local mx, my = W2MM(wx, wy)
                if ci == 1 then nvgMoveTo(vg, mx, my)
                else            nvgLineTo(vg, mx, my) end
            end
            nvgClosePath(vg)
            nvgFillColor(vg, nvgRGBA(90, 165, 90, 160))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(140, 210, 140, 200))
            nvgStrokeWidth(vg, 0.8)
            nvgStroke(vg)
        end
    end

    -- ── 船只标记（黄色三角箭头） ──
    local bx, by = W2MM(boat.x, boat.y)
    local arrowSz = 5
    nvgSave(vg)
    nvgTranslate(vg, bx, by)
    nvgRotate(vg, boat.angle)
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, -arrowSz)
    nvgLineTo(vg, -arrowSz * 0.6, arrowSz * 0.5)
    nvgLineTo(vg,  arrowSz * 0.6, arrowSz * 0.5)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(255, 220, 60, 240))
    nvgFill(vg)
    nvgRestore(vg)

    -- ── 船只脉冲光圈 ──
    local pulse = 0.5 + 0.5 * math.sin(gameTime * 4)
    nvgBeginPath(vg)
    nvgCircle(vg, bx, by, 4 + pulse * 2)
    nvgStrokeColor(vg, nvgRGBA(255, 220, 60, math.floor(50 + 50 * pulse)))
    nvgStrokeWidth(vg, 0.8)
    nvgStroke(vg)

    nvgResetScissor(vg)

    -- ── 罗盘标 ──
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 9)
    nvgFillColor(vg, nvgRGBA(150, 180, 220, 140))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    nvgText(vg, mmX + mmSize / 2, mmY - 3, "N", nil)

    nvgRestore(vg)
end

function DrawMap()
    if not mapOpen then return end

    nvgSave(vg)

    -- ── 背景遮罩 ────────────────────────────────────────────────────────
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, screenW, screenH)
    nvgFillColor(vg, nvgRGBA(8, 18, 38, 210))
    nvgFill(vg)

    -- ── 地图区域（屏幕居中，留边距，等比缩放） ──────────────────────────
    local margin = 60
    local mapAreaW = screenW - margin * 2
    local mapAreaH = screenH - margin * 2 - 40  -- 上方留标题空间

    -- 使用与深度图一致的固定世界范围，确保上下左右均衡显示
    local allIslands = IslandSystem.GetIslands()
    local minX = DEPTH_MAP_BOUNDS.minX
    local minY = DEPTH_MAP_BOUNDS.minY
    local maxX = DEPTH_MAP_BOUNDS.maxX
    local maxY = DEPTH_MAP_BOUNDS.maxY

    local worldW = maxX - minX
    local worldH = maxY - minY

    -- 等比缩放
    local scale = math.min(mapAreaW / worldW, mapAreaH / worldH)
    local drawW = worldW * scale
    local drawH = worldH * scale
    local ox = (screenW - drawW) * 0.5   -- 地图左上角 x
    local oy = margin + 40 + (mapAreaH - drawH) * 0.5  -- 地图左上角 y

    -- 世界坐标 → 地图屏幕坐标
    local function W2M(wx, wy)
        local mx = ox + (wx - minX) / worldW * drawW
        local my = oy + (wy - minY) / worldH * drawH
        return mx, my
    end

    -- 缓存布局参数（供鼠标点击处理函数使用）
    mapLayout_ = { ox = ox, oy = oy, drawW = drawW, drawH = drawH,
                   minX = minX, minY = minY, worldW = worldW, worldH = worldH }

    -- ── 地图背景框 ──────────────────────────────────────────────────────
    nvgBeginPath(vg)
    nvgRoundedRect(vg, ox - 8, oy - 8, drawW + 16, drawH + 16, 6)
    nvgFillColor(vg, nvgRGBA(12, 30, 60, 180))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(80, 140, 200, 120))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- ── 网格线 ──────────────────────────────────────────────────────────
    nvgStrokeColor(vg, nvgRGBA(40, 80, 130, 50))
    nvgStrokeWidth(vg, 0.5)
    local gridStep = 2000
    local gx = math.ceil(minX / gridStep) * gridStep
    while gx < maxX do
        local sx = ox + (gx - minX) / worldW * drawW
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx, oy)
        nvgLineTo(vg, sx, oy + drawH)
        nvgStroke(vg)
        gx = gx + gridStep
    end
    local gy = math.ceil(minY / gridStep) * gridStep
    while gy < maxY do
        local sy = oy + (gy - minY) / worldH * drawH
        nvgBeginPath(vg)
        nvgMoveTo(vg, ox, sy)
        nvgLineTo(vg, ox + drawW, sy)
        nvgStroke(vg)
        gy = gy + gridStep
    end

    -- ── 水下等高线 ──────────────────────────────────────────────────────
    DrawContourLines(minX, minY, worldW, worldH, 80, W2M, true)

    -- ── 岛屿轮廓 ────────────────────────────────────────────────────────
    for id, isl in pairs(allIslands) do
        local contour = isl.contour
        if contour and #contour >= 3 then
            nvgBeginPath(vg)
            for ci, pt in ipairs(contour) do
                local wx = isl.x + pt[1] * isl.w
                local wy = isl.y + pt[2] * isl.h
                local mx, my = W2M(wx, wy)
                if ci == 1 then
                    nvgMoveTo(vg, mx, my)
                else
                    nvgLineTo(vg, mx, my)
                end
            end
            nvgClosePath(vg)
            nvgFillColor(vg, nvgRGBA(90, 165, 90, 160))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(140, 210, 140, 200))
            nvgStrokeWidth(vg, 1.0)
            nvgStroke(vg)

            -- 岛屿编号
            local cx, cy = W2M(isl.x, isl.y)
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 11)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(220, 240, 220, 200))
            nvgText(vg, cx, cy, tostring(id), nil)
        end
    end

    -- ── 船只标记（黄色三角箭头） ────────────────────────────────────────
    local bx, by = W2M(boat.x, boat.y)
    local arrowSize = 8
    local angle = boat.angle  -- 0=上(北)
    nvgSave(vg)
    nvgTranslate(vg, bx, by)
    nvgRotate(vg, angle)
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, -arrowSize)         -- 尖端（朝向方向）
    nvgLineTo(vg, -arrowSize * 0.6, arrowSize * 0.5)
    nvgLineTo(vg, arrowSize * 0.6, arrowSize * 0.5)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(255, 220, 60, 240))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(180, 140, 20, 255))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)
    nvgRestore(vg)

    -- 船只位置脉冲光圈
    local pulse = 0.5 + 0.5 * math.sin(gameTime * 4)
    local ringR = 12 + pulse * 4
    nvgBeginPath(vg)
    nvgCircle(vg, bx, by, ringR)
    nvgStrokeColor(vg, nvgRGBA(255, 220, 60, math.floor(60 + 60 * pulse)))
    nvgStrokeWidth(vg, 1.0)
    nvgStroke(vg)

    -- ── 深度标注点 ──────────────────────────────────────────────────────
    nvgFontFace(vg, "sans")
    for _, m in ipairs(MAP_DEPTH_MARKERS) do
        if not m.band then goto continue_depth end
        local band = m.band
        local px, py = W2M(m.wx, m.wy)

        -- 跳过地图范围外的点
        if px < ox or px > ox + drawW or py < oy or py > oy + drawH then
            goto continue_depth
        end

        -- 用坐标做伪随机种子，在区间内取不重复的具体值
        if not m.depthVal then
            local seed = (math.abs(m.wx) * 7 + math.abs(m.wy) * 13) % 97
            local lo = band.depthMin
            local hi = band.depthMax >= 999 and (band.depthMin + 45) or band.depthMax
            -- 在区间内避开两端，取中间70%范围内的值
            local range = (hi - lo) * 0.7
            local offset = range * (seed / 97) + (hi - lo) * 0.15
            m.depthVal = math.floor(lo + offset)
        end
        local depthStr = string.format("%dm", m.depthVal)

        -- 深度文字（居中于坐标点，带黑色描边提升可读性）
        nvgFontSize(vg, 12)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

        -- 文字描边
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 200))
        for _, off in ipairs({ {-1,0},{1,0},{0,-1},{0,1} }) do
            nvgText(vg, px + off[1], py + off[2], depthStr, nil)
        end
        -- 文字本体
        nvgFillColor(vg, nvgRGBA(230, 245, 255, 255))
        nvgText(vg, px, py, depthStr, nil)

        ::continue_depth::
    end

    -- ── 网格坐标标注 ────────────────────────────────────────────────────
    -- 每隔 2 条网格线标注一次（即每 4000 世界单位），避免过密
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 10)
    nvgFillColor(vg, nvgRGBA(100, 140, 190, 150))
    local labelStep = gridStep * 2
    -- X 轴标注（沿底边）
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    local lgx = math.ceil(minX / labelStep) * labelStep
    while lgx < maxX do
        local sx = ox + (lgx - minX) / worldW * drawW
        if sx > ox + 10 and sx < ox + drawW - 10 then
            nvgText(vg, sx, oy + drawH + 3, tostring(math.floor(lgx)), nil)
        end
        lgx = lgx + labelStep
    end
    -- Y 轴标注（沿左边）
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    local lgy = math.ceil(minY / labelStep) * labelStep
    while lgy < maxY do
        local sy = oy + (lgy - minY) / worldH * drawH
        if sy > oy + 8 and sy < oy + drawH - 8 then
            nvgText(vg, ox - 4, sy, tostring(math.floor(lgy)), nil)
        end
        lgy = lgy + labelStep
    end

    -- ── 比例尺 + 船坐标（地图框外侧底部） ──────────────────────────────
    -- 底部信息栏 Y 坐标（地图下边缘下方18px）
    local infoY = oy + drawH + 18

    -- 自动选合适档位，使比例尺屏幕长度在 60~160px 之间
    local niceSteps = { 200, 500, 1000, 2000, 5000, 10000 }
    local barWorldDist = niceSteps[#niceSteps]
    for _, s in ipairs(niceSteps) do
        if s * scale >= 60 then
            barWorldDist = s
            break
        end
    end
    local barPx  = barWorldDist * scale
    local barX   = ox + drawW - barPx - 4   -- 右对齐地图右边缘
    local barY   = infoY                     -- 框外底部

    -- 比例尺底色（半透明深色背景，增加对比度）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX - 6, barY - 14, barPx + 50, 22, 3)
    nvgFillColor(vg, nvgRGBA(8, 18, 38, 180))
    nvgFill(vg)

    -- 分段填色（浅/深交替，经典比例尺样式）
    local halfPx = barPx * 0.5
    nvgBeginPath(vg)
    nvgRect(vg, barX, barY - 5, halfPx, 9)
    nvgFillColor(vg, nvgRGBA(230, 240, 255, 230))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRect(vg, barX + halfPx, barY - 5, halfPx, 9)
    nvgFillColor(vg, nvgRGBA(80, 120, 180, 230))
    nvgFill(vg)

    -- 比例尺外框
    nvgBeginPath(vg)
    nvgRect(vg, barX, barY - 5, barPx, 9)
    nvgStrokeColor(vg, nvgRGBA(200, 220, 255, 255))
    nvgStrokeWidth(vg, 1.0)
    nvgStroke(vg)

    -- 端点刻度线
    nvgStrokeWidth(vg, 1.5)
    nvgStrokeColor(vg, nvgRGBA(220, 235, 255, 255))
    for _, tx in ipairs({ barX, barX + halfPx, barX + barPx }) do
        nvgBeginPath(vg)
        nvgMoveTo(vg, tx, barY - 8)
        nvgLineTo(vg, tx, barY + 6)
        nvgStroke(vg)
    end

    -- 刻度数字
    nvgFontSize(vg, 10)
    nvgFillColor(vg, nvgRGBA(220, 235, 255, 255))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    nvgText(vg, barX,          barY - 9, "0", nil)
    nvgText(vg, barX + halfPx, barY - 9, tostring(math.floor(barWorldDist * 0.5)), nil)
    nvgText(vg, barX + barPx,  barY - 9, tostring(barWorldDist), nil)

    -- 单位说明
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(160, 190, 230, 200))
    nvgText(vg, barX + barPx + 6, barY, "单位", nil)

    -- ── 船只世界坐标（左对齐地图左边缘） ────────────────────────────────
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 220, 80, 220))
    nvgText(vg, ox, infoY,
        string.format("船: (%.0f, %.0f)", boat.x, boat.y), nil)

    -- ── 深度图例（地图右侧，竖向色块+标注） ─────────────────────────────
    local legW    = 90   -- 图例面板宽度
    local legPad  = 10   -- 色块左内边距
    local swW     = 14   -- 色块宽度
    local swH     = 28   -- 每行色块高度
    local legX    = ox + drawW + 14   -- 紧贴地图右边缘
    local legTopY = oy + 10

    -- 背景面板
    local legH = #DEPTH_BANDS * swH + 36
    nvgBeginPath(vg)
    nvgRoundedRect(vg, legX - 4, legTopY - 4, legW + 8, legH, 5)
    nvgFillColor(vg, nvgRGBA(8, 18, 38, 200))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(80, 120, 180, 120))
    nvgStrokeWidth(vg, 1.0)
    nvgStroke(vg)

    -- 标题
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(180, 210, 255, 200))
    nvgText(vg, legX + legPad, legTopY + 10, "水深分区", nil)

    -- 各深度分区色块 + 文字
    for i, band in ipairs(DEPTH_BANDS) do
        local rowY = legTopY + 28 + (i - 1) * swH

        -- 色块（实色）
        nvgBeginPath(vg)
        nvgRoundedRect(vg, legX + legPad, rowY, swW, swH - 4, 2)
        nvgFillColor(vg, nvgRGBA(band.r, band.g, band.b, 220))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(180, 210, 255, 80))
        nvgStrokeWidth(vg, 0.5)
        nvgStroke(vg)

        -- 分区名称
        nvgFontSize(vg, 11)
        nvgFillColor(vg, nvgRGBA(200, 220, 255, 220))
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgText(vg, legX + legPad + swW + 6, rowY, band.name, nil)

        -- 深度范围
        nvgFontSize(vg, 10)
        nvgFillColor(vg, nvgRGBA(140, 170, 220, 170))
        local depthStr
        if band.depthMax >= 999 then
            depthStr = string.format(">%dm", band.depthMin)
        else
            depthStr = string.format("%d~%dm", band.depthMin, band.depthMax)
        end
        nvgText(vg, legX + legPad + swW + 6, rowY + 13, depthStr, nil)
    end

    -- ── 标题 ────────────────────────────────────────────────────────────
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 22)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 220, 255, 230))
    nvgText(vg, screenW * 0.5, margin + 16, "航海图", nil)

    -- ── 罗盘方向标 ──────────────────────────────────────────────────────
    nvgFontSize(vg, 12)
    nvgFillColor(vg, nvgRGBA(150, 180, 220, 160))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    nvgText(vg, ox + drawW * 0.5, oy - 4, "N", nil)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgText(vg, ox + drawW * 0.5, oy + drawH + 4, "S", nil)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgText(vg, ox - 6, oy + drawH * 0.5, "W", nil)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgText(vg, ox + drawW + 6, oy + drawH * 0.5, "E", nil)

    -- ── 操作提示 ────────────────────────────────────────────────────────
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(180, 200, 230, 160))
    nvgText(vg, screenW * 0.5, screenH - margin * 0.5, "[M] 关闭地图  |  点击地图查看坐标", nil)

    -- ── 点击坐标标记 ────────────────────────────────────────────────────
    if mapClickPos then
        local px, py = W2M(mapClickPos.wx, mapClickPos.wy)

        -- 十字准星
        local crossSize = 8
        nvgStrokeWidth(vg, 1.5)
        nvgStrokeColor(vg, nvgRGBA(255, 80, 80, 255))
        nvgBeginPath(vg)
        nvgMoveTo(vg, px - crossSize, py)
        nvgLineTo(vg, px + crossSize, py)
        nvgStroke(vg)
        nvgBeginPath(vg)
        nvgMoveTo(vg, px, py - crossSize)
        nvgLineTo(vg, px, py + crossSize)
        nvgStroke(vg)

        -- 圆心点
        nvgBeginPath(vg)
        nvgCircle(vg, px, py, 3)
        nvgFillColor(vg, nvgRGBA(255, 80, 80, 255))
        nvgFill(vg)

        -- 坐标文字弹窗
        local label = string.format("(%.0f, %.0f)", mapClickPos.wx, mapClickPos.wy)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 13)
        local textW = nvgTextBounds(vg, 0, 0, label, nil, nil)
        local padX, padY = 8, 5
        local popW = textW + padX * 2
        local popH = 22
        -- 弹窗位置：默认右上方，靠近地图边缘时自动翻转
        local popX = px + 10
        local popY = py - popH - 6
        if popX + popW > ox + drawW then popX = px - popW - 10 end
        if popY < oy then popY = py + 6 end

        -- 弹窗背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, popX, popY, popW, popH, 4)
        nvgFillColor(vg, nvgRGBA(20, 10, 10, 220))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(255, 80, 80, 180))
        nvgStrokeWidth(vg, 1.0)
        nvgStroke(vg)

        -- 坐标文字
        nvgFillColor(vg, nvgRGBA(255, 200, 200, 255))
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgText(vg, popX + padX, popY + popH * 0.5, label, nil)
    end

    nvgRestore(vg)
end

-- ============================================================================
-- HUD
-- ============================================================================

function DrawHUD()
    nvgFontFace(vg, "sans")

    -- 左上: 收获统计
    nvgBeginPath(vg)
    nvgRoundedRect(vg, 10, 10, 170, 55, 8)
    nvgFillColor(vg, nvgRGBA(10, 20, 40, 180))
    nvgFill(vg)

    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 220, 255, 220))
    nvgText(vg, 20, 28, "收获: " .. #caughtList .. " 条", nil)

    nvgFillColor(vg, nvgRGBA(255, 220, 100, 220))
    nvgText(vg, 20, 48, "总重: " .. FormatWeight(totalWeight), nil)

    -- 左上：时钟（收获统计面板右侧）
    local clockStr = TimeWeather.GetClockStr()
    local phase    = TimeWeather.GetPhase()
    local clockIcon = (phase == "night") and "🌙" or
                      (phase == "dawn")  and "🌅" or
                      (phase == "dusk")  and "🌆" or "☀️"
    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(220, 230, 255, 200))
    nvgText(vg, 188, 28, clockIcon .. " " .. clockStr, nil)

    -- 左上偏下: 鱼竿状态面板
    if STATE == "sailing" then
        local panelY = 75
        local rowH = 34   -- 每行高度: 文字行 + 耐久条
        nvgBeginPath(vg)
        nvgRoundedRect(vg, 10, panelY, 170, 8 + CFG.ROD_COUNT * rowH, 8)
        nvgFillColor(vg, nvgRGBA(10, 20, 40, 180))
        nvgFill(vg)

        for i = 1, CFG.ROD_COUNT do
            local rod = rods[i]
            local ry = panelY + 8 + (i - 1) * rowH
            local isActive = (i == activeRod)

            -- 选中标记
            if isActive then
                nvgBeginPath(vg)
                nvgRoundedRect(vg, 14, ry - 2, 160, rowH - 2, 4)
                nvgFillColor(vg, nvgRGBA(40, 80, 140, 100))
                nvgFill(vg)
            end

            -- 鱼竿编号
            nvgFontSize(vg, 13)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            local labelColor = isActive and nvgRGBA(255, 255, 255, 255) or nvgRGBA(160, 170, 180, 200)
            nvgFillColor(vg, labelColor)
            nvgText(vg, 20, ry + 8, "竿" .. i .. ":", nil)

            -- 状态文字
            local stText, stR, stG, stB = "待机", 130, 130, 140
            if rod.state == "trolling" then
                stText = "拖钓中"
                stR, stG, stB = 100, 255, 150
            elseif rod.state == "bite" then
                stText = "咬钩!"
                stR, stG, stB = 255, 200, 50
            elseif rod.state == "strike" then
                stText = "提竿!"
                stR, stG, stB = 255, 255, 100
            elseif rod.state == "casting" then
                stText = "抛投..."
                stR, stG, stB = 150, 200, 255
            end
            nvgFillColor(vg, nvgRGBA(stR, stG, stB, 240))
            nvgText(vg, 60, ry + 8, stText, nil)

            -- 快捷键提示（PC 端才显示）
            if not IS_MOBILE then
                nvgFontSize(vg, 10)
                nvgFillColor(vg, nvgRGBA(120, 130, 150, 150))
                nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
                nvgText(vg, 170, ry + 8, "[" .. i .. "]", nil)
            end

            -- 耐久度进度条
            local dur = rod.durability or 100
            local barX, barY, barW, barH = 20, ry + 20, 140, 5
            -- 背景
            nvgBeginPath(vg)
            nvgRoundedRect(vg, barX, barY, barW, barH, 2)
            nvgFillColor(vg, nvgRGBA(30, 30, 50, 180))
            nvgFill(vg)
            -- 填充 (颜色: 高→绿, 低→黄, 危险→红)
            local ratio = dur / 100
            local dr = ratio > 0.5 and math.floor(255 * (1 - ratio) * 2) or 255
            local dg = ratio > 0.5 and 220 or math.floor(220 * ratio * 2)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, barX, barY, barW * ratio, barH, 2)
            nvgFillColor(vg, nvgRGBA(dr, dg, 60, 220))
            nvgFill(vg)
            -- 数值
            nvgFontSize(vg, 9)
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(180, 180, 200, 160))
            nvgText(vg, 165, barY + 3, dur .. "/100", nil)
        end

        -- ── 竿型选择条 (面板底部) ──
        local rt = ROD_TYPES[equippedRodId] or ROD_TYPES[2]
        local hl = rt.secHighlight  -- 竿型主色
        local rodBarY = panelY + 8 + CFG.ROD_COUNT * rowH + 4

        -- 扩展面板背景高度
        nvgBeginPath(vg)
        nvgRoundedRect(vg, 10, rodBarY - 2, 170, 30, 4)
        nvgFillColor(vg, nvgRGBA(8, 15, 35, 200))
        nvgFill(vg)

        -- 色块 (当前竿型颜色)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, 16, rodBarY + 4, 10, 16, 2)
        nvgFillColor(vg, nvgRGBA(hl[1], hl[2], hl[3], 230))
        nvgFill(vg)

        -- 竿型名称
        nvgFontSize(vg, 12)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(hl[1], hl[2], hl[3], 255))
        nvgText(vg, 32, rodBarY + 12, rt.name, nil)

        -- 快捷键提示（PC 端才显示）
        if not IS_MOBILE then
            nvgFontSize(vg, 10)
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(120, 130, 150, 150))
            nvgText(vg, 175, rodBarY + 12, "Q / R", nil)
        end

        -- ── 鱼钩指示条 (竿型条下方) ──
        local hookLevel = PlayerData.data.equippedHook or 3
        local hookData  = HookSelector.HOOK_TYPES[hookLevel]
        local hkColor   = hookData and hookData.color or { 200, 200, 200 }
        local hookBarY  = rodBarY + 34

        nvgBeginPath(vg)
        nvgRoundedRect(vg, 10, hookBarY - 2, 170, 26, 4)
        nvgFillColor(vg, nvgRGBA(8, 15, 35, 200))
        nvgFill(vg)

        -- 鱼钩色块
        nvgBeginPath(vg)
        nvgRoundedRect(vg, 16, hookBarY + 4, 10, 14, 2)
        nvgFillColor(vg, nvgRGBA(hkColor[1], hkColor[2], hkColor[3], 210))
        nvgFill(vg)

        -- 钩名
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 11)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(hkColor[1], hkColor[2], hkColor[3], 240))
        nvgText(vg, 32, hookBarY + 11,
            (hookData and hookData.name or "中型") .. " 钩", nil)

        -- J 键提示
        if not IS_MOBILE then
            nvgFontSize(vg, 10)
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(120, 130, 150, 150))
            nvgText(vg, 175, hookBarY + 11, "J", nil)
        end

        -- ── 鱼饵指示条 (鱼钩条下方) ──
        local baitLevel = PlayerData.data.equippedBait or 0
        local baitData  = baitLevel > 0 and BaitSelector.BAIT_TYPES[baitLevel] or nil
        local btColor   = baitData and baitData.color or { 130, 130, 130 }
        local baitBarY  = hookBarY + 30

        nvgBeginPath(vg)
        nvgRoundedRect(vg, 10, baitBarY - 2, 170, 26, 4)
        nvgFillColor(vg, nvgRGBA(8, 15, 35, 200))
        nvgFill(vg)

        -- 鱼饵色块
        nvgBeginPath(vg)
        nvgCircle(vg, 21, baitBarY + 11, 6)
        nvgFillColor(vg, nvgRGBA(btColor[1], btColor[2], btColor[3], 210))
        nvgFill(vg)

        -- 饵名
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 11)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(btColor[1], btColor[2], btColor[3], 240))
        nvgText(vg, 32, baitBarY + 11,
            baitData and baitData.name or "空钩", nil)

        -- K 键提示
        if not IS_MOBILE then
            nvgFontSize(vg, 10)
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(120, 130, 150, 150))
            nvgText(vg, 175, baitBarY + 11, "K", nil)
        end
    end

    -- 右上: 状态指示
    local stateText = ""
    local stateColor = {200, 200, 200, 200}
    if STATE == "sailing" then
        if boat.cruise then
            stateText = "巡航中"
            stateColor = {80, 220, 180, 240}
        elseif AnyRodActive() then
            stateText = "拖钓航行"
            stateColor = {100, 255, 150, 220}
        else
            stateText = "航行中"
            stateColor = {100, 200, 255, 220}
        end
    elseif STATE == "fight" then
        stateText = "遛鱼中!"
        stateColor = {255, 150, 50, 255}
    end

    if stateText ~= "" then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, screenW - 140, 10, 130, 32, 8)
        nvgFillColor(vg, nvgRGBA(10, 20, 40, 180))
        nvgFill(vg)

        nvgFontSize(vg, 14)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(stateColor[1], stateColor[2], stateColor[3], stateColor[4]))
        nvgText(vg, screenW - 75, 26, stateText, nil)
    end

    -- 右上偏下: 巡航按钮提示（移动端可直接点击）
    if STATE == "sailing" then
        local cruiseY = 50
        nvgBeginPath(vg)
        nvgRoundedRect(vg, screenW - 140, cruiseY, 130, 24, 6)
        if boat.cruise then
            nvgFillColor(vg, nvgRGBA(30, 100, 80, 200))
        else
            nvgFillColor(vg, nvgRGBA(10, 20, 40, 140))
        end
        nvgFill(vg)

        nvgFontSize(vg, 12)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        if boat.cruise then
            nvgFillColor(vg, nvgRGBA(100, 255, 200, 255))
            nvgText(vg, screenW - 75, cruiseY + 12, "⛵ 巡航 ON", nil)
        else
            nvgFillColor(vg, nvgRGBA(150, 160, 170, 180))
            nvgText(vg, screenW - 75, cruiseY + 12, "⛵ 巡航 OFF", nil)
        end
        -- 注册热区（移动端点击）
        hudBtns_[#hudBtns_ + 1] = { id = "cruise", x = screenW - 140, y = cruiseY, w = 130, h = 24 }
    end

    -- 右上: 资源栏 (金钱 + 木料) — 无背景框，游离在界面外
    do
        local baseX = screenW - 10   -- 右对齐
        local baseY = 82
        local rowH  = 22
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 14)

        -- 金钱: 图标 + 数值（右对齐，图标在数值左边）
        local moneyStr = tostring(PlayerData.GetMoney())
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        -- 文字阴影
        nvgFillColor(vg, nvgRGBA(40, 20, 0, 160))
        nvgText(vg, baseX + 1, baseY + rowH * 0 + 1, moneyStr, nil)
        nvgFillColor(vg, nvgRGBA(255, 225, 100, 255))
        nvgText(vg, baseX, baseY + rowH * 0, moneyStr, nil)
        -- 图标
        local moneyW = nvgTextBounds(vg, 0, 0, moneyStr, nil, nil)
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 220, 60, 255))
        nvgText(vg, baseX - moneyW - 2, baseY + rowH * 0, "💰", nil)

        -- 木料: 图标 + 数值
        local woodStr = tostring(PlayerData.GetResource("wood"))
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(40, 20, 0, 160))
        nvgText(vg, baseX + 1, baseY + rowH * 1 + 1, woodStr, nil)
        nvgFillColor(vg, nvgRGBA(210, 175, 110, 255))
        nvgText(vg, baseX, baseY + rowH * 1, woodStr, nil)
        local woodW = nvgTextBounds(vg, 0, 0, woodStr, nil, nil)
        nvgFillColor(vg, nvgRGBA(190, 140, 70, 255))
        nvgText(vg, baseX - woodW - 2, baseY + rowH * 1, "🪵", nil)
    end



    -- 右上: 鱼群密度侦察（调试用，在燃油条下方）
    local DENSITY_LEVELS = 10
    do
        local dbg = MapSampler.DebugFishDensity(boat.x, boat.y)
        local densityCoeff = dbg.coeff
        local densityLevel = dbg.level
        local dxUI = screenW - 140
        local dyUI = 164
        local dwUI = 130
        local dhUI = 20

        nvgBeginPath(vg)
        nvgRoundedRect(vg, dxUI, dyUI, dwUI, dhUI, 6)
        nvgFillColor(vg, nvgRGBA(10, 20, 40, 180))
        nvgFill(vg)

        -- 鱼图标
        nvgFontSize(vg, 12)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 200))
        nvgText(vg, dxUI + 5, dyUI + dhUI / 2, "🐟", nil)

        -- 密度条（10格小方块）
        local blockW = 8
        local blockH = 10
        local blockGap = 1
        local blocksX = dxUI + 24
        local blocksY = dyUI + (dhUI - blockH) / 2
        local activeBars = DENSITY_LEVELS - densityLevel + 1  -- 等级1→10格亮，等级10→1格亮

        for i = 1, DENSITY_LEVELS do
            nvgBeginPath(vg)
            nvgRect(vg, blocksX + (i - 1) * (blockW + blockGap), blocksY, blockW, blockH)
            if i <= activeBars then
                -- 从绿到黄到红的渐变
                local t = (i - 1) / (DENSITY_LEVELS - 1)
                local br = math.floor(80 + 175 * t)
                local bg = math.floor(220 - 120 * t)
                nvgFillColor(vg, nvgRGBA(br, bg, 60, 220))
            else
                nvgFillColor(vg, nvgRGBA(40, 45, 60, 120))
            end
            nvgFill(vg)
        end

        -- 系数文字
        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(200, 220, 255, 180))
        nvgText(vg, dxUI + dwUI - 4, dyUI + dhUI / 2, string.format("x%.2f", densityCoeff), nil)

        -- ── 调试详情（密度条下方）──
        nvgFontSize(vg, 9)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(180, 200, 255, 200))
        local debugY = dyUI + dhUI + 4
        local lineH = 11

        nvgText(vg, dxUI, debugY, string.format("world: %.0f, %.0f", boat.x, boat.y), nil)
        debugY = debugY + lineH
        nvgText(vg, dxUI, debugY, string.format("pixel: %d, %d", dbg.px, dbg.py), nil)
        debugY = debugY + lineH
        nvgText(vg, dxUI, debugY, string.format("img: %dx%d  s=%.1f", dbg.layerW, dbg.layerH, dbg.scale), nil)
        debugY = debugY + lineH
        local boundsStr = dbg.inBounds and "IN" or "OUT!"
        local boundsColor = dbg.inBounds and nvgRGBA(100, 255, 100, 220) or nvgRGBA(255, 80, 80, 220)
        nvgFillColor(vg, boundsColor)
        nvgText(vg, dxUI, debugY, string.format("bounds: %s  R=%.3f", boundsStr, dbg.rawR), nil)
        debugY = debugY + lineH
        nvgFillColor(vg, nvgRGBA(180, 200, 255, 200))
        nvgText(vg, dxUI, debugY, string.format("lvl=%d coeff=%.2f", dbg.level, dbg.coeff), nil)
        debugY = debugY + lineH
        -- 诊断：显示数据源类型
        nvgFillColor(vg, nvgRGBA(255, 255, 100, 220))
        nvgText(vg, dxUI, debugY, "src=LuaData", nil)
    end

    -- 底部中: 速度条
    if STATE == "sailing" then
        local barW = 120
        local barH = 6
        local barX = screenW / 2 - barW / 2
        local barY = screenH - 30

        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, barY, barW, barH, 3)
        nvgFillColor(vg, nvgRGBA(30, 30, 50, 150))
        nvgFill(vg)

        local speedPct = boat.speed / CFG.BOAT_MAX_SPEED
        local barColorR = boat.cruise and 80 or 80
        local barColorG = boat.cruise and 230 or 200
        local barColorB = boat.cruise and 200 or 255
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, barY, barW * speedPct, barH, 3)
        nvgFillColor(vg, nvgRGBA(barColorR, barColorG, barColorB, 200))
        nvgFill(vg)

        nvgFontSize(vg, 11)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
        nvgFillColor(vg, nvgRGBA(180, 200, 220, 150))
        local speedLabel = string.format("%.0f kn", boat.speed * 0.5)
        if boat.cruise then speedLabel = speedLabel .. " [巡航]" end
        nvgText(vg, screenW / 2, barY - 3, speedLabel, nil)
    end

    -- 操作提示（PC 端才显示键盘提示，移动端有工具条）
    if STATE == "sailing" and not IS_MOBILE then
        nvgFontSize(vg, 12)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
        nvgFillColor(vg, nvgRGBA(180, 200, 220, 120))
        nvgText(vg, screenW / 2, screenH - 45, "左键:收线 | F:巡航 | 1/2:切鱼竿", nil)
    end

    -- 背包面板（最上层绘制）
    if inventoryOpen then
        Inventory.Draw(vg, screenW, screenH, {
            rods            = rods,
            activeRod       = activeRod,
            equippedReelId  = equippedReelId,
            sh              = screenH,
            caughtList      = caughtList,
            totalWeight     = totalWeight,
            PlayerData      = PlayerData,
            fishSheet       = imgFishSheets[1],
            fishSheet2      = imgFishSheets[2],
            fishSheet3      = imgFishSheets[3],
            fishSheet4      = imgFishSheets[4],
        })
    end

    if islandMenuOpen and dockedIsland then
        IslandMenu.Draw(vg, screenW, screenH, {
            island      = dockedIsland,
            caughtList  = caughtList,
            totalWeight = totalWeight,
            PlayerData  = PlayerData,
        }, input.mousePosition.x, input.mousePosition.y)
    end

    if questPanelOpen and dockedIsland then
        QuestPanel.Draw(vg, screenW, screenH, {
            quests      = QuestSystem.GenerateQuests(dockedIsland.id, FISH_TYPES),
            QuestSystem = QuestSystem,
            caughtList  = caughtList,
            PlayerData  = PlayerData,
            fishSheet   = imgFishSheets[1],
            fishSheet2  = imgFishSheets[2],
            fishSheet3  = imgFishSheets[3],
            fishSheet4  = imgFishSheets[4],
            islandName  = dockedIsland.name or "岛屿",
        })
        -- 右侧独立背包面板（与商店界面相同）
        RodShop.DrawBagOnly(vg, screenW, screenH, {
            PlayerData = PlayerData,
            caughtList = caughtList,
            fishSheet  = imgFishSheets[1],
            fishSheet2 = imgFishSheets[2],
            fishSheet3 = imgFishSheets[3],
            fishSheet4 = imgFishSheets[4],
            bagCursor  = QuestPanel.GetBagCursor(),
        })
    end

    if hookSelectorOpen then
        HookSelector.Draw(vg, screenW, screenH, {
            equippedHook = PlayerData.data.equippedHook,
        })
    end

    if baitSelectorOpen then
        BaitSelector.Draw(vg, screenW, screenH, {
            equippedBait = PlayerData.data.equippedBait,
        })
    end

    -- 鱼类图册（最顶层，调试用）
    if fishAtlasOpen then
        FishAtlas.Draw(vg, screenW, screenH)
    end
end

-- ============================================================================
-- 开发者鱼种选择菜单
-- ============================================================================

function DrawDevFishSelect()
    if not devFishSelect then return end

    local cx = screenW * 0.5
    local cy = screenH * 0.5
    local pw = 320   -- 面板宽度
    local lineH = 36 -- 每行高度
    local titleH = 44
    local count = #FISH_TYPES
    local ph = titleH + count * lineH + 16  -- 面板高度
    local px = cx - pw * 0.5
    local py = cy - ph * 0.5

    -- 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, screenW, screenH)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 120))
    nvgFill(vg)

    -- 面板背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px, py, pw, ph, 10)
    nvgFillColor(vg, nvgRGBA(20, 30, 50, 220))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(100, 180, 255, 180))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 标题
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 20)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 150, 255, 255))
    nvgText(vg, cx, py + titleH * 0.5, "[DEV] 选择鱼种")

    -- 鱼种列表
    for i, ft in ipairs(FISH_TYPES) do
        local ly = py + titleH + (i - 1) * lineH + lineH * 0.5
        local c = ft.color or {180, 200, 220}
        local r, g, b = c[1], c[2], c[3]

        -- 序号
        nvgFontSize(vg, 18)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 220, 100, 255))
        nvgText(vg, px + 16, ly, "[" .. i .. "]")

        -- 鱼名 (用鱼种颜色)
        nvgFillColor(vg, nvgRGBA(r, g, b, 255))
        nvgText(vg, px + 52, ly, ft.name)

        -- 难度星级
        local stars = string.rep("★", ft.diff)
        nvgFillColor(vg, nvgRGBA(255, 200, 50, 255))
        nvgText(vg, px + 120, ly, stars)

        -- 体力/拉力
        nvgFontSize(vg, 14)
        nvgFillColor(vg, nvgRGBA(180, 190, 210, 200))
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        local info = string.format("力%dkg", math.floor(ft.forceAtMax or ft.maxForce or 0))
        nvgText(vg, px + pw - 16, ly, info)
    end
end

-- ============================================================================
-- 通知
-- ============================================================================

function DrawNotification()
    if notify.timer <= 0 then return end

    local alpha = math.min(1, notify.timer / 0.5) * 255
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 18)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    local ny = screenH * 0.3

    -- 背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, screenW / 2 - 180, ny - 18, 360, 36, 8)
    nvgFillColor(vg, nvgRGBA(10, 20, 40, alpha * 0.75))
    nvgFill(vg)

    -- 文字
    nvgFillColor(vg, nvgRGBA(notify.color[1], notify.color[2], notify.color[3], alpha))
    nvgText(vg, screenW / 2, ny, notify.text, nil)
end

-- ============================================================================
-- 虚拟控件
-- ============================================================================

function DrawVirtualControls()
    if not IS_MOBILE then return end   -- PC 端不显示虚拟摇杆和动作按钮
    local jR  = CFG.JOYSTICK_R
    local jiR = CFG.JOYSTICK_INNER
    local abR = CFG.ACTION_BTN_R
    local ibR = CFG.INTERACT_BTN_R

    -- 按钮固定圆心
    local abCX = screenW - 90
    local abCY = screenH - 110
    local ibCX = screenW - 90
    local ibCY = screenH - 220

    -- ── 虚拟摇杆 ──────────────────────────────────────────────────────────────
    -- 非激活时：显示固定的幽灵底座提示区域
    -- 激活时：圆心跟随手指落点（vJoy.baseX/Y）
    local jx = vJoy.active and vJoy.baseX or 100
    local jy = vJoy.active and vJoy.baseY or (screenH - 130)

    -- 外圈（非激活时更淡）
    local jOutAlpha = vJoy.active and 55 or 28
    nvgBeginPath(vg)
    nvgCircle(vg, jx, jy, jR)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, jOutAlpha))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(255, 255, 255, jOutAlpha + 30))
    nvgStrokeWidth(vg, vJoy.active and 2 or 1.2)
    nvgStroke(vg)

    -- 内圈（摇头，跟随方向）
    local innerX = vJoy.active and vJoy.stickX or jx
    local innerY = vJoy.active and vJoy.stickY or jy
    local jiAlpha = vJoy.active and 170 or 70
    nvgBeginPath(vg)
    nvgCircle(vg, innerX, innerY, jiR)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, jiAlpha))
    nvgFill(vg)
    -- 内圈描边
    nvgBeginPath(vg)
    nvgCircle(vg, innerX, innerY, jiR)
    nvgStrokeColor(vg, nvgRGBA(255, 255, 255, jiAlpha + 40))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- ── fight 状态：右侧收线提示 ────────────────────────────────────────────
    if STATE == "fight" then
        local rAlpha = actionDown and 120 or 50
        -- 右半屏半透明遮罩提示
        nvgBeginPath(vg)
        nvgRoundedRect(vg, screenW * 0.5 + 10, screenH * 0.35,
            screenW * 0.45, screenH * 0.55, 20)
        nvgFillColor(vg, nvgRGBA(255, 180, 60, rAlpha))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(255, 200, 80, rAlpha + 40))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)
        -- 收线文字
        nvgFontFace(vg, "sans-bold")
        nvgFontSize(vg, 22)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, actionDown and 240 or 160))
        nvgText(vg, screenW * 0.725, screenH * 0.625, "收线", nil)
        nvgFontSize(vg, 13)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 100))
        nvgText(vg, screenW * 0.725, screenH * 0.625 + 26, "按住", nil)
        return  -- fight 时不绘制其他按钮
    end

    -- ── 动作按钮（右下）────────────────────────────────────────────────────
    local abPressed = actionDown
    local abFill    = abPressed and nvgRGBA(255, 210, 60, 160) or nvgRGBA(255, 210, 60, 55)
    local abStroke  = abPressed and nvgRGBA(255, 230, 100, 220) or nvgRGBA(255, 210, 60, 120)
    nvgBeginPath(vg)
    nvgCircle(vg, abCX, abCY, abR)
    nvgFillColor(vg, abFill)
    nvgFill(vg)
    nvgStrokeColor(vg, abStroke)
    nvgStrokeWidth(vg, 2.5)
    nvgStroke(vg)

    -- 动作按钮文字（根据状态动态）
    local btnLabel = "钓鱼"
    if STATE == "trolling" then btnLabel = "收线"
    elseif castState.charging then btnLabel = "抛竿" end
    nvgFontFace(vg, "sans-bold")
    nvgFontSize(vg, 16)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, abPressed and 255 or 190))
    nvgText(vg, abCX, abCY, btnLabel, nil)

    -- ── 互动按钮（右侧中部，有目标时显示）──────────────────────────────────
    local hasInteract = FindNearestIsland() or FindNearestPlank()
    if hasInteract then
        local pulse  = 0.7 + 0.3 * math.sin(gameTime * 3.5)
        local ibAp   = interactBtnDown and 180 or math.floor(80 * pulse)
        local ibSp   = interactBtnDown and 255 or math.floor(180 * pulse)

        -- 外圈脉冲
        nvgBeginPath(vg)
        nvgCircle(vg, ibCX, ibCY, ibR + 6)
        nvgStrokeColor(vg, nvgRGBA(100, 200, 255, math.floor(60 * pulse)))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)

        -- 主体
        nvgBeginPath(vg)
        nvgCircle(vg, ibCX, ibCY, ibR)
        nvgFillColor(vg, nvgRGBA(60, 160, 255, ibAp))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(120, 210, 255, ibSp))
        nvgStrokeWidth(vg, 2.5)
        nvgStroke(vg)

        -- 图标文字
        local ibLabel = FindNearestIsland() and "停靠" or "拾取"
        nvgFontFace(vg, "sans-bold")
        nvgFontSize(vg, 15)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, interactBtnDown and 255 or 210))
        nvgText(vg, ibCX, ibCY - 6, ibLabel, nil)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 11)
        nvgFillColor(vg, nvgRGBA(200, 230, 255, 160))
        nvgText(vg, ibCX, ibCY + 10, "[E]", nil)
    end
end

-- ============================================================================
-- 移动端工具条（DrawVirtualControls 之后绘制，填充 hudBtns_）
-- ============================================================================

function DrawMobileToolbar()
    if not IS_MOBILE then return end   -- PC 端不显示移动端工具条
    if STATE == "menu" then return end

    local sw, sh = screenW, screenH

    -- ── 辅助函数：绘制一个圆角图标按钮并注册热区 ───────────────────────────
    local function IconBtn(id, bx, by, bw, bh, label, active, r, g, b)
        -- 背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx, by, bw, bh, 9)
        if active then
            nvgFillColor(vg, nvgRGBA(r or 50, g or 110, b or 230, 210))
        else
            nvgFillColor(vg, nvgRGBA(10, 18, 38, 185))
        end
        nvgFill(vg)
        nvgStrokeColor(vg, active and nvgRGBA(r or 100, g or 160, b or 255, 200) or nvgRGBA(70, 85, 120, 110))
        nvgStrokeWidth(vg, 1.2)
        nvgStroke(vg)
        -- 标签
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 13)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, active and nvgRGBA(230, 240, 255, 255) or nvgRGBA(185, 200, 225, 190))
        nvgText(vg, bx + bw / 2, by + bh / 2, label, nil)
        -- 注册热区
        hudBtns_[#hudBtns_ + 1] = { id = id, x = bx, y = by, w = bw, h = bh }
    end

    -- ── 顶部中央工具条（航行状态）──────────────────────────────────────────
    -- 位置：顶部居中，避开左上 HUD (x<185) 和右上 HUD (x>sw-145)
    if STATE == "sailing" then
        local BW, BH, GAP = 62, 32, 6
        -- 工具条按钮：背包 / 地图 / 鱼册
        local tbBtns = {
            { id = "bag",   label = "🎒 背包", active = inventoryOpen  },
            { id = "map",   label = "🗺 地图",  active = mapOpen        },
            { id = "atlas", label = "📖 鱼册", active = fishAtlasOpen  },
        }
        local totalW = #tbBtns * BW + (#tbBtns - 1) * GAP
        local startX = math.floor((sw - totalW) / 2)
        local btnY   = 8
        for i, btn in ipairs(tbBtns) do
            local bx = startX + (i - 1) * (BW + GAP)
            IconBtn(btn.id, bx, btnY, BW, BH, btn.label, btn.active)
        end

        -- 暂停/主菜单按钮：顶部中央工具条右侧，小尺寸
        local pauseX = startX + totalW + GAP + 2
        local pauseW = 46
        IconBtn("pause", pauseX, 8, pauseW, BH, "⏸ 退出", false, 80, 40, 40)

        -- ── 鱼竿 1/2 切换：紧贴左侧竿型条下方 ─────────────────────────────
        -- DrawHUD 里竿型条在 panelY + 8 + ROD_COUNT*34 + 4 ≈ 75+8+68+4=155
        local rodBtnY = 160
        local RBW, RBH, RGAP = 38, 26, 4
        for i = 1, CFG.ROD_COUNT do
            local bx = 14 + (i - 1) * (RBW + RGAP)
            IconBtn("rod" .. i, bx, rodBtnY, RBW, RBH, tostring(i),
                i == activeRod, 50, 90, 180)
        end

        -- ── 竿型 ◀ / ▶ 切换：竿1/2按钮右侧 ────────────────────────────────
        local typeBtnX = 14 + CFG.ROD_COUNT * (RBW + RGAP) + 4
        local typeBtnY = rodBtnY
        local TBW, TBH = 30, 26
        IconBtn("rodtype_prev", typeBtnX,        typeBtnY, TBW, TBH, "◀", false)
        IconBtn("rodtype_next", typeBtnX + TBW + RGAP, typeBtnY, TBW, TBH, "▶", false)
    end

    -- ── 遛鱼状态：左侧详情切换 + 右上暂停 ────────────────────────────────
    if STATE == "fight" then
        -- 详情按钮（catch stats 面板 y=55+10=65，放在其下方）
        IconBtn("detail", 10, 68, 80, 26,
            fightDetailOpen and "▲ 详情" or "▼ 详情",
            fightDetailOpen, 40, 80, 200)
        -- 退出按钮（右上）
        IconBtn("pause", sw - 90, 8, 80, 26, "⏸ 退出", false, 80, 40, 40)
    end
end

-- ============================================================================
-- 引擎回调
-- ============================================================================

function GetScreenJoystickPatchString()
    return "<patch><add sel=\"/element/element[./attribute[@name='Name' and @value='Hat0']]\"><attribute name=\"Is Visible\" value=\"false\" /></add></patch>"
end
