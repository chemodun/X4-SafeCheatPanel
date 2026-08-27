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
	bool HasDefaultLoadout2(const char* macroname, bool allowloadoutoverride);
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
local scpEquipment  = require("extensions.safe_cheat_panel.ui.scp_equipment")
local scpCrew       = require("extensions.safe_cheat_panel.ui.scp_crew")
local scpIdentify   = require("extensions.safe_cheat_panel.ui.scp_identify")
local scpCrewSize   = require("extensions.safe_cheat_panel.ui.scp_crewsize")
local scpWorkforce  = require("extensions.safe_cheat_panel.ui.scp_workforce")

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
    assignPurpose  = false,
    purpose        = nil,
  },
  station = {
    first            = true,
    name             = nil,
    plan = nil,
    planType         = "inGame",
    owner            = nil,
    ownerId          = nil,
    addManager       = false,
    addTrader        = false,
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
  -- Existing object pulled in through the "Edit Ship"/"Edit Station" interact action. While
  -- `object` is set the tab renders in edit mode and every spawn action is withheld.
  target = {
    object     = nil,
    isStation  = false,
    macro      = nil,
    loadout    = nil, -- identified loadout id, nil when nothing matched
    newLoadout = nil, -- dropdown selection; re-equips only while it differs from `loadout`
    plan       = nil,
    planType   = nil,
    race       = nil, -- crew race id from MD, "scpMixed", or nil until the answer arrives
    addManager = false,
    addTrader  = false,
  },
  crew = scpCrew.newState(),
  crewSize = scpCrewSize.newState(),
  workforce = scpWorkforce.newState(),
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

-- Stands in for spawnModes while a target is loaded: one inactive entry naming the mode.
local editModes = {
  { id = "editMode", text = ReadText(1972092427, 7401), active = false, icon = "", displayremoveoption = false },
}

-- Job (default AI order) offered per ship. "fight" is gated the same way vanilla jobs.xml
-- allocates it (combat-purpose slots only), not by Patrol's own <requires> (which only excludes
-- lasertowers/spacesuits); the rest mirror each order's own <requires> in aiscripts
-- (order.trade.routine / order.mining.routine / order.salvage.routine / order.build.find.task).
-- Text reused from the vanilla Orders page (1041) so labels match the in-game order names.
local shipPurposeOrders = {
  { id = "trade",   orderId = "TradeRoutine",   nameRef = { 1041, 161 } },
  { id = "mine",    orderId = "MiningRoutine",  nameRef = { 1041, 341 } },
  { id = "salvage", orderId = "SalvageRoutine", nameRef = { 1041, 821 } },
  { id = "build",   orderId = "FindBuildTasks", nameRef = { 1041, 491 } },
  { id = "fight",   orderId = "Patrol",         nameRef = { 1041, 391 } },
}

-- *** Data helpers ***

local function sortText(a, b)
  return a.text < b.text
end

-- Extended mode lists every ship ware, not only the ones the player could ever build.
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

-- Faction whose equipment suits the ship: its blueprint owner, or the maker race when the
-- ware belongs to nobody.
local function getShipDefaultFaction(macro)
  if not macro then return nil end
  local wareId = GetMacroData(macro, "ware")
  local owners = GetWareData(wareId, "blueprintsowners")
  local owner
  if owners and #owners > 0 then
    owner = owners[1]
  end
  if owner == nil or owner == "ownerless" then
    owners = GetMacroData(macro, "makerraceid")
    if owners and #owners > 0 then
      owner = owners[1]
    end
  end
  return owner
end

