-- ============================================================================
-- WeatherRain.lua — 天气系统：雨天粒子与环境效果
-- 从 main.lua 拆分，减少 local 变量占用
-- ============================================================================

local M = {}

-- ── 配置常量 ──
local RAIN_COUNT = 180

-- ── 内部状态 ──
local _drops        = {}
local _intensity    = 0        -- 0.0 ~ 1.0
local _mode         = "sunny"  -- "sunny" | "rain"
local _timer        = 0
local _inited       = false

-- ============================================================================
-- Public API
-- ============================================================================

--- 获取当前天气模式
---@return string "sunny"|"rain"
function M.GetMode()
    return _mode
end

--- 获取当前雨强度 (0~1)
---@return number
function M.GetIntensity()
    return _intensity
end

--- 每帧更新
---@param dt number
---@param screenW number
---@param screenH number
function M.Update(dt, screenW, screenH)
    -- 首次初始化
    if not _inited then
        _inited = true
        _mode   = "sunny"
        _timer  = 300 + math.random() * 300
    end

    -- 天气状态机计时
    _timer = _timer - dt
    if _timer <= 0 then
        M._rollWeather()
    end

    -- 平滑过渡
    local target = _mode == "rain" and 1.0 or 0.0
    _intensity = _intensity + (target - _intensity) * math.min(1, dt * 1.5)

    if _intensity < 0.01 then return end

    if #_drops == 0 then M._initDrops() end

    local WIND = 0.20
    for _, d in ipairs(_drops) do
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

--- 渲染雨天效果
---@param g any  NanoVG context
---@param screenW number
---@param screenH number
function M.Draw(g, screenW, screenH)
    if _intensity < 0.01 then return end
    local t = _intensity

    -- 1. 雨天压暗叠加层
    nvgBeginPath(g)
    nvgRect(g, 0, 0, screenW, screenH)
    nvgFillColor(g, nvgRGBA(18, 28, 52, math.floor(t * 115)))
    nvgFill(g)

    -- 2. 底部雾气
    local fogPaint = nvgLinearGradient(g,
        0, screenH * 0.52, 0, screenH,
        nvgRGBA(35, 50, 75, 0),
        nvgRGBA(25, 40, 65, math.floor(t * 95)))
    nvgBeginPath(g)
    nvgRect(g, 0, screenH * 0.52, screenW, screenH * 0.48)
    nvgFillPaint(g, fogPaint)
    nvgFill(g)

    -- 3. 雨滴条纹
    if #_drops == 0 then return end
    local WIND = 0.20
    nvgLineCap(g, NVG_ROUND)
    for _, d in ipairs(_drops) do
        local a = math.floor(d.alpha * t)
        nvgBeginPath(g)
        nvgMoveTo(g, d.x, d.y)
        nvgLineTo(g, d.x + d.len * WIND, d.y + d.len)
        nvgStrokeColor(g, nvgRGBA(195, 218, 248, a))
        nvgStrokeWidth(g, 0.85)
        nvgStroke(g)
    end
    nvgLineCap(g, NVG_BUTT)

    -- 4. 顶部暗云压顶渐变
    local cloudPaint = nvgLinearGradient(g,
        0, 0, 0, screenH * 0.30,
        nvgRGBA(10, 18, 38, math.floor(t * 80)),
        nvgRGBA(10, 18, 38, 0))
    nvgBeginPath(g)
    nvgRect(g, 0, 0, screenW, screenH * 0.30)
    nvgFillPaint(g, cloudPaint)
    nvgFill(g)
end

-- ============================================================================
-- Internal
-- ============================================================================

function M._initDrops()
    math.randomseed(os.time and os.time() or 12345)
    _drops = {}
    for i = 1, RAIN_COUNT do
        _drops[i] = {
            x     = math.random() * 1920,
            y     = math.random() * 1080,
            spd   = math.random() * 260 + 340,
            len   = math.random() * 13 + 7,
            alpha = math.random() * 55 + 65,
        }
    end
end

function M._rollWeather()
    if math.random() < 1 / 3 then
        _mode  = "rain"
        _timer = 180 + math.random() * 180
        if ShowNotify then ShowNotify("开始下雨了 🌧", 130, 170, 230) end
    else
        _mode  = "sunny"
        _timer = 360 + math.random() * 240
        if _intensity > 0.05 and ShowNotify then  -- global from main
            ShowNotify("雨停了，天晴了 ☀", 255, 220, 80)
        end
    end
end

return M
