-- ============================================================================
-- IslandSystem: 多图层岛屿管理模块
-- ============================================================================
-- 负责岛屿图片加载、分层渲染（含浅水/浮沫效果）、碰撞检测。
-- 渲染分为三个阶段，由 main.lua 在合适的时机分别调用：
--   Phase 1 (DrawBelow):  浅水 + 岛屿底图        → 船只之下
--   Phase 2 (DrawAbove):  石头/宝箱/植物/建筑     → 船只之上
--   Phase 3 (没有单独阶段，碰撞在 Update 中处理)
-- ============================================================================

local IslandSystem = {}

local registry = require("island_registry")

-- ── 贴图显示缩放 ──────────────────────────────────────────────────────────
local TEXTURE_SCALE = 2       -- 1=原始像素 1:1, 2=每像素显示为 2×2

-- ── 运行时数据 ──────────────────────────────────────────────────────────────
local islands = {}      -- 运行时岛屿列表 (已加载图片句柄)
local islandCount = 0

-- ── 图层渲染顺序 (Z-order，按 type 前缀分组) ──────────────────────────────
-- 同类型内按后缀数字排序（rock_1 < rock_2）
local LAYER_ORDER = { "rock", "chest", "plant", "building" }
local LAYER_PRIORITY = {}
for i, prefix in ipairs(LAYER_ORDER) do
    LAYER_PRIORITY[prefix] = i
end

-- ── 解析图层名，返回 (type, index)，如 "building_2" → ("building", 2) ──
local function parseLayer(name)
    local prefix, idx = name:match("^(%a+)_(%d+)$")
    if prefix then
        return prefix, tonumber(idx)
    end
    return name, 0
end

-- ── 排序图层 ──
local function sortLayers(a, b)
    local pa, ia = parseLayer(a)
    local pb, ib = parseLayer(b)
    local oa = LAYER_PRIORITY[pa] or 0
    local ob = LAYER_PRIORITY[pb] or 0
    if oa ~= ob then return oa < ob end
    return ia < ib
end


-- ============================================================================
-- 初始化：加载所有岛屿图片
-- ============================================================================
-- 延迟加载状态
local cachedNvg = nil           -- 缓存 nvg 上下文
local pendingPaths = {}         -- path → { island=island, layerName=layerName }
local pendingCount = 0          -- 待加载图层数量

function IslandSystem.Init(nvg)
    cachedNvg = nvg
    islands = {}
    islandCount = 0
    pendingPaths = {}
    pendingCount = 0

    local cache = GetCache()

    for id, def in pairs(registry.islands) do
        local island = {
            id      = id,
            x       = def.x,
            y       = def.y,
            w       = def.w,
            h       = def.h,
            folder  = def.folder,
            contour = def.contour or {},
            images  = {},       -- layerName → nvgImageId
            aboveLayers = {},   -- 排好序的船上图层名列表
        }

        -- 通过 GetResourceAsync 确保每张图片下载完成后再创建 NanoVG 纹理
        for _, layerName in ipairs(def.layers) do
            local path = "image/islands/" .. def.folder .. "/" .. layerName .. ".png"
            pendingCount = pendingCount + 1
            cache:GetResourceAsync("Image", path, function(resource)
                if resource then
                    local imgId = nvgCreateImage(cachedNvg, path, NVG_IMAGE_NEAREST)
                    if imgId > 0 then
                        island.images[layerName] = imgId
                    else
                        print("[IslandSystem] WARN: nvgCreateImage failed " .. path)
                    end
                else
                    print("[IslandSystem] WARN: resource not ready " .. path)
                end
                pendingCount = pendingCount - 1
                if pendingCount == 0 then
                    print("[IslandSystem] All island textures loaded")
                end
            end)
        end

        -- 构建船上图层列表（排除 base）
        local above = {}
        for _, layerName in ipairs(def.layers) do
            if layerName ~= "base" then
                table.insert(above, layerName)
            end
        end
        table.sort(above, sortLayers)
        island.aboveLayers = above

        islands[id] = island
        islandCount = islandCount + 1
    end

    print("[IslandSystem] Registered " .. islandCount .. " islands, waiting for " .. pendingCount .. " textures...")
end

--- 所有岛屿纹理是否已加载完毕
function IslandSystem.IsReady()
    return pendingCount <= 0
end


