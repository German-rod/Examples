--// Dependencies
local Framework = require(game.ReplicatedStorage.Packages.Framework)
local EffectsService = require(game.ServerScriptService.Services.EffectsService)

local AmmoController = require(script.Parent.Parent.Controllers.AmmoController)
local StateController = require(script.Parent.Parent.Controllers.StateController)
local CooldownController = require(script.Parent.Parent.Controllers.CooldownController)

local ValidationSystem = require(script.Parent.Parent.Systems.ValidationSystem)
local AudioSystem = require(script.Parent.Parent.Systems.AudioSystem)
local AnimationSystem = require(script.Parent.Parent.Systems.AnimationSystem)
local ShootingSystem = require(script.Parent.Parent.Systems.ShootingSystem)
local DamageSystem = require(script.Parent.Parent.Systems.DamageSystem)
local EquipSystem = require(script.Parent.Parent.Systems.EquipSystem)

--// Weapon Base Class
local Weapon = {}
Weapon.__index = Weapon

function Weapon.new(player, tool, data)
	local self = setmetatable({}, Weapon)
	
	self.Data = data
	self.Name = data.Name

	self.Player = player
	self.Character = player.Character
	self.Tool = tool

	self.AmmoController = AmmoController.new(tool, data)
	self.StateController = StateController.new()
	self.CooldownController = CooldownController.new(data.RoundsPerSecond)
	
	self.FireMode = require(data.FireMode).new()
	self.ReloadMode = require(data.ReloadMode).new(self)
	
	self.ValidationSystem = ValidationSystem.new(self)
	self.EquipSystem = EquipSystem.new(self.Character, self.Tool)
	self.AnimationSystem = AnimationSystem.new(
		self.Character,
		data.AnimationsFolder
	)

	self.AudioSystem = AudioSystem.new(
		tool.Handle,
		data.SoundsFolder
	)
	
	self.ShootingSystem = ShootingSystem.new(self.Character)
	self.DamageSystem = DamageSystem.new(self.Player)
	
	self.OnReloadFinished = Framework.Signal.new()
	
	return self
end

function Weapon:Equip()
	local ok, reason = self.ValidationSystem:Validate()

	if not ok then
		warn(`Failed to equip {self.Name} for {self.Player.Name}: {reason}`)
		return
	end

	self.AudioSystem:Play('GunEquip')
	self.AnimationSystem:Play('Draw')
	self.AnimationSystem:Play('Hold', {looped = true})
	self.EquipSystem:Equip()
	self.StateController:SetState('Equipped', true)
end

function Weapon:Unequip()
	self.StateController:SetState('Equipped', false)
	self.AudioSystem:Play('GunUnequip')
	self.AnimationSystem:StopAll()
	self.EquipSystem:Unequip()
	self:InterruptReload()
end

function Weapon:StartFiring(getMousePos)
	self.FireMode:OnStartFiring(self, getMousePos)
end

function Weapon:StopFiring()
	self.FireMode:OnStopFiring(self)
end

function Weapon:RequestShot(getMousePos)
	local ok = self.ValidationSystem:ValidateShot()
	if not ok then return end
	self.FireMode:ConsumeFire(self, getMousePos)
end

function Weapon:Fire(mousePos)
	self.StateController:SetState('Firing', true)

	self.AnimationSystem:Play('Fire', {priority = Enum.AnimationPriority.Action2})
	self.AudioSystem:Play('Fire')
	
	
	local smokePartEffect = {
		Name = 'SmokePartEmit',
		RenderDistance = 500,
		Origin = self.Tool.SmokePart.Position,
		SmokePart = self.Tool:FindFirstChild('SmokePart'),
	}
	
	EffectsService:TriggerEffect(smokePartEffect)
	
	local hitStopEffect = {
		Name = 'Blur',
		Size = 4,
		Duration = 0.1
	}
	EffectsService:TriggerEffectForPlayer(self.Player, hitStopEffect)
	
	local hitStopEffect = {
		Name = 'CameraShake',
		Intensity = 0.5,
		RecoilPitch = 0,
		RecoilYaw = 0,
	}
	EffectsService:TriggerEffectForPlayer(self.Player, hitStopEffect)

	local origin = self.Tool.SmokePart.Position
	local direction = Vector3.new(
		mousePos.X,
		origin.Y,
		mousePos.Z
	) - origin

	local result = self.ShootingSystem:Fire(origin, origin + direction.Unit * (self.Data.Range or 1000), self.Data)
	if result then
		local tracerEffect = {
			Name = 'Tracer',
			RenderDistance = 500,
			Origin = origin,
			HitPosition = result.Position,
		}
		EffectsService:TriggerEffect(tracerEffect)
		
		local humanoid = self.DamageSystem:ApplyFromRaycast(result, self.Data)
		if humanoid then
			local hitEffect = {
				Name = 'PlayerHit',
				RenderDistance = 500,
				Target = humanoid.Parent,
				Origin = result.Instance.Position,
				HitPosition = result.Position,
			}
			
			EffectsService:TriggerEffect(hitEffect)
			EffectsService:TriggerEffectForPlayer(self.Player, hitStopEffect)
		else
			local hitEffect = {
				Name = 'BulletMapHit',
				RenderDistance = 500,
				Origin = result.Position,
				Result = {
					Position = result.Position,
					Instance = result.Instance
				}
			}

			EffectsService:TriggerEffect(hitEffect)
		end
	end
	
	self.StateController:SetState('Firing', false)
end

function Weapon:RequestReload()
	local ok, reason = self.ValidationSystem:ValidateReload()
	if not ok then
		return
	end
	
	self.ReloadMode:Execute(self)
end

function Weapon:InterruptReload()
	self.ReloadMode:Interrupt()
	self.OnReloadFinished:Fire()
end

function Weapon:FinishReload()
	self.AmmoController:Refill()
	self.StateController:SetState('Reloading', false)
	self.OnReloadFinished:Fire()
end

function Weapon:Destroy()
	if self._destroyed then return end
	self._destroyed = true
	
	-- Interrupt any behaviors first
	self:InterruptReload()

	-- Destroy each controller, system and signal.
	self.AnimationSystem:Destroy()
	self.AudioSystem:Destroy()
	self.EquipSystem:Destroy()
	self.ValidationSystem:Destroy()
	self.AmmoController:Destroy()
	self.StateController:Destroy()
	self.CooldownController:Destroy()
	self.ShootingSystem:Destroy()
	self.DamageSystem:Destroy()
	
	self.OnReloadFinished:Destroy()
	
	-- Clear references
	self.Data = nil
	self.Name = nil
	self.Player = nil
	self.Character = nil
	self.Tool = nil
	self.FireMode = nil
	self.ReloadMode = nil
end

return Weapon
