local ffi = require("ffi")
local C = ffi.C

ffi.cdef [[
	typedef uint64_t UniverseID;

	typedef struct {
		const char* id;
		const char* name;
		int32_t state;
		const char* requiredversion;
		const char* installedversion;
	} InvalidPatchInfo;

	typedef struct {
		const char* id;
		const char* name;
		const char* iconid;
		bool deleteable;
	} UILoadoutInfo;

	typedef struct {
		const char* name;
		const char* id;
		const char* source;
		bool deleteable;
	} UIConstructionPlan;

	typedef struct {
		const char* ammomacroname;
		const char* weaponmode;
	} UILoadoutWeaponSetting;

	typedef struct {
		const char* macro;
		uint32_t amount;
		bool optional;
	} UILoadoutAmmoData;

	typedef struct {
		const char* roleid;
		uint32_t count;
		bool optional;
	} UILoadoutCrewData;

	typedef struct {
		const char* macro;
		const char* path;
		const char* group;
		uint32_t count;
		bool optional;
		UILoadoutWeaponSetting weaponsetting;
	} UILoadoutGroupData2;

	typedef struct {
		const char* macro;
		const char* upgradetypename;
		size_t slot;
		bool optional;
		UILoadoutWeaponSetting weaponsetting;
	} UILoadoutMacroData2;

	typedef struct {
		const char* ware;
	} UILoadoutSoftwareData;

	typedef struct {
		const char* macro;
		bool optional;
	} UILoadoutVirtualMacroData;

	typedef struct {
		uint32_t numweapons;
		uint32_t numturrets;
		uint32_t numshields;
		uint32_t numengines;
		uint32_t numturretgroups;
		uint32_t numshieldgroups;
		uint32_t numammo;
		uint32_t numunits;
		uint32_t numsoftware;
		uint32_t numcrew;
	} UILoadoutCounts2;

	typedef struct {
		UILoadoutMacroData2* weapons;
		uint32_t numweapons;
		UILoadoutMacroData2* turrets;
		uint32_t numturrets;
		UILoadoutMacroData2* shields;
		uint32_t numshields;
		UILoadoutMacroData2* engines;
		uint32_t numengines;
		UILoadoutGroupData2* turretgroups;
		uint32_t numturretgroups;
		UILoadoutGroupData2* shieldgroups;
		uint32_t numshieldgroups;
		UILoadoutAmmoData* ammo;
		uint32_t numammo;
		UILoadoutAmmoData* units;
		uint32_t numunits;
		UILoadoutSoftwareData* software;
		uint32_t numsoftware;
		UILoadoutVirtualMacroData thruster;
		uint32_t numcrew;
		UILoadoutCrewData* crew;
		bool hascrewexperience;
	} UILoadout2;

	uint32_t GetNumWares(const char* tags, bool research, const char* licenceownerid, const char* exclusiontags);
	uint32_t GetWares(const char** result, uint32_t resultlen, const char* tags, bool research, const char* licenceownerid, const char* exclusiontags);
	uint32_t GetNumLoadoutsInfo(UniverseID componentid, const char* macroname);
	uint32_t GetLoadoutsInfo(UILoadoutInfo* result, uint32_t resultlen, UniverseID componentid, const char* macroname);
	bool IsLoadoutValid(UniverseID defensibleid, const char* macroname, const char* loadoutid, uint32_t* numinvalidpatches);
	uint32_t GetLoadoutInvalidPatches(InvalidPatchInfo* result, uint32_t resultlen, UniverseID defensibleid, const char* macroname, const char* loadoutid);
	bool IsLoadoutCompatible(const char* macroname, const char* loadoutid);
	void GetLoadout2(UILoadout2* result, UniverseID defensibleid, const char* macroname, const char* loadoutid);
	uint32_t GetLoadoutCounts2(UILoadoutCounts2* result, UniverseID defensibleid, const char* macroname, const char* loadoutid);
	uint32_t GetNumConstructionPlans(void);
	uint32_t GetConstructionPlans(UIConstructionPlan* result, uint32_t resultlen);
	bool IsConstructionPlanValid(const char* constructionplanid, uint32_t* numinvalidpatches);
	bool IsComponentClass(UniverseID componentid, const char* classname);
	const char* GetPlayerName(void);

	typedef struct {
		float x;
		float y;
		float z;
		float yaw;
		float pitch;
		float roll;
	} UIPosRot;

	UniverseID SpawnObjectAtPos2(const char* macroname, UniverseID sectorid, UIPosRot offset, const char* factionid);
	void SetObjectForcedRadarVisible(UniverseID objectid, bool visible);
	UniverseID GetPlayerShipID(void);
	bool TeleportPlayerTo(UniverseID controllableid, bool allowcontrolling, bool instant, bool force);
]]

