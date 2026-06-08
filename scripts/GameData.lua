-- ============================================================================
-- GameData.lua - 游戏静态配置数据
-- 从 main.lua 提取的纯数据模块，无外部依赖
-- ============================================================================
local M = {}

M.CFG = {
    -- 小船
    BOAT_MAX_SPEED   = 130,
    BOAT_ACCEL       = 90,
    BOAT_DECEL       = 30,
    BOAT_TURN_SPEED  = 0.7,
    BOAT_LENGTH      = 42,
    BOAT_WIDTH       = 21,
    BOAT_SCALE       = 2,          -- 船只显示缩放 (1=原始, 2=两倍)

    -- 拖钓
    LINE_LENGTH      = 250,
    ROPE_SEGMENTS    = 36,       -- 绳索节点数
    BITE_AVG_TIME    = 10.0,  -- 咬钩平均时间(秒)
    BITE_MIN_PCT     = 0.10,  -- 最小倍率: 平均值的10%
    BITE_MAX_PCT     = 3.00,  -- 最大倍率: 平均值的300%
    BITE_WINDOW      = 2.5,   -- 咬钩后反应时间
    ROD_COUNT        = 2,     -- 鱼竿数量
    BAG_SIZE         = 20,    -- 背包格子数（每格一条鱼，不叠加）

    -- 遛鱼系统 (基于 Godot 参考实现的弹性张力 + 极坐标鱼AI)
    FIGHT_LINE_MAX     = 750,    -- 最大线容量(米), 超过=清杯
    FIGHT_LINE_STRENGTH = 100,   -- 鱼线强度(kg), 张力超过此值=断线
    FIGHT_CATCH_DIST   = 40,     -- 鱼距 <= 此值 = 成功(米)
    FIGHT_STRETCH_MAX  = 25.0,   -- 最大弹性拉伸距离(米), 超过此距离张力=MAX

    -- 刹车 (档位制: 0~29 对应 0%~40%, 30档=锁死)
    FIGHT_DRAG_GEARS     = 30,   -- 总档数(不含锁死档)
    FIGHT_DRAG_MAX_RATIO = 0.40, -- 最高档(29)对应的张力比例
    FIGHT_DRAG_DEFAULT_GEAR = 15,-- 默认起始档位
    -- (静/动摩擦力已被约束解算替代, 不再需要)

    -- 卷轮 (收线 + 放线惯性)
    FIGHT_REEL_ACCEL   = 20.0,   -- 收线加速度(米/秒²)
    FIGHT_REEL_MAX     = 35.0,   -- 最大收线速度(米/秒)
    FIGHT_SLIP_MASS      = 0.0004, -- 卷轮虚拟质量(kg), 越大惯性越大加速越慢
    FIGHT_SLIP_DAMPING   = 0.01,  -- 粘性阻尼系数, 越大抖动越小但惯性感越弱
    FIGHT_SLIP_SPEED_MAX = 120,  -- 放线速度安全上限(米/秒)

    -- 打滑 (惯性模型)
    -- (打滑加速度/质量/最小持续已被约束解算替代, 不再需要)

    -- 视觉平滑
    FIGHT_SLIP_MEMORY  = 1.0,    -- 打滑记忆持续时间(秒, 仅用于显示)

    -- 鱼AI物理
    FISH_MASS          = 0.1,    -- 鱼的质量
    FISH_DRAG_COEFF    = 0.5,    -- 线性水阻力系数 (F = dragC * v)
    FISH_QUAD_DRAG     = 0.001,  -- 二次方水阻力系数基准值 (参考100g鱼); 实际值按 wMax^(2/3) 缩放
    FISH_SPEED_CAP     = 160,    -- 径向最大速度
    FISH_TAN_SPEED_CAP = 600,    -- 切向最大速度
    FISH_MAX_ANGLE     = 60,     -- 最大偏转角度(度)
    FISH_ANGLE_DAMP_START = 30,  -- 开始阻尼的角度(度)
    FISH_RESTORE_STR   = 2.0,    -- 角度恢复力强度

    -- 虚拟摇杆
    JOYSTICK_R       = 65,   -- 摇杆外圈半径
    JOYSTICK_INNER   = 24,   -- 摇杆内圈（摇头）半径
    ACTION_BTN_R     = 50,   -- 动作按钮半径
    INTERACT_BTN_R   = 44,   -- 互动按钮（靠岸/拾取）半径

    -- 抛竿蓄力
    CAST_CHARGE_TIME  = 1.5,    -- 满蓄力时间(秒)
    CAST_MIN_DIST     = 60,     -- 最小抛投距离(米)
    CAST_MAX_DIST     = 300,    -- 最大抛投距离(米)
    CAST_FLY_SPEED    = 600,    -- 鱼线飞行速度(米/秒)
    CAST_ARC_HEIGHT   = 50,     -- 抛物线高度(像素, 仅视觉)

    -- 抬杆 (提竿)
    STRIKE_DURATION   = 0.35,   -- 抬杆动画总时长(秒)
    STRIKE_LIFT_PX    = 12,     -- 鱼竿抬起最大高度(像素, sprite stack 偏移)
    STRIKE_SHAKE_AMP  = 3,      -- 鱼线抖动振幅(像素)
    STRIKE_ZOOM_PUNCH = 0.08,   -- 镜头缩放脉冲增量

    -- 抬杆 (蓄力抛竿)
    CAST_LIFT_MAX_ANGLE  = math.rad(110), -- 蓄力满格时最大抬起角度 (>90°=越顶后向对侧延伸，投石机效果)
    CAST_LIFT_PX         = 9,            -- 竿尖最大抬起像素偏移 (sprite stack)
    CAST_LIFT_DROP_SPEED = 9.0,          -- 抛出后回落速度 (1/秒)

    -- 抬杆 (fight 状态下右键压杆)
    FIGHT_LIFT_MAX_ANGLE = math.rad(55), -- 最大抬起角度(弧度), 55° ≈ 0.96 rad
    FIGHT_LIFT_SPEED_UP  = 1.4,          -- 抬杆基础速度 (慢抬, 1/秒)
    FIGHT_LIFT_SPEED_DOWN = 5.0,         -- 放杆基础速度 (快放, 1/秒)
    FIGHT_LIFT_TENSION_DRAG = 0.7,       -- 张力对抬杆的阻力系数 (0=无阻力, 1=满张力时速度归零)
    FIGHT_LIFT_PX        = 10,           -- 竿尖最大抬起像素偏移 (sprite stack 叠加)

    -- sprite stacking
    STACK_OFFSET         = 2.25,        -- 层间垂直偏移 (像素)
    ROD_STACK_LAYER      = 6.5,         -- 鱼竿所在 sprite-stack 层
}


