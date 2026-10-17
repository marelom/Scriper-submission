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

local function areAllShipsSunk(shipsHealth)
	for _, health in pairs(shipsHealth) do -- simple loop that checks if every ship has more than 0 health, if it doesnt that menas every ship has been sunk and the player lost
		if health > 0 then return false end
	end
	return true	
end

local function createEmptyBoard()
	local newBoard = {} -- initiate the board
	for x = 1, gridWidth do -- from 1 to  6
		newBoard[x] = {} -- we create the rows in here
		for y = 1, gridHeight do
			newBoard[x][y] = { hasShip = false, isAttacked = false, shipId = nil } -- we create each cell and give its statements
		end	
	end
	return newBoard
end

local function getTableModel(seat)
	if not seat then return nil end
	local current = seat
	while current and current.Parent ~= workspaceTables do -- since the seat might be nested i did a loop that just goes up by a parent and checks if its the folder, if it is then it must be the table model
		current = current.Parent
	end
	return current
end

local function updateTableText(tableModel, text, Colorr) -- updates a text inside each table model
	local BillboardGui = tableModel:FindFirstChild("NametagTable") -- its inside each table model
	if not BillboardGui then return end
	
	local billboardText = BillboardGui.Properties.Player.Label -- each billboard gui has the same hierarchy and names
	
	billboardText.Text = text
	billboardText.TextColor3 = Colorr 
	
end

local function StartMatch(tableModel, player1, player2)
	local prof1 = ProfileManager.Profiles[player1] -- profilemanager is a script that uses profileservice to save variables or lists that i want to put in the datastore. In the profiles theres a profile for each player in the server
	local prof2 = ProfileManager.Profiles[player2]

	local p1Ships = prof1 and prof1.Data.EquippedShips or {"Cruiser", "Destroyer"} -- in case it fails go use the default ones
	local p2Ships = prof2 and prof2.Data.EquippedShips or {"Cruiser", "Destroyer"}

	matches[tableModel] = {
		turn = player1,
		player1 = player1,
		player2 = player2,
		phase = "Placement", 

		[player1] = { equippedShips = p1Ships, placedShips = {}, shipsHealth = {}, isReady = false, boardData = createEmptyBoard() }, -- for each player we initialize all their variables so that if we need to change them we can just get the player and if theyre in match and we can check everything
		[player2] = { equippedShips = p2Ships, placedShips = {}, shipsHealth = {}, isReady = false, boardData = createEmptyBoard() }	
	}

	startMatchEvent:FireClient(player1, p1Ships, matches[tableModel].phase) -- after everything is ready i send a remote event to both so that the board cleans up the stuff from an earlier match and shows the board
	startMatchEvent:FireClient(player2, p2Ships, matches[tableModel].phase)
end

local function SetupTableSeats(tableModel)
	local seats = tableModel:GetDescendants() -- we get all children cause seats may have different names or are nested so if we get descendants we get everything
	local foundSeats = {}

	for _, item in ipairs(seats) do
		if item:IsA("Seat") then table.insert(foundSeats, item) end -- this loop checks how many seats there are by seeing if the item is a seat
	end	
	if #foundSeats < 2 then return end

	local seat1 = foundSeats[1]
	local seat2 = foundSeats[2]

	local function checkSeats()
		local occ1 = seat1.Occupant -- we use the occupant property from the seat item that gives you the player
		local occ2 = seat2.Occupant

		if occ1 and occ2 then -- this runs only if both seats have an occupant
			local player1 = game.Players:GetPlayerFromCharacter(occ1.Parent) -- we get the player's character
			local player2 = game.Players:GetPlayerFromCharacter(occ2.Parent)


			if player1 and player2 and not matches[tableModel] then -- if they arent in an active match then we call the startmatch function and update the table text
				StartMatch(tableModel, player1, player2)
				updateTableText(tableModel, "[Match In Progress]", Color3.fromRGB(85, 255, 0))
			end
		else -- this runs when someone left a seat
			
			local match = matches[tableModel]
			if match then
				if match.player1 then leftMatchEvent:FireClient(match.player1) end -- we clean up and take care to make anything invisible on the gui side
				if match.player2 then leftMatchEvent:FireClient(match.player2) end
				matches[tableModel] = nil -- we remove the match
			end
		end
		
		if matches[tableModel] then -- i did this cause after starting a match it should leave the function in the case that there are both players seated while if one left then i use the next if statements to update the table text
			return
		end
		
		if occ1 or occ2 then -- if only one is still there then update to 1
			updateTableText(tableModel, "[1/2 Players]", Color3.fromRGB(255, 255, 255))
		end
		if not occ1 and not occ2 then -- if neither is there then update to 0
			updateTableText(tableModel, "[0/2 Players]", Color3.fromRGB(255, 255, 255))
		end
	end

	seat1:GetPropertyChangedSignal("Occupant"):Connect(checkSeats) -- this connects the function to when the occupant property ever changes
	seat2:GetPropertyChangedSignal("Occupant"):Connect(checkSeats)
