local ffi = require("ffi")
local C = ffi.C

ffi.cdef [[
    typedef uint64_t UniverseID;
    typedef uint64_t MissionID;

    bool IsComponentClass(UniverseID componentid, const char* classname);
    uint32_t GetNumMapComponentMissions(UniverseID holomapid, UniverseID componentid);
    uint32_t GetMapComponentMissions(MissionID* result, uint32_t resultlen, UniverseID holomapid, UniverseID componentid);
]]

local menu         = Helper.getMenu("MapMenu")
local interactMenu = Helper.getMenu("InteractMenu")

local PAGE_ID = 1972092427
-- The widget engine holds 200 buttons for everything on screen; a longer list goes without them.
local MAX_ROWS_WITH_BUTTONS = 180
local ROW_TYPE = "scpInvincible"

local scpInvincibility = {}

function scpInvincibility.join(scp)
  scpInvincibility.scp = scp
end

local function boolOf(value)
  return value == true or value == 1
end

function scpInvincibility.isTabShown()
  return menu.infoTableMode == "safeCheatPanel" and scpInvincibility.scp.tableMode == "scpInvincible"
end

-- The right-clicked ship or station while the Invincibility tab is shown; another owner's only in extended mode.
local function getTarget()
  local scp = scpInvincibility.scp
  if not scpInvincibility.isTabShown() then
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

-- The right-click list as 64-bit ids; MD prunes destroyed objects only on a toggle.
local function getList()
  local list = GetNPCBlackboard(scpInvincibility.scp.playerId, "$safeCheatPanelInvincible")
  local objects = {}
  if type(list) ~= "table" then
    return objects
  end
  for i = 1, #list do
    objects[#objects + 1] = ConvertStringTo64Bit(tostring(list[i]))
  end
  return objects
end

local function isListed(object)
  for _, listed in ipairs(getList()) do
    if listed == object then
      return true
    end
  end
  return false
end

-- The ship the Player Ship switch protects right now.
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

-- The tab's Remove button: drops the right-click protection only, the Player Ship switch keeps its own.
function scpInvincibility.removeListed(object)
  scpInvincibility.scp.debug("Invincibility: Remove pressed for " .. tostring(object))
  AddUITriggeredEvent("scp_main", "scp_toggle_invincibility", { object = ConvertStringToLuaID(tostring(object)), release = true })
end

function scpInvincibility.isPlayerInvincible()
  local cfg = scpInvincibility.scp.helpers.getConfig()
  return cfg ~= nil and boolOf(cfg.playerInvincible)
end

function scpInvincibility.setPlayerInvincible(checked)
  scpInvincibility.scp.debug("Invincibility: player switch set to " .. tostring(checked))
  AddUITriggeredEvent("scp_main", "scp_player_invincible", checked and 1 or 0)
end

function scpInvincibility.createSection(frameTable, numDisplayed, scp)
  local isV9 = scp.isV9

  numDisplayed = scp.menuHelper.createTitle(frameTable, numDisplayed, {
    text  = ReadText(PAGE_ID, 1400),
    fixed = true,
  })

  local rowGroup = isV9 and frameTable:addRowGroup({}) or frameTable

  local isPlayerInvincible = scpInvincibility.isPlayerInvincible()
  numDisplayed = scp.menuHelper.createButton(rowGroup, "player_invincible", numDisplayed, {
    active          = true,
    text            = ReadText(PAGE_ID, 1112),
    mouseOverText   = ReadText(PAGE_ID, 1113),
    buttonText      = isPlayerInvincible and ReadText(PAGE_ID, 1401) or ReadText(1001, 8986),
    buttonTextColor = isPlayerInvincible and Color["text_negative"] or Color["text_positive"],
    onClick         = function() scpInvincibility.setPlayerInvincible(not isPlayerInvincible) end,
    fixed           = true,
  })

  numDisplayed = scp.menuHelper.createTitle(frameTable, numDisplayed, {
    text  = ReadText(PAGE_ID, 11010),
    fixed = true,
  })

  local entries = {}
  for _, object in ipairs(getList()) do
    if IsValidComponent(object) then
      local name, idcode, icon, sector, owner = GetComponentData(object, "name", "idcode", "icon", "sector", "owner")
      entries[#entries + 1] = { object = object, name = name, idcode = idcode, icon = icon, sector = sector, owner = owner }
    end
  end
  table.sort(entries, Helper.sortName)

  rowGroup = isV9 and frameTable:addRowGroup({}) or frameTable

  if #entries == 0 then
    local row = rowGroup:addRow(nil, { bgColor = Color["row_background_unselectable"] })
    row[1]:setColSpan(12):createText(ReadText(PAGE_ID, 11011), { halign = "center", color = Color["text_inactive"], wordwrap = true })
    return numDisplayed + 1
  end

  local withButtons = #entries <= MAX_ROWS_WITH_BUTTONS
  for _, entry in ipairs(entries) do
    local factionColor = entry.owner and Helper.convertColorToText(GetFactionData(entry.owner, "color")) or ""
    local icon = (entry.icon ~= nil and entry.icon ~= "") and entry.icon or "menu_info"
    local row = rowGroup:addRow({ ROW_TYPE, entry.object }, { bgColor = Color["row_background_unselectable"] })
    row[1]:setColSpan(withButtons and 9 or 12):createIcon(icon, { height = Helper.standardTextHeight, width = Helper.standardTextHeight })
    row[1]:setText(string.format("%s%s (%s)", factionColor, entry.name, entry.idcode), { x = Helper.standardTextHeight, halign = "left" })
    row[1]:setText2(entry.sector or "", { halign = "right" })
    if withButtons then
      row[10]:setColSpan(3):createButton({ mouseOverText = ReadText(PAGE_ID, 123) }):setText(ReadText(1001, 6702), { halign = "center" })
      row[10].handlers.onClick = function() scpInvincibility.removeListed(entry.object) end
    end
    numDisplayed = numDisplayed + 1
  end

  return numDisplayed
end

-- A list row's right-click opens the object's interact menu, as vanilla's object list does.
function scpInvincibility.onTableRightMouseClick(rowData, posX, posY)
  if menu.mode ~= nil or type(rowData) ~= "table" or rowData[1] ~= ROW_TYPE then
    return
  end
  local object = rowData[2]
  if not IsValidComponent(object) then
    return
  end
  local missions = {}
  Helper.ffiVLA(missions, "MissionID", C.GetNumMapComponentMissions, C.GetMapComponentMissions, menu.holomap, object)
  local playerShips, otherObjects, playerDeployables = menu.getSelectedComponentCategories()
  Helper.openInteractMenu(menu, {
    component = object, playerships = playerShips, otherobjects = otherObjects,
    playerdeployables = playerDeployables, mouseX = posX, mouseY = posY, componentmissions = missions,
  })
end

Register_Require_Response("extensions.safe_cheat_panel.ui.scp_invincibility", scpInvincibility)
return scpInvincibility
