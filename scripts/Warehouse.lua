-- ============================================================================
-- Warehouse: 仓库界面模块
-- 左侧：仓库面板（6行×4列，可翻页）
-- 右侧：背包面板（4行×4列，与商店背包相同）
-- 点击格子物品可在仓库/背包间转移
-- ============================================================================

local RodShop    = require "RodShop"
local PlayerData = require "PlayerData"

local Warehouse = {}

-- ── 常量 ────────────────────────────────────────────────────────────────────
local GRID_COLS     = 4
local BAG_ROWS      = 4
local STORE_ROWS    = 5
local SLOTS_PER_PAGE = STORE_ROWS * GRID_COLS  -- 20

-- 面板样式（复用 RodShop 的设计参数）
local PANEL_R       = 40
local TITLE_H       = 127.9
local TITLE_COLOR   = { 37, 40, 41 }     -- #252829
local BODY_COLOR    = { 242, 237, 225 }   -- #F2EDE1
local SLOT_BORDER_W = 7.6
local SLOT_BORDER_C = { 216, 218, 218 }   -- #D8DADA
local SLOT_FILL_C   = { 242, 237, 225 }   -- #F2EDE1
local SLOT_CORNER_R = 8
local SLOT_SIZE     = 127                  -- 格子尺寸（设计坐标）
local SLOT_STEP     = 140                  -- 格子间距（仓库用紧凑间距）
local BAG_SLOT_STEP = 153.5               -- 背包格子间距（与商店一致）

-- 布局（设计坐标 1920×1080）
-- 仓库面板（左侧）
local STORE_X       = 100
local STORE_Y       = 40
local STORE_W       = 665
local STORE_H       = TITLE_H + 30 + STORE_ROWS * SLOT_STEP + 30 + 50  -- ~1048
local STORE_GRID_X  = STORE_X + (STORE_W - GRID_COLS * SLOT_STEP + (SLOT_STEP - SLOT_SIZE)) * 0.5
local STORE_GRID_Y  = STORE_Y + TITLE_H + 30

-- 背包面板（右侧，与商店布局一致）
local BAG_X         = 1155.2
local BAG_Y         = 155.2
local BAG_W         = 665
local BAG_H         = 827
local BAG_GRID_X    = 1190.3
local BAG_GRID_Y    = 321.9

-- ── 内部状态 ────────────────────────────────────────────────────────────────
local open_     = false
local page_     = 1       -- 当前仓库页码（从1开始）
local hitboxes_ = {}      -- 当前帧可点击区域
local imgItem, ITEM_W, ITEM_H  -- 物品图标资源（从 RodShop 获取）
local imgSlotHL, SLOTHL_W, SLOTHL_H  -- 格子高亮底图（从 RodShop 获取）

-- 选中状态
local selBagSlot_   = nil   -- 当前选中的背包格子索引（1-based），nil=无选中
local selStoreIdx_  = nil   -- 当前选中的仓库格子索引（1-based），nil=无选中
local selAnim_      = 0     -- 选中弹性动画剩余帧数（背包）
local selStoreAnim_ = 0     -- 选中弹性动画剩余帧数（仓库）
local SEL_ANIM_TOTAL = 30
local SEL_EXTRA      = 0.04  -- 缩放增量

local function elasticOut(t)
    if t <= 0 then return 0 end
    if t >= 1 then return 1 end
    return 2^(-10*t) * math.sin((t*10 - 0.75) * (2*math.pi/3)) + 1
end

-- 物品图标映射
local ROD_ICON_SLICE  = { 9, 10, 7, 6, 8 }
local REEL_ICON_SLICE = { 4, 5, 3, 2, 1 }

