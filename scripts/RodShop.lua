-- ============================================================================
-- RodShop: 渔具商店 UI
-- 设计稿：1920×1080，缩放基准 S = sh / 1080
-- 切片素材：assets/image/ui/shop_ui/切片N.png
-- 坐标说明：所有 DX/DY 是设计稿绝对坐标（top-left），绘制时直接 * S
-- ============================================================================

local RodShop = {}

-- ── 背包格子屏幕 hitbox（供外部模块读取）─────────────────────────────────────
RodShop.bagSlotHits = {}   -- { {x,y,w,h,fishIdx}, ... } 屏幕空间坐标

-- ── PNG 图像句柄 ──────────────────────────────────────────────────────────────
local img     = {}  -- img[N] 对应 UI 切片N
local imgItem = {}  -- imgItem[N] 对应 item/切片N（装备图标）
local imgHook = {}  -- imgHook[1..5] 对应 item/fishhook/切片N（鱼钩图标）
local imgBait = {}  -- imgBait[1..15] 对应 item/bait/bait_NN.png（鱼饵图标）

-- 装备图原始像素尺寸（1080p 设计稿，px）
local ITEM_W = { 136, 122, 83, 77, 87, 160, 172, 183, 158, 172 }
local ITEM_H = {  96, 118, 73, 68, 99, 160, 168, 179, 159, 168 }
-- 鱼钩图标像素尺寸（实际PNG分辨率）
local HOOK_W = { 104, 95, 108, 102, 102 }
local HOOK_H = { 167, 177, 163, 171, 170 }
-- 鱼竿：1→切9, 2→切10, 3→切7, 4→切6, 5→切8
local ROD_ICON_SLICE = { 9, 10, 7, 6, 8 }

-- ── 切片尺寸（设计稿像素，来自 PNG 分辨率）────────────────────────────────────
local W = {59,120,59,120,295,379,127,127,115,127,665,556,556,911}
local H = {57,120, 56,121, 98,344,128,128, 88,128,827,153,154,1228}
--   1   2   3   4   5   6   7   8   9  10  11  12  13  14

-- ── 切片在设计稿上的绝对坐标（top-left，1920×1080 坐标系）──────────────────────
local DX = {
    [1]=431.2, [2]=109.5, [3]=431.2, [4]=109.5,
    [5]=747.7, [6]=705.3, [7]=1497.3,[8]=1343.8,
    [9]=1728,  [10]=1190.3,[11]=1155.2,[12]=91.2,
    [13]=91.2, [14]=-107.4,
}
local DY = {
    [1]=363.7, [2]=119.3,  [3]=151.2, [4]=331.8,
    [5]=491.8, [6]=102.8,  [7]=321.9, [8]=321.9,
    [9]=54.1,  [10]=321.9, [11]=155.2,[12]=315.2,
    [13]=102.8,[14]=-73.3,
}

-- ── 间距（从重复切片的坐标差推导）────────────────────────────────────────────
-- 行间距：DY[12] - DY[13] = 315.2 - 102.8 = 212.4
local ROW_STEP  = DY[12] - DY[13]   -- ≈ 212.4
-- 格子步进：DX[8] - DX[10] = 1343.8 - 1190.3 = 153.5（横纵共用）
local SLOT_STEP = DX[8]  - DX[10]   -- ≈ 153.5

-- ── 背包格子布局 ─────────────────────────────────────────────────────────────
local GRID_COLS = 4
local GRID_ROWS = 4

-- ── 竿型数据 ─────────────────────────────────────────────────────────────────
local ROD_PRICES = { [1]=0, [2]=1800, [3]=4500, [4]=9000, [5]=18000 }
local ROD_COLORS = {
    [1]={120,180,100}, [2]={100,160,220},
    [3]={200,140, 70}, [4]={200, 80, 60},
    [5]={160,100,220},
}
local ROD_NAMES  = { [1]="溪钓竿", [2]="矶钓竿", [3]="路亚竿", [4]="船钓竿", [5]="重竿" }
-- 鱼竿属性：线拉力（kg）、适配鱼钩等级
local ROD_TENSION  = { [1]="2.7kg", [2]="9kg", [3]="36kg", [4]="95kg", [5]="205kg" }
local ROD_HOOK     = { [1]="微小", [2]="微小&小型", [3]="小型&中型", [4]="中型&大型", [5]="大型&巨型" }

-- ── 渔线轮数据 ────────────────────────────────────────────────────────────────
local REEL_PRICES = { [1]=0, [2]=1200, [3]=3000, [4]=6500, [5]=13000 }
local REEL_NAMES  = { [1]="溪钓轮", [2]="矶钓轮", [3]="路亚轮", [4]="船钓轮", [5]="重型轮" }
-- 渔线轮：1→切4, 2→切5, 3→切3, 4→切2, 5→切1
local REEL_ICON_SLICE = { 4, 5, 3, 2, 1 }

-- ── 鱼钩数据 ──────────────────────────────────────────────────────────────────
local HOOK_PRICES = { [1]=0, [2]=800, [3]=2000, [4]=5000, [5]=12000 }
local HOOK_NAMES  = { [1]="微小钩", [2]="小型钩", [3]="中型钩", [4]="大型钩", [5]="巨大钩" }

-- ── 鱼饵数据 ──────────────────────────────────────────────────────────────────
local BAIT_NAMES = {
    [1]="南极磷虾", [2]="鱼条", [3]="鱿鱼饵", [4]="螺肉", [5]="贝肉",
    [6]="巨型饵鱼", [7]="饵鱼", [8]="鱼块",
    [9]="虾肉", [10]="人造饵", [11]="巨型波趴", [12]="波趴",
    [13]="亮片", [14]="铅笔", [15]="瓜子亮片",
}
local BAIT_PRICES = {
    [1]=50, [2]=80, [3]=120, [4]=100, [5]=100,
    [6]=500, [7]=200, [8]=150,
    [9]=120, [10]=300, [11]=800, [12]=400,
    [13]=350, [14]=450, [15]=250,
}
local BAIT_SIZE = 32  -- 鱼饵图标原始尺寸（正方形32×32）

-- ── 统一商品列表（鱼竿 1-5，渔线轮 6-10，鱼钩 11-15，鱼饵 16-30）───────────
-- item.kind = "rod"|"reel"|"hook"|"bait"
local SHOP_ITEMS = {}
for i = 1, 5 do
    SHOP_ITEMS[i]     = { kind="rod",  id=i, name=ROD_NAMES[i],  price=ROD_PRICES[i],
                          iconSlice=ROD_ICON_SLICE[i] }
end
for i = 1, 5 do
    SHOP_ITEMS[5+i]   = { kind="reel", id=i, name=REEL_NAMES[i], price=REEL_PRICES[i],
                          iconSlice=REEL_ICON_SLICE[i] }
end
for i = 1, 5 do
    SHOP_ITEMS[10+i]  = { kind="hook", id=i, name=HOOK_NAMES[i], price=HOOK_PRICES[i],
                          hookSlice=i }
end
for i = 1, 15 do
    SHOP_ITEMS[15+i]  = { kind="bait", id=i, name=BAIT_NAMES[i], price=BAIT_PRICES[i],
                          baitId=i }
end
local SHOP_ITEM_COUNT = #SHOP_ITEMS  -- 30

-- 每页可见行数（由面板高度决定，硬编码为 4 行与原始布局一致）
local VISIBLE_ROWS = 4

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

