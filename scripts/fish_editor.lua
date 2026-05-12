-- ============================================================================
-- 鱼类 AI 状态编辑器 v3
-- 双 Tab 架构: Tab1=状态模板编辑  Tab2=鱼种配置(模板组合+外部参数)
-- 底部游戏风格力度条 + 波形图 (NanoVG)
-- 模拟为锁线模式(无出线/摩擦), 张力直接反映鱼力
-- ============================================================================

require "LuaScripts/Utilities/Sample"
local UI = require("urhox-libs/UI")

local vg = nil
local fontId = -1

-- ============================================================================
-- 数据模型
-- ============================================================================

local function CreateDefaultStateTemplate(name, category)
    if category == "radial" then
        return {
            name     = name or "新径向状态",
            category = "radial",
            ampLo    = 0.10,    ampHi    = 0.30,
            durMin   = 3.0,     durMax   = 7.0,
            waveDurMin = 1.5,   waveDurMax = 4.5,
            waveBaseMin = 0.65, waveBaseMax = 0.85,
            tremorAmpLo      = 0.40,  tremorAmpHi      = 0.60,
            tremorWaveDurMin = 0.08,  tremorWaveDurMax = 0.18,
            tremorWaveBaseMin = 0.03, tremorWaveBaseMax = 0.05,
            jerkDurMin     = 0.12,  jerkDurMax     = 0.37,
            jerkCooldownMin = 0.3,  jerkCooldownMax = 1.8,
            jerkAmpPct     = 0.12,
            jerkMul        = 1.0,
        }
    else
        return {
            name     = name or "新切向状态",
            category = "tangential",
            durMin   = 2.0,     durMax   = 6.0,
            waveAmpMin  = 1,    waveAmpMax  = 4,
            baseRange   = 1.0,
            wavePeriodMin = 0.8, wavePeriodMax = 2.8,
        }
    end
end

local stateTemplates = {
    { name = "径向-温和",   category = "radial",
      ampLo = 0.03, ampHi = 0.10, durMin = 3.0, durMax = 7.0,
      waveDurMin = 1.5, waveDurMax = 9.4, waveBaseMin = 0.65, waveBaseMax = 0.70,
      tremorAmpLo = 0, tremorAmpHi = 0.24,
      tremorWaveDurMin = 0.19, tremorWaveDurMax = 0.47,
      tremorWaveBaseMin = 0.024, tremorWaveBaseMax = 0.048,
      jerkDurMin = 0.12, jerkDurMax = 0.37, jerkCooldownMin = 0.5, jerkCooldownMax = 1.8,
      jerkAmpPct = 0, jerkMul = 1.0 },
    { name = "径向-凶猛",   category = "radial",
      ampLo = 0.03, ampHi = 0.10, durMin = 1.5, durMax = 4.5,
      waveDurMin = 0.7, waveDurMax = 2.7, waveBaseMin = 0.26, waveBaseMax = 1.66,
      tremorAmpLo = 0, tremorAmpHi = 0.07,
      tremorWaveDurMin = 0.04, tremorWaveDurMax = 0.49,
      tremorWaveBaseMin = 0.14, tremorWaveBaseMax = 0.144,
      jerkDurMin = 0.12, jerkDurMax = 0.37, jerkCooldownMin = 0.3, jerkCooldownMax = 1.2,
      jerkAmpPct = 0, jerkMul = 1.6 },
    { name = "径向-狂暴",   category = "radial",
      ampLo = 0.09, ampHi = 0.61, durMin = 1.0, durMax = 3.0,
      waveDurMin = 0.8, waveDurMax = 2.5, waveBaseMin = 0.31, waveBaseMax = 1.82,
      tremorAmpLo = 0, tremorAmpHi = 0.27,
      tremorWaveDurMin = 0.0429, tremorWaveDurMax = 0.53,
      tremorWaveBaseMin = 0.12, tremorWaveBaseMax = 0.24,
      jerkDurMin = 0.10, jerkDurMax = 0.30, jerkCooldownMin = 0.3, jerkCooldownMax = 0.7,
      jerkAmpPct = 0.12, jerkMul = 1.3 },
    { name = "切向-轻摆",   category = "tangential",
      durMin = 2.0, durMax = 6.0, waveAmpMin = 1, waveAmpMax = 4,
      baseRange = 1.0, wavePeriodMin = 0.8, wavePeriodMax = 2.8 },
    { name = "切向-横冲",   category = "tangential",
      durMin = 1.0, durMax = 3.0, waveAmpMin = 38, waveAmpMax = 42,
      baseRange = 5.0, wavePeriodMin = 0.8, wavePeriodMax = 2.8 },
    { name = "切向-疯摆",   category = "tangential",
      durMin = 0.8, durMax = 2.0, waveAmpMin = 50, waveAmpMax = 65,
      baseRange = 8.0, wavePeriodMin = 0.5, wavePeriodMax = 1.5 },
}

local function CreateDefaultFishConfig(name)
    return {
        name = name or "新鱼种", diff = 1, color = {120, 180, 80},
        wMin = 0.5, wMax = 2.5, stamina = 40, maxForce = 35,
        radialCalmTemplate   = "径向-温和",  radialActiveTemplate = "径向-凶猛",
        tanCalmTemplate      = "切向-轻摆",  tanActiveTemplate    = "切向-横冲",
        calmProb = 0.75, durMul = 1.0, forceMul = 1.0, ampMul = 1.0,
        maxAngle = 60, dampStart = 30, restoreStr = 2.0,
        fishMass = 0.1, dragCoeff = 1.0, radSpeedCap = 40, tanSpeedCap = 60,
    }
end

local fishConfigs = {
    { name="鲈鱼",   diff=1, color={120,180,80},  wMin=0.5,  wMax=2.5,  stamina=40,  maxForce=35,  calmProb=0.75,
      radialCalmTemplate="径向-温和", radialActiveTemplate="径向-凶猛",
      tanCalmTemplate="切向-轻摆",    tanActiveTemplate="切向-横冲",
      durMul=1.0, forceMul=1.0, ampMul=1.0,
      maxAngle=60, dampStart=30, restoreStr=2.0,
      fishMass=0.1, dragCoeff=1.0, radSpeedCap=40, tanSpeedCap=60 },
    { name="鲷鱼",   diff=2, color={230,110,90},  wMin=1.0,  wMax=4.0,  stamina=55,  maxForce=50,  calmProb=0.70,
      radialCalmTemplate="径向-温和", radialActiveTemplate="径向-凶猛",
      tanCalmTemplate="切向-轻摆",    tanActiveTemplate="切向-横冲",
      durMul=1.0, forceMul=1.0, ampMul=1.0,
      maxAngle=60, dampStart=30, restoreStr=2.0,
      fishMass=0.1, dragCoeff=1.0, radSpeedCap=40, tanSpeedCap=60 },
    { name="金枪鱼", diff=3, color={80,130,210},  wMin=3.0,  wMax=10.0, stamina=75,  maxForce=70,  calmProb=0.60,
      radialCalmTemplate="径向-温和", radialActiveTemplate="径向-狂暴",
      tanCalmTemplate="切向-轻摆",    tanActiveTemplate="切向-横冲",
      durMul=1.0, forceMul=1.0, ampMul=1.0,
      maxAngle=60, dampStart=30, restoreStr=2.0,
      fishMass=0.1, dragCoeff=1.0, radSpeedCap=40, tanSpeedCap=60 },
    { name="旗鱼",   diff=4, color={100,80,200},  wMin=5.0,  wMax=18.0, stamina=90,  maxForce=85,  calmProb=0.55,
      radialCalmTemplate="径向-温和", radialActiveTemplate="径向-狂暴",
      tanCalmTemplate="切向-轻摆",    tanActiveTemplate="切向-疯摆",
      durMul=1.1, forceMul=1.0, ampMul=1.0,
      maxAngle=60, dampStart=30, restoreStr=2.0,
      fishMass=0.1, dragCoeff=1.0, radSpeedCap=40, tanSpeedCap=60 },
    { name="鲨鱼",   diff=5, color={110,115,125}, wMin=10.0, wMax=50.0, stamina=100, maxForce=100, calmProb=0.50,
      radialCalmTemplate="径向-温和", radialActiveTemplate="径向-狂暴",
      tanCalmTemplate="切向-轻摆",    tanActiveTemplate="切向-疯摆",
      durMul=1.2, forceMul=1.0, ampMul=1.2,
      maxAngle=60, dampStart=30, restoreStr=2.0,
      fishMass=0.1, dragCoeff=1.0, radSpeedCap=40, tanSpeedCap=60 },
}

local function FindTemplate(name)
    for _, t in ipairs(stateTemplates) do
        if t.name == name then return t end
    end
    return nil
