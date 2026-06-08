-- ============================================================================
-- Inventory: 背包 UI 渲染模块（木质像素 RPG 风格）
-- ============================================================================
-- 纯展示层，不管理数据。由 main.lua 传入所需上下文。
-- ============================================================================

local RodShop = require "RodShop"

local Inventory = {}

-- ── 装备图标（来自 RodShop 共享句柄）────────────────────────────────────────
local imgItem_   = nil  ---@type table
local itemW_     = nil  ---@type table
local itemH_     = nil  ---@type table

-- 渔轮：1→切4, 2→切5, 3→切3, 4→切2, 5→切1
local REEL_ICON_SLICE = { 4, 5, 3, 2, 1 }
-- 鱼竿：1→切9, 2→切10, 3→切7, 4→切6, 5→切8
local ROD_ICON_SLICE  = { 9, 10, 7, 6, 8 }

function Inventory.Init(vg)
    imgItem_, itemW_, itemH_ = RodShop.GetItemImages()

end

-- ── 常量 ────────────────────────────────────────────────────────────────────
local BAG_COLS    = 4      -- 网格列数
local BAG_ROWS    = 5      -- 网格行数 (4×5=20格)
local SLOT_W      = 80     -- 格子宽
local SLOT_H      = 64     -- 格子高
local SLOT_PAD    = 6      -- 格子间距

-- ── 鱼类精灵图映射 (fish ID → 精灵图坐标) ────────────────────────────────
-- sheet=1: fish_01.png,   512×96,  每格 32×32
-- sheet=2: fish_02ui.png, 128×128, 每格 32×32
-- sheet=3: fish_03ui.png, 160×32,  每格 32×32 (5列×1行)
-- sheet=4: fish_04ui.png, 128×96,  每格 32×32 (4列×3行)
local FISH_SPRITE_MAP = {}
do
    local layout1 = {
        { 56, 58, 32, 30, 29, 37, 61, 59, 51, 45, 25, 43, 19, 65, 57, 49 },
        { 26, 31, 39, 52, 41, 48, 42, 63, 62, 47, 33, 55, 64, 53, 36, 50 },
        { 40, 54, 22, 44, 60 },
    }
    for row = 1, #layout1 do
        for col = 1, #layout1[row] do
            FISH_SPRITE_MAP[layout1[row][col]] = { col = col-1, row = row-1, sheet = 1 }
        end
    end
    local layout2 = {
        {  3, 27,  9,  8 },
        {  5, 17, 23, 28 },
        { 35, 66, 38, 67 },
        { 46, 20 },
    }
    for row = 1, #layout2 do
        for col = 1, #layout2[row] do
            FISH_SPRITE_MAP[layout2[row][col]] = { col = col-1, row = row-1, sheet = 2 }
        end
    end
    local layout3 = {
        { 10, 1, 4, 7, 2 },
    }
    for row = 1, #layout3 do
        for col = 1, #layout3[row] do
            FISH_SPRITE_MAP[layout3[row][col]] = { col = col-1, row = row-1, sheet = 3 }
        end
    end
    local layout4 = {
        { 21, 13, 11, 34 },
        { 12, 14,  6, 16 },
        { 18, 15, 24 },
    }
    for row = 1, #layout4 do
        for col = 1, #layout4[row] do
            FISH_SPRITE_MAP[layout4[row][col]] = { col = col-1, row = row-1, sheet = 4 }
        end
    end
end

-- 精灵图图集参数（sheet 编号 → { sheetW, sheetH }）
local SHEET_INFO = {
    [1] = { w = 512, h =  96 },  -- fish_01.png
    [2] = { w = 128, h = 128 },  -- fish_02ui.png
    [3] = { w = 160, h =  32 },  -- fish_03ui.png
    [4] = { w = 128, h =  96 },  -- fish_04ui.png
}

-- ── 内部状态 ────────────────────────────────────────────────────────────────
local tab         = 1      -- 1=鱼竿, 2=渔获
local cursor      = 1      -- 渔获页光标 (1~20)
local equipCursor = 0      -- 鱼竿页光标 (0=未选, 1~N=物品索引)
local _equipHits  = {}     -- 鱼竿页格子 hitbox { {x,y,w,h,idx}, ... }