local SHEET_INFO = {
    [1] = { w = 512, h =  96 },  -- fish_01.png
    [2] = { w = 128, h = 128 },  -- fish_02ui.png
    [3] = { w = 160, h =  32 },  -- fish_03ui.png
    [4] = { w = 128, h =  96 },  -- fish_04ui.png
}

-- ── 内部状态 ─────────────────────────────────────────────────────────────────
local open_     = false
local selected_ = 0   -- 0 = 未选中（正数 = 商品行 slotIdx，负数 = 背包格）
local _hits     = {}

-- 滚动偏移（单位：行，0 = 顶部）
local scrollOffset_    = 0        -- 当前偏移（整数，0 ~ SHOP_ITEM_COUNT-VISIBLE_ROWS）
local scrollAnim_      = 0.0      -- 动画插值目标，用于平滑滚动（像素偏移）
local scrollAnimSpeed_ = 0.18     -- 每帧向目标靠近的比例（0~1）

-- 购买按钮缩放动画（帧计数器）
local btnAnim_       = 0
local BTN_ANIM_TOTAL = 15

-- 进场动画（帧计数器，倒数到0动画完毕）
local openAnim_       = 0
local OPEN_ANIM_TOTAL = 24

-- 弹性选中动画（帧计数器）
local selAnim_       = 0
local SEL_ANIM_TOTAL = 30

-- ── 缓动函数 ─────────────────────────────────────────────────────────────────
local function easeOutCubic(t)
    t = math.max(0, math.min(1, t))
    return 1 - (1 - t)^3
end

-- 弹性回弹：t=0→0, t=1→1，中间有超弹效果
-- 用法：selScale = 1.0 + SEL_EXTRA * elasticOut(t)，t=1时稳定落在 1.0+SEL_EXTRA
local function elasticOut(t)
    if t <= 0 then return 0 end
    if t >= 1 then return 1 end
    return 2^(-10*t) * math.sin((t*10 - 0.75) * (2*math.pi/3)) + 1
end

-- 选中后的持久放大量（动画结束后保持的缩放）
local SEL_EXTRA = 0.04  -- 1.0 + 0.04 = 1.04

-- ── 图像加载 ─────────────────────────────────────────────────────────────────
function RodShop.Init(vg)
    for i = 1, 14 do
        img[i] = nvgCreateImage(vg, "image/ui/shop_ui/切片"..i..".png", 0)
    end
    for i = 1, 10 do
        imgItem[i] = nvgCreateImage(vg, "image/item/切片"..i..".png", 0)
    end
    for i = 1, 5 do
        imgHook[i] = nvgCreateImage(vg, "image/item/fishhook/切片"..i..".png", 0)
    end
    for i = 1, 15 do
        imgBait[i] = nvgCreateImage(vg, string.format("image/item/bait/bait_%02d.png", i), NVG_IMAGE_NEAREST)
    end
end

-- 供 Inventory 等模块共享同一批句柄，避免重复加载
function RodShop.GetItemImages()
    return imgItem, ITEM_W, ITEM_H
end

--- 返回鱼钩图标句柄和尺寸（供外部模块复用）
function RodShop.GetHookImages()
    return imgHook, HOOK_W, HOOK_H
end

--- 返回鱼饵图标句柄和尺寸（供外部模块复用）
function RodShop.GetBaitImages()
    return imgBait, BAIT_SIZE
end

--- 返回格子高亮底图句柄和尺寸（供外部模块复用）
function RodShop.GetSlotHighlight()
    return img[7], W[7], H[7]
end

-- ── 公开接口 ─────────────────────────────────────────────────────────────────
function RodShop.IsOpen() return open_ end

function RodShop.Open()
    open_          = true
    selected_      = 0
    _hits          = {}
    btnAnim_       = 0
    selAnim_       = 0
    openAnim_      = OPEN_ANIM_TOTAL
    scrollOffset_  = 0
    scrollAnim_    = 0.0
end

function RodShop.Close()
    open_     = false
    _hits     = {}
    btnAnim_  = 0
    selAnim_  = 0
    openAnim_ = 0
end

-- ── 滚轮接口（由 main.lua 在 rodShopOpen 时转发）─────────────────────────────
local SCROLL_STEP = 0.24   -- 每格滚轮移动的行数
function RodShop.HandleScroll(delta)
    if not open_ then return end
    -- delta 是原始像素量（±100/tick），归一化为 ±1
    local dir = (delta > 0) and 1 or -1
    local maxOffset = math.max(0, SHOP_ITEM_COUNT - VISIBLE_ROWS)
    scrollOffset_ = math.max(0, math.min(maxOffset, scrollOffset_ - dir * SCROLL_STEP))
end

-- ── 辅助：计算鱼钩等比缩放尺寸（fit into maxW×maxH）───────────────────────
local function hookFitSize(hn, maxW, maxH)
    local srcW = HOOK_W[hn] or 100
    local srcH = HOOK_H[hn] or 170
    local scale = math.min(maxW / srcW, maxH / srcH)
    return srcW * scale, srcH * scale
end

-- ── 辅助：绘制图片切片（屏幕坐标）────────────────────────────────────────────
local function drawImg(vg, handle, x, y, w, h, alpha)
    if not handle or handle <= 0 then return end
    local paint = nvgImagePattern(vg, x, y, w, h, 0, handle, alpha or 1.0)
    nvgBeginPath(vg)
    nvgRect(vg, x, y, w, h)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
end

-- ── 辅助：按切片编号绘制（设计稿坐标 + 附加偏移）─────────────────────────────
local function drawSlice(vg, n, S, ox, oy, alpha)
    local x = (DX[n] + (ox or 0)) * S
    local y = (DY[n] + (oy or 0)) * S
    drawImg(vg, img[n], x, y, W[n]*S, H[n]*S, alpha)
end

-- ── 辅助：以中心缩放绘制切片（ox/oy 为设计坐标附加偏移）──────────────────────
local function drawSliceScaled(vg, n, S, scale, ox, oy)
    local cx = (DX[n] + (ox or 0) + W[n]*0.5) * S
    local cy = (DY[n] + (oy or 0) + H[n]*0.5) * S
    local sw = W[n]*S*scale
    local sh = H[n]*S*scale
    drawImg(vg, img[n], cx - sw*0.5, cy - sh*0.5, sw, sh)
end

-- ── 辅助：程序化绘制背包面板（替代 slice 11）──────────────────────────────────
local BAG_PANEL_R     = 40       -- 圆角半径（设计稿像素）
local BAG_TITLE_H     = 127.9    -- 标题栏高度（设计稿像素）
local BAG_TITLE_COLOR = { 37, 40, 41 }   -- #252829
local BAG_BODY_COLOR  = { 242, 237, 225 } -- #F2EDE1

local function drawBagPanel(vg, S)
    local x = DX[11] * S
    local y = DY[11] * S
    local w = W[11] * S
    local h = H[11] * S
    local r = BAG_PANEL_R * S
    local titleH = BAG_TITLE_H * S

    -- 1. 整体圆角矩形（标题栏深色）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, w, h, r)
    nvgFillColor(vg, nvgRGBA(BAG_TITLE_COLOR[1], BAG_TITLE_COLOR[2], BAG_TITLE_COLOR[3], 255))
    nvgFill(vg)

    -- 2. 内容区域（底部圆角，顶部直角）
    nvgBeginPath(vg)
    nvgMoveTo(vg, x, y + titleH)
    nvgLineTo(vg, x + w, y + titleH)
    nvgLineTo(vg, x + w, y + h - r)
    nvgArcTo(vg, x + w, y + h, x + w - r, y + h, r)
    nvgLineTo(vg, x + r, y + h)
    nvgArcTo(vg, x, y + h, x, y + h - r, r)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(BAG_BODY_COLOR[1], BAG_BODY_COLOR[2], BAG_BODY_COLOR[3], 255))
    nvgFill(vg)

    -- 3. 标题文字 "背包"
    nvgFontFace(vg, "sans-bold")
    nvgFontSize(vg, 42 * S)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(220, 215, 200, 255))
    nvgText(vg, x + 30 * S, y + titleH * 0.5, "背包", nil)
