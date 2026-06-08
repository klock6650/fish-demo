-- ============================================================================
-- CabinSystem: 船舱装备界面模块
-- ============================================================================
-- 左侧：背包面板（与仓库一致的背包面板）
-- 右侧：船舱面板（12个专用格子，特定物品类型）
-- 布局：
--   左列4格（上→下）：鱼竿、渔线轮、鱼钩、鱼饵
--   右列4格（上→下）：鱼竿、渔线轮、鱼钩、鱼饵
--   中上2格：灯具（上）、声纳（下）
--   中下2格：船锚（左）、采饵器（右）
-- ============================================================================

local RodShop    = require "RodShop"
local PlayerData = require "PlayerData"

local CabinSystem = {}

-- ── 物品类型常量 ────────────────────────────────────────────────────────────
-- 每个船舱格子接受的物品类型
CabinSystem.ITEM_TYPES = {
    "rod",            -- 鱼竿
    "reel",           -- 渔线轮
    "hook",           -- 鱼钩
    "bait",           -- 鱼饵
    "lamp",           -- 灯具
    "sonar",          -- 声纳
    "anchor",         -- 船锚
    "bait_collector", -- 采饵器
}

-- 物品类型中文名（用于格子占位提示）
local TYPE_LABELS = {
    rod            = "鱼竿",
    reel           = "渔轮",
    hook           = "鱼钩",
    bait           = "鱼饵",
    lamp           = "灯具",
    sonar          = "声纳",
    anchor         = "船锚",
    bait_collector = "采饵器",
}

-- ── 12个格子的定义 ──────────────────────────────────────────────────────────
-- 每个格子: { slotType = "xxx", col, row }
-- 布局基于1080p设计坐标，相对于船舱面板内容区左上角
-- 格子索引 1~12

-- 左列 (x=col0), 右列 (x=col2), 中列上 (x=col1), 中列下 (x=col1 split)
local SLOT_DEFS = {
    -- 左列（从上到下）
    { slotType = "rod",  col = 0, row = 0 },  -- 1
    { slotType = "reel", col = 0, row = 1 },  -- 2
    { slotType = "hook", col = 0, row = 2 },  -- 3
    { slotType = "bait", col = 0, row = 3 },  -- 4
    -- 右列（从上到下）
    { slotType = "rod",  col = 2, row = 0 },  -- 5
    { slotType = "reel", col = 2, row = 1 },  -- 6
    { slotType = "hook", col = 2, row = 2 },  -- 7
    { slotType = "bait", col = 2, row = 3 },  -- 8
    -- 中上（灯具、声纳）
    { slotType = "lamp",  col = 1, row = 0 },  -- 9
    { slotType = "sonar", col = 1, row = 1 },  -- 10
    -- 中下（船锚、采饵器）
    { slotType = "anchor",         col = 1, row = 3, subCol = 0 },  -- 11
    { slotType = "bait_collector", col = 1, row = 3, subCol = 1 },  -- 12
}

-- ── 面板样式（复用 Warehouse/RodShop 设计参数）─────────────────────────────
local PANEL_R       = 40
local TITLE_H       = 127.9
local TITLE_COLOR   = { 37, 40, 41 }
local BODY_COLOR    = { 242, 237, 225 }
local SLOT_BORDER_W = 7.6
local SLOT_BORDER_C = { 216, 218, 218 }     -- 背包格子边框
local SLOT_FILL_C   = { 242, 237, 225 }     -- 背包格子填充
local CABIN_SLOT_BORDER_C  = { 70, 70, 70 }   -- #464646 船舱格子边框
local CABIN_SLOT_FILL_C    = { 132, 132, 132 } -- #848484 船舱格子填充（空）
local CABIN_SLOT_LOADED_C  = { 70, 70, 70 }    -- #464646 船舱格子填充（已装载）
local SLOT_CORNER_R = 8
local SLOT_SIZE     = 127
local SLOT_STEP     = 153.5

-- 船舱面板布局（设计坐标 1920×1080，与商店/仓库对齐）
local CABIN_X       = 100
local CABIN_Y       = 40
local CABIN_W       = 665
local CABIN_H       = 867

-- 船舱格子起始（相对于面板）
local CABIN_GRID_MARGIN_X = 30
local CABIN_GRID_MARGIN_Y = 20   -- 标题栏下方留白

