--[[
	InventoryModule
	Handles the logic for the inventory interface responsiveness.
]]

--// Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")

--// Variables
local Player = Players.LocalPlayer
local PlayerGui = Player.PlayerGui
local Mouse = Player:GetMouse()
local Character = Player.Character
local HumanoidRootPart = Character.HumanoidRootPart
local Humanoid = Character.Humanoid

local InventoryFrame = PlayerGui.Inventory.Inventory
local InventoryItemsHolder = InventoryFrame.Items
local GroundFrame = PlayerGui.Inventory.Ground
local GroundItemsHolder = GroundFrame.Items
local HotbarFrame = PlayerGui.Inventory.Hotbar
local SideHotbarFrame = PlayerGui.Inventory.SideHotbar
local ItemTemplate = script.Parent.ItemTemplate
local ViewportFrame = PlayerGui.Inventory.ViewportFrame
local CarryWeightLabel = PlayerGui.Inventory.CarryWeight
local InventorySearchTextBox = PlayerGui.Inventory.InventorySearch

local PickUpEvent = script.Parent.PickUp

--// Inventory
local Inventory = {
	-- Settings prefixed by "_" are not meant to be changed.
	Settings = {
		INVENTORY_KEYBIND = Enum.KeyCode.H,
		ITEM_DROP_KEYBIND = Enum.KeyCode.Backspace,
		INVENTORY_SLOTS = 30,
		HOTBAR_SLOTS = 9,
		HOTBAR_KEYBINDS = {
			[1] = Enum.KeyCode.One,
			[2] = Enum.KeyCode.Two,
			[3] = Enum.KeyCode.Three,
			[4] = Enum.KeyCode.Four,
			[5] = Enum.KeyCode.Five,
			[6] = Enum.KeyCode.Six,
			[7] = Enum.KeyCode.Seven,
			[8] = Enum.KeyCode.Eight,
			[9] = Enum.KeyCode.Nine,
		},
		NEAR_TOOL_PICKUP_RANGE = 15,
		MAX_CARRY_WEIGHT = 15,
		_CURRENT_CARRY_WEIGHT = 0,
		EMPTY_SLOT_TRANSPARENCY = 1,
		SLOT_TRANSPARENCY = 0.8,
		DEFAULT_OUTLINE_COLOR = Color3.new(0.6980392157, 0.6941176471, 0.7450980392),
		EQUIPPED_OUTLINE_COLOR = Color3.new(0.792157, 0.772549, 1),
		_GLOBAL_TOOL_EQUIP_TICK = 0,
		GLOBA_TOOL_EQUIP_COOLDOWN = 0.15,
		TOOL_EQUIP_COOLDOWN = 0.2,
	},
	Items = {
		Inventory = {},
		Hotbar = {},
		NearItems = {},
	},
	Cooldowns = {
		Inventory = {},
		Hotbar = {},
	},
	Connections = {},
}

function Inventory:Toggle()
	InventoryFrame.Visible = not InventoryFrame.Visible
	GroundFrame.Visible = InventoryFrame.Visible
	ViewportFrame.Visible = InventoryFrame.Visible
	CarryWeightLabel.Visible = InventoryFrame.Visible
	SideHotbarFrame.Visible = GroundFrame.Visible
	HotbarFrame.Visible = not SideHotbarFrame.Visible
	InventorySearchTextBox.Visible = InventoryFrame.Visible

	CarryWeightLabel.Text = `Carry Weight: {self.Settings._CURRENT_CARRY_WEIGHT} / {self.Settings.MAX_CARRY_WEIGHT}`

	if not self.Connections.SearchConnection then
		self.Connections.SearchConnection = InventorySearchTextBox:GetPropertyChangedSignal("Text"):Connect(function()
			for _, item in pairs(InventoryItemsHolder:GetChildren()) do
				if item:IsA("TextButton") then
					if string.match(string.lower(item.Text), string.lower(InventorySearchTextBox.Text)) then
						item.Visible = true
					else
						item.Visible = false
					end
				end
			end
		end)
	end

	if not self.Connections.MonitorToolConnection then
		self.Connections.MonitorToolConnection = game:GetService("RunService").Heartbeat:Connect(function()
			for _, tool in pairs(workspace:GetChildren()) do
				if not tool:IsA("Tool") then
					continue
				end

				local handle = tool:FindFirstChild("Handle")
				if not handle then
					continue
				end

				local distance = (HumanoidRootPart.Position - handle.Position).Magnitude
				if distance <= self.Settings.NEAR_TOOL_PICKUP_RANGE then
					self:AddNearItem(tool)
				else
					if not self.Items.NearItems[tool] then
						continue
					end
					self:RemoveNearItem(tool)
				end
			end
		end)
	end

	for _, slot in pairs(SideHotbarFrame:GetChildren()) do
		if slot:IsA("TextButton") then
			if not self.Items.Hotbar[tonumber(slot.Name)] then
				slot.Visible = InventoryFrame.Visible
			end
		end
	end

	if InventoryFrame.Visible then
		local blur = Instance.new("BlurEffect", game.Lighting)
	else
		game.Lighting:FindFirstChildWhichIsA("BlurEffect"):Destroy()
	end