end

-- ── 辅助：程序化绘制格子（替代 slice 10）─────────────────────────────────────
local SLOT_BORDER_W     = 7.6        -- 边框宽度（设计稿像素）
local SLOT_BORDER_COLOR = { 216, 218, 218 } -- #D8DADA
local SLOT_FILL_COLOR   = { 242, 237, 225 } -- #F2EDE1
local SLOT_CORNER_R     = 8          -- 格子圆角（设计稿像素）

local function drawSlotBg(vg, gx, gy, S)
    local sw = W[10] * S
    local sh = H[10] * S
    local r  = SLOT_CORNER_R * S
    local bw = SLOT_BORDER_W * S

    -- 外层（边框色）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, gx, gy, sw, sh, r)
    nvgFillColor(vg, nvgRGBA(SLOT_BORDER_COLOR[1], SLOT_BORDER_COLOR[2], SLOT_BORDER_COLOR[3], 255))
    nvgFill(vg)

    -- 内层（填充色）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, gx + bw, gy + bw, sw - bw * 2, sh - bw * 2, math.max(1, r - bw))
    nvgFillColor(vg, nvgRGBA(SLOT_FILL_COLOR[1], SLOT_FILL_COLOR[2], SLOT_FILL_COLOR[3], 255))
    nvgFill(vg)
end