-- 内容区宽度 = CABIN_W - 2*CABIN_GRID_MARGIN_X = 605
-- 三列X坐标（设计坐标，相对内容区左边）
-- 左右对称：左=30, 右=contentW-30-SLOT_SIZE=605-30-127=448
local COL_POSITIONS = {
    [0] = 30,    -- 左列
    [1] = 239,   -- 中列（居中时由getCabinSlotPos动态计算，此值仅备用）
    [2] = 448,   -- 右列（与左列关于中轴对称）
}

-- 行Y坐标（设计坐标，相对内容区顶部，步长=135）
local ROW_POSITIONS = {
    [0] = 0,
    [1] = 135,
    [2] = 270,
    [3] = 405,
}

-- 中下两格的sub列偏移
local SUB_COL_OFFSET = 155

-- 背包面板（右侧，与仓库背包一致）
local BAG_X         = 1155.2
local BAG_Y         = 155.2
local BAG_W         = 665
local BAG_H         = 827
local BAG_GRID_X    = 1190.3
local BAG_GRID_Y    = 321.9
local BAG_COLS      = 4
local BAG_ROWS      = 4
local BAG_SLOT_STEP = 153.5

-- ── 船舱格子对应的水印切片映射（索引=slot号, 值=切片号）────────────────────
local SLOT_WATERMARK = {
    4, 3, 1, 2,   -- 左列 slots 1-4: 切片4,3,1,2
    4, 3, 1, 2,   -- 右列 slots 5-8: 切片4,3,1,2
    8, 7,          -- 中上 slots 9,10: 切片8,7
    6, 5,          -- 中下 slots 11,12: 切片6,5
}

-- ── 内部状态 ────────────────────────────────────────────────────────────────
local open_     = false
local hitboxes_ = {}
local imgItem, ITEM_W, ITEM_H
local imgHook, HOOK_W, HOOK_H
local imgBait, BAIT_SIZE
--- 等比缩放鱼钩图标（fit into maxW×maxH）
local function hookFitSize(hn, maxW, maxH)
    local srcW = HOOK_W and HOOK_W[hn] or 100
    local srcH = HOOK_H and HOOK_H[hn] or 170
    local scale = math.min(maxW / srcW, maxH / srcH)
    return srcW * scale, srcH * scale
end
local imgSlotHL, SLOTHL_W, SLOTHL_H

-- 船舱UI纹理（切片1-9）
local cabinImgs_   = {}   -- cabinImgs_[1..9] = nvg image handle
local cabinImgsLoaded_ = false

-- 选中状态
local selBagSlot_    = nil   -- 背包中选中的格子索引
local selCabinSlot_  = nil   -- 船舱中选中的格子索引 (1~12)
local selAnim_       = 0
local selCabinAnim_  = 0
local SEL_ANIM_TOTAL = 30
local SEL_EXTRA      = 0.04

-- 物品图标映射（与 Warehouse 共享逻辑）
local ROD_ICON_SLICE  = { 9, 10, 7, 6, 8 }
local REEL_ICON_SLICE = { 4, 5, 3, 2, 1 }

-- ── 辅助函数 ────────────────────────────────────────────────────────────────
local function elasticOut(t)
    if t <= 0 then return 0 end
    if t >= 1 then return 1 end
    return 2^(-10*t) * math.sin((t*10 - 0.75) * (2*math.pi/3)) + 1
end

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

local function drawPanel(vg, px, py, pw, ph, S, title, skipBody)
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

    -- 标题栏
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, w, h, r)
    nvgFillColor(vg, nvgRGBA(TITLE_COLOR[1], TITLE_COLOR[2], TITLE_COLOR[3], 255))
    nvgFill(vg)

    -- 内容区（skipBody时跳过，由外部图片替代）
    if not skipBody then
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
    end

    -- 标题文字
    nvgFontFace(vg, "sans-bold")
    nvgFontSize(vg, 42 * S)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(220, 215, 200, 255))
    nvgText(vg, x + 30 * S, y + titleH * 0.5, title, nil)
end

