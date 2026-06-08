---@diagnostic disable: missing-parameter
-- BezierFrame.lua
-- 可移植的贝塞尔曲线 UI 渲染库
-- 将此文件复制到任意 UrhoX 项目的 scripts/ 目录即可使用
--
-- 用法：
--   local BezierFrame = require "BezierFrame"
--   BezierFrame.SetFont(vg, fontId)         -- Start() 中调用一次
--   BezierFrame.Draw(vg, comp, x, y, w, h)  -- Render 中每帧调用
--
-- comp 格式（来自 saves/DialogueBox.lua 等命名存档）：
--   {
--     name    = "DialogueBox",
--     designW = 1920,
--     designH = 1080,
--     frames  = {
--       { fill={r,g,b,a}, textColor={r,g,b,a}, label="...",
--         inner={cx,cy,hw,hh}, anchors={...} },
--       ...
--     }
--   }

local M = {}

---@type any
local fontId_     = -1
---@type any
local fontIdBold_ = -1

-- 设置普通字体（在 Start() 中调用一次）
function M.SetFont(vg, fontId)
    fontId_ = fontId
end

-- 设置粗体字体（在 Start() 中调用一次，可选）
function M.SetBoldFont(vg, fontId)
    fontIdBold_ = fontId
end

-- 内部：将 composite 归一化坐标映射到目标矩形区域
local function BuildFrames(comp, x, y, w, h)
    local scaleX = w / comp.designW
    local scaleY = h / comp.designH

    local result = {}
    for fi, fd in ipairs(comp.frames) do
        local anchors = {}
        for _, a in ipairs(fd.anchors) do
            local ax = x + a.x * comp.designW * scaleX
            local ay = y + a.y * comp.designH * scaleY
            anchors[#anchors + 1] = {
                x = ax, y = ay,
                cpi = {
                    x = x + (a.x + a.cpi.dx) * comp.designW * scaleX,
                    y = y + (a.y + a.cpi.dy) * comp.designH * scaleY,
                },
                cpo = {
                    x = x + (a.x + a.cpo.dx) * comp.designW * scaleX,
                    y = y + (a.y + a.cpo.dy) * comp.designH * scaleY,
                },
            }
        end
        local ir = {
            cx = x + fd.inner.cx * comp.designW * scaleX,
            cy = y + fd.inner.cy * comp.designH * scaleY,
            hw = fd.inner.hw * comp.designW * scaleX,
            hh = fd.inner.hh * comp.designH * scaleY,
        }
        result[fi] = {
            anchors   = anchors,
            inner     = ir,
            fill      = fd.fill      or { 255, 255, 255, 230 },
            textColor = fd.textColor or {  30,  30,  60, 220 },
            label     = fd.label     or "",
            fontSize  = fd.fontSize,   -- 字号系数（nil 则 DrawText 用默认 0.9）
            bold      = fd.bold,       -- 是否加粗
        }
    end
    return result
end

-- 绘制单帧路径（纯色填充，无描边）
local function DrawPath(vg, frame)
    local a = frame.anchors
    local n = #a
    local f = frame.fill

    nvgBeginPath(vg)
    nvgMoveTo(vg, a[1].x, a[1].y)
    for i = 1, n do
        local cur = a[i]
        local nxt = a[(i % n) + 1]
        nvgBezierTo(vg, cur.cpo.x, cur.cpo.y, nxt.cpi.x, nxt.cpi.y, nxt.x, nxt.y)
    end
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(f[1], f[2], f[3], f[4]))
    nvgFill(vg)
end

-- 绘制帧内文本（支持自动换行，垂直居中，裁剪到 inner 矩形）
local function DrawText(vg, frame)
    if fontId_ < 0 then return end
    local label = frame.label
    if not label or label == "" then return end
    local ir = frame.inner
    local tc = frame.textColor

    -- fontSize: 字号系数（默认 0.9），bold: 是否加粗（默认 false）
    local fontScale = frame.fontSize or 0.9
    local bold      = frame.bold     or false
    local fontSize  = math.max(10, ir.hh * fontScale)
    local boxW      = ir.hw * 2
    local boxX      = ir.cx - ir.hw
    local boxY      = ir.cy - ir.hh

    -- bold=true 且有粗体字体时，切换到粗体字体
    local useBoldFace = bold and fontIdBold_ >= 0

    nvgSave(vg)
    nvgScissor(vg, boxX, boxY, boxW, ir.hh * 2)
    nvgFontFaceId(vg, useBoldFace and fontIdBold_ or fontId_)
    nvgFontSize(vg, fontSize)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)

    -- 测量换行后的文本高度，用于垂直居中
    local b = nvgTextBoxBounds(vg, boxX, 0, boxW, label, nil)
    local textH = b[4] - b[2]
    local startY = ir.cy - textH * 0.5

    nvgFillColor(vg, nvgRGBA(tc[1], tc[2], tc[3], tc[4]))
    -- 双重绘制模拟更粗：水平偏移 0.8px 再画一次
    if bold then
        nvgTextBox(vg, boxX + 0.8, startY, boxW, label, nil)
    end
    nvgTextBox(vg, boxX, startY, boxW, label, nil)
    nvgRestore(vg)
end

-- 主绘制函数
-- @param vg    NanoVG context
-- @param comp  composite 数据（来自命名存档，如 require "saves.DialogueBox"）
-- @param x, y  目标矩形左上角（屏幕坐标）
-- @param w, h  目标矩形宽高
-- @param opts  可选配置表：
--              opts.shadow      = true/false  是否绘制投影（默认 true）
--              opts.shadowAlpha = 0~255       投影透明度（默认 55）
--              opts.shadowOY    = 数字         投影 Y 偏移像素（默认 5）
function M.Draw(vg, comp, x, y, w, h, opts)
    if not comp or not comp.frames then return end
    opts = opts or {}
    local shadow      = opts.shadow      ~= false
    local shadowAlpha = opts.shadowAlpha or 55
    local shadowOY    = opts.shadowOY    or 5

    local frames = BuildFrames(comp, x, y, w, h)

    -- 投影（用第一帧路径偏移绘制）
    if shadow and #frames > 0 then
        nvgTranslate(vg, 0, shadowOY)
        local f1 = frames[1]
        local a  = f1.anchors
        local n  = #a
        nvgBeginPath(vg)
        nvgMoveTo(vg, a[1].x, a[1].y)
        for i = 1, n do
            local cur = a[i]
            local nxt = a[(i % n) + 1]
            nvgBezierTo(vg, cur.cpo.x, cur.cpo.y, nxt.cpi.x, nxt.cpi.y, nxt.x, nxt.y)
        end
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, shadowAlpha))
        nvgFill(vg)
        nvgTranslate(vg, 0, -shadowOY)
    end

    -- 从后往前绘制各帧（确保编号靠前的帧在最上层）
    for i = #frames, 1, -1 do
        DrawPath(vg, frames[i])
    end

    -- 从后往前绘制文本
    for i = #frames, 1, -1 do
        DrawText(vg, frames[i])
    end
end

return M