-- ── 木质 RPG 配色 ─────────────────────────────────────────────────────────
local C_FRAME_OUT  = { 101,  68,  32, 255 }
local C_FRAME_IN   = { 139, 101,  56, 255 }
local C_FRAME_LITE = { 185, 148,  88, 255 }
local C_PANEL_BG   = { 210, 175, 110, 255 }
local C_INSET_BG   = { 180, 140,  72, 220 }
local C_SLOT_EMPTY = { 195, 158,  90, 255 }
local C_SLOT_FILL  = { 200, 165,  98, 255 }
local C_SLOT_SEL   = { 235, 195, 110, 255 }
local C_SLOT_BDR   = { 139, 101,  56, 200 }
local C_SLOT_SEL_B = {  90,  50,  15, 255 }
local C_ROD_SLOT   = { 170, 128,  58, 255 }   -- 鱼竿细长格背景（略暗）
local C_ROD_ACT    = { 240, 200, 120, 255 }   -- 激活鱼竿格高亮
local C_TEXT_DARK  = {  60,  30,   8, 255 }
local C_TEXT_MID   = { 100,  65,  20, 230 }
local C_TEXT_LIGHT = { 155, 115,  55, 200 }
local C_TEXT_HINT  = { 130,  95,  40, 160 }   -- 格子占位提示文字
local C_TAB_ON_BG  = { 235, 195, 110, 255 }
local C_TAB_OFF_BG = { 170, 130,  68, 200 }
local C_TAB_ON_T   = {  60,  30,   8, 255 }
local C_TAB_OFF_T  = { 120,  85,  35, 200 }
local C_GOLD       = { 200, 140,   0, 255 }
local C_STARS      = { 200, 120,  10, 255 }
local C_SEP        = { 120,  85,  40, 120 }
local C_OVERLAY    = {   0,   0,   0, 140 }
local C_ST_IDLE    = { 140, 120,  80, 255 }
local C_ST_TROLL   = {  60, 160,  80, 255 }
local C_ST_BITE    = { 210, 140,  10, 255 }
local C_ST_STRIKE  = { 220, 200,  20, 255 }
local C_ST_CAST    = { 100, 150, 210, 255 }

-- ── 辅助 ────────────────────────────────────────────────────────────────────
local function rgba(c)
    return nvgRGBA(c[1], c[2], c[3], c[4])
end

-- 统一文字绘制：加粗 + 黑描边 + 自定义填充色（默认白色）
local function DrawLabel(vg, x, y, text, size, align, r, g, b, a)
    r, g, b, a = r or 255, g or 255, b or 255, a or 255
    nvgFontFace(vg, "sans-bold")
    nvgFontSize(vg, size)
    nvgTextAlign(vg, align)
    -- 黑色描边（8方向偏移1px）
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 210))
    local offsets = { {-1,-1},{0,-1},{1,-1},{-1,0},{1,0},{-1,1},{0,1},{1,1} }
    for _, d in ipairs(offsets) do
        nvgText(vg, x + d[1], y + d[2], text, nil)
    end
    -- 填充色
    nvgFillColor(vg, nvgRGBA(r, g, b, a))
    nvgText(vg, x, y, text, nil)
end

local function DrawWoodPanel(vg, x, y, w, h, r)
    r = r or 8
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x - 3, y - 3, w + 6, h + 6, r + 3)
    nvgFillColor(vg, rgba(C_FRAME_OUT))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, w, h, r)
    nvgFillColor(vg, rgba(C_PANEL_BG))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x + 4, y + 4, w - 8, h - 8, r - 2)
    nvgStrokeColor(vg, rgba(C_FRAME_IN))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)
    nvgBeginPath(vg)
    nvgMoveTo(vg, x + 8, y + 4)
    nvgLineTo(vg, x + w - 8, y + 4)
    nvgStrokeColor(vg, nvgRGBA(C_FRAME_LITE[1], C_FRAME_LITE[2], C_FRAME_LITE[3], 120))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
end

