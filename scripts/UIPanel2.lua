---@diagnostic disable: assign-type-mismatch, missing-parameter
-- UIPanel2.lua
-- 钓获鱼类信息展示面板
-- 通过 UIPanel2.Show(fish) 传入钓获数据自动显示

local M = {}

local DESIGN_W = 1920
local DESIGN_H = 1080

-- 切片坐标（设计分辨率）
local SLICE = {
    bg     = { x=1026,   y=243,   w=718,  h=452 },  -- 切片9 大背景
    bar    = { x=1099.9, y=586.9, w=578,  h=10  },  -- 切片2 进度条轨道
    ptr    = { x=0,      y=547.9, w=32,   h=31  },  -- 切片1 指针（X动态计算）
    stage  = { x=1117.8, y=438.3, w=106,  h=57  },  -- 切片4 成长阶段
    rarity = { x=1553.7, y=438.3, w=106,  h=57  },  -- 切片3 稀有度
}

-- 颜色常量
local COL_JUVENILE = { 0x56/255, 0x7F/255, 0xC5/255 }  -- #567FC5 亚成体（实际未使用，仅成体用）
local COL_ADULT    = { 0x56/255, 0x7F/255, 0xC5/255 }  -- #567FC5 成体
local COL_CHAMPION = { 0xF8/255, 0xD0/255, 0x5D/255 }  -- #F8D05D 冠军

-- ─── 鱼类精灵图映射（从 FishAtlas 复制，UIPanel2 独立使用） ──────────────────
-- key = fishId, value = { col, row, sheet }
-- sheet=1 → fish_01.png (512×96,  32×32/格, 像素风)
-- sheet=2 → fish_02.png (256×256, 64×64/格, 高清全图)
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
    -- layout2: fish_02ui.png (32×32/格) 与 fish_02.png (64×64/格) 布局相同
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
    -- layout3: fish_03.png (600×78, 5col×1row, 120×78/格)
    local layout3 = {
        { 10, 1, 4, 7, 2 },
    }
    for row = 1, #layout3 do
        for col = 1, #layout3[row] do
            FISH_SPRITE_MAP[layout3[row][col]] = { col = col-1, row = row-1, sheet = 3 }
        end
    end
    -- layout4: fish_04.png (256×192, 4col×3row, 64×64/格)
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

-- sheet 信息：UIPanel2 用全尺寸图
local SHEET_INFO = {
    [1] = { w = 512, h =  96, cellPx = 32 },  -- fish_01.png   像素风
    [2] = { w = 256, h = 256, cellPx = 64 },  -- fish_02.png   高清全图
    [3] = { w = 600, h =  78, cellPx = 120 }, -- fish_03.png   120×78/格
    [4] = { w = 256, h = 192, cellPx = 64 },  -- fish_04.png   高清 64×64/格
}

-- ─── 按钮配置（设计空间坐标） ────────────────────────────────────────────────
-- 左按钮 = 切片8(米白底) + 切片5(鱼图标)
-- 右按钮 = 切片7(蓝色底) + 切片6(勾图标)
local BTN = {
    [1] = {
        -- 切片8 body
        body  = { x=1021, y=754, w=239, h=81 },
        -- 切片5 icon
        icon  = { x=1102, y=769, w=81,  h=56 },
        -- 综合点击区
        hit   = { x=1021, y=754, w=239, h=81 },
        slice_body = "image/ui/ui_slice8.png",
        slice_icon = "image/ui/ui_slice5.png",
    },
    [2] = {
        -- 切片7 body
        body  = { x=1504, y=754, w=238, h=81 },
        -- 切片6 icon
        icon  = { x=1595, y=775, w=59,  h=44 },
        -- 综合点击区
        hit   = { x=1504, y=754, w=238, h=81 },
        slice_body = "image/ui/ui_slice7.png",
        slice_icon = "image/ui/ui_slice6.png",
    },
}