local function drawSlotBg(vg, gx, gy, S, borderC, fillC)
    local bc = borderC or SLOT_BORDER_C
    local fc = fillC or SLOT_FILL_C
    local sw = SLOT_SIZE * S
    local sh = SLOT_SIZE * S
    local r  = SLOT_CORNER_R * S
    local bw = SLOT_BORDER_W * S
    nvgBeginPath(vg)
    nvgRoundedRect(vg, gx, gy, sw, sh, r)
    nvgFillColor(vg, nvgRGBA(bc[1], bc[2], bc[3], 255))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, gx + bw, gy + bw, sw - bw * 2, sh - bw * 2, math.max(1, r - bw))
    nvgFillColor(vg, nvgRGBA(fc[1], fc[2], fc[3], 255))
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
    local sw = SLOT_SIZE * S
    -- 鱼钩使用专用图标（等比缩放）
    if item.type == "hook" and item.hookId then
        local hn = item.hookId
        if imgHook and imgHook[hn] and imgHook[hn] > 0 then
            local maxSz = sw * 0.75
            local iw, ih = hookFitSize(hn, maxSz, maxSz)
            drawImg(vg, imgHook[hn], gx + sw * 0.5 - iw * 0.5, gy + sw * 0.5 - ih * 0.5, iw, ih)
        end
        return
    end
    -- 鱼饵使用专用图标（正方形）
    if item.type == "bait" and item.baitId then
        local bn = item.baitId
        if imgBait and imgBait[bn] and imgBait[bn] > 0 then
            local sz = sw * 0.75
            drawImg(vg, imgBait[bn], gx + sw * 0.5 - sz * 0.5, gy + sw * 0.5 - sz * 0.5, sz, sz)
        end
        return
    end
    local sn = getItemSlice(item)
    if sn and imgItem and imgItem[sn] and imgItem[sn] > 0 then
        local iw = ITEM_W[sn] * S
        local ih = ITEM_H[sn] * S
        drawImg(vg, imgItem[sn], gx + sw * 0.5 - iw * 0.5, gy + sw * 0.5 - ih * 0.5, iw, ih)
    end
end

--- 计算船舱格子的屏幕坐标
local function getCabinSlotPos(slotIdx, S)
    local def = SLOT_DEFS[slotIdx]
    if not def then return 0, 0 end

    local contentX = CABIN_X + CABIN_GRID_MARGIN_X
    local contentY = CABIN_Y + TITLE_H + CABIN_GRID_MARGIN_Y

    local col = def.col
    local row = def.row

    -- 内容区宽度和中心（相对 contentX）
    local contentW = CABIN_W - 2 * CABIN_GRID_MARGIN_X  -- 605
    local centerX  = contentW * 0.5                      -- 302.5

    if col == 1 and not def.subCol then
        -- 中上格子（slot 9, 10）：居中于面板中轴线
        local gx = (contentX + centerX - SLOT_SIZE * 0.5) * S
        local gy = (contentY + ROW_POSITIONS[row]) * S
        return gx, gy
    elseif def.subCol then
        -- 中下两格（slot 11, 12）：对称排列在中轴线两侧，下移90px
        local gap = 20  -- 两格之间的间隔
        local pairW = SLOT_SIZE * 2 + gap  -- 两格总占宽
        local startX = centerX - pairW * 0.5
        local gx = (contentX + startX + def.subCol * (SLOT_SIZE + gap)) * S
        local gy = (contentY + ROW_POSITIONS[row] + 90) * S
        return gx, gy
    else
        -- 左列、右列正常计算，下移20px
        local gx = (contentX + COL_POSITIONS[col]) * S
        local gy = (contentY + ROW_POSITIONS[row] + 20) * S
        return gx, gy
    end
end

-- ── 船舱装备数据 ────────────────────────────────────────────────────────────
-- PlayerData.data.cabinSlots[1~12] = item or nil

local function ensureCabinData()
    if not PlayerData.data.cabinSlots then
        PlayerData.data.cabinSlots = {}
    end
end

local function getCabinSlots()
    ensureCabinData()
    return PlayerData.data.cabinSlots
end

--- 检查物品是否可放入指定格子
local function canPlaceInSlot(slotIdx, item)
    if not item then return false end
    local def = SLOT_DEFS[slotIdx]
    if not def then return false end
    return item.type == def.slotType
end

-- ── 公开接口 ────────────────────────────────────────────────────────────────
function CabinSystem.IsOpen() return open_ end

