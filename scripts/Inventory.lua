-- ============================================================================
-- Inventory: 背包 UI 渲染模块
-- ============================================================================
-- 纯展示层，不管理数据。由 main.lua 传入所需上下文。
-- ============================================================================

local Inventory = {}

-- ── 常量 ────────────────────────────────────────────────────────────────────
local BAG_COLS    = 4      -- 网格列数
local BAG_ROWS    = 5      -- 网格行数 (4×5=20格)
local SLOT_W      = 88     -- 格子宽
local SLOT_H      = 72     -- 格子高
local SLOT_PAD    = 8      -- 格子间距

-- ── 内部状态 ────────────────────────────────────────────────────────────────
local tab         = 1      -- 1=装备, 2=渔获
local cursor      = 1      -- 当前选中格子 (1~20)，0=无选中

-- ── 颜色常量 ────────────────────────────────────────────────────────────────
local C_BG         = { 12,  22,  45,  210 }
local C_BORDER     = { 80,  160, 240, 160 }
local C_OVERLAY    = { 0,   0,   0,   120 }
local C_TITLE      = { 200, 220, 255, 255 }
local C_TAB_ON     = { 100, 200, 255, 255 }
local C_TAB_OFF    = { 120, 130, 150, 180 }
local C_TAB_BG_ON  = { 40,  80,  140, 160 }
local C_LABEL      = { 180, 195, 220, 220 }
local C_VALUE      = { 230, 240, 255, 255 }
local C_DIM        = { 130, 140, 160, 180 }
local C_GOLD       = { 255, 220, 80,  240 }
local C_WOOD       = { 210, 175, 110, 240 }
local C_HEADER     = { 140, 160, 190, 200 }
local C_SUM_LINE   = { 80,  100, 140, 120 }
local C_SUM_TEXT   = { 200, 220, 255, 240 }
local C_SLOT_EMPTY = { 20,  35,  65,  180 }
local C_SLOT_FILL  = { 30,  55,  95,  200 }
local C_SLOT_SEL   = { 60,  140, 240, 220 }
local C_STARS      = { 255, 200, 50,  255 }

-- ── 辅助 ────────────────────────────────────────────────────────────────────
local function rgba(c)
    return nvgRGBA(c[1], c[2], c[3], c[4])
end

local function rodStateText(state)
    local map = {
        idle     = { "待机",     130, 130, 140 },
        trolling = { "拖钓中",   100, 255, 150 },
        bite     = { "咬钩!",    255, 200,  50 },
        strike   = { "提竿!",    255, 255, 100 },
        casting  = { "抛投...",  150, 200, 255 },
    }
    local m = map[state] or { state, 180, 180, 180 }
    return m[1], m[2], m[3], m[4]
end

local function rodSideText(side)
    return side == -1 and "左舷" or "右舷"
end

-- ── 按键处理 ────────────────────────────────────────────────────────────────
function Inventory.HandleKey(key)
    if key == KEY_LEFT or key == KEY_RIGHT then
        tab = (key == KEY_LEFT) and 1 or 2
        cursor = 1
        return true
    end

    if tab == 2 then
        -- 渔获页：方向键移动网格光标
        local totalSlots = BAG_COLS * BAG_ROWS  -- 20
        if key == KEY_UP then
            cursor = cursor - BAG_COLS
            if cursor < 1 then cursor = cursor + totalSlots end
            return true
        elseif key == KEY_DOWN then
            cursor = cursor + BAG_COLS
            if cursor > totalSlots then cursor = cursor - totalSlots end
            return true
        elseif key == KEY_LEFT then
            cursor = cursor - 1
            if cursor < 1 then cursor = totalSlots end
            return true
        elseif key == KEY_RIGHT then
            cursor = cursor + 1
            if cursor > totalSlots then cursor = 1 end
            return true
        end
    end
    return false
end

--- 重置状态（关闭时调用）
function Inventory.Reset()
    tab    = 1
    cursor = 1
end

