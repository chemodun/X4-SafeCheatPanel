--region FFI Setup
local ffi = require("ffi")
local C = ffi.C

ffi.cdef [[
    typedef uint64_t UniverseID;

    typedef struct {
        int relationStatus;
        int relationValue;
        int relationLEDValue;
        bool isBoostedValue;
    } RelationDetails;


    typedef struct {
      int major;
      int minor;
    } GameVersion;

	  GameVersion GetGameVersion();

    RelationDetails GetFactionRelationStatus2(const char* factionid);
    bool CanResearch(void);
    bool IsComponentClass(UniverseID componentid, const char* classname);
    void ForceBuildCompletion(UniverseID containerid);
]]
--endregion

--region Config
local menu = {}                  -- NOTE: menu is map menu as its the main menu we access
local shipConfigurationMenu = {} -- NOTE: this is the menu for ship configuration, used in the spawn ship section of the cheat menu
local interactMenu = {}

local scp = {
  playerId = nil,

  cheats = {},
  helpers = {},
  menuHelper = {},

  tableMode = "scpPlayer",
  contextFrameLayer = 2,
  contextMenuData = {},

  isCreated = false,
  isCreatedAtIndex = 0,
  isSectionAdded = false,

  blueprint = {
    primaryTag   = "all",
    secondaryTag = "all",
    expanded     = {},
    data         = nil,
  },

  spawner  = {}, -- populated by require below
  currentRow = {},
  isV9 = C.GetGameVersion().major >= 9,
  table = {},
}

scp.helpers    = require("extensions.safe_cheat_panel.ui.scp_helpers")
scp.menuHelper = require("extensions.safe_cheat_panel.ui.scp_menu_helper")
scp.blueprints = require("extensions.safe_cheat_panel.ui.scp_blueprints")
scp.spawner    = require("extensions.safe_cheat_panel.ui.scp_spawner")
scp.player     = require("extensions.safe_cheat_panel.ui.scp_player")
scp.station    = require("extensions.safe_cheat_panel.ui.scp_station")
scp.station.join(scp)
scp.research   = require("extensions.safe_cheat_panel.ui.scp_research")
scp.inventory  = require("extensions.safe_cheat_panel.ui.scp_inventory")
scp.factions   = require("extensions.safe_cheat_panel.ui.scp_factions")
scp.map        = require("extensions.safe_cheat_panel.ui.scp_map")
scp.destroy    = require("extensions.safe_cheat_panel.ui.scp_destroy")
scp.destroy.join(scp)

-- Canonical isExtendedMode lives in scp_helpers; alias it onto scp for use in
-- display functions and scp.reset().
scp.isExtendedMode = scp.helpers.isExtendedMode
scp.isDeveloperMode = scp.helpers.isDeveloperMode

scp.info = scp.helpers.info
scp.debug = scp.helpers.debug
scp.trace = scp.helpers.trace

