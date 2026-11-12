local ffi = require("ffi")
local C = ffi.C

ffi.cdef [[

	typedef uint64_t UniverseID;

	typedef struct {
		const char* ware;
		const char* macro;
		int amount;
	} UIWareInfo;
	typedef struct {
		UniverseID reserverid;
		const char* ware;
		uint32_t amount;
		bool isbuyreservation;
		double eta;
		TradeID tradedealid;
		MissionID missionid;
		bool isvirtual;
		bool issupply;
	} WareReservationInfo2;

  uint32_t PrepareBuildSequenceResources2(UniverseID holomapid, UniverseID stationid, bool useplanned);
  uint32_t GetBuildSequenceResources(UIWareInfo* result, uint32_t resultlen);
	uint32_t GetNumCargo(UniverseID containerid, const char* tags);
	uint32_t GetCargo(UIWareInfo* result, uint32_t resultlen, UniverseID containerid, const char* tags);
	uint32_t GetNumContainerWareReservations2(UniverseID containerid, bool includevirtual, bool includemission, bool includesupply);
	uint32_t GetContainerWareReservations2(WareReservationInfo2* result, uint32_t resultlen, UniverseID containerid, bool includevirtual, bool includemission, bool includesupply);
]]

local menu         = Helper.getMenu("MapMenu")
local interactMenu = Helper.getMenu("InteractMenu")

local PAGE_ID = 1972092427

local scpStation = {
}