local function DrawInset(vg, x, y, w, h, r)
    r = r or 4
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, w, h, r)
    nvgFillColor(vg, rgba(C_INSET_BG))
    nvgFill(vg)
    nvgStrokeColor(vg, rgba(C_FRAME_OUT))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)
end

local function DrawTopDiamond(vg, cx, y)
    local s = 10
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx, y - s)
    nvgLineTo(vg, cx + s * 0.7, y)
    nvgLineTo(vg, cx, y + s * 0.6)
    nvgLineTo(vg, cx - s * 0.7, y)
    nvgClosePath(vg)
    nvgFillColor(vg, rgba(C_FRAME_OUT))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx, y - s + 3)
    nvgLineTo(vg, cx + s * 0.5, y)
    nvgLineTo(vg, cx, y + s * 0.4)
    nvgLineTo(vg, cx - s * 0.5, y)
    nvgClosePath(vg)
    nvgFillColor(vg, rgba(C_FRAME_LITE))
    nvgFill(vg)
end

local function DrawSep(vg, x1, x2, y)
    nvgBeginPath(vg)
    nvgMoveTo(vg, x1, y)
    nvgLineTo(vg, x2, y)
    nvgStrokeColor(vg, rgba(C_SEP))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
end

-- 绘制单个格子（通用：支持空格、有物品、选中高亮）
local function DrawSlot(vg, sx, sy, sw, sh, r, isSelected, hasItem, hintText)
    r = r or 5
    nvgBeginPath(vg)
    nvgRoundedRect(vg, sx, sy, sw, sh, r)
    if isSelected then
        nvgFillColor(vg, rgba(C_SLOT_SEL))
    elseif hasItem then
        nvgFillColor(vg, rgba(C_SLOT_FILL))
    else
        nvgFillColor(vg, rgba(C_SLOT_EMPTY))
    end
    nvgFill(vg)
    nvgStrokeColor(vg, rgba(isSelected and C_SLOT_SEL_B or C_SLOT_BDR))
    nvgStrokeWidth(vg, isSelected and 2.0 or 1.0)
    nvgStroke(vg)
    -- 内嵌线（立体感）
    if not isSelected then
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx + 3, sy + 2)
        nvgLineTo(vg, sx + sw - 3, sy + 2)
        nvgStrokeColor(vg, nvgRGBA(100, 65, 20, 55))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx + 3, sy + sh - 2)
        nvgLineTo(vg, sx + sw - 3, sy + sh - 2)
        nvgStrokeColor(vg, nvgRGBA(235, 195, 120, 45))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
    end
    -- 空格占位提示文字（居中）
    if not hasItem and hintText then
        DrawLabel(vg, sx + sw / 2, sy + sh / 2, hintText, 13,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 220, 195, 140, 200)
    end
end

local function rodStateText(state)
    local map = {
        idle     = { "待机",   C_ST_IDLE   },
        trolling = { "拖钓中", C_ST_TROLL  },
        bite     = { "咬钩!",  C_ST_BITE   },
        strike   = { "提竿!",  C_ST_STRIKE },
        casting  = { "抛投…",  C_ST_CAST   },
    }
    local m = map[state] or { state, C_ST_IDLE }
    return m[1], m[2]
end

local function rodSideText(side)
    return side == -1 and "左" or "右"
end

-- ── 按键处理 ────────────────────────────────────────────────────────────────
function Inventory.HandleKey(key)
    -- Tab 切换
    if tab == 1 then
        if key == KEY_RIGHT then tab = 2; cursor = 1; return true end
    else
        if key == KEY_LEFT then tab = 1; return true end
    end

    if tab == 1 then
        -- 鱼竿页：上下左右移动 equipCursor
        local invCount = #_equipHits
        if invCount == 0 then return false end
        local cols = 4
        if equipCursor == 0 then equipCursor = 1; return true end
        if key == KEY_UP then
            equipCursor = equipCursor - cols
            if equipCursor < 1 then equipCursor = math.max(1, invCount) end
            return true
        elseif key == KEY_DOWN then
            equipCursor = equipCursor + cols
            if equipCursor > invCount then equipCursor = 1 end
            return true
        elseif key == KEY_LEFT then
            equipCursor = equipCursor - 1
            if equipCursor < 1 then equipCursor = invCount end
            return true
        elseif key == KEY_RIGHT then
            equipCursor = equipCursor + 1
            if equipCursor > invCount then equipCursor = 1 end
            return true
        end
    elseif tab == 2 then
        local totalSlots = BAG_COLS * BAG_ROWS
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