local config = {

  section = { id = "scpCheats", text = ReadText(1972092427, 1), isorder = false },

  cheatCategories = {
    { category = "scpPlayer",    name = ReadText(1972092427, 1000), icon = "tlt_playerinfo", helpOverlayID = "help_category_cheatsplayer",    helpOverlayText = ReadText(1972092427, 1001), display = function() return true end },
    { category = "scpInventory", name = ReadText(1972092427, 2000), icon = "pi_inventory",   helpOverlayID = "help_category_cheatsinventory", helpOverlayText = ReadText(1972092427, 2001), display = function() return true end },
    {
      category = "scpResearch",
      name = ReadText(1972092427, 3000),
      icon = "tlt_research",
      helpOverlayID = "help_category_cheatsresearch",
      helpOverlayText = ReadText(1972092427, 3001),
      display = function()
        return C.CanResearch() or scp.isExtendedMode()
      end
    },
    { category = "scpBlueprint",   name = ReadText(1972092427, 4000), icon = "pi_blueprints",  helpOverlayID = "help_category_cheatsblueprint", helpOverlayText = ReadText(1972092427, 4001), display = function() return true end },
    { category = "scpFactions",    name = ReadText(1972092427, 5000), icon = "pi_diplomacy",   helpOverlayID = "help_category_cheatsfactions",  helpOverlayText = ReadText(1972092427, 5001), display = function() return true end },
    { category = "scpMap",         name = ReadText(1001, 9181),    icon = "tlt_map",        helpOverlayID = "help_category_cheatsmap",       helpOverlayText = ReadText(1001, 9181), display = function() return true end },
    { category = "scpObjectSpawn", name = ReadText(1972092427, 7000), icon = "mapst_cheats",   helpOverlayID = "help_category_cheatsspawn",     helpOverlayText = ReadText(1972092427, 7001), display = function() return true end },
    { category = "scpDestroy",     name = ReadText(1972092427, 9000), icon = "order_attack",   helpOverlayID = "help_category_cheatsdestroy",   helpOverlayText = ReadText(1972092427, 9001), display = function() return true end },
    {
      category = "scpDevMode",
      name = ReadText(1972092427, 8000),
      icon = "mapst_cheats",
      helpOverlayID = "help_category_cheatsdev",
      helpOverlayText = ReadText(1972092427, 8001),
      display = function()
        return scp.isDeveloperMode()
      end
    },
  },

  contextMenuActions = {
    {
      id = "spawnStation",
      type = "scp_cheat",
      actiontype = "lua;spawnStation",
      spawnMode = "spawnModeStation",
      isValidFunction = function() return scp.spawner.showSpawnOption("spawnModeStation", scp.tableMode, nil) end,
      text = ReadText(1972092427, 101),
      scriptFunction = function()
        local s = scp.spawner.state
        scp.spawner.spawnStation(s.station.name, s.station.plan, s.station.ownerId)
      end
    },
    {
      id = "fixStation",
      type = "scp_cheat",
      actiontype = "lua;fixStation",
      isValidFunction = function() return scp.spawner.isStationMissingControlEntities() end,
      text = ReadText(1972092427, 107),
      scriptFunction = function()
        scp.spawner.fixStation()
      end
    },
    {
      id = "spawnShip",
      type = "scp_cheat",
      actiontype = "lua;spawnShip",
      spawnMode = "spawnModeShip",
      isValidFunction = function() return scp.spawner.showSpawnOption("spawnModeShip", scp.tableMode, nil) end,
      text = ReadText(1972092427, 102),
      scriptFunction = function()
        local s = scp.spawner.state
        scp.spawner.spawnShip(
          s.ships_sel.id, s.ships_sel.loadout,
          s.ships_sel.ownerId, s.ships_sel.ownerRace,
          s.ships_sel.rows,
          s.ships_sel.numPerRow,
          s.ships_sel.loadoutFaction)
      end
    },
    {
      id = "spawnObject",
      type = "scp_cheat",
      actiontype = "lua;spawnObject",
      spawnMode = "spawnModeObject",
      isValidFunction = function() return scp.spawner.showSpawnOption("spawnModeObject", scp.tableMode, nil) end,
      text = ReadText(1972092427, 103),
      scriptFunction = function()
        local s = scp.spawner.state
        scp.spawner.spawnObject(s.object.macro, s.object.rows, s.object.numPerRow, s.object.spacing, s.object.ownerId)
      end
    },
    {
      id = "forceBuildCompletion",
      type = "scp_cheat",
      actiontype = "lua;forceBuildCompletion",
      isValidFunction = function() return scp.station.isValidForceBuildCompletion() end,
      text = ReadText(1972092427, 109),
      scriptFunction = function() scp.station.forceBuildCompletion() end
    },
    {
      id = "forceBuildCompletionForAllFaction",
      type = "scp_cheat",
      actiontype = "lua;forceBuildCompletionForAllFaction",
      isValidFunction = function() return scp.isExtendedMode() and scp.station.isValidForceBuildCompletionForAllFaction() end,
      text = ReadText(1972092427, 110),
      scriptFunction = function() scp.station.forceBuildCompletionForAllFaction() end
    },
    {
      id = "fillWaresGapStation",
      type = "scp_cheat",
      actiontype = "lua;fillWaresGapStation",
      isValidFunction = function() return scp.station.isValidFillWaresGapStation() end,
      text = ReadText(1972092427, 111),
      scriptFunction = function() scp.station.fillWaresGapStation() end
    },
    {
      id = "fillWaresGapStationForAllFaction",
      type = "scp_cheat",
      actiontype = "lua;fillWaresGapStationForAllFaction",
      isValidFunction = function() return scp.isExtendedMode() and scp.station.isValidFillWaresGapStationForAllFaction() end,
      text = ReadText(1972092427, 112),
      scriptFunction = function() scp.station.fillWaresGapStationForAllFaction() end
    },
    {
      id = "fillWaresGapBuildStorage",
      type = "scp_cheat",
      actiontype = "lua;fillWaresGapBuildStorage",
      isValidFunction = function() return scp.station.isValidFillWaresGapBuildStorage() end,
      text = ReadText(1972092427, 113),
      scriptFunction = function() scp.station.fillWaresGapBuildStorage() end
    },
    {
      id = "fillWaresGapBuildStorageForAllFaction",
      type = "scp_cheat",
      actiontype = "lua;fillWaresGapBuildStorageForAllFaction",
      isValidFunction = function() return scp.isExtendedMode() and scp.station.isValidFillWaresGapBuildStorageForAllFaction() end,
      text = ReadText(1972092427, 114),
      scriptFunction = function() scp.station.fillWaresGapBuildStorageForAllFaction() end
    },
    {
      id = "teleportObject",
      type = "scp_cheat",
      actiontype = "lua;teleportObject",
      isValidFunction = function() return scp.isValidTeleportObject() end,
      text = ReadText(1972092427, 104),
      scriptFunction = function() scp.teleportObject() end
    },
    {
      id = "teleportPlayer",
      type = "scp_cheat",
      actiontype = "lua;teleportPlayer",
      isValidFunction = function() return scp.player.isValidTeleportPlayer() end,
      text = ReadText(1972092427, 105),
      scriptFunction = function() scp.player.teleportPlayer(false) end
    },
    {
      id = "destroyObject",
      type = "scp_cheat",
      actiontype = "lua;destroyObject",
      isValidFunction = function() return scp.destroy.isValidDestroyObject() end,
      text = ReadText(1972092427, 115),
      scriptFunction = function() scp.destroy.startDestroy() end
    },
    -- ["teleportPlayerSeat"] = {
    --   type = "scp_cheat",
    --   actiontype = "lua;teleportPlayerSeat",
    --   teleportPlayerSeat = true,
    --   text = ReadText(1972092427, 106),
    --   scriptFunction = function() scp.player.teleportPlayer(true) end
    -- }
  },

  blacklistedFactions = { ["civilian"] = true, ["criminal"] = true, ["outlaw"] = true, ["smuggler"] = true, ["visitor"] = true },

  playerCheats = {
    spacesuit = {
      { id = "player_spacesuit_upgrades", title = ReadText(1972092427, 1200), type = "button" },
    },
    factions = {
      id = "player_faction_relations", title = ReadText(1972092427, 5000), type = "slider", slidermin = -30, slidermax = 30, },
  },

  spawnModes = {
    { id = "spawnModeShip",    text = ReadText(1001, 6),  active = true, icon = "", displayremoveoption = false },
    { id = "spawnModeStation", text = ReadText(1001, 3),  active = true, icon = "", displayremoveoption = false },
    { id = "spawnModeObject",  text = ReadText(1001, 93), active = true, icon = "", displayremoveoption = false },
  },
  stationPlanTypes = {
    { id = "ingame",  text = ReadText(1972092427, 7102), active = true, icon = "", displayremoveoption = false },
    { id = "player",  text = ReadText(1972092427, 7103), active = true, icon = "", displayremoveoption = false },
  },
  consumableTypes = {
    { id = "civilian", text = ReadText(1001, 7847), active = true, icon = "", displayremoveoption = false },
    { id = "military", text = ReadText(1001, 7848), active = true, icon = "", displayremoveoption = false },
  },


  -- Faction relation slider values are based on the values used in the game, see GetFactionRelationStatus2 in X4_DataStructures.lua for reference
  mapRowHeight = Helper.standardTextHeight,
  mapFontSize = Helper.standardFontSize,

  variableId = "$safeCheatPanelDataExchange",
  configId   = "$safeCheatPanelConfig"
}
--endregion