end

function Inventory:CreateSlots()
	for slotIndex = 1, self.Settings.HOTBAR_SLOTS do
		-- slot for the main hotbar
		local hotbarSlot = ItemTemplate:Clone()
		hotbarSlot.Name = slotIndex
		hotbarSlot.Parent = HotbarFrame
		hotbarSlot.Keybind.Text = slotIndex < 10 and tostring(slotIndex)
			or string.split(tostring(self.Settings.HOTBAR_KEYBINDS[slotIndex]), ".")[3]
		hotbarSlot.BackgroundTransparency = self.Settings.EMPTY_SLOT_TRANSPARENCY
		hotbarSlot.Visible = false

		-- slot for the side hotbar
		local sideHotbarSlot = ItemTemplate:Clone()
		sideHotbarSlot.Name = slotIndex
		sideHotbarSlot.Parent = SideHotbarFrame
		sideHotbarSlot.Keybind.Text = slotIndex < 10 and tostring(slotIndex)
			or string.split(tostring(self.Settings.HOTBAR_KEYBINDS[slotIndex]), ".")[3]
		sideHotbarSlot.BackgroundTransparency = self.Settings.EMPTY_SLOT_TRANSPARENCY
		sideHotbarSlot.Visible = false
	end

	for slotIndex = 1, self.Settings.INVENTORY_SLOTS do
		local hotbarSlot = ItemTemplate:Clone()
		hotbarSlot.Name = slotIndex
		hotbarSlot.Parent = InventoryItemsHolder
		hotbarSlot.BackgroundTransparency = self.Settings.EMPTY_SLOT_TRANSPARENCY
		hotbarSlot.Visible = true
	end
end

function Inventory:RemoveNearItem(tool)
	if not tool then
		return
	end

	local nearItemFrame = self.Items.NearItems[tool]
	if nearItemFrame then
		self:_DisconnectSlot(nearItemFrame)
		nearItemFrame:Destroy()
	end
	self.Items.NearItems[tool] = nil

	print("Removed item:", tool.Name)
end

function Inventory:AddNearItem(tool)
	if not tool then
		return
	end

	if self.Items.NearItems[tool] then
		return
	end

	local nearItemFrame = ItemTemplate:Clone()
	nearItemFrame.Name = tool.Name
	nearItemFrame.Parent = GroundItemsHolder
	self:_SetToolSlot(nearItemFrame, tool)

	self.Items.NearItems[tool] = nearItemFrame
	self.Connections[nearItemFrame] = {}
	self.Connections[nearItemFrame].ClickConnection = nearItemFrame.MouseButton1Click:Connect(function()
		if tool and tool:IsDescendantOf(workspace) then
			PickUpEvent:FireServer(tool)
			PickUpEvent.OnClientEvent:Once(function()
				self:RemoveNearItem(tool)
			end)
		end
	end)
	print("Added item:", tool.Name)
end