end

-- Processes ship placement requests from clients
placeShipsEvent.OnServerEvent:Connect(function(player, clientPlacedShips)
	local char = player.Character
	if not char or not char:FindFirstChild("Humanoid") then return end

	local tableModel = getTableModel(char.Humanoid.SeatPart) -- this is the seat
	local match = matches[tableModel] -- we can find on what match they are based on the table model
	if not match or match.phase ~= "Placement" then return end -- its separated in phases since at the start the buttons are used to place the ships and then it will be used to attack that button also the phase gets sent to the local script

	local playerData = match[player]
	playerData.placedShips = clientPlacedShips -- clientplaced ships give you the key which is the ship's name and the values which are all the coordinates in the grid that occupies
	playerData.shipsHealth = {}

	for shipId, tileArray in pairs(clientPlacedShips) do -- this loop gets all the ships and their tiels that have been placed
		local maxHealth = ShipData.Ships[shipId] and ShipData.Ships[shipId].Health -- shipdata is like a library that gives you all information about each ship so we can get their health which corresponds to the number of tiles a ship has
		playerData.shipsHealth[shipId] = maxHealth -- we insert the ship's name and the health
		for _, tileString in ipairs(tileArray) do -- tile array is something like this: (1_2), (2_2), (3_2)
			local coords = string.split(tileString, "_") -- we take off the _ so we can get the x and y in the next line
			local x, y = tonumber(coords[1]), tonumber(coords[2])

			if x and y and x >= 1 and x <= gridWidth and y >= 1 and y <= gridHeight then -- this makes sure that the ships are inside the boundaries of the board i check this both in the client and in here
				playerData.boardData[x][y].hasShip = true -- we add in each cell of the board data the hasShip
				playerData.boardData[x][y].shipId = shipId -- and also what ship it's from it will be used later in the attack event
			end
		end
	end
end)

