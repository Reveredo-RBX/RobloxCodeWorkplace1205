local LaunchRocket = game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("LaunchRocket")
local UpgradesConfig = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("UpgradesConfig"))

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Player = game.Players.LocalPlayer
local Base_WalkSpeed = 28

local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")

local Launching = false
local function StartLaunchAnim()
	if Launching then
		return
	end

	Launching = true

	local PlayerBase = workspace:WaitForChild("BaseTemplate")
	--TODO Make the above use the players base

	local GroundSmoke = PlayerBase.Base.GroundSmoke.GroundSmoke
	local Rocket = PlayerBase:FindFirstChild("Rocket")
	if not Rocket or not Rocket.PrimaryCenter then
		Launching = false
		return
	end

	local FireVFX1 = Rocket.Thruster.Rocket.PE1
	local FireVFX2 = Rocket.Thruster.Rocket.PE2

	task.spawn(function()
		GroundSmoke.Enabled = true
		task.wait(2)
		GroundSmoke.Enabled = false
	end)

	FireVFX1.Enabled = true
	FireVFX2.Enabled = true

	task.wait(1)

	-- TODO: Confirm they are the player who owns this base 
	local R_Power = UpgradesConfig:GetUpgrade("FuelPower", Player.upgrades.PowerLevel.Value)
	local R_Fuel = UpgradesConfig:GetUpgrade("FuelCapacity", Player.upgrades.FuelLevel.Value)
	local R_Steering = UpgradesConfig:GetUpgrade("Steering", Player.upgrades.SteeringLevel.Value)

	-- ENTER THE ROCKET AND TWEEN UP

	local Character = Player.Character
	if not Character then
		FireVFX1.Enabled = false
		FireVFX2.Enabled = false
		Launching = false
		return
	end

	local Humanoid = Character:FindFirstChildOfClass("Humanoid")
	local HumanoidRootPart = Character:FindFirstChild("HumanoidRootPart")

	if not Humanoid or not HumanoidRootPart then
		FireVFX1.Enabled = false
		FireVFX2.Enabled = false
		Launching = false
		return
	end

	-- Disable character movement
	Humanoid.AutoRotate = false
	Humanoid.WalkSpeed = 0
	Humanoid.JumpPower = 0

	-- =========================================================
	-- STAGE 1: ROCKET LAUNCHES WITHOUT PLAYER
	-- =========================================================

	local startPivot = Rocket:GetPivot()

	-- First target = 15 studs
	local firstTargetPivot = startPivot + Vector3.new(0, 15, 0)

	local progress = Instance.new("NumberValue")
	progress.Value = 0

	local connection = progress:GetPropertyChangedSignal("Value"):Connect(function()
		Rocket:PivotTo(
			startPivot:Lerp(
				firstTargetPivot,
				progress.Value
			)
		)
	end)

	local firstTween = TweenService:Create(
		progress,
		TweenInfo.new(
			0.8,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.In
		),
		{Value = 1}
	)

	firstTween:Play()
	firstTween.Completed:Wait()

	connection:Disconnect()
	progress:Destroy()

	-- =========================================================
	-- STAGE 2: PUT PLAYER INSIDE ROCKET
	-- =========================================================

	HumanoidRootPart.CFrame = Rocket.PrimaryCenter.CFrame

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = HumanoidRootPart
	weld.Part1 = Rocket.PrimaryCenter
	weld.Parent = HumanoidRootPart

	-- =========================================================
	-- CUSTOM CAMERA
	-- =========================================================

	local Camera = workspace.CurrentCamera

	-- Store the camera's position before switching
	local originalCameraCFrame = Camera.CFrame

	Camera.CameraType = Enum.CameraType.Scriptable

	local rocketCF = Rocket.PrimaryCenter.CFrame

	local cameraPosition =
		rocketCF.Position
		+ rocketCF.UpVector * -15
		+ rocketCF.LookVector * 10

	local lookPosition =
		rocketCF.Position
		+ rocketCF.UpVector * 5

	local targetCameraCFrame = CFrame.lookAt(
		cameraPosition,
		lookPosition
	)

	-- Start at the original camera position
	Camera.CFrame = originalCameraCFrame

	-- Tween into the rocket camera
	local cameraTween = TweenService:Create(
		Camera,
		TweenInfo.new(
			0.6,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out
		),
		{
			CFrame = targetCameraCFrame
		}
	)

	cameraTween:Play()
	cameraTween.Completed:Wait()

	-- Then follow the rocket
	local cameraConnection

	cameraConnection = RunService.RenderStepped:Connect(function()
		if not Rocket.Parent then
			return
		end

		local rocketCF = Rocket.PrimaryCenter.CFrame

		local cameraPosition =
			rocketCF.Position
			+ rocketCF.UpVector * -15
			+ rocketCF.LookVector * 10

		local lookPosition =
			rocketCF.Position
			+ rocketCF.UpVector * 5

		Camera.CFrame = CFrame.lookAt(
			cameraPosition,
			lookPosition
		)
	end)

	-- =========================================================
	-- STAGE 3: ACTUAL ROCKET FLIGHT
	-- =========================================================

	-- The rocket's original orientation is captured once.
	-- Movement is always calculated in WORLD space so tilt can
	-- never affect the direction of travel.
	local flightStartPivot = Rocket:GetPivot()
	local baseRotation = flightStartPivot - flightStartPivot.Position

	local verticalSpeed = 20 * R_Power.Value
	local MAX_XZ_SPEED = 35
	local acceleration = 12 * R_Steering.Value
	local MAX_TILT = math.rad(30)
	local tiltSpeed = 8

	local horizontalVelocity = Vector3.zero
	local currentTiltX = 0
	local currentTiltZ = 0
	local flightStart = os.clock()
	local fuelDuration = R_Fuel.Value
	local flightFinished = false

	-- =========================================================
	-- STEERING INPUT
	-- =========================================================

	local steeringKeys = {
		Left = false,
		Right = false,
		Forward = false,
		Backward = false,
	}

	local SteeringInput = Vector2.zero
	local gamepadInput = Vector2.zero

	local function RefreshSteeringInput()
		local gamepad = gamepadInput

		local x = gamepad.X
		local y = gamepad.Y

		if steeringKeys.Left then
			x -= 1
		end

		if steeringKeys.Right then
			x += 1
		end

		if steeringKeys.Forward then
			y += 1
		end

		if steeringKeys.Backward then
			y -= 1
		end

		SteeringInput = Vector2.new(x, y)

		if SteeringInput.Magnitude > 1 then
			SteeringInput = SteeringInput.Unit
		end
	end

	local function SetSteeringKey(key, state)
		steeringKeys[key] = state ~= Enum.UserInputState.End
		RefreshSteeringInput()
	end

	local function MoveLeft(_, state)
		SetSteeringKey("Left", state)
		return Enum.ContextActionResult.Sink
	end

	local function MoveRight(_, state)
		SetSteeringKey("Right", state)
		return Enum.ContextActionResult.Sink
	end

	local function MoveForward(_, state)
		SetSteeringKey("Forward", state)
		return Enum.ContextActionResult.Sink
	end

	local function MoveBackward(_, state)
		SetSteeringKey("Backward", state)
		return Enum.ContextActionResult.Sink
	end

	ContextActionService:BindAction(
		"RocketLeft",
		MoveLeft,
		true,
		Enum.KeyCode.A,
		Enum.KeyCode.DPadLeft
	)
	ContextActionService:SetTitle("RocketLeft", "◀")
	ContextActionService:SetPosition("RocketLeft", UDim2.fromScale(0.12, 0.72))

	ContextActionService:BindAction(
		"RocketRight",
		MoveRight,
		true,
		Enum.KeyCode.D,
		Enum.KeyCode.DPadRight
	)
	ContextActionService:SetTitle("RocketRight", "▶")
	ContextActionService:SetPosition("RocketRight", UDim2.fromScale(0.24, 0.72))

	ContextActionService:BindAction(
		"RocketForward",
		MoveForward,
		true,
		Enum.KeyCode.W,
		Enum.KeyCode.DPadUp
	)
	ContextActionService:SetTitle("RocketForward", "▲")
	ContextActionService:SetPosition("RocketForward", UDim2.fromScale(0.18, 0.60))

	ContextActionService:BindAction(
		"RocketBackward",
		MoveBackward,
		true,
		Enum.KeyCode.S,
		Enum.KeyCode.DPadDown
	)
	ContextActionService:SetTitle("RocketBackward", "▼")
	ContextActionService:SetPosition("RocketBackward", UDim2.fromScale(0.18, 0.84))

	-- Console thumbstick support. Mobile uses the touch buttons
	-- created by ContextActionService above.
	local gamepadConnection = UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Gamepad1
			and input.KeyCode == Enum.KeyCode.Thumbstick1 then
			gamepadInput = Vector2.new(input.Position.X, input.Position.Y)
			RefreshSteeringInput()
		end
	end)

	-- =========================================================
	-- FLIGHT LOOP
	-- =========================================================

	local flightConnection

	flightConnection = RunService.Heartbeat:Connect(function(deltaTime)
		if not Rocket.Parent then
			flightFinished = true
			return
		end

		local elapsed = os.clock() - flightStart

		if elapsed >= fuelDuration then
			flightFinished = true
			return
		end

		-- -----------------------------------------------------
		-- INPUT -> TARGET XZ VELOCITY
		-- -----------------------------------------------------

		local input = SteeringInput

		if input.Magnitude > 1 then
			input = input.Unit
		end

		-- =====================================================
		-- WORLD-SPACE STEERING
		-- =====================================================
		--
		-- W = +Z
		-- S = -Z
		-- A = -X
		-- D = +X
		--
		-- This deliberately does NOT use the camera's
		-- LookVector/RightVector. The camera follows the rocket,
		-- so using it here would create rotational feedback.
		--

		local desiredDirection = Vector3.new(
			input.X,
			0,
			input.Y
		)

		if desiredDirection.Magnitude > 1 then
			desiredDirection = desiredDirection.Unit
		end

		local targetVelocity =
			desiredDirection * MAX_XZ_SPEED

		-- Steering ONLY changes acceleration. The maximum speed
		-- is always MAX_XZ_SPEED.
		local difference = targetVelocity - horizontalVelocity
		local maxChange = acceleration * deltaTime

		if difference.Magnitude <= maxChange then
			horizontalVelocity = targetVelocity
		elseif difference.Magnitude > 0 then
			horizontalVelocity += difference.Unit * maxChange
		end

		-- -----------------------------------------------------
		-- NO INPUT -> DECELERATE TO ZERO
		-- -----------------------------------------------------

		if input.Magnitude == 0 then
			local deceleration = acceleration * deltaTime

			if horizontalVelocity.Magnitude <= deceleration then
				horizontalVelocity = Vector3.zero
			else
				horizontalVelocity -= horizontalVelocity.Unit * deceleration
			end
		end

		-- -----------------------------------------------------
		-- VERTICAL FLIGHT
		-- -----------------------------------------------------

		-- Fuel Power controls vertical speed.
		-- Fuel Capacity controls how long this loop runs.
		local velocity = Vector3.new(
			horizontalVelocity.X,
			verticalSpeed,
			horizontalVelocity.Z
		)

		-- -----------------------------------------------------
		-- VELOCITY-BASED TILT
		-- -----------------------------------------------------

		local targetPitch = math.clamp(
			-horizontalVelocity.Z / MAX_XZ_SPEED * MAX_TILT,
			-MAX_TILT,
			MAX_TILT
		)

		local targetRoll = math.clamp(
			horizontalVelocity.X / MAX_XZ_SPEED * MAX_TILT,
			-MAX_TILT,
			MAX_TILT
		)

		local tiltAlpha = math.clamp(
			tiltSpeed * deltaTime,
			0,
			1
		)

		currentTiltX +=
			(targetPitch - currentTiltX) * tiltAlpha

		currentTiltZ +=
			(targetRoll - currentTiltZ) * tiltAlpha

		-- -----------------------------------------------------
		-- APPLY MOVEMENT + TILT
		-- -----------------------------------------------------

		local currentPosition = Rocket:GetPivot().Position

		local newPosition =
			currentPosition
			+ velocity * deltaTime

		-- Apply the tilt BEFORE the rocket's original rotation.
		-- This makes the tilt use stable WORLD X/Z axes instead
		-- of the rocket's already-rotated local axes.
		local tiltRotation =
			CFrame.Angles(
				currentTiltX,
				0,
				currentTiltZ
			)

		Rocket:PivotTo(
			CFrame.new(newPosition)
				* tiltRotation
				* baseRotation
		)
	end)

	-- Wait for fuel to run out.
	while not flightFinished and Rocket.Parent do
		task.wait()
	end

	if flightConnection then
		flightConnection:Disconnect()
	end

	if gamepadConnection then
		gamepadConnection:Disconnect()
	end

	-- =========================================================
	-- CLEANUP
	-- =========================================================

	ContextActionService:UnbindAction("RocketLeft")
	ContextActionService:UnbindAction("RocketRight")
	ContextActionService:UnbindAction("RocketForward")
	ContextActionService:UnbindAction("RocketBackward")

	SteeringInput = Vector2.zero

	if cameraConnection then
		cameraConnection:Disconnect()
	end

	if weld and weld.Parent then
		weld:Destroy()
	end

	Humanoid.AutoRotate = true
	Humanoid.WalkSpeed = Base_WalkSpeed
	Humanoid.JumpPower = 50

	Camera.CameraType = Enum.CameraType.Custom
	Camera.CameraSubject = Humanoid

	if PlayerBase:FindFirstChild("TPPart") then
		HumanoidRootPart.CFrame = PlayerBase.TPPart.CFrame
	end

	-- Return the rocket to its base attachment without using the
	-- flight orientation/tilt as the new reference frame.
	local RocketAtt = Rocket:FindFirstChild("Attachment")
	local Base = PlayerBase:FindFirstChild("Base")
	local BaseAtt = Base and Base:FindFirstChild("Attachment")

	if RocketAtt and BaseAtt then
		local attachmentOffset = Rocket:GetPivot():ToObjectSpace(
			RocketAtt.WorldCFrame
		)

		local targetPivot =
			BaseAtt.WorldCFrame * attachmentOffset:Inverse()

		Rocket:PivotTo(targetPivot)
	end

	FireVFX1.Enabled = false
	FireVFX2.Enabled = false

	Launching = false
end

LaunchRocket.OnClientEvent:Connect(function()
	StartLaunchAnim()
end)
