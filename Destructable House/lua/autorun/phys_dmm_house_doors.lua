local allowedMaps = {
    ["phys_dmm_house_r"] = true,
    ["phys_dmm_house_r_ni"] = true
}

local addonEnabled = true -- Default state: enabled

CreateConVar("db_enable_addon", 1, {FCVAR_SERVER_CAN_EXECUTE, FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Enable or disable the addon (1 to enable, 0 to disable)")

local function CheckAddonStatus()
    addonEnabled = GetConVar("db_enable_addon"):GetBool()
end

if not allowedMaps[game.GetMap()] then
    print("[DoorAddon] Addon disabled: Map is not allowed.")
    addonEnabled = false
end

if CLIENT then return end

-- Default door health
local DOOR_HEALTH = 100

-- Table to store individual door health
local doorHealthData = {}

CreateConVar("db_lockopen", 1, {FCVAR_SERVER_CAN_EXECUTE, FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Whether or not doors should be opened and unlocked after being shot open.")

local function InitializeDoorHealth()
    if not addonEnabled then return end
    for _, door in ipairs(ents.GetAll()) do
        if door:GetClass() == "prop_door_rotating" then
            local doorID = door:EntIndex()
            doorHealthData[doorID] = DOOR_HEALTH -- Initialize health for each door
            door:SetHealth(DOOR_HEALTH)
        end
    end
    print("[DoorAddon] Door health initialized.")
end

hook.Add("InitPostEntity", "PrepareDoorsOnMapLoad", function()
    InitializeDoorHealth()
end)

hook.Add("PreCleanupMap", "ResetDoorHealthOnCleanup", function()
    print("[DoorAddon] Resetting all door health due to map cleanup.")
    InitializeDoorHealth()
end)

cvars.AddChangeCallback("db_enable_addon", function(_, _, newValue)
    addonEnabled = tonumber(newValue) == 1
    print("[DoorAddon] Addon " .. (addonEnabled and "enabled" or "disabled"))
    if addonEnabled then
        InitializeDoorHealth()
    end
end)

local knockedDoors = {}

hook.Add("EntityTakeDamage", "HandleDoorDamage", function(door, dmginfo)
    if not addonEnabled then return end
    if door:GetClass() == "prop_door_rotating" and IsValid(door) then
        local doorID = door:EntIndex()
        if not doorHealthData[doorID] then
            doorHealthData[doorID] = DOOR_HEALTH -- Initialize health if not already set
        end

        -- Reduce health based on damage
        local damage = dmginfo:GetDamage()
        doorHealthData[doorID] = doorHealthData[doorID] - damage

        if doorHealthData[doorID] <= 0 and not (door.phys_door and IsValid(door.phys_door)) then
            local force = dmginfo:GetDamageForce()

            if dmginfo:IsDamageType(DMG_BLAST) then
                force = force * 1.5 -- Increase force significantly for explosions
            else
                force = force * 0.1 -- Reduce force for bullets
            end

            DestroyDoor(door, force)
        end
    end
end)

function DestroyDoor(door, force)
    if not addonEnabled then return end
    local dprop = ents.Create("prop_physics")
    dprop:SetCollisionGroup(COLLISION_GROUP_INTERACTIVE)
    dprop:SetMoveType(MOVETYPE_VPHYSICS)
    dprop:SetSolid(SOLID_BBOX)
    dprop:SetPos(door:GetPos() + Vector(0, 0, 2))
    dprop:SetAngles(door:GetAngles())
    dprop:SetModel(door:GetModel())
    dprop:SetSkin(door:GetSkin())
    dprop:Spawn()

    -- Apply force to fling the door
    local phys = dprop:GetPhysicsObject()
    if IsValid(phys) then
        phys:ApplyForceCenter(force + VectorRand() * 200)
    end

    table.insert(knockedDoors, door)
    door:SetNoDraw(true)
    door:SetNotSolid(true)

    if GetConVar("db_lockopen"):GetInt() > 0 then
        door:Fire("unlock", 0)
        door:Fire("open", 0)
    end

    door.phys_door = dprop
end

function ResetDoor(door)
    if not addonEnabled then return end
    local doorID = door:EntIndex()
    if IsValid(door) then
        door:SetNoDraw(false)
        door:SetNotSolid(false)
        doorHealthData[doorID] = DOOR_HEALTH -- Restore door health

        if IsValid(door.phys_door) then
            SafeRemoveEntity(door.phys_door)
            door.phys_door = nil
        end

        for i = #knockedDoors, 1, -1 do
            if knockedDoors[i] == door then
                table.remove(knockedDoors, i)
            end
        end
    end
end

function ResetAllDoors()
    if not addonEnabled then return end
    for i = #knockedDoors, 1, -1 do
        ResetDoor(knockedDoors[i])
    end
end

concommand.Add("db_resetdoors", function(ply)
    if not addonEnabled then return end
    if IsValid(ply) and not ply:IsAdmin() then return end
    ResetAllDoors()
end)

hook.Add("PlayerSay", "DoorCommands", function(ply, text)
    if not addonEnabled then return end
    text = string.lower(text)

    if string.sub(text, 1, 11) == "!checkdoor" then
        local tr = ply:GetEyeTrace()
        local door = tr.Entity
        if IsValid(door) and door:GetClass() == "prop_door_rotating" then
            ply:ChatPrint("That is a valid door!")
        else
            ply:ChatPrint("That is not a valid door!")
        end
        return false
    end

    if string.sub(text, 1, 11) == "!doorhealth" then
        local tr = ply:GetEyeTrace()
        local door = tr.Entity
        if IsValid(door) and door:GetClass() == "prop_door_rotating" then
            local doorID = door:EntIndex()
            ply:ChatPrint("That door's health is " .. (doorHealthData[doorID] or DOOR_HEALTH))
        else
            ply:ChatPrint("That is not a valid door!")
        end
        return false
    end

    if string.sub(text, 1, 11) == "!resetdoor" then
        if ply:IsAdmin() or ply:IsSuperAdmin() then
            ResetAllDoors()
        end
    end
end)