local scpHelpers    = require("extensions.safe_cheat_panel.ui.scp_helpers")

local menu         = Helper.getMenu("MapMenu")
local interactMenu = Helper.getMenu("InteractMenu")

-- *** State ***

local state = {
  factions          = {},
  races             = {},
  ships             = {},
  constructionPlans = {},
  playerPlans       = {},
  mode = {
    id   = "spawnModeShip",
    name = ReadText(1972092427, 7003),
  },
  ships_sel = {
    rows           = 1,
    numPerRow      = 1,
    id             = nil,
    name           = nil,
    owner          = nil,
    ownerId        = nil,
    ownerRace      = nil,
    loadoutFaction = nil,
  },
  station = {
    first            = true,
    name             = nil,
    plan = nil,
    planType         = "inGame",
    owner            = nil,
    ownerId          = nil,
  },
  object = {
    consumableType = "civilian",
    macro          = nil,
    name           = nil,
    ownerId        = "player",
    rows           = 1,
    numPerRow      = 1,
    spacing        = 500,
  },
}

-- *** Config (static tables referenced in UI) ***

local spawnModes = {
  { id = "spawnModeShip",    text = ReadText(1001, 6),  active = true, icon = "", displayremoveoption = false },
  { id = "spawnModeStation", text = ReadText(1001, 3),  active = true, icon = "", displayremoveoption = false },
  { id = "spawnModeObject",  text = ReadText(1001, 93), active = true, icon = "", displayremoveoption = false },
}

local stationPlanTypes = {
  { id = "inGame", text = ReadText(1972092427, 7102), active = true, icon = "", displayremoveoption = false },
  { id = "player", text = ReadText(1972092427, 7103), active = true, icon = "", displayremoveoption = false },
}

-- *** Data helpers ***

local function sortText(a, b)
  return a.text < b.text
end