-- ── 主绘制函数 ──────────────────────────────────────────────────────────────
function Inventory.Draw(vg, sw, sh, ctx)
    -- 网格区域宽 = 4列 × (格子宽+间距) + 左右内边距
    local gridW = BAG_COLS * (SLOT_W + SLOT_PAD) - SLOT_PAD
    local pw    = math.max(gridW + 40, 400)  -- 面板宽至少容纳网格
    local ph    = math.min(520, sh - 40)
    local px    = math.floor((sw - pw) / 2)
    local py    = math.floor((sh - ph) / 2)

    -- 遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, sw, sh)
    nvgFillColor(vg, rgba(C_OVERLAY))
    nvgFill(vg)

    -- 面板背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px, py, pw, ph, 10)
    nvgFillColor(vg, rgba(C_BG))
    nvgFill(vg)
    nvgStrokeColor(vg, rgba(C_BORDER))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 标题栏
    local titleH = 38
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 18)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, rgba(C_TITLE))
    nvgText(vg, px + 16, py + titleH * 0.5, "背包", nil)

    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, rgba(C_DIM))
    nvgText(vg, px + pw - 12, py + titleH * 0.5, "[B] 关闭", nil)

    nvgBeginPath(vg)
    nvgMoveTo(vg, px + 10, py + titleH)
    nvgLineTo(vg, px + pw - 10, py + titleH)
    nvgStrokeColor(vg, rgba(C_SUM_LINE))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 标签栏
    local tabY = py + titleH + 4
    local tabH = 28
    local tabs = { "装备", "渔获" }
    local tabW = 70
    for i, label in ipairs(tabs) do
        local tx  = px + 12 + (i - 1) * (tabW + 8)
        local isOn = (i == tab)
        if isOn then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, tx, tabY, tabW, tabH, 6)
            nvgFillColor(vg, rgba(C_TAB_BG_ON))
            nvgFill(vg)
        end
        nvgFontSize(vg, 14)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, rgba(isOn and C_TAB_ON or C_TAB_OFF))
        nvgText(vg, tx + tabW / 2, tabY + tabH / 2, label, nil)
    end

    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, rgba(C_DIM))
    nvgText(vg, px + pw - 12, tabY + tabH / 2, "← → 切换", nil)

    -- 内容区
    local contentY = tabY + tabH + 8
    local contentH = py + ph - contentY - 10

    if tab == 1 then
        Inventory._DrawEquipment(vg, px, contentY, pw, contentH, ctx)
    else
        Inventory._DrawCatch(vg, px, contentY, pw, contentH, ctx)
    end
end

-- ── 装备页 ──────────────────────────────────────────────────────────────────
function Inventory._DrawEquipment(vg, px, cy, pw, ch, ctx)
    local rods      = ctx.rods
    local activeRod = ctx.activeRod
    local PD        = ctx.PlayerData

    local y = cy + 6

    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, rgba(C_HEADER))
    nvgText(vg, px + 16, y, "鱼竿", nil)
    y = y + 22

    for i = 1, #rods do
        local rod      = rods[i]
        local isActive = (i == activeRod)
        if isActive then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, px + 12, y - 2, pw - 24, 24, 4)
            nvgFillColor(vg, nvgRGBA(40, 80, 140, 80))
            nvgFill(vg)
        end
        nvgFontSize(vg, 14)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFillColor(vg, rgba(isActive and C_VALUE or C_LABEL))
        nvgText(vg, px + 20, y, "竿" .. i .. "  [" .. rodSideText(rod.side) .. "]", nil)
        local stText, sr, sg, sb = rodStateText(rod.state)
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(sr, sg, sb, 240))
        nvgText(vg, px + pw - 20, y, stText, nil)
        y = y + 28
    end

    y = y + 4
    nvgBeginPath(vg)
    nvgMoveTo(vg, px + 16, y)
    nvgLineTo(vg, px + pw - 16, y)
    nvgStrokeColor(vg, rgba(C_SUM_LINE))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
    y = y + 12

    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, rgba(C_HEADER))
    nvgText(vg, px + 16, y, "资源", nil)
    y = y + 24

    nvgFontSize(vg, 15)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, rgba(C_GOLD))
    nvgText(vg, px + 20, y, "💰  金钱", nil)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    nvgFillColor(vg, rgba(C_VALUE))
    nvgText(vg, px + pw - 20, y, tostring(PD.GetMoney()), nil)
    y = y + 26

    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, rgba(C_WOOD))
    nvgText(vg, px + 20, y, "🪵  木料", nil)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    nvgFillColor(vg, rgba(C_VALUE))
    nvgText(vg, px + pw - 20, y, tostring(PD.GetResource("wood")), nil)
end