--region init() and callbacks

local function init()
  scp.info("init")

  menu = Helper.getMenu("MapMenu")
  shipConfigurationMenu = Helper.getMenu("ShipConfigurationMenu")

  menu.registerCallback("createSideBar_on_start", scp.createSideBar)
  menu.registerCallback("createInfoFrame_on_menu_infoTableMode", scp.createInfoFrame)

  interactMenu = Helper.getMenu("InteractMenu")
  interactMenu.registerCallback("prepareSections_on_start", scp.prepareSections)
  interactMenu.registerCallback("prepareActions_prepare_custom_action", scp.prepareActions)
  interactMenu.registerCallback("insertLuaAction_insert_custom_action", scp.insertLuaAction)

  menu.registerCallback("ic_onRowChanged", scp.onRowChanged)
  menu.registerCallback("ic_onSelectElement", scp.onSelectElement)

  RegisterEvent("scp_main.relationsData", scp.factions.onRelationsData)

  RegisterEvent("scp_main.ConfigChanged", function()
    scp.helpers.setDebug()
    scp.reset()
  end)

  RegisterEvent("scp_main.researchRemoved", function() menu.refreshInfoFrame() end)
  RegisterEvent("scp_main.sectorRevealed", function() menu.refreshInfoFrame() end)

  scp.playerId = ConvertStringTo64Bit(tostring(C.GetPlayerID()))
  scp.helpers.init(scp.playerId, config.configId)
  scp.inventory.prepareData()
  scp.factions.init(scp.playerId, config.variableId, config.blacklistedFactions)
  scp.spawner.shipConfigurationMenu = shipConfigurationMenu
  scp.map.init(scp, config)
  scp.menuHelper.init()
