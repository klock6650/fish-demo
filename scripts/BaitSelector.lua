-- ============================================================================
-- BaitSelector: 鱼饵切换 UI
-- 15 种鱼饵，分三栏展示：大型饵(1-6) / 万能饵(7-9) / 轻量饵(10-15)
-- 接口: BaitSelector.Open / Close / IsOpen / Draw / HandleMouseClick
-- ctx 字段: equippedBait (number 1-15 or 0=无), onEquip (function)
-- ============================================================================

local BaitSelector = {}

-- ── 鱼饵定义（1-15）────────────────────────────────────────────────────────
-- 对应 fish_dist_data.lua bait 数组下标，与 xlsx 列 27-41 顺序一致
BaitSelector.BAIT_TYPES = {
    -- ─── 大型饵（1-6，红色系鱼偏好）────────────────────────────────────────
    [1]  = { name = "巨型饵鱼", group = 1, color = { 220, 90,  70 },
             tip = "超大型猎物首选\n对红色鱼效果极佳" },
    [2]  = { name = "巨型波爬", group = 1, color = { 210, 100, 60 },
             tip = "深海大鱼专用\n对红色鱼效果极佳" },
    [3]  = { name = "鱿鱼饵",   group = 1, color = { 200, 80, 140 },
             tip = "深海乌贼系\n对红色鱼效果好" },
    [4]  = { name = "饵鱼",     group = 1, color = { 190, 120, 60 },
             tip = "天然鱼饵\n对红色鱼效果好" },
    [5]  = { name = "波趴",     group = 1, color = { 200, 150, 50 },
             tip = "水面游动拟饵\n对红色鱼有效" },
    [6]  = { name = "螺肉",     group = 1, color = { 180, 130, 80 },
             tip = "底栖生物最爱\n对红色鱼有效" },
    -- ─── 万能饵（7-9，蓝/绿/金色系鱼偏好）──────────────────────────────────
    [7]  = { name = "鱼块",     group = 2, color = {  90, 180, 210 },
             tip = "普通切块鱼肉\n对蓝绿金色鱼有效" },
    [8]  = { name = "铅笔",     group = 2, color = { 100, 160, 220 },
             tip = "细长形拟饵\n对蓝绿金色鱼有效" },
    [9]  = { name = "贝肉",     group = 2, color = { 120, 190, 160 },
             tip = "贝壳鲜肉\n对蓝绿金色鱼有效" },
    -- ─── 轻量饵（10-15，白色系鱼偏好）──────────────────────────────────────
    [10] = { name = "鱼条",     group = 3, color = { 200, 220, 255 },
             tip = "细条鱼肉\n对小型白色鱼有效" },
    [11] = { name = "亮片",     group = 3, color = { 180, 200, 240 },
             tip = "金属反光拟饵\n对白色鱼效果好" },
    [12] = { name = "虾肉",     group = 3, color = { 210, 180, 200 },
             tip = "新鲜虾肉\n对白色鱼效果好" },
    [13] = { name = "人造饵",   group = 3, color = { 160, 200, 255 },
             tip = "仿真橡皮饵\n对白色鱼效果好" },
    [14] = { name = "瓜子亮片", group = 3, color = { 170, 210, 240 },
             tip = "小型旋转亮片\n对白色鱼效果极佳" },
    [15] = { name = "南极磷虾", group = 3, color = { 220, 200, 220 },
             tip = "极地磷虾\n对白色鱼效果极佳" },
}

BaitSelector.BAIT_GROUPS = {
    { id = 1, label = "大型饵", color = { 220, 90, 70 },  range = {1, 6}  },
    { id = 2, label = "万能饵", color = {  90, 180, 210 }, range = {7, 9}  },
    { id = 3, label = "轻量饵", color = { 200, 220, 255 }, range = {10, 15} },
}

-- ── 内部状态 ────────────────────────────────────────────────────────────────
local open_     = false
local hovered_  = 0
local _hitboxes = {}

-- ── 配色 ─────────────────────────────────────────────────────────────────────
local C = {
    OVERLAY   = {  0,   0,   0, 180 },
    PANEL     = { 14,  18,  30, 252 },
    CARD_BG   = {  9,  12,  22, 255 },
    CARD_HOV  = { 24,  30,  48, 255 },
    CARD_SEL  = { 30,  38,  58, 255 },
    BORDER    = { 40,  46,  66, 255 },
    RING_SEL  = { 255, 210,  60, 255 },
    RING_HOV  = { 100, 170, 255, 200 },
    TITLE_A   = {  30, 120, 200, 255 },
    TITLE_B   = {  60, 200, 160, 255 },
    TEXT_W    = { 255, 255, 255, 255 },
    TEXT_DIM  = { 130, 145, 165, 200 },
    GRP_LABEL = { 200, 215, 235, 210 },
    SEP       = {  45,  50,  70, 140 },
    EQUIP_BTN = {  45, 155,  75, 255 },
    EQUIP_DIM = {  30,  36,  54, 255 },
    NONE_BG   = {  20,  25,  40, 255 },
    NONE_SEL  = { 255, 210,  60, 255 },
}