function Inventory.HandleClick(mx, my)
    if tab == 1 then
        for _, h in ipairs(_equipHits) do
            if mx >= h.x and mx <= h.x + h.w and my >= h.y and my <= h.y + h.h then
                equipCursor = (equipCursor == h.idx) and 0 or h.idx
                return true
            end
        end
    end
    return false
end

function Inventory.Reset()
    tab         = 1
    cursor      = 1
    equipCursor = 0
    _equipHits  = {}
end

-- ── 主绘制函数 ──────────────────────────────────────────────────────────────
function Inventory.Draw(vg, sw, sh, ctx)
    local gridW = BAG_COLS * (SLOT_W + SLOT_PAD) - SLOT_PAD
    local leftW  = 200
    local gap    = 6
    local pw     = leftW + gap + gridW + 48
    local ph     = math.min(540, sh - 40)
    local px     = math.floor((sw - pw) / 2)
    local py     = math.floor((sh - ph) / 2)

    -- 全屏遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, sw, sh)
    nvgFillColor(vg, rgba(C_OVERLAY))
    nvgFill(vg)

    -- 主木质面板
    DrawWoodPanel(vg, px, py, pw, ph, 10)
    DrawTopDiamond(vg, px + pw / 2, py)

    -- 标题
    local titleH = 36
    DrawLabel(vg, px + pw / 2, py + titleH * 0.5, "背 包", 19,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 240, 190)
    DrawLabel(vg, px + pw - 16, py + titleH * 0.5, "[B] 关闭", 13,
        NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE, 220, 195, 140, 200)
    DrawSep(vg, px + 8, px + pw - 8, py + titleH)

    -- 内容区
    local contentY = py + titleH + 6
    local contentH = ph - titleH - 12

    -- 左侧：鱼竿二级背包
    local leftPanX = px + 10
    local leftPanY = contentY + 4
    local leftPanH = contentH - 8
    DrawInset(vg, leftPanX, leftPanY, leftW, leftPanH, 6)
    Inventory._DrawRodPanel(vg, leftPanX, leftPanY, leftW, leftPanH, ctx)

    -- 竖向分隔线
    local sepX = leftPanX + leftW + gap / 2
    nvgBeginPath(vg)
    nvgMoveTo(vg, sepX, contentY + 10)
    nvgLineTo(vg, sepX, contentY + contentH - 10)
    nvgStrokeColor(vg, rgba(C_FRAME_IN))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 右侧：标签栏 + 背包网格
    local rightX = leftPanX + leftW + gap
    local rightW = pw - (rightX - px) - 10
    Inventory._DrawBagArea(vg, rightX, contentY, rightW, contentH, ctx)
end

