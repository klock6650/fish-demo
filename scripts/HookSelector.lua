-- ============================================================================
-- HookSelector: 鱼钩切换 UI
-- 5 种鱼钩等级：微小/小型/中型/大型/巨大
-- 接口：HookSelector.Open / Close / IsOpen / Draw / HandleMouseClick
-- ctx 字段：equippedHook (number), onEquip (function)
-- ============================================================================

local HookSelector = {}

-- ── 鱼钩定义（等级 1~5）────────────────────────────────────────────────────
HookSelector.HOOK_TYPES = {
    [1] = {
        name  = "微小",
        desc  = "极细钩，轻如鸿毛",
        color = { 180, 220, 180 },   -- 淡绿
        tip   = "适合0.1g以下微型鱼\n上钩率最高",
    },
    [2] = {
        name  = "小型",
        desc  = "灵巧轻钩",
        color = { 120, 180, 240 },   -- 蓝
        tip   = "适合小型鱼类\n轻口鱼首选",
    },
    [3] = {
        name  = "中型",
        desc  = "万能标准钩",
        color = { 240, 200,  80 },   -- 金
        tip   = "适合大多数鱼种\n综合性能最佳",
    },
    [4] = {
        name  = "大型",
        desc  = "强力重钩",
        color = { 240, 130,  60 },   -- 橙
        tip   = "适合大型鱼类\n小鱼不易上钩",
    },
    [5] = {
        name  = "巨大",
        desc  = "深海霸钩",
        color = { 210,  80,  80 },   -- 红
        tip   = "专为超大型猎物\n普通鱼几乎不咬",
    },
}

-- ── 内部状态 ────────────────────────────────────────────────────────────────
local open_     = false
local hovered_  = 0     -- 鼠标悬停的卡片 (0=无)
local _hitboxes = {}

-- ── 配色 ─────────────────────────────────────────────────────────────────────
local C = {
    OVERLAY   = {  0,   0,   0, 180 },
    PANEL     = { 18,  22,  34, 250 },
    CARD_BG   = { 12,  15,  26, 255 },
    CARD_HOV  = { 28,  34,  52, 255 },
    CARD_SEL  = { 35,  42,  60, 255 },
    BORDER    = { 45,  50,  70, 255 },
    RING_SEL  = { 255, 200,  50, 255 },
    RING_HOV  = { 100, 160, 255, 200 },
    TITLE_A   = {  40, 140, 210, 255 },
    TITLE_B   = {  80, 200, 180, 255 },
    TEXT_W    = { 255, 255, 255, 255 },
    TEXT_DIM  = { 130, 140, 160, 200 },
    TEXT_TIP  = { 180, 190, 210, 210 },
    EQUIP_BTN = {  50, 160,  80, 255 },
    EQUIP_DIM = {  35,  40,  55, 255 },
    SEP       = {  45,  50,  70, 160 },
}

-- ── 辅助 ─────────────────────────────────────────────────────────────────────
local function rgba(c, ao)
    return nvgRGBA(c[1], c[2], c[3], ao or c[4] or 255)
end

local function addHit(id, x, y, w, h)
    _hitboxes[#_hitboxes + 1] = { id=id, x=x, y=y, w=w, h=h }
end

local function hitTest(mx, my)
    for _, b in ipairs(_hitboxes) do
        if mx >= b.x and mx <= b.x+b.w and my >= b.y and my <= b.y+b.h then
            return b.id
        end
    end
    return nil
end

local function BoldText(vg, x, y, text, size, align, c, ao)
    local a = ao or c[4] or 255
    nvgFontFace(vg, "sans-bold")
    nvgFontSize(vg, size)
    nvgTextAlign(vg, align)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
    nvgText(vg, x-1, y,   text, nil)
    nvgText(vg, x+1, y,   text, nil)
    nvgText(vg, x,   y-1, text, nil)
    nvgText(vg, x,   y+1, text, nil)
    nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], a))
    nvgText(vg, x, y, text, nil)
end

-- 绘制鱼钩图标（钩型示意）
local function DrawHookIcon(vg, cx, cy, r, hookLevel, color)
    local lw = math.max(1.5, 1.0 + hookLevel * 0.5)

    -- 钩柄（竖直段）
    local stemH = r * 1.1
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx, cy - stemH)
    nvgLineTo(vg, cx, cy + r * 0.2)
    nvgStrokeColor(vg, nvgRGBA(color[1], color[2], color[3], 220))
    nvgStrokeWidth(vg, lw + 0.5)
    nvgLineCap(vg, NVG_ROUND)
    nvgStroke(vg)

    -- 弯钩弧（右侧半圆）
    nvgBeginPath(vg)
    nvgArc(vg, cx, cy + r * 0.2, r * 0.75, -math.pi * 0.5, math.pi * 0.6, NVG_CW)
    nvgStrokeColor(vg, nvgRGBA(color[1], color[2], color[3], 230))
    nvgStrokeWidth(vg, lw)
    nvgStroke(vg)

    -- 钩尖（小三角）
    local tipX = cx - r * 0.18
    local tipY = cy + r * 0.2 + r * 0.75 * math.sin(math.pi * 0.6)
    nvgBeginPath(vg)
    nvgMoveTo(vg, tipX, tipY)
    nvgLineTo(vg, tipX - r * 0.28, tipY - r * 0.22)
    nvgLineTo(vg, tipX + r * 0.14, tipY - r * 0.10)
    nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], 240))
    nvgFill(vg)

    -- 钩环（顶部小圈）
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy - stemH, lw * 1.8)
    nvgStrokeColor(vg, nvgRGBA(color[1], color[2], color[3], 180))
    nvgStrokeWidth(vg, 1.0)
    nvgStroke(vg)