-- Runs an action over every station of the picked station's owner, construction sites included;
-- the gathered wares reach MD as a single event after the last one.
function scpStation.processForAllStations(functionToProcess)
  local station = interactMenu.componentSlot.component
  if station == nil then return end
  local object64 = ConvertStringTo64Bit(tostring(station))
  local owner = GetComponentData(object64, "owner")
  local stations = GetContainedStationsByOwner(owner, nil, true)
  scpStation.debug(string.format("Processing all stations (%d) for owner: %s", #stations, owner))
  local allWaresData = {}
  for i = 1, #stations do
    local station = stations[i]
    local object64 = ConvertStringTo64Bit(tostring(station))
    local owner, realclassid, name = GetComponentData(object64, "owner", "realclassid", "name")
    if Helper.isComponentClass(realclassid, "station") and owner ~= nil and (owner == "player" or scpStation.scp.isExtendedMode()) then
      scpStation.trace(string.format("Processing station %d/%d: name: %s, owner: %s, object: %s", i, #stations, name, owner, tostring(station)))
      allWaresData = functionToProcess(station, false, allWaresData) or allWaresData
    end
  end
  scpStation.sendWaresData(allWaresData)
  scpStation.helpers.interactMenuFinishAction()
end

function scpStation.isValidForceBuildCompletion()
  local station = interactMenu.componentSlot.component
  if station == nil then return false end
  local object64 = ConvertStringTo64Bit(tostring(station))
  local owner, realclassid = GetComponentData(object64, "owner", "realclassid")
  if not Helper.isComponentClass(realclassid, "station") then return false end
  if owner == nil or (owner ~= "player" and not scpStation.scp.isExtendedMode()) then return false end
  if IsComponentConstruction(object64) then return true end
  if C.GetNumPlannedStationModules(object64, false) > 0 then return true end
  return false
end

function scpStation.isValidForceBuildCompletionForAllFaction()
  local station = interactMenu.componentSlot.component
  if station == nil then return false end
  local object64 = ConvertStringTo64Bit(tostring(station))
  local owner, realclassid = GetComponentData(object64, "owner", "realclassid")
  if not Helper.isComponentClass(realclassid, "station") then return false end
  if owner == nil or (owner ~= "player" and not scpStation.scp.isExtendedMode()) then return false end
  return scpStation.scp.isExtendedMode()
end

function scpStation.forceBuildCompletion(station, finishAction, _)
  local station = station ~= nil and station or interactMenu.componentSlot.component
  finishAction = finishAction == nil and true or finishAction
  if station == nil then return false end
  local object64 = ConvertStringTo64Bit(tostring(station))
  local owner, realclassid, name = GetComponentData(object64, "owner", "realclassid", "name")
  if Helper.isComponentClass(realclassid, "station") and (C.GetNumPlannedStationModules(object64, false) > 0 or IsComponentConstruction(object64)) then
    C.ForceBuildCompletion(object64)
    scpStation.debug("Forced build completion for station: " .. tostring(name) .. ", owner: " .. tostring(owner))
  end
  if finishAction then
    scpStation.helpers.interactMenuFinishAction()
  end
end

function scpStation.forceBuildCompletionForAllFaction()
  scpStation.processForAllStations(scpStation.forceBuildCompletion)
end


-- What the build storage still lacks: the holomap's build sequence, planned modules included,
-- minus what is already stored.
function scpStation.getBuildStorageGap(station, buildStorage)
  local neededResources = {}
  local numTotalResources = C.PrepareBuildSequenceResources2(menu.holomap, station, true)
  scpStation.trace(string.format("Total needed resources for build completion: %d", numTotalResources))
  if numTotalResources > 0 then
    local buf = ffi.new("UIWareInfo[?]", numTotalResources)
    numTotalResources = C.GetBuildSequenceResources(buf, numTotalResources)
    for i = 0, numTotalResources - 1 do
      neededResources[ffi.string(buf[i].ware)] = buf[i].amount 
    end
  end
  local n = C.GetNumCargo(buildStorage, "stationbuilding")
  scpStation.trace(string.format("Current resources in build storage: %d", n))
  local buf = ffi.new("UIWareInfo[?]", n)
  n = C.GetCargo(buf, n, buildStorage, "stationbuilding")
  local count = 0
  for i = 0, n - 1 do
    local ware = ffi.string(buf[i].ware)
    if neededResources[ware] ~= nil then
      local amountGap = neededResources[ware] - buf[i].amount
      if amountGap > 0 then
        neededResources[ware] = amountGap
        count = count + 1
      else
        neededResources[ware] = nil
      end
    end
  end
  count = scpStation.applyReservations(buildStorage, neededResources, count)
  scpStation.debug(string.format("Number of resources in build storage with gaps: %d", count))
  return neededResources
end

-- Ship-building wares the queued builds of a wharf, shipyard or equipment dock still miss.
-- Their buy and production limits are 0; the C calls are declared by vanilla's menus.
local function getMissingShipBuildResources(station64)
  local ok, missing = pcall(function()
    local result = {}
    local n = C.GetNumContainerBuildResources(station64)
    if n == 0 then return result end
    local names = ffi.new("const char*[?]", n)
    n = C.GetContainerBuildResources(names, n, station64)
    local buildWares = {}
    for i = 0, n - 1 do
      buildWares[ffi.string(names[i])] = true
    end
    n = C.GetNumMissingBuildResources2(station64, nil, 0, true)
    if n == 0 then return result end
    local buf = ffi.new("UIWareInfo[?]", n)
    n = C.GetMissingBuildResources(buf, n)
    for i = 0, n - 1 do
      local ware = ffi.string(buf[i].ware)
      if buildWares[ware] and buf[i].amount > 0 then
        result[ware] = buf[i].amount
      end
    end
    return result
  end)
  if not ok then
    scpStation.debug("Missing ship build resources not read: " .. tostring(missing))
    return {}
  end
  return missing
end

-- What the drone and missile supply pool still lacks; the station builds its units from stock.
local function getSupplyPoolNeeds(station64)
  local ok, needs = pcall(function()
    local result = {}
    local n = C.GetNumSupplyOrderResources(station64)
    if n == 0 then return result end
    local buf = ffi.new("SupplyResourceInfo[?]", n)
    n = C.GetSupplyOrderResources(buf, n, station64)
    for i = 0, n - 1 do
      local need = buf[i].total - buf[i].current
      if need > 0 then
        result[ffi.string(buf[i].ware)] = need
      end
    end
    return result
  end)
  if not ok then
    scpStation.debug("Supply pool not read: " .. tostring(needs))
    return {}
  end
  return needs
end

-- Target minus stock for every ware the station takes in; the target is the buy limit (restock)
-- or the storage target (fill) plus the supply pool's lack, raised to what queued ship builds miss.
-- Not its buy offers: those depend on the trade/supply budget and vanish when it is not computed.
function scpStation.getStationGap(station, toStorage)
  local station64 = ConvertStringTo64Bit(tostring(station))
  local allresources, tradewares, cargo = GetComponentData(station64, "allresources", "tradewares", "cargo")
  cargo = cargo or {}
  local poolNeeds = getSupplyPoolNeeds(station64)
  local wares = {}
  for _, ware in ipairs(allresources or {}) do
    wares[ware] = true
  end
  for ware in pairs(poolNeeds) do
    wares[ware] = true
  end
  for _, ware in ipairs(tradewares or {}) do
    if C.GetContainerWareIsBuyable(station64, ware) then
      wares[ware] = true
    end
  end
  local neededResources = {}
  local count = 0
  for ware in pairs(wares) do
    local limit = toStorage and (GetWareProductionLimit(station64, ware) or 0) or C.GetContainerBuyLimit(station64, ware)
    local pool = poolNeeds[ware] or 0
    local gap = limit + pool - (cargo[ware] or 0)
    scpStation.trace(string.format("Ware %s: %s %s, supply pool lacks %s, stored %s, gap %s", ware, toStorage and "storage" or "buy limit", limit, pool, cargo[ware] or 0, gap))
    if gap > 0 then
      neededResources[ware] = gap
      count = count + 1
    end
  end
  for ware, amount in pairs(getMissingShipBuildResources(station64)) do
    scpStation.trace(string.format("Ware %s: queued ship builds miss %s", ware, amount))
    if amount > (neededResources[ware] or 0) then
      if neededResources[ware] == nil then
        count = count + 1
      end
      neededResources[ware] = amount
    end
  end
  count = scpStation.applyReservations(station64, neededResources, count)
  count = scpStation.applyFreeCapacity(station64, neededResources, count)
  scpStation.debug(string.format("Number of resources on station with gaps: %d", count))
  return neededResources
end

-- Scales the gaps down per transport type when a manual storage level over-allocates the modules.
function scpStation.applyFreeCapacity(container64, neededResources, count)
  local free = {}
  local n = C.GetNumCargoTransportTypes(container64, true)
  local buf = ffi.new("StorageInfo[?]", n)
  n = C.GetCargoTransportTypes(buf, n, container64, true, false)
  for i = 0, n - 1 do
    free[ffi.string(buf[i].transport)] = math.max(0, buf[i].capacity - buf[i].spaceused)
  end
  local needed = {}
  for ware, amount in pairs(neededResources) do
    local transport, volume = GetWareData(ware, "transport", "volume")
    needed[transport] = (needed[transport] or 0) + amount * volume
  end
  for ware, amount in pairs(neededResources) do
    local transport = GetWareData(ware, "transport")
    local available = free[transport] or 0
    if needed[transport] > available then
      local scaled = math.floor(amount * available / needed[transport])
      scpStation.trace(string.format("Ware %s: gap %s scaled to %s, %s free of %s needed in %s", ware, amount, scaled, available, needed[transport], transport))
      if scaled > 0 then
        neededResources[ware] = scaled
      else
        neededResources[ware] = nil
        count = count - 1
      end
    end
  end
  return count
end


-- Reservations are stock already on its way in, so they count against the gap.
function scpStation.applyReservations(container, neededResources, count)
  local container64 = ConvertStringTo64Bit(tostring(container))
  local n = C.GetNumContainerWareReservations2(container64, true, true, true)
  local buf = ffi.new("WareReservationInfo2[?]", n)
  n = C.GetContainerWareReservations2(buf, n, container64, true, true, true)
  for i = 0, n - 1 do
    if (not buf[i].isvirtual) and (not buf[i].isbuyreservation) then
      local ware = ffi.string(buf[i].ware)
      if neededResources[ware] then
        neededResources[ware] = neededResources[ware] - buf[i].amount
        if neededResources[ware] <= 0 then
          neededResources[ware] = nil
          count = count - 1
        end
      end
    end
  end
  return count
end

function scpStation.sendWaresData(allWaresData)
  if allWaresData == nil or #allWaresData == 0 then return end
  scpStation.debug(string.format("Sending wares for %d container(s) to MD", #allWaresData))
  AddUITriggeredEvent("scp_main", "scp_add_wares", allWaresData)
end

function scpStation.fillWaresData(object, neededResources, finishAction, allWaresData)
  allWaresData = allWaresData or {}
  finishAction = finishAction == nil and true or finishAction
  if next(neededResources) ~= nil then
    local waresData = {
      object = ConvertStringToLuaID(tostring(object)),
      wares = {},
      amounts = {}
    }
    for ware, amount in pairs(neededResources) do
      table.insert(waresData.wares, ware)
      table.insert(waresData.amounts, amount)
    end
    allWaresData[#allWaresData + 1] = waresData
  end
  if finishAction then
    scpStation.sendWaresData(allWaresData)
    return {}
  end
  return allWaresData
end

function scpStation.isValidFillWaresGapStation(toStorage)
  local station = interactMenu.componentSlot.component
  if station == nil then return false end
  local object64 = ConvertStringTo64Bit(tostring(station))
  local owner, realclassid = GetComponentData(object64, "owner", "realclassid")
  if not Helper.isComponentClass(realclassid, "station") then return false end
  if owner == nil or (owner ~= "player" and not scpStation.scp.isExtendedMode()) then return false end
  local neededResources = scpStation.getStationGap(object64, toStorage)
  return next(neededResources) ~= nil
end

function scpStation.isValidFillStorageStation()
  return scpStation.isValidFillWaresGapStation(true)
end

function scpStation.isValidFillWaresGapStationForAllFaction()
  local station = interactMenu.componentSlot.component
  if station == nil then return false end
  local object64 = ConvertStringTo64Bit(tostring(station))
  local owner, realclassid = GetComponentData(object64, "owner", "realclassid")
  if not Helper.isComponentClass(realclassid, "station") then return false end
  if owner == nil or (owner ~= "player" and not scpStation.scp.isExtendedMode()) then return false end
  return scpStation.scp.isExtendedMode()
end


function scpStation.fillWaresGapStation(station, finishAction, allWaresData, toStorage)
  local station = station ~= nil and station or interactMenu.componentSlot.component
  scpStation.trace("fillWaresGapStation called with station: " .. tostring(station))
  finishAction = finishAction == nil and true or finishAction
  allWaresData = allWaresData or {}
  if station == nil then return end
  local object64 = ConvertStringTo64Bit(tostring(station))
  local owner, realclassid, name = GetComponentData(object64, "owner", "realclassid", "name")
  if not Helper.isComponentClass(realclassid, "station") then return end
  if owner == nil then return end
  scpStation.debug("fillWaresGapStation on station: name: " .. name .. ", owner: " .. owner .. ", toStorage: " .. tostring(toStorage == true))
  local neededResources = scpStation.getStationGap(object64, toStorage)
  allWaresData = scpStation.fillWaresData(object64, neededResources, finishAction, allWaresData)
  if finishAction then
    scpStation.helpers.interactMenuFinishAction()
  end
  return allWaresData
end

function scpStation.fillWaresGapStationForAllFaction()
  scpStation.processForAllStations(scpStation.fillWaresGapStation)
end

function scpStation.fillStorageStation(station, finishAction, allWaresData)
  return scpStation.fillWaresGapStation(station, finishAction, allWaresData, true)
end

function scpStation.fillStorageStationForAllFaction()
  scpStation.processForAllStations(scpStation.fillStorageStation)
end

function scpStation.isValidFillWaresGapBuildStorage()
  local station = interactMenu.componentSlot.component
  if station == nil then return false end
  local object64 = ConvertStringTo64Bit(tostring(station))
  local owner, realclassid, buildstorage = GetComponentData(object64, "owner", "realclassid", "buildstorage")
  if not Helper.isComponentClass(realclassid, "station") then return false end
  if owner == nil or (owner ~= "player" and not scpStation.scp.isExtendedMode()) then return false end
  if buildstorage == nil then return false end
  local neededResources = scpStation.getBuildStorageGap(object64, ConvertStringTo64Bit(tostring(buildstorage)))
  return next(neededResources) ~= nil
end

function scpStation.isValidFillWaresGapBuildStorageForAllFaction()
  local station = interactMenu.componentSlot.component
  if station == nil then return false end
  local object64 = ConvertStringTo64Bit(tostring(station))
  local owner, realclassid, buildstorage = GetComponentData(object64, "owner", "realclassid", "buildstorage")
  if not Helper.isComponentClass(realclassid, "station") then return false end
  if owner == nil or (owner ~= "player" and not scpStation.scp.isExtendedMode()) then return false end
  return scpStation.scp.isExtendedMode()
end

function scpStation.fillWaresGapBuildStorage(station, finishAction, allWaresData)
  local station = station ~= nil and station or interactMenu.componentSlot.component
  finishAction = finishAction == nil and true or finishAction
  allWaresData = allWaresData or {}
  scpStation.trace("fillWaresGapBuildStorage called with station: " .. tostring(station))
  if station == nil then return end
  local object64 = ConvertStringTo64Bit(tostring(station))
  local owner, realclassid, buildstorage, name = GetComponentData(object64, "owner", "realclassid", "buildstorage", "name")
  if not Helper.isComponentClass(realclassid, "station") then return end
  if owner == nil then return end
  if buildstorage == nil then return end
  scpStation.debug("fillWaresGapBuildStorage for station: name: " .. name .. ", buildstorage: " .. tostring(buildstorage) .. ", owner: " .. owner)
  local neededResources = scpStation.getBuildStorageGap(object64, ConvertStringTo64Bit(tostring(buildstorage)))
  allWaresData = scpStation.fillWaresData(buildstorage, neededResources, finishAction, allWaresData)
  if finishAction then
    scpStation.helpers.interactMenuFinishAction()
  end
  return allWaresData
end

function scpStation.fillWaresGapBuildStorageForAllFaction()
  scpStation.processForAllStations(scpStation.fillWaresGapBuildStorage)
end

function scpStation.join(scp)
  scpStation.scp = scp
  scpStation.helpers = scp.helpers
  scpStation.info = scp.helpers.info
  scpStation.debug = scp.helpers.debug
  scpStation.trace = scp.helpers.trace
end

Register_Require_Response("extensions.safe_cheat_panel.ui.scp_station", scpStation)
return scpStation