local vg_          = nil
local img_         = nil   -- 合图（无指针）
local img_ptr_     = nil   -- 切片1 指针图像
local img_fish1_   = nil   -- fish_01.png 精灵图集
local img_fish2_   = nil   -- fish_02.png 高清全图集
local img_fish3_   = nil   -- fish_03.png 精灵图集
local img_fish4_   = nil   -- fish_04.png 高清全图集
-- 按钮图像句柄
local img_s5_      = nil   -- 切片5 鱼图标
local img_s6_      = nil   -- 切片6 勾图标
local img_s7_      = nil   -- 切片7 蓝色按钮体
local img_s8_      = nil   -- 切片8 米白按钮体

-- 按钮动画状态（pressAnim: 0=松开, 1=按下）
local btnState_ = {
    [1] = { pressAnim = 0, pressed = false },
    [2] = { pressAnim = 0, pressed = false },
}

local open_      = false
local alpha_     = 0
local onClose_   = nil   -- 关闭时回调 function()

-- 顶部通知
local NOTIF_DURATION = 3.0
local notifMsg_   = ""
local notifTimer_ = 0

-- 当前展示的鱼数据
---@type table|nil
local fish_    = nil   -- { type={name,wMin,wMax,wSample1,...}, weight=N }

-- ─── 辅助：成长阶段判断 ──────────────────────────────────────────────────────

local function GetStage(fish)
    local ft = fish.type
    local wMax     = ft.wMax    or 1
    local wSample1 = ft.wSample1 or (wMax * 0.8)
    local ratio    = fish.weight / wMax

    if ratio < 0.25 then
        return "juvenile", "亚成体", nil                  -- 无特殊底色（SVG默认）
    elseif fish.weight < wSample1 then
        return "adult",   "成体",   COL_ADULT
    else
        return "champion","冠军",   COL_CHAMPION
    end
end

-- ─── 辅助：格式化体重 ────────────────────────────────────────────────────────

local function FormatWeightParts(w)
    -- 内部单位为 kg，返回 整数部分字符串(含小数点) 和 小数部分字符串(含单位)
    if w >= 1.0 then
        -- 千克级
        local intPart  = math.floor(w)
        local fracPart = math.floor((w - intPart) * 1000 + 0.5)
        return string.format("%d.", intPart), string.format("%03dkg", fracPart)
    elseif w >= 0.001 then
        -- 克级：乘以1000转为克
        local g = w * 1000
        local intPart  = math.floor(g)
        local fracPart = math.floor((g - intPart) * 1000 + 0.5)
        return string.format("%d.", intPart), string.format("%03dg", fracPart)
    else
        -- 毫克级
        local mg = math.floor(w * 1000000 + 0.5)
        return string.format("%d", mg), "mg"
    end
end

-- ─── 公共接口 ────────────────────────────────────────────────────────────────

function M.Init(vg, fishSheet1, fishFull2, fishSheet3, fishFull4)
    vg_          = vg
    img_         = nvgCreateImage(vg, "image/ui/ui_panel2_composite.png", 0)
    img_ptr_     = nvgCreateImage(vg, "image/ui/ui_slice1.png", 0)
    img_fish1_   = fishSheet1   -- fish_01.png 句柄（由 main.lua 传入）
    img_fish2_   = fishFull2    -- fish_02.png 句柄（由 main.lua 传入）
    img_fish3_   = fishSheet3   -- fish_03.png 句柄（由 main.lua 传入）
    img_fish4_   = fishFull4    -- fish_04.png 句柄（由 main.lua 传入）
    -- 按钮切片（交互元素单独加载，支持缩放/亮度效果）
    img_s5_      = nvgCreateImage(vg, "image/ui/ui_slice5.png", 0)
    img_s6_      = nvgCreateImage(vg, "image/ui/ui_slice6.png", 0)
    img_s7_      = nvgCreateImage(vg, "image/ui/ui_slice7.png", 0)
    img_s8_      = nvgCreateImage(vg, "image/ui/ui_slice8.png", 0)

    if img_ < 0 then
        print("[UIPanel2] 合图加载失败")
    end
    if img_ptr_ < 0 then
        print("[UIPanel2] 指针图像加载失败（image/ui/ui_slice1.png）")
    end
end

-- 传入钓获的鱼数据打开面板
function M.Show(fish)
    fish_  = fish
    open_  = true
end

function M.Close()
    if not open_ then return end
    open_ = false
    if onClose_ then onClose_() end