end

-- ============================================================================
-- 编辑状态
-- ============================================================================
local activeTab = "states"
local selectedStateIdx = 1
local selectedFishIdx  = 1
local uiRoot = nil
local uiRefs = {}

-- 模拟开关 (用于单独关闭某个力分量)
local simEnableWave   = true   -- 主振幅波形
local simEnableTremor = true   -- 颤动
local simEnableJerk   = true   -- 甩头

-- ============================================================================
-- 模拟引擎 — 锁线模式 (无出线/摩擦, 张力 = 鱼力)
-- ============================================================================
local SIM_CFG = {
    LINE_STRENGTH  = 100,    -- 最大张力刻度 (显示用)
    LOCKED_LINE    = 200,    -- 锁定线长 (不变)
}

-- ── 临界阻尼二阶弹簧 (无超调, 比一阶指数平滑更丝滑) ──
-- omega: 自然频率, 越大收敛越快; 临界阻尼 zeta=1
local function Spring2Update(cur, vel, target, omega, dt)
    local diff = cur - target
    local accel = omega * omega * (-diff) - 2.0 * omega * vel
    vel = vel + accel * dt
    cur = cur + vel * dt
    return cur, vel
end

local sim = {
    running = true, time = 0,
    fishRadius = 200, fishAngle = 0, fishRadVel = 0, fishAngVel = 0,
    radState = "calm", radStateTimer = 0, radStateDur = 5.0,
    radPhase = 0,                          -- 累加相位 (弧度, 保持连续)
    radFreq = math.pi * 2 / 2.0,          -- 当前角频率 (rad/s)
    radFreqTarget = math.pi * 2 / 2.0,    -- 目标角频率
    radFreqVel = 0,                        -- 二阶弹簧速度
    radWaveBase = 0.7,                     -- 当前基线
    radWaveBaseTarget = 0.7,               -- 目标基线
    radWaveBaseVel = 0,                    -- 二阶弹簧速度
    radAmpPct = 0.2, radAmpPctTarget = 0.2,
    radAmpPctVel = 0,                      -- 二阶弹簧速度
    tanState = "calm", tanTimer = 0, tanDuration = 3.0,
    tanWaveTime = 0, tanWaveDur = 1.5, tanWaveAmp = 2, tanWaveBase = 0,
    tremorPhase = 0,
    tremorFreq = math.pi * 2 / 0.125, tremorFreqTarget = math.pi * 2 / 0.125, tremorFreqVel = 0,
    tremorWaveBase = 0.04, tremorWaveBaseTarget = 0.04, tremorWaveBaseVel = 0,
    tremorAmpPct = 0.5, tremorAmpPctTarget = 0.5, tremorAmpPctVel = 0,
    tremorCycleTimer = 0, tremorCycleDur = 0.125,
    jerkTimer = 0, jerkDurTotal = 0, jerkCooldown = 1.0, jerkAmp = 0,
    tension = 0,
    fishStamina = 100, fishMaxStam = 100,
    forceRadial = 0, forceTangential = 0,
    history = {}, historyIdx = 0, HISTORY_LEN = 400,
    radWaveCycleTimer = 0, radWaveCycleDur = 2.0,
}

local function GetSimTemplates()
    if activeTab == "states" then
        local st = stateTemplates[selectedStateIdx]
        if not st then return nil, nil, nil, nil end
        if st.category == "radial" then
            return st, st, nil, nil
        else
            return nil, nil, st, st
        end
    else
        local fish = fishConfigs[selectedFishIdx]
        if not fish then return nil, nil, nil, nil end
        return FindTemplate(fish.radialCalmTemplate),
               FindTemplate(fish.radialActiveTemplate),
               FindTemplate(fish.tanCalmTemplate),
               FindTemplate(fish.tanActiveTemplate)
    end
end

local function GetSimFish()
    if activeTab == "fish" then
        return fishConfigs[selectedFishIdx]
    end
    return { maxForce=50, stamina=100, calmProb=0.5, durMul=1.0, forceMul=1.0, ampMul=1.0,
             maxAngle=60, dampStart=30, restoreStr=2.0,
             fishMass=0.1, dragCoeff=1.0, radSpeedCap=40, tanSpeedCap=60 }
end

local function SimReset()
    local fish = GetSimFish()
    sim.time = 0
    sim.fishRadius = SIM_CFG.LOCKED_LINE; sim.fishAngle = 0; sim.fishRadVel = 0; sim.fishAngVel = 0
    sim.radState = "calm"; sim.radStateTimer = 0; sim.radStateDur = 5.0
    sim.radPhase = 0
    sim.radFreq = math.pi * 2 / 2.0; sim.radFreqTarget = math.pi * 2 / 2.0; sim.radFreqVel = 0
    sim.radWaveBase = 0.7; sim.radWaveBaseTarget = 0.7; sim.radWaveBaseVel = 0
    sim.radAmpPct = 0.2; sim.radAmpPctTarget = 0.2; sim.radAmpPctVel = 0
    sim.radWaveCycleTimer = 0; sim.radWaveCycleDur = 2.0
    sim.tanState = "calm"; sim.tanTimer = 0; sim.tanDuration = 3.0
    sim.tanWaveTime = 0; sim.tanWaveDur = 1.5; sim.tanWaveAmp = 2; sim.tanWaveBase = 0
    sim.tremorPhase = math.random() * math.pi * 2
    sim.tremorFreq = math.pi * 2 / 0.125; sim.tremorFreqTarget = sim.tremorFreq; sim.tremorFreqVel = 0
    sim.tremorWaveBase = 0.04; sim.tremorWaveBaseTarget = 0.04; sim.tremorWaveBaseVel = 0
    sim.tremorAmpPct = 0.5; sim.tremorAmpPctTarget = 0.5; sim.tremorAmpPctVel = 0
    sim.tremorCycleTimer = 0; sim.tremorCycleDur = 0.125
    sim.jerkTimer = 0; sim.jerkDurTotal = 0; sim.jerkCooldown = 1.0; sim.jerkAmp = 0
    sim.tension = 0
    sim.fishStamina = fish.stamina or 100
    sim.fishMaxStam = fish.stamina or 100
    sim.forceRadial = 0; sim.forceTangential = 0
    sim.history = {}; sim.historyIdx = 0
end

local function SimGenRadialWave()
    local rCalm, rActive = GetSimTemplates()
    local rt = sim.radState == "active" and rActive or rCalm
    if not rt then return end
    local fish = GetSimFish()
    local dm = fish.durMul or 1.0
    -- 不重置 phase! 只更新目标频率和目标基线, 由 SimStep 平滑插值
    local newDur = (rt.waveDurMin + math.random() * (rt.waveDurMax - rt.waveDurMin)) * dm
    sim.radFreqTarget = math.pi * 2 / math.max(0.01, newDur)
    sim.radWaveBaseTarget = rt.waveBaseMin + math.random() * (rt.waveBaseMax - rt.waveBaseMin)
    -- 重置周期计时器
    sim.radWaveCycleTimer = 0
    sim.radWaveCycleDur = newDur
end

local function SimGenTremorWave()
    local rCalm, rActive = GetSimTemplates()
    local rt = sim.radState == "active" and rActive or rCalm
    if not rt then return end
    local dm = (GetSimFish().durMul or 1.0)
    local newDur = (rt.tremorWaveDurMin + math.random() * (rt.tremorWaveDurMax - rt.tremorWaveDurMin)) * dm
    sim.tremorFreqTarget = math.pi * 2 / math.max(0.001, newDur)
    sim.tremorWaveBaseTarget = rt.tremorWaveBaseMin + math.random() * (rt.tremorWaveBaseMax - rt.tremorWaveBaseMin)
    sim.tremorCycleTimer = 0
    sim.tremorCycleDur = newDur
end

local function SimChangeRadialState()
    local rCalm, rActive = GetSimTemplates()
    local fish = GetSimFish()
    local am = fish.ampMul or 1.0
    local dm = fish.durMul or 1.0
    local cp = fish.calmProb or 0.5
    if activeTab == "states" then cp = 0.5 end

    if math.random() < cp then
        sim.radState = "calm"
        local rt = rCalm
        if rt then
            sim.radStateDur = (rt.durMin + math.random() * (rt.durMax - rt.durMin)) * dm
            sim.radAmpPctTarget = (rt.ampLo + math.random() * (rt.ampHi - rt.ampLo)) * am
            sim.tremorAmpPctTarget = (rt.tremorAmpLo + math.random() * (rt.tremorAmpHi - rt.tremorAmpLo)) * am
        end
    else
        sim.radState = "active"
        local rt = rActive
        if rt then
            sim.radStateDur = (rt.durMin + math.random() * (rt.durMax - rt.durMin)) * dm
            sim.radAmpPctTarget = (rt.ampLo + math.random() * (rt.ampHi - rt.ampLo)) * am
            sim.tremorAmpPctTarget = (rt.tremorAmpLo + math.random() * (rt.tremorAmpHi - rt.tremorAmpLo)) * am
        end
    end
    sim.radStateTimer = 0
    SimGenTremorWave()