function Inventory:AddItem(tool, parent, assignedSlot)
	-- Check if the player already has this item.
	local item = self:FindItem(tool)
	if item then
		return
	end

	-- Check if can pick up the tool with the weight.
	local weight = tool:GetAttribute("Weight") or 0
	if not self:CompareCarryWeight(weight) then
		local handle = tool:FindFirstChild("Handle")
		if handle then
			local rightGrip = Character:FindFirstChild("RightHand").RightGrip
			if rightGrip then
				rightGrip:Destroy()
			end

			handle.CFrame = Character:GetPrimaryPartCFrame() * CFrame.new(4, 0, 0)
		end

		tool.Parent = workspace

		return
	end
	self:AddCarryWeight(weight)

	-- Add the new item.
	local length = 0
	for _, _ in pairs(self.Items.Hotbar) do
		length += 1
	end

	local currentParent = "nil"
	local slot = 0
	if length == self.Settings.HOTBAR_SLOTS or parent == "Inventory" then
		currentParent = "Inventory"
		slot = self:GetInventoryEmptySlot()
		self.Items.Inventory[slot] = tool

		tool:SetAttribute("Parent", "Inventory")
	else
		currentParent = "Hotbar"
		slot = assignedSlot or self:GetHotbarEmptySlot()
		self.Items.Hotbar[slot] = tool
		tool:SetAttribute("Parent", "Hotbar")
	end
	tool:SetAttribute("Equipped", false)

	-- Set up the slot.
	local itemFrame, sideItemFrame
	if currentParent == "Hotbar" then
		itemFrame = HotbarFrame[slot]
		sideItemFrame = SideHotbarFrame[slot]
	else
		itemFrame = InventoryItemsHolder[slot]
	end
	--[[if slot > 0 then
		itemFrame = HotbarFrame[slot]
		sideItemFrame = SideHotbarFrame[slot]
	else
		itemFrame = ItemTemplate:Clone()
		itemFrame.Name = tool.Name
		itemFrame.Parent = InventoryItemsHolder
	end]]

	self:_SetToolSlot(itemFrame, tool)
	if self.Connections[itemFrame] then
		self:_DisconnectSlot(itemFrame)
	end
	self.Connections[itemFrame] = {}

	-- Handle equipping logic
	local function UnequipTools()
		for _, equippedTools in pairs(Character:GetChildren()) do
			if equippedTools:IsA("Tool") then
				equippedTools:SetAttribute("Equipped", false)
			end
		end
		for _, hotbarItemSlot in pairs(HotbarFrame:GetChildren()) do
			if not hotbarItemSlot:IsA("TextButton") then
				continue
			end
			self:_SetSlotOutlineColor(hotbarItemSlot, false)
		end

		Humanoid:UnequipTools()
	end
	local function EquipTool(toolToEquip)
		toolToEquip:SetAttribute("Equipped", true)
		Humanoid:EquipTool(toolToEquip)
	end
	local function HandleEquip(actionName, inputState)
		if inputState ~= Enum.UserInputState.Begin then
			return
		end
		-- Cooldown
		if
			(tick() - (self.Cooldowns[itemFrame] or 0) >= self.Settings.TOOL_EQUIP_COOLDOWN)
			and (tick() - self.Settings._GLOBAL_TOOL_EQUIP_TICK >= self.Settings.GLOBA_TOOL_EQUIP_COOLDOWN)
		then
			self.Settings._GLOBAL_TOOL_EQUIP_TICK = tick()
			self.Cooldowns[itemFrame] = tick()

			-- Handling
			local toolToHandle
			if self.Items.Hotbar[slot] == tool then
				toolToHandle = tool
			end
			if not toolToHandle then
				return
			end
			if toolToHandle:GetAttribute("Equipped") then
				UnequipTools()
				toolToHandle:SetAttribute("Equipped", false)
				self:_SetSlotOutlineColor(itemFrame, false)
			else
				UnequipTools()
				EquipTool(toolToHandle)
				self:_SetSlotOutlineColor(itemFrame, true)
			end
		end

		return Enum.ContextActionResult.Pass
	end

	if sideItemFrame then
		self:_SetToolSlot(sideItemFrame, tool)
		if self.Connections[sideItemFrame] then
			self:_DisconnectSlot(sideItemFrame)
		end
		self.Connections[sideItemFrame] = {}

		-- Click to unequip
		self.Connections[sideItemFrame].ClickConnection = sideItemFrame.MouseButton1Click:Connect(function()
			if InventoryFrame.Visible then
				if tool:GetAttribute("Parent") == "Hotbar" then
					UnequipTools()
					self.Items.Hotbar[slot] = nil
					self:_SetSlotEmpty(sideItemFrame)
					self:_DisconnectSlot(sideItemFrame)

					self:_SetSlotEmpty(itemFrame)
					self:_DisconnectSlot(itemFrame)
					itemFrame.Visible = false

					local weight = tool:GetAttribute("Weight") or 0
					self:SubtractCarryWeight(weight)

					self:AddItem(tool, "Inventory")
				end
			end
		end)
	end

	self.Connections[itemFrame].ClickConnection = itemFrame.MouseButton1Click:Connect(function()
		if tool:GetAttribute("Parent") == "Inventory" then
			local hotbarSlot = self:GetHotbarEmptySlot()
			if hotbarSlot ~= 0 then
				self.Items.Inventory[slot] = nil
				self:_SetSlotEmpty(itemFrame)
				self:_DisconnectSlot(itemFrame)

				local weight = tool:GetAttribute("Weight") or 0
				self:SubtractCarryWeight(weight)

				self:AddItem(tool, "Hotbar", hotbarSlot)
			end

			return
		end

		-- Click to equip.
		HandleEquip("Equip", Enum.UserInputState.Begin)
	end)

	-- If the tool is in the hotbar, bind the respective key.
	if currentParent == "Hotbar" and slot > 0 then
		ContextActionService:BindAction(slot .. "Equip", HandleEquip, false, self.Settings.HOTBAR_KEYBINDS[slot])
	end

	self.Connections[itemFrame].DestroyingConnection = tool.AncestryChanged:Connect(function(_, newParent)
		if newParent == Player.Backpack or newParent == Character then
			return
		end

		task.wait(1)
		if not tool:IsDescendantOf(Player) or not tool:IsDescendantOf(Character) then
			if tool:GetAttribute("Equipped") then
				UnequipTools()
			end
			if tool:GetAttribute("Parent") == "Inventory" then
				self.Items.Inventory[slot] = nil
				self:_SetSlotEmpty(itemFrame)
			else
				self.Items.Hotbar[slot] = nil
				self:_SetSlotEmpty(itemFrame)
				self:_SetSlotEmpty(sideItemFrame)

				itemFrame.Visible = false
			end

			local weight = tool:GetAttribute("Weight") or 0
			self:SubtractCarryWeight(weight)

			self:_DisconnectSlot(itemFrame)
			self:_DisconnectSlot(sideItemFrame)
		end
	end)
