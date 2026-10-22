local LocalPlayer = game.Players.LocalPlayer

repeat
	wait()
until LocalPlayer.Character

local speedMultiplier = 1

game.UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent or not script.Parent:IsDescendantOf(LocalPlayer.Character) then
		return
	end

	if input.KeyCode == Enum.KeyCode.Q then
		speedMultiplier = speedMultiplier - 0.1
		if speedMultiplier < 0.1 then
			speedMultiplier = 0.1
		end
	end

	if input.KeyCode == Enum.KeyCode.E then
		speedMultiplier = speedMultiplier + 0.1
		if speedMultiplier > 10 then
			speedMultiplier = 10
		end
	end
end)

local Character = LocalPlayer.Character
local Humanoid = Character:WaitForChild("Humanoid")

local FlyTool = Instance.new("Tool", LocalPlayer.Backpack)
FlyTool.Name = "[FlyTool]"
FlyTool.RequiresHandle = false
FlyTool.CanBeDropped = false

local FlapSound = Instance.new("Sound")
FlapSound.SoundId = "rbxassetid://9113716666"
FlapSound.Parent = LocalPlayer.Character.HumanoidRootPart
FlapSound.Name = "Flapping"
FlapSound.Looped = true

local ActivationSound = Instance.new("Sound")
ActivationSound.Parent = LocalPlayer.Character.HumanoidRootPart
ActivationSound.Name = "Activation"
ActivationSound.SoundId = "rbxassetid://2952274135"

local HoverAnimation = Instance.new("Animation")
HoverAnimation.AnimationId = "rbxassetid://113644780745425"

local FlyAnimation = Instance.new("Animation")
FlyAnimation.AnimationId = "rbxassetid://92365791487740"

local isHovering = false
local hoverAnimTrack = Humanoid:LoadAnimation(HoverAnimation)
hoverAnimTrack.Priority = Enum.AnimationPriority.Action4

local bodyGyro = nil
local bodyPosition = nil
local isBoosting = false
local isBoostHeld = false
local flyAnimTrack = Humanoid:LoadAnimation(FlyAnimation)
flyAnimTrack.Priority = Enum.AnimationPriority.Action4

local equipGeneration = 0
local button1DownConn = nil
local button1UpConn = nil
local currentBoostVelocity = nil

local UNEQUIP_GRACE_PERIOD = 0.1