-- ── 左侧：鱼竿面板 ──────────────────────────────────────────────────────────
-- 上半区：鱼竿列表（可选中切换）
-- 下半区：选中鱼竿的二级背包（鱼竿格 + 4个装备格）
function Inventory._DrawRodPanel(vg, x, y, w, h, ctx)
    local rods      = ctx.rods
    local activeRod = ctx.activeRod
    local pad       = 8
    local cy        = y + pad

    -- ── 上区：鱼竿选择列表 ──
    DrawLabel(vg, x + pad, cy + 5, "▸ 鱼 竿", 12,
        NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, 220, 195, 140, 200)
    cy = cy + 18

    local rodRowH = 26
    for i = 1, #rods do
        local rod   = rods[i]
        local isAct = (i == activeRod)

        if isAct then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, x + pad - 2, cy - 1, w - pad * 2 + 4, rodRowH, 4)
            nvgFillColor(vg, nvgRGBA(C_ROD_ACT[1], C_ROD_ACT[2], C_ROD_ACT[3], 170))
            nvgFill(vg)
            nvgStrokeColor(vg, rgba(C_SLOT_SEL_B))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)
        end

        local rc = isAct and C_TEXT_DARK or C_TEXT_MID
        DrawLabel(vg, x + pad + 4, cy + rodRowH / 2,
            "竿" .. i .. "  [" .. rodSideText(rod.side) .. "舷]", 15,
            NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, rc[1], rc[2], rc[3])

        local stText, stColor = rodStateText(rod.state)
        DrawLabel(vg, x + w - pad, cy + rodRowH / 2, stText, 13,
            NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE, stColor[1], stColor[2], stColor[3])

        cy = cy + rodRowH + 2
    end

    DrawSep(vg, x + pad, x + w - pad, cy + 4)
    cy = cy + 12

    -- ── 下区：选中鱼竿的二级背包 ──
    DrawLabel(vg, x + pad, cy + 5, "▸ 竿" .. activeRod .. " 装备槽", 12,
        NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, 220, 195, 140, 200)
    cy = cy + 16

    -- 剩余可用高度（到面板底部）
    local bottomY   = y + h - pad
    local areaH     = bottomY - cy       -- 装备槽占满这段高度

    -- 水平尺寸
    local subPad    = 5
    local innerW    = w - pad * 2
    local rodSlotW  = 36                 -- 细长鱼竿格宽
    local eqSlotW   = innerW - rodSlotW - subPad  -- 装备格占剩余全宽

    -- 垂直尺寸：鱼竿格高 = areaH；4个装备格均分同样高度（含3个间距）
    local rodSlotH  = areaH
    local eqSlotH   = math.floor((areaH - subPad * 3) / 4)
    -- 重新对齐：让4格总高精确等于 rodSlotH
    -- (eqSlotH * 4 + subPad * 3) 可能比 areaH 少1~3px，用首格补偿
    local eqSlotH1  = areaH - (eqSlotH * 3 + subPad * 3)  -- 第一格稍高补误差

    local startX    = x + pad
    local startY    = cy

    -- 鱼竿细长格
    local rsx = startX
    local rsy = startY
    nvgBeginPath(vg)
    nvgRoundedRect(vg, rsx, rsy, rodSlotW, rodSlotH, 4)
    nvgFillColor(vg, rgba(C_ROD_SLOT))
    nvgFill(vg)
    nvgStrokeColor(vg, rgba(C_SLOT_BDR))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)
    -- 内嵌顶线
    nvgBeginPath(vg)
    nvgMoveTo(vg, rsx + 3, rsy + 3)
    nvgLineTo(vg, rsx + rodSlotW - 3, rsy + 3)
    nvgStrokeColor(vg, nvgRGBA(100, 65, 20, 50))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
    -- 鱼竿图标（若有贴图则绘制，否则显示竖排文字）
    local S = (ctx.sh or 1080) / 1080
    local rodSn = ROD_ICON_SLICE[activeRod]
    if imgItem_ and rodSn and imgItem_[rodSn] and imgItem_[rodSn] > 0 then
        local iw = itemW_[rodSn] * S * 0.9
        local ih = itemH_[rodSn] * S * 0.9
        -- 旋转90°绘制（竿是竖向的，格子也是竖向的，直接缩放放进去）
        -- 如果 ih > rodSlotH 则按高度约束
        if ih > rodSlotH - 8 then
            local scale = (rodSlotH - 8) / ih
            iw = iw * scale
            ih = ih * scale
        end
        if iw > rodSlotW - 4 then
            local scale = (rodSlotW - 4) / iw
            iw = iw * scale
            ih = ih * scale
        end
        -- NanoVG 无法旋转 ImagePattern，将图标缩放后居中平铺（不旋转）
        local pat = nvgImagePattern(vg,
            rsx + rodSlotW * 0.5 - iw * 0.5,
            rsy + rodSlotH * 0.5 - ih * 0.5,
            iw, ih, 0, imgItem_[rodSn], 1.0)
        nvgBeginPath(vg)
        nvgRect(vg,
            rsx + rodSlotW * 0.5 - iw * 0.5,
            rsy + rodSlotH * 0.5 - ih * 0.5,
            iw, ih)
        nvgFillPaint(vg, pat)
        nvgFill(vg)
    else
        nvgSave(vg)
        nvgTranslate(vg, rsx + rodSlotW / 2, rsy + rodSlotH / 2)
        nvgRotate(vg, math.pi / 2)
        DrawLabel(vg, 0, 0, "鱼 竿", 13,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 220, 195, 140, 200)
        nvgRestore(vg)
    end

    -- 4个装备格（1列4格，与鱼竿格上下对齐）
    local eqLabels = { "渔轮", "鱼线", "鱼钩", "鱼饵" }
    local eqX      = startX + rodSlotW + subPad
    local ey       = startY
    local equippedReelId = ctx.equippedReelId or 1
    for i = 1, 4 do
        local slotH = (i == 1) and eqSlotH1 or eqSlotH
        -- 第1格（渔轮）：若有贴图则绘制图标，否则显示占位文字
        local hasIcon = false
        if i == 1 and imgItem_ then
            local reelSn = REEL_ICON_SLICE[equippedReelId]
            if reelSn and imgItem_[reelSn] and imgItem_[reelSn] > 0 then
                hasIcon = true
                DrawSlot(vg, eqX, ey, eqSlotW, slotH, 4, false, true, nil)
                local iw = itemW_[reelSn] * S
                local ih = itemH_[reelSn] * S
                -- 按槽高约束
                if ih > slotH - 8 then
                    local sc = (slotH - 8) / ih
                    iw = iw * sc; ih = ih * sc
                end
                if iw > eqSlotW - 8 then
                    local sc = (eqSlotW - 8) / iw
                    iw = iw * sc; ih = ih * sc
                end
                local pat = nvgImagePattern(vg,
                    eqX + eqSlotW * 0.5 - iw * 0.5,
                    ey  + slotH   * 0.5 - ih * 0.5,
                    iw, ih, 0, imgItem_[reelSn], 1.0)
                nvgBeginPath(vg)
                nvgRect(vg,
                    eqX + eqSlotW * 0.5 - iw * 0.5,
                    ey  + slotH   * 0.5 - ih * 0.5,
                    iw, ih)
                nvgFillPaint(vg, pat)
                nvgFill(vg)
            end
        end
        if not hasIcon then
            DrawSlot(vg, eqX, ey, eqSlotW, slotH, 4, false, false, eqLabels[i])
        end
        ey = ey + slotH + subPad
    end