-- ── 渔获页（网格背包）────────────────────────────────────────────────────────
function Inventory._DrawCatch(vg, px, cy, pw, ch, ctx)
    local list      = ctx.caughtList
    local count     = #list
    local bagSize   = BAG_COLS * BAG_ROWS   -- 20
    local totalW    = ctx.totalWeight

    -- 网格起始坐标（居中）
    local gridTotalW = BAG_COLS * (SLOT_W + SLOT_PAD) - SLOT_PAD
    local gridX      = px + math.floor((pw - gridTotalW) / 2)
    local gridY      = cy + 6

    -- ── 绘制所有格子 ──
    for slot = 1, bagSize do
        local col  = (slot - 1) % BAG_COLS
        local row  = math.floor((slot - 1) / BAG_COLS)
        local sx   = gridX + col * (SLOT_W + SLOT_PAD)
        local sy   = gridY + row * (SLOT_H + SLOT_PAD)

        local fish    = list[slot]
        local isHover = (slot == cursor)

        -- 格子背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, sx, sy, SLOT_W, SLOT_H, 6)
        if isHover then
            nvgFillColor(vg, nvgRGBA(50, 100, 180, 200))
        elseif fish then
            nvgFillColor(vg, rgba(C_SLOT_FILL))
        else
            nvgFillColor(vg, rgba(C_SLOT_EMPTY))
        end
        nvgFill(vg)

        -- 格子边框
        nvgStrokeWidth(vg, isHover and 2.0 or 1.0)
        if isHover then
            nvgStrokeColor(vg, rgba(C_SLOT_SEL))
        else
            nvgStrokeColor(vg, nvgRGBA(60, 90, 140, 100))
        end
        nvgStroke(vg)

        -- 格子序号（右下角）
        nvgFontSize(vg, 9)
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
        nvgFillColor(vg, nvgRGBA(80, 100, 140, 120))
        nvgText(vg, sx + SLOT_W - 4, sy + SLOT_H - 2, tostring(slot), nil)

        if fish then
            local ft = fish.type
            local fc = ft.color or {180, 200, 220}

            -- 鱼种颜色圆点
            nvgBeginPath(vg)
            nvgCircle(vg, sx + 16, sy + 18, 7)
            nvgFillColor(vg, nvgRGBA(fc[1], fc[2], fc[3], 220))
            nvgFill(vg)

            -- 鱼名（最多8个字符，超出用省略号）
            local name = ft.name
            if #name > 6 then name = string.sub(name, 1, 6) .. ".." end
            nvgFontSize(vg, 13)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(fc[1] + 60, fc[2] + 60, fc[3] + 60, 255))
            -- 颜色不超过255
            nvgFillColor(vg, nvgRGBA(
                math.min(255, fc[1] + 60),
                math.min(255, fc[2] + 60),
                math.min(255, fc[3] + 60), 255))
            nvgText(vg, sx + 6, sy + 8, name, nil)

            -- 重量
            nvgFontSize(vg, 11)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(180, 210, 255, 200))
            nvgText(vg, sx + 6, sy + 28, FormatWeight(fish.weight), nil)

            -- 难度星（最多5颗）
            nvgFontSize(vg, 11)
            nvgFillColor(vg, rgba(C_STARS))
            nvgText(vg, sx + 6, sy + 46, string.rep("★", math.min(5, ft.diff or 1)), nil)
        end
    end

    -- ── 底部信息栏 ──
    local infoY = gridY + BAG_ROWS * (SLOT_H + SLOT_PAD) - SLOT_PAD + 10

    -- 分隔线
    nvgBeginPath(vg)
    nvgMoveTo(vg, px + 16, infoY)
    nvgLineTo(vg, px + pw - 16, infoY)
    nvgStrokeColor(vg, rgba(C_SUM_LINE))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
    infoY = infoY + 8

    -- 左：格子占用
    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, rgba(C_SUM_TEXT))
    nvgText(vg, px + 16, infoY,
        string.format("背包 %d / %d", count, bagSize), nil)

    -- 右：总重
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(255, 220, 100, 220))
    nvgText(vg, px + pw - 16, infoY,
        "总重: " .. FormatWeight(totalW), nil)

    -- ── 选中格子详情 ──
    local selFish = list[cursor]
    if selFish then
        local detailY = infoY + 24
        local ft      = selFish.type
        local fc      = ft.color or {180, 200, 220}
        nvgFontSize(vg, 12)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(fc[1], fc[2], fc[3], 240))
        nvgText(vg, px + 16, detailY, ft.name, nil)
        nvgFillColor(vg, rgba(C_VALUE))
        nvgText(vg, px + 100, detailY, FormatWeight(selFish.weight), nil)
        nvgFillColor(vg, rgba(C_STARS))
        nvgText(vg, px + 200, detailY, string.rep("★", math.min(5, ft.diff or 1)), nil)
        nvgFillColor(vg, rgba(C_DIM))
        nvgText(vg, px + pw - 16 - 60, detailY, "↑↓←→ 导航", nil)
    else
        local detailY = infoY + 24
        nvgFontSize(vg, 12)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFillColor(vg, rgba(C_DIM))
        nvgText(vg, px + 16, detailY, "空格", nil)
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
        nvgText(vg, px + pw - 16, detailY, "↑↓←→ 导航", nil)
    end
end

return Inventory
