local ffi = require("ffi")
local C = ffi.C

ffi.cdef [[
	typedef uint64_t UniverseID;

	typedef struct {
		const char* id;
		const char* name;
		const char* shortname;
		const char* description;
		const char* icon;
	} RaceInfo;

	uint32_t GetAllFactions(const char** result, uint32_t resultlen, bool includehidden);
	uint32_t GetAllRaces(RaceInfo* result, uint32_t resultlen);
	uint32_t GetNumAllFactions(bool includehidden);
	uint32_t GetNumAllRaces(void);
	uint32_t GetNumWares(const char* tags, bool research, const char* licenceownerid, const char* exclusiontags);
	uint32_t GetWares(const char** result, uint32_t resultlen, const char* tags, bool research, const char* licenceownerid, const char* exclusiontags);
	bool HasResearched(const char* wareid);
]]

local scp = {}

local _playerId  = nil
local _configId  = nil
local debugLevel = "none"   -- "none" | "debug" | "trace"

--- Called by safe_cheat_panel during init to provide the player ID and config key.
function scp.init(playerId, configId)
  _playerId = playerId
  _configId = configId
  -- Sync debug level from persisted config (handles Lua env reloads).
  local cfg = GetNPCBlackboard(_playerId, _configId)
  if cfg and cfg.debugMode then
    debugLevel = cfg.debugMode
    scp.debug("Initialized debug level from config: " .. debugLevel)
    scp.printGameEnvironmentStats()
  end
end

--- Returns true when the player has chosen "extended" mode in the mod config.
function scp.isExtendedMode()
  if _playerId == nil then return false end
  local cfg = GetNPCBlackboard(_playerId, _configId)
  return cfg ~= nil and cfg.mode == "extended"
end

--- Returns true when the player has chosen "developer" mode in the mod config.
function scp.isDeveloperMode()
  if _playerId == nil then return false end
  local cfg = GetNPCBlackboard(_playerId, _configId)
  return cfg ~= nil and cfg.mode == "developer"
end

--- Logs a debug message when debug level is "debug" or "trace".

function scp.info(msg)
  DebugError("SafeCheatPanel: " .. msg)
end

function scp.debug(msg)
  if debugLevel ~= "none" then
    DebugError("SafeCheatPanel: " .. msg)
  end
end

--- Logs a trace message when debug level is "trace" only.
function scp.trace(msg)
  if debugLevel == "trace" then
    DebugError("SafeCheatPanel [trace]: " .. msg)
  end
end

local interactMenu = Helper.getMenu("InteractMenu")

local config = {
  consumableDefinitions = {
    { id = "satellite",     type = "civilian" },
    { id = "navbeacon",     type = "civilian" },
    { id = "resourceprobe", type = "civilian" },
    { id = "lasertower",    type = "military" },
    { id = "mine",          type = "military" },
  }
}

