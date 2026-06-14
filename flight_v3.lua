repeat task.wait() until game:IsLoaded()

getgenv().fly_config = {
    controls = {
        toggle = Enum.KeyCode.V,
        boost = Enum.KeyCode.LeftShift,
    },
    movement = {
        base_speed = 100,
        boost_multiplier = 5,
        acceleration = 5,
        turn_speed = 3,
        hover_force = 2.1,
        tilt = {
            forward_angle = 0,
            application_rate = 0,
        }
    },
    options = {
        noclip = true,
        disable_animations = true,
        gravity_enabled = false,
        notification_duration = 2,
    },
    debug = {
        enabled = false,
        show_velocity = false,
    }
}

local services = {
    user_input_service = nil,
    starter_gui = nil,
    run = nil,
    players = nil,
    debris = nil,
    core_gui = nil
}

local safe_getservice = function(service_name)
    local success, service = pcall(function()
        return cloneref(game:GetService(service_name))
    end)
    
    if success then
        return service
    else
        warn("[FUNC] safe_getservice: Failed to get service: " .. service_name)
        return nil
    end
end

services.user_input_service = safe_getservice("UserInputService")
services.starter_gui = safe_getservice("StarterGui")
services.run = safe_getservice("RunService")
services.players = safe_getservice("Players")
services.debris = safe_getservice("Debris")
services.core_gui = safe_getservice("CoreGui")

if not (services.user_input_service and services.run and services.players and services.core_gui) then
    warn("Flight V3: Critical services unavailable. Flight script cannot run.")
    return
end

local state = {
    camera = workspace.CurrentCamera,
    player = services.players.LocalPlayer,
    char = nil,
    root = nil,
    humanoid = nil,
    animator = nil,
    velocity = Vector3.new(),
    connection = nil,
    noclip_connection = nil,
    flying = false,
    current_tilt = 0,
    target_tilt = 0,
    forward_movement = false,
    safe_mode = false
}

local notify = function(title, text)
    if services.starter_gui then
        pcall(function()
            services.starter_gui:SetCore("SendNotification", {
                Title = title,
                Text = text,
                Duration = fly_config.options.notification_duration or 2
            })
        end)
    end
end

local set_char = function(char)
    if not char then return end
    
    state.char = char
    
    local success, result = pcall(function()
        local root = char:WaitForChild("HumanoidRootPart", 5)
        local humanoid = char:WaitForChild("Humanoid", 5)
        local animator = humanoid:FindFirstChildOfClass("Animator") or humanoid:WaitForChild("Animator", 2)
        
        return {
            root = root,
            humanoid = humanoid,
            animator = animator
        }
    end)
    
    if success and result.root and result.humanoid then
        state.root = result.root
        state.humanoid = result.humanoid
        state.animator = result.animator
    else
        warn("Flight V3: Character setup failed")
        state.safe_mode = true
    end
end

local disable_animations = function()
    if not fly_config.options.disable_animations then return end
    
    if state.animator then
        pcall(function()
            for _, track in pairs(state.animator:GetPlayingAnimationTracks()) do
                track:Stop()
            end
        end)
    end
end

