-- ============================================================================
-- WaveSprites.lua — 海浪精灵系统 (手绘风浪花漂浮在海面上)
-- 从 main.lua 拆分，减少 local 变量占用
-- ============================================================================

local M = {}

-- ── 配置常量 ──
local WAVE_MAX           = 18
local WAVE_SPAWN_CD      = 0.8
local WAVE_CURRENT_ANGLE = math.pi * 0.5  -- 向下

-- ── 内部状态 ──
local _sprites     = {}
local _spawnTimer  = 0

-- ── 外部依赖（由 Init 注入） ──
local _waveImages  = nil   -- 引用 main 中的 waveImages table

-- ============================================================================
-- Public API
-- ============================================================================

--- 注入 waveImages 引用（在 Start 中加载图片后调用一次）
---@param images table  nvgCreateImage handle 数组
function M.SetImages(images)
    _waveImages = images
end

--- 初始化/重置海浪精灵
---@param camX number  相机世界X
---@param camY number  相机世界Y
function M.Init(camX, camY)
    _sprites = {}
    _spawnTimer = 0
    for _ = 1, WAVE_MAX do
        M._spawn(camX, camY, true)
    end
end

--- 每帧更新
---@param dt number  时间步长
---@param camX number  相机世界X
---@param camY number  相机世界Y
function M.Update(dt, camX, camY)
    -- 更新现有海浪
    for i = #_sprites, 1, -1 do
        local w = _sprites[i]
        w.age = w.age + dt
        if w.age >= w.life then
            table.remove(_sprites, i)
        else
            w.x = w.x + w.dx * dt
            w.y = w.y + w.dy * dt
            w.frameTimer = w.frameTimer + dt
        end
    end

    -- 补充新海浪
    _spawnTimer = _spawnTimer + dt
    if _spawnTimer >= WAVE_SPAWN_CD and #_sprites < WAVE_MAX then
        _spawnTimer = 0
        M._spawn(camX, camY, false)
    end
end

--- 绘制所有海浪精灵
---@param g any  NanoVG context
---@param WorldToScreen fun(wx:number,wy:number):number,number
---@param screenW number
---@param screenH number
function M.Draw(g, WorldToScreen, screenW, screenH)
    if not _waveImages then return end
    local frameCount = #_waveImages
    if frameCount == 0 then return end

    for _, w in ipairs(_sprites) do
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
            local imgId = _waveImages[frameIdx]
            if imgId and imgId > 0 then
                nvgSave(g)
                nvgTranslate(g, sx, sy)
                nvgRotate(g, w.angle)
                nvgGlobalAlpha(g, alpha)

                local pat = nvgImagePattern(g, -w.w/2, -w.h/2, w.w, w.h, 0, imgId, 1.0)
                nvgBeginPath(g)
                nvgRect(g, -w.w/2, -w.h/2, w.w, w.h)
                nvgFillPaint(g, pat)
                nvgFill(g)

                nvgRestore(g)
            end
        end
    end
end

-- ============================================================================
-- Internal
-- ============================================================================

---@param camX number
---@param camY number
---@param randomAge boolean
function M._spawn(camX, camY, randomAge)
    if not _waveImages or #_waveImages == 0 then return end

    local baseW = 167
    local baseH = 66
    local scaleMul = 0.8 + math.random() * 0.6

    local frameCount = #_waveImages
    local animSpeed = 4 + math.random() * 3
    local cycleDur = frameCount / animSpeed
    local fi = 0.5
    local fo = 1.0
    local maxLife = fi + cycleDur + fo
    local age = randomAge and (math.random() * maxLife) or 0

    local spawnRange = 900
    local wx = camX + (math.random() - 0.5) * spawnRange * 2
    local wy = camY + (math.random() - 0.5) * spawnRange * 2

    local driftAngle = WAVE_CURRENT_ANGLE
    local driftSpeed = 7.5 + math.random() * 9

    local facing = 0

    table.insert(_sprites, {
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
        frameTimer = math.random() * frameCount / animSpeed,
        animSpeed = animSpeed,
    })
end

return M
