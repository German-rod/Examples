--[[
	DataService

	Knit service responsible for player data management using ProfileStore.
	Handles profile loading, reconciliation, session lifecycle, and asynchronous access via Promises.
]]

--// Dependencies
local Knit = require(game:GetService('ReplicatedStorage').Packages.Knit)
local Promise = require(game:GetService('ReplicatedStorage').Packages.Promise)
local Signal = require(game:GetService('ReplicatedStorage').Packages.Signal)
local ProfileStore = require(game:GetService('ReplicatedStorage').Packages.ProfileStore)
local Players = game:GetService('Players')

--// Constants
local Profile_Template = require(script.ProfileTemplate)
local PlayerStore = ProfileStore.New('PlayerStore', Profile_Template)

--// Service
local DataService = Knit.CreateService{
	Name = 'DataService',
	
	ProfileLoaded = Signal.new(),
	Profiles = {}
}

--// Methods & Functions
function DataService:PlayerAdded(player)
	local profile = PlayerStore:StartSessionAsync(tostring(player.UserId), {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})
	
	if profile ~= nil then
		profile:AddUserId(player.UserId)
		profile:Reconcile() -- Fill in missing variables from Profile_Template
		
		profile.OnSessionEnd:Connect(function()
			self.Profiles[player] = nil
			player:Kick(`Profile session end - Please rejoin`)
		end)
		
		if player.Parent == Players then
			self.Profiles[player] = profile
			self.ProfileLoaded:Fire(player, profile)
		else
			-- The player has left before the profile session started
			profile:EndSession()
		end
	else
		player:Kick(`Profile load fail - Please rejoin`)
	end
end

function DataService:PlayerRemoved(player)
	local profile = self.Profiles[player]
	if profile ~= nil then
		profile:EndSession()
	end
end

function DataService:GetProfile(player)
	if not player then
		return nil
	end
	
	local profile = self.Profiles[player]
	if profile then
		return profile
	end
	
	return nil
end

function DataService:WaitForProfile(player)
	return Promise.new(function(resolve, reject, onCancel)
		local connection
		connection = self.ProfileLoaded:Connect(function(loadedPlayer, profile)
			if loadedPlayer == player then
				connection:Disconnect()
				resolve(profile)
			end
		end)

		onCancel(function()
			if connection then
				connection:Disconnect()
			end
			reject('WaitForProfile was cancelled')
		end)
	end)
end

--// Knit Lifecycle

function DataService:KnitStart()
	-- In case Players have joined the server earlier than this script ran:
	for _, player in Players:GetPlayers() do
		task.spawn(function()
			self:PlayerAdded(player)
		end)
	end
	
	-- Connections
	Players.PlayerAdded:Connect(function(player)
		self:PlayerAdded(player)
	end)
	
	Players.PlayerRemoving:Connect(function(player)
		self:PlayerRemoved(player)
	end)
end

return DataService
