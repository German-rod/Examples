--// Dependencies
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Framework = require(ReplicatedStorage.Packages.Framework) -- Framework is just an interface.
--export type Framework = {Maid: typeof(Maid), Net: typeof(Net), Signal: typeof(Signal), Promise: typeof(Promise)}
local MovementService = require(game.ServerScriptService.Services.MovementService)

local WeaponRegistry = require(script.Registries.WeaponRegistry)
local PlayerWeaponRegistry = require(script.Registries.PlayerWeaponRegistry)

--// Constants
local SPRINT_LOCK_TIME = 0.25

--// Classes
local WeaponClass = require(script.Classes.Weapon)

--// Helper Functions
local function ValidateCharAndWeapon(player, tool)
	local character = player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then
		return
	end

	if humanoid.Health <= 0 or humanoid:GetState() == Enum.HumanoidStateType.Dead then
		return
	end

	local weapon = PlayerWeaponRegistry[player].Inventory[tool.Name]
	if not weapon then
		return
	end

	return weapon
end

--// Service
local WeaponsService = {
	Events = {
		WeaponEquip = Framework.Net:RemoteEvent("WeaponEquip"),
		WeaponUnEquip = Framework.Net:RemoteEvent("WeaponUnEquip"),
		WeaponReload = Framework.Net:RemoteEvent("WeaponReload"),
		WeaponStopFiring = Framework.Net:RemoteEvent("WeaponStopFiring"),
		WeaponFire = Framework.Net:RemoteEvent("WeaponFire"),
	},

	Client = {
		GetWeaponSettings = Framework.Net:RemoteFunction("GetWeaponSetting"),
	},
}

function WeaponsService:Create(player, tool)
	if not player or not tool then
		return
	end

	local weaponData = WeaponRegistry[tool.Name]
	if not weaponData then
		warn(`[WeaponsService]: Weapon:{tool.Name}, does not exist.`)
		return
	end

	if not PlayerWeaponRegistry[player].Inventory[tool.Name] then
		local weapon = WeaponClass.new(player, tool, weaponData)

		PlayerWeaponRegistry[player].Inventory[tool.Name] = weapon

		tool.Destroying:Once(function()
			if not PlayerWeaponRegistry[player] then
				return
			end -- player already left

			weapon:Destroy()
			PlayerWeaponRegistry[player].Inventory[tool.Name] = nil

			local equipped = PlayerWeaponRegistry[player].Equipped
			if equipped and equipped.Tool == tool then
				PlayerWeaponRegistry[player].Equipped = nil
			end
		end)
	end
end

function WeaponsService:Connections()
	--// Events
	WeaponsService.Events.WeaponEquip.OnServerEvent:Connect(function(player, tool)
		local weapon = ValidateCharAndWeapon(player, tool)
		if not weapon then
			return
		end

		PlayerWeaponRegistry[player].Equipped = weapon
		weapon:Equip()
	end)
	WeaponsService.Events.WeaponUnEquip.OnServerEvent:Connect(function(player, tool)
		local weapon = ValidateCharAndWeapon(player, tool)
		if not weapon then
			return
		end

		PlayerWeaponRegistry[player].Equipped = nil
		weapon:Unequip()
	end)

	WeaponsService.Events.WeaponFire.OnServerEvent:Connect(function(player, mousePos, tool)
		local weapon = ValidateCharAndWeapon(player, tool)
		if not weapon then
			return
		end
		MovementService:AddSprintLock(player, "Weapon.Firing")
		weapon:RequestShot(mousePos)
	end)

	WeaponsService.Events.WeaponStopFiring.OnServerEvent:Connect(function(player, tool)
		local weapon = ValidateCharAndWeapon(player, tool)
		if not weapon then
			return
		end

		MovementService:RemoveSprintLock(player, "Weapon.Firing", SPRINT_LOCK_TIME)
		weapon:StopFiring()
	end)

	WeaponsService.Events.WeaponReload.OnServerEvent:Connect(function(player, tool)
		local weapon = ValidateCharAndWeapon(player, tool)
		if not weapon then
			return
		end

		MovementService:AddSprintLock(player, "Weapon.Reloading")
		weapon:RequestReload()

		pcall(function()
			weapon.OnReloadFinished:Once(function()
				MovementService:RemoveSprintLock(player, "Weapon.Reloading")
			end)
		end)
	end)

	--// Remote Functions
	Framework.Net:Handle("GetWeaponSetting", function(player, weaponName, setting)
		weaponName = weaponName:match("^%s*(.-)%s*$") or weaponName

		local weaponData = WeaponRegistry[weaponName]
		if not weaponData then
			warn(`Weapon '{weaponName}' not found in registry`)
			return nil
		end

		return weaponData[setting]
	end)

	--// Connections
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			-- destroy all existing weapons, character has changed
			for name, weapon in pairs(PlayerWeaponRegistry[player].Inventory) do
				weapon:Destroy()
				PlayerWeaponRegistry[player].Inventory[name] = nil
			end
			PlayerWeaponRegistry[player].Equipped = nil

			-- interrupt reload on death
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.Died:Once(function()
					local weapon = PlayerWeaponRegistry[player].Equipped
					if weapon then
						weapon:InterruptReload()
					end
				end)
			end

			task.wait() -- wait a frame for backpack to populate

			for _, tool in pairs(player.Backpack:GetChildren()) do
				if tool:IsA("Tool") and tool:GetAttribute("Weapon") then
					self:Create(player, tool)
				end
			end
		end)

		player.Backpack.ChildAdded:Connect(function(tool)
			if tool:IsA("Tool") and tool:GetAttribute("Weapon") then
				self:Create(player, tool)
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		for index, weapon in pairs(PlayerWeaponRegistry[player].Inventory) do
			weapon:Destroy()
			PlayerWeaponRegistry[player].Inventory[index] = nil
		end
		PlayerWeaponRegistry[player] = nil
	end)
end

function WeaponsService:OnStart()
	self:Connections()
end

return WeaponsService