function scp.getAllFactions(blacklisted)
  local playerFaction = {}
  local factions = {}
  local n = C.GetNumAllFactions(false)
  local buf = ffi.new("const char*[?]", n)
  n = C.GetAllFactions(buf, n, false)
  for i = 0, n - 1 do
    local id = ffi.string(buf[i])
    local name, primaryRace, icon = GetFactionData(id, "name", "primaryrace", "icon")
    if id == "player" then
      playerFaction[#playerFaction + 1] = { id = id, ownerrace = primaryRace, name = name, text = string.format("\027[%s] %s", icon, name), active = true, icon = "", displayremoveoption = false }
    else
      if not blacklisted or not blacklisted[id] then
        factions[#factions + 1] = { id = id, ownerrace = primaryRace, name = name, text = string.format("\027[%s] %s", icon, name), active = true, icon = "", displayremoveoption = false }
      end
    end
  end
  table.sort(factions, Helper.sortName)
  table.insert(factions, 1, playerFaction[1])
  return factions
end

function scp.getAllRaces()
  local races = {}
  if scp.isExtendedMode() then
    local n = C.GetNumAllRaces()
    local buf = ffi.new("RaceInfo[?]", n)
    n = C.GetAllRaces(buf, n)
    for i = 0, n - 1 do
      local name = ffi.string(buf[i].name)
      local icon = ffi.string(buf[i].icon)
      races[#races + 1] = { id = ffi.string(buf[i].id), name = name, text = name, active = true, icon = icon, displayremoveoption = false }
    end
    table.sort(races, Helper.sortName)
  else
    local libRaces = GetLibrary("races")
    table.sort(libRaces, Helper.sortName)
    for i = 1, #libRaces do
      races[#races + 1] = { id = libRaces[i].id, name = libRaces[i].name, text = libRaces[i].name, active = true, icon = libRaces[i].icon, displayremoveoption = false }
    end
  end
  for i = 1, #races do
    local race = races[i]
    race.text = string.format("\027[%s] %s", race.icon, race.text)
    race.icon = ""
  end
  return races
end

function scp.getAllResearch()
  local isAllUnlocked = true
  local numResearch = C.GetNumWares("", true, "", "hidden")
  local buf = ffi.new("const char*[?]", numResearch)
  local researchItems = {}
  numResearch = C.GetWares(buf, numResearch, "", true, "", "hidden")
  for i = 0, numResearch - 1 do
    local ware = ffi.string(buf[i])
    local name, description, sortOrder, precursors = GetWareData(ware, "name", "description", "sortorder", "researchprecursors")
    local completed = C.HasResearched(ware)
    if not completed then
      isAllUnlocked = false
    end
    researchItems[#researchItems + 1] = { id = ware, name = name, description = description, sortOrder = sortOrder, precursors = precursors, completed = completed }
  end
  scp.topologicalSortResearch(researchItems)
  table.sort(researchItems, scp.sortResearch)
  return researchItems, isAllUnlocked
end

function scp.isAllResearchUnlocked(researchWares)
  for i = 1, #researchWares do
    if not C.HasResearched(researchWares[i]) then
      return false
    end
  end

  return true
end

function scp.getConsumables(consumableType)
  local result = {}
  for _, consumableDef in ipairs(config.consumableDefinitions) do
    if consumableDef.type == consumableType then
      local n = C.GetNumWares(consumableDef.id, false, "", "deprecated")
      if n > 0 then
        local buf = ffi.new("const char*[?]", n)
        n = C.GetWares(buf, n, consumableDef.id, false, "", "deprecated")
        for i = 0, n - 1 do
          local ware = ffi.string(buf[i])
          local name, macro = GetWareData(ware, "name", "component")
          if macro and macro ~= "" then
            table.insert(result, {
              id = macro,
              text = name,
              active = true,
              icon = "",
              displayremoveoption = false
            })
          end
        end
      end
    end
  end
  table.sort(result, scp.sortText)
  return result
end

function scp.sortText(a, b)
  return a.text < b.text
end

function scp.topologicalSortResearch(items)
  -- Build a lookup table for items by ID
  local itemById = {}
  for i = 1, #items do
    itemById[items[i].id] = items[i]
  end

  -- Calculate depth for each item (max depth of its precursors + 1)
  local function getDepth(item, visited)
    if item.depth then
      return item.depth
    end

    visited = visited or {}
    if visited[item.id] then
      return 0  -- Circular dependency, break the cycle
    end
    visited[item.id] = true

    local maxDepth = 0
    if item.precursors and #item.precursors > 0 then
      for i = 1, #item.precursors do
        local precursorId = item.precursors[i]
        local precursor = itemById[precursorId]
        if precursor then
          local precursorDepth = getDepth(precursor, visited)
          if precursorDepth > maxDepth then
            maxDepth = precursorDepth
          end
        end
      end
      item.depth = maxDepth + 1
    else
      item.depth = 0
    end

    return item.depth
  end

  -- Calculate depth for all items
  for i = 1, #items do
    getDepth(items[i])
  end
end

function scp.sortResearch(a, b)
  -- Sort by sortOrder first (keeps categories/groups together)
  if a.sortOrder ~= b.sortOrder then
    return a.sortOrder < b.sortOrder
  end

  -- Within same sortOrder group, use topologically-assigned depth
  if a.depth ~= b.depth then
    return a.depth < b.depth
  end

  -- Finally by name
  return a.name < b.name
end

function scp.interactMenuFinishAction()
  if interactMenu.shown then
    interactMenu.onCloseElement("close")
  else
    Helper.resetUpdateHandler()
    local _config = interactMenu.uix_getConfig()
    Helper.clearFrame(interactMenu, _config.layer)
    Helper.returnFromInteractMenu(interactMenu.currentOverTable, "refresh")
    interactMenu.cleanup()
  end
end

function scp.setDebug()
  scp.debug("Updating debug level. Current level: " .. debugLevel)
  if _playerId == nil then return false end
  local cfg = GetNPCBlackboard(_playerId, _configId)
  scp.trace("Fetched value from blackboard: " .. (cfg and tostring(cfg.debugMode) or "nil"))
  if cfg ~= nil and cfg.debugMode then
    local oldDebugLevel = debugLevel
    debugLevel = cfg.debugMode or "none"
    scp.debug("Updated debug level to: " .. debugLevel)
    if oldDebugLevel == "none" and debugLevel ~= "none" then
      scp.printGameEnvironmentStats()
    end
  end
end

function scp.printGameEnvironmentStats()
  if debugLevel == "none" then
    return
  end
  local lines = {}
  lines[#lines + 1] = "=== Game Environment ==="
  lines[#lines + 1] = "Version: " .. GetVersionString() .. "  Build: " .. ffi.string(C.GetBuildVersionSuffix())

  local extensions = GetExtensionList()
  local dlcList = {}
  local modList = {}
  for _, ext in ipairs(extensions) do
    if ext.enabled then
      if ext.egosoftextension and ext.enabledbydefault then
        dlcList[#dlcList + 1] = ext
      else
        modList[#modList + 1] = ext
      end
    end
  end

  lines[#lines + 1] = "--- Enabled DLCs (" .. #dlcList .. ") ---"
  for _, dlc in ipairs(dlcList) do
    lines[#lines + 1] = string.format("  id:%-30s  name:%-40s  v%-10s  date:%s", dlc.id, dlc.name, dlc.version, dlc.date)
  end

  lines[#lines + 1] = "--- Enabled Extensions (" .. #modList .. ") ---"
  for _, mod in ipairs(modList) do
    local source = mod.egosoftextension and "ego" or (mod.isworkshop and "workshop" or (mod.personal and "personal" or "local"))
    lines[#lines + 1] = string.format("  id:%-30s  name:%-40s  author:%-25s  [%s]  v%-10s  date:%s", mod.id, mod.name, mod.author or "", source, mod.version, mod.date)
  end

  scp.debug(table.concat(lines, "\n"))
end

Register_Require_Response("extensions.safe_cheat_panel.ui.scp_helpers", scp)
return scp
