--[[
	MovementController

	Client-side Knit controller that manages player movement
	behaviors including sprinting and dodging. Handles input,
	animation control, physics, and movement state along MovementService.
]]

--// Dependencies
local Knit = require(game:GetService("ReplicatedStorage").Packages.Knit)
local UserInputService = game:GetService("UserInputService")

--// Variables
local Player = game:GetService("Players").LocalPlayer

--// Constants
local WALK_SPEED = game.StarterPlayer.CharacterWalkSpeed
local JUMP_HEIGHT = game.StarterPlayer.CharacterJumpHeight
local RUN_MULTIPLIER = 1.5

local RUN_ANIMATION = game.ReplicatedStorage.Animations.Run
local ROLL_ANIMATION = game.ReplicatedStorage.Animations.Roll
--// Controller

local MovementController = Knit.CreateController({
	Name = "MovementController",

	Character = Player.Character or Player.CharacterAdded:Wait(),
	Running = false,
	MovementDisabled = false,
	DodgeVelocity = nil,
})

--// Methods

function MovementController:Run()
	self.Character = Player.Character or Player.CharacterAdded:Wait()
	if not self.Character then
		return
	end

	self.Running = true
	local track = self.Character.Humanoid.Animator:LoadAnimation(RUN_ANIMATION)
	track:Play()

	self.Character.Humanoid.WalkSpeed = WALK_SPEED * RUN_MULTIPLIER * Player:GetAttribute("SpeedMultiplier")

	while self.Running do
		task.wait()
		if self.Character.Humanoid.MoveDirection == Vector3.zero then
			self:StopRun()
		end
	end
end

function MovementController:StopRun()
	self.Character = Player.Character or Player.CharacterAdded:Wait()
	if not self.Character then
		return
	end

	self.Running = false
	for _, track in pairs(self.Character.Humanoid.Animator:GetPlayingAnimationTracks()) do
		if track.Animation == RUN_ANIMATION then
			track:Stop()
		end
	end

	self.Character.Humanoid.WalkSpeed = WALK_SPEED * Player:GetAttribute("SpeedMultiplier")
end

function MovementController:Dodge()
	self.Character = Player.Character or Player.CharacterAdded:Wait()
	if not self.Character then
		return
	end
	self.Character.Humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)

	-- Fire the DodgeSignal, basically ask for permission to perform the dodge from the server.
	self.MovementService.DodgeSignal:Fire()
end

--// Handling
function MovementController:KnitStart()
	self.MovementService = Knit.GetService("MovementService")

	-- Connect to the DodgeSignal for handling the dodge logic.
	self.MovementService.DodgeSignal:Connect(function(DodgeDuration, DodgeForce)
		local humanoidRootPart = self.Character.HumanoidRootPart
		local humanoid = self.Character.Humanoid
		if not humanoidRootPart or not humanoid or not humanoid:FindFirstChild("Animator") then
			return
		end

		-- Create and set BodyVelocity
		local bodyVelocity = Instance.new("BodyVelocity")
		bodyVelocity.MaxForce = Vector3.new(100000, 0, 100000)
		bodyVelocity.P = 500000
		bodyVelocity.Velocity = humanoidRootPart.CFrame.LookVector * DodgeForce
		bodyVelocity.Parent = humanoidRootPart
		self.DodgeVelocity = bodyVelocity

		local dodging = true
		task.spawn(function()
			while dodging do
				if not bodyVelocity then
					break
				end

				if humanoid.FloorMaterial == Enum.Material.Air then
					humanoidRootPart.Velocity = humanoidRootPart.CFrame.LookVector * (DodgeForce * 0.1)
				else
					bodyVelocity.Velocity = humanoidRootPart.CFrame.LookVector * DodgeForce
				end
				task.wait()
			end
		end)

		-- Play dodge animation
		local track = humanoid.Animator:LoadAnimation(ROLL_ANIMATION)
		track:Play()
		track.Ended:Once(function()
			if self.MovementDisabled then
				return
			end

			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
		end)

		-- Remove BodyVelocity
		task.delay(DodgeDuration, function()
			dodging = false
			if bodyVelocity then
				bodyVelocity:Destroy()
			end
			self.DodgeVelocity = nil
		end)
	end)

	Player:GetAttributeChangedSignal("MovementDisabled"):Connect(function()
		local isDisabled = Player:GetAttribute("MovementDisabled")
		self.MovementDisabled = isDisabled

		if isDisabled then
			if self.Running then
				self.Running = false
				for _, track in pairs(self.Character.Humanoid.Animator:GetPlayingAnimationTracks()) do
					if
						track.Animation == RUN_ANIMATION
						or track.Animation == ROLL_ANIMATION
					then
						track:Stop()
					end
				end
			end
			if self.DodgeVelocity then
				self.DodgeVelocity:Destroy()
			end

			return
		end
	end)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if self.MovementDisabled then
			return
		end

		if input.KeyCode == Enum.KeyCode.LeftShift then
			self:Run()
		end

		if input.KeyCode == Enum.KeyCode.Q then
			self:Dodge()
		end
	end)

	UserInputService.InputEnded:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if self.MovementDisabled then
			return
		end

		if input.KeyCode == Enum.KeyCode.LeftShift then
			self:StopRun()
		end
	end)
end

return MovementController