end

function M.SetOnClose(fn)
    onClose_ = fn
end

function M.IsOpen()
    return open_
end

function M.Update(dt, screenW, screenH)
    if open_ then
        alpha_ = math.min(1, alpha_ + dt * 6)
    else
        alpha_ = math.max(0, alpha_ - dt * 6)
    end

    -- 通知计时（面板关闭后继续倒计时）
    if notifTimer_ > 0 then
        notifTimer_ = notifTimer_ - dt
    end

    if alpha_ <= 0 then return end

    -- 计算缩放和偏移（设计坐标 → 屏幕坐标）
    local scale = math.min(screenW / DESIGN_W, screenH / DESIGN_H)
    local offX  = (screenW - DESIGN_W * scale) * 0.5
    local offY  = (screenH - DESIGN_H * scale) * 0.5
    local function sx(dx) return offX + dx * scale end
    local function sy(dy) return offY + dy * scale end

    -- 鼠标状态
    local mx      = input.mousePosition.x
    local my      = input.mousePosition.y
    local lbDown  = input:GetMouseButtonDown(MOUSEB_LEFT)
    local lbPress = input:GetMouseButtonPress(MOUSEB_LEFT)

    for i = 1, 2 do
        local btn   = BTN[i]
        local state = btnState_[i]
        local h     = btn.hit
        -- 命中检测（屏幕坐标）
        local hx1 = sx(h.x)
        local hy1 = sy(h.y)
        local hx2 = sx(h.x + h.w)
        local hy2 = sy(h.y + h.h)
        local hover = (mx >= hx1 and mx <= hx2 and my >= hy1 and my <= hy2)
        state.pressed = hover and lbDown

        -- 点击触发（鼠标按下瞬间且在命中区内）
        if hover and lbPress then
            if i == 1 then
                notifMsg_   = "鱼已放生"
            else
                notifMsg_   = "鱼已装入船舱"
            end
            notifTimer_ = NOTIF_DURATION
            M.Close()
        end

        -- pressAnim 平滑过渡（按下→1，松开→0）
        local target = state.pressed and 1 or 0
        state.pressAnim = state.pressAnim + (target - state.pressAnim) * math.min(1, dt * 18)
    end
end

