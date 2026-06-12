local run_service = game:GetService("RunService")
local replicated_storage = game:GetService("ReplicatedStorage")
local players = game:GetService("Players")
local teams = game:GetService("Teams")

local neutral_team = teams.Neutral
local guards_team = teams.Guards
local prisoners_team = teams.Inmates
local criminals_team = teams.Criminals

local local_player = players.LocalPlayer

local character = local_player.Character
local camera = workspace.CurrentCamera

local config = {
    fade_time = 2500
}

local LINE_POOL_SIZE = 50
local linePool = table.create(LINE_POOL_SIZE)
local activeLines = table.create(LINE_POOL_SIZE)
local poolIndex = 0

local Vector2_new = Vector2.new
local Vector3_new = Vector3.new
local Color3_new = Color3.new
local math_clamp = math.clamp
local table_remove = table.remove
local table_insert = table.insert
local tick_fn = tick
local task_wait = task.wait

local gun_remotes = replicated_storage:WaitForChild("GunRemotes")
local shoot_event = gun_remotes:WaitForChild("ShootEvent")

local last_shot_time = 0

local function createLine()
    local line = Drawing.new("Line")
    line.Thickness = 3
    line.Color = Color3_new(1, 0, 0)
    line.Visible = false
    return line
end

local function getLine()
    poolIndex = poolIndex + 1
    if poolIndex > LINE_POOL_SIZE then
        poolIndex = 1
    end
    
    local line = linePool[poolIndex]
    if not line then
        line = createLine()
        linePool[poolIndex] = line
    end
    
    return line
end

local function worldToScreen(pos: Vector3): (Vector2, boolean)
    local screenPos, onScreen = camera:WorldToViewportPoint(pos)
    return Vector2_new(screenPos.X, screenPos.Y), onScreen
end

local function visualizeBullet(startPos: Vector3, endPos: Vector3)
    local line = getLine()
    
    local startTime = tick_fn()
    local fadeTimeSeconds = config.fade_time / 1000
    
    table_insert(activeLines, {
        line = line,
        startTime = startTime,
        fadeTime = fadeTimeSeconds,
        startPos = startPos,
        endPos = endPos
    })
end

local function updateLines(currentTime: number)
    local i = 1
    local active_count = #activeLines
    while i <= active_count do
        local data = activeLines[i]
        local elapsed = currentTime - data.startTime
        
        if elapsed >= data.fadeTime then
            data.line.Visible = false
            table_remove(activeLines, i)
            active_count = active_count - 1
        else
            local startScreen, startOnScreen = worldToScreen(data.startPos)
            local endScreen, endOnScreen = worldToScreen(data.endPos)
            
            if startOnScreen and endOnScreen then
                data.line.From = startScreen
                data.line.To = endScreen
                data.line.Visible = true
                
                local progress = elapsed / data.fadeTime
                data.line.Transparency = math_clamp(1 - progress, 0, 1)
            else
                data.line.Visible = false
            end
            
            i = i + 1
        end
    end
end

local check_team = function(player)
    local player_team = player.Team
    local local_team = local_player.Team
    
    if local_team == neutral_team then
        return false
    end
    
    if local_team == guards_team then
        if player_team == guards_team then
            return false
        end
        
        if player_team == prisoners_team then
            local player_char = player.Character
            if player_char then
                local hostile = player_char:GetAttribute("Hostile")
                if hostile then
                    return true
                end
                
                local entered_armory = player_char:GetAttribute("EnteredArmory")
                if entered_armory then
                    return true
                end
                
                local equipped_gun = player_char:GetAttribute("EquippedHostileTool")
                if equipped_gun then
                    return true
                end
            end
            return false
        end
        
        if player_team == criminals_team then
            return true
        end
        
        return false
    else
        if player_team == guards_team then
            return true
        end
        return false
    end
end

