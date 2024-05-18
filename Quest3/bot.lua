-- Module to store game state and handle actions
local Bot = {
    LatestGameState = {},  -- Stores all game data
    InAction = false,      -- Prevents your bot from doing multiple actions
    colors = {
        red = "\27[31m",
        green = "\27[32m",
        blue = "\27[34m",
        reset = "\27[0m",
        gray = "\27[90m"
    }
}

-- Checks if two points are within a given range.
local function inRange(x1, y1, x2, y2, range)
    return math.abs(x1 - x2) <= range and math.abs(y1 - y2) <= range
end

-- Decide the next action based on player proximity, energy, health, and game map analysis.
local function decideNextAction()
    local player = Bot.LatestGameState.Players[ao.id]
    local targetInRange = false
    local bestTarget = nil

    for target, state in pairs(Bot.LatestGameState.Players) do
        if target ~= ao.id and inRange(player.x, player.y, state.x, state.y, 1) then
            targetInRange = true
            if not bestTarget or state.health < bestTarget.health or 
                (state.health == bestTarget.health and inRange(player.x, player.y, state.x, state.y, 1) < inRange(player.x, player.y, bestTarget.x, bestTarget.y, 1)) then
                bestTarget = state
            end
        end
    end

    if player.energy > 5 and targetInRange then
        print(Bot.colors.red .. "Player in range. Attacking." .. Bot.colors.reset)
        ao.send({
            Target = Game,
            Action = "PlayerAttack",
            Player = ao.id,
            AttackEnergy = tostring(player.energy),
        })
    else
        print(Bot.colors.red .. "No player in range or low energy. Moving randomly." .. Bot.colors.reset)
        local directions = {"Up", "Down", "Left", "Right"}
        local randomIndex = math.random(#directions)
        ao.send({Target = Game, Action = "PlayerMove", Player = ao.id, Direction = directions[randomIndex]})
    end
    Bot.InAction = false
end

local function handleEvent(msg)
    if msg.Event == "Started-Waiting-Period" then
        ao.send({Target = ao.id, Action = "AutoPay"})
    elseif (msg.Event == "Tick" or msg.Event == "Started-Game") and not Bot.InAction then
        Bot.InAction = true
        ao.send({Target = Game, Action = "GetGameState"})
    elseif Bot.InAction then
        print("Previous action still in progress. Skipping.")
    end
    print(Bot.colors.green .. msg.Event .. ": " .. msg.Data .. Bot.colors.reset)
end

local function handleTick()
    if not Bot.InAction then
        Bot.InAction = true
        print(Bot.colors.gray .. "Getting game state..." .. Bot.colors.reset)
        ao.send({Target = Game, Action = "GetGameState"})
    else
        print("Previous action still in progress. Skipping.")
    end
end

local function handleAutoPay()
    print("Auto-paying confirmation fees.")
    ao.send({Target = Game, Action = "Transfer", Recipient = Game, Quantity = "1000"})
end

local function handleUpdateGameState(msg)
    local json = require("json")
    Bot.LatestGameState = json.decode(msg.Data)
    ao.send({Target = ao.id, Action = "UpdatedGameState"})
    print("Game state updated. Print 'LatestGameState' for detailed view.")
end

local function handleDecideNextAction()
    if Bot.LatestGameState.GameMode ~= "Playing" then
        Bot.InAction = false
        return
    end
    print("Deciding next action.")
    decideNextAction()
    ao.send({Target = ao.id, Action = "Tick"})
end

local function handleReturnAttack(msg)
    if not Bot.InAction then
        Bot.InAction = true
        local playerEnergy = Bot.LatestGameState.Players[ao.id].energy
        if playerEnergy == nil then
            print(Bot.colors.red .. "Unable to read energy." .. Bot.colors.reset)
            ao.send({Target = Game, Action = "Attack-Failed", Reason = "Unable to read energy."})
        elseif playerEnergy == 0 then
            print(Bot.colors.red .. "Player has insufficient energy." .. Bot.colors.reset)
            ao.send({Target = Game, Action = "Attack-Failed", Reason = "Player has no energy."})
        else
            print(Bot.colors.red .. "Returning attack." .. Bot.colors.reset)
            ao.send({Target = Game, Action = "PlayerAttack", Player = ao.id, AttackEnergy = tostring(playerEnergy)})
        end
        Bot.InAction = false
        ao.send({Target = ao.id, Action = "Tick"})
    else
        print("Previous action still in progress. Skipping.")
    end
end

-- Register handlers
Handlers.add("PrintAnnouncements", Handlers.utils.hasMatchingTag("Action", "Announcement"), handleEvent)
Handlers.add("GetGameStateOnTick", Handlers.utils.hasMatchingTag("Action", "Tick"), handleTick)
Handlers.add("AutoPay", Handlers.utils.hasMatchingTag("Action", "AutoPay"), handleAutoPay)
Handlers.add("UpdateGameState", Handlers.utils.hasMatchingTag("Action", "GameState"), handleUpdateGameState)
Handlers.add("decideNextAction", Handlers.utils.hasMatchingTag("Action", "UpdatedGameState"), handleDecideNextAction)
Handlers.add("ReturnAttack", Handlers.utils.hasMatchingTag("Action", "Hit"), handleReturnAttack)

return Bot
