--[[ This Script is for a Battleship game that uses a board gui that has a 6x5 grid and each buttons has its own tile id that is written in : X_Y. 
Theres also a gui that gives you the ships to choose from and places the ships in the gird giving the clientplacedships array which you will see in the PlaceShipsEvent.]]
  
-- Variables and states
local rps = game:GetService("ReplicatedStorage")
local work = game:GetService("Workspace")
local attackEvent = rps:WaitForChild("AttackEvent")
local infoEvent = rps:WaitForChild("InfoEvent")
local startMatchEvent = rps:WaitForChild("StartMatchEvent")
local endMatchEvent = rps:WaitForChild("EndMatchEvent")
local workspaceTables = work:WaitForChild("Tables")
local sss = game:GetService("ServerScriptService")
local ProfileManager = require(sss.Services.ProfileManager)
local ShipData = require(rps.Ships.ShipData)
local placeShipsEvent = rps:WaitForChild("PlaceShipsEvent")
local GameOverEvent = rps:WaitForChild("GameOverEvent")
local playerReadyEvent = rps:WaitForChild("PlayerReadyEvent")
local startBattleEvent = rps:WaitForChild("StartBattleEvent") 
local changeTurnEvent = rps:WaitForChild("ChangeTurnEvent")
local leftMatchEvent = rps:WaitForChild("LeftDuringMatchEvent")

local gridWidth = 6
local gridHeight = 5
local matches = {}

-- Checks if all ships are destroyed
local function areAllShipsSunk(shipsHealth)
	for _, health in pairs(shipsHealth) do
		if health > 0 then return false end
	end
	return true	
end

-- Generates a blank grid array
local function createEmptyBoard()
	local newBoard = {}
	for x = 1, gridWidth do
		newBoard[x] = {}
		for y = 1, gridHeight do
			newBoard[x][y] = { hasShip = false, isAttacked = false, shipId = nil }
		end	
	end
	return newBoard
end

-- Locates the master table model
local function getTableModel(seat)
	if not seat then return nil end
	local current = seat
	while current and current.Parent ~= workspaceTables do
		current = current.Parent
	end
	return current
end

-- Updates the table text display
local function updateTableText(tableModel, text, Colorr)
	local BillboardGui = tableModel:FindFirstChild("NametagTable")
	if not BillboardGui then return end
	
	local billboardText = BillboardGui.Properties.Player.Label
	
	billboardText.Text = text
	billboardText.TextColor3 = Colorr
	
end

-- Initializes game data for both players
local function StartMatch(tableModel, player1, player2)
	local prof1 = ProfileManager.Profiles[player1]
	local prof2 = ProfileManager.Profiles[player2]

	local p1Ships = prof1 and prof1.Data.EquippedShips or {"Cruiser", "Destroyer"}
	local p2Ships = prof2 and prof2.Data.EquippedShips or {"Cruiser", "Destroyer"}

	matches[tableModel] = {
		turn = player1,
		player1 = player1,
		player2 = player2,
		phase = "Placement", 

		[player1] = { equippedShips = p1Ships, placedShips = {}, shipsHealth = {}, isReady = false, boardData = createEmptyBoard() },
		[player2] = { equippedShips = p2Ships, placedShips = {}, shipsHealth = {}, isReady = false, boardData = createEmptyBoard() }	
	}

	startMatchEvent:FireClient(player1, p1Ships, matches[tableModel].phase)
	startMatchEvent:FireClient(player2, p2Ships, matches[tableModel].phase)
end

-- Handles player seating logic
local function SetupTableSeats(tableModel)
	local seats = tableModel:GetDescendants()
	local foundSeats = {}

	for _, item in ipairs(seats) do
		if item:IsA("Seat") then table.insert(foundSeats, item) end
	end	
	if #foundSeats < 2 then return end

	local seat1 = foundSeats[1]
	local seat2 = foundSeats[2]

	local function checkSeats()
		local occ1 = seat1.Occupant
		local occ2 = seat2.Occupant

		if occ1 and occ2 then
			local player1 = game.Players:GetPlayerFromCharacter(occ1.Parent)
			local player2 = game.Players:GetPlayerFromCharacter(occ2.Parent)


			if player1 and player2 and not matches[tableModel] then
				StartMatch(tableModel, player1, player2)
				updateTableText(tableModel, "[Match In Progress]", Color3.fromRGB(85, 255, 0))
			end
		else
			-- Clears active game records securely
			local match = matches[tableModel]	
			if match then
				if match.player1 then leftMatchEvent:FireClient(match.player1) end
				if match.player2 then leftMatchEvent:FireClient(match.player2) end
				matches[tableModel] = nil	
			end
		end
		
		if matches[tableModel] then
			return
		end
		
		if occ1 or occ2 then
			updateTableText(tableModel, "[1/2 Players]", Color3.fromRGB(255, 255, 255))
		end
		if not occ1 and not occ2 then
			updateTableText(tableModel, "[0/2 Players]", Color3.fromRGB(255, 255, 255))
		end
	end

	seat1:GetPropertyChangedSignal("Occupant"):Connect(checkSeats)
	seat2:GetPropertyChangedSignal("Occupant"):Connect(checkSeats)