function M.Draw(vg, screenW, screenH)
    -- 通知文字（独立于面板开关，面板关闭后仍可显示）
    if notifTimer_ > 0 and notifMsg_ ~= "" then
        local fadeIn  = math.min(1, (NOTIF_DURATION - notifTimer_) / 0.25)
        local fadeOut = math.min(1, notifTimer_ / 0.6)
        local nAlpha  = math.floor(255 * fadeIn * fadeOut)
        local scale   = math.min(screenW / DESIGN_W, screenH / DESIGN_H)
        nvgSave(vg)
        nvgFontFace(vg, "sans-bold")
        nvgFontSize(vg, 46 * scale)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        -- 淡阴影
        nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(nAlpha * 0.5)))
        nvgText(vg, screenW * 0.5 + 2 * scale, screenH * 0.08 + 2 * scale, notifMsg_, nil)
        -- 白色正文
        nvgFillColor(vg, nvgRGBA(255, 255, 255, nAlpha))
        nvgText(vg, screenW * 0.5, screenH * 0.08, notifMsg_, nil)
        nvgRestore(vg)
    end

    if alpha_ <= 0 or not img_ or img_ < 0 then return end

    local scale = math.min(screenW / DESIGN_W, screenH / DESIGN_H)
    local offX  = (screenW - DESIGN_W * scale) * 0.5
    local offY  = (screenH - DESIGN_H * scale) * 0.5

    -- 辅助坐标转换（设计空间 → 屏幕空间）
    local function sp(v)  return v * scale end
    local function sx(dx) return offX + sp(dx) end
    local function sy(dy) return offY + sp(dy) end
    local ai = math.floor(255 * alpha_)

    nvgSave(vg)

    -- 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, screenW, screenH)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(200 * alpha_)))
    nvgFill(vg)

    -- 合图（切片2~9）
    local iw = DESIGN_W * scale
    local ih = DESIGN_H * scale
    local paint = nvgImagePattern(vg, offX, offY, iw, ih, 0, img_, alpha_)
    nvgBeginPath(vg)
    nvgRect(vg, offX, offY, iw, ih)
    nvgFillPaint(vg, paint)
    nvgFill(vg)

    -- ── 鱼类全图（左侧区域） ──────────────────────────────────────────────────

    if fish_ then
        local ft     = fish_.type
        local fishId = ft.id
        local sprCell = fishId and FISH_SPRITE_MAP[fishId]

        -- 左侧区域中心（0~1026 的中间，垂直对齐 SLICE.bg）
        local leftCX = 413   -- 设计空间 x 中心（左移 100px）
        local leftCY = SLICE.bg.y + SLICE.bg.h * 0.5 + 55   -- 垂直居中对齐 UI 面板（下移 55px）

        if sprCell then
            local si     = SHEET_INFO[sprCell.sheet]
            -- 根据 sheet 选对应图片句柄
            local sheetImages = { img_fish1_, img_fish2_, img_fish3_, img_fish4_ }
            local imgH   = sheetImages[sprCell.sheet]
            local cellPx = si.cellPx

            if imgH and imgH > 0 then
                -- 展示尺寸：高清图(sheet2/4)用400px，像素风(sheet1/3)用288px
                local displaySize = (cellPx >= 64) and 400 or 288

                -- 用 nvgScissor 裁剪出单格
                local drawX  = sx(leftCX - displaySize * 0.5)
                local drawY  = sy(leftCY - displaySize * 0.5)
                local drawSz = sp(displaySize)

                local sScale = math.min(screenW / DESIGN_W, screenH / DESIGN_H)
                local imgScale = displaySize * sScale / cellPx
                local imgW_px = si.w * imgScale
                local imgH_px = si.h * imgScale
                local imgX    = drawX - sprCell.col * cellPx * imgScale
                local imgY    = drawY - sprCell.row * cellPx * imgScale

                -- 圆形背光（径向渐变：内圈透明 → 边缘亮 → 外圈透明，鱼覆盖在上方遮住中心）
                local gcx = drawX + drawSz * 0.5
                local gcy = drawY + drawSz * 0.5
                -- 内径亮（0.2）→ 外径透明（0.5），颜色 #1FBFD5
                local innerR = drawSz * 0.2
                local outerR = drawSz * 0.5
                local glow = nvgRadialGradient(vg, gcx, gcy, innerR, outerR,
                    nvgRGBA(31, 191, 213, math.floor(200 * alpha_)),
                    nvgRGBA(31, 191, 213, 0))
                nvgBeginPath(vg)
                nvgCircle(vg, gcx, gcy, outerR)
                nvgFillPaint(vg, glow)
                nvgFill(vg)

                local pat = nvgImagePattern(vg, imgX, imgY, imgW_px, imgH_px, 0, imgH, alpha_)
                nvgSave(vg)
                nvgScissor(vg, drawX, drawY, drawSz, drawSz)
                nvgBeginPath(vg)
                nvgRect(vg, drawX, drawY, drawSz, drawSz)
                nvgFillPaint(vg, pat)
                nvgFill(vg)
                nvgResetScissor(vg)
                nvgRestore(vg)
            end
        end
    end

    -- ── 动态内容层 ───────────────────────────────────────────────────────────

    if fish_ then
        local ft      = fish_.type
        local weight  = fish_.weight
        local wMin    = ft.wMin    or 0
        local wMax    = ft.wMax    or 1
        local wSample1= ft.wSample1 or (wMax * 0.8)

        -- 成长阶段判断
        local stage, stageLabel, stageColor = GetStage(fish_)

        -- 切片4：动态背景色（成体/冠军）
        if stageColor then
            local r, g, b = stageColor[1], stageColor[2], stageColor[3]
            local s4 = SLICE.stage
            -- 在切片4区域内绘制填充色（内缩4px留出SVG边框）
            nvgBeginPath(vg)
            nvgRoundedRect(vg,
                sx(s4.x + 4), sy(s4.y + 4),
                sp(s4.w - 8), sp(s4.h - 8), sp(6))
            nvgFillColor(vg, nvgRGBA(
                math.floor(r*255), math.floor(g*255), math.floor(b*255), ai))
            nvgFill(vg)
        end

        -- 切片4：成长阶段文字
        nvgFontFace(vg, "sans-bold")
        nvgFontSize(vg, sp(30))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, ai))
        nvgText(vg,
            sx(SLICE.stage.x + SLICE.stage.w * 0.5),
            sy(SLICE.stage.y + SLICE.stage.h * 0.5),
            stageLabel, nil)

        -- 切片3：稀有度（暂用鱼类名称稀有度字段，后续替换）
        nvgText(vg,
            sx(SLICE.rarity.x + SLICE.rarity.w * 0.5),
            sy(SLICE.rarity.y + SLICE.rarity.h * 0.5),
            "珍稀", nil)

        -- 鱼名：切片9顶部下60px居中
        nvgFontSize(vg, sp(50))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, ai))
        nvgText(vg, sx(SLICE.bg.x + SLICE.bg.w * 0.5), sy(SLICE.bg.y + 60), ft.name, nil)

        -- 体重：混合字号，居中，基线对齐
        local intStr, fracStr = FormatWeightParts(weight)
        nvgFontSize(vg, sp(64))
        local w_int  = nvgTextBounds(vg, 0, 0, intStr, nil)
        nvgFontSize(vg, sp(30))
        local w_frac = nvgTextBounds(vg, 0, 0, fracStr, nil)

        local weightCX    = sx(SLICE.bg.x + SLICE.bg.w * 0.5)
        local weightStartX = weightCX - (w_int + w_frac) * 0.5
        local weightBaseY  = sy(SLICE.bg.y + 260)

        nvgFillColor(vg, nvgRGBA(0, 0, 0, ai))
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_BASELINE)
        nvgFontSize(vg, sp(64))
        nvgText(vg, weightStartX, weightBaseY, intStr, nil)
        nvgFontSize(vg, sp(30))
        nvgText(vg, weightStartX + w_int, weightBaseY, fracStr, nil)

        -- 进度条分段着色（叠在切片2 SVG 上，内缩 2px 留出边框）
        do
            local bx  = SLICE.bar.x
            local by  = SLICE.bar.y
            local bw  = SLICE.bar.w
            local bh  = SLICE.bar.h
            local inY = 2   -- 垂直内缩量（设计像素）

            -- 非线性映射：开方曲线，左端展开（稀疏）右端压缩（密集）
            local function barT(w)
                local t = math.max(0, math.min(1, (w - wMin) / math.max(wMax - wMin, 0.001)))
                return t ^ 0.5
            end

            -- 三段分界（亚成体/成体 25% wMax，成体/冠军 wSample1）
            local t25   = barT(wMax * 0.25)
            local tSamp = barT(wSample1)

            -- x 坐标（设计空间）
            local x0 = bx                      -- wMin
            local x1 = bx + t25   * bw         -- 成体起点
            local x2 = bx + tSamp * bw         -- 冠军起点
            local x3 = bx + bw                 -- wMax

            -- 亚成体段（原色：不覆盖，SVG 默认已有颜色）
            -- 只在成体/冠军段覆盖颜色

            -- 成体段 #567FC5
            if x2 > x1 then
                nvgBeginPath(vg)
                nvgRect(vg, sx(x1), sy(by + inY), sp(x2 - x1), sp(bh - inY * 2))
                nvgFillColor(vg, nvgRGBA(0x56, 0x7F, 0xC5, ai))
                nvgFill(vg)
            end

            -- 冠军段 #F8D05D
            if x3 > x2 then
                nvgBeginPath(vg)
                nvgRect(vg, sx(x2), sy(by + inY), sp(x3 - x2), sp(bh - inY * 2))
                nvgFillColor(vg, nvgRGBA(0xF8, 0xD0, 0x5D, ai))
                nvgFill(vg)
            end
        end

        -- 进度条指针（切片1）：使用相同的非线性映射定位
        local t = (math.max(0, math.min(1, (weight - wMin) / math.max(wMax - wMin, 0.001)))) ^ 0.5
        local barX  = SLICE.bar.x
        local barW  = SLICE.bar.w
        local ptrW  = SLICE.ptr.w
        local ptrH  = SLICE.ptr.h
        local ptrDX = barX + t * barW - ptrW * 0.5   -- 水平居中对齐进度位置
        local ptrDY = SLICE.ptr.y

        if img_ptr_ and img_ptr_ >= 0 then
            local pp = nvgImagePattern(vg,
                sx(ptrDX), sy(ptrDY),
                sp(ptrW),  sp(ptrH),
                0, img_ptr_, alpha_)
            nvgBeginPath(vg)
            nvgRect(vg, sx(ptrDX), sy(ptrDY), sp(ptrW), sp(ptrH))
            nvgFillPaint(vg, pp)
            nvgFill(vg)
        else
            -- 指针图像不可用时回退：绘制三角形指针
            local cx = sx(ptrDX + ptrW * 0.5)
            local ty = sy(ptrDY)
            local by = sy(ptrDY + ptrH)
            nvgBeginPath(vg)
            nvgMoveTo(vg, cx,              ty)
            nvgLineTo(vg, cx - sp(8),      by)
            nvgLineTo(vg, cx + sp(8),      by)
            nvgClosePath(vg)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, ai))
            nvgFill(vg)
        end
    end

    -- ── 按钮渲染（切片7/8 底+切片5/6 图标，带缩放+亮度动画） ─────────────────

    -- 辅助：绘制一张带 alpha 的图片切片（图片是 2× 导出，设计尺寸 = PNG/2）
    local function drawSlice(imgHandle, rx, ry, rw, rh, a)
        if not imgHandle or imgHandle < 0 then return end
        local pat = nvgImagePattern(vg, sx(rx), sy(ry), sp(rw), sp(rh), 0, imgHandle, a)
        nvgBeginPath(vg)
        nvgRect(vg, sx(rx), sy(ry), sp(rw), sp(rh))
        nvgFillPaint(vg, pat)
        nvgFill(vg)
    end

    for i = 1, 2 do
        local btn   = BTN[i]
        local state = btnState_[i]
        local pa    = state.pressAnim   -- 0~1

        -- 缩放中心为按钮体中心
        local b    = btn.body
        local bcx  = sx(b.x + b.w * 0.5)
        local bcy  = sy(b.y + b.h * 0.5)
        -- 按下时轻微缩小（最多缩到 0.96）
        local scaleV = 1.0 - pa * 0.04

        nvgSave(vg)
        nvgTranslate(vg, bcx, bcy)
        nvgScale(vg, scaleV, scaleV)
        nvgTranslate(vg, -bcx, -bcy)

        -- 绘制按钮体
        local bodyImg = (i == 1) and img_s8_ or img_s7_
        drawSlice(bodyImg, b.x, b.y, b.w, b.h, alpha_)

        -- 绘制图标
        local ic     = btn.icon
        local iconImg = (i == 1) and img_s5_ or img_s6_
        drawSlice(iconImg, ic.x, ic.y, ic.w, ic.h, alpha_)

        -- 亮度叠加：再绘制一次按钮体，利用图片透明通道自然贴合形状
        drawSlice(bodyImg, b.x, b.y, b.w, b.h, pa * alpha_ * 0.55)

        nvgRestore(vg)
    end

    -- 关闭提示
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 12 * scale)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
    nvgFillColor(vg, nvgRGBA(180, 180, 180, math.floor(180 * alpha_)))
    nvgText(vg, screenW - 16, screenH - 12, "[ESC / E / 空格] 关闭", nil)

    nvgRestore(vg)
end

function M.HandleKey(key)
    if not open_ then return false end
    if key == KEY_ESCAPE or key == KEY_E or key == KEY_SPACE
    or key == KEY_RETURN or key == KEY_KP_ENTER then
        M.Close()
        return true
    end
    return true
end

-- 兼容旧接口（UISelector 里还用 Open()）
function M.Open()
    -- 无鱼数据时用占位数据打开（测试用）
    if not fish_ then
        fish_ = {
            type = { name="大王乌贼", wMin=37.5, wMax=500, wSample1=234.8569 },
            weight = 156.426
        }
    end
    open_ = true
end

return M