-- ============================================================================
-- 钓竿数据
-- ============================================================================
-- 五档钓竿，按目标鱼体重分级。
-- lineStrength: 断线张力(kg)；stretchMax: 最大弹性伸展(m)，越小线越软。
-- dragMaxRatio 已移除，由渔线轮的 maxDragForce / lineStrength 动态计算。
-- 竿身颜色: secBase = 深色基调 RGB，secHighlight = 高光 RGB。
M.ROD_TYPES = {
    {
        id   = 1,
        name = "溪钓竿",
        desc = "微小型鱼",
        lineStrength = 2.7,
        stretchMax   = 6.0,
        -- 竹绿色
        secBase      = { {20,50,20},{28,58,25},{38,68,32},{50,80,42},{68,95,55} },
        secHighlight = {120,180,100},
    },
    {
        id   = 2,
        name = "矶钓竿",
        desc = "微小&小型鱼",
        lineStrength = 9,
        stretchMax   = 12.0,
        -- 海蓝色
        secBase      = { {20,38,60},{26,46,72},{34,56,85},{44,68,100},{58,84,118} },
        secHighlight = {100,160,220},
    },
    {
        id   = 3,
        name = "路亚竿",
        desc = "小型&中型鱼",
        lineStrength = 36,
        stretchMax   = 20.0,
        -- 橙棕色
        secBase      = { {55,30,10},{68,38,14},{82,48,18},{98,60,24},{118,76,32} },
        secHighlight = {200,140,70},
    },
    {
        id   = 4,
        name = "船钓竿",
        desc = "中型大型鱼",
        lineStrength = 95,
        stretchMax   = 30.0,
        -- 深红/炭黑色
        secBase      = { {50,15,15},{62,20,18},{76,26,22},{92,34,28},{112,44,36} },
        secHighlight = {200,80,60},
    },
    {
        id   = 5,
        name = "重竿",
        desc = "大型巨型鱼",
        lineStrength = 205,
        stretchMax   = 55.0,
        -- 深紫/钛黑色
        secBase      = { {30,18,50},{38,24,62},{48,32,76},{60,42,92},{76,54,112} },
        secHighlight = {160,100,220},
    },
}

-- ============================================================================
-- 渔线轮数据
-- ============================================================================
-- maxDragForce : 最大刹车力(kg，绝对值)，与鱼竿 lineStrength 的比值即 dragMaxRatio
-- lineCapacity : 鱼线容量(米)，超过此值=清杯
-- 配套关系示例：溪钓竿(0.8kg)+溪钓轮 → dragMaxRatio=0.6/0.8=0.75

--              重竿(150kg)+重型轮     → dragMaxRatio=60/150=0.40
M.REEL_TYPES = {
    {
        id           = 1,
        name         = "溪钓轮",
        desc         = "轻量纺车轮，适配溪钓竿",
        maxDragForce = 2,      -- kg
        lineCapacity = 300,    -- 米
        mechStrength = 5,      -- kg，渔轮机械强度上限
        reelSpeedMax = 15,     -- 最大收线速度(m/s)
        reelAccel    = 6,      -- 收线加速度(m/s²)
    },
    {
        id           = 2,
        name         = "矶钓轮",
        desc         = "通用纺车轮，适配矶钓竿",
        maxDragForce = 6,      -- kg
        lineCapacity = 450,    -- 米
        mechStrength = 20,     -- kg，渔轮机械强度上限
        reelSpeedMax = 20,     -- 最大收线速度(m/s)
        reelAccel    = 10,     -- 收线加速度(m/s²)
    },
    {
        id           = 3,
        name         = "路亚轮",
        desc         = "中型纺车轮，适配路亚竿",
        maxDragForce = 15,     -- kg
        lineCapacity = 550,    -- 米
        mechStrength = 40,     -- kg，渔轮机械强度上限
        reelSpeedMax = 25,     -- 最大收线速度(m/s)
        reelAccel    = 15,     -- 收线加速度(m/s²)
    },
    {
        id           = 4,
        name         = "船钓轮",
        desc         = "鼓形轮，适配船钓竿",
        maxDragForce = 35,     -- kg
        lineCapacity = 750,    -- 米
        mechStrength = 105,    -- kg，渔轮机械强度上限
        reelSpeedMax = 35,     -- 最大收线速度(m/s)
        reelAccel    = 15,     -- 收线加速度(m/s²)
    },
    {
        id           = 5,
        name         = "重型轮",
        desc         = "大容量海钓轮，适配重竿",
        maxDragForce = 36,     -- kg
        lineCapacity = 1500,   -- 米
        mechStrength = 300,    -- kg，渔轮机械强度上限
        reelSpeedMax = 45,     -- 最大收线速度(m/s)
        reelAccel    = 25,     -- 收线加速度(m/s²)
    },
}