-- ============================================================================
-- Phase 1: 绘制船只之下的内容（浅水光晕 + 岛屿底图）
-- ============================================================================
-- 在 NanoVG 世界空间中调用，使用 WorldToScreen 坐标
-- @param nvg       NanoVG context
-- @param WorldToScreen  坐标转换函数
-- @param screenW, screenH  屏幕尺寸
-- @param gameTime  游戏时间（用于动画）
function IslandSystem.DrawBelow(nvg, WorldToScreen, screenW, screenH, gameTime)
    for _, island in pairs(islands) do
        local sx, sy = WorldToScreen(island.x, island.y)
        local w, h = island.w, island.h
        local dw, dh = w * TEXTURE_SCALE, h * TEXTURE_SCALE  -- 显示尺寸
        local margin = math.max(dw, dh) * 0.8

        -- 视锥裁剪
        if sx < -margin or sx > screenW + margin or sy < -margin or sy > screenH + margin then
            goto continue_below
        end

        -- ── 1. 浅水光晕 ──
        local halfDiag = math.sqrt(dw * dw + dh * dh) * 0.5
        local innerR = halfDiag * 0.5
        local outerR = halfDiag * 1.1
        local breathe = math.sin(gameTime * 0.4) * 0.08 + 1.0
        local shallowAlpha = math.floor(85 * breathe)
        local shallowGrad = nvgRadialGradient(nvg, sx, sy, innerR, outerR,
            nvgRGBA(90, 190, 180, shallowAlpha),
            nvgRGBA(90, 190, 180, 0))
        nvgBeginPath(nvg)
        nvgRect(nvg, sx - outerR, sy - outerR, outerR * 2, outerR * 2)
        nvgFillPaint(nvg, shallowGrad)
        nvgFill(nvg)

        -- ── 2. 浮沫（沿碰撞轮廓） ──
        local contour = island.contour
        local cCount = #contour
        if cCount >= 3 then
            local t = gameTime
            for i = 1, cCount do
                local pt = contour[i]
                local ptNext = contour[(i % cCount) + 1]
                -- 边缘法线方向（指向外）
                local dx = ptNext[1] - pt[1]
                local dy = ptNext[2] - pt[2]
                local len = math.sqrt(dx * dx + dy * dy)
                if len < 0.001 then len = 0.001 end
                local nx, ny = -dy / len, dx / len

                local phase = i * 2.37 + t * 0.8
                local brt = math.sin(phase) * 0.3 + 0.7
                local wave = math.sin(phase * 1.3 + t * 1.2) * 3
                local foamDist = (6 + wave) * TEXTURE_SCALE
                local fx = sx + pt[1] * dw + nx * foamDist
                local fy = sy + pt[2] * dh + ny * foamDist

                local baseR = (5 + math.sin(i * 1.73) * 2) * TEXTURE_SCALE
                local r = baseR * brt
                local alpha = math.floor(90 * brt + 30)
                nvgBeginPath(nvg)
                nvgCircle(nvg, fx, fy, r)
                nvgFillColor(nvg, nvgRGBA(230, 240, 255, alpha))
                nvgFill(nvg)

                -- 外侧小泡沫
                local outerPhase = phase + 1.5
                local outerBrt = math.sin(outerPhase) * 0.4 + 0.6
                local outerDist = foamDist + (5 + math.sin(outerPhase * 0.7) * 3) * TEXTURE_SCALE
                local ofx = sx + pt[1] * dw + nx * outerDist
                local ofy = sy + pt[2] * dh + ny * outerDist
                local or2 = (baseR * 0.5) * outerBrt
                local oAlpha = math.floor(50 * outerBrt + 15)
                nvgBeginPath(nvg)
                nvgCircle(nvg, ofx, ofy, or2)
                nvgFillColor(nvg, nvgRGBA(220, 235, 255, oAlpha))
                nvgFill(nvg)
            end
        end

        -- ── 3. 水下淡影 ──
        local baseImg = island.images["base"]
        if baseImg then
            nvgSave(nvg)
            nvgTranslate(nvg, sx, sy)
            local shadowOff = 4 * TEXTURE_SCALE
            local shadowPat = nvgImagePattern(nvg, -dw/2 + shadowOff, -dh/2 + shadowOff, dw, dh, 0, baseImg, 0.25)
            nvgBeginPath(nvg)
            nvgRect(nvg, -dw/2 + shadowOff - 2, -dh/2 + shadowOff - 2, dw + 4, dh + 4)
            nvgFillPaint(nvg, shadowPat)
            nvgFill(nvg)

            -- ── 4. 岛屿底图 ──
            local pat = nvgImagePattern(nvg, -dw/2, -dh/2, dw, dh, 0, baseImg, 1.0)
            nvgBeginPath(nvg)
            nvgRect(nvg, -dw/2, -dh/2, dw, dh)
            nvgFillPaint(nvg, pat)
            nvgFill(nvg)
            nvgRestore(nvg)
        end

        ::continue_below::
    end
end


-- ============================================================================
-- Phase 2: 绘制船只之上的内容（石头/宝箱/植物/建筑）
-- ============================================================================
function IslandSystem.DrawAbove(nvg, WorldToScreen, screenW, screenH, gameTime)
    for _, island in pairs(islands) do
        local sx, sy = WorldToScreen(island.x, island.y)
        local dw, dh = island.w * TEXTURE_SCALE, island.h * TEXTURE_SCALE
        local margin = math.max(dw, dh) * 0.8

        if sx < -margin or sx > screenW + margin or sy < -margin or sy > screenH + margin then
            goto continue_above
        end

        for _, layerName in ipairs(island.aboveLayers) do
            local imgId = island.images[layerName]
            if imgId then
                nvgSave(nvg)
                nvgTranslate(nvg, sx, sy)

                local pat = nvgImagePattern(nvg, -dw/2, -dh/2, dw, dh, 0, imgId, 1.0)
                nvgBeginPath(nvg)
                nvgRect(nvg, -dw/2, -dh/2, dw, dh)
                nvgFillPaint(nvg, pat)
                nvgFill(nvg)
                nvgRestore(nvg)
            end
        end

        ::continue_above::
    end
