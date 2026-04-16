-- Vagabundo — Volleyball Legends
-- HOST THIS WHOLE FILE ON PASTEBIN (RAW) AND RUN PASTEBIN_LOADER.LUA IN DELTA.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local TeleportService   = game:GetService("TeleportService")
local StarterGui        = game:GetService("StarterGui")
local CoreGui           = game:GetService("CoreGui")

local player = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- Auto-rejoin when the game kicks with an ErrorPrompt
CoreGui.ChildAdded:Connect(function(child)
    if child:IsA("ScreenGui") and child.Name == "ErrorPrompt" then
        task.wait(2)
        pcall(function() TeleportService:Teleport(game.PlaceId, player) end)
    end
end)

local REWARDS = {
	{ id = 1, key = "lucky", label = "Lucky Spin" },
	{ id = 2, key = "yen", label = "Yen" },
	{ id = 4, key = "ability", label = "Lucky Ability Spin" },
	{ id = 5, key = "regular", label = "Regular Spins" }
}

local REWARD_IDS = {
	lucky = 1,
	yen = 2,
	ability = 4,
	regular = 5
}

local function shouldUseGoldRewards(rank)
	return rank >= 8 -- Gold 2+
end

local function getRequestRankedReward()
	return ReplicatedStorage:WaitForChild("Packages")
		:WaitForChild("_Index")
		:WaitForChild("sleitnick_knit@1.7.0")
		:WaitForChild("knit")
		:WaitForChild("Services")
		:WaitForChild("SeasonService")
		:WaitForChild("RF")
		:WaitForChild("RequestRankedReward")
end

-- Rank number to name mapping
local RANK_NAMES = {
	[1] = "Bronze 1",
	[2] = "Bronze 2",
	[3] = "Bronze 3",
	[4] = "Silver 1",
	[5] = "Silver 2",
	[6] = "Silver 3",
	[7] = "Gold 1",
	[8] = "Gold 2",
	[9] = "Gold 3",
	[10] = "Diamond 1",
	[11] = "Diamond 2"
}

local function getPlayerRank()
	local function findRankValue(parent, name)
		local child = parent:FindFirstChild(name)
		if child and child:IsA("IntValue") then
			return child.Value
		end
		return nil
	end

	local rankNames = {"Rank", "rank", "Level", "level", "Tier", "tier", "RANK", "Rang", "rang"}

	local pathsToTry = {
		player,
		player:FindFirstChild("Data"),
		player:FindFirstChild("PlayerData"),
		player:FindFirstChild("data"),
		player:FindFirstChild("Stats"),
		player:FindFirstChild("leaderstats"),
		player:FindFirstChild("Values"),
		player:FindFirstChild("Settings"),
	}

	for _, path in ipairs(pathsToTry) do
		if path then
			for _, name in ipairs(rankNames) do
				local val = findRankValue(path, name)
				if val and type(val) == "number" and val >= 1 and val <= 11 then
					return val
				end
			end
		end
	end

	local deeperPaths = {
		player:FindFirstChild("Data") and player.Data:FindFirstChild("Stats"),
		player:FindFirstChild("Data") and player.Data:FindFirstChild("PlayerStats"),
		player:FindFirstChild("Data") and player.Data:FindFirstChild("Statistics"),
		player:FindFirstChild("Data") and player.Data:FindFirstChild("Rank"),
		player:FindFirstChild("leaderstats") and player.leaderstats:FindFirstChild("Stats"),
	}

	for _, path in ipairs(deeperPaths) do
		if path then
			for _, name in ipairs(rankNames) do
				local val = findRankValue(path, name)
				if val and type(val) == "number" and val >= 1 and val <= 11 then
					return val
				end
			end
		end
	end

	local ok, knit = pcall(function()
		return require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("_Index"):WaitForChild("sleitnick_knit@1.7.0"):WaitForChild("knit"))
	end)

	if ok and knit then
		local playerService = knit.Player
		if playerService then
			local ok2, val = pcall(function()
				return playerService:GetAttribute("Rank")
			end)
			if ok2 and type(val) == "number" and val >= 1 and val <= 11 then
				return val
			end
		end
	end

	return 1
end

local function getRankDisplayName(rank)
	return RANK_NAMES[rank] or tostring(rank)
end

local function getEligibleRewardIds(rewardKey, currentRank)
	return { REWARD_IDS[rewardKey] }
end

local function claimBestAvailableReward(rf, rewardKey, currentRank)
	local eligibleRewardIds = getEligibleRewardIds(rewardKey, currentRank)

	for _, rewardId in ipairs(eligibleRewardIds) do
		local args = { rewardId }
		local ok, result = pcall(function()
			return rf:InvokeServer(unpack(args))
		end)

		if ok then
			return true, rewardId, result
		end
	end

	return false, nil, nil
end

local playerRank = getPlayerRank()

local enabled = {}
for _, r in ipairs(REWARDS) do
	enabled[r.key] = false
end

local smartAimEnabled    = false
local selectedAimMode    = "Biggest Gap"
local lastBallLandX      = nil
local lastBallLandZ      = nil
local autoReceiveEnabled = false
local autoSpikeEnabled   = false

-- Visual features
local trajectoryEnabled  = false
local visualColor        = Color3.fromRGB(0, 255, 100)  -- shared: trajectory + ball hitbox
local ballHitboxEnabled  = false
local CurrentHitboxScale = 5.0

-- Directional beam lines (Helpers tab)
local linesEnabled  = false
local lineDistance  = 50

-- Character tab
local directionalJumpEnabled = true
local moveInAirEnabled       = false
local AirMoveSpeed           = 50
local IsJumping              = false

-- Auto Tilt (Helpers tab)
local autoTiltEnabled = false
local hotkeyEnum      = Enum.KeyCode.Z

-- Enemy Jump ESP
local enemyJumpESPEnabled = true

-- =====================================
-- CONFIG SAVE / LOAD
-- =====================================

local HttpService  = game:GetService("HttpService")
local CONFIG_FILE  = "vagabundo_config.json"
local _savePending = false

local function saveConfig()
    if _savePending then return end
    _savePending = true
    task.delay(1, function()
        _savePending = false
        local cfg = {
            smartAimEnabled         = smartAimEnabled,
            selectedAimMode         = selectedAimMode,
            autoReceiveEnabled      = autoReceiveEnabled,
            autoSpikeEnabled        = autoSpikeEnabled,
            trajectoryEnabled       = trajectoryEnabled,
            visualColorR            = math.round(visualColor.R * 255),
            visualColorG            = math.round(visualColor.G * 255),
            visualColorB            = math.round(visualColor.B * 255),
            linesEnabled            = linesEnabled,
            lineDistance            = lineDistance,
            ballHitboxEnabled       = ballHitboxEnabled,
            CurrentHitboxScale      = CurrentHitboxScale,
            directionalJumpEnabled  = directionalJumpEnabled,
            moveInAirEnabled        = moveInAirEnabled,
            AirMoveSpeed            = AirMoveSpeed,
            autoTiltEnabled         = autoTiltEnabled,
        }
        local ok, encoded = pcall(HttpService.JSONEncode, HttpService, cfg)
        if ok then pcall(writefile, CONFIG_FILE, encoded) end
    end)
end

-- Load saved config and apply to state variables BEFORE the UI is built
-- so CurrentValue / CurrentOption in each widget reflects saved state.
do
    local ok, raw = pcall(readfile, CONFIG_FILE)
    if ok and raw and raw ~= "" then
        local ok2, cfg = pcall(HttpService.JSONDecode, HttpService, raw)
        if ok2 and cfg then
            if cfg.selectedAimMode    then selectedAimMode    = cfg.selectedAimMode    end

            if cfg.smartAimEnabled        ~= nil then smartAimEnabled        = cfg.smartAimEnabled        end
            if cfg.autoReceiveEnabled     ~= nil then autoReceiveEnabled     = cfg.autoReceiveEnabled     end
            if cfg.autoSpikeEnabled       ~= nil then autoSpikeEnabled       = cfg.autoSpikeEnabled       end
            if cfg.trajectoryEnabled      ~= nil then trajectoryEnabled      = cfg.trajectoryEnabled      end
            if cfg.visualColorR and cfg.visualColorG and cfg.visualColorB then
                visualColor = Color3.fromRGB(cfg.visualColorR, cfg.visualColorG, cfg.visualColorB)
            end
            if cfg.linesEnabled           ~= nil then linesEnabled           = cfg.linesEnabled           end
            if cfg.ballHitboxEnabled      ~= nil then ballHitboxEnabled      = cfg.ballHitboxEnabled      end
            if cfg.CurrentHitboxScale          then CurrentHitboxScale      = cfg.CurrentHitboxScale      end
            if cfg.lineDistance                then lineDistance             = cfg.lineDistance            end
            if cfg.directionalJumpEnabled ~= nil then directionalJumpEnabled = cfg.directionalJumpEnabled end
            if cfg.moveInAirEnabled       ~= nil then moveInAirEnabled       = cfg.moveInAirEnabled       end
            if cfg.AirMoveSpeed                then AirMoveSpeed            = cfg.AirMoveSpeed            end
            if cfg.autoTiltEnabled        ~= nil then autoTiltEnabled        = cfg.autoTiltEnabled        end
        end
    end
end

-- =====================================
-- BALL HITBOX FUNCTIONS (Ball.001 Part)
-- =====================================

local function _findAnyBallPart(model)
    for _, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") then return part end
    end
end

local function createOrUpdateHitboxes(scale)
    for _, model in ipairs(workspace:GetChildren()) do
        if model:IsA("Model") and model.Name:match("^CLIENT_BALL_%d+$") then
            local ball = model:FindFirstChild("Ball.001")
            if not ball then
                local ref = _findAnyBallPart(model)
                if ref then
                    ball = Instance.new("Part")
                    ball.Name         = "Ball.001"
                    ball.Shape        = Enum.PartType.Ball
                    ball.Size         = Vector3.new(2, 2, 2) * scale
                    ball.CFrame       = ref.CFrame
                    ball.Anchored     = true
                    ball.CanCollide   = false
                    ball.Transparency = 0.6
                    ball.Material     = Enum.Material.ForceField
                    ball.Color        = visualColor
                    ball.Parent       = model
                end
            else
                ball.Size = Vector3.new(2, 2, 2) * scale
            end
        end
    end
end

local function clearHitboxes()
    for _, model in ipairs(workspace:GetChildren()) do
        if model:IsA("Model") and model.Name:match("^CLIENT_BALL_%d+$") then
            local ball = model:FindFirstChild("Ball.001")
            if ball then ball:Destroy() end
        end
    end
end

workspace.ChildAdded:Connect(function(child)
    if child:IsA("Model") and child.Name:match("^CLIENT_BALL_%d+$") then
        task.wait(0.1)
        if ballHitboxEnabled then createOrUpdateHitboxes(CurrentHitboxScale) end
    end
end)

-- =====================================
-- CHARACTER SETUP (for directional jump / air movement)
-- =====================================

local charHumanoid, charHRP

local function setupCharacter(character)
    charHumanoid = character:WaitForChild("Humanoid")
    charHRP      = character:WaitForChild("HumanoidRootPart")
    charHumanoid.StateChanged:Connect(function(_, state)
        if state == Enum.HumanoidStateType.Landed then
            charHumanoid.AutoRotate = true
        end
    end)
end

if player.Character then setupCharacter(player.Character) end
player.CharacterAdded:Connect(setupCharacter)

-- Directional jump: face camera direction on jump
UserInputService.JumpRequest:Connect(function()
    if directionalJumpEnabled and charHumanoid and charHRP then
        task.defer(function()
            task.wait(0.03)
            local dir = Vector3.new(Camera.CFrame.LookVector.X, 0, Camera.CFrame.LookVector.Z)
            if dir.Magnitude > 0 then
                charHRP.CFrame = CFrame.lookAt(charHRP.Position, charHRP.Position + dir.Unit)
                charHumanoid.AutoRotate = false
            end
        end)
    elseif charHumanoid then
        charHumanoid.AutoRotate = true
    end
end)

-- Track jumping state for air movement
RunService.Stepped:Connect(function()
    if charHumanoid then
        local st = charHumanoid:GetState()
        IsJumping = (st == Enum.HumanoidStateType.Jumping or st == Enum.HumanoidStateType.Freefall)
    end
end)