end

function scp.resetValues()
  if scp.tableMode ~= "scpInventory" then
    scp.inventory.reset()
    scp.currentRow = {}
  end
end

function scp.reset()
  if not scp.isExtendedMode() then
    scp.factions.state.factionFor = "player"
  end
  scp.spawner.reset(config.blacklistedFactions)
end

function scp.createSideBar(_config)
  local safeCheatMenu = {
    name = ReadText(1972092427, 1),
    icon = "mapst_cheats",
    mode = "safeCheatPanel",
    helpOverlayID = "help_sidebar_safeCheatPanel",
    helpOverlayText = ReadText(1972092427, 2)
  }
  if _config.leftBar[#_config.leftBar].mode ~= "safeCheatPanel" then
    for i = #_config.leftBar - 1, 1, -1 do
      if _config.leftBar[i + 1].mode == "safeCheatPanel" then
        table.remove(_config.leftBar, i + 1)
        table.remove(_config.leftBar, i)
      end
    end
    _config.leftBar[#_config.leftBar + 1] = { spacing = true }
    _config.leftBar[#_config.leftBar + 1] = safeCheatMenu
    scp.isCreated = true
    scp.map.requestSectors()
  end
end

function scp.createInfoFrame()
  if menu.infoTableMode == "safeCheatPanel" then
    scp.createCheatMenu(menu.infoFrame, "left")
  end
end

--endregion

--region Context Menu Actions
function scp.insertLuaAction(actionType, _)
  if scp.isSectionAdded then
    local actionData = nil
    for i = 1, #config.contextMenuActions do
      local action = config.contextMenuActions[i]
      if action.id == actionType then
        actionData = action
        break
      end
    end
    if not actionData then
      return
    end
    interactMenu.insertInteractionContent("scpCheats", {
      type = "scp_cheat",
      text = actionData.text,
      script = actionData.scriptFunction,
      mouseOverText = "",
      helpOverlayID = "",
      helpOverlayText = "",
      helperOverlayHighlightOnly = true
    })
  end
end

function scp.prepareActions(actions, definedActions)
  if scp.isSectionAdded then
    local isToBeDisplayed = false
    for i = 1, #config.contextMenuActions do
      local action = config.contextMenuActions[i]
      if action.isValidFunction() then
        scp.addAction(actions, definedActions, action, isToBeDisplayed)
      end
    end
  end
end

function scp.prepareSections(sections)
  if not scp.isSectionAdded then
    sections[#sections + 1] = config.section
    scp.isSectionAdded = true
  end
end

function scp.onRowChanged(row, rowData, uiTable, modified, input, source)
  if menu.infoTableMode ~= "safeCheatPanel" then
    return
  end
  if scp.table and scp.table.id == uiTable and source ~= "auto" then
    scp.currentRow[scp.tableMode] = row
  end
end

function scp.onSelectElement(uiTable, modified, row, isDblClick, input)
  if menu.infoTableMode ~= "safeCheatPanel" then
    return
  end
  if scp.table and scp.table.id == uiTable then
    scp.currentRow[scp.tableMode] = row
    if scp.tableMode == "scpMap" and scp.table.rows[row] then
      scp.map.onSelectElement(uiTable, modified, row, isDblClick, input, scp.table.rows[row].rowdata)
    end
  end
end
--endregion

--region Lua Action Helpers
function scp.addAction(actions, definedActions, action, isToBeDisplayed)
  table.insert(actions, {
    id = #actions,
    text = action.text,
    actiontype = action.actiontype,
    active = isToBeDisplayed,
    istobedisplayed = isToBeDisplayed
  })
  definedActions[action.actiontype] = #actions
end

function scp.isValidTeleportObject()
  local component = C.GetPlayerShipID()
  local convertedComponent = ConvertStringTo64Bit(tostring(C.GetPlayerShipID()))
  if component ~= nil and convertedComponent ~= 0 then
    local pilot = GetComponentData(convertedComponent, "pilot")
    local isPlayerPilot = GetComponentData(pilot, "name") == ffi.string(C.GetPlayerName())
    return isPlayerPilot
  end
  return false
end

function scp.teleportObject()
  local targetObject
  if menu.selectedcomponent ~= nil then
    targetObject = ConvertStringTo64Bit(tostring(interactMenu.componentSlot.component))
  else
    targetObject = ConvertStringToLuaID(tostring(C.GetPlayerShipID()))
  end
  local data = {
    object = targetObject,
    offsetComponent = ConvertStringToLuaID(tostring(interactMenu.offsetcomponent)),
    position = {
      x = interactMenu.offset.x,
      y = interactMenu.offset.y,
      z = interactMenu.offset.z
    }
  }
  AddUITriggeredEvent("scp_main", "scp_teleport_object", data)
  scp.helpers.interactMenuFinishAction()
end

--endregion

--region Menu Functions
function scp.createCheatMenu(frame, _)
  -- local infoTableMode = menu.infoTableMode[instance]
  local mainTable = frame:addTable(12, { tabOrder = 2, reserveScrollBar = false })
  scp.table = mainTable
  mainTable:setDefaultCellProperties("text", { minRowHeight = config.mapRowHeight, fontsize = config.mapFontSize })
  mainTable:setDefaultCellProperties("button", { height = config.mapRowHeight })
  mainTable:setDefaultCellProperties("dropdown", { height = config.mapRowHeight })
  mainTable:setDefaultComplexCellProperties("button", "text", { fontsize = config.mapFontSize })

  local maxNumCategoryColumns = math.floor(menu.infoTableWidth / (menu.sideBarWidth + Helper.borderSize))
  if maxNumCategoryColumns > Helper.maxTableCols then
    maxNumCategoryColumns = Helper.maxTableCols
  end

  local numdisplayed = 0
  local maxVisibleHeight = mainTable:getFullHeight()

  if scp.tableMode == "scpPlayer" then
    numdisplayed = scp.player.createSection(mainTable, numdisplayed, scp)
  elseif scp.tableMode == "scpResearch" then
    numdisplayed = scp.research.createSection(mainTable, numdisplayed, scp)
  elseif scp.tableMode == "scpInventory" then
    numdisplayed = scp.inventory.createSection(mainTable, numdisplayed, scp)
  elseif scp.tableMode == "scpMap" then
    numdisplayed = scp.map.createSection(mainTable, numdisplayed, scp)
  elseif scp.tableMode == "scpFactions" then
    numdisplayed = scp.factions.createSection(mainTable, numdisplayed, scp)
  elseif scp.tableMode == "scpObjectSpawn" then
    numdisplayed = scp.spawner.createSection(mainTable, numdisplayed, scp.isV9, scp.helpers.getConsumables, config.consumableTypes, nil)
  elseif scp.tableMode == "scpDestroy" then
    numdisplayed = scp.destroy.createSection(mainTable, numdisplayed, scp)
  elseif scp.tableMode == "scpBlueprint" then
    numdisplayed = scp.blueprints.createSection(mainTable, numdisplayed, scp)
  end

  local tabTable = frame:addTable(maxNumCategoryColumns, { tabOrder = 2, reserveScrollBar = false })
  tabTable:setDefaultCellProperties("text", { minRowHeight = config.mapRowHeight, fontsize = config.mapFontSize })
  tabTable:setDefaultCellProperties("button", { height = config.mapRowHeight })
  tabTable:setDefaultComplexCellProperties("button", "text", { fontsize = config.mapFontSize })

  if maxNumCategoryColumns > 0 then
    for i = 1, maxNumCategoryColumns do
      tabTable:setColWidth(i, menu.sideBarWidth, false)
    end
    local diff = menu.infoTableWidth - maxNumCategoryColumns * (menu.sideBarWidth + Helper.borderSize)
    tabTable:setColWidth(maxNumCategoryColumns, menu.sideBarWidth + diff, false)
    -- object list categories row
    local row = tabTable:addRow("cheat_tabs", { fixed = true })
    local rowCount = 1

    if #config.cheatCategories > 0 then
      local categoriesFiltered = {}
      for i = 1, #config.cheatCategories do
        if config.cheatCategories[i].display() then
          categoriesFiltered[#categoriesFiltered + 1] = config.cheatCategories[i]
        end
      end
      for i, entry in ipairs(categoriesFiltered) do
        if i / maxNumCategoryColumns > rowCount then
          row = tabTable:addRow("cheat_tabs", { fixed = true })
          rowCount = rowCount + 1
        end
        local bgColor = scp.tableMode == entry.category and Color["row_background_selected"] or Color["row_title_background"]
        local color = Color["icon_normal"]
        row[i - math.floor((i - 1) / maxNumCategoryColumns) * maxNumCategoryColumns]
            :createButton({
              height = menu.sideBarWidth,
              width = menu.sideBarWidth,
              bgColor = bgColor,
              mouseOverText = entry.name,
              scaling = false,
              helpOverlayID = entry.helpOverlayID,
              helpOverlayText = entry.helpOverlayText,
            })
            :setIcon(entry.icon, { color = color })
        row[i - math.floor((i - 1) / maxNumCategoryColumns) * maxNumCategoryColumns].handlers.onClick = function()
          return scp.buttonObjectSubMode(entry.category, i)
        end
      end
    end
  end

  if numdisplayed > 50 then
    mainTable.properties.maxVisibleHeight = maxVisibleHeight +
        50 * (Helper.scaleY(config.mapRowHeight) + Helper.borderSize)
  end
  menu.numFixedRows = mainTable.numfixedrows

  menu.settoprow = ((not menu.settoprow) or (menu.settoprow == 0)) and ((menu.setrow and menu.setrow > 21) and (menu.setrow - 17) or 3) or menu.settoprow
  mainTable:setTopRow(menu.settoprow)
  if menu.infoTable then
    local result = GetShiftStartEndRow(menu.infoTable)
    if result then
      local shiftStart, shiftEnd = table.unpack(result)
      mainTable:setShiftStartEnd(table.unpack(result))
    end
  end
  mainTable:setSelectedRow(scp.currentRow[scp.tableMode] or menu.setrow or nil)
  menu.setrow = nil
  menu.settoprow = nil
  menu.setcol = nil
  menu.sethighlightborderrow = nil

  mainTable.properties.y = tabTable.properties.y + tabTable:getFullHeight() + Helper.borderSize
end

function scp.buttonObjectSubMode(mode, col)
  if mode ~= scp.tableMode then
    scp.tableMode = mode

    AddUITriggeredEvent(menu.name, scp.tableMode)
    scp.resetValues()

    menu.selectedRows.propertytabs = 1
    menu.selectedCols.propertytabs = col
    menu.refreshInfoFrame(1, col)
  end
end

--endregion

Register_OnLoad_Init(init)
