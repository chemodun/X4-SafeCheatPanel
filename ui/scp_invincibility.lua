local ffi = require("ffi")
local C = ffi.C

ffi.cdef [[
    typedef uint64_t UniverseID;

    bool IsComponentClass(UniverseID componentid, const char* classname);
]]

local menu         = Helper.getMenu("MapMenu")
local interactMenu = Helper.getMenu("InteractMenu")

local scpInvincibility = {}

function scpInvincibility.join(scp)
  scpInvincibility.scp = scp
end

local function boolOf(value)
  return value == true or value == 1
end

-- The right-clicked ship or station while the Spawn tab is shown; another owner's only in extended mode.
local function getTarget()
  local scp = scpInvincibility.scp
  if menu.infoTableMode ~= "safeCheatPanel" or scp.tableMode ~= "scpObjectSpawn" then
    return nil
  end
  local component = interactMenu.componentSlot and interactMenu.componentSlot.component
  if component == nil or component == 0 then
    return nil
  end
  if C.IsComponentClass(component, "spacesuit") or not (C.IsComponentClass(component, "ship") or C.IsComponentClass(component, "station")) then
    return nil
  end
  local object = ConvertStringTo64Bit(tostring(component))
  if not IsValidComponent(object) then
    return nil
  end
  if not (GetComponentData(object, "isplayerowned") or scp.isExtendedMode()) then
    return nil
  end
  return object
end

local function isListed(object)
  local list = GetNPCBlackboard(scpInvincibility.scp.playerId, "$safeCheatPanelInvincible")
  if type(list) ~= "table" then
    return false
  end
  for i = 1, #list do
    if ConvertStringTo64Bit(tostring(list[i])) == object then
      return true
    end
  end
  return false
end

-- The ship the Player tab switch protects right now.
local function isSwitchShip(object)
  local cfg = scpInvincibility.scp.helpers.getConfig()
  if cfg == nil or not boolOf(cfg.playerInvincible) or cfg.playerInvincibleShip == nil then
    return false
  end
  return ConvertStringTo64Bit(tostring(cfg.playerInvincibleShip)) == object
end

local function isInvincible(object)
  return isListed(object) or isSwitchShip(object)
end

function scpInvincibility.isValidMake()
  local object = getTarget()
  return object ~= nil and not isInvincible(object)
end

function scpInvincibility.isValidRemove()
  local object = getTarget()
  return object ~= nil and isInvincible(object)
end

function scpInvincibility.toggle()
  local object = getTarget()
  if object then
    local listed, switched = isListed(object), isSwitchShip(object)
    scpInvincibility.scp.debug(string.format("Invincibility: toggle on %s (listed %s, Player switch ship %s)", tostring(object), tostring(listed), tostring(switched)))
    -- Remove on the Player switch ship turns the switch off as well.
    if switched then
      scpInvincibility.setPlayerInvincible(false)
    end
    if listed or not switched then
      AddUITriggeredEvent("scp_main", "scp_toggle_invincibility", { object = ConvertStringToLuaID(tostring(object)) })
    end
  end
  scpInvincibility.scp.helpers.interactMenuFinishAction()
end

function scpInvincibility.isPlayerInvincible()
  local cfg = scpInvincibility.scp.helpers.getConfig()
  return cfg ~= nil and boolOf(cfg.playerInvincible)
end

function scpInvincibility.setPlayerInvincible(checked)
  scpInvincibility.scp.debug("Invincibility: player switch set to " .. tostring(checked))
  AddUITriggeredEvent("scp_main", "scp_player_invincible", checked and 1 or 0)
end

Register_Require_Response("extensions.safe_cheat_panel.ui.scp_invincibility", scpInvincibility)
return scpInvincibility