function CabinSystem.Open()
    open_ = true
    selBagSlot_ = nil
    selCabinSlot_ = nil
    selAnim_ = 0
    selCabinAnim_ = 0
    ensureCabinData()
    imgItem, ITEM_W, ITEM_H = RodShop.GetItemImages()
    imgHook, HOOK_W, HOOK_H = RodShop.GetHookImages()
    imgBait, BAIT_SIZE = RodShop.GetBaitImages()
    imgSlotHL, SLOTHL_W, SLOTHL_H = RodShop.GetSlotHighlight()

    -- 纹理在Draw中懒加载（需要vg上下文）
end

function CabinSystem.Close()
    open_ = false
    selBagSlot_ = nil
    selCabinSlot_ = nil
end

-- ── 绘制 ────────────────────────────────────────────────────────────────────
function CabinSystem.Draw(vg, sw, sh, ctx)
    if not open_ then return end
    hitboxes_ = {}

    -- 懒加载船舱UI纹理（需要vg上下文，只加载一次）
    if not cabinImgsLoaded_ and vg then
        for i = 1, 9 do
            local path = "image/ui/cabin/切片" .. i .. ".png"
            cabinImgs_[i] = nvgCreateImage(vg, path, 0)
        end
        cabinImgsLoaded_ = true
    end

    local S = sh / 1080
    local PD = ctx.PlayerData
    local slotPx = SLOT_SIZE * S

    -- 选中动画（背包）
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

    -- 选中动画（船舱）
    local selCabinScale = 1.0
    if selCabinSlot_ then
        if selCabinAnim_ > 0 then
            selCabinAnim_ = selCabinAnim_ - 1
            local t = 1.0 - selCabinAnim_ / SEL_ANIM_TOTAL
            selCabinScale = 1.0 + SEL_EXTRA * elasticOut(t)
        else
            selCabinScale = 1.0 + SEL_EXTRA
        end
    end

    -- ── 统一缩放因子（与商店/鱼铺一致）────────────────────────────────────────
    local dpr = graphics:GetDPR()
    local isMobile = (dpr >= 2.0) or (sh < 800)
    local BAG_SCALE = isMobile and 1.20 or 0.756

    -- ══════════════════════════════════════════════════════════════════════════
    -- 左侧：船舱面板（缩放与商店/鱼铺一致）
    -- ══════════════════════════════════════════════════════════════════════════
    local cabinPanelCX = (CABIN_X + CABIN_W * 0.5) * S
    local cabinPanelCY = (CABIN_Y + CABIN_H * 0.5) * S

    nvgSave(vg)
    nvgTranslate(vg, cabinPanelCX, cabinPanelCY)
    nvgScale(vg, BAG_SCALE, BAG_SCALE)
    nvgTranslate(vg, -cabinPanelCX, -cabinPanelCY)

    -- 切片9作为船舱面板完整背景
    if cabinImgs_[9] and cabinImgs_[9] > 0 then
        local bgX = CABIN_X * S
        local bgY = CABIN_Y * S
        local bgW = CABIN_W * S
        local bgH = CABIN_H * S
        drawImg(vg, cabinImgs_[9], bgX, bgY, bgW, bgH, 1.0)
    else
        -- 无图片时回退到程序绘制
        drawPanel(vg, CABIN_X, CABIN_Y, CABIN_W, CABIN_H, S, "船舱")
    end

    -- 绘制12个船舱格子
    local cabinSlots = getCabinSlots()
    for i = 1, 12 do
        local gx, gy = getCabinSlotPos(i, S)
        local def = SLOT_DEFS[i]
        local item = cabinSlots[i]
        local isCabinSel = (selCabinSlot_ == i)

        -- 格子背景（船舱专用颜色，有物品时用装载色）
        local fillC = item and CABIN_SLOT_LOADED_C or CABIN_SLOT_FILL_C
        drawSlotBg(vg, gx, gy, S, CABIN_SLOT_BORDER_C, fillC)

        -- 绘制水印图标（半透明，始终显示在格子底层）
        local wmSlice = SLOT_WATERMARK[i]
        if wmSlice and cabinImgs_[wmSlice] and cabinImgs_[wmSlice] > 0 then
            local innerSize = SLOT_SIZE * 0.6 * S
            local cx = gx + slotPx * 0.5
            local cy = gy + slotPx * 0.5
            drawImg(vg, cabinImgs_[wmSlice], cx - innerSize * 0.5, cy - innerSize * 0.5, innerSize, innerSize, 0.35)
        end

        if item then
            -- 有物品：仅绘制物品图标（不绘制背包的高亮背景）
            if isCabinSel then
                local gcx = gx + slotPx * 0.5
                local gcy = gy + slotPx * 0.5
                -- 鱼钩专用图标（等比缩放）
                if item.type == "hook" and item.hookId then
                    local hn = item.hookId
                    if imgHook and imgHook[hn] and imgHook[hn] > 0 then
                        local maxSz = slotPx * selCabinScale * 0.75
                        local iw, ih = hookFitSize(hn, maxSz, maxSz)
                        drawImg(vg, imgHook[hn], gcx - iw * 0.5, gcy - ih * 0.5, iw, ih)
                    end
                elseif item.type == "bait" and item.baitId then
                    local bn = item.baitId
                    if imgBait and imgBait[bn] and imgBait[bn] > 0 then
                        local sz = slotPx * selCabinScale * 0.75
                        drawImg(vg, imgBait[bn], gcx - sz * 0.5, gcy - sz * 0.5, sz, sz)
                    end
                else
                    local sn = getItemSlice(item)
                    if sn and imgItem and imgItem[sn] and imgItem[sn] > 0 then
                        local iw = ITEM_W[sn] * S * selCabinScale
                        local ih = ITEM_H[sn] * S * selCabinScale
                        drawImg(vg, imgItem[sn], gcx - iw * 0.5, gcy - ih * 0.5, iw, ih)
                    end
                end
            else
                drawItemInSlot(vg, item, gx, gy, S)
            end
        else
            -- 空格：显示类型提示文字
            local label = TYPE_LABELS[def.slotType] or ""
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 20 * S)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(160, 155, 140, 180))
            nvgText(vg, gx + slotPx * 0.5, gy + slotPx * 0.5, label, nil)
        end

        -- hitbox 缩放转换
        local hitX = (gx - cabinPanelCX) * BAG_SCALE + cabinPanelCX
        local hitY = (gy - cabinPanelCY) * BAG_SCALE + cabinPanelCY
        local hitW = slotPx * BAG_SCALE
        local hitH = slotPx * BAG_SCALE
        addHit("cabin_" .. i, hitX, hitY, hitW, hitH)
    end

    nvgRestore(vg)

    -- ══════════════════════════════════════════════════════════════════════════
    -- 右侧：背包面板（缩放与商店/鱼铺一致）
    -- ══════════════════════════════════════════════════════════════════════════

    -- 面板中心点（设计坐标 * S）
    local bagPanelCX = (BAG_X + BAG_W * 0.5) * S
    local bagPanelCY = (BAG_Y + BAG_H * 0.5) * S

    nvgSave(vg)
    -- 以面板中心为锚点等比缩放
    nvgTranslate(vg, bagPanelCX, bagPanelCY)
    nvgScale(vg, BAG_SCALE, BAG_SCALE)
    nvgTranslate(vg, -bagPanelCX, -bagPanelCY)

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
        local money = PD.GetMoney and PD.GetMoney() or 0
        local coinH = moneyH * 0.72
        local coinW = RodShop.DrawCoinIcon(vg, 0, -9999, coinH) or coinH
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

    -- 背包格子（只显示可放入船舱的装备类物品）
    local inventory = PD.GetInventory()

    -- 构建背包显示列表（过滤出装备类物品）
    local bagList = {}
    for idx, item in ipairs(inventory) do
        -- 所有船舱可接受的类型
        if item.type == "rod" or item.type == "reel" or item.type == "hook"
            or item.type == "bait" or item.type == "lamp" or item.type == "sonar"
            or item.type == "anchor" or item.type == "bait_collector" then
            bagList[#bagList + 1] = { item = item, invIdx = idx }
        end
    end

    for row = 0, BAG_ROWS - 1 do
        for col = 0, BAG_COLS - 1 do
            local gx = BAG_GRID_X * S + col * BAG_SLOT_STEP * S
            local gy = BAG_GRID_Y * S + row * BAG_SLOT_STEP * S
            drawSlotBg(vg, gx, gy, S)

            local slot = row * BAG_COLS + col + 1
            local entry = bagList[slot]
            local isSel = (selBagSlot_ == slot)

            if entry then
                if isSel then
                    local gcx = gx + slotPx * 0.5
                    local gcy = gy + slotPx * 0.5
                    if imgSlotHL and imgSlotHL > 0 then
                        local hlW = SLOTHL_W * S * selScale
                        local hlH = SLOTHL_H * S * selScale
                        drawImg(vg, imgSlotHL, gcx - hlW * 0.5, gcy - hlH * 0.5, hlW, hlH)
                    end
                    -- 物品图标（选中放大）
                    if entry.item.type == "hook" and entry.item.hookId then
                        local hn = entry.item.hookId
                        if imgHook and imgHook[hn] and imgHook[hn] > 0 then
                            local maxSz = slotPx * selScale * 0.75
                            local iw, ih = hookFitSize(hn, maxSz, maxSz)
                            drawImg(vg, imgHook[hn], gcx - iw * 0.5, gcy - ih * 0.5, iw, ih)
                        end
                    elseif entry.item.type == "bait" and entry.item.baitId then
                        local bn = entry.item.baitId
                        if imgBait and imgBait[bn] and imgBait[bn] > 0 then
                            local sz = slotPx * selScale * 0.75
                            drawImg(vg, imgBait[bn], gcx - sz * 0.5, gcy - sz * 0.5, sz, sz)
                        end
                    else
                        local sn = getItemSlice(entry.item)
                        if sn and imgItem and imgItem[sn] and imgItem[sn] > 0 then
                            local iw = ITEM_W[sn] * S * selScale
                            local ih = ITEM_H[sn] * S * selScale
                            drawImg(vg, imgItem[sn], gcx - iw * 0.5, gcy - ih * 0.5, iw, ih)
                        end
                    end
                else
                    if imgSlotHL and imgSlotHL > 0 then
                        drawImg(vg, imgSlotHL, gx, gy, SLOTHL_W * S, SLOTHL_H * S)
                    end
                    drawItemInSlot(vg, entry.item, gx, gy, S)
                end
            end

            -- hitbox 需要转换到屏幕坐标（考虑缩放变换）
            local hitX = (gx - bagPanelCX) * BAG_SCALE + bagPanelCX
            local hitY = (gy - bagPanelCY) * BAG_SCALE + bagPanelCY
            local hitW = slotPx * BAG_SCALE
            local hitH = slotPx * BAG_SCALE
            addHit("bag_" .. slot, hitX, hitY, hitW, hitH)
        end
    end

    -- ══════════════════════════════════════════════════════════════════════════
    -- 操作按钮
    -- ══════════════════════════════════════════════════════════════════════════
    do
        local btnGap = 20 * S
        local btnW = 180 * S
        local btnH = 56 * S
        local totalW = btnW * 2 + btnGap
        local startX = (BAG_X + BAG_W * 0.5) * S - totalW * 0.5
        local btnY = (BAG_Y + BAG_H - 80) * S

        -- 按钮1：装入船舱
        local enabled1 = (selBagSlot_ ~= nil)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, startX, btnY, btnW, btnH, 14 * S)
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
        nvgText(vg, startX + btnW * 0.5, btnY + btnH * 0.5, "装入船舱", nil)
        -- hitbox 缩放转换
        local hx1 = (startX - bagPanelCX) * BAG_SCALE + bagPanelCX
        local hy1 = (btnY - bagPanelCY) * BAG_SCALE + bagPanelCY
        addHit("equip_selected", hx1, hy1, btnW * BAG_SCALE, btnH * BAG_SCALE)

        -- 按钮2：卸下装备
        local enabled2 = (selCabinSlot_ ~= nil and cabinSlots[selCabinSlot_] ~= nil)
        local btn2X = startX + btnW + btnGap
        nvgBeginPath(vg)
        nvgRoundedRect(vg, btn2X, btnY, btnW, btnH, 14 * S)
        if enabled2 then
            nvgFillColor(vg, nvgRGBA(180, 60, 40, 240))
        else
            nvgFillColor(vg, nvgRGBA(160, 160, 160, 180))
        end
        nvgFill(vg)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgText(vg, btn2X + btnW * 0.5, btnY + btnH * 0.5, "卸下装备", nil)
        local hx2 = (btn2X - bagPanelCX) * BAG_SCALE + bagPanelCX
        local hy2 = (btnY - bagPanelCY) * BAG_SCALE + bagPanelCY
        addHit("unequip_selected", hx2, hy2, btnW * BAG_SCALE, btnH * BAG_SCALE)
    end

    -- ══════════════════════════════════════════════════════════════════════════
    -- 返回按钮
    -- ══════════════════════════════════════════════════════════════════════════
    local btnW = 90 * S
    local btnH = 50 * S
    local btnX = (BAG_X + BAG_W - 100) * S
    local btnY2 = (BAG_Y - 60) * S
    nvgBeginPath(vg)
    nvgRoundedRect(vg, btnX, btnY2, btnW, btnH, 12 * S)
    nvgFillColor(vg, nvgRGBA(37, 40, 41, 220))
    nvgFill(vg)
    nvgFontFace(vg, "sans-bold")
    nvgFontSize(vg, 26 * S)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, btnX + btnW * 0.5, btnY2 + btnH * 0.5, "返回", nil)
    local hxC = (btnX - bagPanelCX) * BAG_SCALE + bagPanelCX
    local hyC = (btnY2 - bagPanelCY) * BAG_SCALE + bagPanelCY
    addHit("close", hxC, hyC, btnW * BAG_SCALE, btnH * BAG_SCALE)

    nvgRestore(vg)