local is_target_visible = function(player)
    local player_character = player.Character
    local local_player_character = local_player.Character
    
    if not (player_character and local_player_character) then return false end
    
    local player_root = player_character:FindFirstChild("HumanoidRootPart")
    if not player_root then return false end
    
    local cast_points, ignore_list = {player_root.Position}, {local_player_character, player_character}
    local obscuring_parts = workspace.CurrentCamera:GetPartsObscuringTarget(cast_points, ignore_list)
    
    for _, part in ipairs(obscuring_parts) do
        if part.CanCollide and part.Transparency < 1 then
            return false
        end
    end
    
    return true
end

local shoot_at = function(player: Player): boolean?
    local tool = character:FindFirstChildOfClass("Tool")
    if not tool then
        return
    end
    
    if not check_team(player) then
        return
    end
    
    if not is_target_visible(player) then
        return
    end
    
    local player_char = player.Character
    if not player_char then
        return
    end
    
    local humanoid = player_char:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then
        return
    end
    
    local head = player_char:FindFirstChild("Head")
    if not head then
        return
    end
    
    local handle = tool:FindFirstChild("Handle")
    if not handle then
        return
    end
    
    local current_time = tick_fn()
    local fire_rate = tool:GetAttribute("FireRate") or 0.11
    
    if current_time - last_shot_time < fire_rate then
        return
    end
    
    local current_ammo = tool:GetAttribute("CurrentAmmo")
    local max_ammo = tool:GetAttribute("MaxAmmo")
    
    if current_ammo and current_ammo == 0 then
        if max_ammo then
            repeat
                task_wait(0.1)
                game:GetService("replicated_storage"):WaitForChild("GunRemotes"):WaitForChild("FuncReload"):InvokeServer()
                current_ammo = tool:GetAttribute("CurrentAmmo")
            until current_ammo == max_ammo
        else
            return
        end
    end
    
    local startPos = handle.Position
    local endPos = head.Position
    
    local range_attr = tool:GetAttribute("Range")
    if range_attr then
        local dx = endPos.X - startPos.X
        local dy = endPos.Y - startPos.Y
        local dz = endPos.Z - startPos.Z
        local distSq = dx*dx + dy*dy + dz*dz
        
        if distSq > range_attr * range_attr then
            return
        end
    end
    
    local direction = (endPos - startPos).Unit
    local distance = (endPos - startPos).Magnitude
    
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
    raycastParams.FilterDescendantsInstances = {character, player_char}
    
    local rayResult = workspace:Raycast(startPos, direction * distance, raycastParams)
    
    if rayResult then
        local hit_part = rayResult.Instance
        local can_collide = hit_part.CanCollide
        
        if can_collide then
            return
        end
    end
    
    visualizeBullet(startPos, endPos)
    
    local tool_name = tool.Name
    
    if tool_name == "Remington 870" then
        local args = {
            {
                {
                    startPos,
                    endPos,
                    head
                },
                {
                    startPos,
                    endPos,
                    head
                },
                {
                    startPos,
                    endPos,
                    head
                },
                {
                    startPos,
                    endPos,
                    head
                },
                {
                    startPos,
                    endPos,
                    head
                }
            }
        }
        shoot_event:FireServer(unpack(args))
    else
        local args = {
            {
                {
                    startPos,
                    endPos,
                    head
                }
            }
        }
        shoot_event:FireServer(unpack(args))
    end
    
    last_shot_time = current_time
    
    return true
end

local heartbeat_connection

heartbeat_connection = run_service.Heartbeat:Connect(function()
    local active_count = #activeLines
    if active_count > 0 then
        updateLines(tick_fn())
    end
    
    if not character then
        character = local_player.Character
        if not character then
            return
        end
    end
    
    local tool = character:FindFirstChildOfClass("Tool")
    if not tool then
        return
    end
    
    local players_array = players:Getplayers()
    local player_count = #players_array
    
    for i = 1, player_count do
        local player = players_array[i]
        if player ~= local_player then
            shoot_at(player)
        end
    end
end)

local_player.CharacterAdded:Connect(function(char)
    character = char
end)