end

-- ── 右侧背包区域（含标签切换）────────────────────────────────────────────
function Inventory._DrawBagArea(vg, rx, ry, rw, rh, ctx)
    local tabH  = 26
    local tabW  = 68
    local tabY  = ry + 4
    local tabs  = { "鱼竿", "渔获" }
    for i, label in ipairs(tabs) do
        local tx  = rx + (i - 1) * (tabW + 6)
        local isOn = (i == tab)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, tx, tabY, tabW, tabH, 5)
        nvgFillColor(vg, rgba(isOn and C_TAB_ON_BG or C_TAB_OFF_BG))
        nvgFill(vg)
        nvgStrokeColor(vg, rgba(C_FRAME_IN))
        nvgStrokeWidth(vg, isOn and 1.5 or 1.0)
        nvgStroke(vg)
        local tc = isOn and C_TAB_ON_T or C_TAB_OFF_T
        DrawLabel(vg, tx + tabW / 2, tabY + tabH / 2, label, 15,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, tc[1], tc[2], tc[3])
    end

    DrawLabel(vg, rx + rw, tabY + tabH / 2, "← →", 12,
        NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE, 220, 195, 140, 200)

    local contentY = tabY + tabH + 4
    local contentH = rh - (contentY - ry) - 4
    DrawInset(vg, rx, contentY, rw, contentH, 6)

    if tab == 1 then
        Inventory._DrawEquipBag(vg, rx, contentY, rw, contentH, ctx)
    else
        Inventory._DrawCatch(vg, rx, contentY, rw, contentH, ctx)
    end
end