FlyTool.Equipped:Connect(function(mouse)
	equipGeneration = equipGeneration + 1

	ActivationSound:Play()
	mouse.TargetFilter = workspace

	isHovering = true

	if not bodyGyro then
		bodyGyro = Instance.new("BodyGyro")
		bodyGyro.Name = "NA"
		bodyGyro.Parent = Character.HumanoidRootPart
		bodyGyro.MaxTorque = Vector3.new(30000, 0, 30000)
		bodyGyro.P = bodyGyro.P * 5
		bodyGyro.CFrame = CFrame.new(0, 0, 0)
	end

	if not bodyPosition then
		bodyPosition = Instance.new("BodyPosition")
		bodyPosition.Name = "NA"
		bodyPosition.Parent = Character.HumanoidRootPart
		bodyPosition.MaxForce = Vector3.new(60000, 60000, 60000)
		bodyPosition.Position = Character.HumanoidRootPart.Position
	end

	if not isBoostHeld and not hoverAnimTrack.IsPlaying then
		hoverAnimTrack:Play()
	end

	if button1DownConn then
		button1DownConn:Disconnect()
	end
	if button1UpConn then
		button1UpConn:Disconnect()
	end

	button1DownConn = mouse.Button1Down:Connect(function()
		FlapSound:Play()

		if isBoosting then
			return
		end

		isBoosting = true
		isBoostHeld = true
		flyAnimTrack:Play()

		local boostVelocity = Instance.new("BodyVelocity", Character.HumanoidRootPart)
		boostVelocity.Name = "ShazamFlyBoostVelocity"
		boostVelocity.MaxForce = Vector3.new(50000, 50000, 50000)
		currentBoostVelocity = boostVelocity

		local function finishBoost()
			isBoostHeld = false

			pcall(function()
				if Humanoid and Humanoid.Parent then
					Humanoid.AutoRotate = true
				end

				if boostVelocity and boostVelocity.Parent then
					boostVelocity:Destroy()
				end

				if currentBoostVelocity == boostVelocity then
					currentBoostVelocity = nil
				end

				if bodyPosition then
					pcall(function()
						local hrp = Character:FindFirstChild("HumanoidRootPart")
						if hrp then
							bodyPosition.Position = hrp.Position
							bodyPosition.Parent = hrp
						end
					end)
				end

				if bodyGyro then
					pcall(function()
						bodyGyro.MaxTorque = Vector3.new(30000, 0, 30000)
						bodyGyro.CFrame = CFrame.new(0, 0, 0)
					end)
				end

				if isHovering and hoverAnimTrack and not hoverAnimTrack.IsPlaying then
					hoverAnimTrack:Play()
				end

				FlapSound:Stop()
				flyAnimTrack:Stop()
			end)

			wait(0.3)
			isBoosting = false
		end

		local ok, err = pcall(function()
			boostVelocity.Velocity = CFrame.new(Character.HumanoidRootPart.CFrame.p, mouse.Hit.p).lookVector * 85

			if bodyGyro and bodyGyro.Parent then
				bodyGyro.MaxTorque = Vector3.new(30000, 30000, 30000)
				bodyGyro.CFrame = CFrame.new(Character.HumanoidRootPart.CFrame.p, mouse.Hit.p)
			end

			if bodyPosition and bodyPosition.Parent then
				bodyPosition.Parent = nil
			end

			Humanoid.AutoRotate = false

			if hoverAnimTrack.IsPlaying then
				hoverAnimTrack:Stop()
			end

			while isBoostHeld do
				if not boostVelocity or not boostVelocity.Parent then break end
				if not bodyGyro or not bodyGyro.Parent then break end

				local hrp = Character:FindFirstChild("HumanoidRootPart")
				if not hrp then break end

				local aimCFrame = CFrame.new(hrp.Position, mouse.Hit.p)
				boostVelocity.Velocity = aimCFrame.lookVector * 85 * speedMultiplier
				bodyGyro.CFrame = aimCFrame
				game:GetService("RunService").Heartbeat:Wait()
			end
		end)

		if not ok then
			warn("ShazamFly boost error: " .. tostring(err))
		end

		finishBoost()
	end)

	button1UpConn = mouse.Button1Up:Connect(function()
		FlapSound:Stop()
		isBoostHeld = false
	end)
end)

FlyTool.Unequipped:Connect(function()
	local thisGeneration = equipGeneration

	FlapSound:Stop()
	ActivationSound:Play()
	isHovering = false

	task.wait(UNEQUIP_GRACE_PERIOD)
	if equipGeneration ~= thisGeneration then
		return
	end

	isBoostHeld = false

	if currentBoostVelocity and currentBoostVelocity.Parent then
		currentBoostVelocity:Destroy()
		currentBoostVelocity = nil
	end

	pcall(function()
		if Humanoid and Humanoid.Parent then
			Humanoid.AutoRotate = true
		end
	end)

	if bodyGyro then
		bodyGyro:Destroy()
		bodyGyro = nil
	end

	if bodyPosition then
		bodyPosition:Destroy()
		bodyPosition = nil
	end

	if hoverAnimTrack.IsPlaying then
		hoverAnimTrack:Stop()
	end
end)

FlyTool.Destroying:Connect(function()
	if FlyTool.Parent == LocalPlayer.Character then
		FlapSound:Stop()
		ActivationSound:Play()
		isHovering = false
		isBoostHeld = false

		if currentBoostVelocity and currentBoostVelocity.Parent then
			currentBoostVelocity:Destroy()
			currentBoostVelocity = nil
		end

		pcall(function()
			if Humanoid and Humanoid.Parent then
				Humanoid.AutoRotate = true
			end
		end)

		if bodyGyro then
			bodyGyro:Destroy()
			bodyGyro = nil
		end

		if bodyPosition then
			bodyPosition:Destroy()
			bodyPosition = nil
		end

		if hoverAnimTrack.IsPlaying then
			hoverAnimTrack:Stop()
		end
	end
end)