-- ── 辅助函数 ────────────────────────────────────────────────────────────────
local function addHit(id, x, y, w, h)
    hitboxes_[#hitboxes_ + 1] = { id = id, x = x, y = y, w = w, h = h }
end

local function hitTest(mx, my)
    for _, box in ipairs(hitboxes_) do
        if mx >= box.x and mx <= box.x + box.w and
           my >= box.y and my <= box.y + box.h then
            return box.id
        end
    end
    return nil
end

local function drawImg(vg, handle, x, y, w, h, alpha)
    if not handle or handle <= 0 then return end
    local paint = nvgImagePattern(vg, x, y, w, h, 0, handle, alpha or 1.0)
    nvgBeginPath(vg)
    nvgRect(vg, x, y, w, h)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
end

local function drawPanel(vg, px, py, pw, ph, S, title)
    local x, y, w, h = px * S, py * S, pw * S, ph * S
    local r = PANEL_R * S
    local titleH = TITLE_H * S

    -- 阴影
    local sBlur = math.floor(24 * S)
    local sOfs  = math.floor(6 * S)
    local sPaint = nvgBoxGradient(vg, x, y + sOfs, w, h, r, sBlur,
        nvgRGBA(0, 0, 0, 90), nvgRGBA(0, 0, 0, 0))
    nvgBeginPath(vg)
    nvgRect(vg, x - sBlur, y - sBlur, w + sBlur * 2, h + sBlur * 2 + sOfs)
    nvgRoundedRect(vg, x, y, w, h, r)
    nvgPathWinding(vg, NVG_HOLE)
    nvgFillPaint(vg, sPaint)
    nvgFill(vg)

    -- 标题栏（整体填色）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, w, h, r)
    nvgFillColor(vg, nvgRGBA(TITLE_COLOR[1], TITLE_COLOR[2], TITLE_COLOR[3], 255))
    nvgFill(vg)

    -- 内容区（仅下半部分，底部圆角）
    nvgBeginPath(vg)
    nvgMoveTo(vg, x, y + titleH)
    nvgLineTo(vg, x + w, y + titleH)
    nvgLineTo(vg, x + w, y + h - r)
    nvgArcTo(vg, x + w, y + h, x + w - r, y + h, r)
    nvgLineTo(vg, x + r, y + h)
    nvgArcTo(vg, x, y + h, x, y + h - r, r)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(BODY_COLOR[1], BODY_COLOR[2], BODY_COLOR[3], 255))
    nvgFill(vg)

    -- 标题文字
    nvgFontFace(vg, "sans-bold")
    nvgFontSize(vg, 42 * S)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(220, 215, 200, 255))
    nvgText(vg, x + 30 * S, y + titleH * 0.5, title, nil)
end

local function drawSlotBg(vg, gx, gy, S)
    local sw = SLOT_SIZE * S
    local sh = SLOT_SIZE * S
    local r  = SLOT_CORNER_R * S
    local bw = SLOT_BORDER_W * S
    nvgBeginPath(vg)
    nvgRoundedRect(vg, gx, gy, sw, sh, r)
    nvgFillColor(vg, nvgRGBA(SLOT_BORDER_C[1], SLOT_BORDER_C[2], SLOT_BORDER_C[3], 255))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, gx + bw, gy + bw, sw - bw * 2, sh - bw * 2, math.max(1, r - bw))
    nvgFillColor(vg, nvgRGBA(SLOT_FILL_C[1], SLOT_FILL_C[2], SLOT_FILL_C[3], 255))
    nvgFill(vg)
end

--- 获取物品的图标切片号
local function getItemSlice(item)
    if item.type == "rod" and item.rodId then
        return ROD_ICON_SLICE[item.rodId]
    elseif item.type == "reel" and item.reelId then
        return REEL_ICON_SLICE[item.reelId]
    end
    return nil
end

--- 绘制格子中的物品图标
local function drawItemInSlot(vg, item, gx, gy, S)
    local sn = getItemSlice(item)
    if sn and imgItem and imgItem[sn] and imgItem[sn] > 0 then
        local iw = ITEM_W[sn] * S
        local ih = ITEM_H[sn] * S
        local sw = SLOT_SIZE * S
        drawImg(vg, imgItem[sn], gx + sw * 0.5 - iw * 0.5, gy + sw * 0.5 - ih * 0.5, iw, ih)
    end
end

-- ── 公开接口 ────────────────────────────────────────────────────────────────
function Warehouse.IsOpen() return open_ end