end

-- ── 公开接口 ─────────────────────────────────────────────────────────────────
function HookSelector.IsOpen() return open_ end

function HookSelector.Open()
    open_     = true
    hovered_  = 0
    _hitboxes = {}
end

function HookSelector.Close()
    open_     = false
    _hitboxes = {}
end

--- @return boolean consumed, table|nil result
function HookSelector.HandleMouseClick(mx, my, ctx)
    if not open_ then return false, nil end
    local id = hitTest(mx, my)
    if not id then
        -- 点击遮罩外关闭
        HookSelector.Close()
        return true, { close = true }
    end

    if id == "close" then
        HookSelector.Close()
        return true, { close = true }
    end

    local cardId = id:match("^card_(%d+)$")
    if cardId then
        local level = tonumber(cardId)
        if level and level ~= (ctx.equippedHook or 3) then
            HookSelector.Close()
            return true, { equip = level }
        else
            HookSelector.Close()
            return true, { close = true }
        end
    end

    return true, nil
end

--- 更新悬停状态（可选，在 HandleMouseMove 中调用以显示 hover 高亮）
function HookSelector.HandleMouseMove(mx, my)
    if not open_ then return end
    local id = hitTest(mx, my)
    local cardId = id and id:match("^card_(%d+)$")
    hovered_ = cardId and tonumber(cardId) or 0
end