end


-- ============================================================================
-- 碰撞检测：点是否在岛屿碰撞区域内（射线法点在多边形内判定）
-- ============================================================================
-- @param wx, wy  世界坐标
-- @return island table or nil
function IslandSystem.CheckCollision(wx, wy)
    for _, island in pairs(islands) do
        -- 快速 AABB 排除（使用显示尺寸）
        local dx = wx - island.x
        local dy = wy - island.y
        local halfW = island.w * TEXTURE_SCALE * 0.5
        local halfH = island.h * TEXTURE_SCALE * 0.5
        if math.abs(dx) > halfW or math.abs(dy) > halfH then
            goto continue_collision
        end

        -- 将世界坐标转为归一化坐标 (-0.5 ~ 0.5)
        -- contour 数据基于原始 w/h 归一化, 所以这里也用原始尺寸
        local nx = dx / (island.w * TEXTURE_SCALE)
        local ny = dy / (island.h * TEXTURE_SCALE)
        -- AABB 用显示尺寸过滤范围, 归一化也用显示尺寸 —— contour 边界 ±0.45 左右
        -- 因此二者一致: 世界偏移 / 显示尺寸 = 归一化

        -- 射线法判断点在多边形内
        local contour = island.contour
        local n = #contour
        if n < 3 then goto continue_collision end

        local inside = false
        local j = n
        for i = 1, n do
            local xi, yi = contour[i][1], contour[i][2]
            local xj, yj = contour[j][1], contour[j][2]
            if ((yi > ny) ~= (yj > ny)) and (nx < (xj - xi) * (ny - yi) / (yj - yi) + xi) then
                inside = not inside
            end
            j = i
        end

        if inside then
            return island
        end

        ::continue_collision::
    end
    return nil
end


-- ============================================================================
-- 点到线段最短距离的平方（内部工具函数）
-- ============================================================================
local function pointToSegSq(px, py, ax, ay, bx, by)
    local abx, aby = bx - ax, by - ay
    local apx, apy = px - ax, py - ay
    local ab2 = abx * abx + aby * aby
    if ab2 < 1e-12 then
        return apx * apx + apy * apy
    end
    local t = (apx * abx + apy * aby) / ab2
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    local cx, cy = ax + abx * t, ay + aby * t
    local dx, dy = px - cx, py - cy
    return dx * dx + dy * dy
end

-- ============================================================================
-- 寻找最近岛屿（基于碰撞点到轮廓线段的最短距离）
-- ============================================================================
-- @param probes   碰撞探测点数组 { {x,y}, {x,y}, ... }
-- @param maxDist  最大搜索距离（世界像素）
-- @return island table or nil, distance
function IslandSystem.FindNearest(probes, maxDist)
    local bestIsland, bestDistSq = nil, (maxDist or 200) * (maxDist or 200)

    for _, island in pairs(islands) do
        local contour = island.contour
        local cn = #contour
        if cn < 3 then goto continue_find end

        -- AABB 快速排除：任一探测点在岛屿扩展范围内才继续
        local halfW = island.w * TEXTURE_SCALE * 0.5 + maxDist
        local halfH = island.h * TEXTURE_SCALE * 0.5 + maxDist
        local inRange = false
        for _, p in ipairs(probes) do
            if math.abs(p[1] - island.x) <= halfW and math.abs(p[2] - island.y) <= halfH then
                inRange = true
                break
            end
        end
        if not inRange then goto continue_find end

        -- 遍历轮廓线段，计算每个探测点到每条边的最短距离
        for _, p in ipairs(probes) do
            local px, py = p[1], p[2]
            local j = cn
            for i = 1, cn do
                -- 轮廓点从归一化坐标转为世界坐标
                local ax = island.x + contour[j][1] * island.w * TEXTURE_SCALE
                local ay = island.y + contour[j][2] * island.h * TEXTURE_SCALE
                local bx = island.x + contour[i][1] * island.w * TEXTURE_SCALE
                local by = island.y + contour[i][2] * island.h * TEXTURE_SCALE

                local dSq = pointToSegSq(px, py, ax, ay, bx, by)
                if dSq < bestDistSq then
                    bestDistSq = dSq
                    bestIsland = island
                end
                j = i
            end
        end

        ::continue_find::
    end

    return bestIsland, bestIsland and math.sqrt(bestDistSq) or nil
end


-- ============================================================================
-- 获取岛屿列表（供外部遍历）
-- ============================================================================
function IslandSystem.GetIslands()
    return islands
end

function IslandSystem.GetIsland(id)
    return islands[id]
end

function IslandSystem.GetCount()
    return islandCount
end


return IslandSystem