function Warehouse.Open()
    open_ = true
    page_ = 1
    selBagSlot_ = nil
    selStoreIdx_ = nil
    selAnim_ = 0
    selStoreAnim_ = 0
    -- 确保物品图标已加载
    imgItem, ITEM_W, ITEM_H = RodShop.GetItemImages()
    imgSlotHL, SLOTHL_W, SLOTHL_H = RodShop.GetSlotHighlight()
end

function Warehouse.Close()
    open_ = false
end

function Warehouse.GetMaxPages()
    local storage = PlayerData.GetStorage()
    return math.max(1, math.ceil(#storage / SLOTS_PER_PAGE))
end

-- ── 绘制 ────────────────────────────────────────────────────────────────────
function Warehouse.Draw(vg, sw, sh, ctx)
    if not open_ then return end
    hitboxes_ = {}

    local S = sh / 1080
    local PD = ctx.PlayerData

    -- 选中动画计算（背包）
    local selScale = 1.0
    if selBagSlot_ then
        if selAnim_ > 0 then
            selAnim_ = selAnim_ - 1
            local t = 1.0 - selAnim_ / SEL_ANIM_TOTAL
            selScale = 1.0 + SEL_EXTRA * elasticOut(t)
        else
            selScale = 1.0 + SEL_EXTRA
        end
    end

    -- 选中动画计算（仓库）
    local selStoreScale = 1.0
    if selStoreIdx_ then
        if selStoreAnim_ > 0 then
            selStoreAnim_ = selStoreAnim_ - 1
            local t = 1.0 - selStoreAnim_ / SEL_ANIM_TOTAL
            selStoreScale = 1.0 + SEL_EXTRA * elasticOut(t)
        else
            selStoreScale = 1.0 + SEL_EXTRA
        end
    end

    -- ══════════════════════════════════════════════════════════════════════════
    -- 左侧：仓库面板
    -- ══════════════════════════════════════════════════════════════════════════
    drawPanel(vg, STORE_X, STORE_Y, STORE_W, STORE_H, S, "仓库")

    -- 页码显示
    local maxPages = Warehouse.GetMaxPages()
    local pageStr = page_ .. " / " .. maxPages
    nvgFontFace(vg, "sans-bold")
    nvgFontSize(vg, 28 * S)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(80, 80, 80, 255))
    local pageY = (STORE_Y + STORE_H - 30) * S
    local pageCX = (STORE_X + STORE_W * 0.5) * S
    nvgText(vg, pageCX, pageY, pageStr, nil)

    -- 翻页按钮
    local arrowW = 60 * S
    local arrowH = 40 * S
    -- 上一页 ◀
    local prevX = pageCX - 120 * S
    nvgFontSize(vg, 32 * S)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    if page_ > 1 then
        nvgFillColor(vg, nvgRGBA(60, 60, 60, 255))
    else
        nvgFillColor(vg, nvgRGBA(180, 180, 180, 255))
    end
    nvgText(vg, prevX, pageY, "◀", nil)
    addHit("page_prev", prevX - arrowW * 0.5, pageY - arrowH * 0.5, arrowW, arrowH)

    -- 下一页 ▶
    local nextX = pageCX + 120 * S
    if page_ < maxPages then
        nvgFillColor(vg, nvgRGBA(60, 60, 60, 255))
    else
        nvgFillColor(vg, nvgRGBA(180, 180, 180, 255))
    end
    nvgText(vg, nextX, pageY, "▶", nil)
    addHit("page_next", nextX - arrowW * 0.5, pageY - arrowH * 0.5, arrowW, arrowH)

    -- 仓库格子
    local storage = PD.GetStorage()
    local startIdx = (page_ - 1) * SLOTS_PER_PAGE  -- 0-based offset
    local fishSheet1 = ctx.fishSheet
    local fishSheet2 = ctx.fishSheet2
    local fishSheet3 = ctx.fishSheet3
    local fishSheet4 = ctx.fishSheet4
    local slotPx = SLOT_SIZE * S

    for row = 0, STORE_ROWS - 1 do
        for col = 0, GRID_COLS - 1 do
            local gx = STORE_GRID_X * S + col * SLOT_STEP * S
            local gy = STORE_GRID_Y * S + row * SLOT_STEP * S
            drawSlotBg(vg, gx, gy, S)

            local idx = startIdx + row * GRID_COLS + col + 1  -- 1-based
            local item = storage[idx]
            local isStoreSel = (selStoreIdx_ == idx)
            if item then
                local hlW = SLOTHL_W * S
                local hlH = SLOTHL_H * S
                if isStoreSel then
                    -- 选中：缩放高亮+物品
                    local gcx = gx + hlW * 0.5
                    local gcy = gy + hlH * 0.5
                    local hlW2 = hlW * selStoreScale
                    local hlH2 = hlH * selStoreScale
                    if imgSlotHL and imgSlotHL > 0 then
                        drawImg(vg, imgSlotHL, gcx - hlW2*0.5, gcy - hlH2*0.5, hlW2, hlH2)
                    end
                    if item.type == "fish" and item.fishId then
                        local sprSize = slotPx * selStoreScale
                        local sprX = gcx - sprSize * 0.5
                        local sprY = gcy - sprSize * 0.5
                        RodShop.DrawFishSprite(vg, item.fishId, sprX, sprY, sprSize, sprSize, fishSheet1, fishSheet2, fishSheet3, fishSheet4)
                    else
                        local sn = getItemSlice(item)
                        if sn and imgItem and imgItem[sn] and imgItem[sn] > 0 then
                            local iw = ITEM_W[sn] * S * selStoreScale
                            local ih = ITEM_H[sn] * S * selStoreScale
                            drawImg(vg, imgItem[sn], gcx - iw*0.5, gcy - ih*0.5, iw, ih)
                        end
                    end
                else
                    -- 非选中：正常渲染
                    if imgSlotHL and imgSlotHL > 0 then
                        drawImg(vg, imgSlotHL, gx, gy, hlW, hlH)
                    end
                    if item.type == "fish" and item.fishId then
                        RodShop.DrawFishSprite(vg, item.fishId, gx, gy, slotPx, slotPx, fishSheet1, fishSheet2, fishSheet3, fishSheet4)
                    else
                        drawItemInSlot(vg, item, gx, gy, S)
                    end
                end
            end

            -- hitbox
            addHit("store_" .. idx, gx, gy, slotPx, slotPx)
        end
    end

    -- ══════════════════════════════════════════════════════════════════════════
    -- 右侧：背包面板
    -- ══════════════════════════════════════════════════════════════════════════
    drawPanel(vg, BAG_X, BAG_Y, BAG_W, BAG_H, S, "背包")

    -- 金钱显示
    do
        local moneyW = 305.7 * S
        local moneyH = 69.3 * S
        local moneyR = moneyH * 0.25
        local titleH = TITLE_H * S
        local moneyX = (BAG_X + BAG_W) * S - moneyW - 20 * S
        local moneyY = BAG_Y * S + (titleH - moneyH) * 0.5
        nvgBeginPath(vg)
        nvgRoundedRect(vg, moneyX, moneyY, moneyW, moneyH, moneyR)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
        nvgFill(vg)
        -- 金币图标 + 数字
        local money = PD.GetMoney and PD.GetMoney() or 0
        local coinH = moneyH * 0.72
        local coinW = RodShop.DrawCoinIcon(vg, 0, -9999, coinH) or coinH  -- 获取宽度
        local gap   = 6 * S
        nvgFontFace(vg, "sans-bold")
        nvgFontSize(vg, 32 * S)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        local moneyStr = tostring(money)
        local textW = nvgTextBounds(vg, 0, 0, moneyStr)
        local totalW = coinW + gap + textW
        local startX = moneyX + (moneyW - totalW) * 0.5
        local cy = moneyY + moneyH * 0.5
        RodShop.DrawCoinIcon(vg, startX, cy - coinH * 0.5, coinH)
        nvgFillColor(vg, nvgRGBA(255, 215, 60, 255))
        nvgText(vg, startX + coinW + gap, cy, moneyStr, nil)
    end

    -- 背包格子
    local inventory  = PD.GetInventory()
    local caughtList = ctx.caughtList or {}

    -- 构建背包显示列表
    local bagList = {}
    for _, item in ipairs(inventory) do
        local sn = getItemSlice(item)
        if sn then
            bagList[#bagList + 1] = { kind = "equip", item = item, sn = sn }
        end
    end
    for _, fish in ipairs(caughtList) do
        bagList[#bagList + 1] = { kind = "fish", fish = fish }
    end

    for row = 0, BAG_ROWS - 1 do
        for col = 0, GRID_COLS - 1 do
            local gx = BAG_GRID_X * S + col * BAG_SLOT_STEP * S
            local gy = BAG_GRID_Y * S + row * BAG_SLOT_STEP * S
            drawSlotBg(vg, gx, gy, S)

            local slot = row * GRID_COLS + col + 1
            local entry = bagList[slot]
            local isSel = (selBagSlot_ == slot)
            if entry then
                local hlW = SLOTHL_W * S
                local hlH = SLOTHL_H * S
                if isSel then
                    -- 选中：缩放高亮+物品
                    local gcx = gx + hlW * 0.5
                    local gcy = gy + hlH * 0.5
                    local hlW2 = hlW * selScale
                    local hlH2 = hlH * selScale
                    if imgSlotHL and imgSlotHL > 0 then
                        drawImg(vg, imgSlotHL, gcx - hlW2*0.5, gcy - hlH2*0.5, hlW2, hlH2)
                    end
                    if entry.kind == "equip" then
                        local sn = getItemSlice(entry.item)
                        if sn and imgItem and imgItem[sn] and imgItem[sn] > 0 then
                            local iw = ITEM_W[sn] * S * selScale
                            local ih = ITEM_H[sn] * S * selScale
                            drawImg(vg, imgItem[sn], gcx - iw*0.5, gcy - ih*0.5, iw, ih)
                        end
                    elseif entry.kind == "fish" then
                        local fishId = entry.fish.type and entry.fish.type.id
                        local sprSize = slotPx * selScale
                        local sprX = gcx - sprSize * 0.5
                        local sprY = gcy - sprSize * 0.5
                        RodShop.DrawFishSprite(vg, fishId, sprX, sprY, sprSize, sprSize, fishSheet1, fishSheet2, fishSheet3, fishSheet4)
                    end
                else
                    -- 非选中：正常渲染
                    if imgSlotHL and imgSlotHL > 0 then
                        drawImg(vg, imgSlotHL, gx, gy, hlW, hlH)
                    end
                    if entry.kind == "equip" then
                        drawItemInSlot(vg, entry.item, gx, gy, S)
                    elseif entry.kind == "fish" then
                        local fishId = entry.fish.type and entry.fish.type.id
                        RodShop.DrawFishSprite(vg, fishId, gx, gy, slotPx, slotPx, fishSheet1, fishSheet2, fishSheet3, fishSheet4)
                    end
                end
            end

            addHit("bag_" .. slot, gx, gy, slotPx, slotPx)
        end
    end

    -- ══════════════════════════════════════════════════════════════════════════
    -- 操作按钮（背包面板底部：存入仓库 + 全部存入）
    -- ══════════════════════════════════════════════════════════════════════════
    do
        local btnGap = 20 * S
        local storeBtnW = 180 * S
        local storeBtnH = 56 * S
        local totalW = storeBtnW * 2 + btnGap
        local startX = (BAG_X + BAG_W * 0.5) * S - totalW * 0.5
        local btnY = (BAG_Y + BAG_H - 80) * S

        -- 按钮1：存入仓库
        local enabled1 = (selBagSlot_ ~= nil)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, startX, btnY, storeBtnW, storeBtnH, 14 * S)
        if enabled1 then
            nvgFillColor(vg, nvgRGBA(56, 142, 60, 240))
        else
            nvgFillColor(vg, nvgRGBA(160, 160, 160, 180))
        end
        nvgFill(vg)
        nvgFontFace(vg, "sans-bold")
        nvgFontSize(vg, 26 * S)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgText(vg, startX + storeBtnW * 0.5, btnY + storeBtnH * 0.5, "存入仓库", nil)
        addHit("store_selected", startX, btnY, storeBtnW, storeBtnH)

        -- 按钮2：全部存入
        local btn2X = startX + storeBtnW + btnGap
        nvgBeginPath(vg)
        nvgRoundedRect(vg, btn2X, btnY, storeBtnW, storeBtnH, 14 * S)
        nvgFillColor(vg, nvgRGBA(33, 100, 150, 240))  -- 蓝色
        nvgFill(vg)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgText(vg, btn2X + storeBtnW * 0.5, btnY + storeBtnH * 0.5, "全部存入", nil)
        addHit("store_all", btn2X, btnY, storeBtnW, storeBtnH)
    end

    -- ══════════════════════════════════════════════════════════════════════════
    -- 返回按钮（右上角）
    -- ══════════════════════════════════════════════════════════════════════════
    local btnW = 90 * S
    local btnH = 50 * S
    local btnX = (BAG_X + BAG_W - 100) * S
    local btnY = (BAG_Y - 60) * S
    nvgBeginPath(vg)
    nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 12 * S)
    nvgFillColor(vg, nvgRGBA(37, 40, 41, 220))
    nvgFill(vg)
    nvgFontFace(vg, "sans-bold")
    nvgFontSize(vg, 26 * S)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, btnX + btnW * 0.5, btnY + btnH * 0.5, "返回", nil)
    addHit("close", btnX, btnY, btnW, btnH)
