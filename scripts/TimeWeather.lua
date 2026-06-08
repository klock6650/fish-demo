-- TimeWeather.lua
-- 游戏时间与天气系统
-- 1 游戏天 = DAY_DURATION 真实秒（默认 24 分钟 = 1440 秒）
-- tod（time-of-day）: 0.0 = 午夜, 0.25 = 凌晨6点, 0.5 = 正午, 0.75 = 傍晚18点, 1.0 = 午夜

local M = {}

-- ── 配置 ─────────────────────────────────────────────────────────────
M.DAY_DURATION = 24 * 60   -- 真实秒/游戏天（24 分钟）
local tod_     = 0.35      -- 初始时刻：上午（0.35 ≈ 8:24）

-- ── 天空色调关键帧 ────────────────────────────────────────────────────
-- { tod, overlay_r, overlay_g, overlay_b, overlay_a }
-- 叠加层使用「变暗」思路：白天不叠加，夜晚叠加深蓝，日出/落叠加暖色
-- alpha 控制强度，白天核心时段保持 0（完全不遮挡画面）
local SKY_KEYS = {
    { 0.000,  10,  20,  70, 160 },   -- 00:00  深夜（蓝黑）
    { 0.208,  15,  20,  80, 140 },   -- 05:00  黎明前
    { 0.250, 245,  60,   0,  55 },   -- 06:00  日出（深橙红，高饱和）
    { 0.292, 245, 110,   5,  18 },   -- 07:00  清晨暖橙（快速消退）
    { 0.333,   0,   0,   0,   0 },   -- 08:00  完全透明
    { 0.500,   0,   0,   0,   0 },   -- 12:00  正午（无叠加）
    { 0.625,   0,   0,   0,   0 },   -- 15:00  完全透明
    { 0.667, 235,  95,   0,  20 },   -- 16:00  午后偏橙（轻微）
    { 0.708, 255,  55,   0,  60 },   -- 17:00  黄昏（高饱和橙）
    { 0.750, 175,  22,   0, 100 },   -- 18:00  日落（深橙红）
    { 0.792,  25,  15,  55, 130 },   -- 19:00  入夜
    { 0.833,  10,  18,  65, 150 },   -- 20:00  夜晚
    { 1.000,  10,  20,  70, 160 },   -- 24:00  深夜（回到起点）
}

-- ── 地平线色调关键帧（渐变底部色，偏暖偏浅） ─────────────────────────
local HORIZON_KEYS = {
    { 0.000,  20,  40,  90, 100 },   -- 00:00  深夜地平线（蓝紫，比顶部浅）
    { 0.208,  25,  30,  90,  85 },   -- 05:00  黎明前
    { 0.250, 245, 110,  15,  75 },   -- 06:00  日出地平线（暖橙）
    { 0.292, 255, 175,  50,  25 },   -- 07:00  清晨暖黄
    { 0.333,   0,   0,   0,   0 },   -- 08:00  透明
    { 0.625,   0,   0,   0,   0 },   -- 15:00  透明
    { 0.667, 255, 130,  30,  28 },   -- 16:00  午后橙（轻微）
    { 0.708, 255,  65,   5,  85 },   -- 17:00  黄昏地平线（深橙）
    { 0.750, 190,  35,   0, 120 },   -- 18:00  日落地平线
    { 0.792,  30,  20,  65,  95 },   -- 19:00  入夜
    { 0.833,  18,  35,  80, 100 },   -- 20:00  夜晚地平线
    { 1.000,  20,  40,  90, 100 },   -- 24:00  深夜（回起点）
}

-- ── 工具：线性插值 ────────────────────────────────────────────────────
local function lerp(a, b, t) return a + (b - a) * t end

local function sampleKeys(keys, tod)
    for i = 1, #keys - 1 do
        local k0 = keys[i]
        local k1 = keys[i + 1]
        if tod >= k0[1] and tod <= k1[1] then
            local t = (tod - k0[1]) / (k1[1] - k0[1])
            return
                math.floor(lerp(k0[2], k1[2], t)),
                math.floor(lerp(k0[3], k1[3], t)),
                math.floor(lerp(k0[4], k1[4], t)),
                math.floor(lerp(k0[5], k1[5], t))
        end
    end
    local k = keys[1]
    return k[2], k[3], k[4], k[5]
end

local function sampleSkyKeys(tod)
    return sampleKeys(SKY_KEYS, tod)
end

-- ── 公开接口 ──────────────────────────────────────────────────────────

-- 每帧推进时间
function M.Update(dt)
    tod_ = (tod_ + dt / M.DAY_DURATION) % 1.0
end

-- 直接设置时刻（0~1）
function M.SetTOD(v)
    tod_ = math.max(0, math.min(0.9999, v))