local function rgba(c, ao)
    return nvgRGBA(c[1], c[2], c[3], ao or c[4] or 255)
end

local function addHit(id, x, y, w, h)
    _hitboxes[#_hitboxes + 1] = { id = id, x = x, y = y, w = w, h = h }
end

local function hitTest(mx, my)
    for _, b in ipairs(_hitboxes) do
        if mx >= b.x and mx <= b.x + b.w and my >= b.y and my <= b.y + b.h then
            return b.id
        end
    end
    return nil
end

local function BoldText(vg, x, y, text, size, align, c, ao)
    local a = ao or (c and c[4]) or 255
    local r = c and c[1] or 255
    local g = c and c[2] or 255
    local b = c and c[3] or 255
    nvgFontFace(vg, "sans-bold")
    nvgFontSize(vg, size)
    nvgTextAlign(vg, align)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 150))
    nvgText(vg, x - 1, y,     text, nil)
    nvgText(vg, x + 1, y,     text, nil)
    nvgText(vg, x,     y - 1, text, nil)
    nvgText(vg, x,     y + 1, text, nil)
    nvgFillColor(vg, nvgRGBA(r, g, b, a))
    nvgText(vg, x, y, text, nil)
end

-- 绘制鱼饵图标（简单示意）
local function DrawBaitIcon(vg, cx, cy, r, baitIdx, color)
    local grp = BaitSelector.BAIT_TYPES[baitIdx] and BaitSelector.BAIT_TYPES[baitIdx].group or 1
    if grp == 1 then
        -- 大型饵：鱼形
        nvgBeginPath(vg)
        nvgEllipse(vg, cx - r * 0.1, cy, r * 0.75, r * 0.38)
        nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], 200))
        nvgFill(vg)
        -- 尾巴
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx + r * 0.62, cy)
        nvgLineTo(vg, cx + r,        cy - r * 0.35)
        nvgLineTo(vg, cx + r,        cy + r * 0.35)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], 180))
        nvgFill(vg)
    elseif grp == 2 then
        -- 万能饵：方块
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cx - r * 0.6, cy - r * 0.6, r * 1.2, r * 1.2, r * 0.2)
        nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], 210))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 60))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
    else
        -- 轻量饵：亮片/圆形
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, r * 0.62)
        nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], 220))
        nvgFill(vg)
        -- 反光
        nvgBeginPath(vg)
        nvgCircle(vg, cx - r * 0.18, cy - r * 0.18, r * 0.22)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 90))
        nvgFill(vg)
    end
end

-- ── 公开接口 ─────────────────────────────────────────────────────────────────
function BaitSelector.IsOpen() return open_ end

function BaitSelector.Open()
    open_    = true
    hovered_ = 0
    _hitboxes = {}
end

function BaitSelector.Close()
    open_    = false
    _hitboxes = {}
end

--- @return boolean consumed, table|nil result
function BaitSelector.HandleMouseClick(mx, my, ctx)
    if not open_ then return false, nil end
    local id = hitTest(mx, my)
    if not id then
        BaitSelector.Close()
        return true, { close = true }
    end
    if id == "close" then
        BaitSelector.Close()
        return true, { close = true }
    end
    if id == "none" then
        BaitSelector.Close()
        return true, { equip = 0 }
    end
    local cardId = id:match("^card_(%d+)$")
    if cardId then
        local idx = tonumber(cardId)
        BaitSelector.Close()
        return true, { equip = idx }
    end
    return true, nil
end

function BaitSelector.HandleMouseMove(mx, my)
    if not open_ then return end
    local id = hitTest(mx, my)
    local cardId = id and id:match("^card_(%d+)$")
    hovered_ = cardId and tonumber(cardId) or 0
end