end

-- Processes ship placement requests from clients
placeShipsEvent.OnServerEvent:Connect(function(player, clientPlacedShips)
	local char = player.Character
	if not char or not char:FindFirstChild("Humanoid") then return end

	local tableModel = getTableModel(char.Humanoid.SeatPart)
	local match = matches[tableModel]
	if not match or match.phase ~= "Placement" then return end

	local playerData = match[player]
	playerData.placedShips = clientPlacedShips
	playerData.shipsHealth = {}

	for shipId, tileArray in pairs(clientPlacedShips) do
		local maxHealth = ShipData.Ships[shipId] and ShipData.Ships[shipId].Health
		playerData.shipsHealth[shipId] = maxHealth
		for _, tileString in ipairs(tileArray) do
			local coords = string.split(tileString, "_")
			local x, y = tonumber(coords[1]), tonumber(coords[2])
			-- Verifies grid boundary thresholds
			if x and y and x >= 1 and x <= gridWidth and y >= 1 and y <= gridHeight then
				playerData.boardData[x][y].hasShip = true
				playerData.boardData[x][y].shipId = shipId
			end
		end
	end
end)

-- Manages attack turns and data synchronization
attackEvent.OnServerEvent:Connect(function(player, tileB)
	local char = player.Character
	if not char or not char:FindFirstChild("Humanoid") then return end

	local tableModel = getTableModel(char.Humanoid.SeatPart)
	local match = matches[tableModel]
	if not match or match.phase ~= "Attacking" or match.turn ~= player then return end

	local defender = (player == match.player1) and match.player2 or match.player1
	local defenderData = match[defender]

	local coords = string.split(tileB, "_")
	local x, y = tonumber(coords[1]), tonumber(coords[2])

	if not x or not y or not defenderData.boardData[x] or not defenderData.boardData[x][y] then return end
	local cell = defenderData.boardData[x][y]

	if cell.isAttacked then return end
	cell.isAttacked = true

	if cell.hasShip then
		local hitShipId = cell.shipId
		defenderData.shipsHealth[hitShipId] -= 1

		if defenderData.shipsHealth[hitShipId] <= 0 then
			infoEvent:FireClient(player, "SUNK", tileB)
			infoEvent:FireClient(defender, "YOUR_SHIP_SUNK", tileB)

			if areAllShipsSunk(defenderData.shipsHealth) then
				-- Prevents any incoming attack requests immediately
				match.phase = "Finished"
				
				local AnimId = "rbxassetid://507770239"
				local profile = ProfileManager.Profiles[player]
				if profile then 
					profile.Data.leaderstats.Coins += 100 

					-- Increases win count inside the profile
					profile.Data.leaderstats.Wins += 1 

					-- Updates global leaderboard data storage online
					local DataStoreService = game:GetService("DataStoreService")
					local winsODS = DataStoreService:GetOrderedDataStore("WinsLeaderboard") 

					pcall(function()
						winsODS:SetAsync("Wins_" .. player.UserId, profile.Data.leaderstats.Wins)
					end)
				end

				if profile then
					AnimId = profile.Data.EquippedAnimation[1]
				end
				
				local loserProfile = ProfileManager.Profiles[defender]
				
				profile.Data.currentStreak += 1
				
				if loserProfile then
					loserProfile.Data.currentStreak = 0
				end
				
				if profile.Data.currentStreak > profile.Data.leaderstats.Streak then
					profile.Data.leaderstats.Streak = profile.Data.currentStreak
				end
				
				local nametag = player.Character.Head:FindFirstChild("Nametag")
				
				nametag.Properties.List.streakvalueframe.Visible = true
				nametag.Properties.List.streakvalueframe.valuelabel.Text = "[Streak: " .. profile.Data.currentStreak .. "]"
				
				local loserNametag = defender.Character.Head:FindFirstChild("Nametag")
				
				loserNametag.Properties.List.streakvalueframe.Visible = false
				loserNametag.Properties.List.streakvalueframe.valuelabel.Text = "[Streak: " .. loserProfile.Data.currentStreak .. "]"
				
				GameOverEvent:FireClient(player, "Won The Match", player, AnimId)
				GameOverEvent:FireClient(defender, "Lost The Match", defender, AnimId)
			end
		end
	end
end)