-- ── 主绘制 ───────────────────────────────────────────────────────────────────
function HookSelector.Draw(vg, sw, sh, ctx)
    if not open_ then return end
    _hitboxes = {}

    local equipped = ctx.equippedHook or 3
    local HOOKS    = HookSelector.HOOK_TYPES

    -- ── 布局参数 ──────────────────────────────────────────────────────────
    local CARD_W    = 120
    local CARD_H    = 180
    local CARD_GAP  = 12
    local TITLE_H   = 46
    local PAD_H     = 16     -- 上下内边距
    local PAD_V     = 14

    local totalCards = 5
    local panelW = PAD_H * 2 + totalCards * CARD_W + (totalCards - 1) * CARD_GAP
    local panelH = TITLE_H + PAD_V * 2 + CARD_H + 14  -- 14 = 底部提示行

    local panelX = math.floor((sw - panelW) / 2)
    local panelY = math.floor(sh * 0.5 - panelH * 0.5)

    -- ── 全屏半透明遮罩 ────────────────────────────────────────────────────
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, sw, sh)
    nvgFillColor(vg, rgba(C.OVERLAY))
    nvgFill(vg)

    -- ── 面板背景 ──────────────────────────────────────────────────────────
    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, 14)
    nvgFillColor(vg, rgba(C.PANEL))
    nvgFill(vg)

    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, 14)
    nvgStrokeColor(vg, rgba(C.BORDER))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- ── 标题栏（渐变）────────────────────────────────────────────────────
    local titleGrad = nvgLinearGradient(vg,
        panelX, panelY,
        panelX + panelW, panelY,
        rgba(C.TITLE_A), rgba(C.TITLE_B))
    nvgBeginPath(vg)
    nvgRoundedRectVarying(vg, panelX, panelY, panelW, TITLE_H, 14, 14, 0, 0)
    nvgFillPaint(vg, titleGrad)
    nvgFill(vg)

    BoldText(vg, panelX + panelW * 0.5, panelY + TITLE_H * 0.5,
        "选择鱼钩", 20, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, C.TEXT_W)

    -- 快捷键提示
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 100))
    nvgText(vg, panelX + panelW - 12, panelY + TITLE_H * 0.5, "J 键关闭", nil)

    -- 关闭按钮
    local closeSz = 26
    local closeX  = panelX + panelW - closeSz - 8
    local closeY  = panelY + (TITLE_H - closeSz) * 0.5
    nvgBeginPath(vg)
    nvgRoundedRect(vg, closeX, closeY, closeSz, closeSz, 6)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 70))
    nvgFill(vg)
    BoldText(vg, closeX + closeSz * 0.5, closeY + closeSz * 0.5,
        "✕", 13, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, C.TEXT_W)
    addHit("close", closeX, closeY, closeSz, closeSz)

    -- ── 5 张卡片 ──────────────────────────────────────────────────────────
    local cardsStartX = panelX + PAD_H
    local cardsY      = panelY + TITLE_H + PAD_V

    for i = 1, totalCards do
        local hook  = HOOKS[i]
        local cx    = cardsStartX + (i - 1) * (CARD_W + CARD_GAP)
        local cy    = cardsY
        local isSel = (i == equipped)
        local isHov = (i == hovered_)

        -- 卡片底色
        local bgColor = isSel and C.CARD_SEL or (isHov and C.CARD_HOV or C.CARD_BG)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cx, cy, CARD_W, CARD_H, 8)
        nvgFillColor(vg, rgba(bgColor))
        nvgFill(vg)

        -- 外框
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cx, cy, CARD_W, CARD_H, 8)
        if isSel then
            nvgStrokeColor(vg, rgba(C.RING_SEL))
            nvgStrokeWidth(vg, 2.5)
        elseif isHov then
            nvgStrokeColor(vg, rgba(C.RING_HOV))
            nvgStrokeWidth(vg, 2)
        else
            nvgStrokeColor(vg, rgba(C.BORDER))
            nvgStrokeWidth(vg, 1)
        end
        nvgStroke(vg)

        -- 图标区背景
        local iconH = CARD_H * 0.52
        nvgBeginPath(vg)
        nvgRoundedRectVarying(vg, cx+1, cy+1, CARD_W-2, iconH, 7, 7, 0, 0)
        nvgFillColor(vg, nvgRGBA(8, 12, 22, 255))
        nvgFill(vg)

        -- 鱼钩图标
        local iconR = math.min(CARD_W, iconH) * 0.28
        DrawHookIcon(vg, cx + CARD_W * 0.5, cy + iconH * 0.5, iconR, i, hook.color)

        -- 等级色块（左上角角标）
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cx + 6, cy + 6, 18, 18, 4)
        nvgFillColor(vg, nvgRGBA(hook.color[1], hook.color[2], hook.color[3], 180))
        nvgFill(vg)
        nvgFontFace(vg, "sans-bold")
        nvgFontSize(vg, 11)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 220))
        nvgText(vg, cx + 15, cy + 15, tostring(i), nil)

        -- 已装备 √ 标记
        if isSel then
            local mkX = cx + CARD_W - 24
            local mkY = cy + 6
            nvgBeginPath(vg)
            nvgRoundedRect(vg, mkX, mkY, 18, 18, 4)
            nvgFillColor(vg, nvgRGBA(80, 200, 120, 220))
            nvgFill(vg)
            BoldText(vg, mkX + 9, mkY + 9, "✓", 11,
                NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, C.TEXT_W)
        end

        -- 钩名
        local nameY = cy + iconH + 11
        nvgFontFace(vg, "sans-bold")
        nvgFontSize(vg, 15)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(hook.color[1], hook.color[2], hook.color[3], 255))
        nvgText(vg, cx + CARD_W * 0.5, nameY, hook.name, nil)

        -- 副标题
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 11)
        nvgFillColor(vg, rgba(C.TEXT_DIM))
        nvgText(vg, cx + CARD_W * 0.5, nameY + 18, hook.desc, nil)

        -- 分隔线
        local sepY = nameY + 34
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx + 10, sepY)
        nvgLineTo(vg, cx + CARD_W - 10, sepY)
        nvgStrokeColor(vg, rgba(C.SEP))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

        -- 提示文字（多行，按 \n 分割）
        local tipLines = {}
        for line in hook.tip:gmatch("[^\n]+") do
            tipLines[#tipLines+1] = line
        end
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 10.5)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, rgba(C.TEXT_TIP))
        for li, line in ipairs(tipLines) do
            nvgText(vg, cx + CARD_W * 0.5, sepY + 6 + (li - 1) * 14, line, nil)
        end

        -- 底部按钮
        local btnH   = 28
        local btnW   = CARD_W - 16
        local btnX   = cx + 8
        local btnY   = cy + CARD_H - btnH - 8
        local btnCol = isSel and C.EQUIP_DIM or C.EQUIP_BTN
        local btnLbl = isSel and "当前装备" or "装备"

        nvgBeginPath(vg)
        nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 5)
        nvgFillColor(vg, rgba(btnCol))
        nvgFill(vg)
        -- 按钮高光
        if not isSel then
            nvgBeginPath(vg)
            nvgMoveTo(vg, btnX + 6, btnY + 3)
            nvgLineTo(vg, btnX + btnW - 6, btnY + 3)
            nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 40))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)
        end
        BoldText(vg, btnX + btnW * 0.5, btnY + btnH * 0.5, btnLbl, 12,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, C.TEXT_W)

        addHit("card_" .. i, cx, cy, CARD_W, CARD_H)
    end

    -- ── 底部提示 ──────────────────────────────────────────────────────────
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, rgba(C.TEXT_DIM))
    nvgText(vg, panelX + panelW * 0.5,
        panelY + TITLE_H + PAD_V + CARD_H + 5,
        "单击卡片装备鱼钩  J 键快速切换关闭", nil)

    -- 整体面板注册点击区（用于"点击遮罩外关闭"逻辑的补全）
    addHit("panel", panelX, panelY, panelW, panelH)
end

return HookSelector