end

local function SimChangeTanState()
    local _, _, tCalm, tActive = GetSimTemplates()
    local fish = GetSimFish()
    local dm = fish.durMul or 1.0
    local cp = fish.calmProb or 0.5
    if activeTab == "states" then cp = 0.5 end

    if math.random() < cp then
        sim.tanState = "calm"
        local tt = tCalm
        if tt then
            sim.tanDuration = (tt.durMin + math.random() * (tt.durMax - tt.durMin)) * dm
            sim.tanWaveAmp  = tt.waveAmpMin + math.random() * (tt.waveAmpMax - tt.waveAmpMin)
            sim.tanWaveBase = (math.random() - 0.5) * 2 * tt.baseRange
            sim.tanWaveDur  = tt.wavePeriodMin + math.random() * (tt.wavePeriodMax - tt.wavePeriodMin)
        end
    else
        sim.tanState = "active"
        local tt = tActive
        if tt then
            sim.tanDuration = (tt.durMin + math.random() * (tt.durMax - tt.durMin)) * dm
            sim.tanWaveAmp  = tt.waveAmpMin + math.random() * (tt.waveAmpMax - tt.waveAmpMin)
            sim.tanWaveBase = (math.random() - 0.5) * 2 * tt.baseRange
            sim.tanWaveDur  = tt.wavePeriodMin + math.random() * (tt.wavePeriodMax - tt.wavePeriodMin)
        end
    end
    sim.tanTimer = 0; sim.tanWaveTime = 0
end

local function SimStep(dt)
    if not sim.running then return end
    local fish = GetSimFish()
    local rCalm, rActive, tCalm, tActive = GetSimTemplates()
    sim.time = sim.time + dt

    local mass = fish.fishMass or 0.1
    local dragC = fish.dragCoeff or 1.0
    local maxForce = (fish.maxForce or 50) * (fish.forceMul or 1.0)
    local stamRatio = sim.fishStamina / math.max(1, sim.fishMaxStam)
    local staminaFactor = 0.2 + 0.8 * stamRatio

    -- ═══ 径向力 (平滑过渡: 频率/基线/振幅均用指数平滑) ═══
    local forceRadial = 0
    local rt = sim.radState == "active" and rActive or rCalm
    if rt then
        -- 周期计时 (仅控制何时生成新波形参数, 不影响 phase)
        sim.radWaveCycleTimer = sim.radWaveCycleTimer + dt
        if sim.radWaveCycleTimer >= sim.radWaveCycleDur then SimGenRadialWave() end
        -- 状态切换计时
        sim.radStateTimer = sim.radStateTimer + dt
        if sim.radStateTimer >= sim.radStateDur then SimChangeRadialState() end

        -- 二阶临界阻尼弹簧平滑 (加速度连续, 无突变拐点)
        -- omega=3 → 约 1 秒柔和收敛; omega=2 → 约 1.5 秒更缓
        sim.radFreq, sim.radFreqVel =
            Spring2Update(sim.radFreq, sim.radFreqVel, sim.radFreqTarget, 3.0, dt)
        sim.radWaveBase, sim.radWaveBaseVel =
            Spring2Update(sim.radWaveBase, sim.radWaveBaseVel, sim.radWaveBaseTarget, 3.0, dt)
        sim.radAmpPct, sim.radAmpPctVel =
            Spring2Update(sim.radAmpPct, sim.radAmpPctVel, sim.radAmpPctTarget, 2.0, dt)

        -- 累加相位 (连续, 永不重置 → 无 phase 跳变)
        sim.radPhase = sim.radPhase + sim.radFreq * dt
        local actualAmp = sim.radWaveBase * sim.radAmpPct
        local pullPct = sim.radWaveBase + actualAmp * math.sin(sim.radPhase)
        if simEnableWave then
            forceRadial = maxForce * pullPct * staminaFactor
        end

        -- 颤动 (与主波形同构: 累加相位 + 弹簧平滑)
        sim.tremorCycleTimer = sim.tremorCycleTimer + dt
        if sim.tremorCycleTimer >= sim.tremorCycleDur then SimGenTremorWave() end
        sim.tremorFreq, sim.tremorFreqVel =
            Spring2Update(sim.tremorFreq, sim.tremorFreqVel, sim.tremorFreqTarget, 6.0, dt)
        sim.tremorWaveBase, sim.tremorWaveBaseVel =
            Spring2Update(sim.tremorWaveBase, sim.tremorWaveBaseVel, sim.tremorWaveBaseTarget, 6.0, dt)
        sim.tremorAmpPct, sim.tremorAmpPctVel =
            Spring2Update(sim.tremorAmpPct, sim.tremorAmpPctVel, sim.tremorAmpPctTarget, 4.0, dt)
        sim.tremorPhase = sim.tremorPhase + sim.tremorFreq * dt
        local tremorActualAmp = sim.tremorWaveBase * sim.tremorAmpPct
        local tremorPullPct = sim.tremorWaveBase + tremorActualAmp * math.sin(sim.tremorPhase)
        if simEnableTremor then
            forceRadial = forceRadial + maxForce * tremorPullPct * staminaFactor
        end

        -- 甩头
        if sim.jerkTimer > 0 then
            sim.jerkTimer = sim.jerkTimer - dt
            if sim.jerkTimer <= 0 then
                sim.jerkTimer = 0
                sim.jerkCooldown = (rt.jerkCooldownMin or 0.3) + math.random() * ((rt.jerkCooldownMax or 1.8) - (rt.jerkCooldownMin or 0.3))
            elseif simEnableJerk then
                local prog = 1.0 - sim.jerkTimer / sim.jerkDurTotal
                local env = math.sin(prog * math.pi)
                local jAmpPct = (rt.jerkAmpPct or 0.12) * (rt.jerkMul or 1.0)
                forceRadial = forceRadial + maxForce * jAmpPct * sim.jerkAmp * env * staminaFactor
            end
        else
            sim.jerkCooldown = sim.jerkCooldown - dt
            if sim.jerkCooldown <= 0 then
                local dur = (rt.jerkDurMin or 0.12) + math.random() * ((rt.jerkDurMax or 0.37) - (rt.jerkDurMin or 0.12))
                sim.jerkTimer = dur; sim.jerkDurTotal = dur
                sim.jerkAmp = math.random() > 0.5 and 1 or -1
            end
        end
    end
    sim.forceRadial = forceRadial

    -- ═══ 切向力 ═══
    local forceTan = 0
    local tt = sim.tanState == "active" and tActive or tCalm
    if tt then
        sim.tanTimer = sim.tanTimer + dt
        if sim.tanTimer >= sim.tanDuration then SimChangeTanState() end
        sim.tanWaveTime = sim.tanWaveTime + dt
        if sim.tanWaveTime >= sim.tanWaveDur then
            sim.tanWaveTime = sim.tanWaveTime - sim.tanWaveDur
        end
        local tanPhase = (sim.tanWaveTime / math.max(0.01, sim.tanWaveDur)) * math.pi * 2
        local tanPull = sim.tanWaveBase + sim.tanWaveAmp * math.sin(tanPhase)
        tanPull = math.max(-1, math.min(1, tanPull)) * staminaFactor

        local maxAngleRad = math.rad(fish.maxAngle or 60)
        local dampStartRad = math.rad(fish.dampStart or 30)
        local aD = math.abs(sim.fishAngle)
        if aD > dampStartRad then
            local t = math.min(1, (aD - dampStartRad) / (maxAngleRad - dampStartRad))
            tanPull = tanPull * math.cos(t * math.pi * 0.5)
        end
        local restore = 0
        if aD > dampStartRad then
            local s = sim.fishAngle > 0 and -1 or 1
            restore = s * (fish.restoreStr or 2.0) * ((aD - dampStartRad) / (maxAngleRad - dampStartRad))
        end
        forceTan = tanPull * maxForce * 0.5 + restore
    end
    sim.forceTangential = forceTan

    -- ═══ 锁线模式: 张力 = 鱼的径向力 (无出线/摩擦, 无上限) ═══
    sim.tension = math.max(0, forceRadial)
    sim.fishRadius = SIM_CFG.LOCKED_LINE

    -- 角度物理仍运行 (切向)
    local radius = math.max(1, sim.fishRadius)
    local tanSpeed = sim.fishAngVel * radius
    local netTan = forceTan - tanSpeed * dragC
    tanSpeed = tanSpeed + (netTan / mass) * dt
    tanSpeed = math.max(-(fish.tanSpeedCap or 60), math.min(fish.tanSpeedCap or 60, tanSpeed))
    sim.fishAngVel = tanSpeed / radius
    sim.fishAngle = sim.fishAngle + sim.fishAngVel * dt
    local maxAngleRad = math.rad(fish.maxAngle or 60)
    sim.fishAngle = math.max(-maxAngleRad, math.min(maxAngleRad, sim.fishAngle))

    -- 编辑器模式: 不消耗体力, 避免重置引起视觉跳变
    -- sim.fishStamina 保持满值

    -- 历史 (复用已有table, 减少GC)
    sim.historyIdx = (sim.historyIdx % sim.HISTORY_LEN) + 1
    local entry = sim.history[sim.historyIdx]
    if entry then
        entry.tension  = sim.tension
        entry.forceR   = forceRadial
        entry.radState = sim.radState
        entry.tanState = sim.tanState
    else
        sim.history[sim.historyIdx] = {
            tension = sim.tension, forceR = forceRadial,
            radState = sim.radState, tanState = sim.tanState,
        }
    end