local noclip = function()
    if not state.char then return end
    
    pcall(function()
        for _, part in pairs(state.char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end
    end)
end

local reset_collisions = function()
    if not state.char then return end
    
    pcall(function()
        for _, part in pairs(state.char:GetDescendants()) do
            if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                part.CanCollide = true
            end
        end
    end)
end

local calculate_move_vector = function()
    local baseVel = Vector3.new()
    local input = services.user_input_service
    local camera = state.camera
    
    if not input or not camera then return baseVel end
    
    if not input:GetFocusedTextBox() then
        if input:IsKeyDown(Enum.KeyCode.W) then
            baseVel = baseVel + (camera.CFrame.LookVector * fly_config.movement.base_speed)
            state.forward_movement = true
        end
        if input:IsKeyDown(Enum.KeyCode.S) then
            baseVel = baseVel - (camera.CFrame.LookVector * fly_config.movement.base_speed)
            state.forward_movement = true
        end
        if input:IsKeyDown(Enum.KeyCode.A) then
            baseVel = baseVel - (camera.CFrame.RightVector * fly_config.movement.base_speed)
        end
        if input:IsKeyDown(Enum.KeyCode.D) then
            baseVel = baseVel + (camera.CFrame.RightVector * fly_config.movement.base_speed)
        end
        if input:IsKeyDown(Enum.KeyCode.Space) then
            baseVel = baseVel + (camera.CFrame.UpVector * fly_config.movement.base_speed)
        end
        
        if input:IsKeyDown(fly_config.controls.boost) then
            baseVel = baseVel * fly_config.movement.boost_multiplier
        end
        
        if not (input:IsKeyDown(Enum.KeyCode.W) or input:IsKeyDown(Enum.KeyCode.S)) then
            state.forward_movement = false
        end
    end
    
    return baseVel
end

local flight = function(delta)
    if state.safe_mode then return end
    
    if not (state.root and state.humanoid) then return end
    
    local baseVel = calculate_move_vector()
    
    pcall(function()
        local root = state.root
        if not root or root.Anchored then return end
        
        state.humanoid:ChangeState(Enum.HumanoidStateType.Physics)
        state.humanoid.PlatformStand = true
        
        if fly_config.options.disable_animations then
            disable_animations()
        end
        
        state.velocity = state.velocity:Lerp(
            baseVel,
            math.clamp(delta * fly_config.movement.acceleration, 0, 1)
        )
        
        root.Velocity = state.velocity + Vector3.new(0, fly_config.movement.hover_force, 0)
        
        state.target_tilt = state.forward_movement and 
            math.rad(fly_config.movement.tilt.forward_angle) or 0
        
        state.current_tilt = state.forward_movement 
            and state.current_tilt + (state.target_tilt - state.current_tilt) * fly_config.movement.tilt.application_rate
            or 0
        
        root.RotVelocity = Vector3.new()
        
        local lookVector = state.camera.CFrame.LookVector
        
        local baseOrientation = CFrame.lookAt(
            root.Position, 
            root.Position + lookVector
        )
        
        local tiltRotation = CFrame.Angles(state.current_tilt, 0, 0)
        local targetOrientation = baseOrientation * tiltRotation
        
        root.CFrame = root.CFrame:Lerp(
            targetOrientation,
            math.clamp(delta * fly_config.movement.turn_speed, 0, 1)
        )
    end)
end

local get_or_create_debug_gui = function()
    if not services.core_gui then return nil end

    local screenGuiName = "FlightV3_DebugGui"
    local textLabelName = "FlightV3_DebugTextLabel"

    local screenGui = services.core_gui:FindFirstChild(screenGuiName)
    if not screenGui or not screenGui:IsA("ScreenGui") then
        if screenGui then screenGui:Destroy() end
        screenGui = Instance.new("ScreenGui")
        screenGui.Name = screenGuiName
        screenGui.ResetOnSpawn = false
        screenGui.Parent = services.core_gui
    end

    local textLabel = screenGui:FindFirstChild(textLabelName)
    if not textLabel or not textLabel:IsA("TextLabel") then
        if textLabel then textLabel:Destroy() end
        textLabel = Instance.new("TextLabel")
        textLabel.Name = textLabelName
        textLabel.Size = UDim2.new(0, 200, 0, 100)
        textLabel.Position = UDim2.new(0, 10, 0, 10)
        textLabel.BackgroundTransparency = 0.5
        textLabel.BackgroundColor3 = Color3.new(0, 0, 0)
        textLabel.TextColor3 = Color3.new(1, 1, 1)
        textLabel.TextXAlignment = Enum.TextXAlignment.Left
        textLabel.TextYAlignment = Enum.TextYAlignment.Top
        textLabel.Parent = screenGui
    end
    return textLabel
end

local update_debug = function()
    if not fly_config.debug.enabled then return end
    
    local debugText = get_or_create_debug_gui()
    if not debugText then return end

    pcall(function()
        local info = "Flight V3 Debug\n"
        if fly_config.debug.show_velocity and state.velocity then
            info = info .. "Velocity: " .. tostring(state.velocity.Magnitude) .. "\n"
        end
        info = info .. "Flying: " .. tostring(state.flying) .. "\n"
        info = info .. "Tilt: " .. tostring(math.deg(state.current_tilt)) .. "°\n"
        
        debugText.Text = info
    end)
end

local enable_flight = function()
    state.flying = true
    state.velocity = state.root and state.root.Velocity or Vector3.new()
    
    state.connection = services.run.Heartbeat:Connect(flight)
    
    if fly_config.options.noclip then
        state.noclip_connection = services.run.Stepped:Connect(noclip)
    end
    
    if not fly_config.options.gravity_enabled and state.humanoid then
        state.humanoid.UseJumpPower = false
    end
    
    if fly_config.debug.enabled then
        services.run.RenderStepped:Connect(update_debug)
    end
    
    notify("Flight V3", "Enabled")
end

local disable_flight = function()
    state.flying = false
    
    if state.connection then
        state.connection:Disconnect()
        state.connection = nil
    end
    
    if state.noclip_connection then
        state.noclip_connection:Disconnect()
        state.noclip_connection = nil
    end
    
    if state.humanoid then
        pcall(function()
            state.humanoid.PlatformStand = false
            state.humanoid:ChangeState(Enum.HumanoidStateType.Running)
            state.humanoid.UseJumpPower = true
        end)
    end
    
    reset_collisions()
    
    state.current_tilt = 0
    state.target_tilt = 0
    
    notify("Flight V3", "Disabled")
end

workspace.Changed:Connect(function(property)
    if property == "CurrentCamera" then
        state.camera = workspace.CurrentCamera
    end
end)

state.player.CharacterAdded:Connect(set_char)
if state.player.Character then
    set_char(state.player.Character)
end

services.user_input_service.InputBegan:Connect(function(input, processed)
    if processed then return end
    
    if input.KeyCode == fly_config.controls.toggle then
        if state.flying then
            disable_flight()
        else
            if state.root and state.humanoid then
                enable_flight()
            else
                notify("Flight V3", "Cannot fly - character not ready")
            end
        end
    end
end)

getgenv().updateFlightConfig = function(newConfig)
    for category, settings in pairs(newConfig) do
        if fly_config[category] then
            for setting, value in pairs(settings) do
                if fly_config[category][setting] ~= nil then
                    fly_config[category][setting] = value
                end
            end
        end
    end
    notify("Flight V3", "Configuration updated")
end

notify("Flight V3", "Loaded successfully")