end

function Inventory:CompareCarryWeight(weight)
	if self.Settings._CURRENT_CARRY_WEIGHT > self.Settings.MAX_CARRY_WEIGHT then
		return false
	end

	if (self.Settings._CURRENT_CARRY_WEIGHT + weight) > self.Settings.MAX_CARRY_WEIGHT then
		return false
	end

	return true
end

function Inventory:SubtractCarryWeight(weight)
	if weight <= 0 then
		return
	end

	self.Settings._CURRENT_CARRY_WEIGHT =
		math.clamp(self.Settings._CURRENT_CARRY_WEIGHT - weight, 0, self.Settings.MAX_CARRY_WEIGHT)
	CarryWeightLabel.Text = `Carry Weight: {self.Settings._CURRENT_CARRY_WEIGHT} / {self.Settings.MAX_CARRY_WEIGHT}`
end

function Inventory:AddCarryWeight(weight)
	if weight <= 0 then
		return
	end

	self.Settings._CURRENT_CARRY_WEIGHT =
		math.clamp(self.Settings._CURRENT_CARRY_WEIGHT + weight, 0, self.Settings.MAX_CARRY_WEIGHT)
	CarryWeightLabel.Text = `Carry Weight: {self.Settings._CURRENT_CARRY_WEIGHT} / {self.Settings.MAX_CARRY_WEIGHT}`
end

function Inventory:GetInventoryEmptySlot()
	for i = 1, self.Settings.INVENTORY_SLOTS do
		if self.Items.Inventory[i] ~= nil then
			continue
		end

		return i
	end

	return 0
end

function Inventory:GetHotbarEmptySlot()
	for i = 1, self.Settings.HOTBAR_SLOTS do
		if self.Items.Hotbar[i] ~= nil then
			continue
		end

		return i
	end

	return 0
end

function Inventory:FindItem(tool)
	for index, item in pairs(self.Items.Hotbar) do
		if item == tool then
			return item, "Hotbar", index
		end
	end

	for index, item in pairs(self.Items.Inventory) do
		if item == tool then
			return item, "Inventory", index
		end
	end

	return nil
end

function Inventory:_SetToolSlot(itemFrame, tool)
	if not itemFrame or not tool then
		return
	end
	itemFrame.Text = tool.Name
	itemFrame.BackgroundTransparency = self.Settings.SLOT_TRANSPARENCY
	itemFrame.Visible = true
end

function Inventory:_SetSlotEmpty(itemFrame)
	if not itemFrame then
		return
	end

	itemFrame.Text = ""
	itemFrame.BackgroundTransparency = self.Settings.EMPTY_SLOT_TRANSPARENCY
end

function Inventory:_SetSlotOutlineColor(itemFrame, equipped)
	if itemFrame:IsA("UIGridLayout") then
		return
	end

	if equipped then
		itemFrame.Outline.ImageColor3 = self.Settings.EQUIPPED_OUTLINE_COLOR
	else
		itemFrame.Outline.ImageColor3 = self.Settings.DEFAULT_OUTLINE_COLOR
	end
end

function Inventory:_DisconnectSlot(slot: GuiBase)
	if not self.Connections[slot] then
		return
	end

	for i, con in pairs(self.Connections[slot]) do
		if typeof(con) == "RBXScriptConnection" then
			con:Disconnect()
		end
		if typeof(con) == "thread" then
			task.cancel(con)
		end

		self.Connections[slot][i] = nil
	end
end

return Inventory