end

-- ============================================================================
-- 保存 / 加载
-- ============================================================================
local SAVE_FILE = "fish_ai_data.json"

local function SaveAll()
    local data = { version = 2, stateTemplates = stateTemplates, fishConfigs = fishConfigs }
    local jsonStr = cjson.encode(data)
    local file = File(SAVE_FILE, FILE_WRITE)
    if file:IsOpen() then
        file:WriteString(jsonStr)
        file:Close()
    end
    -- 同时输出到日志, 方便从日志提取写回工作区持久化
    print("[FishEditor:SAVE_BEGIN]")
    print(jsonStr)
    print("[FishEditor:SAVE_END]")
    print("[FishEditor] Saved: " .. #stateTemplates .. " templates, " .. #fishConfigs .. " fish")
    return true
end

-- 迁移旧版数据: 将 tremorFreq/tremorAmpPct/tremorMul 转换为新波形参数
local function MigrateTemplates()
    for _, st in ipairs(stateTemplates) do
        if st.category == "radial" and not st.tremorAmpLo then
            local oldFreq = st.tremorFreq or 8
            local oldAmp  = st.tremorAmpPct or 0.06
            local oldMul  = st.tremorMul or 1.0
            local period  = 1.0 / math.max(0.1, oldFreq)
            st.tremorAmpLo      = oldAmp * oldMul * 0.7
            st.tremorAmpHi      = oldAmp * oldMul * 1.3
            st.tremorWaveDurMin = period * 0.6
            st.tremorWaveDurMax = period * 1.4
            st.tremorWaveBaseMin = oldAmp * oldMul * 0.4
            st.tremorWaveBaseMax = oldAmp * oldMul * 0.8
            -- 清理旧字段
            st.tremorFreq = nil; st.tremorAmpPct = nil; st.tremorMul = nil
            print("[FishEditor] Migrated tremor for: " .. (st.name or "?"))
        end
    end
end

local function LoadAll()
    -- 优先: WASM 内存文件 (本次会话内的保存)
    if fileSystem:FileExists(SAVE_FILE) then
        local file = File(SAVE_FILE, FILE_READ)
        if file:IsOpen() then
            local ok, data = pcall(cjson.decode, file:ReadString())
            file:Close()
            if ok and data and data.stateTemplates and data.fishConfigs then
                stateTemplates = data.stateTemplates
                fishConfigs = data.fishConfigs
                MigrateTemplates()
                print("[FishEditor] Loaded from local: " .. #stateTemplates .. " templates, " .. #fishConfigs .. " fish")
                return true
            end
        end
    end
    -- 回退: 从打包资源加载 (工作区 assets/ 中的持久化副本)
    if not cache:Exists(SAVE_FILE) then return false end
    local resFile = cache:GetFile(SAVE_FILE)
    if resFile then
        local ok, data = pcall(cjson.decode, resFile:ReadString())
        resFile:Close()
        if ok and data and data.stateTemplates and data.fishConfigs then
            stateTemplates = data.stateTemplates
            fishConfigs = data.fishConfigs
            MigrateTemplates()
            print("[FishEditor] Loaded from bundle: " .. #stateTemplates .. " templates, " .. #fishConfigs .. " fish")
            return true
        end
    end
    return false
end

-- ============================================================================
-- UI 辅助
-- ============================================================================

local function SliderRow(label, obj, key, min, max, step, fmt, pct)
    local function fmtVal(v)
        if pct then return string.format(fmt or "%.0f%%", v * 100) end
        return string.format(fmt or "%.2f", v)
    end
    local valLabel = UI.Label {
        text = fmtVal(obj[key]), width = 60, fontSize = 11,
        textAlign = "right", fontColor = {200,200,200,255},
    }
    local sl = UI.Slider {
        value = obj[key], min = min, max = max, step = step,
        height = 22, flexGrow = 1, flexShrink = 1, flexBasis = 0,
        trackHeight = 3, thumbSize = 12,
        onChange = function(self, v) obj[key] = v; valLabel:SetText(fmtVal(v)) end,
    }
    uiRefs[tostring(obj) .. "." .. key] = { slider = sl, label = valLabel, obj = obj, key = key }
    return UI.Panel {
        flexDirection = "row", alignItems = "center",
        paddingVertical = 1, paddingHorizontal = 4, gap = 4,
        children = {
            UI.Label { text = label, width = 110, fontSize = 11, fontColor = {160,160,160,255} },
            sl, valLabel,
        }
    }
end

local function SectionTitle(text, color)
    return UI.Label {
        text = text, fontSize = 13, fontWeight = "bold",
        fontColor = color or {200,200,200,255},
        marginTop = 8, marginBottom = 2, paddingHorizontal = 6,
    }
end

local function Divider()
    return UI.Panel { width = "100%", height = 1, backgroundColor = {50,55,65,255}, marginVertical = 4 }
end

-- ============================================================================
-- 右侧预览面板 (精简: 只保留状态/体力等文字信息, 力度条移到底部NanoVG)
-- ============================================================================
local pvRadLabel, pvTanLabel, pvTimeLabel
local pvStaminaBar, pvStaminaLabel
local pvFishAngleLabel

local function BuildPreviewPanel()
    pvRadLabel = UI.Label { text = "径向: calm", fontSize = 12, fontColor = {100,200,100,255} }
    pvTanLabel = UI.Label { text = "切向: calm", fontSize = 12, fontColor = {100,200,100,255} }
    pvTimeLabel = UI.Label { text = "0.0s", fontSize = 11, fontColor = {120,120,120,255} }

    pvStaminaBar = UI.ProgressBar {
        value = 1, width = "100%", height = 16,
        backgroundColor = {35,38,48,255}, borderRadius = 3,
        fillGradient = { direction = "to-right", from = "#4CAF50", to = "#8BC34A" },
    }
    pvStaminaLabel = UI.Label { text = "100/100", fontSize = 11, fontColor = {130,200,130,255}, textAlign = "center" }
    pvFishAngleLabel = UI.Label { text = "偏角: 0°", fontSize = 11, fontColor = {120,120,120,255} }

    return UI.Panel {
        width = 200, paddingHorizontal = 10, paddingVertical = 8,
        backgroundColor = {22,25,32,255}, gap = 5,
        children = {
            UI.Label { text = "模拟状态", fontSize = 14, fontWeight = "bold", fontColor = {200,200,200,255} },
            UI.Panel { flexDirection = "row", gap = 10, children = { pvRadLabel, pvTanLabel } },
            pvTimeLabel,
            Divider(),
            UI.Label { text = "体力", fontSize = 11, fontColor = {150,150,150,255} },
            pvStaminaBar, pvStaminaLabel,
            pvFishAngleLabel,
            Divider(),
            UI.Label { text = "力分量开关", fontSize = 12, fontWeight = "bold", fontColor = {180,180,180,255}, marginTop = 2 },
            UI.Button { text = simEnableWave and "振幅 ON" or "振幅 OFF", fontSize = 11,
                backgroundColor = simEnableWave and {60,130,60,255} or {80,40,40,255},
                ref = function(self) uiRefs._btnWave = self end,
                onClick = function(self)
                    simEnableWave = not simEnableWave
                    self:SetText(simEnableWave and "振幅 ON" or "振幅 OFF")
                    self.props.backgroundColor = simEnableWave and {60,130,60,255} or {80,40,40,255}
                end },
            UI.Button { text = simEnableTremor and "颤动 ON" or "颤动 OFF", fontSize = 11,
                backgroundColor = simEnableTremor and {60,130,60,255} or {80,40,40,255},
                onClick = function(self)
                    simEnableTremor = not simEnableTremor
                    self:SetText(simEnableTremor and "颤动 ON" or "颤动 OFF")
                    self.props.backgroundColor = simEnableTremor and {60,130,60,255} or {80,40,40,255}
                end },
            UI.Button { text = simEnableJerk and "甩头 ON" or "甩头 OFF", fontSize = 11,
                backgroundColor = simEnableJerk and {60,130,60,255} or {80,40,40,255},
                onClick = function(self)
                    simEnableJerk = not simEnableJerk
                    self:SetText(simEnableJerk and "甩头 ON" or "甩头 OFF")
                    self.props.backgroundColor = simEnableJerk and {60,130,60,255} or {80,40,40,255}
                end },
            Divider(),
            UI.Panel {
                flexDirection = "row", gap = 6, marginTop = 4,
                children = {
                    UI.Button { text = "重置", variant = "secondary", fontSize = 11,
                        onClick = function()
                            SimReset(); SimGenRadialWave(); SimChangeRadialState(); SimChangeTanState()
                        end },
                    UI.Button { text = "暂停/继续", variant = "primary", fontSize = 11,
                        onClick = function() sim.running = not sim.running end },
                },
            },
        },
    }
end

-- ============================================================================
-- Tab 1: 状态模板编辑器
-- ============================================================================

local function BuildRadialEditor(st)
    return UI.Panel {
        gap = 2,
        children = {
            SectionTitle("振幅 (% of maxForce)", {255,160,80,255}),
            SliderRow("振幅下限",    st, "ampLo",    0, 2.0, 0.01, "%.0f%%", true),
            SliderRow("振幅上限",    st, "ampHi",    0, 3.0, 0.01, "%.0f%%", true),
            Divider(),
            SectionTitle("状态持续时间", {255,160,80,255}),
            SliderRow("最小时长(s)", st, "durMin",   0.3, 20, 0.1, "%.1fs"),
            SliderRow("最大时长(s)", st, "durMax",   0.3, 30, 0.1, "%.1fs"),
            Divider(),
            SectionTitle("波形", {255,160,80,255}),
            SliderRow("波形周期min", st, "waveDurMin",  0.1, 10, 0.1, "%.1fs"),
            SliderRow("波形周期max", st, "waveDurMax",  0.1, 15, 0.1, "%.1fs"),
            SliderRow("基线min",     st, "waveBaseMin", 0,   2.0, 0.01, "%.2f"),
            SliderRow("基线max",     st, "waveBaseMax", 0,   2.0, 0.01, "%.2f"),
            Divider(),
            SectionTitle("颤动 (Tremor) — 与主波形同构", {200,180,255,255}),
            SliderRow("振幅下限",     st, "tremorAmpLo",       0, 3.0, 0.01, "%.0f%%", true),
            SliderRow("振幅上限",     st, "tremorAmpHi",       0, 3.0, 0.01, "%.0f%%", true),
            SliderRow("波形周期min",  st, "tremorWaveDurMin",  0.01, 1.0, 0.01, "%.3fs"),
            SliderRow("波形周期max",  st, "tremorWaveDurMax",  0.01, 2.0, 0.01, "%.3fs"),
            SliderRow("基线min",      st, "tremorWaveBaseMin", 0, 0.5, 0.005, "%.3f"),
            SliderRow("基线max",      st, "tremorWaveBaseMax", 0, 0.5, 0.005, "%.3f"),
            Divider(),
            SectionTitle("甩头 (Jerk)", {200,180,255,255}),
            SliderRow("时长min(s)",   st, "jerkDurMin",     0.05, 1.0, 0.01, "%.2fs"),
            SliderRow("时长max(s)",   st, "jerkDurMax",     0.05, 2.0, 0.01, "%.2fs"),
            SliderRow("冷却min(s)",   st, "jerkCooldownMin", 0.1, 5.0, 0.1, "%.1fs"),
            SliderRow("冷却max(s)",   st, "jerkCooldownMax", 0.1, 10.0, 0.1, "%.1fs"),
            SliderRow("振幅(%力)",    st, "jerkAmpPct",     0, 0.8, 0.01, "%.0f%%", true),
            SliderRow("倍率",         st, "jerkMul",        0.5, 5.0, 0.1, "%.1fx"),
        }
    }
end

local function BuildTangentialEditor(st)
    return UI.Panel {
        gap = 2,
        children = {
            SectionTitle("状态持续时间", {80,180,255,255}),
            SliderRow("最小时长(s)", st, "durMin",  0.3, 20, 0.1, "%.1fs"),
            SliderRow("最大时长(s)", st, "durMax",  0.3, 30, 0.1, "%.1fs"),
            Divider(),
            SectionTitle("摆动振幅", {80,180,255,255}),
            SliderRow("振幅min",     st, "waveAmpMin",  0, 80,  0.5, "%.1f"),
            SliderRow("振幅max",     st, "waveAmpMax",  0, 100, 0.5, "%.1f"),
            SliderRow("偏移范围",    st, "baseRange",   0, 30,  0.1, "%.1f"),
            Divider(),
            SectionTitle("波形周期", {80,180,255,255}),
            SliderRow("周期min(s)",  st, "wavePeriodMin", 0.1, 10, 0.1, "%.1fs"),
            SliderRow("周期max(s)",  st, "wavePeriodMax", 0.1, 15, 0.1, "%.1fs"),
        }
    }
end

local stateListContainer = nil
local stateEditorContainer = nil

local function RefreshStateList()
    if not stateListContainer then return end
    stateListContainer:ClearChildren()
    for i, st in ipairs(stateTemplates) do
        local isRadial = st.category == "radial"
        local selected = (i == selectedStateIdx)
        local bgColor = selected and {50,55,75,255} or {30,33,42,255}
        local tagColor = isRadial and {255,140,60,200} or {60,160,255,200}
        stateListContainer:AddChild(UI.Panel {
            flexDirection = "row", alignItems = "center",
            paddingHorizontal = 8, paddingVertical = 6, gap = 6,
            backgroundColor = bgColor, borderRadius = 4, marginBottom = 2,
            cursor = "pointer",
            onClick = function()
                selectedStateIdx = i
                RefreshStateList()
                RebuildStateEditor()
                SimReset(); SimGenRadialWave(); SimChangeRadialState(); SimChangeTanState()
            end,
            children = {
                UI.Panel { width = 6, height = 6, borderRadius = 3, backgroundColor = tagColor },
                UI.Label {
                    text = st.name, fontSize = 12,
                    fontColor = selected and {255,255,255,255} or {180,180,180,255},
                    flexGrow = 1, flexShrink = 1,
                },
            }
        })
    end
end

function RebuildStateEditor()
    if not stateEditorContainer then return end
    stateEditorContainer:ClearChildren()
    local st = stateTemplates[selectedStateIdx]
    if not st then return end

    stateEditorContainer:AddChild(UI.Panel {
        flexDirection = "row", alignItems = "center", gap = 6,
        paddingHorizontal = 6, paddingVertical = 4,
        children = {
            UI.Label { text = "名称:", fontSize = 12, fontColor = {150,150,150,255}, width = 40 },
            UI.TextField {
                value = st.name, fontSize = 12, flexGrow = 1,
                onChange = function(self, v) st.name = v; RefreshStateList() end,
            },
            UI.Label {
                text = st.category == "radial" and "径向" or "切向",
                fontSize = 11, fontColor = st.category == "radial" and {255,140,60,255} or {60,160,255,255},
            },
        }
    })

    if st.category == "radial" then
        stateEditorContainer:AddChild(BuildRadialEditor(st))
    else
        stateEditorContainer:AddChild(BuildTangentialEditor(st))
    end
end

local function BuildStatesTab()
    stateListContainer = UI.Panel { gap = 2 }
    stateEditorContainer = UI.Panel { gap = 2, paddingBottom = 30 }

    local leftList = UI.Panel {
        width = 180, backgroundColor = {25,28,36,255},
        borderColor = {45,48,58,255}, borderRightWidth = 1,
        children = {
            UI.Panel {
                paddingHorizontal = 6, paddingVertical = 6, gap = 4,
                children = {
                    UI.Label { text = "状态模板", fontSize = 14, fontWeight = "bold", fontColor = {200,200,200,255} },
                    UI.Panel {
                        flexDirection = "row", gap = 4,
                        children = {
                            UI.Button { text = "+径向", fontSize = 10, variant = "primary",
                                onClick = function()
                                    stateTemplates[#stateTemplates+1] = CreateDefaultStateTemplate("径向-新" .. #stateTemplates, "radial")
                                    selectedStateIdx = #stateTemplates
                                    RefreshStateList(); RebuildStateEditor()
                                end },
                            UI.Button { text = "+切向", fontSize = 10, variant = "primary",
                                onClick = function()
                                    stateTemplates[#stateTemplates+1] = CreateDefaultStateTemplate("切向-新" .. #stateTemplates, "tangential")
                                    selectedStateIdx = #stateTemplates
                                    RefreshStateList(); RebuildStateEditor()
                                end },
                        }
                    },
                },
            },
            UI.ScrollView {
                flexGrow = 1, flexBasis = 0, paddingHorizontal = 4,
                children = { stateListContainer },
            },
        },
    }

    local centerEdit = UI.ScrollView {
        flexGrow = 1, flexShrink = 1, flexBasis = 0,
        paddingHorizontal = 4, paddingVertical = 4,
        children = { stateEditorContainer },
    }

    RefreshStateList()
    RebuildStateEditor()

    return UI.Panel {
        flexGrow = 1, flexBasis = 0, flexDirection = "row",
        children = { leftList, centerEdit },
    }
end

-- ============================================================================
-- Tab 2: 鱼种配置器
-- ============================================================================
local fishListContainer = nil
local fishEditorContainer = nil

local function GetRadialTemplateOptions()
    local opts = {}
    for _, t in ipairs(stateTemplates) do
        if t.category == "radial" then opts[#opts+1] = { value = t.name, label = t.name } end
    end
    return opts
end

local function GetTanTemplateOptions()
    local opts = {}
    for _, t in ipairs(stateTemplates) do
        if t.category == "tangential" then opts[#opts+1] = { value = t.name, label = t.name } end
    end
    return opts
end

local function RefreshFishList()
    if not fishListContainer then return end
    fishListContainer:ClearChildren()
    for i, f in ipairs(fishConfigs) do
        local selected = (i == selectedFishIdx)
        fishListContainer:AddChild(UI.Panel {
            flexDirection = "row", alignItems = "center",
            paddingHorizontal = 8, paddingVertical = 6, gap = 6,
            backgroundColor = selected and {50,55,75,255} or {30,33,42,255},
            borderRadius = 4, marginBottom = 2, cursor = "pointer",
            onClick = function()
                selectedFishIdx = i
                RefreshFishList(); RebuildFishEditor()
                SimReset(); SimGenRadialWave(); SimChangeRadialState(); SimChangeTanState()
            end,
            children = {
                UI.Panel {
                    width = 10, height = 10, borderRadius = 5,
                    backgroundColor = {f.color[1], f.color[2], f.color[3], 255},
                },
                UI.Label {
                    text = f.name .. " Lv" .. (f.diff or 1), fontSize = 12,
                    fontColor = selected and {255,255,255,255} or {180,180,180,255},
                    flexGrow = 1, flexShrink = 1,
                },
            }
        })
    end
end

function RebuildFishEditor()
    if not fishEditorContainer then return end
    fishEditorContainer:ClearChildren()
    local f = fishConfigs[selectedFishIdx]
    if not f then return end

    fishEditorContainer:AddChild(UI.Panel {
        flexDirection = "row", alignItems = "center", gap = 6,
        paddingHorizontal = 6, paddingVertical = 4,
        children = {
            UI.Label { text = "名称:", fontSize = 12, fontColor = {150,150,150,255}, width = 40 },
            UI.TextField {
                value = f.name, fontSize = 12, flexGrow = 1,
                onChange = function(self, v) f.name = v; RefreshFishList() end,
            },
            UI.Label { text = "难度:", fontSize = 12, fontColor = {150,150,150,255}, width = 40 },
            UI.Slider {
                value = f.diff, min = 1, max = 10, step = 1, width = 80,
                trackHeight = 3, thumbSize = 12,
                onChange = function(self, v) f.diff = v; RefreshFishList() end,
            },
        }
    })

    fishEditorContainer:AddChild(SectionTitle("状态模板分配", {100,220,160,255}))
    fishEditorContainer:AddChild(UI.Panel {
        gap = 4, paddingHorizontal = 6,
        children = {
            UI.Label { text = "径向 - Calm:", fontSize = 11, fontColor = {255,160,80,200} },
            UI.Dropdown { options = GetRadialTemplateOptions(), value = f.radialCalmTemplate, width = "100%",
                onChange = function(self, v) f.radialCalmTemplate = v end },
            UI.Label { text = "径向 - Active:", fontSize = 11, fontColor = {255,100,60,200}, marginTop = 4 },
            UI.Dropdown { options = GetRadialTemplateOptions(), value = f.radialActiveTemplate, width = "100%",
                onChange = function(self, v) f.radialActiveTemplate = v end },
            UI.Label { text = "切向 - Calm:", fontSize = 11, fontColor = {80,180,255,200}, marginTop = 4 },
            UI.Dropdown { options = GetTanTemplateOptions(), value = f.tanCalmTemplate, width = "100%",
                onChange = function(self, v) f.tanCalmTemplate = v end },
            UI.Label { text = "切向 - Active:", fontSize = 11, fontColor = {60,140,255,200}, marginTop = 4 },
            UI.Dropdown { options = GetTanTemplateOptions(), value = f.tanActiveTemplate, width = "100%",
                onChange = function(self, v) f.tanActiveTemplate = v end },
        }
    })

    fishEditorContainer:AddChild(Divider())
    fishEditorContainer:AddChild(SectionTitle("外部参数 (叠加在模板之上)", {100,220,160,255}))
    fishEditorContainer:AddChild(UI.Panel { gap = 2, children = {
        SliderRow("平静概率",     f, "calmProb",  0,   1.0,  0.01, "%.0f%%", true),
        SliderRow("持续时间倍率", f, "durMul",    0.1, 5.0,  0.1,  "%.1fx"),
        SliderRow("力度倍率",     f, "forceMul",  0.1, 5.0,  0.1,  "%.1fx"),
        SliderRow("振幅倍率",     f, "ampMul",    0.1, 5.0,  0.1,  "%.1fx"),
    }})

    fishEditorContainer:AddChild(Divider())
    fishEditorContainer:AddChild(SectionTitle("基础属性", {220,220,220,255}))
    fishEditorContainer:AddChild(UI.Panel { gap = 2, children = {
        SliderRow("最大拉力",     f, "maxForce",  5,   300,  1,    "%.0f"),
        SliderRow("体力",         f, "stamina",   5,   500,  1,    "%.0f"),
        SliderRow("体重min(kg)",  f, "wMin",      0.1, 100,  0.1,  "%.1f"),
        SliderRow("体重max(kg)",  f, "wMax",      0.1, 200,  0.1,  "%.1f"),
    }})

    fishEditorContainer:AddChild(Divider())
    fishEditorContainer:AddChild(SectionTitle("角度约束", {220,220,220,255}))
    fishEditorContainer:AddChild(UI.Panel { gap = 2, children = {
        SliderRow("最大偏转角°",  f, "maxAngle",   10, 180, 1,   "%.0f°"),
        SliderRow("阻尼起始角°",  f, "dampStart",  5,  90,  1,   "%.0f°"),
        SliderRow("恢复力强度",   f, "restoreStr", 0.1, 10, 0.1, "%.1f"),
    }})

    fishEditorContainer:AddChild(Divider())
    fishEditorContainer:AddChild(SectionTitle("物理参数", {220,220,220,255}))
    fishEditorContainer:AddChild(UI.Panel { gap = 2, paddingBottom = 30, children = {
        SliderRow("质量",         f, "fishMass",    0.01, 1.0,  0.01, "%.2f"),
        SliderRow("水阻力",       f, "dragCoeff",   0.1,  5.0,  0.1,  "%.1f"),
        SliderRow("径向速度上限", f, "radSpeedCap", 10,   200,  1,    "%.0f"),
        SliderRow("切向速度上限", f, "tanSpeedCap", 10,   200,  1,    "%.0f"),
    }})
end

local function BuildFishTab()
    fishListContainer = UI.Panel { gap = 2 }
    fishEditorContainer = UI.Panel { gap = 2 }

    local leftList = UI.Panel {
        width = 180, backgroundColor = {25,28,36,255},
        borderColor = {45,48,58,255}, borderRightWidth = 1,
        children = {
            UI.Panel {
                paddingHorizontal = 6, paddingVertical = 6, gap = 4,
                children = {
                    UI.Label { text = "鱼种列表", fontSize = 14, fontWeight = "bold", fontColor = {200,200,200,255} },
                    UI.Button { text = "+ 新鱼种", fontSize = 10, variant = "primary",
                        onClick = function()
                            fishConfigs[#fishConfigs+1] = CreateDefaultFishConfig("新鱼种" .. #fishConfigs)
                            selectedFishIdx = #fishConfigs
                            RefreshFishList(); RebuildFishEditor()
                        end },
                },
            },
            UI.ScrollView {
                flexGrow = 1, flexBasis = 0, paddingHorizontal = 4,
                children = { fishListContainer },
            },
        },
    }

    local centerEdit = UI.ScrollView {
        flexGrow = 1, flexShrink = 1, flexBasis = 0,
        paddingHorizontal = 4, paddingVertical = 4,
        children = { fishEditorContainer },
    }

    RefreshFishList()
    RebuildFishEditor()

    return UI.Panel {
        flexGrow = 1, flexBasis = 0, flexDirection = "row",
        children = { leftList, centerEdit },
    }
end

-- ============================================================================
-- 主 UI 构建
-- ============================================================================
local contentContainer = nil
local tabStatesBtn, tabFishBtn

local function SwitchTab(tab)
    activeTab = tab
    if not contentContainer then return end
    contentContainer:ClearChildren()
    uiRefs = {}

    if tab == "states" then
        contentContainer:AddChild(BuildStatesTab())
        tabStatesBtn.props.backgroundColor = {60,65,85,255}
        tabFishBtn.props.backgroundColor = {35,38,48,255}
    else
        contentContainer:AddChild(BuildFishTab())
        tabStatesBtn.props.backgroundColor = {35,38,48,255}
        tabFishBtn.props.backgroundColor = {60,65,85,255}
    end

    SimReset(); SimGenRadialWave(); SimChangeRadialState(); SimChangeTanState()
end

-- 底部力度条+波形图的保留高度 (NanoVG 渲染区)
local BOTTOM_BAR_HEIGHT = 100

local function BuildUI()
    uiRefs = {}

    tabStatesBtn = UI.Button {
        text = "状态模板", fontSize = 13,
        backgroundColor = {60,65,85,255},
        onClick = function() SwitchTab("states") end,
    }
    tabFishBtn = UI.Button {
        text = "鱼种配置", fontSize = 13,
        backgroundColor = {35,38,48,255},
        onClick = function() SwitchTab("fish") end,
    }

    local toolbar = UI.Panel {
        height = 44, flexDirection = "row", alignItems = "center",
        paddingHorizontal = 10, gap = 6,
        backgroundColor = {28,32,42,255},
        borderColor = {45,48,58,255}, borderBottomWidth = 1,
        children = {
            UI.Label { text = "Fish AI Editor", fontSize = 16, fontWeight = "bold", fontColor = {220,220,220,255} },
            UI.Panel { width = 16 },
            tabStatesBtn, tabFishBtn,
            UI.Panel { flexGrow = 1 },
            UI.Button { text = "保存", variant = "success", fontSize = 12,
                onClick = function() SaveAll() end },
            UI.Button { text = "加载", variant = "secondary", fontSize = 12,
                onClick = function() if LoadAll() then BuildUI() end end },
        },
    }

    contentContainer = UI.Panel {
        flexGrow = 1, flexShrink = 1, flexBasis = 0, flexDirection = "row",
    }

    local preview = BuildPreviewPanel()

    local root = UI.Panel {
        width = "100%", height = "100%", flexDirection = "column",
        backgroundColor = {18,20,28,255},
        children = {
            toolbar,
            UI.Panel {
                flexGrow = 1, flexShrink = 1, flexBasis = 0, flexDirection = "row",
                children = {
                    contentContainer,
                    UI.Panel {
                        width = 200,
                        borderColor = {45,48,58,255}, borderLeftWidth = 1,
                        children = { preview },
                    },
                },
            },
            -- 底部留白给 NanoVG 力度条+波形图
            UI.Panel {
                width = "100%", height = BOTTOM_BAR_HEIGHT,
                backgroundColor = {12,14,22,255},
            },
        },
    }

    UI.SetRoot(root)
    SwitchTab(activeTab)
end

-- ============================================================================
-- 生命周期
-- ============================================================================

function Start()
    SampleStart()
    graphics.windowTitle = "Fish AI Editor"

    vg = nvgCreate(1)
    if vg then fontId = nvgCreateFont(vg, "sans", "Fonts/MiSans-Regular.ttf") end

    UI.Init({
        fonts = { { family = "sans", weights = { normal = "Fonts/MiSans-Regular.ttf" } } },
        scale = UI.Scale.DEFAULT,
    })
    SampleInitMouseMode(MM_FREE)

    LoadAll()
    SimReset(); SimGenRadialWave(); SimChangeRadialState(); SimChangeTanState()
    BuildUI()
end

-- UI 文本缓存, 仅在值变化时调用 SetText (减少布局重算)
local uiCache = {}

local function CachedSetText(widget, key, text)
    if uiCache[key] ~= text then
        uiCache[key] = text
        widget:SetText(text)
    end
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    SimStep(dt)

    -- 更新右侧状态面板 (带缓存)
    if pvRadLabel then
        local txt = "径向:" .. sim.radState
        CachedSetText(pvRadLabel, "rad", txt)
        pvRadLabel.props.fontColor = sim.radState == "active" and {255,100,60,255} or {100,200,100,255}
    end
    if pvTanLabel then
        local txt = "切向:" .. sim.tanState
        CachedSetText(pvTanLabel, "tan", txt)
        pvTanLabel.props.fontColor = sim.tanState == "active" and {60,140,255,255} or {100,200,100,255}
    end
    if pvTimeLabel then
        CachedSetText(pvTimeLabel, "time", string.format("%.1fs", sim.time))
    end
    if pvFishAngleLabel then
        CachedSetText(pvFishAngleLabel, "angle", string.format("偏角: %.1f°", math.deg(sim.fishAngle)))
    end
end

function HandleNanoVGRender(eventType, eventData)
    if not vg then return end
    local w = graphics:GetWidth()
    local h = graphics:GetHeight()
    local dpr = graphics:GetDPR()
    local lw, lh = w / dpr, h / dpr

    nvgBeginFrame(vg, lw, lh, dpr)

    local fish = GetSimFish()
    local maxForce = (fish.maxForce or 50) * (fish.forceMul or 1.0)

    -- ════════════════════════════════════════════════════════════════
    -- 底部区域: 波形图 + 游戏风格力度条
    -- ════════════════════════════════════════════════════════════════
    local bottomY = lh - BOTTOM_BAR_HEIGHT
    local margin = 20

    -- 背景
    nvgBeginPath(vg); nvgRect(vg, 0, bottomY, lw, BOTTOM_BAR_HEIGHT)
    nvgFillColor(vg, nvgRGBA(12, 14, 22, 255)); nvgFill(vg)
    -- 顶部分割线
    nvgBeginPath(vg); nvgMoveTo(vg, 0, bottomY); nvgLineTo(vg, lw, bottomY)
    nvgStrokeColor(vg, nvgRGBA(45, 50, 65, 255)); nvgStrokeWidth(vg, 1); nvgStroke(vg)

    -- ── 波形图 (上半部分) ──
    local chartX = margin
    local chartY = bottomY + 6
    local chartW = lw - margin * 2
    local chartH = 40

    -- 波形图背景
    nvgBeginPath(vg); nvgRoundedRect(vg, chartX, chartY, chartW, chartH, 3)
    nvgFillColor(vg, nvgRGBA(20, 24, 36, 200)); nvgFill(vg)

    -- 波形图标签
    nvgFontFace(vg, "sans"); nvgFontSize(vg, 9)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(100,100,100,255))
    nvgText(vg, chartX+4, chartY+2, string.format("力度波形  %.1fs", sim.time), nil)

    -- 危险线 (100% maxForce)
    local dangerY = chartY + 4
    nvgBeginPath(vg); nvgMoveTo(vg, chartX, dangerY); nvgLineTo(vg, chartX+chartW, dangerY)
    nvgStrokeColor(vg, nvgRGBA(255,50,50,40)); nvgStrokeWidth(vg, 1); nvgStroke(vg)

    local histLen = #sim.history
    if histLen > 1 then
        local dLen = math.min(histLen, sim.HISTORY_LEN)
        local step = chartW / sim.HISTORY_LEN
        local drawH = chartH - 8
        local drawY = chartY + 4
        local yMax = maxForce * 1.5  -- y轴范围

        -- 张力线 (橙色)
        nvgBeginPath(vg)
        local first = true
        for i = 1, dLen do
            local idx = ((sim.historyIdx - dLen + i - 1) % sim.HISTORY_LEN) + 1
            local e = sim.history[idx]
            if e then
                local x = chartX + (i-1) * step
                local y = drawY + drawH - (e.tension / yMax) * drawH
                y = math.max(drawY, math.min(drawY + drawH, y))
                if first then nvgMoveTo(vg, x, y); first = false else nvgLineTo(vg, x, y) end
            end
        end
        nvgStrokeColor(vg, nvgRGBA(255,140,60,220)); nvgStrokeWidth(vg, 1.5); nvgStroke(vg)

        -- 径向力线 (红色半透明)
        nvgBeginPath(vg); first = true
        for i = 1, dLen do
            local idx = ((sim.historyIdx - dLen + i - 1) % sim.HISTORY_LEN) + 1
            local e = sim.history[idx]
            if e then
                local x = chartX + (i-1) * step
                local y = drawY + drawH - (e.forceR / yMax) * drawH
                y = math.max(drawY, math.min(drawY + drawH, y))
                if first then nvgMoveTo(vg, x, y); first = false else nvgLineTo(vg, x, y) end
            end
        end
        nvgStrokeColor(vg, nvgRGBA(255,80,80,80)); nvgStrokeWidth(vg, 1); nvgStroke(vg)

        -- 状态指示条 (底部细条) — 按状态批量绘制, 减少draw call
        local barStepW = math.max(1, step)
        local barStripY = drawY + drawH + 1
        -- active 色块
        nvgBeginPath(vg)
        for i = 1, dLen do
            local idx = ((sim.historyIdx - dLen + i - 1) % sim.HISTORY_LEN) + 1
            local e = sim.history[idx]
            if e and e.radState == "active" then
                nvgRect(vg, chartX + (i-1) * step, barStripY, barStepW, 2)
            end
        end
        nvgFillColor(vg, nvgRGBA(255,80,60,180)); nvgFill(vg)
        -- calm 色块
        nvgBeginPath(vg)
        for i = 1, dLen do
            local idx = ((sim.historyIdx - dLen + i - 1) % sim.HISTORY_LEN) + 1
            local e = sim.history[idx]
            if e and e.radState ~= "active" then
                nvgRect(vg, chartX + (i-1) * step, barStripY, barStepW, 2)
            end
        end
        nvgFillColor(vg, nvgRGBA(80,200,100,100)); nvgFill(vg)
    end

    -- 图例
    nvgFontSize(vg, 9); nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(255,140,60,255)); nvgText(vg, chartX + chartW - 50, chartY+2, "张力", nil)
    nvgFillColor(vg, nvgRGBA(255,80,80,150)); nvgText(vg, chartX + chartW - 4, chartY+2, "径向力", nil)

    -- ── 游戏风格力度条 (下半部分, 镜像双向填充) ──
    local barW = lw - margin * 2
    local barH = 18
    local barX = margin
    local barY = bottomY + chartH + 18

    -- 张力比例 (锁线模式: 直接是力的比例)
    local tensionRatio = math.min(1.0, sim.tension / SIM_CFG.LINE_STRENGTH)

    -- 渐变色: 绿 → 橙 → 红 (同游戏)
    local tr, tg, tb
    if tensionRatio <= 0.30 then
        tr, tg, tb = 50, 180, 80
    elseif tensionRatio <= 0.60 then
        local t = (tensionRatio - 0.30) / 0.30
        tr = math.floor(50  + (230 - 50)  * t)
        tg = math.floor(180 + (150 - 180) * t)
        tb = math.floor(80  + (40  - 80)  * t)
    elseif tensionRatio <= 0.90 then
        local t = (tensionRatio - 0.60) / 0.30
        tr = math.floor(230 + (220 - 230) * t)
        tg = math.floor(150 + (50  - 150) * t)
        tb = math.floor(40  + (40  - 40)  * t)
    else
        tr, tg, tb = 220, 50, 40
    end

    -- 标题行: 鱼名 + 数值
    nvgFontSize(vg, 12); nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    if activeTab == "fish" then
        local f = fishConfigs[selectedFishIdx]
        if f then
            nvgFillColor(vg, nvgRGBA(f.color[1], f.color[2], f.color[3], 230))
            nvgText(vg, barX, barY - 10, f.name, nil)
        end
    else
        local st = stateTemplates[selectedStateIdx]
        if st then
            local c = st.category == "radial" and {255,160,80} or {80,180,255}
            nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], 230))
            nvgText(vg, barX, barY - 10, st.name, nil)
        end
    end

    -- 状态标签
    local stateText = ""
    local stR, stG, stB = 200, 200, 200
    if sim.radState == "active" then
        stateText = " 挣扎"; stR, stG, stB = 255, 100, 60
    else
        stateText = " 平静"; stR, stG, stB = 100, 200, 120
    end
    local nameEndX = barX + 80
    nvgFillColor(vg, nvgRGBA(stR, stG, stB, 220))
    nvgText(vg, nameEndX, barY - 10, stateText, nil)

    -- 数值 (右对齐)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(220, 220, 230, 200))
    nvgFontSize(vg, 11)
    nvgText(vg, barX + barW, barY - 10,
        string.format("%.1f / %.0f  (%.0f%%)", sim.tension, SIM_CFG.LINE_STRENGTH, tensionRatio * 100), nil)

    -- 背景槽
    nvgBeginPath(vg); nvgRoundedRect(vg, barX, barY, barW, barH, 5)
    nvgFillColor(vg, nvgRGBA(15, 20, 35, 200)); nvgFill(vg)

    -- 镜像双向填充 (从中心向两侧)
    local halfW = barW * 0.5
    local midX = barX + halfW
    local fillPx = tensionRatio * halfW
    if fillPx > 0.5 then
        -- 左半
        nvgBeginPath(vg); nvgRoundedRect(vg, midX - fillPx, barY, fillPx, barH, 0)
        nvgFillColor(vg, nvgRGBA(tr, tg, tb, 220)); nvgFill(vg)
        -- 右半
        nvgBeginPath(vg); nvgRoundedRect(vg, midX, barY, fillPx, barH, 0)
        nvgFillColor(vg, nvgRGBA(tr, tg, tb, 220)); nvgFill(vg)

        -- 发光效果 (靠近边缘时渐亮)
        if tensionRatio > 0.3 then
            local glowAlpha = math.floor(math.min(1, (tensionRatio - 0.3) / 0.7) * 60)
            local glowPaint = nvgBoxGradient(vg, midX - fillPx, barY, fillPx*2, barH, 4, 8,
                nvgRGBA(tr, tg, tb, glowAlpha), nvgRGBA(tr, tg, tb, 0))
            nvgBeginPath(vg); nvgRoundedRect(vg, midX - fillPx - 4, barY - 4, fillPx*2 + 8, barH + 8, 6)
            nvgFillPaint(vg, glowPaint); nvgFill(vg)
        end
    end

    -- 中线
    nvgBeginPath(vg); nvgMoveTo(vg, midX, barY - 2); nvgLineTo(vg, midX, barY + barH + 2)
    nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 100)); nvgStrokeWidth(vg, 1); nvgStroke(vg)

    -- 刻度标记 (25%, 50%, 75%)
    nvgFontSize(vg, 8); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(80, 85, 100, 150))
    for _, pct in ipairs({0.25, 0.50, 0.75}) do
        local tickX = midX + pct * halfW
        nvgBeginPath(vg); nvgMoveTo(vg, tickX, barY + barH); nvgLineTo(vg, tickX, barY + barH + 3)
        nvgStrokeColor(vg, nvgRGBA(80,85,100,120)); nvgStrokeWidth(vg, 1); nvgStroke(vg)
        nvgText(vg, tickX, barY + barH + 3, string.format("%.0f%%", pct * 100), nil)
        -- 左侧对称
        local tickX2 = midX - pct * halfW
        nvgBeginPath(vg); nvgMoveTo(vg, tickX2, barY + barH); nvgLineTo(vg, tickX2, barY + barH + 3)
        nvgStrokeColor(vg, nvgRGBA(80,85,100,120)); nvgStrokeWidth(vg, 1); nvgStroke(vg)
    end

    -- 超限闪烁
    if tensionRatio > 0.85 then
        local flash = math.sin(sim.time * 10) * 0.5 + 0.5
        nvgBeginPath(vg); nvgRoundedRect(vg, barX - 1, barY - 1, barW + 2, barH + 2, 6)
        nvgStrokeColor(vg, nvgRGBA(255, 50, 30, math.floor(flash * 180)))
        nvgStrokeWidth(vg, 2); nvgStroke(vg)
    end

    nvgEndFrame(vg)
end

function Stop()
    if vg then nvgDelete(vg) end
end

SubscribeToEvent("Update", "HandleUpdate")
SubscribeToEvent("NanoVGRender", "HandleNanoVGRender")
