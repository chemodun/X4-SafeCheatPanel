local ffi = require("ffi")
local C = ffi.C

ffi.cdef [[

	typedef uint64_t UniverseID;

	typedef struct {
		const char* ware;
		const char* macro;
		int amount;
	} UIWareInfo;

  uint32_t PrepareBuildSequenceResources2(UniverseID holomapid, UniverseID stationid, bool useplanned);
  uint32_t GetBuildSequenceResources(UIWareInfo* result, uint32_t resultlen);
	uint32_t GetNumCargo(UniverseID containerid, const char* tags);
	uint32_t GetCargo(UIWareInfo* result, uint32_t resultlen, UniverseID containerid, const char* tags);
	uint32_t GetNumWares(const char* tags, bool research, const char* licenceownerid, const char* exclusiontags);
	uint32_t GetWares(const char** result, uint32_t resultlen, const char* tags, bool research, const char* licenceownerid, const char* exclusiontags);
]]

local menu         = Helper.getMenu("MapMenu")
local interactMenu = Helper.getMenu("InteractMenu")

local PAGE_ID = 1972092427

local scpStation = {
}


function scpStation.isValidForceBuildCompletion()
  local station = interactMenu.componentSlot.component
  if station == nil then return false end
  local object64 = ConvertStringTo64Bit(tostring(station))
  local owner, realclassid = GetComponentData(object64, "owner", "realclassid")
  if not Helper.isComponentClass(realclassid, "station") then return false end
  if owner == nil or owner ~= "player" then return false end
  if IsComponentConstruction(object64) then return true end
  if C.GetNumPlannedStationModules(object64, false) > 0 then return true end
  return false
end

function scpStation.forceBuildCompletion()
  local station = interactMenu.componentSlot.component
  if station == nil then return false end
  C.ForceBuildCompletion(station)
  scpStation.helpers.interactMenuFinishAction()
end

function scpStation.GetBuildStorageGap(station, buildStorage)
  local neededResources = {}
  local numTotalResources = C.PrepareBuildSequenceResources2(menu.holomap, station, true)
  if numTotalResources > 0 then
    local buf = ffi.new("UIWareInfo[?]", numTotalResources)
    numTotalResources = C.GetBuildSequenceResources(buf, numTotalResources)
    for i = 0, numTotalResources - 1 do
      neededResources[ffi.string(buf[i].ware)] = buf[i].amount 
    end
  end
  local n = C.GetNumCargo(buildStorage, "stationbuilding")
  local buf = ffi.new("UIWareInfo[?]", n)
  n = C.GetCargo(buf, n, buildStorage, "stationbuilding")
  for i = 0, n - 1 do
    local ware = ffi.string(buf[i].ware)
    if neededResources[ware] ~= nil then
      local amountGap = neededResources[ware] - buf[i].amount
      if amountGap > 0 then
        neededResources[ware] = amountGap
      else
        neededResources[ware] = nil
      end
    end
  end
  return neededResources
end

function scpStation.isValidFillWaresGapStation()
  local station = interactMenu.componentSlot.component
  if station == nil then return false end
  local object64 = ConvertStringTo64Bit(tostring(station))
  local owner, realclassid = GetComponentData(object64, "owner", "realclassid")
  if not Helper.isComponentClass(realclassid, "station") then return false end
  if owner == nil or owner ~= "player" then return false end

  return false
end

function scpStation.isValidFillWaresGapBuildStorage()
  local station = interactMenu.componentSlot.component
  if station == nil then return false end
  local object64 = ConvertStringTo64Bit(tostring(station))
  local owner, realclassid, buildstorage = GetComponentData(object64, "owner", "realclassid", "buildstorage")
  if not Helper.isComponentClass(realclassid, "station") then return false end
  if owner == nil or owner ~= "player" then return false end
  if buildstorage == nil then return false end
  local neededResources = scpStation.GetBuildStorageGap(object64, ConvertStringTo64Bit(tostring(buildstorage)))
  return next(neededResources) ~= nil
end

function scpStation.fillWaresGapStation()
  local station = interactMenu.componentSlot.component
  if station == nil then return end
  local object64 = ConvertStringTo64Bit(tostring(station))
  local owner, realclassid, buildstorage = GetComponentData(object64, "owner", "realclassid", "buildstorage")
  if not Helper.isComponentClass(realclassid, "station") then return end
  if owner == nil or owner ~= "player" then return end
  if buildstorage == nil then return end
end

function scpStation.fillWaresGapBuildStorage()
  local station = interactMenu.componentSlot.component
  if station == nil then return end
  local object64 = ConvertStringTo64Bit(tostring(station))
  local owner, realclassid, buildstorage = GetComponentData(object64, "owner", "realclassid", "buildstorage")
  if not Helper.isComponentClass(realclassid, "station") then return end
  if owner == nil or owner ~= "player" then return end
  if buildstorage == nil then return end
  local neededResources = scpStation.GetBuildStorageGap(object64, ConvertStringTo64Bit(tostring(buildstorage)))
  local addWaresData = {
    object = buildstorage,
    wares = {},
    amounts = {}
  }
  for ware, amount in pairs(neededResources) do
    table.insert(addWaresData.wares, ware)
    table.insert(addWaresData.amounts, amount)
  end
  AddUITriggeredEvent("scp_main", "scp_add_wares", addWaresData)
  scpStation.helpers.interactMenuFinishAction()
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
