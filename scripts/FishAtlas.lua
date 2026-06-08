-- ============================================================================
-- FishAtlas: 鱼类图册 UI
-- 基于设计稿 1920×1080 绝对坐标渲染
-- 包含目录模板（4页）和详情模板（67页），通过书签按钮切换
-- ============================================================================

local FishAtlas = {}

-- ── 精灵图映射（供外部模块使用）─────────────────────────────────────────────
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
    [1] = { w = 512, h =  96 },
    [2] = { w = 128, h = 128 },
    [3] = { w = 160, h =  32 },
    [4] = { w = 128, h =  96 },
}

-- ── 图册 UI 布局（设计稿 1920×1080 坐标）────────────────────────────────────
-- 各切片的设计坐标和尺寸
local SLICES = {
    bg         = { x = 310.1,  y = 156.1, w = 1324, h = 891  },  -- 切片5 背景
    catalog    = { x = 455,    y = 132.9, w = 1054, h = 816  },  -- 切片1 目录模板
    detail     = { x = 455,    y = 132.9, w = 1054, h = 816  },  -- 切片7 详情模板
    fishBg     = { x = 946.8,  y = 217.5, w = 489,  h = 321  },  -- 切片6 鱼类素材背景
    pageBar    = { x = 539.3,  y = 65.6,  w = 293,  h = 131  },  -- 切片2 页数显示栏
    btnCatalog = { x = 1436.6, y = 286.7, w = 288,  h = 117  },  -- 切片3 目录按钮
    btnDetail  = { x = 1436.6, y = 435.9, w = 287,  h = 117  },  -- 切片4 详情按钮
    btnExit    = { x = 1839.7, y = 15.9,  w = 109,  h = 108  },  -- 切片11 退出按钮
    btnPrev    = { x = 153.5,  y = 132.9, w = 138,  h = 123  },  -- 切片12 向前翻页
    btnNext    = { x = 1671.1, y = 132.9, w = 137,  h = 123  },  -- 切片13 向后翻页
}

-- 页数配置
local CATALOG_PAGES = 4
local DETAIL_PAGES  = 67

-- ── 模块状态 ────────────────────────────────────────────────────────────────
local isOpen_    = false
local mode_      = "catalog"   -- "catalog" | "detail"
local page_      = 1           -- 当前页码（从1开始）
local vg_        = nil         ---@type NVGContextWrapper NanoVG context
local imgs_      = {}          -- 图片句柄表

-- 精灵相关（供 DrawSprite 使用）
local sheets_    = nil         ---@type table

-- ── 书签弹性动画 ─────────────────────────────────────────────────────────────
local BOOKMARK_SLIDE = 45        -- 抽出距离（设计像素）
local SPRING_K       = 180       -- 弹簧刚度
local SPRING_D       = 14        -- 阻尼
local bmAnim_ = {
    catalogX   = 0,   catalogVel = 0,
    detailX    = 0,   detailVel  = 0,
    lastTime   = 0,
}

-- ── 按钮点击缩放回弹 ─────────────────────────────────────────────────────────
local BTN_SPRING_K   = 300       -- 缩放弹簧刚度（快速回弹）
local BTN_SPRING_D   = 16        -- 缩放弹簧阻尼
local BTN_PRESS_SCALE = 0.75     -- 点击瞬间缩到的比例
local btnScale_ = {
    exit = 1.0,  exitVel = 0,
    prev = 1.0,  prevVel = 0,
    next = 1.0,  nextVel = 0,
}

-- ── 辅助函数 ────────────────────────────────────────────────────────────────
local function drawImg(vg, img, x, y, w, h)
    if not img or img <= 0 then return end
    local paint = nvgImagePattern(vg, x, y, w, h, 0, img, 1.0)
    nvgBeginPath(vg)
    nvgRect(vg, x, y, w, h)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
end

--- 以中心缩放绘制图片
local function drawImgScaled(vg, img, x, y, w, h, scale)
    if not img or img <= 0 then return end
    if scale == 1.0 then
        drawImg(vg, img, x, y, w, h)
        return
    end
    local cx, cy = x + w * 0.5, y + h * 0.5
    local sw, sh = w * scale, h * scale
    local sx, sy = cx - sw * 0.5, cy - sh * 0.5
    local paint = nvgImagePattern(vg, sx, sy, sw, sh, 0, img, 1.0)
    nvgBeginPath(vg)
    nvgRect(vg, sx, sy, sw, sh)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
end