local function getAllShips()
  local ships = {}
  local excludeTags = "noplayerblueprint noblueprint noplayerbuild deprecated missiononly"
  if scpHelpers.isExtendedMode() then
    excludeTags = "deprecated"
  end
  local n = C.GetNumWares("ship", false, "", excludeTags)
  scpHelpers.debug("Num ships: " .. n)
  local buf = ffi.new("const char*[?]", n)
  n = C.GetWares(buf, n, "ship", false, "", excludeTags)
  scpHelpers.debug("Num ships after filtering: " .. n)
  for i = 0, n - 1 do
    local ware = ffi.string(buf[i])
    local name, macro = GetWareData(ware, "name", "component")
    local icon = GetMacroData(macro, "icon")
    ships[#ships + 1] = { id = macro, text = name, active = true, icon = icon, displayremoveoption = false }
  end
  table.sort(ships, sortText)
  for i = 1, #ships do
    local ship = ships[i]
    if ship ~= nil then
      ship.text = string.format("\027[%s] %s", ship.icon, ship.text)
      ship.icon = ""
    end
  end
  return ships
end

local function getShipDefaultFaction(macro)
  if not macro then return nil end
  local wareId = macro:gsub("_macro$", "")
  local owners = GetWareData(wareId, "blueprintsowners")
  if owners and #owners > 0 then
    return owners[1]
  end
  return nil
end

local function getShipLoadouts(macro)
  local loadouts = {}
  if macro == nil then return loadouts end

  local n = C.GetNumLoadoutsInfo(0, macro)
  local buf = ffi.new("UILoadoutInfo[?]", n)
  n = C.GetLoadoutsInfo(buf, n, 0, macro)
  for i = 0, n - 1 do
    local id = ffi.string(buf[i].id)
    local active = false
    local mouseOverText = ""
    local numInvalidPatches = ffi.new("uint32_t[?]", 1)
    if not C.IsLoadoutValid(0, macro, id, numInvalidPatches) then
      local numPatches = numInvalidPatches[0]
      local patchBuf = ffi.new("InvalidPatchInfo[?]", numPatches)
      numPatches = C.GetLoadoutInvalidPatches(patchBuf, numPatches, 0, macro, id)
      mouseOverText = ReadText(1001, 2685) .. ReadText(1001, 120)
      for j = 0, numPatches - 1 do
        if j > 3 then
          mouseOverText = mouseOverText .. "\n- ..."
          break
        end
        mouseOverText = mouseOverText .. "\n- " .. ffi.string(patchBuf[j].name) .. " (" .. ffi.string(patchBuf[j].id) .. " - " .. ffi.string(patchBuf[j].requiredversion) .. ")"
        if patchBuf[j].state == 2 then
          mouseOverText = mouseOverText .. " " .. ReadText(1001, 2686)
        elseif patchBuf[j].state == 3 then
          mouseOverText = mouseOverText .. " " .. ReadText(1001, 2687)
        elseif patchBuf[j].state == 4 then
          mouseOverText = mouseOverText .. " " .. string.format(ReadText(1001, 2688), ffi.string(patchBuf[j].installedversion))
        end
      end
    elseif not C.IsLoadoutCompatible(macro, id) then
      mouseOverText = ReadText(1026, 8024)
    else
      active = true
    end
    table.insert(loadouts, { id = id, text = ffi.string(buf[i].name), icon = ffi.string(buf[i].iconid), displayremoveoption = false, active = active, mouseovertext = mouseOverText })
  end
  table.sort(loadouts, sortText)
  table.insert(loadouts, 1, { id = "scpDefaultLow",    text = ReadText(1001, 7910), icon = "", displayremoveoption = false, preset = 0.1, active = true })
  table.insert(loadouts, 2, { id = "scpDefaultLow", text = ReadText(1001, 7911), icon = "", displayremoveoption = false, preset = 0.5, active = true })
  table.insert(loadouts, 3, { id = "scpDefaultHigh",   text = ReadText(1001, 7912), icon = "", displayremoveoption = false, preset = 1.0, active = true })
  if #loadouts > 3 then
    table.insert(loadouts, 4, { id = "none", text = ReadText(1972092427, 7219), icon = "", displayremoveoption = false, active = false })
  end
  return loadouts
end

local function getAllConstructionPlans()
  local inGamePlans = {}
  local playerPlans = {}
  local n = C.GetNumConstructionPlans()
  local buf = ffi.new("UIConstructionPlan[?]", n)
  n = C.GetConstructionPlans(buf, n)
  local numinvalidpatches = ffi.new("uint32_t[?]", 1)
  for i = 0, n - 1 do
    local id     = ffi.string(buf[i].id)
    local name   = ffi.string(buf[i].name)
    local source = ffi.string(buf[i].source)
    if source == "local" then
      playerPlans[#playerPlans + 1] = { id = id, text = name, active = true, icon = "", displayremoveoption = false }
    elseif C.IsConstructionPlanValid(id, numinvalidpatches) then
      inGamePlans[#inGamePlans + 1] = { id = id, text = name, active = true, icon = "", displayremoveoption = false }
    end
  end
  table.sort(inGamePlans, sortText)
  table.sort(playerPlans, sortText)
  return inGamePlans, playerPlans
end

-- *** Public module table ***

local scpSpawner = {}

-- Called once from safe_cheat_panel init() so the spawner can hold a reference
-- to the shipConfigurationMenu needed by PresetAndCrewForSpawnShip.
scpSpawner.shipConfigurationMenu = {}

function scpSpawner.PresetAndCrewForSpawnShip(macro, loadoutId)
  local preset = -1
  if loadoutId == "scpDefaultLow" then
    preset = 0.1
  elseif loadoutId == "scpDefaultLow" then
    preset = 0.5
  elseif loadoutId == "scpDefaultHigh" then
    preset = 1
  end
  local crew = {
    roles = {},
    hasCrewExperience = preset == 1,
  }
  if preset > 0 then
    local scMenu = scpSpawner.shipConfigurationMenu
    scMenu.crew = { roles = {}, total = 0 }
    scMenu.object = 0
    scMenu.macro = macro
    scMenu.prepareMacroCrewInfo(macro)
    local crewInfo = scMenu.crew
    local intendedCrew = preset * crewInfo.capacity
    local intendedCrewPerRole = math.floor(intendedCrew / #crewInfo.roles)
    for i, entry in ipairs(crewInfo.roles) do
      crew.roles[#crew.roles + 1] = { role = entry.id, count = intendedCrewPerRole }
    end
    scMenu.object = nil
    scMenu.macro = nil
  else
    local loadout = Helper.getLoadoutHelper2(C.GetLoadout2, C.GetLoadoutCounts2, "UILoadout2", 0, macro, loadoutId)
    local loadoutInfo = Helper.convertLoadout(0, macro, loadout, nil, "UILoadout2")
    for role, count in pairs(loadoutInfo.crew) do
      crew.roles[#crew.roles + 1] = { role = role, count = count }
    end
    crew.hasCrewExperience = loadoutInfo.hascrewexperience
  end
  return preset, crew
end

-- Expose getShipDefaultFaction for SpawnShip
function scpSpawner.getShipDefaultFaction(macro)
  return getShipDefaultFaction(macro)
end

-- Returns the current spawner state (read-only reference used by safe_cheat_panel
-- to read scp.spawner.* fields for context actions / showSpawnOption).
function scpSpawner.getState()
  return state
end

-- *** Init / Reset ***

local function getSpawnerFactions(blacklisted)
  if scpHelpers.isExtendedMode() then
    return scpHelpers.getAllFactions(blacklisted)
  end
  local name, primaryrace, icon = GetFactionData("player", "name", "primaryrace", "icon")
  return { { id = "player", ownerrace = primaryrace, name = name, text = string.format("\027[%s] %s", icon, name), active = true, icon = "", displayremoveoption = false } }
end

function scpSpawner.reset(blacklisted)
  state.factions = getSpawnerFactions(blacklisted)
  state.constructionPlans = {}
  state.playerPlans = {}
  state.station.plan = nil
  state.station.name = nil
  state.ships = {}
  state.races = {}
  scpSpawner.initStations()
  scpSpawner.initShips()
  state.object.ownerId = "player"
end

function scpSpawner.initStations()
  if #state.constructionPlans == 0 then
    state.constructionPlans, state.playerPlans = getAllConstructionPlans()
  end
  if state.station.plan == nil then
    if state.station.planType == "player" then
      state.station.ownerId = "player"
      if #state.playerPlans > 0 then
        state.station.plan = state.playerPlans[1].id
        state.station.name             = state.playerPlans[1].text
      end
    else
      if #state.constructionPlans > 0 then
        state.station.plan = state.constructionPlans[1].id
        state.station.name             = state.constructionPlans[1].text
      end
      if #state.factions > 0 then
        state.station.ownerId = state.factions[1].id
      end
    end
  end
end

function scpSpawner.initShips()
  if #state.ships == 0 then
    state.ships = getAllShips()
    if #state.ships > 0 then
      state.ships_sel.id            = state.ships[1].id
      state.ships_sel.loadout       = "scpDefaultHigh"
      state.ships_sel.name          = state.ships[1].text
      state.ships_sel.ownerId       = #state.factions > 0 and state.factions[1].id or "player"
      state.ships_sel.ownerRace     = #state.factions > 0 and state.factions[1].ownerrace or nil
      state.ships_sel.loadoutFaction = getShipDefaultFaction(state.ships_sel.id)
    end
  end
  if #state.races == 0 then
    state.races = scpHelpers.getAllRaces()
  end
  if #state.races == 0 then
    return
  end
  for i = 1, #state.races do
    local race = state.races[i]
    if race ~= nil then
      if race.id == state.ships_sel.ownerRace then
        return
      end
    end
  end
  state.ships_sel.ownerRace = state.races[1].id
end

-- *** Action condition helpers ***

function scpSpawner.showSpawnOption(mode, tableMode, devtools)
  if menu.infoTableMode ~= "safeCheatPanel" then return false end
  if tableMode ~= "scpObjectSpawn" or state.mode.id ~= mode then return false end
  if mode == "spawnModeStation" then
    if state.station.planType == "player" then
      return state.station.plan ~= nil
    end
    return state.station.plan ~= nil and state.station.ownerId ~= nil
  elseif mode == "spawnModeShip" then
    return state.ships_sel.id ~= nil and state.ships_sel.ownerId ~= nil
  elseif mode == "spawnModeObject" then
    return true
  end
  return false
end

function scpSpawner.isStationMissingControlEntities()
  if interactMenu.componentSlot.component == nil then return false end
  local object64 = ConvertStringTo64Bit(tostring(interactMenu.componentSlot.component))
  if not C.IsComponentClass(object64, "station") then return false end
  local defencenpc, engineer = GetComponentData(object64, "defencenpc", "engineer")
  return (defencenpc == nil or defencenpc == 0) or (engineer == nil or engineer == 0)
end

-- *** Data mutation callbacks ***

local function isPresetLoadout(loadoutId)
  return loadoutId == "scpDefaultLow" or loadoutId == "scpDefaultLow" or loadoutId == "scpDefaultHigh"
end

function scpSpawner.setStationSpawnData(id, dataType)
  if dataType == "station" then
    state.station.plan = id
    local planList = (state.station.planType == "player") and state.playerPlans or state.constructionPlans
    for _, plan in pairs(planList) do
      if plan.id == id then
        state.station.name = plan.text
        break
      end
    end
  elseif dataType == "planType" then
    state.station.planType = id
    if id == "player" then
      state.station.ownerId = "player"
      if #state.playerPlans > 0 then
        state.station.plan = state.playerPlans[1].id
        state.station.name             = state.playerPlans[1].text
      else
        state.station.plan = nil
        state.station.name             = nil
      end
    else
      if #state.constructionPlans > 0 then
        state.station.plan = state.constructionPlans[1].id
        state.station.name             = state.constructionPlans[1].text
      end
      if #state.factions > 0 then
        state.station.ownerId = state.factions[1].id
      end
    end
  else
    state.station.ownerId = id
  end
  menu.refreshInfoFrame()
end

function scpSpawner.setShipSpawnData(id, dataType)
  if dataType == "ship" then
    state.ships_sel.id = id
  elseif dataType == "loadout" then
    state.ships_sel.loadout = id
  elseif dataType == "faction" then
    state.ships_sel.ownerId = id
    for _, faction in pairs(state.factions) do
      if faction.id == id then
        state.ships_sel.ownerRace = faction.ownerrace
        break
      end
    end
  elseif dataType == "race" then
    state.ships_sel.ownerRace = id
  end
  if dataType == "ship" or dataType == "loadout" then
    if isPresetLoadout(state.ships_sel.loadout) then
      state.ships_sel.loadoutFaction = getShipDefaultFaction(state.ships_sel.id)
    else
      state.ships_sel.loadoutFaction = nil
    end
  end
  menu.refreshInfoFrame()
end

function scpSpawner.setObjectSpawnData(id, dataType, getConsumables)
  if dataType == "type" then
    state.object.consumableType = id
    state.object.macro = nil
    state.object.name  = nil
  elseif dataType == "item" then
    state.object.macro = id
    for _, item in pairs(getConsumables(state.object.consumableType)) do
      if item.id == id then
        state.object.name = item.text
        break
      end
    end
  elseif dataType == "faction" then
    state.object.ownerId = id
  end
  menu.refreshInfoFrame()
end

function scpSpawner.setMode(newmode)
  state.mode.id = newmode
  menu.refreshInfoFrame()
end

-- *** UI section ***

function scpSpawner.createSection(frameTable, numDisplayed, consumableTypes, scp)
  local isV9 = scp.isV9
  if #state.factions == 0 then
    -- factions not yet loaded (first open before reset was called)
    state.factions = getSpawnerFactions({})
  end

  numDisplayed = scp.menuHelper.createTitle(frameTable, numDisplayed, {
    text  = ReadText(1972092427, 7000),
    fixed = nil,
  })

  local rowGroup = isV9 and frameTable:addRowGroup({}) or frameTable
  numDisplayed = scp.menuHelper.createDropDown(rowGroup, true, numDisplayed, {
    active           = true,
    dropDownData     = spawnModes,
    startOption      = state.mode.id,
    text             = ReadText(1972092427, 7008),
    textOverride     = "",
    onConfirmed      = function(_, id) scpSpawner.setMode(id) end,
    textColIndex     = nil,
    dropDownColIndex = nil,
    dropDownSpan     = nil,
    textColor        = nil,
    fixed            = nil,
    isHeader         = nil,
  })

  if state.mode.id == "spawnModeStation" then
    numDisplayed = scpSpawner.createStationMenu(frameTable, numDisplayed, scp)
  elseif state.mode.id == "spawnModeShip" then
    numDisplayed = scpSpawner.createShipMenu(frameTable, numDisplayed, scp)
  elseif state.mode.id == "spawnModeObject" then
    numDisplayed = scpSpawner.createObjectMenu(frameTable, numDisplayed, consumableTypes, scp)
  end

  return numDisplayed
end

function scpSpawner.createStationMenu(frameTable, numDisplayed, scp)
  local isV9 = scp.isV9
  scpSpawner.initStations()

  numDisplayed = scp.menuHelper.createTitle(frameTable, numDisplayed, {
    text  = ReadText(1972092427, 7101),
    fixed = nil,
  })
  local rowGroup = isV9 and frameTable:addRowGroup({}) or frameTable
  numDisplayed = scp.menuHelper.createDropDown(rowGroup, true, numDisplayed, {
    active           = true,
    dropDownData     = stationPlanTypes,
    startOption      = state.station.planType,
    text             = nil,
    textOverride     = "",
    onConfirmed      = function(_, id) scpSpawner.setStationSpawnData(id, "planType") end,
    textColIndex     = 1,
    dropDownColIndex = 1,
    dropDownSpan     = 12,
    textColor        = nil,
    fixed            = nil,
    isHeader         = nil,
  })

  if state.station.planType == "player" then
    numDisplayed = scp.menuHelper.createTitle(frameTable, numDisplayed, {
      text  = ReadText(1972092427, 7104),
      fixed = nil,
    })
    if #state.playerPlans > 0 then
      rowGroup = isV9 and frameTable:addRowGroup({}) or frameTable
      numDisplayed = scp.menuHelper.createDropDown(rowGroup, true, numDisplayed, {
        active           = #state.playerPlans > 1,
        dropDownData     = state.playerPlans,
        startOption      = state.station.plan,
        text             = nil,
        textOverride     = "",
        onConfirmed      = function(_, id) scpSpawner.setStationSpawnData(id, "station") end,
        textColIndex     = 1,
        dropDownColIndex = 1,
        dropDownSpan     = 12,
        textColor        = nil,
        fixed            = nil,
        isHeader         = nil,
      })
    else
      numDisplayed = scp.menuHelper.createTitle(frameTable, numDisplayed, {
        text  = ReadText(1972092427, 7105),
        fixed = nil,
      })
    end
  else
    numDisplayed = scp.menuHelper.createTitle(frameTable, numDisplayed, {
      text  = ReadText(1972092427, 7100),
      fixed = nil,
    })
    rowGroup = isV9 and frameTable:addRowGroup({}) or frameTable
    numDisplayed = scp.menuHelper.createDropDown(rowGroup, true, numDisplayed, {
      active           = true,
      dropDownData     = state.constructionPlans,
      startOption      = state.station.plan,
      text             = nil,
      textOverride     = "",
      onConfirmed      = function(_, id) scpSpawner.setStationSpawnData(id, "station") end,
      textColIndex     = 1,
      dropDownColIndex = 1,
      dropDownSpan     = 12,
      textColor        = nil,
      fixed            = nil,
      isHeader         = nil,
    })

    numDisplayed = scp.menuHelper.createTitle(frameTable, numDisplayed, {
      text  = ReadText(1972092427, 7005),
      fixed = nil,
    })
    rowGroup = isV9 and frameTable:addRowGroup({}) or frameTable
    numDisplayed = scp.menuHelper.createDropDown(rowGroup, true, numDisplayed, {
      active           = #state.factions > 1,
      dropDownData     = state.factions,
      startOption      = state.station.ownerId,
      text             = nil,
      textOverride     = "",
      onConfirmed      = function(_, id) scpSpawner.setStationSpawnData(id, "faction") end,
      textColIndex     = 1,
      dropDownColIndex = 1,
      dropDownSpan     = 12,
      textColor        = nil,
      fixed            = nil,
      isHeader         = nil,
    })
  end

  return numDisplayed
end

function scpSpawner.createShipMenu(frameTable, numDisplayed, scp)
  local isV9 = scp.isV9
  scpSpawner.initShips()

  numDisplayed = scp.menuHelper.createTitle(frameTable, numDisplayed, {
    text  = ReadText(1972092427, 7200),
    fixed = nil,
  })
  local rowGroup = isV9 and frameTable:addRowGroup({}) or frameTable
  numDisplayed = scp.menuHelper.createDropDown(rowGroup, true, numDisplayed, {
    active           = true,
    dropDownData     = state.ships,
    startOption      = state.ships_sel.id,
    text             = nil,
    textOverride     = "",
    onConfirmed      = function(_, id) scpSpawner.setShipSpawnData(id, "ship") end,
    textColIndex     = 1,
    dropDownColIndex = 1,
    dropDownSpan     = 12,
    textColor        = nil,
    fixed            = nil,
    isHeader         = nil,
  })

  local loadoutOptions = getShipLoadouts(state.ships_sel.id)
  numDisplayed = scp.menuHelper.createTitle(frameTable, numDisplayed, {
    text  = ReadText(1001, 7905),
    fixed = nil,
  })
  rowGroup = isV9 and frameTable:addRowGroup({}) or frameTable
  numDisplayed = scp.menuHelper.createDropDown(rowGroup, true, numDisplayed, {
    active           = true,
    dropDownData     = loadoutOptions,
    startOption      = state.ships_sel.loadout,
    text             = nil,
    textOverride     = "",
    onConfirmed      = function(_, id) scpSpawner.setShipSpawnData(id, "loadout") end,
    textColIndex     = 1,
    dropDownColIndex = 1,
    dropDownSpan     = 12,
    textColor        = nil,
    fixed            = nil,
    isHeader         = nil,
  })

  numDisplayed = scp.menuHelper.createTitle(frameTable, numDisplayed, {
    text  = ReadText(1972092427, 7005),
    fixed = nil,
  })
  rowGroup = isV9 and frameTable:addRowGroup({}) or frameTable
  numDisplayed = scp.menuHelper.createDropDown(rowGroup, true, numDisplayed, {
    active           = #state.factions > 1,
    dropDownData     = state.factions,
    startOption      = state.ships_sel.ownerId,
    text             = nil,
    textOverride     = "",
    onConfirmed      = function(_, id) scpSpawner.setShipSpawnData(id, "faction") end,
    textColIndex     = 1,
    dropDownColIndex = 1,
    dropDownSpan     = 12,
    textColor        = nil,
    fixed            = nil,
    isHeader         = nil,
  })

  numDisplayed = scp.menuHelper.createTitle(frameTable, numDisplayed, {
    text  = ReadText(1972092427, 7006),
    fixed = nil,
  })
  rowGroup = isV9 and frameTable:addRowGroup({}) or frameTable
  numDisplayed = scp.menuHelper.createDropDown(rowGroup, true, numDisplayed, {
    active           = state.ships_sel.ownerId == "player",
    dropDownData     = state.races,
    startOption      = state.ships_sel.ownerRace,
    text             = nil,
    textOverride     = "",
    onConfirmed      = function(_, id) scpSpawner.setShipSpawnData(id, "race") end,
    textColIndex     = 1,
    dropDownColIndex = 1,
    dropDownSpan     = 12,
    textColor        = nil,
    fixed            = nil,
    isHeader         = nil,
  })

  numDisplayed = scp.menuHelper.createTitle(frameTable, numDisplayed, {
    text  = ReadText(1972092427, 7007),
    fixed = nil,
  })
  rowGroup = isV9 and frameTable:addRowGroup({}) or frameTable
  numDisplayed = scp.menuHelper.createSliderRow(rowGroup, nil, numDisplayed, {
    text                = ReadText(1972092427, 7201),
    mouseOverText       = ReadText(1972092427, 7202),
    startValue          = state.ships_sel.numPerRow,
    onSliderChanged     = function(_, value) state.ships_sel.numPerRow = value end,
    onSliderConfirm     = nil,
    onSliderActivated   = nil,
    onSliderDeactivated = nil,
    min                 = nil,
    max                 = nil,
    step                = nil,
    textColIndex        = nil,
    sliderColIndex      = nil,
    sliderSpan          = nil,
    textColor           = nil,
  })
  numDisplayed = scp.menuHelper.createSliderRow(rowGroup, nil, numDisplayed, {
    text                = ReadText(1972092427, 7203),
    mouseOverText       = ReadText(1972092427, 7204),
    startValue          = state.ships_sel.rows,
    onSliderChanged     = function(_, value) state.ships_sel.rows = value end,
    onSliderConfirm     = nil,
    onSliderActivated   = nil,
    onSliderDeactivated = nil,
    min                 = nil,
    max                 = nil,
    step                = nil,
    textColIndex        = nil,
    sliderColIndex      = nil,
    sliderSpan          = nil,
    textColor           = nil,
  })

  return numDisplayed
end

function scpSpawner.createObjectMenu(frameTable, numDisplayed, consumableTypes, scp)
  local isV9 = scp.isV9
  local getConsumables = scp.helpers.getConsumables
  numDisplayed = scp.menuHelper.createTitle(frameTable, numDisplayed, {
    text  = ReadText(1972092427, 7300),
    fixed = nil,
  })

  local rowGroup = isV9 and frameTable:addRowGroup({}) or frameTable
  numDisplayed = scp.menuHelper.createDropDown(rowGroup, true, numDisplayed, {
    active           = true,
    dropDownData     = consumableTypes,
    startOption      = state.object.consumableType,
    text             = ReadText(1001, 6400),
    textOverride     = "",
    onConfirmed      = function(_, id) scpSpawner.setObjectSpawnData(id, "type", getConsumables) end,
    textColIndex     = nil,
    dropDownColIndex = nil,
    dropDownSpan     = nil,
    textColor        = nil,
    fixed            = nil,
    isHeader         = nil,
  })

  local itemOptions = getConsumables(state.object.consumableType)
  if state.object.macro == nil and #itemOptions > 0 then
    state.object.macro = itemOptions[1].id
    state.object.name  = itemOptions[1].text
  end

  numDisplayed = scp.menuHelper.createDropDown(rowGroup, true, numDisplayed, {
    active           = #itemOptions > 0,
    dropDownData     = itemOptions,
    startOption      = state.object.macro,
    text             = ReadText(1001, 23),
    textOverride     = "",
    onConfirmed      = function(_, id) scpSpawner.setObjectSpawnData(id, "item", getConsumables) end,
    textColIndex     = nil,
    dropDownColIndex = nil,
    dropDownSpan     = nil,
    textColor        = nil,
    fixed            = nil,
    isHeader         = nil,
  })

  numDisplayed = scp.menuHelper.createTitle(frameTable, numDisplayed, {
    text  = ReadText(1972092427, 7005),
    fixed = nil,
  })
  rowGroup = isV9 and frameTable:addRowGroup({}) or frameTable
  numDisplayed = scp.menuHelper.createDropDown(rowGroup, true, numDisplayed, {
    active           = #state.factions > 1,
    dropDownData     = state.factions,
    startOption      = state.object.ownerId,
    text             = nil,
    textOverride     = "",
    onConfirmed      = function(_, id) scpSpawner.setObjectSpawnData(id, "faction", getConsumables) end,
    textColIndex     = 1,
    dropDownColIndex = 1,
    dropDownSpan     = 12,
    textColor        = nil,
    fixed            = nil,
    isHeader         = nil,
  })

  numDisplayed = scp.menuHelper.createTitle(frameTable, numDisplayed, {
    text  = ReadText(1972092427, 7007),
    fixed = nil,
  })
  rowGroup = isV9 and frameTable:addRowGroup({}) or frameTable
  numDisplayed = scp.menuHelper.createSliderRow(rowGroup, nil, numDisplayed, {
    text                = ReadText(1972092427, 7301),
    mouseOverText       = ReadText(1972092427, 7302),
    startValue          = state.object.numPerRow,
    onSliderChanged     = function(_, value) state.object.numPerRow = value end,
    onSliderConfirm     = nil,
    onSliderActivated   = nil,
    onSliderDeactivated = nil,
    min                 = nil,
    max                 = nil,
    step                = nil,
    textColIndex        = nil,
    sliderColIndex      = nil,
    sliderSpan          = nil,
    textColor           = nil,
  })
  numDisplayed = scp.menuHelper.createSliderRow(rowGroup, nil, numDisplayed, {
    text                = ReadText(1972092427, 7303),
    mouseOverText       = ReadText(1972092427, 7304),
    startValue          = state.object["rows"],
    onSliderChanged     = function(_, value) state.object["rows"] = value end,
    onSliderConfirm     = nil,
    onSliderActivated   = nil,
    onSliderDeactivated = nil,
    min                 = nil,
    max                 = nil,
    step                = nil,
    textColIndex        = nil,
    sliderColIndex      = nil,
    sliderSpan          = nil,
    textColor           = nil,
  })
  numDisplayed = scp.menuHelper.createSliderRow(rowGroup, nil, numDisplayed, {
    text                = ReadText(1972092427, 7305),
    mouseOverText       = ReadText(1972092427, 7306),
    startValue          = state.object["spacing"],
    onSliderChanged     = function(_, value) state.object["spacing"] = value end,
    onSliderConfirm     = nil,
    onSliderActivated   = nil,
    onSliderDeactivated = nil,
    min                 = 100,
    max                 = 100000,
    step                = 100,
    textColIndex        = nil,
    sliderColIndex      = nil,
    sliderSpan          = nil,
    textColor           = nil,
  })

  return numDisplayed
end

-- Expose internal state
scpSpawner.state = state

-- *** Spawn action functions (called from safe_cheat_panel luaActions) ***

function scpSpawner.spawnShip(ship, loadout, ownerId, ownerRace, rows, numPerRow, loadoutFaction)
  local preset, crew = scpSpawner.PresetAndCrewForSpawnShip(ship, loadout)
  local data = {
    ship = ship,
    loadout = loadout,
    crew = crew,
    preset = preset,
    offsetComponent = ConvertStringToLuaID(tostring(interactMenu.offsetcomponent)),
    ownerId = ownerId,
    ownerRace = ownerRace,
    loadoutFaction = loadoutFaction,
    position = {
      x = interactMenu.offset.x,
      y = interactMenu.offset.y,
      z = interactMenu.offset.z
    },
    rows = rows,
    numPerRow = numPerRow
  }
  AddUITriggeredEvent("scp_main", "scp_spawn_ship", data)
  scpHelpers.interactMenuFinishAction()
end

function scpSpawner.spawnStation(stationName, constructionPlan, ownerId)
  local data = {
    name = stationName,
    offsetComponent = ConvertStringToLuaID(tostring(interactMenu.offsetcomponent)),
    constructionPlan = constructionPlan,
    ownerId = ownerId,
    position = {
      x = interactMenu.offset.x,
      y = interactMenu.offset.y,
      z = interactMenu.offset.z
    }
  }
  AddUITriggeredEvent("scp_main", "scp_spawn_station", data)
  scpHelpers.interactMenuFinishAction()
end

function scpSpawner.fixStation()
  local data = {
    station = ConvertStringToLuaID(tostring(interactMenu.componentSlot.component)),
  }
  AddUITriggeredEvent("scp_main", "scp_fix_station", data)
  scpHelpers.interactMenuFinishAction()
end

function scpSpawner.spawnObject(macro, rows, numPerRow, spacing, ownerId)
  macro = macro or "eq_arg_satellite_02_macro"
  rows = rows or 1
  numPerRow = numPerRow or 1
  spacing = spacing or 500
  ownerId = ownerId or "player"
  local baseX = interactMenu.offset.x - (numPerRow - 1) * spacing / 2
  local baseZ = interactMenu.offset.z + (rows - 1) * spacing / 2
  for row = 0, rows - 1 do
    for col = 0, numPerRow - 1 do
      local pos = ffi.new("UIPosRot", {
        x = baseX + col * spacing,
        y = interactMenu.offset.y,
        z = baseZ - row * spacing,
        yaw = interactMenu.offset.yaw,
        pitch = interactMenu.offset.pitch,
        roll = interactMenu.offset.roll
      })
      local object = C.SpawnObjectAtPos2(macro, interactMenu.offsetcomponent, pos, ownerId)
      if object ~= 0 then
        C.SetObjectForcedRadarVisible(object, true)
      end
    end
  end
  scpHelpers.interactMenuFinishAction()
end

Register_Require_Response("extensions.safe_cheat_panel.ui.scp_spawner", scpSpawner)
return scpSpawner