attackEvent.OnServerEvent:Connect(function(player, tileB) -- this is when a button in the grid gets clicked in the attacking phase
	local char = player.Character
	if not char or not char:FindFirstChild("Humanoid") then return end

	local tableModel = getTableModel(char.Humanoid.SeatPart)
	local match = matches[tableModel] -- we did the same things as before
	if not match or match.phase ~= "Attacking" or match.turn ~= player then return end -- this checks if its not your turn or if the phase isnt attacking so it doesnt run

	local defender = (player == match.player1) and match.player2 or match.player1 -- this is like an if statement since the statement in the parenthesis is true if the player is player so it will give you player 2 if its false then the and statement goes wrong and it goes in the or statement and says it player 1 
	local defenderData = match[defender] 

	local coords = string.split(tileB, "_") -- everytime a tile is clicked we send this event and we also send the tile id which could be like 6_4
	local x, y = tonumber(coords[1]), tonumber(coords[2]) 

	if not x or not y or not defenderData.boardData[x] or not defenderData.boardData[x][y] then return end -- if this  tile doesnt exist then we leave the function this is just for like cheating controls
	local cell = defenderData.boardData[x][y] -- this is the attacked cell

	if cell.isAttacked then return end -- if it has been already attacked then you cant attack it so we leave the function
	cell.isAttacked = true -- if it didnt leave the function then isAttacked is false so we turn it into true

	if cell.hasShip then -- we find the name of the ship, that theres an else statememnt at the end
		local hitShipId = cell.shipId -- we get the name of the ship
		defenderData.shipsHealth[hitShipId] -= 1 -- now we can get from the name of the ship its health which for example is 3 and we take off 1

		if defenderData.shipsHealth[hitShipId] <= 0 then -- this check is a ship has been fully sunk cause if it doesnt have anymore health then it doesnt have any tiles left it also has an else statement at the end
			infoEvent:FireClient(player, "SUNK", tileB) -- we send an event for when a ship sunks this is for the player who sunk the ship
			infoEvent:FireClient(defender, "YOUR_SHIP_SUNK", tileB) -- this is for the player who's ship got sunk

			if areAllShipsSunk(defenderData.shipsHealth) then -- this checks if all the ships have 0 health from the function we mentioned at the top
				match.phase = "Finished" -- then the match is finished
				
				local AnimId = "rbxassetid://507770239"
				local profile = ProfileManager.Profiles[player]
				if profile then 
					profile.Data.leaderstats.Coins += 100 -- we give money to the winner

					profile.Data.leaderstats.Wins += 1 -- and also a win

					local DataStoreService = game:GetService("DataStoreService") -- this is for a leaderboard system that needs an ordered data store so we send it to the leaderboard's data store too
					local winsODS = DataStoreService:GetOrderedDataStore("WinsLeaderboard")

					pcall(function()
						winsODS:SetAsync("Wins_" .. player.UserId, profile.Data.leaderstats.Wins) -- this connects the wins on the leaderboard with the player's total wins
					end)
					-- ------------------------------------
				end

				
				if profile then
					AnimId = profile.Data.EquippedAnimation[1] -- if player has an equipped animation then we use his instead we keep the one thats already been referenced
				end
				
				local loserProfile = ProfileManager.Profiles[defender]
				
				profile.Data.currentStreak += 1 -- we update a streak that when you join is always 0
				
				if loserProfile then
					loserProfile.Data.currentStreak = 0 -- if the player had a streak then they lose it if they didnt its still 0
				end
				
				if profile.Data.currentStreak > profile.Data.leaderstats.Streak then
					profile.Data.leaderstats.Streak = profile.Data.currentStreak -- Streak is actually your highest streaj and this checks if the current streak is higher than your highest streak if it is then we update the streak number to be the current streak
				end
				
				local nametag = player.Character.Head:FindFirstChild("Nametag") -- every player gets a nametag that also has a nametag text to showcase their current streak
				
				nametag.Properties.List.streakvalueframe.Visible = true
				nametag.Properties.List.streakvalueframe.valuelabel.Text = "[Streak: " .. profile.Data.currentStreak .. "]" -- this shows your streak
				
				local loserNametag = defender.Character.Head:FindFirstChild("Nametag")
				
				loserNametag.Properties.List.streakvalueframe.Visible = false
				loserNametag.Properties.List.streakvalueframe.valuelabel.Text = "[Streak: " .. loserProfile.Data.currentStreak .. "]" -- this hides your streak if you lost
				
				
				GameOverEvent:FireClient(player, "Won The Match", player, AnimId) -- basically in the game over event we do a simple cutscene showcasing the player dancing with their emote
				GameOverEvent:FireClient(defender, "Lost The Match", player, AnimId)



				local p1 = match.player1
				local p2 = match.player2 -- this saves the players before removing them from matches 

				task.delay(10, function() -- this is the cutscene's duration
					if p1 and p1.Character then
						local hum = p1.Character:FindFirstChildOfClass("Humanoid") -- this makes the p1 get up from their seats by removing the weld
						if hum and hum.SeatPart then
							local weld = hum.SeatPart:FindFirstChild("SeatWeld")
							if weld then weld:Destroy() end
						end
					end

					if p2 and p2.Character then
						local hum = p2.Character:FindFirstChildOfClass("Humanoid") -- while this is the same thing for the other player
						if hum and hum.SeatPart then
							local weld = hum.SeatPart:FindFirstChild("SeatWeld")
							if weld then weld:Destroy() end
						end
					end

					if p1 then endMatchEvent:FireClient(p1) end -- we send an event to change the ui
					if p2 then endMatchEvent:FireClient(p2) end

					matches[tableModel] = nil -- and we remove the match
				end)
					
				return -- and exit the function since the match is finished
			end
		else
			infoEvent:FireClient(player, "X", tileB) -- this is the else statement for the if the ship's health is smaller than 0 cause if it is then it means you just hit the ship but didnt sunk it
			infoEvent:FireClient(defender, "DEFENDER_HIT", tileB)
		end
	else
		infoEvent:FireClient(player, "O", tileB) -- this is the else statememnt for if cell.hasShip so if it doesnt then the player missed 
		infoEvent:FireClient(defender, "DEFENDER_MISS", tileB)
	end

	match.turn = defender -- this only runs in case the match hasnt finished and it swaps the turns
	changeTurnEvent:FireClient(player, match.turn) -- and updates the ui
	changeTurnEvent:FireClient(defender, match.turn)
end)


playerReadyEvent.OnServerEvent:Connect(function(player) -- basically when players have finished placing their ships they have to press a button to say theyre ready and that initiates the placedships event and also changed the phase to attacking
	local char = player.Character
	if not char or not char:FindFirstChild("Humanoid") then return end

	local tableModel = getTableModel(char.Humanoid.SeatPart)
	local match = matches[tableModel]
	if not match or match.phase ~= "Placement" then return end

	match[player].isReady = true -- if they clicked on the button then it becomes true

	local p1Ready = match[match.player1].isReady
	local p2Ready = match[match.player2].isReady

	if p1Ready and p2Ready then -- if both clicked ready then we can start the match
		match.phase = "Attacking"
		startBattleEvent:FireClient(match.player1, match.turn, match.phase) -- we update the ui
		startBattleEvent:FireClient(match.player2, match.turn, match.phase)
	end
end)

for _, child in ipairs(workspaceTables:GetChildren()) do -- this is the initial loop that connects for every table model the setuptableseats function
	if child:IsA("Model") then SetupTableSeats(child) end
end

workspaceTables.ChildAdded:Connect(function(child) -- this is in case a table gets added in tables folder and we do the same thing as before
	if child:IsA("Model") then SetupTableSeats(child) end
end)