--- 检测点击是否在指定设计坐标区域内
local function hitTest(mx, my, S, slice)
    local sx = slice.x * S
    local sy = slice.y * S
    local sw = slice.w * S
    local sh = slice.h * S
    return mx >= sx and mx <= sx + sw and my >= sy and my <= sy + sh
end

-- ── 获取当前模板的最大页数 ───────────────────────────────────────────────────
local function getMaxPages()
    if mode_ == "catalog" then
        return CATALOG_PAGES
    else
        return DETAIL_PAGES
    end
end

-- ============================================================================
-- 公开接口：精灵绘制（其他模块使用）
-- ============================================================================

--- 在指定中心坐标绘制单条鱼的精灵图
--- @param vg      NVGContextWrapper NanoVG context
--- @param fishId  number  鱼种 id
--- @param sheets  table   { imgSheet1, imgSheet2 }
--- @param cx      number  中心 x
--- @param cy      number  中心 y
--- @param size    number  精灵边长（像素）
--- @param alpha   number  透明度 0~1，默认 1.0
--- @return boolean         是否成功绘制
function FishAtlas.DrawSprite(vg, fishId, sheets, cx, cy, size, alpha)
    alpha = alpha or 1.0
    local sprCell = FISH_SPRITE_MAP[fishId]
    if not sprCell then return false end
    local imgSheet = sheets and sheets[sprCell.sheet]
    if not imgSheet or imgSheet <= 0 then return false end
    local si     = SHEET_INFO[sprCell.sheet] ---@type {w:number, h:number}
    local cellPx = 32.0
    local scale  = size / cellPx
    local x = cx - size * 0.5
    local y = cy - size * 0.5
    local ox = x - sprCell.col * cellPx * scale
    local oy = y - sprCell.row * cellPx * scale
    local pat = nvgImagePattern(vg, ox, oy, si.w * scale, si.h * scale, 0, imgSheet, alpha)
    nvgSave(vg)
    nvgScissor(vg, x, y, size, size)
    nvgBeginPath(vg)
    nvgRect(vg, x, y, size, size)
    nvgFillPaint(vg, pat)
    nvgFill(vg)
    nvgResetScissor(vg)
    nvgRestore(vg)
    return true
end

-- ============================================================================
-- 公开接口：图册 UI
-- ============================================================================

--- 初始化/加载图片资源
--- @param nvgCtx NVGContextWrapper
function FishAtlas.Init(nvgCtx)
    vg_ = nvgCtx
    -- 加载切片图片
    imgs_.bg         = nvgCreateImage(vg_, "image/ui/album/切片5.png", 0)
    imgs_.catalog    = nvgCreateImage(vg_, "image/ui/album/切片1.png", 0)
    imgs_.detail     = nvgCreateImage(vg_, "image/ui/album/切片7.png", 0)
    imgs_.fishBg     = nvgCreateImage(vg_, "image/ui/album/切片6.png", 0)
    imgs_.pageBar    = nvgCreateImage(vg_, "image/ui/album/切片2.png", 0)
    imgs_.btnCatalog = nvgCreateImage(vg_, "image/ui/album/切片3.png", 0)
    imgs_.btnDetail  = nvgCreateImage(vg_, "image/ui/album/切片4.png", 0)
    imgs_.btnExit    = nvgCreateImage(vg_, "image/ui/album/切片11.png", 0)
    imgs_.btnPrev    = nvgCreateImage(vg_, "image/ui/album/切片12.png", 0)
    imgs_.btnNext    = nvgCreateImage(vg_, "image/ui/album/切片13.png", 0)
    print("[FishAtlas] Init done, images loaded")
end

--- 打开图册
function FishAtlas.Open(fishTypes, fishSheet, fishSheet2, fishSheet3, fishSheet4)
    isOpen_ = true
    mode_   = "catalog"
    page_   = 1
    sheets_ = { fishSheet, fishSheet2, fishSheet3, fishSheet4 }
    -- 初始化书签动画：catalog 立即抽出，detail 收回
    bmAnim_.catalogX   = BOOKMARK_SLIDE
    bmAnim_.catalogVel = 0
    bmAnim_.detailX    = 0
    bmAnim_.detailVel  = 0
    bmAnim_.lastTime   = time.elapsedTime
    print("[FishAtlas] Opened, mode=catalog, page=1")
end

--- 关闭图册
function FishAtlas.Close()
    isOpen_ = false
    print("[FishAtlas] Closed")
end

--- 图册是否打开
function FishAtlas.IsOpen()
    return isOpen_
end