end

-- 当前 tod（0~1）
function M.GetTOD()
    return tod_
end

-- 当前游戏小时（0~24 浮点）
function M.GetHour()
    return tod_ * 24
end

-- 返回格式化时间字符串 "HH:MM"
function M.GetClockStr()
    local totalMin = math.floor(tod_ * 24 * 60)
    local h = math.floor(totalMin / 60) % 24
    local m = totalMin % 60
    return string.format("%02d:%02d", h, m)
end

-- 当前阶段：night / dawn / day / dusk
function M.GetPhase()
    local h = tod_ * 24
    if h >= 6 and h < 7.5  then return "dawn"
    elseif h >= 7.5 and h < 17 then return "day"
    elseif h >= 17 and h < 19.5 then return "dusk"
    else return "night"
    end
end

-- 是否白天（用于游戏逻辑判断）
function M.IsDay()
    local phase = M.GetPhase()
    return phase == "day" or phase == "dawn" or phase == "dusk"
end

-- 夜晚强度（0 = 完全白天，1 = 完全夜晚），用于灯光亮度
-- 08:00-16:00 = 0，16:00-19:00 渐亮，19:00-05:00 = 1，05:00-08:00 渐灭
function M.GetNightIntensity()
    local h = tod_ * 24
    if h >= 8 and h < 16 then
        return 0
    elseif h >= 16 and h < 19 then
        return (h - 16) / 3
    elseif h >= 19 or h < 5 then
        return 1
    else  -- 5:00 ~ 8:00
        return 1 - (h - 5) / 3
    end
end

-- 天空叠加层颜色（r,g,b,a）— 顶部色
function M.GetOverlay()
    return sampleSkyKeys(tod_)
end

-- 地平线叠加层颜色（r,g,b,a）— 底部色，用于上下渐变
function M.GetHorizonOverlay()
    return sampleKeys(HORIZON_KEYS, tod_)
end

-- 太阳/月亮的弧形轨迹位置（0~1 的归一化进度）
-- 返回 sx, sy（归一化屏幕坐标 0~1）
function M.GetCelestialPos()
    local phase = M.GetPhase()
    local progress   -- 0=地平线左 1=地平线右

    if phase == "dawn" or phase == "day" or phase == "dusk" then
        -- 白天：tod 0.25(06:00) → 0.75(18:00) 映射到 0→1
        progress = math.max(0, math.min(1, (tod_ - 0.25) / 0.5))
    else
        -- 夜晚：tod 0.75(18:00) → 1.25(06:00，跨午夜) 映射到 0→1
        local t = tod_ >= 0.75 and (tod_ - 0.75) or (tod_ + 0.25)
        progress = math.max(0, math.min(1, t / 0.5))
    end

    -- 弧形轨迹（抛物线）
    local sx = 0.08 + progress * 0.84              -- 水平：左8% ~ 右92%
    local arc = 1 - (progress * 2 - 1)^2           -- 弧高：中间最高
    local sy = 0.42 - arc * 0.32                   -- 垂直：顶部约 10%

    return sx, sy
end

-- 太阳/月亮的颜色与光晕半径
function M.GetCelestialStyle()
    local phase = M.GetPhase()
    local h = tod_ * 24

    if phase == "night" then
        -- 月亮：银白色，小光晕
        return { 230, 235, 255 }, { 200, 210, 240, 40 }, 10, 28
        --  body_rgb,             glow_rgba,              r,  glow_r
    elseif phase == "dawn" then
        -- 日出：橙红
        local t = math.max(0, (h - 6) / 1.5)
        local gr = math.floor(lerp(255, 255, t))
        local gg = math.floor(lerp(80,  200, t))
        return { gr, gg, 40 }, { 255, 140, 30, 60 }, 14, 38
    elseif phase == "dusk" then
        -- 日落：深橙
        local t = math.max(0, (h - 17) / 2.5)
        local gg = math.floor(lerp(160, 60, t))
        return { 255, gg, 20 }, { 255, 100, 20, 70 }, 14, 36
    else
        -- 白天：明黄
        return { 255, 240, 120 }, { 255, 230, 80, 35 }, 16, 42
    end
end

-- 夜晚星星随机种子列表（只生成一次，外部维护）
-- 返回 n 颗星星的归一化坐标 + 闪烁偏移
function M.GenStars(n)
    local stars = {}
    math.randomseed(42)   -- 固定种子，每次相同
    for i = 1, n do
        stars[i] = {
            x      = math.random() * 0.98 + 0.01,
            y      = math.random() * 0.45,
            size   = math.random() * 1.2 + 0.5,
            phase  = math.random() * math.pi * 2,
        }
    end
    return stars
end

return M
