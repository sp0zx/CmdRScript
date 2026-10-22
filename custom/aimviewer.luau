--[[
	Aimviewer - Moderator tool
	Draws a tracer from each player's held gun to their (replicated) aim point,
	and analyzes that aim point over time to flag suspicious "aimbot-like" behavior:
	locking onto heads/torsos, unnaturally sharp snaps, and unnaturally perfect
	tracking of a moving target. The tracer color ramps green -> red with the
	computed probability so you can spot suspicious aim at a glance.

	NOTE ON LATENCY: the aim point we read (BodyEffects.MousePos.Value) is a value
	replicated from the aiming player's client, so it always lags behind their real
	input by roughly their ping + ours. We can't eliminate that, so every metric
	here is computed over a rolling time window (HISTORY_DURATION) rather than
	single frames, which smooths out network jitter at the cost of a little
	detection latency. Treat the probability score as a strong hint, not proof.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local MainModule = require(ReplicatedStorage:WaitForChild("MainModule"))

--// Config

local SAMPLE_INTERVAL = 1 / 20        -- how often (seconds) we sample each player's aim point
local HISTORY_DURATION = 2.5          -- seconds of aim history kept per player

local SEARCH_RADIUS = 20              -- studs; max distance from aim point to consider a body part a candidate target
local LOCK_RADIUS = 3.5               -- studs; aim within this of a body part counts as "on target"
local TIGHT_LOCK_RADIUS = 1.25        -- studs; very precise, used for snap detection
local SNAP_MIN_JUMP = 6               -- studs; minimum aim-point jump to count a sudden lock as a "snap"
local EXACT_LOCK_EPSILON = 0.15       -- studs; aim point basically IS the part's position (a hard-set aim value) - no human mouse is this precise

local TRACKED_PARTS = {"Head", "UpperTorso", "HumanoidRootPart"}
local PART_BIAS = {Head = 1.15, UpperTorso = 1.0, HumanoidRootPart = 0.9} -- tie-break preference, headlock reads as more suspicious

local MIN_SAMPLES_FOR_SCORE = 12      -- don't report a score until we have enough data

--// State

local enabled = false
local trackedData = {}    -- [player] = { history = {}, metrics = {...} }
local tracers = {}        -- [player] = Part
local highlights = {}     -- [player] = Part (marks the exact body part they're locked onto)
local heartbeatConn = nil

--// Helpers

local function getGunHandle(character)
	local ok, held = pcall(MainModule.GunHold, character)
	if not ok or not held or not held[1] or not held[1].Handle then
		return nil
	end
	return held[1].Handle
end

local function getAimPoint(character)
	local bodyEffects = character:FindFirstChild("BodyEffects")
	local mousePos = bodyEffects and bodyEffects:FindFirstChild("MousePos")
	if not mousePos then return nil end
	return mousePos.Value
end

-- Finds the closest tracked body part (Head/UpperTorso/HumanoidRootPart) belonging to
-- any player other than `excludePlayer`, within SEARCH_RADIUS of `aimPos`.
local function findNearestTarget(aimPos, excludePlayer)
	local bestPlayer, bestPart, bestPos, bestDist = nil, nil, nil, math.huge

	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= excludePlayer and other.Character then
			for _, partName in ipairs(TRACKED_PARTS) do
				local part = other.Character:FindFirstChild(partName)
				if part then
					local dist = (part.Position - aimPos).Magnitude
					local biased = dist / (PART_BIAS[partName] or 1)
					if dist <= SEARCH_RADIUS and biased < bestDist then
						bestDist = biased
						bestPlayer, bestPart, bestPos = other, partName, part.Position
					end
				end
			end
		end
	end

	if not bestPlayer then return nil end
	local realDist = (bestPos - aimPos).Magnitude
	return bestPlayer, bestPart, bestPos, realDist
end

local function getData(player)
	local data = trackedData[player]
	if not data then
		data = {history = {}, metrics = {probability = 0, isLocked = false}}
		trackedData[player] = data
	end
	return data
end

local function pushSample(player, sample)
	local data = getData(player)
	local history = data.history
	history[#history + 1] = sample

	local cutoff = sample.t - HISTORY_DURATION
	local removeCount = 0
	for i = 1, #history do
		if history[i].t >= cutoff then break end
		removeCount = i
	end
	if removeCount > 0 then
		for _ = 1, removeCount do table.remove(history, 1) end
	end
end

-- Recomputes suspicion metrics for a player from their sample history.
local function analyze(player)
	local data = getData(player)
	local history = data.history
	local n = #history
	if n == 0 then
		data.metrics = {probability = 0, isLocked = false, target = nil, part = nil, samples = 0}
		return data.metrics
	end

	local lockedCount, headLockedCount, snapCount, exactLockCount = 0, 0, 0, 0
	local trackingSum, trackingSamples = 0, 0
	local jitterSum, jitterSamples = 0, 0
	local lockStreak, lockStreakStart = 0, nil

	local last = history[n]
	local isLocked = last.dist ~= nil and last.dist <= LOCK_RADIUS
	local isExactLock = last.dist ~= nil and last.dist <= EXACT_LOCK_EPSILON

	-- current unbroken lock streak (walk backwards while same target+part and locked)
	if isLocked then
		for i = n, 1, -1 do
			local s = history[i]
			if s.target == last.target and s.part == last.part and s.dist and s.dist <= LOCK_RADIUS then
				lockStreak += 1
				lockStreakStart = s.t
			else
				break
			end
		end
	end

	for i = 1, n do
		local s = history[i]
		local locked = s.dist ~= nil and s.dist <= LOCK_RADIUS
		if locked then
			lockedCount += 1
			if s.part == "Head" then headLockedCount += 1 end
			if s.dist <= EXACT_LOCK_EPSILON then exactLockCount += 1 end
		end

		if i > 1 then
			local prev = history[i - 1]
			local jump = (s.pos - prev.pos).Magnitude
			local wasLocked = prev.dist ~= nil and prev.dist <= LOCK_RADIUS and prev.target == s.target
			local nowTight = s.dist ~= nil and s.dist <= TIGHT_LOCK_RADIUS

			-- snap: previously not locked (or far), suddenly landed tight on a target after a big jump
			if nowTight and not wasLocked and jump >= SNAP_MIN_JUMP then
				snapCount += 1
			end

			-- while continuously locked to the SAME target+part, measure jitter and tracking correlation
			if locked and prev.dist ~= nil and prev.dist <= LOCK_RADIUS and prev.target == s.target and prev.part == s.part then
				jitterSum += math.abs(s.dist - prev.dist)
				jitterSamples += 1

				local dt = s.t - prev.t
				if dt > 0.001 and s.targetPos and prev.targetPos then
					local aimVel = (s.pos - prev.pos) / dt
					local targetVel = (s.targetPos - prev.targetPos) / dt
					if targetVel.Magnitude > 0.5 then -- only meaningful if the target is actually moving
						local diff = (aimVel - targetVel).Magnitude
						local score = 1 - math.clamp(diff / targetVel.Magnitude, 0, 1)
						trackingSum += score
						trackingSamples += 1
					end
				end
			end
		end
	end

	local lockRatio = lockedCount / n
	local headRatio = lockedCount > 0 and (headLockedCount / lockedCount) or 0
	local exactRatio = lockedCount > 0 and (exactLockCount / lockedCount) or 0
	local snapRate = math.clamp(snapCount / math.max(HISTORY_DURATION, 0.1), 0, 3) / 3 -- normalize ~0-1
	local trackingScore = trackingSamples > 0 and (trackingSum / trackingSamples) or 0
	local avgJitter = jitterSamples > 0 and (jitterSum / jitterSamples) or LOCK_RADIUS
	local smoothnessScore = 1 - math.clamp(avgJitter / LOCK_RADIUS, 0, 1) -- 1 = suspiciously steady, 0 = normal human jitter

	local probability = 0
	if n >= MIN_SAMPLES_FOR_SCORE then
		-- exact-lock is the strongest possible signal (the aim value was basically hard-set to
		-- the part's position), so it gets the biggest single weight in the score.
		probability = (lockRatio * 20) + (headRatio * 10) + (exactRatio * 35) + (snapRate * 20) + (trackingScore * 10) + (smoothnessScore * 5)
		probability = math.clamp(probability, 0, 100)
	end

	data.metrics = {
		probability = probability,
		isLocked = isLocked,
		isExactLock = isExactLock,
		target = isLocked and last.target or nil,
		part = isLocked and last.part or nil,
		lockedFor = lockStreakStart and (last.t - lockStreakStart) or 0,
		samples = n,
	}
	return data.metrics
end

--// Tracers

local function updateTracer(player, handlePos, aimPos, metrics)
	local tracer = tracers[player]
	if not tracer then
		tracer = Instance.new("Part")
		tracer.Name = "AimviewerTracer"
		tracer.Anchored = true
		tracer.CanCollide = false
		tracer.CanQuery = false
		tracer.Shape = Enum.PartType.Cylinder
		tracer.Material = Enum.Material.Neon
		tracer.Transparency = 0.25
		tracer.Parent = workspace.Ignored
		tracers[player] = tracer
	end

	local diff = aimPos - handlePos
	local length = math.clamp(diff.Magnitude, 0.5, 300)
	tracer.Size = Vector3.new(length, 0.1, 0.1)
	tracer.CFrame = CFrame.new(handlePos, handlePos + diff.Unit) * CFrame.new(0, 0, -length * 0.5) * CFrame.Angles(0, math.pi / 2, 0)

	-- color ramps green -> yellow -> red with probability, but an exact-lock (aim value
	-- basically equals the part's position - a hard-set aim, not human) always flashes magenta
	local color
	if metrics.isExactLock then
		color = Color3.fromRGB(255, 0, 255)
	else
		local p = metrics.probability / 100
		if p < 0.5 then
			color = Color3.fromRGB(0, 255, 0):Lerp(Color3.fromRGB(255, 255, 0), p / 0.5)
		else
			color = Color3.fromRGB(255, 255, 0):Lerp(Color3.fromRGB(255, 0, 0), (p - 0.5) / 0.5)
		end
	end
	tracer.Color = color

	-- highlight the exact body part they're locked onto
	local highlight = highlights[player]
	if metrics.isLocked and metrics.target and metrics.target.Character then
		local part = metrics.target.Character:FindFirstChild(metrics.part)
		if part then
			if not highlight then
				highlight = Instance.new("Part")
				highlight.Name = "AimviewerLockHighlight"
				highlight.Anchored = true
				highlight.CanCollide = false
				highlight.CanQuery = false
				highlight.Shape = Enum.PartType.Ball
				highlight.Material = Enum.Material.Neon
				highlight.Transparency = 0.35
				highlight.Parent = workspace.Ignored
				highlights[player] = highlight
			end
			highlight.Size = Vector3.new(1.3, 1.3, 1.3)
			highlight.CFrame = part.CFrame
			highlight.Color = color
		elseif highlight then
			highlight.Parent = nil
		end
	elseif highlight then
		highlight.Parent = nil
	end
end

local function clearVisualsFor(player)
	if tracers[player] then tracers[player]:Destroy() tracers[player] = nil end
	if highlights[player] then highlights[player]:Destroy() highlights[player] = nil end
end

local function clearAllVisuals()
	for player in pairs(tracers) do clearVisualsFor(player) end
	for player in pairs(highlights) do clearVisualsFor(player) end
end

--// Core loop

local function sampleTick()
	local now = os.clock()
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= LocalPlayer and other.Character then
			local handled = false
			local ok = pcall(function()
				local character = other.Character
				local handle = getGunHandle(character)
				if not handle then return end

				local aimPos = getAimPoint(character)
				if not aimPos then return end

				handled = true

				local data = getData(other)
				local lastSample = data.lastSampleTime or 0
				if now - lastSample < SAMPLE_INTERVAL then
					-- still update the tracer visual every frame using last known metrics for smoothness
					updateTracer(other, handle.Position, aimPos, data.metrics)
					return
				end
				data.lastSampleTime = now

				local targetPlayer, targetPart, targetPos, dist = findNearestTarget(aimPos, other)
				pushSample(other, {
					t = now,
					pos = aimPos,
					target = targetPlayer,
					part = targetPart,
					targetPos = targetPos,
					dist = dist,
				})

				local metrics = analyze(other)
				updateTracer(other, handle.Position, aimPos, metrics)
			end)
			-- if they have no gun, no aim point, or errored out, don't leave a stale tracer/highlight up
			if not ok or not handled then
				clearVisualsFor(other)
			end
		else
			clearVisualsFor(other)
		end
	end
end

local function EnableAimViewer()
	if enabled then return end
	enabled = true

	heartbeatConn = RunService.Heartbeat:Connect(sampleTick)

	if _G.Notification then
		_G.Notification("Aim Viewer Enabled")
	end
end

local function DisableAimViewer()
	if not enabled then return end
	enabled = false

	if heartbeatConn then heartbeatConn:Disconnect() heartbeatConn = nil end

	clearAllVisuals()
	trackedData = {}

	if _G.Notification then
		_G.Notification("Aim Viewer Disabled")
	end
end

local function ToggleAimViewer()
	if enabled then DisableAimViewer() else EnableAimViewer() end
end

--// Tool setup

local Parent = Instance.new("Tool")
Parent.Name = "Aimviewer"
Parent.RequiresHandle = false
Parent.Parent = LocalPlayer.Backpack

Parent.Activated:Connect(ToggleAimViewer)

Players.PlayerRemoving:Connect(function(player)
	trackedData[player] = nil
	clearVisualsFor(player)
end)

LocalPlayer.CharacterAdded:Connect(function()
	trackedData = {}
	clearAllVisuals()
end)