-- ── 装备背包（鱼竿 & 渔线轮）────────────────────────────────────────────
function Inventory._DrawEquipBag(vg, gx, gy, gw, gh, ctx)
    local PD   = ctx.PlayerData
    local inv  = PD and PD.GetInventory() or {}

    -- 每帧重建 hitbox 表
    _equipHits = {}

    local cols   = 4
    local slotW  = 72
    local slotH  = 58
    local padX   = 8
    local padY   = 8
    local totalW = cols * slotW + (cols - 1) * padX
    local sx0    = gx + math.floor((gw - totalW) / 2)
    local sy0    = gy + 8

    -- 空背包提示
    if #inv == 0 then
        DrawLabel(vg, gx + gw / 2, gy + gh / 2, "背包空空如也", 15,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 220, 195, 140, 160)
        return
    end

    for i, item in ipairs(inv) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local sx  = sx0 + col * (slotW + padX)
        local sy  = sy0 + row * (slotH + padY)

        -- 判断是否超出绘制区域
        if sy + slotH > gy + gh then break end

        local isSel = (equipCursor == i)
        DrawSlot(vg, sx, sy, slotW, slotH, 5, isSel, true, nil)

        -- 记录 hitbox
        _equipHits[#_equipHits + 1] = { x = sx, y = sy, w = slotW, h = slotH, idx = i }

        -- 根据物品类型取图标切片
        local sn = nil
        local kindLabel = ""
        if item.type == "rod" and item.rodId then
            sn = ROD_ICON_SLICE[item.rodId]
            kindLabel = "鱼竿"
        elseif item.type == "reel" and item.reelId then
            sn = REEL_ICON_SLICE[item.reelId]
            kindLabel = "渔线轮"
        end

        if sn and imgItem_ and imgItem_[sn] and imgItem_[sn] > 0 then
            local iw = itemW_[sn]
            local ih = itemH_[sn]
            -- 缩放适配格子（留 6px 边距）
            local maxW = slotW - 6
            local maxH = slotH - 18  -- 底部留文字空间
            local scale = math.min(maxW / iw, maxH / ih, 1.0)
            iw = iw * scale
            ih = ih * scale
            local px = sx + (slotW - iw) / 2
            local py = sy + 4
            local pat = nvgImagePattern(vg, px, py, iw, ih, 0, imgItem_[sn], 1.0)
            nvgBeginPath(vg)
            nvgRect(vg, px, py, iw, ih)
            nvgFillPaint(vg, pat)
            nvgFill(vg)
        end

        -- 底部类型标签
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 11)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
        nvgFillColor(vg, nvgRGBA(200, 175, 110, 200))
        nvgText(vg, sx + slotW / 2, sy + slotH - 3, kindLabel)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_BASELINE)
    end
end