-- ── 主绘制 ───────────────────────────────────────────────────────────────────
function BaitSelector.Draw(vg, sw, sh, ctx)
    if not open_ then return end
    _hitboxes = {}

    local equipped = ctx.equippedBait or 0
    local BAITS    = BaitSelector.BAIT_TYPES
    local GROUPS   = BaitSelector.BAIT_GROUPS

    -- ── 布局参数 ──────────────────────────────────────────────────────────
    local CARD_W   = 88
    local CARD_H   = 155
    local CARD_GAP = 8
    local GRP_GAP  = 20    -- 组间距
    local TITLE_H  = 46
    local PAD_H    = 16
    local PAD_V    = 12

    -- 计算总面板宽：6 + gap*5 + GRP_GAP + 3 + gap*2 + GRP_GAP + 6 + gap*5
    local grp1W = 6 * CARD_W + 5 * CARD_GAP
    local grp2W = 3 * CARD_W + 2 * CARD_GAP
    local grp3W = 6 * CARD_W + 5 * CARD_GAP
    local NONE_W = 52
    local panelW = PAD_H * 2 + NONE_W + CARD_GAP + grp1W + GRP_GAP + grp2W + GRP_GAP + grp3W
    local panelH = TITLE_H + PAD_V * 2 + CARD_H + 24  -- 24=底部说明

    -- 屏幕居中
    local panelX = math.floor((sw - panelW) * 0.5)
    local panelY = math.floor(sh * 0.5 - panelH * 0.5)

    -- ── 全屏遮罩 ──────────────────────────────────────────────────────────
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, sw, sh)
    nvgFillColor(vg, rgba(C.OVERLAY))
    nvgFill(vg)

    -- ── 面板 ──────────────────────────────────────────────────────────────
    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, 14)
    nvgFillColor(vg, rgba(C.PANEL))
    nvgFill(vg)
    nvgStrokeColor(vg, rgba(C.BORDER))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- ── 标题栏渐变 ────────────────────────────────────────────────────────
    local grad = nvgLinearGradient(vg,
        panelX, panelY, panelX + panelW, panelY,
        rgba(C.TITLE_A), rgba(C.TITLE_B))
    nvgBeginPath(vg)
    nvgRoundedRectVarying(vg, panelX, panelY, panelW, TITLE_H, 14, 14, 0, 0)
    nvgFillPaint(vg, grad)
    nvgFill(vg)
    BoldText(vg, panelX + panelW * 0.5, panelY + TITLE_H * 0.5,
        "选择鱼饵", 20, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, C.TEXT_W)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 100))
    nvgText(vg, panelX + panelW - 12, panelY + TITLE_H * 0.5, "K 键关闭", nil)

    -- 关闭按钮
    local csz  = 26
    local cx_c = panelX + panelW - csz - 8
    local cy_c = panelY + (TITLE_H - csz) * 0.5
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx_c, cy_c, csz, csz, 6)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 70))
    nvgFill(vg)
    BoldText(vg, cx_c + csz * 0.5, cy_c + csz * 0.5, "✕", 13,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, C.TEXT_W)
    addHit("close", cx_c, cy_c, csz, csz)

    -- ── 卡片区 ────────────────────────────────────────────────────────────
    local cardsY = panelY + TITLE_H + PAD_V
    local curX   = panelX + PAD_H

    -- 「不用鱼饵」按钮
    local isNone = (equipped == 0)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, curX, cardsY, NONE_W, CARD_H, 8)
    nvgFillColor(vg, isNone and rgba(C.CARD_SEL) or rgba(C.NONE_BG))
    nvgFill(vg)
    nvgStrokeColor(vg, isNone and rgba(C.RING_SEL) or rgba(C.BORDER))
    nvgStrokeWidth(vg, isNone and 2.5 or 1)
    nvgStroke(vg)
    nvgSave(vg)
    nvgTranslate(vg, curX + NONE_W * 0.5, cardsY + CARD_H * 0.5)
    nvgRotate(vg, -math.pi * 0.5)
    BoldText(vg, 0, 0, isNone and "✓ 空钩" or "空  钩", 13,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, isNone and C.RING_SEL or C.TEXT_DIM)
    nvgRestore(vg)
    addHit("none", curX, cardsY, NONE_W, CARD_H)
    curX = curX + NONE_W + CARD_GAP

    -- 三组卡片
    for gi, grp in ipairs(GROUPS) do
        if gi > 1 then curX = curX + GRP_GAP end

        -- 组标签
        local grpW = (grp.range[2] - grp.range[1] + 1) * CARD_W +
                     (grp.range[2] - grp.range[1]) * CARD_GAP
        BoldText(vg, curX + grpW * 0.5, cardsY - 6, grp.label, 11,
            NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM, grp.color)

        -- 各卡
        for idx = grp.range[1], grp.range[2] do
            local bait  = BAITS[idx]
            local isSel = (idx == equipped)
            local isHov = (idx == hovered_)
            local bx    = curX + (idx - grp.range[1]) * (CARD_W + CARD_GAP)
            local by    = cardsY

            -- 卡片底色
            nvgBeginPath(vg)
            nvgRoundedRect(vg, bx, by, CARD_W, CARD_H, 8)
            nvgFillColor(vg, isSel and rgba(C.CARD_SEL)
                or (isHov and rgba(C.CARD_HOV) or rgba(C.CARD_BG)))
            nvgFill(vg)
            nvgStrokeColor(vg, isSel and rgba(C.RING_SEL)
                or (isHov and rgba(C.RING_HOV) or rgba(C.BORDER)))
            nvgStrokeWidth(vg, isSel and 2.5 or (isHov and 2 or 1))
            nvgStroke(vg)

            -- 图标区
            local iconH = CARD_H * 0.48
            nvgBeginPath(vg)
            nvgRoundedRectVarying(vg, bx + 1, by + 1, CARD_W - 2, iconH, 7, 7, 0, 0)
            nvgFillColor(vg, nvgRGBA(6, 10, 20, 255))
            nvgFill(vg)
            local iconR = math.min(CARD_W, iconH) * 0.28
            DrawBaitIcon(vg, bx + CARD_W * 0.5, by + iconH * 0.5, iconR, idx, bait.color)

            -- 组色角标
            nvgBeginPath(vg)
            nvgRoundedRect(vg, bx + 5, by + 5, 16, 16, 3)
            nvgFillColor(vg, nvgRGBA(bait.color[1], bait.color[2], bait.color[3], 160))
            nvgFill(vg)
            nvgFontFace(vg, "sans-bold")
            nvgFontSize(vg, 10)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 200))
            nvgText(vg, bx + 13, by + 13, tostring(idx), nil)

            -- 已选 √
            if isSel then
                nvgBeginPath(vg)
                nvgRoundedRect(vg, bx + CARD_W - 22, by + 5, 17, 17, 4)
                nvgFillColor(vg, nvgRGBA(80, 200, 120, 220))
                nvgFill(vg)
                BoldText(vg, bx + CARD_W - 13, by + 13, "✓", 10,
                    NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, C.TEXT_W)
            end

            -- 名称
            local nameY = by + iconH + 9
            nvgFontFace(vg, "sans-bold")
            nvgFontSize(vg, 12)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(bait.color[1], bait.color[2], bait.color[3], 255))
            nvgText(vg, bx + CARD_W * 0.5, nameY, bait.name, nil)

            -- 提示
            nvgBeginPath(vg)
            nvgMoveTo(vg, bx + 8, nameY + 16)
            nvgLineTo(vg, bx + CARD_W - 8, nameY + 16)
            nvgStrokeColor(vg, rgba(C.SEP))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)
            local tipLines = {}
            for line in bait.tip:gmatch("[^\n]+") do
                tipLines[#tipLines + 1] = line
            end
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 9.5)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            nvgFillColor(vg, rgba(C.TEXT_DIM))
            for li, line in ipairs(tipLines) do
                nvgText(vg, bx + CARD_W * 0.5, nameY + 20 + (li - 1) * 13, line, nil)
            end

            -- 底部按钮
            local btnH = 24
            local btnW = CARD_W - 14
            local btnX = bx + 7
            local btnY = by + CARD_H - btnH - 7
            nvgBeginPath(vg)
            nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 5)
            nvgFillColor(vg, isSel and rgba(C.EQUIP_DIM) or rgba(C.EQUIP_BTN))
            nvgFill(vg)
            if not isSel then
                nvgBeginPath(vg)
                nvgMoveTo(vg, btnX + 5, btnY + 3)
                nvgLineTo(vg, btnX + btnW - 5, btnY + 3)
                nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 40))
                nvgStrokeWidth(vg, 1)
                nvgStroke(vg)
            end
            BoldText(vg, btnX + btnW * 0.5, btnY + btnH * 0.5,
                isSel and "已装备" or "装备", 11,
                NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, C.TEXT_W)

            addHit("card_" .. idx, bx, by, CARD_W, CARD_H)
        end
        curX = curX + grpW
    end

    -- ── 底部说明 ──────────────────────────────────────────────────────────
    local footY = panelY + TITLE_H + PAD_V + CARD_H + 8
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, rgba(C.TEXT_DIM))
    nvgText(vg, panelX + panelW * 0.5, footY,
        "单击卡片装备鱼饵   K 键快速关闭   左: 大型饵  中: 万能饵  右: 轻量饵", nil)

    -- 整体面板点击区
    addHit("panel", panelX, panelY, panelW, panelH)
end

return BaitSelector