--- 处理点击事件（屏幕坐标）
function FishAtlas.HandleClick(mx, my, screenW, screenH)
    if not isOpen_ then return false end
    local S = screenH / 1080

    -- 退出按钮
    if hitTest(mx, my, S, SLICES.btnExit) then
        btnScale_.exit = BTN_PRESS_SCALE
        btnScale_.exitVel = 0
        FishAtlas.Close()
        return true
    end

    -- 目录按钮
    if hitTest(mx, my, S, SLICES.btnCatalog) then
        mode_ = "catalog"
        page_ = 1
        print("[FishAtlas] Switch to catalog, page=1")
        return true
    end

    -- 详情按钮
    if hitTest(mx, my, S, SLICES.btnDetail) then
        mode_ = "detail"
        page_ = 1
        print("[FishAtlas] Switch to detail, page=1")
        return true
    end

    -- 向前翻页
    if hitTest(mx, my, S, SLICES.btnPrev) then
        btnScale_.prev = BTN_PRESS_SCALE
        btnScale_.prevVel = 0
        if page_ > 1 then
            page_ = page_ - 1
            print("[FishAtlas] Prev page:", page_)
        end
        return true
    end

    -- 向后翻页
    if hitTest(mx, my, S, SLICES.btnNext) then
        btnScale_.next = BTN_PRESS_SCALE
        btnScale_.nextVel = 0
        if page_ < getMaxPages() then
            page_ = page_ + 1
            print("[FishAtlas] Next page:", page_)
        end
        return true
    end

    -- 点击在图册区域内，消费事件但不做其他操作
    if hitTest(mx, my, S, SLICES.bg) then
        return true
    end

    return false
end

--- 处理按键事件
function FishAtlas.HandleKey(key)
    if not isOpen_ then return false end
    if key == KEY_ESCAPE then
        FishAtlas.Close()
        return true
    elseif key == KEY_LEFT then
        if page_ > 1 then
            page_ = page_ - 1
        end
        return true
    elseif key == KEY_RIGHT then
        if page_ < getMaxPages() then
            page_ = page_ + 1
        end
        return true
    end
    return false
end