-- ============================================================================
-- 鱼种数据
-- ============================================================================
M.FISH_TYPES = {
    -- 翻车鱼
    { name="翻车鱼", diff=5,
      wMin=150, wMax=2300, wBias=0, wSpread=0.5,  wSample1=1067.4429,
      forceAtMax=700, forceExp=0.45,
      tanCoeff=1, radSpeedMax=130, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.7, label="calm", ampLo=0.1, ampHi=0.3, durMin=2, durMax=7 },
          { weight=0.25, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0.05, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=3 },
      }},
    -- 蓝鳍金枪鱼
    { name="蓝鳍金枪鱼", diff=5,
      wMin=30, wMax=680, wBias=0.2, wSpread=0.27,  wSample1=307.3665,
      forceAtMax=680, forceExp=0.45,
      tanCoeff=4, radSpeedMax=260, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.5, label="calm", ampLo=0.1, ampHi=0.3, durMin=4, durMax=7 },
          { weight=0.25, label="active", ampLo=0.35, ampHi=0.55, durMin=2, durMax=4.5 },
          { weight=0.25, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=7 },
      }},
    -- 大王乌贼
    { name="大王乌贼", diff=5,
      wMin=37.5, wMax=500, wBias=0.2, wSpread=0.27,  wSample1=234.8569,
      forceAtMax=500, forceExp=0.45,
      tanCoeff=0.5, radSpeedMax=130, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.25, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=4 },
          { weight=0.3, label="active", ampLo=0.35, ampHi=0.55, durMin=2, durMax=4.5 },
          { weight=0.45, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=3 },
      }},
    -- 长尾鲨
    { name="长尾鲨", diff=5,
      wMin=6, wMax=240, wBias=0.2, wSpread=0.27,  wSample1=105.8519,
      forceAtMax=240, forceExp=0.45,
      tanCoeff=2, radSpeedMax=260, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.6, label="calm", ampLo=0.1, ampHi=0.3, durMin=2, durMax=7 },
          { weight=0.3, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0.1, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=3 },
      }},
    -- 巨石斑鱼
    { name="巨石斑鱼", diff=5,
      wMin=7.5, wMax=300, wBias=0.2, wSpread=0.27,  wSample1=132.3149,
      forceAtMax=300, forceExp=0.45,
      tanCoeff=0.5, radSpeedMax=60, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.9, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=4 },
          { weight=0.1, label="active", ampLo=0.35, ampHi=0.55, durMin=2, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=3 },
      }},
    -- 魔鬼鱼
    { name="魔鬼鱼", diff=5,
      wMin=15, wMax=300, wBias=0.2, wSpread=0.27,  wSample1=136.6145,
      forceAtMax=300, forceExp=0.45,
      tanCoeff=1, radSpeedMax=130, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.9, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=4 },
          { weight=0.1, label="active", ampLo=0.35, ampHi=0.55, durMin=2, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=3 },
      }},
    -- 皇带鱼
    { name="皇带鱼", diff=5,
      wMin=15, wMax=270, wBias=0.2, wSpread=0.27,  wSample1=123.813,
      forceAtMax=270, forceExp=0.45,
      tanCoeff=0.5, radSpeedMax=60, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.9, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=4 },
          { weight=0.1, label="active", ampLo=0.35, ampHi=0.55, durMin=2, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=3 },
      }},
    -- 鼠鲨
    { name="鼠鲨", diff=5,
      wMin=18, wMax=250, wBias=0.2, wSpread=0.27,  wSample1=116.9985,
      forceAtMax=250, forceExp=0.45,
      tanCoeff=2, radSpeedMax=260, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.6, label="calm", ampLo=0.1, ampHi=0.3, durMin=2, durMax=7 },
          { weight=0.3, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0.1, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=3 },
      }},
    -- 青鲨
    { name="青鲨", diff=4,
      wMin=12, wMax=200, wBias=0.2, wSpread=0.27,  wSample1=92.2229,
      forceAtMax=200, forceExp=0.45,
      tanCoeff=2, radSpeedMax=260, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.6, label="calm", ampLo=0.1, ampHi=0.3, durMin=2, durMax=7 },
          { weight=0.3, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0.1, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=3 },
      }},
    -- 旗鱼
    { name="旗鱼", diff=4,
      wMin=12, wMax=150, wBias=0.2, wSpread=0.27,  wSample1=70.887,
      forceAtMax=150, forceExp=0.45,
      tanCoeff=4, radSpeedMax=260, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.5, label="calm", ampLo=0.1, ampHi=0.3, durMin=4, durMax=7 },
          { weight=0.25, label="active", ampLo=0.35, ampHi=0.55, durMin=2, durMax=4.5 },
          { weight=0.25, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=7 },
      }},
    -- 皱筛鲨
    { name="皱筛鲨", diff=4,
      wMin=6, wMax=100, wBias=0.2, wSpread=0.27,  wSample1=46.1115,
      forceAtMax=100, forceExp=0.45,
      tanCoeff=1, radSpeedMax=60, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.6, label="calm", ampLo=0.1, ampHi=0.3, durMin=2, durMax=7 },
          { weight=0.4, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=3 },
      }},
    -- 刺魟
    { name="刺魟", diff=4,
      wMin=4.5, wMax=100, wBias=0.2, wSpread=0.27,  wSample1=45.2515,
      forceAtMax=100, forceExp=0.45,
      tanCoeff=0.5, radSpeedMax=60, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.9, label="calm", ampLo=0.1, ampHi=0.3, durMin=2, durMax=7 },
          { weight=0.1, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=2.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=3 },
      }},
    -- 牛港鲹
    { name="牛港鲹", diff=4,
      wMin=2.25, wMax=80, wBias=0.2, wSpread=0.27,  wSample1=35.4273,
      forceAtMax=80, forceExp=0.45,
      tanCoeff=4, radSpeedMax=130, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.5, label="calm", ampLo=0.1, ampHi=0.3, durMin=2, durMax=7 },
          { weight=0.25, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0.25, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=3 },
      }},
    -- 犁头鳐
    { name="犁头鳐", diff=4,
      wMin=3, wMax=70, wBias=0.2, wSpread=0.27,  wSample1=31.5901,
      forceAtMax=70, forceExp=0.45,
      tanCoeff=0.5, radSpeedMax=60, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.9, label="calm", ampLo=0.1, ampHi=0.3, durMin=2, durMax=7 },
          { weight=0.1, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=2.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=3 },
      }},
    -- 长鳍金枪鱼
    { name="长鳍金枪鱼", diff=4,
      wMin=5.25, wMax=70, wBias=0.2, wSpread=0.27,  wSample1=32.88,
      forceAtMax=70, forceExp=0.45,
      tanCoeff=4, radSpeedMax=260, dragScale=0.5385, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.5, label="calm", ampLo=0.1, ampHi=0.3, durMin=2, durMax=7 },
          { weight=0.25, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=2.5 },
          { weight=0.25, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=3 },
      }},
    -- 月鱼
    { name="月鱼", diff=4,
      wMin=3, wMax=200, wBias=0.2, wSpread=0.27,  wSample1=87.0634,
      forceAtMax=200, forceExp=0.45,
      tanCoeff=1, radSpeedMax=60, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.9, label="calm", ampLo=0.1, ampHi=0.3, durMin=2, durMax=7 },
          { weight=0.1, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=3 },
      }},
    -- 海湾鲟
    { name="海湾鲟", diff=4,
      wMin=2.25, wMax=145, wBias=0.2, wSpread=0.27,  wSample1=63.1639,
      forceAtMax=145, forceExp=0.45,
      tanCoeff=4, radSpeedMax=260, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.5, label="calm", ampLo=0.1, ampHi=0.3, durMin=4, durMax=7 },
          { weight=0.25, label="active", ampLo=0.35, ampHi=0.55, durMin=2, durMax=4.5 },
          { weight=0.25, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=7 },
      }},
    -- 高体鰤
    { name="高体鰤", diff=4,
      wMin=1.2, wMax=72, wBias=0.2, wSpread=0.27,  wSample1=31.4116,
      forceAtMax=72, forceExp=0.45,
      tanCoeff=2, radSpeedMax=260, dragScale=0.5538, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.5, label="calm", ampLo=0.1, ampHi=0.3, durMin=2, durMax=7 },
          { weight=0.25, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0.25, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=3 },
      }},
    -- 红尾梭鱼
    { name="红尾梭鱼", diff=1,
      wMin=0.09, wMax=1.5, wBias=0.2, wSpread=0.27,  wSample1=0.6917,
      forceAtMax=1.5, forceExp=0.45,
      tanCoeff=2, radSpeedMax=130, dragScale=0.02308, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.9, label="calm", ampLo=0.1, ampHi=0.3, durMin=2, durMax=7 },
          { weight=0.1, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=3 },
      }},
    -- 真蛸
    { name="真蛸", diff=1,
      wMin=0.3, wMax=5, wBias=0.2, wSpread=0.27,  wSample1=2.3056,
      forceAtMax=5, forceExp=0.45,
      tanCoeff=2, radSpeedMax=130, dragScale=0.07692, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.9, label="calm", ampLo=0.1, ampHi=0.3, durMin=2, durMax=7 },
          { weight=0.1, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=3 },
      }},
    -- 裸胸鳝
    { name="裸胸鳝", diff=3,
      wMin=0.45, wMax=24, wBias=0.2, wSpread=0.27,  wSample1=10.4992,
      forceAtMax=24, forceExp=0.45,
      tanCoeff=0.5, radSpeedMax=60, dragScale=0.8, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.4, label="calm", ampLo=0.1, ampHi=0.3, durMin=4, durMax=7 },
          { weight=0.1, label="active", ampLo=0.35, ampHi=0.55, durMin=2, durMax=4.5 },
          { weight=0.5, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=7 },
      }},
    -- 海狼鱼
    { name="海狼鱼", diff=3,
      wMin=0.75, wMax=45, wBias=0.2, wSpread=0.27,  wSample1=19.6323,
      forceAtMax=45, forceExp=0.45,
      tanCoeff=2, radSpeedMax=130, dragScale=0.6923, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.5, label="calm", ampLo=0.1, ampHi=0.3, durMin=4, durMax=7 },
          { weight=0.25, label="active", ampLo=0.35, ampHi=0.55, durMin=2, durMax=4.5 },
          { weight=0.25, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=7 },
      }},
    -- 海鲇
    { name="海鲇", diff=2,
      wMin=0.45, wMax=20, wBias=0.2, wSpread=0.27,  wSample1=8.7923,
      forceAtMax=20, forceExp=0.45,
      tanCoeff=0.5, radSpeedMax=60, dragScale=0.6667, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.9, label="calm", ampLo=0.1, ampHi=0.3, durMin=2, durMax=7 },
          { weight=0.1, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 马鲛鱼
    { name="马鲛鱼", diff=4,
      wMin=1.8, wMax=140, wBias=0.2, wSpread=0.27,  wSample1=60.7724,
      forceAtMax=140, forceExp=0.45,
      tanCoeff=2, radSpeedMax=260, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.5, label="calm", ampLo=0.1, ampHi=0.3, durMin=4, durMax=7 },
          { weight=0.25, label="active", ampLo=0.35, ampHi=0.55, durMin=2, durMax=4.5 },
          { weight=0.25, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=7 },
      }},
    -- 真鲷
    { name="真鲷", diff=2,
      wMin=0.15, wMax=10, wBias=0.2, wSpread=0.27,  wSample1=4.3532,
      forceAtMax=10, forceExp=0.45,
      tanCoeff=1, radSpeedMax=130, dragScale=0.1538, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.6, label="calm", ampLo=0.1, ampHi=0.3, durMin=2, durMax=7 },
          { weight=0.3, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0.1, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 东星斑
    { name="东星斑", diff=2,
      wMin=0.375, wMax=20, wBias=0.2, wSpread=0.27,  wSample1=8.7493,
      forceAtMax=20, forceExp=0.45,
      tanCoeff=0.5, radSpeedMax=60, dragScale=0.6667, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.9, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0.1, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 牙鲆
    { name="牙鲆", diff=2,
      wMin=0.225, wMax=10, wBias=0.2, wSpread=0.27,  wSample1=4.3962,
      forceAtMax=10, forceExp=0.45,
      tanCoeff=0.5, radSpeedMax=25, dragScale=0.8, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.9, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0.1, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 金眼鲈
    { name="金眼鲈", diff=3,
      wMin=1.8, wMax=50, wBias=0.2, wSpread=0.27,  wSample1=22.3678,
      forceAtMax=50, forceExp=0.45,
      tanCoeff=4, radSpeedMax=260, dragScale=0.3846, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.4, label="calm", ampLo=0.1, ampHi=0.3, durMin=4, durMax=7 },
          { weight=0.35, label="active", ampLo=0.35, ampHi=0.55, durMin=2, durMax=4.5 },
          { weight=0.25, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=7 },
      }},
    -- 河豚
    { name="河豚", diff=1,
      wMin=0.15, wMax=3, wBias=0.2, wSpread=0.27,  wSample1=1.3661,
      forceAtMax=3, forceExp=0.45,
      tanCoeff=0.5, radSpeedMax=60, dragScale=0.1, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.9, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0.1, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 黑鲷
    { name="黑鲷", diff=2,
      wMin=0.12, wMax=6, wBias=0.2, wSpread=0.27,  wSample1=2.6291,
      forceAtMax=6, forceExp=0.45,
      tanCoeff=1, radSpeedMax=130, dragScale=0.09231, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.6, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0.3, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0.1, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 带鱼
    { name="带鱼", diff=2,
      wMin=0.3, wMax=12, wBias=0.2, wSpread=0.27,  wSample1=5.2926,
      forceAtMax=12, forceExp=0.45,
      tanCoeff=0.5, radSpeedMax=60, dragScale=0.4, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.6, label="calm", ampLo=0.1, ampHi=0.3, durMin=4, durMax=7 },
          { weight=0.3, label="active", ampLo=0.35, ampHi=0.55, durMin=2, durMax=4.5 },
          { weight=0.1, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=7 },
      }},
    -- 鲈鱼
    { name="鲈鱼", diff=2,
      wMin=0.255, wMax=7, wBias=0.2, wSpread=0.27,  wSample1=3.1332,
      forceAtMax=7, forceExp=0.45,
      tanCoeff=4, radSpeedMax=130, dragScale=0.1077, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.6, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0.3, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0.1, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 椰子海螺
    { name="椰子海螺", diff=1,
      wMin=0.15, wMax=2.5, wBias=0.2, wSpread=0.27,  wSample1=1.1528,
      forceAtMax=2.5, forceExp=0.45,
      tanCoeff=0.1, radSpeedMax=15, dragScale=0.3333, tanSpeedMax=600,
      radialStateTable = {
          { weight=1, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 金鲳鱼
    { name="金鲳鱼", diff=3,
      wMin=0.6, wMax=25, wBias=0.2, wSpread=0.27,  wSample1=11.0119,
      forceAtMax=25, forceExp=0.45,
      tanCoeff=4, radSpeedMax=260, dragScale=0.1923, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.6, label="calm", ampLo=0.1, ampHi=0.3, durMin=4, durMax=7 },
          { weight=0.3, label="active", ampLo=0.35, ampHi=0.55, durMin=2, durMax=4.5 },
          { weight=0.1, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=7 },
      }},
    -- 帆蜥
    { name="帆蜥", diff=3,
      wMin=0.6, wMax=22, wBias=0.2, wSpread=0.27,  wSample1=9.7318,
      forceAtMax=22, forceExp=0.45,
      tanCoeff=0.5, radSpeedMax=60, dragScale=0.7333, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.4, label="calm", ampLo=0.1, ampHi=0.3, durMin=4, durMax=7 },
          { weight=0.35, label="active", ampLo=0.35, ampHi=0.55, durMin=2, durMax=4.5 },
          { weight=0.25, label="active", ampLo=0.55, ampHi=0.85, durMin=6, durMax=7 },
      }},
    -- 灰仙鱼
    { name="灰仙鱼", diff=2,
      wMin=0.12, wMax=6, wBias=0.2, wSpread=0.27,  wSample1=2.6291,
      forceAtMax=6, forceExp=0.45,
      tanCoeff=1, radSpeedMax=60, dragScale=0.2, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.9, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0.1, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 鹦鹉螺
    { name="鹦鹉螺", diff=1,
      wMin=0.12, wMax=1.5, wBias=0.2, wSpread=0.27,  wSample1=0.7089,
      forceAtMax=1.5, forceExp=0.45,
      tanCoeff=0.5, radSpeedMax=15, dragScale=0.2, tanSpeedMax=600,
      radialStateTable = {
          { weight=1, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 鼠尾鳕
    { name="鼠尾鳕", diff=1,
      wMin=0.15, wMax=5, wBias=0.2, wSpread=0.27,  wSample1=2.2196,
      forceAtMax=5, forceExp=0.45,
      tanCoeff=0.5, radSpeedMax=25, dragScale=0.4, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.6, label="calm", ampLo=0.1, ampHi=0.3, durMin=4, durMax=7 },
          { weight=0.3, label="active", ampLo=0.35, ampHi=0.55, durMin=2, durMax=4.5 },
          { weight=0.1, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=7 },
      }},
    -- 褐拟鳞鲀
    { name="褐拟鳞鲀", diff=2,
      wMin=0.9, wMax=20, wBias=0.2, wSpread=0.27,  wSample1=9.0503,
      forceAtMax=20, forceExp=0.45,
      tanCoeff=1, radSpeedMax=130, dragScale=0.3077, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.5, label="calm", ampLo=0.1, ampHi=0.3, durMin=4, durMax=7 },
          { weight=0.25, label="active", ampLo=0.35, ampHi=0.55, durMin=2, durMax=4.5 },
          { weight=0.25, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=7 },
      }},
    -- 枪鱿
    { name="枪鱿", diff=1,
      wMin=0.09, wMax=4, wBias=0.2, wSpread=0.27,  wSample1=1.7585,
      forceAtMax=4, forceExp=0.45,
      tanCoeff=1, radSpeedMax=260, dragScale=0.03077, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.9, label="calm", ampLo=0.1, ampHi=0.3, durMin=4, durMax=7 },
          { weight=0.1, label="active", ampLo=0.35, ampHi=0.55, durMin=2, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=7 },
      }},
    -- 香蕉鱼
    { name="香蕉鱼", diff=1,
      wMin=0.045, wMax=0.8, wBias=0.2, wSpread=0.27,  wSample1=0.3672,
      forceAtMax=0.8, forceExp=0.45,
      tanCoeff=1, radSpeedMax=60, dragScale=0.02667, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.9, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0.1, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 鲭鱼
    { name="鲭鱼", diff=1,
      wMin=0.09, wMax=1.4, wBias=0.2, wSpread=0.27,  wSample1=0.649,
      forceAtMax=1.4, forceExp=0.45,
      tanCoeff=1, radSpeedMax=130, dragScale=0.02154, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.6, label="calm", ampLo=0.1, ampHi=0.3, durMin=4, durMax=7 },
          { weight=0.3, label="active", ampLo=0.35, ampHi=0.55, durMin=2, durMax=4.5 },
          { weight=0.1, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=7 },
      }},
    -- 绿毒鲉
    { name="绿毒鲉", diff=1,
      wMin=0.045, wMax=0.8, wBias=0.2, wSpread=0.27,  wSample1=0.3672,
      forceAtMax=0.8, forceExp=0.45,
      tanCoeff=0.5, radSpeedMax=25, dragScale=0.064, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.9, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0.1, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 鲍
    { name="鲍", diff=1,
      wMin=0.022, wMax=0.5, wBias=0.2, wSpread=0.27,  wSample1=0.226,
      forceAtMax=0.5, forceExp=0.45,
      tanCoeff=0.1, radSpeedMax=15, dragScale=0.06667, tanSpeedMax=600,
      radialStateTable = {
          { weight=1, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 刺尻鱼
    { name="刺尻鱼", diff=1,
      wMin=0.03, wMax=0.5, wBias=0.2, wSpread=0.27,  wSample1=0.2306,
      forceAtMax=0.5, forceExp=0.45,
      tanCoeff=0.5, radSpeedMax=60, dragScale=0.01667, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.9, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0.1, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 竹荚鱼
    { name="竹荚鱼", diff=1,
      wMin=0.09, wMax=2.4, wBias=0.2, wSpread=0.27,  wSample1=1.0757,
      forceAtMax=2.4, forceExp=0.45,
      tanCoeff=2, radSpeedMax=130, dragScale=0.03692, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.9, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0.1, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 棘海星
    { name="棘海星", diff=1,
      wMin=0.03, wMax=0.5, wBias=0.2, wSpread=0.27,  wSample1=0.2306,
      forceAtMax=0.5, forceExp=0.45,
      tanCoeff=0.1, radSpeedMax=15, dragScale=0.06667, tanSpeedMax=600,
      radialStateTable = {
          { weight=1, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 马夫鱼
    { name="马夫鱼", diff=1,
      wMin=0.022, wMax=0.6, wBias=0.2, wSpread=0.27,  wSample1=0.2686,
      forceAtMax=0.6, forceExp=0.45,
      tanCoeff=0.5, radSpeedMax=60, dragScale=0.02, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.9, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0.1, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 红海星
    { name="红海星", diff=1,
      wMin=0.022, wMax=0.4, wBias=0.2, wSpread=0.27,  wSample1=0.1833,
      forceAtMax=0.4, forceExp=0.45,
      tanCoeff=0.1, radSpeedMax=15, dragScale=0.05333, tanSpeedMax=600,
      radialStateTable = {
          { weight=1, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 黑蝴蝶鱼
    { name="黑蝴蝶鱼", diff=1,
      wMin=0.018, wMax=0.35, wBias=0.2, wSpread=0.27,  wSample1=0.1597,
      forceAtMax=0.35, forceExp=0.45,
      tanCoeff=1, radSpeedMax=60, dragScale=0.01167, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.9, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0.1, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 蓝指海星
    { name="蓝指海星", diff=1,
      wMin=0.015, wMax=0.3, wBias=0.2, wSpread=0.27,  wSample1=0.1366,
      forceAtMax=0.3, forceExp=0.45,
      tanCoeff=0.1, radSpeedMax=15, dragScale=0.04, tanSpeedMax=600,
      radialStateTable = {
          { weight=1, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 拟花鮨
    { name="拟花鮨", diff=1,
      wMin=0.022, wMax=0.3, wBias=0.2, wSpread=0.27,  wSample1=0.1406,
      forceAtMax=0.3, forceExp=0.45,
      tanCoeff=1, radSpeedMax=60, dragScale=0.01, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.9, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0.1, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 蓝圆鲹
    { name="蓝圆鲹", diff=2,
      wMin=0.3, wMax=7, wBias=0.2, wSpread=0.27,  wSample1=3.159,
      forceAtMax=7, forceExp=0.45,
      tanCoeff=2, radSpeedMax=130, dragScale=0.1077, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.6, label="calm", ampLo=0.1, ampHi=0.3, durMin=4, durMax=7 },
          { weight=0.3, label="active", ampLo=0.35, ampHi=0.55, durMin=2, durMax=4.5 },
          { weight=0.1, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=7 },
      }},
    -- 扇贝
    { name="扇贝", diff=1,
      wMin=0.015, wMax=0.3, wBias=0.2, wSpread=0.27,  wSample1=0.1366,
      forceAtMax=0.3, forceExp=0.45,
      tanCoeff=0.1, radSpeedMax=15, dragScale=0.04, tanSpeedMax=600,
      radialStateTable = {
          { weight=1, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 蝴蝶鱼
    { name="蝴蝶鱼", diff=1,
      wMin=0.015, wMax=0.3, wBias=0.2, wSpread=0.27,  wSample1=0.1366,
      forceAtMax=0.3, forceExp=0.45,
      tanCoeff=1, radSpeedMax=60, dragScale=0.01, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.9, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0.1, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 小丑鱼（伯爵）
    { name="小丑鱼（伯爵）", diff=1,
      wMin=0.003, wMax=0.07, wBias=0.2, wSpread=0.27,  wSample1=0.0316,
      forceAtMax=0.07, forceExp=0.45,
      tanCoeff=0.5, radSpeedMax=60, dragScale=0.0023, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.9, label="calm", ampLo=0.1, ampHi=0.3, durMin=4, durMax=7 },
          { weight=0.1, label="active", ampLo=0.35, ampHi=0.55, durMin=2, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=7 },
      }},
    -- 紫海胆
    { name="紫海胆", diff=1,
      wMin=0.003, wMax=0.25, wBias=0.2, wSpread=0.27,  wSample1=0.1084,
      forceAtMax=0.25, forceExp=0.45,
      tanCoeff=0.1, radSpeedMax=15, dragScale=0.03333, tanSpeedMax=600,
      radialStateTable = {
          { weight=1, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 小丑鱼
    { name="小丑鱼", diff=1,
      wMin=0.003, wMax=0.07, wBias=0.2, wSpread=0.27,  wSample1=0.0316,
      forceAtMax=0.07, forceExp=0.45,
      tanCoeff=0.5, radSpeedMax=60, dragScale=0.0023, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.9, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0.1, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 大鳍弹涂鱼
    { name="大鳍弹涂鱼", diff=1,
      wMin=0.012, wMax=0.15, wBias=0.2, wSpread=0.27,  wSample1=0.0709,
      forceAtMax=0.15, forceExp=0.45,
      tanCoeff=0.1, radSpeedMax=15, dragScale=0.02, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.9, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0.1, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 秋刀鱼
    { name="秋刀鱼", diff=1,
      wMin=0.012, wMax=0.15, wBias=0.2, wSpread=0.27,  wSample1=0.0709,
      forceAtMax=0.15, forceExp=0.45,
      tanCoeff=4, radSpeedMax=130, dragScale=0.0023, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.6, label="calm", ampLo=0.1, ampHi=0.3, durMin=4, durMax=7 },
          { weight=0.3, label="active", ampLo=0.35, ampHi=0.55, durMin=2, durMax=4.5 },
          { weight=0.1, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=7 },
      }},
    -- 文蛤
    { name="文蛤", diff=1,
      wMin=0.007, wMax=0.15, wBias=0.2, wSpread=0.27,  wSample1=0.068,
      forceAtMax=0.15, forceExp=0.45,
      tanCoeff=0.1, radSpeedMax=15, dragScale=0.02, tanSpeedMax=600,
      radialStateTable = {
          { weight=1, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 蛤蜊
    { name="蛤蜊", diff=1,
      wMin=0.004, wMax=0.1, wBias=0.2, wSpread=0.27,  wSample1=0.045,
      forceAtMax=0.1, forceExp=0.45,
      tanCoeff=0.1, radSpeedMax=15, dragScale=0.01333, tanSpeedMax=600,
      radialStateTable = {
          { weight=1, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 弹涂鱼
    { name="弹涂鱼", diff=1,
      wMin=0.007, wMax=0.1, wBias=0.2, wSpread=0.27,  wSample1=0.0467,
      forceAtMax=0.1, forceExp=0.45,
      tanCoeff=0.1, radSpeedMax=15, dragScale=0.01333, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.9, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0.1, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 沙丁鱼
    { name="沙丁鱼", diff=1,
      wMin=0.006, wMax=0.15, wBias=0.2, wSpread=0.27,  wSample1=0.0674,
      forceAtMax=0.15, forceExp=0.45,
      tanCoeff=2, radSpeedMax=130, dragScale=0.0023, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.6, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0.3, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0.1, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 贻贝
    { name="贻贝", diff=1,
      wMin=0.003, wMax=0.07, wBias=0.2, wSpread=0.27,  wSample1=0.0316,
      forceAtMax=0.07, forceExp=0.45,
      tanCoeff=0.1, radSpeedMax=15, dragScale=0.0093, tanSpeedMax=600,
      radialStateTable = {
          { weight=1, label="calm", ampLo=0.1, ampHi=0.3, durMin=1, durMax=7 },
          { weight=0, label="active", ampLo=0.35, ampHi=0.55, durMin=1.5, durMax=4.5 },
          { weight=0, label="active", ampLo=0.55, ampHi=0.85, durMin=0.5, durMax=1.5 },
      }},
    -- 鞭冠鱼
    { name="鞭冠鱼", diff=2,
      wMin=0.3, wMax=6, wBias=0.2, wSpread=0.27,  wSample1=2.7323,
      forceAtMax=6, forceExp=0.45,
      tanCoeff=0.5, radSpeedMax=25, dragScale=0.48, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.6, label="calm", ampLo=0.1, ampHi=0.3, durMin=4, durMax=7 },
          { weight=0.3, label="active", ampLo=0.35, ampHi=0.55, durMin=2, durMax=4.5 },
          { weight=0.1, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=7 },
      }},
    -- 银斧鱼
    { name="银斧鱼", diff=1,
      wMin=0.003, wMax=0.07, wBias=0.2, wSpread=0.27,  wSample1=0.0316,
      forceAtMax=0.07, forceExp=0.45,
      tanCoeff=0.5, radSpeedMax=25, dragScale=0.0056, tanSpeedMax=600,
      radialStateTable = {
          { weight=0.6, label="calm", ampLo=0.1, ampHi=0.3, durMin=4, durMax=7 },
          { weight=0.3, label="active", ampLo=0.35, ampHi=0.55, durMin=2, durMax=4.5 },
          { weight=0.1, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=7 },
      }},
    -- 测试鱼（保留）
    { name="测试鱼", diff=3, wMin=5, wMax=5, wBias=0.5, wSpread=0.3,
      forceAtMax=70, forceExp=0, tanCoeff=1, radSpeedMax=160, dragScale=0.875, tanSpeedMax=600,
      testFixed=true,
      radialStateTable = {
          { weight=1, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=3 },
      }},
}


-- 为每个鱼种注入自身索引（供精灵图查找使用）
do
    for i, ft in ipairs(M.FISH_TYPES) do
        ft.id = i
    end
end

M.FLOOR_FISH_TYPES = {
    -- 竿1 兜底 500g  (力量=重量/4)
    { name="小鱼", diff=1,
      wMin=0.5, wMax=0.5, wBias=0.5, wSpread=0,
      forceAtMax=0.125, forceExp=0,
      tanCoeff=0.8, radSpeedMax=60,  dragScale=0.06, tanSpeedMax=200,
      testFixed=true,
      radialStateTable = {
          { weight=1, label="active", ampLo=0.45, ampHi=0.75, durMin=1, durMax=3 },
      }},
    -- 竿2 兜底 1.5kg  (力量=重量/4)
    { name="小鱼", diff=2,
      wMin=1.5, wMax=1.5, wBias=0.5, wSpread=0,
      forceAtMax=0.375, forceExp=0,
      tanCoeff=1.0, radSpeedMax=80,  dragScale=0.19, tanSpeedMax=300,
      testFixed=true,
      radialStateTable = {
          { weight=1, label="active", ampLo=0.5,  ampHi=0.8,  durMin=1, durMax=3 },
      }},
    -- 竿3 兜底 5kg  (力量=重量/4)
    { name="小鱼", diff=3,
      wMin=5.0, wMax=5.0, wBias=0.5, wSpread=0,
      forceAtMax=1.25, forceExp=0,
      tanCoeff=1.0, radSpeedMax=100, dragScale=0.63, tanSpeedMax=400,
      testFixed=true,
      radialStateTable = {
          { weight=1, label="active", ampLo=0.5,  ampHi=0.8,  durMin=1, durMax=3 },
      }},
    -- 竿4 兜底 10kg  (力量=重量/4)
    { name="小鱼", diff=4,
      wMin=10.0, wMax=10.0, wBias=0.5, wSpread=0,
      forceAtMax=2.5, forceExp=0,
      tanCoeff=1.5, radSpeedMax=130, dragScale=1.25, tanSpeedMax=500,
      testFixed=true,
      radialStateTable = {
          { weight=1, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=3 },
      }},
    -- 竿5 兜底 20kg  (复用竿4力学参数，判定门槛提升)
    { name="小鱼", diff=4,
      wMin=20.0, wMax=20.0, wBias=0.5, wSpread=0,
      forceAtMax=2.5, forceExp=0,
      tanCoeff=1.5, radSpeedMax=130, dragScale=1.25, tanSpeedMax=500,
      testFixed=true,
      radialStateTable = {
          { weight=1, label="active", ampLo=0.55, ampHi=0.85, durMin=1, durMax=3 },
      }},
}

M.ROD_MIN_FIGHT_WEIGHT = { 0.5, 1.5, 5.0, 10.0, 20.0 }

return M