end

-- ── 鼠标点击 ────────────────────────────────────────────────────────────────
function CabinSystem.HandleMouseClick(mx, my, ctx)
    if not open_ then return false, nil end

    local id = hitTest(mx, my)
    if not id then return false, nil end

    local PD = ctx.PlayerData

    -- 关闭
    if id == "close" then
        CabinSystem.Close()
        return true, { close = true }
    end

    -- 背包格子点击
    if id:sub(1, 4) == "bag_" then
        local slot = tonumber(id:sub(5))
        if slot then
            if selBagSlot_ == slot then
                selBagSlot_ = nil  -- 取消选中
            else
                selBagSlot_ = slot
                selAnim_ = SEL_ANIM_TOTAL
            end
            selCabinSlot_ = nil  -- 互斥选中
        end
        return true, nil
    end

    -- 船舱格子点击
    if id:sub(1, 6) == "cabin_" then
        local slot = tonumber(id:sub(7))
        if slot then
            if selCabinSlot_ == slot then
                selCabinSlot_ = nil
            else
                selCabinSlot_ = slot
                selCabinAnim_ = SEL_ANIM_TOTAL
            end
            selBagSlot_ = nil  -- 互斥选中
        end
        return true, nil
    end

    -- 装入船舱按钮
    if id == "equip_selected" then
        if selBagSlot_ then
            -- 找到背包中对应物品
            local inventory = PD.GetInventory()
            local bagList = {}
            for idx, item in ipairs(inventory) do
                if item.type == "rod" or item.type == "reel" or item.type == "hook"
                    or item.type == "bait" or item.type == "lamp" or item.type == "sonar"
                    or item.type == "anchor" or item.type == "bait_collector" then
                    bagList[#bagList + 1] = { item = item, invIdx = idx }
                end
            end
            local entry = bagList[selBagSlot_]
            if entry then
                -- 找到合适的空船舱格子
                local placed = false
                local cabinSlots = getCabinSlots()
                for i = 1, 12 do
                    if not cabinSlots[i] and canPlaceInSlot(i, entry.item) then
                        cabinSlots[i] = entry.item
                        PD.RemoveInventoryItem(entry.invIdx)
                        placed = true
                        selBagSlot_ = nil
                        break
                    end
                end
                if not placed then
                    return true, { message = "没有可用的船舱格子" }
                else
                    return true, { message = "已装入船舱" }
                end
            end
        end
        return true, nil
    end

    -- 卸下装备按钮
    if id == "unequip_selected" then
        if selCabinSlot_ then
            local cabinSlots = getCabinSlots()
            local item = cabinSlots[selCabinSlot_]
            if item then
                PD.AddInventoryItem(item)
                cabinSlots[selCabinSlot_] = nil
                selCabinSlot_ = nil
                return true, { message = "已卸下装备" }
            end
        end
        return true, nil
    end

    return true, nil
end

return CabinSystem