-- Jobs applicable to this ship. Auxiliary ships (resupply/service) get none: their real default,
-- SupplyFleet, needs a pre-existing commander/fleet a freshly spawned standalone ship never has,
-- so offering it would just be a no-op. Otherwise: mine/build need the ship's own primarypurpose,
-- salvage needs a tug/compactor shiptype, trade is open to everything else EXCEPT miners (a
-- dedicated miner should not be defaulted to trading). Returns the filtered dropdown list plus
-- the ship's primarypurpose, so the caller can preselect the best match.
local function getShipPurposeOptions(macro)
  if macro == nil then return {}, nil end
  local primaryPurpose, shipType = GetMacroData(macro, "primarypurpose", "shiptype")
  local options = {}
  if primaryPurpose == "auxiliary" then
    return options, primaryPurpose
  end
  for _, entry in ipairs(shipPurposeOrders) do
    local applicable
    if entry.id == "trade" then
      applicable = shipType ~= "lasertower" and primaryPurpose ~= "mine"
    elseif entry.id == "mine" then
      applicable = primaryPurpose == "mine"
    elseif entry.id == "salvage" then
      applicable = shipType == "tug" or shipType == "compactor"
    elseif entry.id == "build" then
      applicable = primaryPurpose == "build"
    elseif entry.id == "fight" then
      applicable = primaryPurpose == "fight"
    end
    if applicable then
      options[#options + 1] = { id = entry.id, text = ReadText(entry.nameRef[1], entry.nameRef[2]), active = true, icon = "", displayremoveoption = false }
    end
  end
  return options, primaryPurpose
end

-- Preselects the option matching the ship's own primarypurpose; falls back to the first
-- (always-applicable) entry, which is "trade" for any normal ship.
local function pickDefaultShipPurpose(options, primaryPurpose)
  for _, option in ipairs(options) do
    if option.id == primaryPurpose then return option.id end
  end
  return options[1] and options[1].id or nil
end

local function getShipPurposeOrderId(purposeId)
  for _, entry in ipairs(shipPurposeOrders) do
    if entry.id == purposeId then return entry.orderId end
  end
  return nil
end

-- A hull whose equipment is not sold carries its own default loadout; vanilla then offers that
-- alone and no generated preset (menu_ship_configuration.lua).
local function hasDefaultLoadout(macro)
  return macro ~= nil and macro ~= "" and C.HasDefaultLoadout2(macro, true)
end

-- What the loadout dropdown starts on: the fullest entry the hull offers.
local function defaultLoadoutChoice(macro)
  if not hasDefaultLoadout(macro) then return "scpDefaultHigh" end
  return scpIdentify.defaultLoadoutFill(macro).full and "default" or "scpDefaultFull"
end

-- The macro's named loadouts, headed by its default loadout or by the three generated presets.
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
  local heading = 3
  if hasDefaultLoadout(macro) then
    -- Its equipment is default-loadout only: never in a faction pool, so no preset can fit it.
    table.insert(loadouts, 1, { id = "default", text = ReadText(1001, 3231), icon = "", displayremoveoption = false, active = true })
    heading = 1
    -- Most hull defaults leave slots free; this entry takes their equipment out to every slot.
    if not scpIdentify.defaultLoadoutFill(macro).full then
      table.insert(loadouts, 2, { id = "scpDefaultFull", text = ReadText(1001, 3231) .. " (" .. ReadText(1001, 19) .. ")", icon = "", displayremoveoption = false, active = true })
      heading = 2
    end
  else
    table.insert(loadouts, 1, { id = "scpDefaultLow",    text = ReadText(1001, 7910), icon = "", displayremoveoption = false, preset = 0.1, active = true })
    table.insert(loadouts, 2, { id = "scpDefaultMedium", text = ReadText(1001, 7911), icon = "", displayremoveoption = false, preset = 0.5, active = true })
    table.insert(loadouts, 3, { id = "scpDefaultHigh",   text = ReadText(1001, 7912), icon = "", displayremoveoption = false, preset = 1.0, active = true })
  end
  if #loadouts > heading then
    -- Inactive separator between the generated entries and the named loadouts.
    table.insert(loadouts, heading + 1, { id = "none", text = ReadText(1972092427, 7219), icon = "", displayremoveoption = false, active = false })
  end
  return loadouts
end

---Whether a loadout id is still on offer for a macro - named loadouts and the default/preset
---split are both per-hull, so a selection does not survive every ship change.
local function isLoadoutOffered(macro, loadoutId)
  if loadoutId == nil then return false end
  for _, option in ipairs(getShipLoadouts(macro)) do
    if option.id == loadoutId and option.active then
      return true
    end
  end
  return false
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

-- Head counts come from the crew sliders; all that is left to read is whether the crew starts out
-- experienced - High and Default Full do, a plain Default only when it leaves no slot free.
function scpSpawner.PresetAndCrewForSpawnShip(macro, loadoutId)
  local preset = -1
  if loadoutId == "scpDefaultLow" then
    preset = 0.1
  elseif loadoutId == "scpDefaultMedium" then
    preset = 0.5
  elseif loadoutId == "scpDefaultHigh" then
    preset = 1
  end
  local crew = { hasCrewExperience = preset == 1 }
  -- Preset stays negative for both hull-default entries: MD takes the loadout whole through
  -- get_loadout, exactly as it does a named one, and must not generate over it.
  if loadoutId == "scpDefaultFull" then
    crew.hasCrewExperience = true
  elseif loadoutId == "default" then
    crew.hasCrewExperience = scpIdentify.defaultLoadoutFill(macro).full
  elseif preset <= 0 then
    local loadout = Helper.getLoadoutHelper2(C.GetLoadout2, C.GetLoadoutCounts2, "UILoadout2", 0, macro, loadoutId)
    local loadoutInfo = Helper.convertLoadout(0, macro, loadout, nil, "UILoadout2")
    crew.hasCrewExperience = loadoutInfo.hascrewexperience
  end
  return preset, crew
end

---One line per equipment plan for the log: how many candidates each loadout flag ended up with.
local function describePlan(plan)
  if plan == nil then return "none" end
  local parts = {}
  for flag, pools in pairs(plan) do
    local candidates = 0
    for _, pool in ipairs(pools) do
      candidates = candidates + #pool
    end
    parts[#parts + 1] = flag .. "=" .. #pools .. "x" .. candidates
  end
  table.sort(parts)
  return #parts > 0 and table.concat(parts, " ") or "empty"
end

---The loadout flags a fill pass may apply, for the log.
local function describeFlags(flags)
  if flags == nil then return "none" end
  local parts = {}
  for flag in pairs(flags) do
    parts[#parts + 1] = flag
  end
  table.sort(parts)
  return #parts > 0 and table.concat(parts, " ") or "empty"
end

---What MD is asked for: the loadout id it fetches and the candidate pool it fills slots from.
---Default Full resolves to the default loadout with a pool attached, not to an id of its own.
local function loadoutRequest(macro, loadoutId, preset, spawnFaction)
  if loadoutId == "scpDefaultFull" then
    local fill = scpIdentify.defaultLoadoutFill(macro)
    scpSpawner.scp.debug("Loadout: " .. tostring(macro) .. " takes its hull default filled out - pool "
      .. describePlan(fill.plan) .. ", applied to " .. describeFlags(fill.free))
    return "default", fill.plan, fill.free
  end
  local plan = scpEquipment.buildLoadoutPlan(macro, preset, spawnFaction)
  scpSpawner.scp.debug("Loadout: " .. tostring(macro) .. " takes " .. tostring(loadoutId)
    .. " (preset " .. tostring(preset) .. ", faction " .. tostring(spawnFaction) .. ") - pool " .. describePlan(plan))
  return loadoutId, plan, nil
end

function scpSpawner.getShipDefaultFaction(macro)
  return getShipDefaultFaction(macro)
end

-- Live reference, not a copy: safe_cheat_panel reads the spawner's selection through it.
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
  -- Cleared so a mode switch cannot leave an owner the rebuilt faction list no longer offers.
  state.station.ownerId = nil
  state.ships = {}
  state.races = {}
  -- A mode switch rebuilds the plan lists, so the identification cache and any loaded target go.
  scpIdentify.reset()
  state.target = { object = nil, isStation = false, addManager = false, addTrader = false }
  scpCrew.resetState(state.crew)
  scpCrewSize.resetState(state.crewSize)
  scpWorkforce.resetState(state.workforce)
  scpSpawner.initStations()
  scpSpawner.initShips()
  state.object.ownerId = "player"
end

function scpSpawner.initStations()
  if #state.constructionPlans == 0 then
    state.constructionPlans, state.playerPlans = getAllConstructionPlans()
  end
  if state.station.plan == nil then
    local planList = (state.station.planType == "player") and state.playerPlans or state.constructionPlans
    if #planList > 0 then
      state.station.plan = planList[1].id
      state.station.name = planList[1].text
    end
  end
  -- Owner applies to both plan types; getSpawnerFactions puts the player first.
  if state.station.ownerId == nil and #state.factions > 0 then
    state.station.ownerId = state.factions[1].id
  end
end

function scpSpawner.initShips()
  if #state.ships == 0 then
    state.ships = getAllShips()
    if #state.ships > 0 then
      state.ships_sel.id            = state.ships[1].id
      state.ships_sel.loadout       = defaultLoadoutChoice(state.ships[1].id)
      state.ships_sel.name          = state.ships[1].text
      state.ships_sel.ownerId       = #state.factions > 0 and state.factions[1].id or "player"
      state.ships_sel.ownerRace     = #state.factions > 0 and state.factions[1].ownerrace or nil
      state.ships_sel.loadoutFaction = getShipDefaultFaction(state.ships_sel.id)
      local purposeOptions, primaryPurpose = getShipPurposeOptions(state.ships_sel.id)
      state.ships_sel.purpose = pickDefaultShipPurpose(purposeOptions, primaryPurpose)
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

-- *** Edit mode: an existing object loaded into the tab ***

function scpSpawner.join(scp)
  scpSpawner.scp = scp
end

function scpSpawner.init()
  RegisterEvent("scp_main.objectInspected", scpSpawner.onObjectInspected)
  RegisterEvent("scp_main.objectEdited", scpSpawner.onObjectEdited)
end

local function dropTarget()
  state.target = { object = nil, isStation = false, addManager = false, addTrader = false }
  scpCrew.resetState(state.crew)
  scpCrewSize.resetState(state.crewSize)
  scpWorkforce.resetState(state.workforce)
end

---Drops a target that was destroyed or changed hands while the tab was open. Runs during frame
---setup, so it must never refresh the frame - see the onRowChanged re-entrancy rule.
local function validateTarget()
  local object = state.target.object
  if object == nil then return nil end
  if not IsValidComponent(object) or GetComponentData(object, "isplayerowned") ~= true then
    dropTarget()
    return nil
  end
  return object
end

---Shared validity for both edit actions: a player-owned ship or station, while the tab is shown.
---Stays available with a target already loaded, so another object can be picked up directly.
local function isValidEditTarget(className)
  if menu.infoTableMode ~= "safeCheatPanel" or scpSpawner.scp.tableMode ~= "scpObjectSpawn" then
    return false
  end
  local component = interactMenu.componentSlot and interactMenu.componentSlot.component
  if component == nil or component == 0 then
    return false
  end
  if not C.IsComponentClass(component, className) then
    return false
  end
  local converted = ConvertStringTo64Bit(tostring(component))
  if not IsValidComponent(converted) then
    return false
  end
  return GetComponentData(converted, "isplayerowned") == true
end

function scpSpawner.isValidEditShip()
  return isValidEditTarget("ship")
end

function scpSpawner.isValidEditStation()
  return isValidEditTarget("station")
end

---Pulls the right-clicked object's configuration into the tab. Everything Lua can read is
---resolved here; the crew race comes back later through scp_main.objectInspected.
function scpSpawner.startEdit(isStation)
  local object = ConvertStringTo64Bit(tostring(interactMenu.componentSlot.component))
  scpCrew.resetState(state.crew)
  scpCrewSize.resetState(state.crewSize)
  scpWorkforce.resetState(state.workforce)
  state.crew.enabled = true
  state.target = {
    object     = object,
    isStation  = isStation,
    macro      = GetComponentData(object, "macro"),
    addManager = false,
    addTrader  = false,
  }
  -- Crew baselines are seeded on every render, not here, so they stay right after an apply.
  if isStation then
    scpSpawner.initStations()
    state.target.plan, state.target.planType = scpIdentify.stationPlan(object, state.constructionPlans, state.playerPlans)
  else
    state.target.loadout = scpIdentify.shipLoadout(object, state.target.macro, getShipLoadouts(state.target.macro))
    state.target.newLoadout = state.target.loadout
  end
  -- Crew race is not reachable from Lua at all - no GetPersonRace in the FFI export set.
  AddUITriggeredEvent("scp_main", "scp_inspect_object", { object = ConvertStringToLuaID(tostring(object)) })
  scpSpawner.scp.debug("Edit: target set to " .. tostring(object) .. (isStation and " (station)" or " (ship)"))
  scpHelpers.interactMenuFinishAction()
  menu.refreshInfoFrame()
end

function scpSpawner.clearTarget()
  dropTarget()
  menu.refreshInfoFrame()
end

function scpSpawner.cancelEdit()
  scpSpawner.scp.debug("Edit: cancelled")
  scpSpawner.clearTarget()
end

---Reset drops the pending changes but keeps the object loaded; cancel drops the object too.
function scpSpawner.resetEdit()
  scpSpawner.scp.debug("Edit: reset pressed")
  state.crew.targets = {}
  state.crew.allSkills = false
  scpCrewSize.resetState(state.crewSize)
  scpWorkforce.resetState(state.workforce)
  state.target.newLoadout = state.target.loadout
  state.target.addManager = false
  state.target.addTrader = false
  menu.refreshInfoFrame()
end

function scpSpawner.hasEditChanges()
  if scpCrew.hasChanges(state.crew) then return true end
  if state.target.isStation then
    return state.target.addManager or state.target.addTrader or scpWorkforce.hasChanges(state.workforce)
  end
  return state.target.newLoadout ~= state.target.loadout or scpCrewSize.hasChanges(state.crewSize)
end

function scpSpawner.onObjectInspected(_, param)
  if type(param) ~= "table" or state.target.object == nil then return end
  state.target.race = param.race
  scpSpawner.scp.debug("Edit: crew race reported as " .. tostring(param.race))
  menu.refreshInfoFrame()
end

function scpSpawner.onObjectEdited()
  scpSpawner.scp.debug("Edit: MD confirmed the changes, refreshing")
  state.crew.targets = {}
  state.crew.allSkills = false
  scpCrewSize.resetState(state.crewSize)
  scpWorkforce.resetState(state.workforce)
  state.target.addManager = false
  state.target.addTrader = false
  if state.target.object ~= nil and not state.target.isStation then
    state.target.loadout = state.target.newLoadout
  end
  menu.refreshInfoFrame()
end

function scpSpawner.applyEdit()
  local object = validateTarget()
  if object == nil then return end
  -- Components crossing AddUITriggeredEvent must be LuaIDs, not the 64-bit ids used locally.
  local data = {
    object    = ConvertStringToLuaID(tostring(object)),
    isStation = state.target.isStation,
    allSkills = state.crew.allSkills,
    skills    = scpCrew.getChanges(state.crew),
  }
  if not state.target.isStation and scpCrewSize.hasChanges(state.crewSize) then
    data.crewSize = scpCrewSize.getChange(state.crewSize, (scpCrewSize.collect(object)))
  end
  if state.target.isStation then
    data.addManager = state.target.addManager
    data.addTrader  = state.target.addTrader
    data.workforce  = scpWorkforce.getChange(state.workforce)
  elseif state.target.newLoadout ~= state.target.loadout then
    -- Only a moved loadout dropdown re-equips; leaving it alone never touches the equipment.
    local preset = scpSpawner.PresetAndCrewForSpawnShip(state.target.macro, state.target.newLoadout)
    local loadoutFaction = getShipDefaultFaction(state.target.macro)
    local mdLoadout, equipment, fillFlags = loadoutRequest(state.target.macro, state.target.newLoadout, preset,
      (preset > 0 and loadoutFaction) or "player")
    -- The equipment libraries read the macro off $spawnData.$ship, so it travels under that name.
    data.ship           = state.target.macro
    data.loadout        = mdLoadout
    data.preset         = preset
    data.loadoutFaction = loadoutFaction
    data.equipment      = equipment
    data.fillFlags      = fillFlags
  end
  scpSpawner.scp.debug("Edit: apply pressed, allSkills=" .. tostring(data.allSkills) .. ", loadout=" .. tostring(data.loadout)
    .. ", workforce=" .. tostring(data.workforce)
    .. ", crew=" .. (data.crewSize and (data.crewSize.marines .. " marines / " .. data.crewSize.service .. " service") or "unchanged"))
  AddUITriggeredEvent("scp_main", "scp_edit_object", data)
end

-- *** Action condition helpers ***

function scpSpawner.showSpawnOption(mode, tableMode, devtools)
  if menu.infoTableMode ~= "safeCheatPanel" then return false end
  if tableMode ~= "scpObjectSpawn" or state.mode.id ~= mode then return false end
  -- Spawning is withheld while an object is loaded for editing; the two share the same rows.
  if state.target.object ~= nil then return false end
  if mode == "spawnModeStation" then
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
  return loadoutId == "scpDefaultLow" or loadoutId == "scpDefaultMedium" or loadoutId == "scpDefaultHigh"
end

---Switching to a plan that builds no pier or build module must drop a pending trader request.
local function clearTraderIfPlanCannotEquip()
  if state.station.addTrader and not scpIdentify.planCanEquipShips(state.station.plan) then
    state.station.addTrader = false
    state.crew.targets.trader = nil
  end
end

---Same for the workforce: a plan without a habitation module builds nowhere to put workers.
local function clearWorkforceIfPlanHasNoHabitation()
  if state.workforce.enabled and not scpIdentify.planHasHabitation(state.station.plan) then
    scpWorkforce.resetState(state.workforce)
  end
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
    -- The two plan lists are disjoint, so the selected plan never survives a type switch.
    local planList = (id == "player") and state.playerPlans or state.constructionPlans
    if #planList > 0 then
      state.station.plan = planList[1].id
      state.station.name = planList[1].text
    else
      state.station.plan = nil
      state.station.name = nil
    end
  elseif dataType == "addManager" then
    state.station.addManager = id
    if not id then state.crew.targets.manager = nil end
  elseif dataType == "addTrader" then
    state.station.addTrader = id
    if not id then state.crew.targets.trader = nil end
  else
    state.station.ownerId = id
  end
  if dataType == "station" or dataType == "planType" then
    clearTraderIfPlanCannotEquip()
    clearWorkforceIfPlanHasNoHabitation()
  end
  menu.refreshInfoFrame()
end

function scpSpawner.setShipSpawnData(id, dataType)
  if dataType == "ship" then
    state.ships_sel.id = id
    -- A loadout the new hull does not offer falls back to its head entry.
    if not isLoadoutOffered(id, state.ships_sel.loadout) then
      state.ships_sel.loadout = defaultLoadoutChoice(id)
    end
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
  elseif dataType == "assignPurpose" then
    state.ships_sel.assignPurpose = id
  elseif dataType == "purpose" then
    state.ships_sel.purpose = id
  end
  -- Only a generated preset needs a loadout faction; a named loadout brings its own equipment.
  if dataType == "ship" or dataType == "loadout" then
    if isPresetLoadout(state.ships_sel.loadout) then
      state.ships_sel.loadoutFaction = getShipDefaultFaction(state.ships_sel.id)
    else
      state.ships_sel.loadoutFaction = nil
    end
  end
  -- The applicable job list depends on the ship macro, so the selection may no longer fit.
  -- A ship with no applicable job (e.g. auxiliary) forces the checkbox off, not just greyed out,
  -- so a stale assignPurpose=true from a previous ship can never carry a job into spawnShip.
  if dataType == "ship" then
    local purposeOptions, primaryPurpose = getShipPurposeOptions(state.ships_sel.id)
    state.ships_sel.purpose = pickDefaultShipPurpose(purposeOptions, primaryPurpose)
    if #purposeOptions == 0 then
      state.ships_sel.assignPurpose = false
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
    -- First open, before reset() has run.
    state.factions = getSpawnerFactions({})
  end

  local editing = validateTarget() ~= nil

  numDisplayed = scp.menuHelper.createTitle(frameTable, numDisplayed, {
    text  = ReadText(1972092427, editing and 7400 or 7000),
    fixed = nil,
  })

  local rowGroup = isV9 and frameTable:addRowGroup({}) or frameTable
  numDisplayed = scp.menuHelper.createDropDown(rowGroup, true, numDisplayed, {
    active           = not editing,
    dropDownData     = editing and editModes or spawnModes,
    startOption      = editing and "editMode" or state.mode.id,
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

  if editing then
    if state.target.isStation then
      numDisplayed = scpSpawner.createStationEditMenu(frameTable, numDisplayed, scp)
    else
      numDisplayed = scpSpawner.createShipEditMenu(frameTable, numDisplayed, scp)
    end
  elseif state.mode.id == "spawnModeStation" then
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
  end

  -- Owner applies to either plan type; outside Extended mode the list holds the player alone.
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

  -- Vanilla only withholds the manager and trader from player-owned stations.
  if state.station.ownerId == "player" then
    numDisplayed = scp.menuHelper.createTitle(frameTable, numDisplayed, {
      text  = ReadText(1972092427, 7420),
      fixed = nil,
    })
    rowGroup = isV9 and frameTable:addRowGroup({}) or frameTable
    numDisplayed = scp.menuHelper.createCheckBoxOnLeft(rowGroup, "spawn_add_manager", numDisplayed, {
      active        = true,
      checked       = state.station.addManager,
      text          = ReadText(1972092427, 7421),
      mouseOverText = ReadText(1972092427, 7422),
      textColIndex  = 2,
      onClick       = function(_, checked) scpSpawner.setStationSpawnData(checked, "addManager") end,
    })
    -- A trader has nowhere to stand unless the plan builds a pier or a build module.
    if scpIdentify.planCanEquipShips(state.station.plan) then
      numDisplayed = scp.menuHelper.createCheckBoxOnLeft(rowGroup, "spawn_add_trader", numDisplayed, {
        active        = true,
        checked       = state.station.addTrader,
        text          = ReadText(1972092427, 7423),
        mouseOverText = ReadText(1972092427, 7424),
        textColIndex  = 2,
        onClick       = function(_, checked) scpSpawner.setStationSpawnData(checked, "addTrader") end,
      })
    end

    numDisplayed = scp.menuHelper.createTitle(frameTable, numDisplayed, {
      text  = ReadText(1972092427, 7410),
      fixed = nil,
    })
    rowGroup = isV9 and frameTable:addRowGroup({}) or frameTable
    numDisplayed = scpCrew.addEnableRow(rowGroup, numDisplayed, scp, state.crew)
    if state.crew.enabled then
      numDisplayed = scpCrew.addSpawnRows(rowGroup, numDisplayed, scp, state.crew, scpSpawner.getStationSpawnCategories())
      numDisplayed = scpCrew.addAllSkillsRow(rowGroup, numDisplayed, scp, state.crew, true)
    end

    -- A plan with no habitation module builds a station with no workforce capacity.
    if scpIdentify.planHasHabitation(state.station.plan) then
      rowGroup = isV9 and frameTable:addRowGroup({}) or frameTable
      numDisplayed = scpWorkforce.addRows(rowGroup, numDisplayed, scp, state.workforce, nil)
    end
  end

  return numDisplayed
end

---Posts a spawned player station will have: defence and engineer always, manager and trader on request.
function scpSpawner.getStationSpawnCategories()
  local categories = {}
  if state.station.addManager then categories[#categories + 1] = "manager" end
  if state.station.addTrader then categories[#categories + 1] = "trader" end
  categories[#categories + 1] = "defence"
  categories[#categories + 1] = "engineer"
  return categories
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

  -- Auto-assigning a job order only makes sense for NPC-owned spawns; the player flies their
  -- own ships directly. The title+checkbox always show for a non-player owner so the panel
  -- doesn't jump around; a ship with no applicable job (e.g. auxiliary) just shows them disabled.
  if state.ships_sel.ownerId ~= "player" then
    local purposeOptions, _ = getShipPurposeOptions(state.ships_sel.id)
    local hasPurposeOptions = #purposeOptions > 0

    numDisplayed = scp.menuHelper.createTitle(frameTable, numDisplayed, {
      text  = ReadText(1972092427, 7213),
      fixed = nil,
    })
    rowGroup = isV9 and frameTable:addRowGroup({}) or frameTable
    numDisplayed = scp.menuHelper.createCheckBoxOnLeft(rowGroup, true, numDisplayed, {
      checked       = hasPurposeOptions and state.ships_sel.assignPurpose,
      active        = hasPurposeOptions,
      text          = ReadText(1972092427, 7210),
      mouseOverText = ReadText(1972092427, 7211),
      textColIndex  = 2,
      checkBoxColIndex = nil,
      textColor     = nil,
      fixed         = nil,
      onClick       = function(_, checked) scpSpawner.setShipSpawnData(checked, "assignPurpose") end,
    })
    if hasPurposeOptions then
      numDisplayed = scp.menuHelper.createDropDown(rowGroup, true, numDisplayed, {
        active           = state.ships_sel.assignPurpose,
        dropDownData     = purposeOptions,
        startOption      = state.ships_sel.purpose,
        text             = ReadText(1972092427, 7212),
        textOverride     = "",
        onConfirmed      = function(_, id) scpSpawner.setShipSpawnData(id, "purpose") end,
        textColIndex     = nil,
        dropDownColIndex = nil,
        dropDownSpan     = nil,
        textColor        = nil,
        fixed            = nil,
        isHeader         = nil,
      })
    end
  end

  -- Authoritative for a spawn: the ship gets exactly this crew, whatever the loadout would have set.
  local crewCapacity = scpCrewSize.getMacroCapacity(state.ships_sel.id)
  if crewCapacity > 0 then
    rowGroup = isV9 and frameTable:addRowGroup({}) or frameTable
    numDisplayed = scpCrewSize.addRows(rowGroup, numDisplayed, scp, state.crewSize, crewCapacity, nil, nil)
  end

  -- Unchecked, the spawned crew keeps the loadout preset's randomised skill ranges.
  numDisplayed = scp.menuHelper.createTitle(frameTable, numDisplayed, {
    text  = ReadText(1972092427, 7410),
    fixed = nil,
  })
  rowGroup = isV9 and frameTable:addRowGroup({}) or frameTable
  numDisplayed = scpCrew.addEnableRow(rowGroup, numDisplayed, scp, state.crew)
  if state.crew.enabled then
    numDisplayed = scpCrew.addSpawnRows(rowGroup, numDisplayed, scp, state.crew, scpCrew.shipCategories)
    numDisplayed = scpCrew.addAllSkillsRow(rowGroup, numDisplayed, scp, state.crew, true)
  end

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

-- *** Edit mode sections ***

local function addTargetInfoRow(rowGroup, numDisplayed, scp, object)
  local name, idcode, icon, sector, owner = GetComponentData(object, "name", "idcode", "icon", "sector", "owner")
  local factionColor = owner and Helper.convertColorToText(GetFactionData(owner, "color")) or ""
  return scp.menuHelper.createIconWithTextRow(rowGroup, "edit_object_info", numDisplayed, {
    icon      = (icon ~= nil and icon ~= "") and icon or "menu_info",
    textLeft  = string.format("%s%s (%s)", factionColor, name, idcode),
    textRight = sector or "",
    fixed     = true,
  })
end

---One-entry dropdown standing in for a control that is display-only in edit mode.
local function fixedOption(id, text)
  return { { id = id, text = text, active = false, icon = "", displayremoveoption = false } }
end

local function addEditButtons(frameTable, numDisplayed)
  local row = frameTable:addRow("edit_buttons", { fixed = true, bgColor = Color["row_background_unselectable"] })
  row[1]:setColSpan(4):createButton({ active = true }):setText(ReadText(1001, 64), { halign = "center" }) -- Cancel
  row[1].handlers.onClick = scpSpawner.cancelEdit
  row[5]:setColSpan(4):createButton({ active = function() return scpSpawner.hasEditChanges() end }):setText(ReadText(1001, 3318), { halign = "center" }) -- Reset
  row[5].handlers.onClick = scpSpawner.resetEdit
  row[9]:setColSpan(4):createButton({ active = function() return scpSpawner.hasEditChanges() end }):setText(ReadText(1972092427, 7430), { halign = "center", color = Color["text_positive"] })
  row[9].handlers.onClick = scpSpawner.applyEdit
  return numDisplayed + 1
end

---The crew race the ship carries, display-only: changing it is not offered, so one inactive entry.
local function addRaceRow(rowGroup, numDisplayed, scp)
  local raceId, raceText = state.target.race, nil
  if raceId == nil then
    raceText = ReadText(1972092427, 7405) -- Unknown, until MD answers
  elseif raceId == "scpMixed" then
    raceText = ReadText(1972092427, 7403) -- Mixed
  else
    for _, race in ipairs(state.races) do
      if race.id == raceId then
        raceText = race.text
        break
      end
    end
    raceText = raceText or raceId
  end
  return scp.menuHelper.createDropDown(rowGroup, true, numDisplayed, {
    active           = false,
    dropDownData     = fixedOption(raceId or "scpUnknown", raceText),
    startOption      = raceId or "scpUnknown",
    text             = nil,
    textOverride     = "",
    onConfirmed      = nil,
    textColIndex     = 1,
    dropDownColIndex = 1,
    dropDownSpan     = 12,
    textColor        = nil,
    fixed            = nil,
    isHeader         = nil,
  })
end

function scpSpawner.createShipEditMenu(frameTable, numDisplayed, scp)
  local isV9 = scp.isV9
  local object = state.target.object
  local macro = state.target.macro or ""
  scpSpawner.initShips()

  local rowGroup = isV9 and frameTable:addRowGroup({}) or frameTable
  numDisplayed = addTargetInfoRow(rowGroup, numDisplayed, scp, object)

  -- The ship itself is fixed: a target's macro may not even be in the spawnable ware list.
  numDisplayed = scp.menuHelper.createTitle(frameTable, numDisplayed, {
    text  = ReadText(1972092427, 7200),
    fixed = nil,
  })
  rowGroup = isV9 and frameTable:addRowGroup({}) or frameTable
  numDisplayed = scp.menuHelper.createDropDown(rowGroup, true, numDisplayed, {
    active           = false,
    dropDownData     = fixedOption(macro, GetMacroData(macro, "name")),
    startOption      = macro,
    text             = nil,
    textOverride     = "",
    onConfirmed      = nil,
    textColIndex     = 1,
    dropDownColIndex = 1,
    dropDownSpan     = 12,
    textColor        = nil,
    fixed            = nil,
    isHeader         = nil,
  })

  -- Loadout is the one identified control that stays editable: picking another re-equips.
  local loadoutOptions = getShipLoadouts(macro)
  if state.target.loadout == nil then
    table.insert(loadoutOptions, 1, { id = "scpCustom", text = ReadText(1972092427, 7402), icon = "", displayremoveoption = false, active = false })
  end
  numDisplayed = scp.menuHelper.createTitle(frameTable, numDisplayed, {
    text  = ReadText(1001, 7905),
    fixed = nil,
  })
  rowGroup = isV9 and frameTable:addRowGroup({}) or frameTable
  numDisplayed = scp.menuHelper.createDropDown(rowGroup, true, numDisplayed, {
    active           = true,
    dropDownData     = loadoutOptions,
    startOption      = state.target.newLoadout or "scpCustom",
    text             = nil,
    textOverride     = "",
    onConfirmed      = function(_, id) scpSpawner.setEditData(id, "loadout") end,
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
  numDisplayed = addRaceRow(rowGroup, numDisplayed, scp)

  -- Seeded on every render, like the crew-skill baselines, so it stays right after an apply.
  local crewCapacity, crewCurrent, crewCurrentMarines = scpCrewSize.seedInitial(state.crewSize, object)
  if crewCapacity > 0 then
    if not isV9 then
      frameTable:addEmptyRow(Helper.standardTextHeight / 2, { fixed = true })
    end
    rowGroup = isV9 and frameTable:addRowGroup({}) or frameTable
    numDisplayed = scpCrewSize.addRows(rowGroup, numDisplayed, scp, state.crewSize, crewCapacity, crewCurrent, crewCurrentMarines)
  end

  numDisplayed = scp.menuHelper.createTitle(frameTable, numDisplayed, {
    text  = ReadText(1972092427, 7410),
    fixed = nil,
  })
  rowGroup = isV9 and frameTable:addRowGroup({}) or frameTable
  if not isV9 then
    frameTable:addEmptyRow(Helper.standardTextHeight / 2, { fixed = true })
  end
  local crewData = scpCrew.collectShip(object)
  scpCrew.seedInitial(state.crew, crewData, scpCrew.shipCategories)
  numDisplayed = scpCrew.addShipRows(rowGroup, numDisplayed, scp, state.crew, crewData, true)
  numDisplayed = scpCrew.addAllSkillsRow(rowGroup, numDisplayed, scp, state.crew, true)

  if not isV9 then
    frameTable:addEmptyRow(Helper.standardTextHeight / 2, { fixed = true })
  end
  return addEditButtons(frameTable, numDisplayed)
end

function scpSpawner.createStationEditMenu(frameTable, numDisplayed, scp)
  local isV9 = scp.isV9
  local object = state.target.object
  scpSpawner.initStations()

  local rowGroup = isV9 and frameTable:addRowGroup({}) or frameTable
  numDisplayed = addTargetInfoRow(rowGroup, numDisplayed, scp, object)

  -- Modules cannot be rearranged from here, so both plan controls are display-only.
  local planText, planId = ReadText(1972092427, 7405), "scpUnknown"
  if state.target.plan then
    local planList = (state.target.planType == "player") and state.playerPlans or state.constructionPlans
    for _, plan in ipairs(planList) do
      if plan.id == state.target.plan then
        planText, planId = plan.text, plan.id
        break
      end
    end
  end
  numDisplayed = scp.menuHelper.createTitle(frameTable, numDisplayed, {
    text  = ReadText(1972092427, 7101),
    fixed = nil,
  })
  rowGroup = isV9 and frameTable:addRowGroup({}) or frameTable
  numDisplayed = scp.menuHelper.createDropDown(rowGroup, true, numDisplayed, {
    active           = false,
    dropDownData     = fixedOption(state.target.planType or "scpUnknown",
      state.target.planType and ReadText(1972092427, state.target.planType == "player" and 7103 or 7102) or ReadText(1972092427, 7405)),
    startOption      = state.target.planType or "scpUnknown",
    text             = nil,
    textOverride     = "",
    onConfirmed      = nil,
    textColIndex     = 1,
    dropDownColIndex = 1,
    dropDownSpan     = 12,
    textColor        = nil,
    fixed            = nil,
    isHeader         = nil,
  })
  numDisplayed = scp.menuHelper.createTitle(frameTable, numDisplayed, {
    text  = ReadText(1972092427, 7100),
    fixed = nil,
  })
  rowGroup = isV9 and frameTable:addRowGroup({}) or frameTable
  numDisplayed = scp.menuHelper.createDropDown(rowGroup, true, numDisplayed, {
    active           = false,
    dropDownData     = fixedOption(planId, planText),
    startOption      = planId,
    text             = nil,
    textOverride     = "",
    onConfirmed      = nil,
    textColIndex     = 1,
    dropDownColIndex = 1,
    dropDownSpan     = 12,
    textColor        = nil,
    fixed            = nil,
    isHeader         = nil,
  })

  numDisplayed = scp.menuHelper.createTitle(frameTable, numDisplayed, {
    text  = ReadText(1972092427, 7420),
    fixed = nil,
  })
  rowGroup = isV9 and frameTable:addRowGroup({}) or frameTable
  if not isV9 then
    frameTable:addEmptyRow(Helper.standardTextHeight / 2, { fixed = true })
  end
  local crewData = scpCrew.collectStation(object)
  scpCrew.seedInitial(state.crew, crewData, scpCrew.stationCategories)
  numDisplayed = scpSpawner.addStationPostRows(rowGroup, numDisplayed, scp, object, crewData)
  numDisplayed = scpCrew.addStationRows(rowGroup, numDisplayed, scp, state.crew, crewData, true,
    { manager = state.target.addManager, trader = state.target.addTrader })
  numDisplayed = scpCrew.addAllSkillsRow(rowGroup, numDisplayed, scp, state.crew, true)

  rowGroup = isV9 and frameTable:addRowGroup({}) or frameTable
  numDisplayed = scpWorkforce.addRows(rowGroup, numDisplayed, scp, state.workforce, object)

  if not isV9 then
    frameTable:addEmptyRow(Helper.standardTextHeight / 2, { fixed = true })
  end
  return addEditButtons(frameTable, numDisplayed)
end

---The two "create this post" checkboxes. Each disappears once its post is filled; the trader's
---greys out on the live canequipships, the same gate vanilla's CreateShipDealerEntity applies.
function scpSpawner.addStationPostRows(rowGroup, numDisplayed, scp, object, crewData)
  if not crewData.manager.exists then
    numDisplayed = scp.menuHelper.createCheckBoxOnLeft(rowGroup, "edit_add_manager", numDisplayed, {
      active        = true,
      checked       = state.target.addManager,
      text          = ReadText(1972092427, 7421),
      mouseOverText = ReadText(1972092427, 7422),
      textColIndex  = 2,
      fixed         = true,
      onClick       = function(_, checked) scpSpawner.setEditData(checked, "addManager") end,
    })
  end
  local trader = GetComponentData(object, "shiptrader")
  if trader == nil or trader == 0 then
    local canEquip = GetComponentData(object, "canequipships") == true
    numDisplayed = scp.menuHelper.createCheckBoxOnLeft(rowGroup, "edit_add_trader", numDisplayed, {
      active        = canEquip,
      checked       = canEquip and state.target.addTrader,
      text          = ReadText(1972092427, 7423),
      mouseOverText = ReadText(1972092427, 7424),
      textColIndex  = 2,
      textColor     = canEquip and Color["text_normal"] or Color["text_inactive"],
      fixed         = true,
      onClick       = function(_, checked) scpSpawner.setEditData(checked, "addTrader") end,
    })
  end
  return numDisplayed
end

function scpSpawner.setEditData(id, dataType)
  if dataType == "loadout" then
    state.target.newLoadout = id
  elseif dataType == "addManager" then
    state.target.addManager = id
    -- The slider only writes on change, so a ticked box seeds a value itself.
    state.crew.targets.manager = id and (state.crew.targets.manager or 3) or nil
  elseif dataType == "addTrader" then
    state.target.addTrader = id
    state.crew.targets.trader = id and (state.crew.targets.trader or 3) or nil
  end
  menu.refreshInfoFrame()
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

scpSpawner.state = state

-- *** Spawn action functions (called from safe_cheat_panel luaActions) ***

function scpSpawner.spawnShip(ship, loadout, ownerId, ownerRace, rows, numPerRow, loadoutFaction, assignPurpose, purpose)
  local preset, crew = scpSpawner.PresetAndCrewForSpawnShip(ship, loadout)
  -- MD reconciles the ship against these counts instead of adding to what the loadout left.
  -- A macro with no crew berths sends neither key, so MD leaves its crew alone.
  local crewCapacity = scpCrewSize.getMacroCapacity(ship)
  if crewCapacity > 0 then
    crew.marines, crew.service = select(2, scpCrewSize.targets(state.crewSize, crewCapacity))
  end
  -- Must match the faction MD creates the ship under, so both sides judge equipment alike.
  local spawnFaction = (preset > 0 and loadoutFaction) or ownerId
  -- Player-owned ships stay under direct player control; never auto-assign them a job.
  local purposeOrderId = (ownerId ~= "player" and assignPurpose) and getShipPurposeOrderId(purpose) or nil
  local mdLoadout, equipment, fillFlags = loadoutRequest(ship, loadout, preset, spawnFaction)
  local data = {
    ship = ship,
    loadout = mdLoadout,
    crew = crew,
    preset = preset,
    -- Candidates for slots the faction pool cannot reach or a hull default left free; nil for a named loadout.
    equipment = equipment,
    -- Which categories the fill pass may apply to; a full one must be left as the default left it.
    fillFlags = fillFlags,
    offsetComponent = ConvertStringToLuaID(tostring(interactMenu.offsetcomponent)),
    ownerId = ownerId,
    ownerRace = ownerRace,
    loadoutFaction = loadoutFaction,
    purposeOrderId = purposeOrderId,
    -- Absent unless the checkbox is on, so an untouched spawn keeps the preset's ranges.
    crewSkills = state.crew.enabled and scpCrew.pickCategories(state.crew, scpCrew.shipCategories) or nil,
    allSkills = state.crew.enabled and state.crew.allSkills or false,
    position = {
      x = interactMenu.offset.x,
      y = interactMenu.offset.y,
      z = interactMenu.offset.z
    },
    rows = rows,
    numPerRow = numPerRow
  }
  scpSpawner.scp.debug("Spawn: " .. tostring(ship) .. " x" .. tostring(rows * numPerRow)
    .. " for " .. tostring(ownerId) .. "/" .. tostring(ownerRace)
    .. ", loadout " .. tostring(loadout) .. " sent as " .. tostring(mdLoadout)
    .. ", preset " .. tostring(preset)
    .. ", experienced crew " .. tostring(crew.hasCrewExperience)
    .. ", marines " .. tostring(crew.marines) .. ", service " .. tostring(crew.service)
    .. ", equipment " .. describePlan(equipment)
    .. ", fill " .. describeFlags(fillFlags)
    .. ", job " .. tostring(purposeOrderId))
  AddUITriggeredEvent("scp_main", "scp_spawn_ship", data)
  scpHelpers.interactMenuFinishAction()
end

function scpSpawner.spawnStation(stationName, constructionPlan, ownerId)
  local data = {
    name = stationName,
    offsetComponent = ConvertStringToLuaID(tostring(interactMenu.offsetcomponent)),
    constructionPlan = constructionPlan,
    ownerId = ownerId,
    -- Vanilla withholds both posts from player-owned stations; these two put them back.
    addManager = ownerId == "player" and state.station.addManager or false,
    addTrader = ownerId == "player" and state.station.addTrader or false,
    crewSkills = (ownerId == "player" and state.crew.enabled) and scpCrew.pickCategories(state.crew, scpSpawner.getStationSpawnCategories()) or nil,
    allSkills = (ownerId == "player" and state.crew.enabled) and state.crew.allSkills or false,
    workforce = ownerId == "player" and scpWorkforce.getChange(state.workforce) or nil,
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
