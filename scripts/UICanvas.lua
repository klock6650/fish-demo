-- ============================================================================
-- UICanvas.lua  —  基于 1920×1080 设计分辨率的 UI 坐标系
--
-- 用法：
--   1. 在 Start() 末尾调用 UICanvas.Init(vg)
--   2. 在每帧渲染时（nvgBeginFrame 之后）调用 UICanvas.Update(screenW, screenH)
--   3. 用 UICanvas.LoadImage / UICanvas.Draw 加载并绘制 PNG
--
-- 坐标说明：
--   所有 x, y, w, h 都是 Affinity 1920×1080 画布上的像素坐标，直接填即可。
--   UICanvas 会自动换算到当前屏幕分辨率。
-- ============================================================================

local M = {}

-- 设计分辨率
M.DESIGN_W = 1920
M.DESIGN_H = 1080

-- 运行时缩放参数（每帧由 Update 刷新）
M.scale  = 1.0   -- 等比缩放系数
M.offX   = 0     -- 水平居中偏移（px）
M.offY   = 0     -- 垂直居中偏移（px）

local vg_ = nil

-- ── Init ─────────────────────────────────────────────────────────────────────
function M.Init(vg)
    vg_ = vg
end

-- ── Update（每帧 nvgBeginFrame 之后调用）────────────────────────────────────
function M.Update(screenW, screenH)
    M.scale = math.min(screenW / M.DESIGN_W, screenH / M.DESIGN_H)
    M.offX  = (screenW - M.DESIGN_W * M.scale) * 0.5
    M.offY  = (screenH - M.DESIGN_H * M.scale) * 0.5
end

-- ── 加载图片（在 Start() 里调用，只调用一次）────────────────────────────────
-- path：相对 assets/ 的路径，如 "image/hud.png"
-- 返回 image handle（整数），传给 Draw 使用
function M.LoadImage(path)
    return nvgCreateImage(vg_, path, 0)
end

-- ── 绘制图片（每帧可调用）───────────────────────────────────────────────────
-- imgId : LoadImage 返回的 handle
-- dx,dy : Affinity 画布上的左上角坐标
-- dw,dh : Affinity 画布上的宽高
-- alpha : 透明度 0~1，默认 1
function M.Draw(imgId, dx, dy, dw, dh, alpha)
    if not imgId or imgId == 0 then return end
    alpha = alpha or 1.0
    local x = M.offX + dx * M.scale
    local y = M.offY + dy * M.scale
    local w = dw * M.scale
    local h = dh * M.scale
    local paint = nvgImagePattern(vg_, x, y, w, h, 0, imgId, alpha)
    nvgBeginPath(vg_)
    nvgRect(vg_, x, y, w, h)
    nvgFillPaint(vg_, paint)
    nvgFill(vg_)
end

-- ── 将设计坐标换算为屏幕坐标（用于动态元素定位）───────────────────────────
-- 返回 sx, sy（屏幕像素）
function M.ToScreen(dx, dy)
    return M.offX + dx * M.scale,
           M.offY + dy * M.scale
end

-- ── 将屏幕坐标换算回设计坐标（用于鼠标命中检测）───────────────────────────
function M.ToDesign(sx, sy)
    return (sx - M.offX) / M.scale,
           (sy - M.offY) / M.scale
end

-- ── 检查鼠标是否在某个设计坐标矩形内 ───────────────────────────────────────
function M.HitTest(mx, my, dx, dy, dw, dh)
    local lx, ly = M.ToDesign(mx, my)
    return lx >= dx and lx <= dx + dw and
           ly >= dy and ly <= dy + dh
end

return M