--- 渲染图册 UI
function FishAtlas.Draw(vg, screenW, screenH)
    if not isOpen_ then return end
    local S = screenH / 1080

    -- 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, screenW, screenH)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 150))
    nvgFill(vg)

    -- 背景（切片5）
    local bg = SLICES.bg
    drawImg(vg, imgs_.bg, bg.x * S, bg.y * S, bg.w * S, bg.h * S)

    -- ── 书签弹性动画更新 ──────────────────────────────────────────────────
    local now = time.elapsedTime
    local dt = now - bmAnim_.lastTime
    if dt <= 0 or dt > 0.1 then dt = 0.016 end  -- 首帧 / 跳帧保护
    bmAnim_.lastTime = now

    -- 弹簧目标：当前激活的模式对应书签抽出
    local tgtC = (mode_ == "catalog") and BOOKMARK_SLIDE or 0
    local tgtD = (mode_ == "detail")  and BOOKMARK_SLIDE or 0

    -- catalog 书签弹簧（半隐式欧拉，稳定性更好）
    local acC = -SPRING_K * (bmAnim_.catalogX - tgtC) - SPRING_D * bmAnim_.catalogVel
    bmAnim_.catalogVel = bmAnim_.catalogVel + acC * dt
    bmAnim_.catalogX   = bmAnim_.catalogX + bmAnim_.catalogVel * dt
    -- 静止吸附（防止微小抖动）
    if math.abs(bmAnim_.catalogX - tgtC) < 0.3 and math.abs(bmAnim_.catalogVel) < 1 then
        bmAnim_.catalogX = tgtC
        bmAnim_.catalogVel = 0
    end

    -- detail 书签弹簧
    local acD = -SPRING_K * (bmAnim_.detailX - tgtD) - SPRING_D * bmAnim_.detailVel
    bmAnim_.detailVel = bmAnim_.detailVel + acD * dt
    bmAnim_.detailX   = bmAnim_.detailX + bmAnim_.detailVel * dt
    if math.abs(bmAnim_.detailX - tgtD) < 0.3 and math.abs(bmAnim_.detailVel) < 1 then
        bmAnim_.detailX = tgtD
        bmAnim_.detailVel = 0
    end

    -- ── 书签（位于背景和模板页之间的图层）────────────────────────────────
    -- 页数显示栏（切片2）
    local pb = SLICES.pageBar
    drawImg(vg, imgs_.pageBar, pb.x * S, pb.y * S, pb.w * S, pb.h * S)

    -- 页码文字
    local pageText = string.format("%d / %d", page_, getMaxPages())
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 22 * S)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(60, 40, 20, 255))
    local pbCx = (pb.x + pb.w * 0.5) * S
    local pbCy = (pb.y + pb.h * 0.5) * S
    nvgText(vg, pbCx, pbCy, pageText, nil)

    -- 目录按钮（切片3）— 弹性平移
    local bc = SLICES.btnCatalog
    drawImg(vg, imgs_.btnCatalog, (bc.x + bmAnim_.catalogX) * S, bc.y * S, bc.w * S, bc.h * S)
    -- 详情按钮（切片4）— 弹性平移
    local bd = SLICES.btnDetail
    drawImg(vg, imgs_.btnDetail, (bd.x + bmAnim_.detailX) * S, bd.y * S, bd.w * S, bd.h * S)

    -- 书页模板（下移16设计像素）
    local PAGE_OFFSET_Y = 16
    if mode_ == "catalog" then
        -- 目录模板（切片1）
        local cat = SLICES.catalog
        drawImg(vg, imgs_.catalog, cat.x * S, (cat.y + PAGE_OFFSET_Y) * S, cat.w * S, cat.h * S)
    else
        -- 详情模板（切片7）
        local det = SLICES.detail
        drawImg(vg, imgs_.detail, det.x * S, (det.y + PAGE_OFFSET_Y) * S, det.w * S, det.h * S)
        -- 鱼类素材背景（切片6，仅详情页显示）
        local fb = SLICES.fishBg
        drawImg(vg, imgs_.fishBg, fb.x * S, (fb.y + PAGE_OFFSET_Y) * S, fb.w * S, fb.h * S)
    end

    -- ── 按钮缩放弹簧更新 ──────────────────────────────────────────────────
    -- exit
    local acE = -BTN_SPRING_K * (btnScale_.exit - 1.0) - BTN_SPRING_D * btnScale_.exitVel
    btnScale_.exitVel = btnScale_.exitVel + acE * dt
    btnScale_.exit    = btnScale_.exit + btnScale_.exitVel * dt
    if math.abs(btnScale_.exit - 1.0) < 0.005 and math.abs(btnScale_.exitVel) < 0.1 then
        btnScale_.exit = 1.0; btnScale_.exitVel = 0
    end
    -- prev
    local acP = -BTN_SPRING_K * (btnScale_.prev - 1.0) - BTN_SPRING_D * btnScale_.prevVel
    btnScale_.prevVel = btnScale_.prevVel + acP * dt
    btnScale_.prev    = btnScale_.prev + btnScale_.prevVel * dt
    if math.abs(btnScale_.prev - 1.0) < 0.005 and math.abs(btnScale_.prevVel) < 0.1 then
        btnScale_.prev = 1.0; btnScale_.prevVel = 0
    end
    -- next
    local acN = -BTN_SPRING_K * (btnScale_.next - 1.0) - BTN_SPRING_D * btnScale_.nextVel
    btnScale_.nextVel = btnScale_.nextVel + acN * dt
    btnScale_.next    = btnScale_.next + btnScale_.nextVel * dt
    if math.abs(btnScale_.next - 1.0) < 0.005 and math.abs(btnScale_.nextVel) < 0.1 then
        btnScale_.next = 1.0; btnScale_.nextVel = 0
    end

    -- 退出按钮（切片11）
    local be = SLICES.btnExit
    drawImgScaled(vg, imgs_.btnExit, be.x * S, be.y * S, be.w * S, be.h * S, btnScale_.exit)

    -- 翻页按钮
    -- 向前翻页（切片12）
    local bp = SLICES.btnPrev
    if page_ > 1 then
        drawImgScaled(vg, imgs_.btnPrev, bp.x * S, bp.y * S, bp.w * S, bp.h * S, btnScale_.prev)
    end
    -- 向后翻页（切片13）
    local bn = SLICES.btnNext
    if page_ < getMaxPages() then
        drawImgScaled(vg, imgs_.btnNext, bn.x * S, bn.y * S, bn.w * S, bn.h * S, btnScale_.next)
    end
end

--- 设置页数配置（动态调整）
function FishAtlas.SetPageCounts(catalogPages, detailPages)
    if catalogPages then CATALOG_PAGES = catalogPages end
    if detailPages then DETAIL_PAGES = detailPages end
end

--- 获取当前状态（供外部查询）
function FishAtlas.GetState()
    return {
        isOpen = isOpen_,
        mode   = mode_,
        page   = page_,
        maxPages = getMaxPages(),
    }
end

return FishAtlas