-- Air movement
RunService.RenderStepped:Connect(function()
    if moveInAirEnabled and IsJumping and charHumanoid and charHRP then
        local md = charHumanoid.MoveDirection
        if md.Magnitude > 0 then
            charHRP.AssemblyLinearVelocity = Vector3.new(
                md.X * AirMoveSpeed, charHRP.AssemblyLinearVelocity.Y, md.Z * AirMoveSpeed
            )
        end
    end
end)

-- =====================================
-- AUTO TILT
-- =====================================

local function applyTilt()
    if not autoTiltEnabled then return end
    local character = player.Character
    if not character then return end
    local hum = character:FindFirstChildOfClass("Humanoid")
    if hum and hum:GetState() == Enum.HumanoidStateType.Freefall then
        local dir = Vector3.new(Camera.CFrame.LookVector.X, 0, Camera.CFrame.LookVector.Z)
        if dir.Magnitude > 0 then hum:Move(dir.Unit, false) end
    end
end

RunService.RenderStepped:Connect(applyTilt)

UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == hotkeyEnum then
        autoTiltEnabled = not autoTiltEnabled
        saveConfig()
    end
end)

-- =====================================
-- CLONE ESP
-- =====================================

local CloneESP = {}
CloneESP.enabled = false
CloneESP.color   = Color3.fromRGB(255, 255, 255)
CloneESP.espFolder = nil
CloneESP.clones    = {}
CloneESP.renderConn = nil

local _validBodyParts = {
    Head=true, Torso=true, UpperTorso=true, LowerTorso=true,
    LeftArm=true, RightArm=true, LeftUpperArm=true, RightUpperArm=true,
    LeftLowerArm=true, RightLowerArm=true, LeftHand=true, RightHand=true,
    LeftLeg=true, RightLeg=true, LeftUpperLeg=true, RightUpperLeg=true,
    LeftLowerLeg=true, RightLowerLeg=true, LeftFoot=true, RightFoot=true,
    HumanoidRootPart=true,
}
local ESP_OFFSET       = 5
local ESP_TRANSPARENCY = 0.3

function CloneESP:Cleanup()
    if self.renderConn then self.renderConn:Disconnect(); self.renderConn = nil end
    if self.espFolder  then self.espFolder:Destroy(); self.espFolder = nil end
    self.clones = {}
end

function CloneESP:CreateESP(character)
    if not character then return end
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    self:Cleanup()
    self.espFolder = Instance.new("Folder")
    self.espFolder.Name   = "ESP_Clones"
    self.espFolder.Parent = Camera
    for _, part in ipairs(character:GetChildren()) do
        if (part:IsA("Part") or part:IsA("MeshPart")) and _validBodyParts[part.Name] then
            local clone = part:Clone()
            clone.Anchored   = true
            clone.CanCollide = false
            clone.CanTouch   = false
            clone.CanQuery   = false
            clone.Color      = self.color
            clone.Transparency = part.Transparency + ESP_TRANSPARENCY
            clone.Material   = part.Material
            clone.Parent     = self.espFolder
            for _, ch in ipairs(clone:GetChildren()) do
                if ch:IsA("Script") or ch:IsA("LocalScript") or ch:IsA("ModuleScript")
                or ch:IsA("Motor6D") or ch:IsA("Weld") or ch:IsA("WeldConstraint")
                or ch:IsA("Humanoid") or ch:IsA("Attachment") then ch:Destroy() end
            end
            self.clones[part] = clone
        end
    end
    self.renderConn = RunService.RenderStepped:Connect(function()
        if not character or not character.Parent then return end
        local camLook = Camera.CFrame.LookVector
        local hLook   = Vector3.new(camLook.X, 0, camLook.Z)
        hLook = hLook.Magnitude > 0 and hLook.Unit or Vector3.new(0,0,1)
        local espPos   = hrp.Position - hLook * ESP_OFFSET
        local espCF    = CFrame.new(espPos, espPos + hLook)
        for orig, clone in pairs(self.clones) do
            if orig and orig:IsDescendantOf(character) and clone and clone.Parent then
                local ok, rel = pcall(function() return hrp.CFrame:ToObjectSpace(orig.CFrame) end)
                if ok then
                    clone.CFrame       = espCF * rel
                    clone.Color        = self.color
                    clone.Material     = orig.Material
                    clone.Transparency = orig.Transparency + ESP_TRANSPARENCY
                end
            end
        end
    end)
end

player.CharacterAdded:Connect(function(char)
    task.wait(1)
    if CloneESP.enabled then CloneESP:CreateESP(char) end
end)
if player.Character and CloneESP.enabled then CloneESP:CreateESP(player.Character) end

-- =====================================
-- ENEMY JUMP ESP
-- =====================================

local jumpESPStorage = {}
local jumpESPConns   = {}

local function _isEnemy(p)
    return p ~= player and p.Team and player.Team and p.Team ~= player.Team
end

local function _createJumpESP(p)
    if not p.Character or jumpESPStorage[p] then return end
    local hl = Instance.new("Highlight")
    hl.Name                = "JumpESP"
    hl.Adornee             = p.Character
    hl.FillTransparency    = 1
    hl.OutlineTransparency = 0
    hl.OutlineColor        = Color3.fromRGB(255, 255, 0)
    hl.DepthMode           = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Parent              = p.Character
    jumpESPStorage[p]      = hl
end

local function _removeJumpESP(p)
    if jumpESPStorage[p] then jumpESPStorage[p]:Destroy(); jumpESPStorage[p] = nil end
end

local function _setupJumpESP(p)
    if p == player then return end
    local function monitorChar(character)
        if jumpESPConns[p] then
            for _, c in pairs(jumpESPConns[p]) do pcall(function() c:Disconnect() end) end
        end
        _removeJumpESP(p)
        local hum = character:WaitForChild("Humanoid", 3)
        if not hum then return end
        local sc = hum.StateChanged:Connect(function(_, st)
            if not enemyJumpESPEnabled then return end
            if _isEnemy(p) then
                if st == Enum.HumanoidStateType.Jumping or st == Enum.HumanoidStateType.Freefall then
                    _createJumpESP(p)
                elseif st == Enum.HumanoidStateType.Landed then
                    _removeJumpESP(p)
                end
            else
                _removeJumpESP(p)
            end
        end)
        local hc = RunService.Heartbeat:Connect(function()
            if not p.Character or not _isEnemy(p) then _removeJumpESP(p); return end
            local st = hum:GetState()
            if st ~= Enum.HumanoidStateType.Jumping and st ~= Enum.HumanoidStateType.Freefall then
                _removeJumpESP(p)
            end
        end)
        jumpESPConns[p] = {sc, hc}
    end
    if p.Character then monitorChar(p.Character) end
    p.CharacterAdded:Connect(monitorChar)
end

for _, p in ipairs(Players:GetPlayers()) do _setupJumpESP(p) end
Players.PlayerAdded:Connect(_setupJumpESP)
Players.PlayerRemoving:Connect(function(p)
    _removeJumpESP(p)
    if jumpESPConns[p] then
        for _, c in pairs(jumpESPConns[p]) do pcall(function() c:Disconnect() end) end
        jumpESPConns[p] = nil
    end
end)

-- =====================================
-- BEAM DIRECTIONAL LINES
-- =====================================

local beams = {}
local _colorList = {
    Color3.fromRGB(255,0,0),   Color3.fromRGB(0,255,0),
    Color3.fromRGB(0,0,255),   Color3.fromRGB(255,165,0),
    Color3.fromRGB(128,0,128), Color3.fromRGB(255,255,0),
    Color3.fromRGB(139,0,0),   Color3.fromRGB(0,100,0),
}