-- ── 辅助：hitbox（屏幕坐标）──────────────────────────────────────────────────
local function addHit(id, x, y, w, h) _hits[#_hits+1]={id=id,x=x,y=y,w=w,h=h} end
local function hitTest(mx, my)
    for i = #_hits, 1, -1 do
        local b = _hits[i]
        if mx>=b.x and mx<=b.x+b.w and my>=b.y and my<=b.y+b.h then return b.id end
    end
end

-- ── 辅助：竿型示意图（绘制在图标底框内）────────────────────────────────────────
local function drawRodIcon(vg, cx, cy, w, h, rodId)
    local rc = ROD_COLORS[rodId] or {150,150,150}
    local thk = math.max(1.5, 5.0 - rodId * 0.6)
    local x0,y0 = cx - w*0.38, cy + h*0.25
    local x1,y1 = cx + w*0.40, cy - h*0.20
    for s = 0, 5 do
        local t0,t1 = s/6, (s+1)/6
        local ax = x0+(x1-x0)*t0;  local ay = y0+(y1-y0)*t0 - math.sin(t0*math.pi)*h*0.08
        local bx = x0+(x1-x0)*t1;  local by = y0+(y1-y0)*t1 - math.sin(t1*math.pi)*h*0.08
        nvgBeginPath(vg); nvgMoveTo(vg,ax,ay); nvgLineTo(vg,bx,by)
        nvgStrokeColor(vg, nvgRGBA(rc[1],rc[2],rc[3],220))
        nvgStrokeWidth(vg, thk*(1-t0*0.7)); nvgStroke(vg)
    end
end

-- ── 购买逻辑（商店与背包完全解耦，商品可重复购买）──────────────────────────
-- slotIdx: SHOP_ITEMS 的索引 (1-10)
local function canBuy(slotIdx, PD)
    local item = SHOP_ITEMS[slotIdx]
    if not item then return false end
    return PD.CanAfford(item.price)
end

local function doBuy(slotIdx, PD)
    local item = SHOP_ITEMS[slotIdx]
    if not item then return false, "无效商品" end
    local p = item.price
    if p > 0 and not PD.CanAfford(p) then return false, "金钱不足" end
    if p > 0 then PD.SpendMoney(p) end
    if item.kind == "rod" then
        PD.AddInventoryItem({ type = "rod",  rodId  = item.id })
    elseif item.kind == "reel" then
        PD.AddInventoryItem({ type = "reel", reelId = item.id })
    elseif item.kind == "hook" then
        PD.AddInventoryItem({ type = "hook", hookId = item.id })
    elseif item.kind == "bait" then
        PD.AddInventoryItem({ type = "bait", baitId = item.id })
    end
    return true, "购买成功！"
end

-- ── 主绘制 ───────────────────────────────────────────────────────────────────
function RodShop.Draw(vg, sw, sh, ctx)
    if not open_ then return end
    _hits = {}

    local PD   = ctx.PlayerData
    local eqId = ctx.equippedRodId or 1
    local S    = sh / 1080

    -- ── 进场动画进度 ────────────────────────────────────────────────────────
    local openT = 1.0
    if openAnim_ > 0 then
        openAnim_ = openAnim_ - 1
        openT = easeOutCubic(1.0 - openAnim_ / OPEN_ANIM_TOTAL)
    end
    local leftOffX  =  (1.0 - openT) * (-sw)   -- 左侧从屏幕左侧弹入（屏幕像素偏移）
    local rightOffX =  (1.0 - openT) * sw       -- 右侧从屏幕右侧弹入

    -- ── 弹性选中缩放 ────────────────────────────────────────────────────────
    -- 动画结束后永久保持 1.0+SEL_EXTRA；动画过程中超弹再收回该值
    local selScale = 1.0
    if selected_ ~= 0 then   -- 正数=商品行，负数=背包格，都需要放大
        if selAnim_ > 0 then
            selAnim_ = selAnim_ - 1
            local t = 1.0 - selAnim_ / SEL_ANIM_TOTAL
            selScale = 1.0 + SEL_EXTRA * elasticOut(t)
        else
            selScale = 1.0 + SEL_EXTRA  -- 动画结束后持久保持
        end
    end

    -- ========================================================================
    -- 左侧面板：背景 + 商品列表 + 详情 + 购买按钮
    -- ========================================================================
    nvgSave(vg)
    nvgTranslate(vg, leftOffX, 0)

    -- 1. 切片14：主背景面板
    drawSlice(vg, 14, S)

    -- 2. 左侧商品列表（鱼竿+渔线轮，支持滚动）
    -- ── 平滑滚动动画：scrollAnim_ 插值到目标像素偏移 ────────────────────────
    local targetPixelOff = scrollOffset_ * ROW_STEP * S
    scrollAnim_ = scrollAnim_ + (targetPixelOff - scrollAnim_) * scrollAnimSpeed_
    if math.abs(scrollAnim_ - targetPixelOff) < 0.5 then scrollAnim_ = targetPixelOff end
    local pixelOff = scrollAnim_

    -- 列表可见区域（设计稿坐标：DY[13] 到 DY[13]+ROW_STEP*VISIBLE_ROWS）
    local listTop    = DY[13] * S
    local listBottom = (DY[13] + ROW_STEP * VISIBLE_ROWS) * S
    local listLeft   = DX[13] * S
    local listRight  = (DX[13] + W[13]) * S

    -- 用 Scissor 裁剪超出可见区域的内容（含少量上下余量避免截断行框边缘）
    local clipPadV = 4   -- 上下余量
    local clipPadH = 24  -- 左右余量（扩大以避免选中背景条被裁剪）
    nvgScissor(vg, listLeft - clipPadH, listTop - clipPadV,
                   (listRight - listLeft) + clipPadH*2,
                   (listBottom - listTop) + clipPadV*2)

    for slotIdx = 1, SHOP_ITEM_COUNT do
        local item  = SHOP_ITEMS[slotIdx]
        -- 该行在列表中的视觉行号（从0开始，0=最顶行）
        local visRow = slotIdx - 1
        local stepY  = ROW_STEP * visRow
        -- 实际屏幕 Y 偏移 = 设计坐标 - 滚动像素偏移
        local rowScreenY = stepY * S - pixelOff   -- 相对 DY[13]*S 的偏移量

        -- 判断是否在可见范围内（提前跳过不可见行，减少绘制量）
        local rowTopScreen    = DY[13]*S + rowScreenY
        local rowBottomScreen = rowTopScreen + H[13]*S
        if rowBottomScreen >= listTop - 8 and rowTopScreen <= listBottom + 8 then

            -- 行框（切片13），相对偏移 stepY - (pixelOff/S)
            local adjStepY = stepY - pixelOff / S  -- 设计稿坐标系中的偏移

            if selected_ == slotIdx then
                drawSliceScaled(vg, 13, S, selScale, 0, adjStepY)
            else
                drawSlice(vg, 13, S, 0, adjStepY)
            end

            -- 图标底框（切片2）
            drawSlice(vg, 2, S, 0, adjStepY)

            -- 金币图标（切片3）
            drawSlice(vg, 3, S, 0, adjStepY)

            -- 商品图标（在切片2内部居中）
            local ico_cx = (DX[2] + W[2]*0.5) * S
            local ico_cy = (DY[2] + adjStepY + H[2]*0.5) * S
            local sn = item.iconSlice
            if item.baitId and imgBait[item.baitId] and imgBait[item.baitId] > 0 then
                -- 鱼饵图标（32×32 像素素材，整数3倍放大保持像素清晰）
                local bn = item.baitId
                local maxSz = 96 * S
                drawImg(vg, imgBait[bn], ico_cx - maxSz*0.5, ico_cy - maxSz*0.5, maxSz, maxSz)
            elseif item.hookSlice and imgHook[item.hookSlice] and imgHook[item.hookSlice] > 0 then
                -- 鱼钩图标（等比缩放适配格子）
                local hn = item.hookSlice
                local maxSz = W[2] * S * 0.75
                local iw, ih = hookFitSize(hn, maxSz, maxSz)
                drawImg(vg, imgHook[hn], ico_cx - iw*0.5, ico_cy - ih*0.5, iw, ih)
            elseif sn and imgItem[sn] and imgItem[sn] > 0 then
                local iw = ITEM_W[sn] * S
                local ih = ITEM_H[sn] * S
                drawImg(vg, imgItem[sn], ico_cx - iw*0.5, ico_cy - ih*0.5, iw, ih)
            elseif item.kind == "rod" then
                drawRodIcon(vg, ico_cx, ico_cy, W[2]*S, H[2]*S, item.id)
            end

            -- 商品名文字（切片2 右侧）
            local tx = (DX[2] + W[2] + 10) * S
            local ty = (DY[2] + adjStepY + H[2]*0.5) * S
            local isSelected = (selected_ == slotIdx)
            nvgFontSize(vg, 42*S)
            nvgFontFace(vg, "sans-bold")
            nvgFillColor(vg, isSelected
                and nvgRGBA(0x32, 0x34, 0x35, 255)
                or  nvgRGBA(0x76, 0x7A, 0x7D, 255))
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgText(vg, tx, ty, item.name)

            -- 价格文字（切片3 右侧）
            local px2 = (DX[3] + W[3] + 4) * S
            local py2 = (DY[3] + adjStepY + H[3]*0.5) * S
            nvgFontSize(vg, 42*S)
            nvgFontFace(vg, "sans-bold")
            nvgFillColor(vg, isSelected
                and nvgRGBA(0x32, 0x34, 0x35, 255)
                or  nvgRGBA(0x76, 0x7A, 0x7D, 255))
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgText(vg, px2, py2, tostring(item.price))
            nvgFontFace(vg, "sans")
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_BASELINE)

            -- hitbox（需加上 leftOffX，Y 坐标用实际屏幕位置）
            addHit("row_"..slotIdx,
                listLeft + leftOffX,
                rowTopScreen,
                listRight - listLeft,
                H[13]*S)
        end
    end

    nvgResetScissor(vg)

    -- ── 滚动条（仅当内容超出可见区域时显示）──────────────────────────────────
    local maxOffset = math.max(0, SHOP_ITEM_COUNT - VISIBLE_ROWS)
    if maxOffset > 0 then
        local barX     = listRight + 28 * S
        local barY     = listTop
        local barH     = listBottom - listTop
        local barW     = 6 * S
        -- 轨道
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, barY, barW, barH, barW*0.5)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 60))
        nvgFill(vg)
        -- 滑块
        local thumbRatio = VISIBLE_ROWS / SHOP_ITEM_COUNT
        local thumbH     = math.max(barW * 2, barH * thumbRatio)
        local scrollRatio = (maxOffset > 0) and (scrollOffset_ / maxOffset) or 0
        local thumbY  = barY + (barH - thumbH) * scrollRatio
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, thumbY, barW, thumbH, barW*0.5)
        nvgFillColor(vg, nvgRGBA(200, 180, 100, 180))
        nvgFill(vg)
    end

    -- 3. 切片6：详情卡片（仅在选中时显示）
    if selected_ > 0 then
        drawSlice(vg, 6, S)

        -- 商品名文字
        local selItem = SHOP_ITEMS[selected_]
        local dtx = (DX[6] + W[6]*0.5) * S
        local dty = (DY[6] + 28) * S
        nvgFontSize(vg, 42*S)
        nvgFontFace(vg, "sans-bold")
        nvgFillColor(vg, nvgRGBA(0x32, 0x34, 0x35, 255))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgText(vg, dtx, dty, selItem and selItem.name or "???")
        -- 类型标签
        nvgFontSize(vg, 24*S)
        nvgFontFace(vg, "sans-bold")
        nvgFillColor(vg, nvgRGBA(0x76, 0x7A, 0x7D, 255))
        local kindLabel = ""
        if selItem then
            if selItem.kind == "rod" then kindLabel = "鱼竿"
            elseif selItem.kind == "reel" then kindLabel = "渔线轮"
            elseif selItem.kind == "hook" then kindLabel = "鱼钩"
            elseif selItem.kind == "bait" then kindLabel = "鱼饵"
            end
        end
        nvgText(vg, dtx + 105*S, dty + 15*S, kindLabel)
        nvgFontFace(vg, "sans")
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_BASELINE)

        -- 鱼竿专属属性（鱼竿拉力 / 适配鱼钩）
        if selItem and selItem.kind == "rod" then
            nvgFontSize(vg, 24*S)
            nvgFontFace(vg, "sans-bold")
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            -- 标签(#323435) + 数值(#986B57) 分色居中绘制
            local function drawLabelValue(lbl, val, lx, y)
                local lblAdv = nvgTextBounds(vg, 0, 0, lbl)
                nvgFillColor(vg, nvgRGBA(0x32, 0x34, 0x35, 255))
                nvgText(vg, lx, y, lbl)
                nvgFillColor(vg, nvgRGBA(0x98, 0x6B, 0x57, 255))
                nvgText(vg, lx + lblAdv, y, val)
            end
            local textLeft = (DX[6] + 82) * S
            drawLabelValue("鱼竿拉力：", ROD_TENSION[selItem.id] or "", textLeft, dty + 160*S)
            drawLabelValue("适配鱼钩：", ROD_HOOK[selItem.id] or "",    textLeft, dty + 239*S)
            nvgFontFace(vg, "sans")
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_BASELINE)
        end

        -- 4. 切片5：购买/装备按钮（带缩放动画，仅在选中时显示）
        local btnScale = 1.0
        if btnAnim_ > 0 then
            btnAnim_ = btnAnim_ - 1
            local t = 1.0 - btnAnim_ / BTN_ANIM_TOTAL  -- 0→1
            if t < 0.35 then
                btnScale = 1.0 - 0.10 * (t / 0.35)          -- 压缩 1.0→0.90
            elseif t < 0.65 then
                btnScale = 0.90 + 0.15 * ((t-0.35) / 0.30)  -- 回弹 0.90→1.05
            else
                btnScale = 1.05 - 0.05 * ((t-0.65) / 0.35)  -- 稳定 1.05→1.0
            end
        end
        drawSliceScaled(vg, 5, S, btnScale)

        -- 按钮 hitbox：选中时始终可点击（无论金币是否足够）
        addHit("btn_action", DX[5]*S + leftOffX, DY[5]*S, W[5]*S, H[5]*S)

        -- 金币不足时在按钮下方显示提示
        if not canBuy(selected_, PD) then
            local tipx = (DX[5] + W[5]*0.5) * S
            local tipy = (DY[5] + H[5] + 8) * S
            nvgFontSize(vg, 14*S); nvgFontFace(vg, "sans")
            nvgFillColor(vg, nvgRGBA(240,100,80,220))
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            nvgText(vg, tipx, tipy, "金币不足")
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_BASELINE)
        end
    end

    nvgRestore(vg)

    -- ========================================================================
    -- 右侧面板：背包（等比缩小以适配贴图）
    -- ========================================================================
    local dpr = graphics:GetDPR()
    local isMobile = (dpr >= 2.0) or (sh < 800)  -- DPR高 或 视口小 → 手机
    local BAG_SCALE = isMobile and 1.20 or 0.756

    -- 面板中心点（设计坐标 * S）
    local panelCX = (DX[11] + W[11] * 0.5) * S
    local panelCY = (DY[11] + H[11] * 0.5) * S

    nvgSave(vg)
    nvgTranslate(vg, rightOffX, 0)
    -- 以面板中心为锚点等比缩小
    nvgTranslate(vg, panelCX, panelCY)
    nvgScale(vg, BAG_SCALE, BAG_SCALE)
    nvgTranslate(vg, -panelCX, -panelCY)

    -- 背包面板阴影
    local bagX = DX[11] * S
    local bagY = DY[11] * S
    local bagW = W[11] * S
    local bagH = H[11] * S
    local bagR = BAG_PANEL_R * S
    local sBlur = math.floor(24 * S)
    local sOfs  = math.floor(6 * S)
    local sPaint = nvgBoxGradient(vg, bagX, bagY + sOfs, bagW, bagH, bagR, sBlur,
        nvgRGBA(0, 0, 0, 90), nvgRGBA(0, 0, 0, 0))
    nvgBeginPath(vg)
    nvgRect(vg, bagX - sBlur, bagY - sBlur, bagW + sBlur * 2, bagH + sBlur * 2 + sOfs)
    nvgRoundedRect(vg, bagX, bagY, bagW, bagH, bagR)
    nvgPathWinding(vg, NVG_HOLE)
    nvgFillPaint(vg, sPaint)
    nvgFill(vg)

    -- 5. 右侧背包面板（程序绘制）
    drawBagPanel(vg, S)

    -- 金钱显示面板（背包标题栏右侧）
    do
        local moneyW = 305.7 * S
        local moneyH = 69.3 * S
        local moneyR = moneyH * 0.25  -- 圆角 25%
        local titleH = (DY[10] - DY[11]) * S  -- 标题栏高度
        local moneyX = (DX[11] + W[11]) * S - moneyW - 20 * S  -- 右对齐留边距
        local moneyY = DY[11] * S + (titleH - moneyH) * 0.5    -- 垂直居中
        nvgBeginPath(vg)
        nvgRoundedRect(vg, moneyX, moneyY, moneyW, moneyH, moneyR)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
        nvgFill(vg)
        -- 金币图标 + 数字
        local money = PD.GetMoney and PD.GetMoney() or 0
        local coinH = moneyH * 0.72
        local coinW = coinH * (W[3] / H[3])  -- 保持宽高比
        local gap   = 6 * S
        nvgFontFace(vg, "sans-bold")
        nvgFontSize(vg, 32 * S)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        local moneyStr = tostring(money)
        local textW = nvgTextBounds(vg, 0, 0, moneyStr)
        local totalW = coinW + gap + textW
        local startX = moneyX + (moneyW - totalW) * 0.5
        local cy = moneyY + moneyH * 0.5
        drawImg(vg, img[3], startX, cy - coinH * 0.5, coinW, coinH)
        nvgFillColor(vg, nvgRGBA(255, 215, 60, 255))
        nvgText(vg, startX + coinW + gap, cy, moneyStr, nil)
    end

    -- 6. 背包格子（4×4）—— 装备 + 渔获
    -- 合并列表：先装备物品，后渔获（鱼）
    local inventory  = PD.GetInventory()
    local caughtList = ctx.caughtList or {}
    local fishSheet1 = ctx.fishSheet
    local fishSheet2 = ctx.fishSheet2
    local fishSheet3 = ctx.fishSheet3
    local fishSheet4 = ctx.fishSheet4
    local maxSlots   = GRID_COLS * GRID_ROWS

    -- 构建统一显示列表：{ {kind="equip"|"hook"|"bait"|"fish", ...}, ... }
    local displayList = {}
    for _, item in ipairs(inventory) do
        if item.type == "hook" and item.hookId then
            displayList[#displayList + 1] = { kind = "hook", hookId = item.hookId }
        elseif item.type == "bait" and item.baitId then
            displayList[#displayList + 1] = { kind = "bait", baitId = item.baitId }
        else
            local sn = nil
            if item.type == "rod" and item.rodId then
                sn = ROD_ICON_SLICE[item.rodId]
            elseif item.type == "reel" and item.reelId then
                sn = REEL_ICON_SLICE[item.reelId]
            end
            if sn then
                displayList[#displayList + 1] = { kind = "equip", sn = sn }
            end
        end
    end
    for _, fish in ipairs(caughtList) do
        displayList[#displayList + 1] = { kind = "fish", fish = fish }
    end

    -- 先铺所有空格底图
    for row = 0, GRID_ROWS-1 do
        for col = 0, GRID_COLS-1 do
            local gx = (DX[10] + col*SLOT_STEP) * S
            local gy = (DY[10] + row*SLOT_STEP) * S
            drawSlotBg(vg, gx, gy, S)
        end
    end

    -- 渲染每个格子内容
    for slot = 0, math.min(#displayList, maxSlots) - 1 do
        local entry = displayList[slot + 1]
        local col = slot % GRID_COLS
        local row = math.floor(slot / GRID_COLS)
        local gx  = (DX[10] + col*SLOT_STEP) * S
        local gy  = (DY[10] + row*SLOT_STEP) * S
        local gw  = W[7]*S
        local gh  = H[7]*S
        local isInvSel = (selected_ == -(slot + 1))

        if entry.kind == "equip" then
            -- 装备图标渲染
            local sn = entry.sn
            if isInvSel then
                local gcx = gx + gw*0.5
                local gcy = gy + gh*0.5
                local gw2 = gw * selScale
                local gh2 = gh * selScale
                drawImg(vg, img[7], gcx-gw2*0.5, gcy-gh2*0.5, gw2, gh2)
                if imgItem[sn] and imgItem[sn] > 0 then
                    local iw = ITEM_W[sn] * S * selScale
                    local ih = ITEM_H[sn] * S * selScale
                    drawImg(vg, imgItem[sn], gcx - iw*0.5, gcy - ih*0.5, iw, ih)
                end
            else
                drawImg(vg, img[7], gx, gy, gw, gh)
                if imgItem[sn] and imgItem[sn] > 0 then
                    local iw = ITEM_W[sn] * S
                    local ih = ITEM_H[sn] * S
                    drawImg(vg, imgItem[sn], gx+gw*0.5 - iw*0.5, gy+gh*0.5 - ih*0.5, iw, ih)
                end
            end
        elseif entry.kind == "hook" then
            -- 鱼钩图标渲染（等比缩放）
            local hn = entry.hookId
            if isInvSel then
                local gcx = gx + gw*0.5
                local gcy = gy + gh*0.5
                local gw2 = gw * selScale
                local gh2 = gh * selScale
                drawImg(vg, img[7], gcx-gw2*0.5, gcy-gh2*0.5, gw2, gh2)
                if hn and imgHook[hn] and imgHook[hn] > 0 then
                    local maxSz = gw2 * 0.75
                    local iw, ih = hookFitSize(hn, maxSz, maxSz)
                    drawImg(vg, imgHook[hn], gcx - iw*0.5, gcy - ih*0.5, iw, ih)
                end
            else
                drawImg(vg, img[7], gx, gy, gw, gh)
                if hn and imgHook[hn] and imgHook[hn] > 0 then
                    local maxSz = gw * 0.75
                    local iw, ih = hookFitSize(hn, maxSz, maxSz)
                    drawImg(vg, imgHook[hn], gx+gw*0.5 - iw*0.5, gy+gh*0.5 - ih*0.5, iw, ih)
                end
            end
        elseif entry.kind == "bait" then
            -- 鱼饵图标渲染（正方形）
            local bn = entry.baitId
            if isInvSel then
                local gcx = gx + gw*0.5
                local gcy = gy + gh*0.5
                local gw2 = gw * selScale
                local gh2 = gh * selScale
                drawImg(vg, img[7], gcx-gw2*0.5, gcy-gh2*0.5, gw2, gh2)
                if bn and imgBait[bn] and imgBait[bn] > 0 then
                    -- 补偿 BAG_SCALE，确保最终像素为 32 的整数倍
                    local finalPx = 96  -- 目标最终 3×（96px @1080p）
                    local sz = (finalPx / BAG_SCALE) * S * selScale
                    drawImg(vg, imgBait[bn], gcx - sz*0.5, gcy - sz*0.5, sz, sz)
                end
            else
                drawImg(vg, img[7], gx, gy, gw, gh)
                if bn and imgBait[bn] and imgBait[bn] > 0 then
                    local finalPx = 96
                    local sz = (finalPx / BAG_SCALE) * S
                    drawImg(vg, imgBait[bn], gx+gw*0.5 - sz*0.5, gy+gh*0.5 - sz*0.5, sz, sz)
                end
            end
        elseif entry.kind == "fish" then
            -- 鱼精灵图渲染
            local fish   = entry.fish
            local fishId = fish.type and fish.type.id
            local sprCell = fishId and FISH_SPRITE_MAP[fishId]
            local sheets  = { fishSheet1, fishSheet2, fishSheet3, fishSheet4 }
            local sheet   = sprCell and sheets[sprCell.sheet]

            if isInvSel then
                local gcx = gx + gw*0.5
                local gcy = gy + gh*0.5
                local gw2 = gw * selScale
                local gh2 = gh * selScale
                drawImg(vg, img[7], gcx-gw2*0.5, gcy-gh2*0.5, gw2, gh2)
            else
                drawImg(vg, img[7], gx, gy, gw, gh)
            end

            -- 绘制鱼精灵图（居中；手机端扩大一倍）
            local sprRatio = 1.0
            local sprSize = math.min(gw, gh) * sprRatio
            local sprX = gx + (gw - sprSize) / 2
            local sprY = gy + (gh - sprSize) / 2
            if isInvSel then
                sprSize = sprSize * selScale
                sprX = gx + (gw - sprSize) / 2
                sprY = gy + (gh - sprSize) / 2
            end

            if sprCell and sheet and sheet > 0 then
                local si     = SHEET_INFO[sprCell.sheet]
                local cellPx = 32.0
                local scaleX = sprSize / cellPx
                local scaleY = sprSize / cellPx
                local ox = sprX - sprCell.col * cellPx * scaleX
                local oy = sprY - sprCell.row * cellPx * scaleY
                local pat = nvgImagePattern(vg, ox, oy, si.w * scaleX, si.h * scaleY, 0, sheet, 1.0)
                nvgSave(vg)
                nvgScissor(vg, sprX, sprY, sprSize, sprSize)
                nvgBeginPath(vg)
                nvgRect(vg, sprX, sprY, sprSize, sprSize)
                nvgFillPaint(vg, pat)
                nvgFill(vg)
                nvgResetScissor(vg)
                nvgRestore(vg)
            else
                -- 无精灵图：回退彩色圆点
                local fc = (fish.type and fish.type.color) or {180, 200, 220}
                nvgBeginPath(vg)
                nvgCircle(vg, gx + gw*0.5, gy + gh*0.5, sprSize*0.35)
                nvgFillColor(vg, nvgRGBA(fc[1], fc[2], fc[3], 230))
                nvgFill(vg)
            end
        end

        -- hitbox 需要转换到屏幕坐标（考虑缩放变换）
        local hitX = (gx - panelCX) * BAG_SCALE + panelCX + rightOffX
        local hitY = (gy - panelCY) * BAG_SCALE + panelCY
        local hitW = gw * BAG_SCALE
        local hitH = gh * BAG_SCALE
        addHit("inv_"..( slot+1 ), hitX, hitY, hitW, hitH)
    end

    nvgRestore(vg)
end

-- ── 绘制金币图标（供外部模块复用）───────────────────────────────────────────
-- 在 (x, y) 处绘制金币图标，h 为图标高度，保持宽高比
function RodShop.DrawCoinIcon(vg, x, y, h)
    if img[3] and img[3] > 0 then
        local w = h * (W[3] / H[3])
        drawImg(vg, img[3], x, y, w, h)
        return w  -- 返回实际绘制宽度
    end
    return 0
end

--- 在指定格子位置渲染鱼精灵图（供外部模块复用）
--- @param vg any NanoVG context
--- @param fishId number 鱼类型 ID
--- @param gx number 格子左上角 X（屏幕像素）
--- @param gy number 格子左上角 Y（屏幕像素）
--- @param gw number 格子宽（屏幕像素）
--- @param gh number 格子高（屏幕像素）
--- @param fishSheet1 any sheet1 图片句柄
--- @param fishSheet2 any sheet2 图片句柄
function RodShop.DrawFishSprite(vg, fishId, gx, gy, gw, gh, fishSheet1, fishSheet2, fishSheet3, fishSheet4)
    local sprCell = fishId and FISH_SPRITE_MAP[fishId]
    local sheets  = { fishSheet1, fishSheet2, fishSheet3, fishSheet4 }
    local sheet   = sprCell and sheets[sprCell.sheet]

    local sprSize = math.min(gw, gh) * 1.0
    local sprX    = gx + (gw - sprSize) / 2
    local sprY    = gy + (gh - sprSize) / 2

    if sprCell and sheet and sheet > 0 then
        local si     = SHEET_INFO[sprCell.sheet]
        local cellPx = 32.0
        local scaleX = sprSize / cellPx
        local scaleY = sprSize / cellPx
        local ox = sprX - sprCell.col * cellPx * scaleX
        local oy = sprY - sprCell.row * cellPx * scaleY
        local pat = nvgImagePattern(vg, ox, oy, si.w * scaleX, si.h * scaleY, 0, sheet, 1.0)
        nvgSave(vg)
        nvgScissor(vg, sprX, sprY, sprSize, sprSize)
        nvgBeginPath(vg)
        nvgRect(vg, sprX, sprY, sprSize, sprSize)
        nvgFillPaint(vg, pat)
        nvgFill(vg)
        nvgResetScissor(vg)
        nvgRestore(vg)
    else
        -- 无精灵图：彩色圆点 fallback
        nvgBeginPath(vg)
        nvgCircle(vg, gx + gw * 0.5, gy + gh * 0.5, sprSize * 0.35)
        nvgFillColor(vg, nvgRGBA(180, 200, 220, 230))
        nvgFill(vg)
    end
end

-- ── 返回按钮（单独绘制，确保在小地图之上）────────────────────────────────────
function RodShop.DrawBackButton(vg, sw, sh)
    if not open_ then return end
    local S = sh / 1080
    local dpr = graphics:GetDPR()
    local isMobile = (dpr >= 2.0) or (sh < 800)
    local ox = 0
    if isMobile then
        local BAG_SCALE = 1.20
        ox = SLOT_STEP * S * BAG_SCALE  -- 右移1个背包格子
    end
    local bx = DX[9] * S + ox
    local by = DY[9] * S
    drawImg(vg, img[9], bx, by, W[9] * S, H[9] * S)
    addHit("close", bx, by, W[9] * S, H[9] * S)
end

-- ── 点击处理 ─────────────────────────────────────────────────────────────────
function RodShop.HandleMouseClick(mx, my, ctx)
    if not open_ then return false, nil end
    local id = hitTest(mx, my)
    if not id then return false, nil end

    if id == "close" then
        open_ = false
        return true, {close=true}
    end

    local ri = id:match("^row_(%d+)$")
    if ri then
        local newSel = tonumber(ri)
        if newSel ~= selected_ then
            selected_ = newSel
            selAnim_ = SEL_ANIM_TOTAL  -- 切换选中时触发弹性动画
        end
        return true, nil
    end

    if id == "btn_action" then
        -- 按钮动画始终触发
        btnAnim_ = BTN_ANIM_TOTAL
        local PD = ctx.PlayerData
        -- 只有选中商品行（selected_ > 0）时才尝试购买
        if selected_ > 0 and canBuy(selected_, PD) then
            local ok, msg = doBuy(selected_, PD)
            return true, {bought=ok, message=msg}
        end
        -- 金币不足或未选中：动画触发但不执行逻辑
        return true, nil
    end

    local si = id:match("^inv_(%d+)$")
    if si then
        -- 背包格子用负索引，与商品行正索引区分
        local invIdx = tonumber(si)
        local newSel = -(invIdx)
        if newSel ~= selected_ then
            selected_ = newSel
            selAnim_ = SEL_ANIM_TOTAL
        end
        return true, nil
    end

    return true, nil
end

-- ══════════════════════════════════════════════════════════════════════════════
-- 独立背包面板绘制（供任务面板等场景复用）
-- ctx: { PlayerData, caughtList, fishSheet, fishSheet2 }
-- ══════════════════════════════════════════════════════════════════════════════
function RodShop.DrawBagOnly(vg, sw, sh, ctx)
    -- 确保图片已加载（正常流程 Init 已在 main.lua 中调用）
    if not img[10] or img[10] <= 0 then RodShop.Init(vg) end

    local S   = sh / 1080
    local PD  = ctx.PlayerData
    local dpr = graphics:GetDPR()
    local isMobile = (dpr >= 2.0) or (sh < 800)
    local BAG_SCALE = isMobile and 1.20 or 0.756

    -- 面板中心（与商店相同的设计坐标）
    local panelCX = (DX[11] + W[11] * 0.5) * S
    local panelCY = (DY[11] + H[11] * 0.5) * S

    -- 垂直对齐：手机端上下居中，PC端对齐任务面板底边
    local deltaX = 0
    local deltaY = 0
    if isMobile then
        -- 手机端：垂直居中
        deltaY = sh * 0.5 - panelCY
        -- 向右偏移2个背包格子宽度（屏幕空间）
        deltaX = 2 * SLOT_STEP * S * BAG_SCALE
    else
        -- PC端：底边对齐任务面板
        local QUEST_PY = 211.2
        local QUEST_PH = 693.4
        local questBottom = (QUEST_PY + QUEST_PH * 0.5) * S + QUEST_PH * 0.5 * S * 1.0
        local bagBottom   = panelCY + H[11] * 0.5 * S * BAG_SCALE
        deltaY = questBottom - bagBottom
    end

    nvgSave(vg)
    nvgTranslate(vg, deltaX, deltaY)
    -- 以面板中心为锚点缩放
    nvgTranslate(vg, panelCX, panelCY)
    nvgScale(vg, BAG_SCALE, BAG_SCALE)
    nvgTranslate(vg, -panelCX, -panelCY)

    -- 背包面板阴影
    local bagX = DX[11] * S
    local bagY = DY[11] * S
    local bagW = W[11] * S
    local bagH = H[11] * S
    local bagR = BAG_PANEL_R * S
    local sBlur = math.floor(24 * S)
    local sOfs  = math.floor(6 * S)
    local sPaint = nvgBoxGradient(vg, bagX, bagY + sOfs, bagW, bagH, bagR, sBlur,
        nvgRGBA(0, 0, 0, 90), nvgRGBA(0, 0, 0, 0))
    nvgBeginPath(vg)
    nvgRect(vg, bagX - sBlur, bagY - sBlur, bagW + sBlur * 2, bagH + sBlur * 2 + sOfs)
    nvgRoundedRect(vg, bagX, bagY, bagW, bagH, bagR)
    nvgPathWinding(vg, NVG_HOLE)
    nvgFillPaint(vg, sPaint)
    nvgFill(vg)

    -- 背包面板底图（程序绘制）
    drawBagPanel(vg, S)

    -- 金钱显示面板（背包标题栏右侧）
    do
        local moneyW = 305.7 * S
        local moneyH = 69.3 * S
        local moneyR = moneyH * 0.25  -- 圆角 25%
        local titleH = (DY[10] - DY[11]) * S  -- 标题栏高度
        local moneyX = (DX[11] + W[11]) * S - moneyW - 20 * S  -- 右对齐留边距
        local moneyY = DY[11] * S + (titleH - moneyH) * 0.5    -- 垂直居中
        nvgBeginPath(vg)
        nvgRoundedRect(vg, moneyX, moneyY, moneyW, moneyH, moneyR)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
        nvgFill(vg)
        -- 金币图标 + 数字
        local money = PD.GetMoney and PD.GetMoney() or 0
        local coinH = moneyH * 0.72
        local coinW = coinH * (W[3] / H[3])  -- 保持宽高比
        local gap   = 6 * S
        nvgFontFace(vg, "sans-bold")
        nvgFontSize(vg, 32 * S)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        local moneyStr = tostring(money)
        local textW = nvgTextBounds(vg, 0, 0, moneyStr)
        local totalW = coinW + gap + textW
        local startX = moneyX + (moneyW - totalW) * 0.5
        local cy = moneyY + moneyH * 0.5
        drawImg(vg, img[3], startX, cy - coinH * 0.5, coinW, coinH)
        nvgFillColor(vg, nvgRGBA(255, 215, 60, 255))
        nvgText(vg, startX + coinW + gap, cy, moneyStr, nil)
    end

    -- 4×4 格子
    local inventory  = PD.GetInventory()
    local caughtList = ctx.caughtList or {}
    local fishSheet1 = ctx.fishSheet
    local fishSheet2 = ctx.fishSheet2
    local fishSheet3 = ctx.fishSheet3
    local fishSheet4 = ctx.fishSheet4
    local maxSlots   = GRID_COLS * GRID_ROWS

    -- 清空背包格子 hitbox
    RodShop.bagSlotHits = {}
    local fishStartIdx = 0  -- caughtList 在 displayList 中的起始偏移

    -- 统一显示列表
    local displayList = {}
    for _, item in ipairs(inventory) do
        if item.type == "hook" and item.hookId then
            displayList[#displayList + 1] = { kind = "hook", hookId = item.hookId }
        elseif item.type == "bait" and item.baitId then
            displayList[#displayList + 1] = { kind = "bait", baitId = item.baitId }
        else
            local sn = nil
            if item.type == "rod" and item.rodId then
                sn = ROD_ICON_SLICE[item.rodId]
            elseif item.type == "reel" and item.reelId then
                sn = REEL_ICON_SLICE[item.reelId]
            end
            if sn then
                displayList[#displayList + 1] = { kind = "equip", sn = sn }
            end
        end
    end
    fishStartIdx = #displayList  -- 装备数量（鱼从这之后开始）
    for _, fish in ipairs(caughtList) do
        displayList[#displayList + 1] = { kind = "fish", fish = fish }
    end

    -- 空格底图
    for row = 0, GRID_ROWS - 1 do
        for col = 0, GRID_COLS - 1 do
            local gx = (DX[10] + col * SLOT_STEP) * S
            local gy = (DY[10] + row * SLOT_STEP) * S
            drawSlotBg(vg, gx, gy, S)
        end
    end

    -- 格子内容
    for slot = 0, math.min(#displayList, maxSlots) - 1 do
        local entry = displayList[slot + 1]
        local col = slot % GRID_COLS
        local row = math.floor(slot / GRID_COLS)
        local gx  = (DX[10] + col * SLOT_STEP) * S
        local gy  = (DY[10] + row * SLOT_STEP) * S
        local gw  = W[7] * S
        local gh  = H[7] * S

        if entry.kind == "equip" then
            local sn = entry.sn
            drawImg(vg, img[7], gx, gy, gw, gh)
            if imgItem[sn] and imgItem[sn] > 0 then
                local iw = ITEM_W[sn] * S
                local ih = ITEM_H[sn] * S
                drawImg(vg, imgItem[sn], gx + gw * 0.5 - iw * 0.5, gy + gh * 0.5 - ih * 0.5, iw, ih)
            end
        elseif entry.kind == "hook" then
            local hn = entry.hookId
            drawImg(vg, img[7], gx, gy, gw, gh)
            if hn and imgHook[hn] and imgHook[hn] > 0 then
                local maxSz = gw * 0.75
                local iw, ih = hookFitSize(hn, maxSz, maxSz)
                drawImg(vg, imgHook[hn], gx + gw * 0.5 - iw * 0.5, gy + gh * 0.5 - ih * 0.5, iw, ih)
            end
        elseif entry.kind == "bait" then
            local bn = entry.baitId
            drawImg(vg, img[7], gx, gy, gw, gh)
            if bn and imgBait[bn] and imgBait[bn] > 0 then
                local finalPx = 96
                local sz = (finalPx / BAG_SCALE) * S
                drawImg(vg, imgBait[bn], gx + gw * 0.5 - sz * 0.5, gy + gh * 0.5 - sz * 0.5, sz, sz)
            end
        elseif entry.kind == "fish" then
            local fish   = entry.fish
            local fishId = fish.type and fish.type.id
            local sprCell = fishId and FISH_SPRITE_MAP[fishId]
            local sheets  = { fishSheet1, fishSheet2, fishSheet3, fishSheet4 }
            local sheet   = sprCell and sheets[sprCell.sheet]

            drawImg(vg, img[7], gx, gy, gw, gh)

            -- 鱼精灵图
            local sprSize = math.min(gw, gh) * 1.0
            local sprX    = gx + (gw - sprSize) / 2
            local sprY    = gy + (gh - sprSize) / 2

            if sprCell and sheet and sheet > 0 then
                local si     = SHEET_INFO[sprCell.sheet]
                local cellPx = 32.0
                local scaleX = sprSize / cellPx
                local scaleY = sprSize / cellPx
                local ox = sprX - sprCell.col * cellPx * scaleX
                local oy = sprY - sprCell.row * cellPx * scaleY
                local pat = nvgImagePattern(vg, ox, oy, si.w * scaleX, si.h * scaleY, 0, sheet, 1.0)
                nvgSave(vg)
                nvgScissor(vg, sprX, sprY, sprSize, sprSize)
                nvgBeginPath(vg)
                nvgRect(vg, sprX, sprY, sprSize, sprSize)
                nvgFillPaint(vg, pat)
                nvgFill(vg)
                nvgResetScissor(vg)
                nvgRestore(vg)
            else
                local fc = (fish.type and fish.type.color) or {180, 200, 220}
                nvgBeginPath(vg)
                nvgCircle(vg, gx + gw * 0.5, gy + gh * 0.5, sprSize * 0.35)
                nvgFillColor(vg, nvgRGBA(fc[1], fc[2], fc[3], 230))
                nvgFill(vg)
            end

            -- 选中高亮
            local fishIdx = slot - fishStartIdx + 1
            local bagCur = ctx.bagCursor or {}
            if bagCur[fishIdx] then
                nvgBeginPath(vg)
                nvgRoundedRect(vg, gx - 2, gy - 2, gw + 4, gh + 4, 6)
                nvgStrokeColor(vg, nvgRGBA(0xD3, 0xA7, 0x5A, 255))
                nvgStrokeWidth(vg, 3)
                nvgStroke(vg)
            end

            -- 记录鱼格子的屏幕空间 hitbox（slot 从 0 开始，fishIdx 从 1 开始）
            local hx = deltaX + panelCX + (gx - panelCX) * BAG_SCALE
            local hy = deltaY + panelCY + (gy - panelCY) * BAG_SCALE
            local hw = gw * BAG_SCALE
            local hh = gh * BAG_SCALE
            RodShop.bagSlotHits[#RodShop.bagSlotHits + 1] = {
                x = hx, y = hy, w = hw, h = hh, fishIdx = fishIdx
            }
        end
    end

    nvgRestore(vg)
end

return RodShop