-- ── 渔获网格 ─────────────────────────────────────────────────────────────
function Inventory._DrawCatch(vg, gx, gy, gw, gh, ctx)
    local list    = ctx.caughtList
    local count   = #list
    local bagSize = BAG_COLS * BAG_ROWS
    local total   = ctx.totalWeight

    local gridTotalW = BAG_COLS * (SLOT_W + SLOT_PAD) - SLOT_PAD
    local gridTotalH = BAG_ROWS * (SLOT_H + SLOT_PAD) - SLOT_PAD
    local sx0 = gx + math.floor((gw - gridTotalW) / 2)
    local sy0 = gy + 8

    for slot = 1, bagSize do
        local col   = (slot - 1) % BAG_COLS
        local row   = math.floor((slot - 1) / BAG_COLS)
        local sx    = sx0 + col * (SLOT_W + SLOT_PAD)
        local sy    = sy0 + row * (SLOT_H + SLOT_PAD)
        local fish  = list[slot]
        local isSel = (slot == cursor)

        DrawSlot(vg, sx, sy, SLOT_W, SLOT_H, 5, isSel, fish ~= nil, nil)

        -- 格子序号（空格右下角，很淡）
        if not fish then
            nvgFontFace(vg, "sans-bold")
            nvgFontSize(vg, 11)
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
            nvgFillColor(vg, nvgRGBA(120, 85, 40, 70))
            nvgText(vg, sx + SLOT_W - 4, sy + SLOT_H - 3, tostring(slot), nil)
        end

        if fish then
            local ft      = fish.type
            local fc      = ft.color or { 180, 200, 220 }
            local fishId  = ft.id
            local sprCell  = fishId and FISH_SPRITE_MAP[fishId]
            local sheets   = { ctx.fishSheet, ctx.fishSheet2, ctx.fishSheet3, ctx.fishSheet4 }
            local imgSheet = sprCell and sheets[sprCell.sheet]

            -- 精灵图区域：左侧 32×32（与源格子精确 1:1，NEAREST 无失真），垂直居中
            local sprW, sprH = 32, 32
            local sprX = sx + 3
            local sprY = sy + math.floor((SLOT_H - sprH) / 2)

            if sprCell and imgSheet and imgSheet > 0 then
                local si     = SHEET_INFO[sprCell.sheet]
                local cellPx = 32.0
                local scaleX = sprW / cellPx
                local scaleY = sprH / cellPx
                local ox   = sprX - sprCell.col * cellPx * scaleX
                local oy   = sprY - sprCell.row * cellPx * scaleY
                local pat  = nvgImagePattern(vg, ox, oy, si.w * scaleX, si.h * scaleY, 0, imgSheet, 1.0)
                nvgSave(vg)
                nvgScissor(vg, sprX, sprY, sprW, sprH)
                nvgBeginPath(vg)
                nvgRect(vg, sprX, sprY, sprW, sprH)
                nvgFillPaint(vg, pat)
                nvgFill(vg)
                nvgResetScissor(vg)
                nvgRestore(vg)
            else
                -- 无精灵图时回退：彩色圆点
                nvgBeginPath(vg)
                nvgCircle(vg, sprX + sprW / 2, sprY + sprH / 2, 10)
                nvgFillColor(vg, nvgRGBA(fc[1], fc[2], fc[3], 230))
                nvgFill(vg)
                nvgStrokeColor(vg, rgba(C_SLOT_SEL_B))
                nvgStrokeWidth(vg, 0.8)
                nvgStroke(vg)
            end

            -- 鱼名（精灵图右侧）
            local nameX = sprX + sprW + 4
            local name  = ft.name
            if #name > 4 then name = string.sub(name, 1, 4) .. "…" end
            DrawLabel(vg, nameX, sy + 7, name, 14,
                NVG_ALIGN_LEFT + NVG_ALIGN_TOP)

            -- 重量（右下角）
            DrawLabel(vg, sx + SLOT_W - 4, sy + SLOT_H - 4,
                FormatWeight(fish.weight), 12,
                NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM, 255, 230, 120)

            -- 难度星（精灵图右下）
            DrawLabel(vg, nameX, sy + SLOT_H - 4,
                string.rep("★", math.min(5, ft.diff or 1)), 12,
                NVG_ALIGN_LEFT + NVG_ALIGN_BOTTOM, 255, 200, 50)
        end
    end

    -- 底部信息条
    local infoH = 38
    local infoY = gy + gh - infoH - 4
    DrawInset(vg, gx + 4, infoY, gw - 8, infoH, 4)

    DrawLabel(vg, gx + 12, infoY + infoH / 2,
        string.format("背包  %d / %d", count, bagSize), 14,
        NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    DrawLabel(vg, gx + gw - 12, infoY + infoH / 2,
        "总重: " .. FormatWeight(total), 14,
        NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE, 255, 220, 80)

    -- 选中格子详情
    local selFish = list[cursor]
    if selFish then
        local bottomY = sy0 + gridTotalH + 4
        if infoY - bottomY > 14 then
            local ft  = selFish.type
            local fc  = ft.color or {180, 200, 220}
            DrawLabel(vg, gx + 8, bottomY, ft.name, 14,
                NVG_ALIGN_LEFT + NVG_ALIGN_TOP, fc[1], fc[2], fc[3])
            DrawLabel(vg, gx + 8 + 100, bottomY, FormatWeight(selFish.weight), 14,
                NVG_ALIGN_LEFT + NVG_ALIGN_TOP, 255, 230, 120)
            DrawLabel(vg, gx + 8 + 200, bottomY,
                string.rep("★", math.min(5, ft.diff or 1)), 14,
                NVG_ALIGN_LEFT + NVG_ALIGN_TOP, 255, 200, 50)
        end
    end
end

return Inventory