local function _createBeam(p, index)
    if beams[p] then return end
    local character = p.Character
    if not character then return end
    local head = character:FindFirstChild("Head")
    if not head then return end
    local startAtt  = Instance.new("Attachment", head)
    local targetPart = Instance.new("Part")
    targetPart.Anchored     = true
    targetPart.CanCollide   = false
    targetPart.Transparency = 1
    targetPart.Size         = Vector3.new(0.1,0.1,0.1)
    targetPart.Parent       = workspace
    local endAtt = Instance.new("Attachment", targetPart)
    local beam = Instance.new("Beam")
    beam.Attachment0   = startAtt
    beam.Attachment1   = endAtt
    beam.Width0        = 0.25
    beam.Width1        = 0.25
    beam.FaceCamera    = true
    beam.LightEmission = 1
    beam.Transparency  = NumberSequence.new(0.3)
    beam.Color         = ColorSequence.new(_colorList[(index-1) % #_colorList + 1])
    beam.Parent        = head
    beams[p] = { beam=beam, target=targetPart, att=startAtt, active=true }
end

local function _clearBeam(p)
    local d = beams[p]
    if d then
        if d.beam   then d.beam:Destroy()   end
        if d.target then d.target:Destroy() end
        if d.att    then d.att:Destroy()    end
        beams[p] = nil
    end
end

RunService.RenderStepped:Connect(function()
    if not linesEnabled then
        for _, d in pairs(beams) do if d and d.beam then d.beam.Enabled = false end end
        return
    end
    local enemies = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player and p.Team ~= player.Team then
            table.insert(enemies, p)
        end
    end
    for i, p in ipairs(enemies) do
        if not beams[p] then _createBeam(p, i) end
        local d = beams[p]
        if d then
            d.beam.Enabled = true
            local character = p.Character
            local head = character and character:FindFirstChild("Head")
            local hrp  = character and character:FindFirstChild("HumanoidRootPart")
            if head and hrp then
                d.target.Position = head.Position + hrp.CFrame.LookVector * lineDistance
            end
        end
    end
    -- hide beams for players no longer enemies
    for p, d in pairs(beams) do
        local found = false
        for _, ep in ipairs(enemies) do if ep == p then found = true; break end end
        if not found and d and d.beam then d.beam.Enabled = false end
    end
end)

Players.PlayerRemoving:Connect(_clearBeam)

-- =====================================
-- DYNAMIC HITBOX SYSTEM
-- =====================================
local Hitbox = {
    Enabled = false,
    Interval = 5,
    MinSize = 1.0,
    MaxSize = 8.0,
    CurrentSize = 3.0,
    Color = Color3.fromRGB(0, 255, 100),
    Transparency = 0.35,
    UpdateThread = nil
}

function Hitbox:Unload()
    self.Enabled = false
    if self.UpdateThread then
        self.UpdateThread:Disconnect()
        self.UpdateThread = nil
    end
    for _, model in ipairs(workspace:GetChildren()) do
        if model:IsA("Model") and model.Name:match("^CLIENT_BALL_%d+$") then
            local hitbox = model:FindFirstChild("DYNAMIC_HITBOX")
            if hitbox then hitbox:Destroy() end
        end
    end
    if Luna and Luna.Destroy then
        Luna:Destroy()
    end
    print("[🔴] System unloaded")
end

function Hitbox:GetRandomSize()
    return math.random(self.MinSize * 10, self.MaxSize * 10) / 10
end

function Hitbox:ApplyToBall(model)
    if not model:IsA("Model") then return end
    if not model.Name:match("^CLIENT_BALL_%d+$") then return end
    local basePart
    for _, child in ipairs(model:GetDescendants()) do
        if child:IsA("BasePart") then basePart = child; break end
    end
    if not basePart then return end
    local hitbox = model:FindFirstChild("DYNAMIC_HITBOX")
    if not hitbox then
        hitbox = Instance.new("Part")
        hitbox.Name         = "DYNAMIC_HITBOX"
        hitbox.Shape        = Enum.PartType.Ball
        hitbox.Size         = Vector3.new(2, 2, 2) * self.CurrentSize
        hitbox.CFrame       = basePart.CFrame
        hitbox.Anchored     = true
        hitbox.CanCollide   = false
        hitbox.Transparency = self.Transparency
        hitbox.Material     = Enum.Material.Neon
        hitbox.Color        = self.Color
        hitbox.Parent       = model
    else
        hitbox.Size         = Vector3.new(2, 2, 2) * self.CurrentSize
        hitbox.Transparency = self.Transparency
        hitbox.Color        = self.Color
    end
end

function Hitbox:UpdateAll()
    if not self.Enabled then return end
    self.CurrentSize = self:GetRandomSize()
    for _, model in ipairs(workspace:GetChildren()) do
        if model:IsA("Model") and model.Name:match("^CLIENT_BALL_%d+$") then
            self:ApplyToBall(model)
        end
    end
end

function Hitbox:StartAutoUpdate()
    if self.UpdateThread then
        self.UpdateThread:Disconnect()
    end
    self.UpdateThread = RunService.Heartbeat:Connect(function()
        if tick() - (self.LastUpdate or 0) >= self.Interval then
            self:UpdateAll()
            self.LastUpdate = tick()
        end
    end)
end

function Hitbox:Cleanup()
    for _, model in ipairs(workspace:GetChildren()) do
        if model:IsA("Model") and model.Name:match("^CLIENT_BALL_%d+$") then
            local hitbox = model:FindFirstChild("DYNAMIC_HITBOX")
            if hitbox then hitbox:Destroy() end
        end
    end
    if self.UpdateThread then
        self.UpdateThread:Disconnect()
        self.UpdateThread = nil
    end
end

workspace.ChildAdded:Connect(function(child)
    if child:IsA("Model") and child.Name:match("^CLIENT_BALL_%d+$") then
        task.wait(0.1)
        if Hitbox.Enabled then
            Hitbox:ApplyToBall(child)
        end
    end
end)

-- =====================================
-- LUNA UI
-- =====================================

local Luna = loadstring(game:HttpGet("https://raw.githubusercontent.com/Nebula-Softworks/Luna-Interface-Suite/refs/heads/master/source.lua", true))()

local Window = Luna:CreateWindow({
   Name = "💜 Vagabundo",
   Subtitle = "by Otr_bb",
   LoadingEnabled = true,
   LoadingTitle = "Vagabundo",
   LoadingSubtitle = "by Otr_bb",
   ConfigSettings = { ConfigFolder = "Vagabundo" },
   KeySystem = false,
})

local SpinsTab  = Window:CreateTab({Name = "🎰 Spins",  ShowTitle = true})
local RankedTab = Window:CreateTab({Name = "🏐 Ranked", ShowTitle = true})
local VisualTab = Window:CreateTab({Name = "🎨 Visual", ShowTitle = true})
local MiscTab   = Window:CreateTab({Name = "⚙️ Misc",   ShowTitle = true})

-- Rank section and all Misc content created inside _createMiscContent (password-gated below)
local selectedRank = 1

-- ==================== SPINS TAB
local SpinsSection = SpinsTab:CreateSection("Auto Claim")

for _, r in ipairs(REWARDS) do
	SpinsTab:CreateToggle({
		Name = r.label,
		CurrentValue = false,
		Callback = function(Value)
			enabled[r.key] = Value
		end,
	}, "Spin_" .. r.key)
end

-- ==================== RANKED TAB
local RankedSection = RankedTab:CreateSection("Game Features")

RankedTab:CreateToggle({
	Name = "Auto Spike Aim",
	CurrentValue = false,
	Callback = function(Value)
		smartAimEnabled = Value
		saveConfig()
	end,
}, "AutoSpikeAim")

RankedTab:CreateDropdown({
	Name = "Aim Strategy",
	Options = {"Biggest Gap", "Court Edges", "Target Landed", "Avoid Blockers", "Weakest Spot"},
	CurrentOption = {selectedAimMode},
	MultipleOptions = false,
	Callback = function(Option)
		selectedAimMode = Option
		saveConfig()
	end,
}, "AimStrategy")


RankedTab:CreateToggle({
	Name = "Auto Set",
	CurrentValue = autoReceiveEnabled,
	Callback = function(Value)
		autoReceiveEnabled = Value
		saveConfig()
	end,
}, "AutoSet")

RankedTab:CreateToggle({
	Name = "Auto Spike",
	CurrentValue = autoSpikeEnabled,
	Callback = function(Value)
		autoSpikeEnabled = Value
		saveConfig()
	end,
}, "AutoSpike")



RankedTab:CreateToggle({
	Name = "Auto Back Block",
	CurrentValue = false,
	Callback = function(Value)
		print("Auto Back Block: " .. tostring(Value))
	end,
}, "AutoBackBlock")

-- ==================== VISUAL TAB
VisualTab:CreateSection("Visuals")

-- ── Ball Trajectory ───────────────────────────────────────────────────────────
-- Color picker appears when trajectory is enabled; the same color is shared
-- with the ball hitbox so both always match.
local _trajColorPicker = nil
local function _destroyTrajColorPicker()
	if _trajColorPicker then pcall(function() _trajColorPicker:Destroy() end); _trajColorPicker = nil end
end
local function _createTrajColorPicker()
	if _trajColorPicker then return end
	_trajColorPicker = VisualTab:CreateColorPicker({
		Name = "Trajectory & Hitbox Color",
		Color = visualColor,
		Callback = function(color)
			visualColor = color
			saveConfig()
			-- Refresh hitbox color live if it is currently active
			if ballHitboxEnabled then
				for _, model in ipairs(workspace:GetChildren()) do
					if model:IsA("Model") and model.Name:match("^CLIENT_BALL_%d+$") then
						local ball = model:FindFirstChild("Ball.001")
						if ball then ball.Color = visualColor end
					end
				end
			end
		end,
	}, "VisualColor")
end

VisualTab:CreateToggle({
	Name = "Ball Trajectory",
	CurrentValue = trajectoryEnabled,
	Callback = function(Value)
		trajectoryEnabled = Value
		saveConfig()
		if Value then _createTrajColorPicker() else _destroyTrajColorPicker() end
	end,
}, "BallTrajectory")
if trajectoryEnabled then _createTrajColorPicker() end

-- ── Ball Hitbox ───────────────────────────────────────────────────────────────
local _hitboxSizeSlider = nil
local function _destroyHitboxSizeSlider()
	if _hitboxSizeSlider then pcall(function() _hitboxSizeSlider:Destroy() end); _hitboxSizeSlider = nil end
end
local function _createHitboxSizeSlider()
	if _hitboxSizeSlider then return end
	_hitboxSizeSlider = VisualTab:CreateSlider({
		Name = "Hitbox Size", Range = {0, 20}, Increment = 0.1,
		CurrentValue = CurrentHitboxScale,
		Callback = function(v)
			CurrentHitboxScale = v
			if ballHitboxEnabled then createOrUpdateHitboxes(v) end
		end,
	}, "HitboxSize")
end

VisualTab:CreateToggle({
	Name = "Ball Hitbox",
	CurrentValue = ballHitboxEnabled,
	Callback = function(Value)
		ballHitboxEnabled = Value
		saveConfig()
		if Value then
			createOrUpdateHitboxes(CurrentHitboxScale)
			_createHitboxSizeSlider()
		else
			clearHitboxes()
			_destroyHitboxSizeSlider()
		end
	end,
}, "BallHitbox")
if ballHitboxEnabled then createOrUpdateHitboxes(CurrentHitboxScale); _createHitboxSizeSlider() end

--// =========================
--// ADVANCED AUTO SPIKE AIM
--// =========================

-- Court layout constants (net sits at Z=0, black court = negative Z, white court = positive Z)
local ENEMY_COURT_HALF_WIDTH = 20   -- ±X bounds inside enemy court
local ENEMY_COURT_NEAR_Z     = 5    -- minimum Z distance from net on enemy side
local ENEMY_COURT_FAR_Z      = 48   -- far edge of enemy court

local lockedLookDir   = nil   -- normalised XZ direction to lock character facing
local jumpTriggered   = false
local wasAirborne     = false  -- previous-frame airborne state (for landing detection)
local lastWarnTime    = 0      -- rate-limit console warnings to once per 5 s

-- ── Smart Aim Areas ──────────────────────────────────────────────────────────
-- Area 1 shares its state with the red court overlay (overlayOffset* / overlaySize*).
-- Area 2 is an independent blue overlay.
-- Declared here (before getBestTarget) so Lua can close over them as upvalues.
-- UI callbacks in the Court Mapping section write to these same locals.
local aimArea1Active  = false   -- mirrors courtOverlayEnabled for spike filtering
local aimArea2Active  = false
local aimArea2OffsetX = 0.50
local aimArea2OffsetY = -4.50
local aimArea2OffsetZ = 25.50   -- WHITE court (positive Z side)
local aimArea2SizeX   = 50.50
local aimArea2SizeZ   = 48.50
local aimArea2Part    = nil

-- Area 1 overlay vars — MUST be declared before isInAimArea so Lua can close
-- over them as upvalues.  The Court Mapping UI sections below write to these
-- same locals; they do NOT redeclare them.
local overlayOffsetX = 0.50
local overlayOffsetY = -4.50
local overlayOffsetZ = -26.50  -- BLACK court (negative Z side)
local overlaySizeX   = 50.50
local overlaySizeZ   = 48.50

-- Court bounds — declared before getBestTarget so it can close over them.
local BLACK_COURT = { X = 0.50, Z = -26.50, SizeX = 50.50, SizeZ = 48.50 }
local WHITE_COURT = { X = 0.50, Z =  25.50, SizeX = 50.50, SizeZ = 48.50 }

-- ── Net geometry for avoidance checks ────────────────────────────────────────
-- The net runs along the X-axis at Z = 0.  NET_HALF_W is the half-width of the
-- playable opening; shots whose trajectory exits that window hit the post/wall.
-- NET_SAFE_DIST keeps targets at least this far from the net on the landing side.
local NET_Z         = 0
local NET_HALF_W    = 25.25   -- half of the ~50.5-stud court width
local NET_SAFE_DIST = 4       -- don't land within 4 studs of the net

-- Serve / back-corner zone: when the player is deep in their own court (more
-- than SERVE_DEPTH_THRESHOLD studs from the net), restrict targeting to the
-- back portion of the enemy court.  Mirrored for both sides.
local SERVE_DEPTH_THRESHOLD = 30    -- studs from net that count as "back corner"
local SERVE_ZONE_OFFSET_X   = -0.50
local SERVE_ZONE_SIZE_X     = 50.50
local SERVE_ZONE_OFFSET_Z   = 34.50 -- absolute Z centre on enemy side (mirrored below)
local SERVE_ZONE_SIZE_Z     = 30.50

-- Outside-court zones: player is fully behind their own baseline (serving from
-- the bench / outside area).  Two separate zones, one per side.
-- When inside either zone the target grid is restricted to a tighter landing
-- area on the enemy court (also mirrored automatically via sideSign).
local OUTSIDE_ZONE = {
    WHITE = { centerZ =  64.50, halfZ = 30.50 / 2 },  -- behind WHITE baseline
    BLACK = { centerZ = -67.00, halfZ = 33.00 / 2 },  -- behind BLACK baseline
}
-- Landing area enforced while in an outside zone (Z mirrored per sideSign)
local OUTSIDE_TARGET_OFFSET_X = 0.50
local OUTSIDE_TARGET_SIZE_X   = 50.50
local OUTSIDE_TARGET_OFFSET_Z = 33.00  -- |Z| centre on the enemy court
local OUTSIDE_TARGET_SIZE_Z   = 30.50

-- Find the volleyball wherever it is: workspace root OR parented to a player
-- character/tool (common during serve-toss animations).
local BALL_PREFIX = "CLIENT_BALL_"
local function _extractBallPart(model)
    return model:FindFirstChild("Sphere.001")
        or model:FindFirstChild("Cube.001")
        or model:FindFirstChildWhichIsA("BasePart")
end
local function findBall()
    -- Primary: workspace direct children (ball during normal play)
    for _, obj in ipairs(workspace:GetChildren()) do
        if obj:IsA("Model") and string.sub(obj.Name, 1, #BALL_PREFIX) == BALL_PREFIX then
            local part = _extractBallPart(obj)
            if part then return part end
        end
    end
    -- Fallback: ball may be reparented to a player's character during serve
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character then
            for _, obj in ipairs(p.Character:GetChildren()) do
                if obj:IsA("Model") and string.sub(obj.Name, 1, #BALL_PREFIX) == BALL_PREFIX then
                    local part = _extractBallPart(obj)
                    if part then return part end
                end
            end
            -- Also handle the ball as a direct BasePart child of a Tool
            for _, tool in ipairs(p.Character:GetChildren()) do
                if tool:IsA("Tool") then
                    local part = tool:FindFirstChildWhichIsA("BasePart")
                    if part then
                        local ln = part.Name:lower()
                        if string.find(ln, "ball") or string.find(ln, "sphere") or string.find(ln, "volley") then
                            return part
                        end
                    end
                end
            end
        end
    end
    return nil
end

-- (PlayerModule controls cache removed)

-- ── Cut-shot zone & character-aware tilt helpers ─────────────────────────────
-- The cut-shot zone is the band straddling both sides of the net where Sanju /
-- Kijo can add angular deviation to redirect the ball (±8–15°).
-- Coordinates came from mapping with the Zone 2 overlay tool.

-- Returns true when point (gx, gz) is inside at least one enabled aim area.
-- If NEITHER area is active the constraint is off and every cell is valid.
local function isInAimArea(gx, gz)
	if not aimArea1Active and not aimArea2Active then
		return true
	end
	if aimArea1Active then
		-- Area 1 bounds come from the shared overlay variables (defined later but
		-- already in scope by the time this function is CALLED, not defined).
		if math.abs(gx - overlayOffsetX) <= overlaySizeX / 2 and
		   math.abs(gz - overlayOffsetZ) <= overlaySizeZ / 2 then
			return true
		end
	end
	if aimArea2Active then
		if math.abs(gx - aimArea2OffsetX) <= aimArea2SizeX / 2 and
		   math.abs(gz - aimArea2OffsetZ) <= aimArea2SizeZ / 2 then
			return true
		end
	end
	return false
end

-- Get the HumanoidRootPart (or fallback torso) from a character
local function u32(playerCharacter)
	return playerCharacter:FindFirstChild('HumanoidRootPart')
		or playerCharacter:FindFirstChild('Torso')
		or playerCharacter:FindFirstChild('UpperTorso')
end

-- Get all players with position metadata
local function getAllPlayerPositions()
	local allPlayers = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			local root = p.Character:FindFirstChild("HumanoidRootPart")
			if root then
				table.insert(allPlayers, {
					player       = p,
					character    = p.Character,
					isLocalPlayer = (p == player),
					position     = root.Position,
					lookVector   = root.CFrame.LookVector,
					velocity     = root.AssemblyLinearVelocity,
					-- black court occupies negative Z, white occupies positive Z
					team         = (root.Position.Z < 0) and "BLACK" or "WHITE",
				})
			end
		end
	end
	return allPlayers
end

-- Return Character models of all opponents.
-- Prefers Roblox's built-in Team objects (reliable), falls back to
-- Z-position split only when the game doesn't use the Teams service.
local function getEnemies()
	local enemies = {}
	local myRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not myRoot then return enemies end

	local myRbxTeam = player.Team  -- nil when the game doesn't use Roblox Teams

	for _, p in ipairs(Players:GetPlayers()) do
		if p == player then continue end
		if not p.Character then continue end
		local root = p.Character:FindFirstChild("HumanoidRootPart")
		if not root then continue end

		local isEnemy
		if myRbxTeam and p.Team then
			-- Roblox Teams API — most reliable
			isEnemy = (p.Team ~= myRbxTeam)
		else
			-- Fallback: players on opposite side of the net (Z = 0) are enemies
			isEnemy = (myRoot.Position.Z < 0) ~= (root.Position.Z < 0)
		end

		if isEnemy then
			table.insert(enemies, p.Character)
		end
	end

	return enemies
end

--[[
	getBestTarget — strategy-aware targeting system.

	Strategies:
	  Biggest Gap    — find the cell furthest from ALL enemies (true open space).
	                   Smart-cut: if enemy cluster is on one side, bias the opposite.
	  Court Edges    — heavy weight on sidelines and corners; cross-court bias.
	  Target Landed  — project ball arc to landing spot, aim near it.
	                   Falls back to lastBallLandX/Z or Biggest Gap if no ball data.
	  Avoid Blockers — detect airborne enemies (FloorMaterial == Air) and penalise
	                   cells they cover; prefer grounded defenders' zones instead.
	  Weakest Spot   — maximise the travel distance the responsible defender must run.
	                   Also applies smart-cut: weight cells opposite the enemy centroid.
--]]
local function getBestTarget(myCharacter)
	local root = myCharacter and myCharacter:FindFirstChild("HumanoidRootPart")
	if not root then return nil, nil end

	local myPos   = root.Position
	local enemies = getEnemies()

	-- ── Collect enemy positions + airborne flag ───────────────────────────────
	local enemyPos      = {}   -- all enemy ground positions
	local enemyAirborne = {}   -- subset that are currently jumping / blocking
	for _, enemy in ipairs(enemies) do
		local er = enemy:FindFirstChild("HumanoidRootPart")
		local eh = enemy:FindFirstChild("Humanoid")
		if er then
			table.insert(enemyPos, er.Position)
			if eh and eh.FloorMaterial == Enum.Material.Air then
				table.insert(enemyAirborne, er.Position)
			end
		end
	end

	-- ── Determine enemy court bounds ──────────────────────────────────────────
	local mySide     = myPos.Z < 0 and "BLACK" or "WHITE"
	local enemyCourt = mySide == "BLACK" and WHITE_COURT or BLACK_COURT
	local sideSign   = mySide == "BLACK" and 1 or -1

	-- Hard grid limits come directly from the court area coordinates so targets
	-- can never be outside the playable court bounds regardless of strategy.
	local courtHalfX = enemyCourt.SizeX / 2
	local courtHalfZ = enemyCourt.SizeZ / 2
	local xMin = enemyCourt.X - courtHalfX
	local xMax = enemyCourt.X + courtHalfX
	local zMin = enemyCourt.Z - courtHalfZ
	local zMax = enemyCourt.Z + courtHalfZ
	-- Pull the net-side edge inward by NET_SAFE_DIST to avoid the net band
	if sideSign > 0 then
		zMin = math.max(zMin, NET_SAFE_DIST)
	else
		zMax = math.min(zMax, -NET_SAFE_DIST)
	end

	local ball = findBall()
	local ballDistFromNet   = ball and math.abs(ball.Position.Z) or 0
	local playerDistFromNet = math.abs(myPos.Z)

	-- Exclude the front row when player OR ball is deep — prevents back-row
	-- spikes from targeting just past the net.
	local DEEP_THRESHOLD  = 14
	local FRONT_ROW_EXCL  = 14
	if ballDistFromNet > DEEP_THRESHOLD or playerDistFromNet > DEEP_THRESHOLD then
		if sideSign > 0 then
			zMin = math.max(zMin, FRONT_ROW_EXCL)
		else
			zMax = math.min(zMax, -FRONT_ROW_EXCL)
		end
	end

	-- Close-to-net angle correction: when the player is within 12 studs of the
	-- net the facing direction to a shallow target is nearly horizontal — the ball
	-- hits the top of the net.  Force the minimum target depth to 22 studs so the
	-- character faces forward-downward at an angle that clears the net cleanly.
	local CLOSE_NET_THRESHOLD = 12
	local CLOSE_NET_MIN_DEPTH = 22
	if playerDistFromNet < CLOSE_NET_THRESHOLD then
		if sideSign > 0 then
			zMin = math.max(zMin, CLOSE_NET_MIN_DEPTH)
		else
			zMax = math.min(zMax, -CLOSE_NET_MIN_DEPTH)
		end
	end

	-- Serve / back-corner rule: when the player is deep in their own court,
	-- restrict the target grid to the back zone of the enemy court only.
	-- The zone centre Z is mirrored: +SERVE_ZONE_OFFSET_Z for WHITE court,
	-- -SERVE_ZONE_OFFSET_Z for BLACK court.
	if playerDistFromNet > SERVE_DEPTH_THRESHOLD then
		local szHalfX = SERVE_ZONE_SIZE_X / 2
		local szHalfZ = SERVE_ZONE_SIZE_Z / 2
		local szCenterZ = sideSign * SERVE_ZONE_OFFSET_Z
		xMin = math.max(xMin, SERVE_ZONE_OFFSET_X - szHalfX)
		xMax = math.min(xMax, SERVE_ZONE_OFFSET_X + szHalfX)
		zMin = math.max(zMin, szCenterZ - szHalfZ)
		zMax = math.min(zMax, szCenterZ + szHalfZ)
	end

	-- Outside-court rule: player is fully behind their baseline (serving from
	-- the bench).  Override bounds with the tighter landing area on enemy court.
	-- sideSign automatically mirrors the Z centre for both sides.
	local oz = OUTSIDE_ZONE
	local inOutside = math.abs(myPos.Z - oz.WHITE.centerZ) <= oz.WHITE.halfZ
	              or  math.abs(myPos.Z - oz.BLACK.centerZ) <= oz.BLACK.halfZ
	if inOutside then
		local tHalfX  = OUTSIDE_TARGET_SIZE_X / 2
		local tHalfZ  = OUTSIDE_TARGET_SIZE_Z / 2
		local tCenterZ = sideSign * OUTSIDE_TARGET_OFFSET_Z
		xMin = OUTSIDE_TARGET_OFFSET_X - tHalfX
		xMax = OUTSIDE_TARGET_OFFSET_X + tHalfX
		zMin = tCenterZ - tHalfZ
		zMax = tCenterZ + tHalfZ
	end

	local halfW = enemyCourt.SizeX / 2

	-- ── Enemy formation centroid (for smart-cut / Weakest Spot) ──────────────
	-- The centroid is the "mass centre" of the enemy team.  Aiming at the cell
	-- on the opposite side of the court from the centroid is the smart cut.
	local centroidX = enemyCourt.X
	local centroidZ = sideSign * (math.abs(enemyCourt.Z) * 0.5)
	if #enemyPos > 0 then
		local sx, sz = 0, 0
		for _, ep in ipairs(enemyPos) do sx = sx + ep.X; sz = sz + ep.Z end
		centroidX = sx / #enemyPos
		centroidZ = sz / #enemyPos
	end

	-- ── Ball landing projection (for Target Landed) ───────────────────────────
	local projLandX, projLandZ = nil, nil
	if selectedAimMode == "Target Landed" then
		local ball = findBall()
		if ball then
			local bpos = ball.Position
			local bvel = ball.AssemblyLinearVelocity
			-- Simple parabolic arc: solve Y = bpos.Y + bvel.Y*t - 0.5*g*t² = targetY
			local GRAVITY = 196   -- Roblox default studs/s²
			local targetY = -4.5  -- court floor Y (same as FLOOR_Y used by trajectory)
			local a = -0.5 * GRAVITY
			local b = bvel.Y
			local c = bpos.Y - targetY
			local disc = b*b - 4*a*c
			if disc >= 0 then
				local sqrtDisc = math.sqrt(disc)
				local t1 = (-b + sqrtDisc) / (2*a)
				local t2 = (-b - sqrtDisc) / (2*a)
				local t  = nil
				-- Pick the smallest positive time > 0.05 s
				if t1 > 0.05 and (not t2 or t2 <= 0.05 or t1 <= t2) then t = t1
				elseif t2 and t2 > 0.05 then t = t2 end
				if t then
					projLandX = bpos.X + bvel.X * t
					projLandZ = bpos.Z + bvel.Z * t
				end
			end
		end
	end

	-- ── Grid search ───────────────────────────────────────────────────────────
	local GRID_STEP  = 3
	local bestTarget = nil
	local bestScore  = -math.huge

	for gx = xMin, xMax, GRID_STEP do
		for gz = zMin, zMax, GRID_STEP do

			if not isInAimArea(gx, gz) then continue end

			-- ── Shared per-cell values (used by all strategies) ───────────────

			-- Distance from nearest enemy + sum of all enemy distances
			local closestDist   = 0
			local totalDist     = 0
			local dangerPenalty = 0
			for _, ep in ipairs(enemyPos) do
				local d = math.sqrt((gx - ep.X)^2 + (gz - ep.Z)^2)
				totalDist = totalDist + d
				if closestDist == 0 or d < closestDist then closestDist = d end
				-- Hard penalty: within 8 studs of ANY enemy = likely spiking at their feet
				if d < 8 then
					dangerPenalty = dangerPenalty + (8 - d) * 6
				end
			end

			-- Sideline bonus — rewards cross-court angles away from defenders
			local edgeDist  = halfW - math.abs(gx - enemyCourt.X)
			local sideBonus = math.max(0, halfW - edgeDist) * 2.0

			-- Smart-cut bonus — rewards the lateral side opposite the enemy centroid
			local cellSide = gx - enemyCourt.X
			local centSide = centroidX - enemyCourt.X
			local cutBonus = ((cellSide < 0) ~= (centSide < 0)) and 15 or 0

			-- ── Strategy-specific score ───────────────────────────────────────
			local score = 0

			-- ── BIGGEST GAP ───────────────────────────────────────────────────
			if selectedAimMode == "Biggest Gap" then
				score = closestDist * 2

			-- ── COURT EDGES ───────────────────────────────────────────────────
			elseif selectedAimMode == "Court Edges" then
				local distFromNet = math.abs(gz) - NET_SAFE_DIST
				local frontScore  = math.max(0, 10 - distFromNet) * 0.8
				score = sideBonus * 1.5 + frontScore + closestDist * 0.3

			-- ── TARGET LANDED ─────────────────────────────────────────────────
			elseif selectedAimMode == "Target Landed" then
				local refX = projLandX or lastBallLandX or enemyCourt.X
				local refZ = projLandZ or lastBallLandZ or (sideSign * 15)
				refX = math.max(xMin, math.min(xMax, refX))
				refZ = math.max(zMin, math.min(zMax, refZ))
				local distFromLand = math.sqrt((gx - refX)^2 + (gz - refZ)^2)
				score = -distFromLand * 0.6 + closestDist * 0.6

			-- ── AVOID BLOCKERS ────────────────────────────────────────────────
			elseif selectedAimMode == "Avoid Blockers" then
				local blockerPenalty = 0
				for _, bp in ipairs(enemyAirborne) do
					local d = math.sqrt((gx - bp.X)^2 + (gz - bp.Z)^2)
					blockerPenalty = blockerPenalty + math.max(0, 18 - d) * 2.5
				end
				score = closestDist - blockerPenalty

			-- ── WEAKEST SPOT ──────────────────────────────────────────────────
			elseif selectedAimMode == "Weakest Spot" then
				score = totalDist
			end

			-- Apply shared rules to every strategy
			score = score + sideBonus + cutBonus - dangerPenalty

			if score > bestScore then
				bestScore  = score
				bestTarget = Vector3.new(gx, 0, gz)
			end
		end
	end

	-- ── Fallback ──────────────────────────────────────────────────────────────
	if not bestTarget then
		local safeZ   = sideSign * NET_SAFE_DIST
		local cornerX = (myPos.X <= enemyCourt.X) and xMax or xMin
		bestTarget = Vector3.new(cornerX, 0, safeZ)
	end

	-- ── Normalised direction ──────────────────────────────────────────────────
	-- Use the ball's current XZ position as the spike origin so the facing
	-- direction is correct even when the ball is off-centre during a serve toss.
	-- Fall back to player position if no ball is found.
	local originX = ball and ball.Position.X or myPos.X
	local originZ = ball and ball.Position.Z or myPos.Z

	local dx  = bestTarget.X - originX
	local dz  = bestTarget.Z - originZ
	local mag = math.sqrt(dx * dx + dz * dz)
	if mag < 0.001 then return nil, nil end

	return Vector3.new(dx / mag, 0, dz / mag), bestTarget, #enemies
end

-- ── Ball landing tracker (used by "Target Landed" strategy) ─────────────────
-- Records the X/Z position the last time the ball was detected touching the
-- ground on the ENEMY court.  Checked at 10 Hz — not every frame.
task.spawn(function()
	local prevVelY = 0
	while task.wait(0.1) do
		local ball = findBall()
		if not ball then prevVelY = 0; continue end

		local velY = ball.AssemblyLinearVelocity.Y
		local posY = ball.Position.Y

		-- Detect ground contact: Y-velocity just flipped from negative to near-zero
		-- and ball is close to court level (below 6 studs)
		if prevVelY < -5 and velY >= -2 and posY < 6 then
			local myRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if myRoot then
				-- Only record if ball landed on the enemy side
				local mySide = myRoot.Position.Z < 0 and "BLACK" or "WHITE"
				local landedOnEnemySide = (mySide == "BLACK" and ball.Position.Z > 0)
				                      or (mySide == "WHITE" and ball.Position.Z < 0)
				if landedOnEnemySide then
					lastBallLandX = ball.Position.X
					lastBallLandZ = ball.Position.Z
				end
			end
		end

		prevVelY = velY
	end
end)

-- ── Auto Spike Aim — face-lock on jump ──────────────────────────────────────
-- On every jump: pick the best open spot, snap the character's CFrame to face
-- that direction, and hold it every frame while airborne (re-apply prevents
-- the engine from re-orienting during the jump arc). Clear on landing.
-- Uses root.CFrame directly — no input injection, no PlayerModule calls.
RunService.Heartbeat:Connect(function()
	if not smartAimEnabled then return end

	local ok, err = pcall(function()

	local character = player.Character
	if not character then return end

	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then return end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local airborne = humanoid.FloorMaterial == Enum.Material.Air

	-- ── On jump: compute best target, lock look direction ──────────────────
	-- Detect on BOTH Jumping (fires while still grounded) and the first frame
	-- of Freefall (reliable in-air state) so a missed Jumping tick is recovered.
	local state = humanoid:GetState()
	local isJumpState = (state == Enum.HumanoidStateType.Jumping)
	                 or (state == Enum.HumanoidStateType.Freefall and airborne)

	if isJumpState and not jumpTriggered then
		jumpTriggered = true

		local ok2, dir, target, nEnemies = pcall(getBestTarget, character)
		if not ok2 then
			dir = nil  -- keep the feature alive; error logged below if recent
		end

		if dir then
			lockedLookDir = dir
			Luna:Notification({
				Title   = "Spike Aim [" .. selectedAimMode .. "]",
				Content = string.format("→ (%.0f, %.0f)  enemies: %d", target.X, target.Z, nEnemies or 0),
			})
		else
			local fwd = root.Position.Z < 0 and 1 or -1
			lockedLookDir = Vector3.new(0, 0, fwd)
			Luna:Notification({ Title = "Spike Aim", Content = "No enemies — aiming forward" })
		end
	end

	-- ── While airborne: re-apply facing every frame ─────────────────────────
	if lockedLookDir and airborne then
		local lookPos = root.Position + Vector3.new(lockedLookDir.X, 0, lockedLookDir.Z)
		root.CFrame   = CFrame.new(root.Position, lookPos)
	end

	-- ── On landing: release the lock (ONLY on air→ground transition) ────────
	-- Do NOT clear every frame while grounded — that would wipe lockedLookDir
	-- on the same tick it was set (Jumping state fires before leaving the floor).
	if wasAirborne and not airborne then
		lockedLookDir = nil
		jumpTriggered = false
	end
	wasAirborne = airborne

	end) -- end pcall
	if not ok then
		local now = tick()
		if now - lastWarnTime >= 5 then
			lastWarnTime = now
			warn("[Vagabundo AutoSpike] " .. tostring(err))
		end
	end
end)

-- =====================================
-- AUTO CLAIM LOOP
-- =====================================

task.spawn(function()
	local ok, rf = pcall(getRequestRankedReward)
	if not ok or not rf then
		return
	end

	while task.wait(1.2) do
		local currentRank = playerRank
		for _, r in ipairs(REWARDS) do
			if enabled[r.key] then
				pcall(claimBestAvailableReward, rf, r.key, currentRank)
			end
		end
	end
end)

task.spawn(function()
	while task.wait(2) do
		local ok, newRank = pcall(getPlayerRank)
		if ok and newRank then
			playerRank = newRank
		end
	end
end)

-- =====================================
-- AUTO RECEIVE / AUTO SPIKE
-- =====================================
-- Both loops run at 50 ms intervals — NOT every frame — to avoid any
-- rate issues.  Each triggers at most once per ball approach (cooldown).

local RECEIVE_RANGE  = 22    -- studs: max distance for early receive
local SPIKE_RANGE    = 7     -- studs: trigger spike when in air and ball this close
local SPIKE_COOLDOWN = 0.5   -- seconds between spike attempts
local lastSpikeTime  = 0

-- Receive fires ONCE per approach: armed when ball crosses the net onto your
-- side, then disarmed immediately after triggering.  Resets when ball returns.
local receiveArmed       = false
local ballWasOnEnemySide = false  -- previous-tick ball-side state

-- Helper: single left-mouse-button click (LMB / RT / R2) — used for receive and spike
local function clickLMB()
    pcall(mouse1press)
    task.wait(0.05)
    pcall(mouse1release)
end

task.spawn(function()
    while task.wait(0.001) do
        if not autoReceiveEnabled and not autoSpikeEnabled then continue end

        local char = player.Character
        if not char then continue end
        local myRoot   = char:FindFirstChild("HumanoidRootPart")
        local humanoid = char:FindFirstChild("Humanoid")
        if not myRoot or not humanoid then continue end

        local ball = findBall()
        if not ball then continue end

        local dist     = (ball.Position - myRoot.Position).Magnitude
        local onGround = humanoid.FloorMaterial ~= Enum.Material.Air

        -- ── Ball-side tracking ────────────────────────────────────────────────
        -- "My side" = same sign of Z as my root.  Net is at Z = 0.
        local myZ   = myRoot.Position.Z
        local ballZ = ball.Position.Z
        local ballOnMySide    = (myZ < 0 and ballZ < 0) or (myZ >= 0 and ballZ >= 0)
        local ballOnEnemySide = not ballOnMySide

        -- Arm when ball crosses from enemy side onto my side (one arm per rally)
        if ballWasOnEnemySide and ballOnMySide then
            receiveArmed = true
        end

        -- Disarm without firing when ball returns to enemy side
        if ballOnEnemySide then
            receiveArmed = false
        end

        ballWasOnEnemySide = ballOnEnemySide

        -- ── Auto Receive: fire once as early as the ball is within reach ──────
        -- Requires: armed (came from enemy side) + grounded + ball descending or
        -- roughly level (not still climbing) + within generous receive range.
        if autoReceiveEnabled and receiveArmed and onGround then
            local velY         = ball.AssemblyLinearVelocity.Y
            local ballDescending = velY <= 3   -- not still shooting upward
            if ballDescending and dist <= RECEIVE_RANGE then
                receiveArmed = false  -- disarm — only one receive per approach
                -- Face the ball before receiving
                local flat = Vector3.new(ballZ ~= 0 and ball.Position.X or myRoot.Position.X,
                                         myRoot.Position.Y,
                                         ball.Position.Z)
                if (flat - myRoot.Position).Magnitude > 0.1 then
                    myRoot.CFrame = CFrame.new(myRoot.Position, flat)
                end
                clickLMB()
            end
        end

        -- ── Auto Spike: airborne, ball within spike range ─────────────────────
        if autoSpikeEnabled and not onGround and dist <= SPIKE_RANGE then
            local now = tick()
            if now - lastSpikeTime >= SPIKE_COOLDOWN then
                lastSpikeTime = now
                clickLMB()
            end
        end
    end
end)

-- =====================================
-- TRAJECTORY VISUALIZER + LOOK LINES
-- =====================================
-- All parts are parented to workspace.CurrentCamera which is CLIENT-ONLY —
-- they are never replicated to the server so there is zero packet overhead.

local _cam      = workspace.CurrentCamera
local TRAJ_DOTS = 30   -- more dots = smoother arc
local TRAJ_HZ   = 20  -- update rate (Hz)

-- The court floor sits at exactly Y = -4.5 in Volleyball Legends.
-- Using a hardcoded constant is more reliable than raycasting (which can hit
-- the wrong surface, return 0, or be slow to initialise).
local FLOOR_Y = -4.5

-- Pre-create dot pool (reuse each frame, never destroy/create mid-game)
local _trajDots = {}
for i = 1, TRAJ_DOTS do
	local p = Instance.new("Part")
	p.Name        = "VagaTrajDot"
	p.Anchored    = true
	p.CanCollide  = false
	p.CastShadow  = false
	p.Material    = Enum.Material.Neon
	p.Shape       = Enum.PartType.Ball
	p.Size        = Vector3.new(0.5, 0.5, 0.5)
	p.CFrame      = CFrame.new(0, -9999, 0)
	p.Parent      = _cam
	_trajDots[i]  = p
end

-- Landing circle: flat cylinder lying on the court floor
local _landCircle = Instance.new("Part")
_landCircle.Name        = "VagaLandCircle"
_landCircle.Anchored    = true
_landCircle.CanCollide  = false
_landCircle.CastShadow  = false
_landCircle.Material    = Enum.Material.Neon
_landCircle.Color       = Color3.fromRGB(0, 220, 60)
_landCircle.Shape       = Enum.PartType.Cylinder
_landCircle.Size        = Vector3.new(0.08, 5, 5)   -- thin disc, 5-stud diameter
_landCircle.CFrame      = CFrame.new(0, -9999, 0)
_landCircle.Parent      = _cam

-- Ball hitbox is now handled by createOrUpdateHitboxes (Ball.001 Parts inside
-- each CLIENT_BALL model).  No adornment needed here.

local function _hideTraj()
	for _, d in ipairs(_trajDots) do d.CFrame = CFrame.new(0, -9999, 0) end
	_landCircle.CFrame = CFrame.new(0, -9999, 0)
end

task.spawn(function()
	while task.wait(1 / TRAJ_HZ) do
		if not trajectoryEnabled then _hideTraj(); continue end

		local ball = findBall()
		if not ball then _hideTraj(); continue end

		local pos = ball.Position
		local vel = ball.AssemblyLinearVelocity
		local g   = workspace.Gravity  -- studs/s², positive value

		-- Solve for time until ball reaches FLOOR_Y.
		-- Physics: py(t) = pos.Y + vel.Y*t - 0.5*g*t²  →  set = FLOOR_Y
		-- Quadratic: 0.5*g·t² - vel.Y·t + (FLOOR_Y - pos.Y) = 0
		local qa   = 0.5 * g
		local qb   = -vel.Y
		local qc   = FLOOR_Y - pos.Y   -- negative: ball is above floor
		local disc = qb*qb - 4*qa*qc   -- always positive when ball is above floor
		local totalTime = 1.5           -- fallback
		if disc >= 0 then
			local sq = math.sqrt(disc)
			-- (-qb ± sq)/(2*qa) = (vel.Y ± sq)/g
			-- The larger root is the one we want (ball going up first, then down).
			local t1 = (-qb + sq) / (2*qa)
			local t2 = (-qb - sq) / (2*qa)
			local best = nil
			if t1 > 0.05 then best = t1 end
			if t2 > 0.05 and (not best or t2 < best) then best = t2 end
			if best then totalTime = math.min(best, 6) end
		end

		local landX = pos.X + vel.X * totalTime
		local landZ = pos.Z + vel.Z * totalTime
		local col   = visualColor

		-- Distribute dots evenly from the ball's CURRENT position (frac=0)
		-- to the LANDING position (frac=1).  All dots are the same size and
		-- fully opaque so the arc is clearly readable.
		for i, dot in ipairs(_trajDots) do
			local frac = (i - 1) / (TRAJ_DOTS - 1)  -- 0 → 1
			local t    = frac * totalTime
			local px   = pos.X + vel.X * t
			local py   = pos.Y + vel.Y * t - 0.5 * g * t * t
			local pz   = pos.Z + vel.Z * t

			if py < FLOOR_Y then
				-- This dot fell underground — hide it (shouldn't happen with correct totalTime)
				dot.Size  = Vector3.new(0.01, 0.01, 0.01)
				dot.CFrame = CFrame.new(0, -9999, 0)
			else
				-- Uniform dot: same colour, slight shrink near landing so
				-- the arc tapers naturally into the ground circle.
				local sz = 0.65 - frac * 0.35   -- 0.65 near ball → 0.30 near floor
				dot.Color        = col
				dot.Size         = Vector3.new(sz, sz, sz)
				dot.Transparency = 0.10          -- nearly opaque for all dots
				dot.CFrame       = CFrame.new(px, py, pz)
			end
		end

		-- Landing circle locked to FLOOR_Y, always at the arc's endpoint
		_landCircle.CFrame = CFrame.new(landX, FLOOR_Y, landZ)
		                   * CFrame.Angles(0, 0, math.pi / 2)
	end
end)

-- Player look lines are now Beam-based (see BEAM DIRECTIONAL LINES section above).

-- =====================================
-- COURT MAPPING TOOLS
-- =====================================

local courtOverlayEnabled = false
local netMappingEnabled = false

local courtOverlayPart = nil
local drawingMode = false
local startPoint = nil

-- (overlayOffset* / overlaySize* declared earlier — do not redeclare here)

-- SECOND FLOOR ZONE
local zone2Enabled = false
local zone2OffsetX = 0
local zone2OffsetY = -40
local zone2OffsetZ = 0
local zone2SizeX = 20
local zone2SizeZ = 20
local zone2Part = nil

local netMapPart = nil
local netMapOffsetX = 0.00
local netMapOffsetY = 0.00
local netMapOffsetZ = 0.00
local netMapWidth = 59.70
local netMapHeight = 4.90
local netMapThickness = 1.00

-- (BLACK_COURT / WHITE_COURT declared earlier — do not redeclare here)

-- ── Misc tab password gate ────────────────────────────────────────────────────
local miscUnlocked = false

MiscTab:CreateSection("Access")
MiscTab:CreateInput({
	Name        = "Admin Password",
	PlaceholderText = "Enter password...",
	RemoveTextAfterFocusLost = true,
	Callback    = function(Text)
		if Text == "Adm" and not miscUnlocked then
			miscUnlocked = true
			_createMiscContent()
		end
	end,
}, "AdminPass")

function _createMiscContent()
	MiscTab:CreateSection("Rank Selection")
	MiscTab:CreateDropdown({
		Name = "Select Your Rank",
		Options = {"Bronze 1", "Bronze 2", "Bronze 3", "Silver 1", "Silver 2", "Silver 3", "Gold 1", "Gold 2", "Gold 3", "Diamond 1", "Diamond 2", "Diamond 3", "Pro"},
		CurrentOption = {"Bronze 1"},
		MultipleOptions = false,
		Callback = function(Option)
			local rankMap = {
				["Bronze 1"] = 1, ["Bronze 2"] = 2, ["Bronze 3"] = 3,
				["Silver 1"] = 4, ["Silver 2"] = 5, ["Silver 3"] = 6,
				["Gold 1"]   = 7, ["Gold 2"]   = 8, ["Gold 3"]   = 9,
				["Diamond 1"] = 10, ["Diamond 2"] = 11, ["Diamond 3"] = 12,
				["Pro"] = 13,
			}
			selectedRank = rankMap[Option] or 1
		end,
	}, "SelectedRank")

	MiscTab:CreateSection("Court Mapping")

-- UI Controls
MiscTab:CreateToggle({
	Name = "Smart Aim Area",
	CurrentValue = false,
	Callback = function(Value)
		courtOverlayEnabled = Value
		aimArea1Active      = Value
		if Value then
			-- Snap once to the detected enemy court when first enabled.
			-- After this, arrow keys and sliders are free to override it.
			local myRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if myRoot then
				local court = myRoot.Position.Z < 0 and WHITE_COURT or BLACK_COURT
				overlayOffsetX = court.X
				overlayOffsetZ = court.Z
				overlaySizeX   = court.SizeX
				overlaySizeZ   = court.SizeZ
			end
		end
	end,
}, "SmartAimArea")

MiscTab:CreateToggle({
	Name = "Smart Aim Area 2",
	CurrentValue = false,
	Callback = function(Value)
		aimArea2Active = Value
	end,
}, "SmartAimArea2")

MiscTab:CreateSlider({
	Name = "Aim Area 2 Width",
	Range = {5, 500},
	Increment = 0.5,
	CurrentValue = 50.5,
	Callback = function(Value)
		aimArea2SizeX = Value
	end,
}, "AimArea2Width")

MiscTab:CreateSlider({
	Name = "Aim Area 2 Length",
	Range = {5, 500},
	Increment = 0.5,
	CurrentValue = 48.5,
	Callback = function(Value)
		aimArea2SizeZ = Value
	end,
}, "AimArea2Length")

MiscTab:CreateSlider({
	Name = "Aim Area 2 Floor Height",
	Range = {-200, 200},
	Increment = 0.1,
	CurrentValue = -4.5,
	Callback = function(Value)
		aimArea2OffsetY = Value
	end,
}, "AimArea2FloorY")

MiscTab:CreateSlider({
	Name = "Aim Area 2 Position X",
	Range = {-100, 100},
	Increment = 0.5,
	CurrentValue = 0.5,
	Callback = function(Value)
		aimArea2OffsetX = Value
	end,
}, "AimArea2PosX")

MiscTab:CreateSlider({
	Name = "Aim Area 2 Position Z",
	Range = {-100, 100},
	Increment = 0.5,
	CurrentValue = -26.5,
	Callback = function(Value)
		aimArea2OffsetZ = Value
	end,
}, "AimArea2PosZ")

MiscTab:CreateToggle({
	Name = "Net Mapping Tool",
	CurrentValue = false,
	Callback = function(Value)
		netMappingEnabled = Value
	end,
}, "NetMappingTool")

MiscTab:CreateSlider({
	Name = "Smart Aim Width",
	Range = {5, 500},
	Increment = 0.5,
	CurrentValue = 50.5,
	Callback = function(Value)
		overlaySizeX = Value
	end,
}, "SmartAimWidth")

MiscTab:CreateSlider({
	Name = "Smart Aim Length",
	Range = {5, 500},
	Increment = 0.5,
	CurrentValue = 48.5,
	Callback = function(Value)
		overlaySizeZ = Value
	end,
}, "SmartAimLength")

MiscTab:CreateSlider({
	Name = "Smart Aim Floor Height",
	Range = {-200, 200},
	Increment = 0.1,
	CurrentValue = -4.5,
	Callback = function(Value)
		overlayOffsetY = Value
	end,
}, "SmartAimFloorY")

MiscTab:CreateSlider({
	Name = "Smart Aim Position X",
	Range = {-100, 100},
	Increment = 0.5,
	CurrentValue = 0.5,
	Callback = function(Value)
		overlayOffsetX = Value
	end,
}, "SmartAimPosX")

MiscTab:CreateSlider({
	Name = "Smart Aim Position Z",
	Range = {-100, 100},
	Increment = 0.5,
	CurrentValue = 26.5,
	Callback = function(Value)
		overlayOffsetZ = Value
	end,
}, "SmartAimPosZ")

MiscTab:CreateSlider({
	Name = "Net Position X",
	Range = {-200, 200},
	Increment = 0.1,
	CurrentValue = 0,
	Callback = function(Value)
		netMapOffsetX = Value
	end,
}, "NetPosX")

MiscTab:CreateSlider({
	Name = "Net Position Y",
	Range = {-200, 200},
	Increment = 0.1,
	CurrentValue = 0,
	Callback = function(Value)
		netMapOffsetY = Value
	end,
}, "NetPosY")

MiscTab:CreateSlider({
	Name = "Net Position Z",
	Range = {-200, 200},
	Increment = 0.1,
	CurrentValue = 0,
	Callback = function(Value)
		netMapOffsetZ = Value
	end,
}, "NetPosZ")

MiscTab:CreateSlider({
	Name = "Net Width",
	Range = {0, 500},
	Increment = 0.1,
	CurrentValue = 59.70,
	Callback = function(Value)
		netMapWidth = Value
	end,
}, "NetWidth")

MiscTab:CreateSlider({
	Name = "Net Height",
	Range = {0, 10},
	Increment = 0.1,
	CurrentValue = 4.90,
	Callback = function(Value)
		netMapHeight = Value
	end,
}, "NetHeight")

MiscTab:CreateSlider({
	Name = "Net Thickness",
	Range = {0, 10},
	Increment = 0.1,
	CurrentValue = 1.00,
	Callback = function(Value)
		netMapThickness = Value
	end,
}, "NetThickness")

-- SECOND FLOOR ZONE UI
MiscTab:CreateToggle({
	Name = "Second Floor Zone",
	CurrentValue = false,
	Callback = function(Value)
		zone2Enabled = Value
	end,
}, "SecondFloorZone")

MiscTab:CreateSlider({
	Name = "Zone 2 Width",
	Range = {5, 500},
	Increment = 0.5,
	CurrentValue = 20,
	Callback = function(Value)
		zone2SizeX = Value
	end,
}, "Zone2Width")

MiscTab:CreateSlider({
	Name = "Zone 2 Length",
	Range = {5, 500},
	Increment = 0.5,
	CurrentValue = 20,
	Callback = function(Value)
		zone2SizeZ = Value
	end,
}, "Zone2Length")

MiscTab:CreateSlider({
	Name = "Zone 2 Floor Height",
	Range = {-200, 200},
	Increment = 0.1,
	CurrentValue = -40,
	Callback = function(Value)
		zone2OffsetY = Value
	end,
}, "Zone2FloorY")
end  -- _createMiscContent

local function updateCourtOverlay()
	if courtOverlayEnabled then
		if not courtOverlayPart then
			courtOverlayPart = Instance.new("Part")
			courtOverlayPart.Anchored = true
			courtOverlayPart.CanCollide = false
			courtOverlayPart.CanTouch = false
			courtOverlayPart.CanQuery = false
			courtOverlayPart.Transparency = 0.7
			courtOverlayPart.Color = Color3.new(1, 0, 0)
			courtOverlayPart.Parent = workspace
		end

		courtOverlayPart.Size = Vector3.new(overlaySizeX, 0.01, overlaySizeZ)
		courtOverlayPart.Position = Vector3.new(overlayOffsetX, overlayOffsetY + 0.005, overlayOffsetZ)
	else
		if courtOverlayPart then
			courtOverlayPart:Destroy()
			courtOverlayPart = nil
		end
	end
end

-- Mouse click drag draw system
UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	if not courtOverlayEnabled then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		local camera = workspace.CurrentCamera
		local ray = camera:ScreenPointToRay(input.Position.X, input.Position.Y)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = {player.Character, courtOverlayPart}

		local result = workspace:Raycast(ray.Origin, ray.Direction * 1000, params)

		if result and result.Position.Y < 2 then
			if not drawingMode then
				drawingMode = true
				startPoint = result.Position
			else
				drawingMode = false
				startPoint = nil
			end
		end
	end
end)

UserInputService.InputChanged:Connect(function(input, gpe)
	if gpe then return end
	if not drawingMode or not startPoint then return end

	if input.UserInputType == Enum.UserInputType.MouseMovement then
		local camera = workspace.CurrentCamera
		local ray = camera:ScreenPointToRay(input.Position.X, input.Position.Y)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = {player.Character, courtOverlayPart}

		local result = workspace:Raycast(ray.Origin, ray.Direction * 1000, params)

		if result then
			local endPoint = result.Position

			overlaySizeX = math.abs(endPoint.X - startPoint.X)
			overlaySizeZ = math.abs(endPoint.Z - startPoint.Z)
			overlayOffsetX = (startPoint.X + endPoint.X) / 2
			overlayOffsetZ = (startPoint.Z + endPoint.Z) / 2
		end
	end
end)

-- Arrow key movement controls
UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then return end

	local moveStep = 0.5

	if netMappingEnabled then
		if input.KeyCode == Enum.KeyCode.Up then
			netMapOffsetZ -= moveStep
		elseif input.KeyCode == Enum.KeyCode.Down then
			netMapOffsetZ += moveStep
		elseif input.KeyCode == Enum.KeyCode.Left then
			netMapOffsetX -= moveStep
		elseif input.KeyCode == Enum.KeyCode.Right then
			netMapOffsetX += moveStep
		elseif input.KeyCode == Enum.KeyCode.PageUp then
			netMapOffsetY += moveStep
		elseif input.KeyCode == Enum.KeyCode.PageDown then
			netMapOffsetY -= moveStep
		elseif input.KeyCode == Enum.KeyCode.Equals then
			netMapWidth += 1
			netMapHeight += 0.1
		elseif input.KeyCode == Enum.KeyCode.Minus then
			netMapWidth -= 1
			netMapHeight -= 0.1
		elseif input.KeyCode == Enum.KeyCode.RightShift then
			Luna:Notification({
				Title = "Net Coordinates",
				Content = string.format("Position: X: %.2f | Y: %.2f | Z: %.2f\nSize: Width: %.2f | Height: %.2f | Thickness: %.2f", netMapOffsetX, netMapOffsetY, netMapOffsetZ, netMapWidth, netMapHeight, netMapThickness),
			})
			local coordString = string.format("netMapOffsetX = %.2f\nnetMapOffsetY = %.2f\nnetMapOffsetZ = %.2f\nnetMapWidth = %.2f\nnetMapHeight = %.2f\nnetMapThickness = %.2f", netMapOffsetX, netMapOffsetY, netMapOffsetZ, netMapWidth, netMapHeight, netMapThickness)
			setclipboard(coordString)
		end
	elseif courtOverlayEnabled then
		if input.KeyCode == Enum.KeyCode.Up then
			overlayOffsetZ -= moveStep
		elseif input.KeyCode == Enum.KeyCode.Down then
			overlayOffsetZ += moveStep
		elseif input.KeyCode == Enum.KeyCode.Left then
			overlayOffsetX -= moveStep
		elseif input.KeyCode == Enum.KeyCode.Right then
			overlayOffsetX += moveStep
		elseif input.KeyCode == Enum.KeyCode.PageUp then
			overlayOffsetY += moveStep
		elseif input.KeyCode == Enum.KeyCode.PageDown then
			overlayOffsetY -= moveStep
		elseif input.KeyCode == Enum.KeyCode.Equals then
			overlaySizeX += 1
			overlaySizeZ += 1
		elseif input.KeyCode == Enum.KeyCode.Minus then
			overlaySizeX -= 1
			overlaySizeZ -= 1
		elseif input.KeyCode == Enum.KeyCode.RightShift then
			-- Always dump BOTH areas so you can paste the full layout here
			local coordString = string.format(
				"-- Area 1\noverlayOffsetX = %.2f\noverlayOffsetY = %.2f\noverlayOffsetZ = %.2f\noverlaySizeX = %.2f\noverlaySizeZ = %.2f\n\n-- Area 2\naimArea2OffsetX = %.2f\naimArea2OffsetY = %.2f\naimArea2OffsetZ = %.2f\naimArea2SizeX = %.2f\naimArea2SizeZ = %.2f",
				overlayOffsetX, overlayOffsetY, overlayOffsetZ, overlaySizeX, overlaySizeZ,
				aimArea2OffsetX, aimArea2OffsetY, aimArea2OffsetZ, aimArea2SizeX, aimArea2SizeZ
			)
			Luna:Notification({
				Title = "Smart Aim Areas Copied",
				Content = string.format(
					"Area 1 → (%.1f, %.1f) %dx%d\nArea 2 → (%.1f, %.1f) %dx%d",
					overlayOffsetX, overlayOffsetZ, overlaySizeX, overlaySizeZ,
					aimArea2OffsetX, aimArea2OffsetZ, aimArea2SizeX, aimArea2SizeZ
				),
			})
			setclipboard(coordString)
		end
	elseif aimArea2Active then
		if input.KeyCode == Enum.KeyCode.Up then
			aimArea2OffsetZ -= moveStep
		elseif input.KeyCode == Enum.KeyCode.Down then
			aimArea2OffsetZ += moveStep
		elseif input.KeyCode == Enum.KeyCode.Left then
			aimArea2OffsetX -= moveStep
		elseif input.KeyCode == Enum.KeyCode.Right then
			aimArea2OffsetX += moveStep
		elseif input.KeyCode == Enum.KeyCode.PageUp then
			aimArea2OffsetY += moveStep
		elseif input.KeyCode == Enum.KeyCode.PageDown then
			aimArea2OffsetY -= moveStep
		elseif input.KeyCode == Enum.KeyCode.Equals then
			aimArea2SizeX += 1
			aimArea2SizeZ += 1
		elseif input.KeyCode == Enum.KeyCode.Minus then
			aimArea2SizeX -= 1
			aimArea2SizeZ -= 1
		elseif input.KeyCode == Enum.KeyCode.RightShift then
			local coordString = string.format(
				"-- Area 1\noverlayOffsetX = %.2f\noverlayOffsetY = %.2f\noverlayOffsetZ = %.2f\noverlaySizeX = %.2f\noverlaySizeZ = %.2f\n\n-- Area 2\naimArea2OffsetX = %.2f\naimArea2OffsetY = %.2f\naimArea2OffsetZ = %.2f\naimArea2SizeX = %.2f\naimArea2SizeZ = %.2f",
				overlayOffsetX, overlayOffsetY, overlayOffsetZ, overlaySizeX, overlaySizeZ,
				aimArea2OffsetX, aimArea2OffsetY, aimArea2OffsetZ, aimArea2SizeX, aimArea2SizeZ
			)
			Luna:Notification({
				Title = "Smart Aim Areas Copied",
				Content = string.format(
					"Area 1 → (%.1f, %.1f) %dx%d\nArea 2 → (%.1f, %.1f) %dx%d",
					overlayOffsetX, overlayOffsetZ, overlaySizeX, overlaySizeZ,
					aimArea2OffsetX, aimArea2OffsetZ, aimArea2SizeX, aimArea2SizeZ
				),
			})
			setclipboard(coordString)
		end
	elseif zone2Enabled then
		if input.KeyCode == Enum.KeyCode.Up then
			zone2OffsetZ -= moveStep
		elseif input.KeyCode == Enum.KeyCode.Down then
			zone2OffsetZ += moveStep
		elseif input.KeyCode == Enum.KeyCode.Left then
			zone2OffsetX -= moveStep
		elseif input.KeyCode == Enum.KeyCode.Right then
			zone2OffsetX += moveStep
		elseif input.KeyCode == Enum.KeyCode.Equals then
			zone2SizeX += 1
			zone2SizeZ += 1
		elseif input.KeyCode == Enum.KeyCode.Minus then
			zone2SizeX -= 1
			zone2SizeZ -= 1
		elseif input.KeyCode == Enum.KeyCode.PageUp then
			zone2OffsetY += moveStep
		elseif input.KeyCode == Enum.KeyCode.PageDown then
			zone2OffsetY -= moveStep
		elseif input.KeyCode == Enum.KeyCode.RightShift then
			Luna:Notification({
				Title = "Second Floor Zone Coordinates",
				Content = string.format("Position: X: %.2f | Y: %.2f | Z: %.2f\nSize: Width: %.2f | Length: %.2f", zone2OffsetX, zone2OffsetY, zone2OffsetZ, zone2SizeX, zone2SizeZ),
			})
			local coordString = string.format("zone2OffsetX = %.2f\nzone2OffsetY = %.2f\nzone2OffsetZ = %.2f\nzone2SizeX = %.2f\nzone2SizeZ = %.2f", zone2OffsetX, zone2OffsetY, zone2OffsetZ, zone2SizeX, zone2SizeZ)
			setclipboard(coordString)
		end
	end
end)

RunService.Heartbeat:Connect(function()
	updateCourtOverlay()

	-- SMART AIM AREA 2 (blue overlay, movable with arrow keys when active)
	if aimArea2Active then
		if not aimArea2Part then
			aimArea2Part = Instance.new("Part")
			aimArea2Part.Anchored   = true
			aimArea2Part.CanCollide = false
			aimArea2Part.CanTouch   = false
			aimArea2Part.CanQuery   = false
			aimArea2Part.Transparency = 0.7
			aimArea2Part.Color      = Color3.fromRGB(0, 120, 255)
			aimArea2Part.Parent     = workspace
		end
		aimArea2Part.Size     = Vector3.new(aimArea2SizeX, 0.01, aimArea2SizeZ)
		aimArea2Part.Position = Vector3.new(aimArea2OffsetX, aimArea2OffsetY + 0.005, aimArea2OffsetZ)
	else
		if aimArea2Part then
			aimArea2Part:Destroy()
			aimArea2Part = nil
		end
	end

	-- SECOND FLOOR ZONE
	if zone2Enabled then
		if not zone2Part then
			zone2Part = Instance.new("Part")
			zone2Part.Anchored = true
			zone2Part.CanCollide = false
			zone2Part.CanTouch = false
			zone2Part.CanQuery = false
			zone2Part.Transparency = 0.7
			zone2Part.Color = Color3.new(0, 1, 0)
			zone2Part.Parent = workspace
		end

		zone2Part.Size = Vector3.new(zone2SizeX, 0.01, zone2SizeZ)
		zone2Part.Position = Vector3.new(zone2OffsetX, zone2OffsetY + 0.005, zone2OffsetZ)
	else
		if zone2Part then
			zone2Part:Destroy()
			zone2Part = nil
		end
	end

	-- Net Mapping Tool
	if netMappingEnabled then
		if not netMapPart then
			netMapPart = Instance.new("Part")
			netMapPart.Anchored = true
			netMapPart.CanCollide = false
			netMapPart.CanTouch = false
			netMapPart.CanQuery = false
			netMapPart.Transparency = 0.5
			netMapPart.Color = Color3.new(1, 0.4, 0)
			netMapPart.Parent = workspace
		end

		netMapPart.Size = Vector3.new(netMapWidth, netMapHeight, netMapThickness)
		netMapPart.Position = Vector3.new(netMapOffsetX, netMapOffsetY + (netMapHeight / 2), netMapOffsetZ)
	else
		if netMapPart then
			netMapPart:Destroy()
			netMapPart = nil
		end
	end

end)

-- =====================================
-- CHARACTER TAB
-- =====================================
local CharTab = Window:CreateTab({Name = "Character", Icon = "user-round", ImageSource = "Lucide", ShowTitle = true})
CharTab:CreateSection("Movement")

CharTab:CreateToggle({
	Name = "Directional Jump",
	CurrentValue = directionalJumpEnabled,
	Callback = function(val)
		directionalJumpEnabled = val
		saveConfig()
		if not val and charHumanoid then charHumanoid.AutoRotate = true end
	end,
}, "DirectionalJump")

CharTab:CreateParagraph({
	Title = "How to Use",
	Text = "Disable shift-lock. Character auto-steers toward camera direction on jump.",
})

local _airSpeedSlider = nil
local function _destroyAirSpeedSlider()
	if _airSpeedSlider then pcall(function() _airSpeedSlider:Destroy() end); _airSpeedSlider = nil end
end
local function _createAirSpeedSlider()
	if _airSpeedSlider then return end
	_airSpeedSlider = CharTab:CreateSlider({
		Name = "Air Move Speed", Range = {10, 150}, Increment = 5,
		CurrentValue = AirMoveSpeed,
		Callback = function(v) AirMoveSpeed = v; saveConfig() end,
	}, "AirSpeed")
end

CharTab:CreateToggle({
	Name = "Air Movement",
	CurrentValue = moveInAirEnabled,
	Callback = function(val)
		moveInAirEnabled = val
		saveConfig()
		if val then _createAirSpeedSlider() else _destroyAirSpeedSlider() end
	end,
}, "AirMovement")
if moveInAirEnabled then _createAirSpeedSlider() end

CharTab:CreateSection("ESP")

CharTab:CreateToggle({
	Name = "Character ESP (Clone)",
	CurrentValue = CloneESP.enabled,
	Callback = function(val)
		CloneESP.enabled = val
		if val then
			if player.Character then CloneESP:CreateESP(player.Character) end
		else
			CloneESP:Cleanup()
		end
	end,
}, "CharESP")

CharTab:CreateColorPicker({
	Name = "Clone ESP Color",
	Color = CloneESP.color,
	Callback = function(color)
		CloneESP.color = color
		for _, clone in pairs(CloneESP.clones) do
			if clone and clone:IsA("BasePart") then clone.Color = color end
		end
	end,
}, "CloneESPColor")

-- =====================================
-- HELPERS TAB
-- =====================================
local HelpersTab = Window:CreateTab({Name = "Helpers", Icon = "eye", ImageSource = "Lucide", ShowTitle = true})
HelpersTab:CreateSection("Directional Lines")

local _lineLenSlider = nil
local function _destroyLineLenSlider()
	if _lineLenSlider then pcall(function() _lineLenSlider:Destroy() end); _lineLenSlider = nil end
end
local function _createLineLenSlider()
	if _lineLenSlider then return end
	_lineLenSlider = HelpersTab:CreateSlider({
		Name = "Line Distance", Range = {10, 100}, Increment = 10,
		CurrentValue = lineDistance,
		Callback = function(v) lineDistance = v; saveConfig() end,
	}, "LineLen")
end

HelpersTab:CreateToggle({
	Name = "Enemy Look Lines",
	CurrentValue = linesEnabled,
	Callback = function(val)
		linesEnabled = val
		saveConfig()
		if val then _createLineLenSlider()
		else
			_destroyLineLenSlider()
			for _, d in pairs(beams) do if d and d.beam then d.beam.Enabled = false end end
		end
	end,
}, "LookLines")
if linesEnabled then _createLineLenSlider() end

HelpersTab:CreateSection("Auto Tilt")

HelpersTab:CreateToggle({
	Name = "Auto Tilt (recommended for setters)",
	CurrentValue = autoTiltEnabled,
	Callback = function(val)
		autoTiltEnabled = val
		saveConfig()
	end,
}, "AutoTilt")

HelpersTab:CreateInput({
	Name = "Tilt Toggle Key (PC)",
	PlaceholderText = "Ex: Z",
	RemoveTextAfterFocusLost = true,
	Callback = function(text)
		text = text:upper()
		local key = Enum.KeyCode[text]
		if key then
			hotkeyEnum = key
		end
	end,
}, "TiltKey")

HelpersTab:CreateParagraph({
	Title = "How Auto Tilt works",
	Text = "While in Freefall the character leans toward where your camera looks, without needing joystick/W input.",
})

HelpersTab:CreateSection("Enemy ESP")

HelpersTab:CreateToggle({
	Name = "Enemy Jump ESP",
	CurrentValue = enemyJumpESPEnabled,
	Callback = function(val)
		enemyJumpESPEnabled = val
		if not val then
			for p in pairs(jumpESPStorage) do _removeJumpESP(p) end
		end
	end,
}, "EnemyJumpESP")

-- =====================================
-- OTHERS TAB
-- =====================================
local OthersTab = Window:CreateTab({Name = "Others", Icon = "alert-triangle", ImageSource = "Lucide", ShowTitle = true})
OthersTab:CreateSection("Utility")

OthersTab:CreateButton({
	Name = "Rejoin Server",
	Callback = function()
		pcall(function() TeleportService:Teleport(game.PlaceId, player) end)
	end,
})

OthersTab:CreateButton({
	Name = "Panic Mode (Disable All)",
	Callback = function()
		-- Spike / receive
		smartAimEnabled    = false
		autoReceiveEnabled = false
		autoSpikeEnabled   = false
		-- Hitbox
		ballHitboxEnabled  = false
		clearHitboxes()
		-- Lines
		linesEnabled = false
		for _, d in pairs(beams) do if d and d.beam then d.beam.Enabled = false end end
		-- Character
		directionalJumpEnabled = false
		moveInAirEnabled       = false
		if charHumanoid then charHumanoid.AutoRotate = true end
		-- ESP
		CloneESP.enabled = false
		CloneESP:Cleanup()
		enemyJumpESPEnabled = false
		for p in pairs(jumpESPStorage) do _removeJumpESP(p) end
		-- Tilt
		autoTiltEnabled = false
		-- Trajectory
		trajectoryEnabled = false
		Luna:Notification({ Title = "Panic Mode", Content = "All features disabled." })
	end,
})

-- =====================================
-- 🎯 HITBOXES TAB
-- =====================================
local HitboxTab = Window:CreateTab({Name = "🎯 Hitboxes", Icon = "target", ImageSource = "Lucide", ShowTitle = true})

HitboxTab:CreateToggle({
    Name = "⚡ Enable Hitboxes",
    CurrentValue = Hitbox.Enabled,
    Callback = function(state)
        Hitbox.Enabled = state
        if state then
            Hitbox:StartAutoUpdate()
            Hitbox:UpdateAll()
            Luna:Notification({ Title = "✅ Hitboxes ON", Content = "Auto-updating every " .. Hitbox.Interval .. "s" })
        else
            Hitbox:Cleanup()
            Luna:Notification({ Title = "⛔ Hitboxes OFF", Content = "All hitboxes removed" })
        end
    end
}, "HitboxEnabled")

HitboxTab:CreateSlider({
    Name = "🔄 Update Interval",
    Range = {1, 30},
    Increment = 1,
    CurrentValue = Hitbox.Interval,
    Callback = function(value)
        Hitbox.Interval = value
        if Hitbox.Enabled then Hitbox:StartAutoUpdate() end
    end
}, "DynHitboxInterval")

HitboxTab:CreateSlider({
    Name = "📏 Min Size",
    Range = {0.5, 5},
    Increment = 0.1,
    CurrentValue = Hitbox.MinSize,
    Callback = function(value)
        Hitbox.MinSize = value
        if Hitbox.Enabled then Hitbox:UpdateAll() end
    end
}, "DynHitboxMinSize")

HitboxTab:CreateSlider({
    Name = "📐 Max Size",
    Range = {1, 15},
    Increment = 0.1,
    CurrentValue = Hitbox.MaxSize,
    Callback = function(value)
        Hitbox.MaxSize = value
        if Hitbox.Enabled then Hitbox:UpdateAll() end
    end
}, "DynHitboxMaxSize")

HitboxTab:CreateColorPicker({
    Name = "🎨 Color",
    Color = Hitbox.Color,
    Callback = function(color)
        Hitbox.Color = color
        if Hitbox.Enabled then Hitbox:UpdateAll() end
    end
}, "DynHitboxColor")

HitboxTab:CreateSlider({
    Name = "🔍 Transparency",
    Range = {0, 1},
    Increment = 0.05,
    CurrentValue = Hitbox.Transparency,
    Callback = function(value)
        Hitbox.Transparency = value
        if Hitbox.Enabled then Hitbox:UpdateAll() end
    end
}, "DynHitboxTransp")

HitboxTab:CreateButton({
    Name = "🔄 Update Now",
    Callback = function()
        if Hitbox.Enabled then
            Hitbox:UpdateAll()
            Luna:Notification({ Title = "⚡ Updated", Content = "New sizes applied" })
        end
    end
})

HitboxTab:CreateButton({
    Name = "🎲 Random Color",
    Callback = function()
        Hitbox.Color = Color3.fromRGB(
            math.random(50, 255),
            math.random(50, 255),
            math.random(50, 255)
        )
        if Hitbox.Enabled then Hitbox:UpdateAll() end
        Luna:Notification({
            Title = "🌈 Random Color",
            Content = string.format("RGB(%d, %d, %d)",
                math.floor(Hitbox.Color.R * 255),
                math.floor(Hitbox.Color.G * 255),
                math.floor(Hitbox.Color.B * 255))
        })
    end
})

-- =====================================
-- ⚙️ UTILITIES TAB
-- =====================================
local UtilTab = Window:CreateTab({Name = "⚙️ Utilities", Icon = "settings", ImageSource = "Lucide", ShowTitle = true})

UtilTab:CreateButton({
    Name = "🧹 Clear Hitboxes",
    Callback = function()
        Hitbox:Cleanup()
        Luna:Notification({ Title = "🧹 Cleared", Content = "All hitboxes removed" })
    end
})

UtilTab:CreateButton({
    Name = "🔄 Rejoin Server",
    Callback = function()
        TeleportService:Teleport(game.PlaceId, player)
    end
})

UtilTab:CreateButton({
    Name = "🔴 Unload Script",
    Callback = function()
        Luna:Notification({ Title = "🔴 Unloading...", Content = "Removing everything" })
        task.wait(1)
        Hitbox:Unload()
    end
})

UtilTab:CreateParagraph({
    Title = "⚠️ Warning",
    Text = "Unload will remove ALL hitboxes and close UI. Use 'Clear Hitboxes' to just remove visuals."
})

Luna:Notification({
	Title = "Vagabundo Loaded",
	Content = "Toggle UI from the button.",
})

Luna:LoadAutoloadConfig()

--[[
                        IMPORTED PLAYER & BALL TRACKING
-- STEALED FROM HAiKYUU SCRIPT:

-- BALL TRACKING SYSTEM:
local ballPrefix = "CLIENT_BALL_"
local function getBall()
    for _, object in pairs(workspace:GetChildren()) do
        if object:IsA("Model") and object.Name:match(ballPrefix) then
            return object:FindFirstChild("Sphere.001") or object:FindFirstChild("Cube.001")
        end
    end
    return nil
end

-- PLAYER TRACKING + LOOK DIRECTION:
local function getPlayerLookDirection(targetPlayer)
    if not targetPlayer.Character then return nil end
    local root = targetPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not root then return nil end
    return root.CFrame.LookVector
end

local function getAllPlayerPositions()
    local positions = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
            table.insert(positions, {
                player = p,
                position = p.Character.HumanoidRootPart.Position,
                lookVector = getPlayerLookDirection(p),
                velocity = p.Character.HumanoidRootPart.AssemblyLinearVelocity
            })
        end
    end
    return positions
end

-- AUTO BUMP IMPLEMENTATION:
local autoBumpEnabled = false
local function autoBumpLogic()
    while task.wait(0.03) do
        if not autoBumpEnabled then continue end
        local ball = getBall()
        if not ball then continue end

        local myRoot = u32(player.Character)
        if not myRoot then continue end

        local distance = (ball.Position - myRoot.Position).Magnitude

        if distance < 12 and ball.Position.Y > myRoot.Position.Y + 1 then
            -- AUTOMATIC TILT DIRECTION CALCULATION
            local lookTarget = ball.Position
            myRoot.CFrame = CFrame.new(myRoot.Position, Vector3.new(lookTarget.X, myRoot.Position.Y, lookTarget.Z))

            -- PRESS BUMP ACTION
            game:GetService("VirtualInputManager"):SendMouseButtonEvent(0, 0, 0, true, game, 1)
            task.wait(0.02)
            game:GetService("VirtualInputManager"):SendMouseButtonEvent(0, 0, 0, false, game, 1)
        end
    end
end

-- TILT DIRECTION DATA SYSTEM:
local currentTiltDirection = Vector3.new(0,0,0)
RunService.Heartbeat:Connect(function()
    if player.Character then
        local root = u32(player.Character)
        if root then
            currentTiltDirection = root.CFrame.LookVector
            -- real time tilt vector is stored here: currentTiltDirection.X, currentTiltDirection.Z
        end
    end
end)

-- Enable with: autoBumpEnabled = true
]]