end

-- ── 鼠标点击 ────────────────────────────────────────────────────────────────
function Warehouse.HandleMouseClick(mx, my, ctx)
    if not open_ then return false, nil end

    local id = hitTest(mx, my)
    if not id then return false, nil end

    -- 关闭
    if id == "close" then
        Warehouse.Close()
        return true, { close = true }
    end

    -- 翻页
    if id == "page_prev" then
        if page_ > 1 then
            page_ = page_ - 1
            selStoreIdx_ = nil
            selStoreAnim_ = 0
        end
        return true, nil
    elseif id == "page_next" then
        local maxPages = Warehouse.GetMaxPages()
        if page_ < maxPages then
            page_ = page_ + 1
            selStoreIdx_ = nil
            selStoreAnim_ = 0
        end
        return true, nil
    end

    -- "存入仓库"按钮
    if id == "store_selected" then
        if selBagSlot_ then
            -- 重建背包列表来定位实际物品
            local inventory = PlayerData.GetInventory()
            local caughtList = ctx and ctx.caughtList or {}
            local bagList = {}
            for _, item in ipairs(inventory) do
                local sn = getItemSlice(item)
                if sn then
                    bagList[#bagList + 1] = { kind = "equip", item = item, srcIdx = #bagList + 1 }
                end
            end
            local equipCount = #bagList
            for i, fish in ipairs(caughtList) do
                bagList[#bagList + 1] = { kind = "fish", fish = fish, fishIdx = i }
            end

            local entry = bagList[selBagSlot_]
            if entry then
                if entry.kind == "equip" then
                    -- 找到该装备在 inventory 中的实际索引
                    local inv = PlayerData.GetInventory()
                    for idx, it in ipairs(inv) do
                        if it == entry.item then
                            local removed = PlayerData.RemoveInventoryItem(idx)
                            if removed then
                                PlayerData.AddStorageItem(removed)
                            end
                            break
                        end
                    end
                elseif entry.kind == "fish" then
                    -- 将鱼从 caughtList 移到仓库
                    local fishIdx = selBagSlot_ - equipCount
                    if fishIdx >= 1 and fishIdx <= #caughtList then
                        local fish = caughtList[fishIdx]
                        local storageItem = { type = "fish", fishId = fish.type and fish.type.id }
                        table.remove(caughtList, fishIdx)
                        PlayerData.AddStorageItem(storageItem)
                    end
                end
            end
            selBagSlot_ = nil
            selAnim_ = 0
        end
        return true, nil
    end

    -- "全部存入"按钮
    if id == "store_all" then
        -- 将所有背包物品移入仓库
        local inventory = PlayerData.GetInventory()
        local caughtList = ctx and ctx.caughtList or {}

        -- 先存装备（从后往前删避免索引偏移）
        for i = #inventory, 1, -1 do
            local item = inventory[i]
            if getItemSlice(item) then
                local removed = PlayerData.RemoveInventoryItem(i)
                if removed then
                    PlayerData.AddStorageItem(removed)
                end
            end
        end

        -- 再存鱼
        for i = #caughtList, 1, -1 do
            local fish = caughtList[i]
            local storageItem = { type = "fish", fishId = fish.type and fish.type.id }
            table.remove(caughtList, i)
            PlayerData.AddStorageItem(storageItem)
        end

        selBagSlot_ = nil
        selAnim_ = 0
        selStoreIdx_ = nil
        selStoreAnim_ = 0
        return true, nil
    end

    -- 仓库格子点击 → 选中/取消选中
    local storeIdx = id:match("^store_(%d+)$")
    if storeIdx then
        storeIdx = tonumber(storeIdx)
        -- 清除背包选中
        selBagSlot_ = nil
        selAnim_ = 0
        -- 检查该格子是否有物品
        local storage = PlayerData.GetStorage()
        if storeIdx >= 1 and storage[storeIdx] then
            if selStoreIdx_ == storeIdx then
                selStoreIdx_ = nil  -- 取消选中
                selStoreAnim_ = 0
            else
                selStoreIdx_ = storeIdx  -- 选中新格子
                selStoreAnim_ = SEL_ANIM_TOTAL
            end
        else
            selStoreIdx_ = nil
            selStoreAnim_ = 0
        end
        return true, nil
    end

    -- 背包格子点击 → 选中/取消选中
    local bagSlot = id:match("^bag_(%d+)$")
    if bagSlot then
        bagSlot = tonumber(bagSlot)
        -- 清除仓库选中
        selStoreIdx_ = nil
        selStoreAnim_ = 0
        -- 重建背包列表检查该格子是否有物品
        local inventory = PlayerData.GetInventory()
        local caughtList = ctx and ctx.caughtList or {}
        local totalItems = 0
        for _, item in ipairs(inventory) do
            if getItemSlice(item) then totalItems = totalItems + 1 end
        end
        totalItems = totalItems + #caughtList

        if bagSlot >= 1 and bagSlot <= totalItems then
            if selBagSlot_ == bagSlot then
                selBagSlot_ = nil  -- 取消选中
                selAnim_ = 0
            else
                selBagSlot_ = bagSlot  -- 选中新格子
                selAnim_ = SEL_ANIM_TOTAL
            end
        else
            selBagSlot_ = nil  -- 点击空格取消选中
            selAnim_ = 0
        end
        return true, nil
    end

    return false, nil
end

-- ── 按键处理 ────────────────────────────────────────────────────────────────
function Warehouse.HandleKey(key)
    if not open_ then return false end
    if key == KEY_ESCAPE then
        Warehouse.Close()
        return true, { close = true }
    end
    -- 翻页快捷键
    if key == KEY_LEFT or key == KEY_A then
        if page_ > 1 then page_ = page_ - 1 end
        return true
    elseif key == KEY_RIGHT or key == KEY_D then
        local maxPages = Warehouse.GetMaxPages()
        if page_ < maxPages then page_ = page_ + 1 end
        return true
    end
    return true  -- 吃掉其他按键，防止穿透
end

-- ── 滚轮处理 ────────────────────────────────────────────────────────────────
function Warehouse.HandleScroll(delta)
    if not open_ then return false end
    if delta > 0 then
        if page_ > 1 then page_ = page_ - 1 end
    elseif delta < 0 then
        local maxPages = Warehouse.GetMaxPages()
        if page_ < maxPages then page_ = page_ + 1 end
    end
    return true
end

return Warehouse
