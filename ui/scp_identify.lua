-- What an existing object was built from, for the editor's dropdowns. Named loadouts and plans
-- compare exactly; generated presets cannot, so only "every slot full" is decidable.

local ffi = require("ffi")
local C = ffi.C

ffi.cdef [[
	typedef uint64_t UniverseID;

	typedef struct {
		const char* macro;
		bool optional;
	} UILoadoutVirtualMacroData;

	typedef struct {
		const char* macro;
		const char* upgradetypename;
		size_t slot;
		bool optional;
	} UILoadoutMacroData;

	typedef struct {
		const char* macro;
		const char* path;
		const char* group;
		uint32_t count;
		bool optional;
	} UILoadoutGroupData;

	typedef struct {
		const char* macro;
		uint32_t amount;
		bool optional;
	} UILoadoutAmmoData;

	typedef struct {
		const char* ware;
	} UILoadoutSoftwareData;

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
	} UILoadoutCounts;

	typedef struct {
		UILoadoutMacroData* weapons;
		uint32_t numweapons;
		UILoadoutMacroData* turrets;
		uint32_t numturrets;
		UILoadoutMacroData* shields;
		uint32_t numshields;
		UILoadoutMacroData* engines;
		uint32_t numengines;
		UILoadoutGroupData* turretgroups;
		uint32_t numturretgroups;
		UILoadoutGroupData* shieldgroups;
		uint32_t numshieldgroups;
		UILoadoutAmmoData* ammo;
		uint32_t numammo;
		UILoadoutAmmoData* units;
		uint32_t numunits;
		UILoadoutSoftwareData* software;
		uint32_t numsoftware;
		UILoadoutVirtualMacroData thruster;
	} UILoadout;

	typedef struct {
		const char* path;
		const char* group;
	} UpgradeGroup;

	typedef struct {
		UniverseID currentcomponent;
		const char* currentmacro;
		const char* slotsize;
		uint32_t count;
		uint32_t operational;
		uint32_t total;
	} UpgradeGroupInfo;

	typedef struct {
		float x;
		float y;
		float z;
		float yaw;
		float pitch;
		float roll;
	} UIPosRot;

	typedef struct {
		size_t idx;
		const char* macroid;
		UniverseID componentid;
		UIPosRot offset;
		const char* connectionid;
		size_t predecessoridx;
		const char* predecessorconnectionid;
		bool isfixed;
	} UIConstructionPlanEntry;

	void GetLoadout(UILoadout* result, UniverseID defensibleid, const char* macroname, const char* loadoutid);
	uint32_t GetLoadoutCounts(UILoadoutCounts* result, UniverseID defensibleid, const char* macroname, const char* loadoutid);
	size_t GetNumUpgradeSlots(UniverseID destructibleid, const char* macroname, const char* upgradetypename);
	uint32_t GetNumUpgradeGroups(UniverseID destructibleid, const char* macroname);
	uint32_t GetUpgradeGroups(UpgradeGroup* result, uint32_t resultlen, UniverseID destructibleid, const char* macroname);
	UpgradeGroupInfo GetUpgradeGroupInfo(UniverseID destructibleid, const char* macroname, const char* path, const char* group, const char* upgradetypename);
	UpgradeGroup GetUpgradeSlotGroup(UniverseID destructibleid, const char* macroname, const char* upgradetypename, size_t slot);
	const char* GetUpgradeSlotCurrentMacro(UniverseID objectid, UniverseID moduleid, const char* upgradetypename, size_t slot);
	size_t GetNumVirtualUpgradeSlots(UniverseID objectid, const char* macroname, const char* upgradetypename);
	const char* GetVirtualUpgradeSlotCurrentMacro(UniverseID defensibleid, const char* upgradetypename, size_t slot);
	size_t GetNumConstructionPlanInfo(const char* constructionplanid);
	size_t GetConstructionPlanInfo(UIConstructionPlanEntry* result, size_t resultlen, const char* constructionplanid);
	size_t GetNumPlannedStationModules(UniverseID defensibleid, bool includeall);
	size_t GetPlannedStationModules(UIConstructionPlanEntry* result, uint32_t resultlen, UniverseID defensibleid, bool includeall);
	uint32_t GetNumStationModules(UniverseID stationid, bool includeconstructions, bool includewrecks);
	uint32_t GetStationModules(UniverseID* result, uint32_t resultlen, UniverseID stationid, bool includeconstructions, bool includewrecks);
]]

local scpIdentify = {}

-- What the fingerprint covers. Consumables, software, crew and paint/equipment mods stay out: they
-- drift with use, and none of them is part of a v1 UILoadout in the first place.
local macroCategories = {
  -- enginegroup is a pseudogroup, so a grouped engine slot still reports its own macro.
  { category = "engines", type = "engine", pseudogroup = true },
  { category = "shields", type = "shield" },
  { category = "weapons", type = "weapon" },
  { category = "turrets", type = "turret" },
}
local groupCategories = {
  { category = "turretgroups", type = "turret" },
  { category = "shieldgroups", type = "shield" },
}

-- Plan module lists never change for a given id; cleared with the rest of the spawner state.
local planSignatures = {}
local planEquips = {}
local planHabitats = {}

function scpIdentify.join(scp)
  scpIdentify.scp = scp
end

function scpIdentify.reset()
  planSignatures = {}
  planEquips = {}
  planHabitats = {}
end

local function addCount(counts, upgradeType, macro, amount)
  if macro == nil or macro == "" or amount == nil or amount <= 0 then return end
  counts[upgradeType] = counts[upgradeType] or {}
  counts[upgradeType][macro] = (counts[upgradeType][macro] or 0) + amount
end

---Flattens a per-type macro multiset into one comparable string.
local function countsSignature(counts)
  local types = {}
  for upgradeType, macros in pairs(counts) do
    local parts = {}
    for macro, amount in pairs(macros) do
      parts[#parts + 1] = macro .. "*" .. amount
    end
    table.sort(parts)
    types[#types + 1] = upgradeType .. "=" .. table.concat(parts, ",")
  end
  table.sort(types)
  return table.concat(types, ";")
end

---Macro multiset of a named loadout. Grouped and individually addressed slots land in the same
---bucket - which of the two the engine reports a slot on differs between a stored loadout and a
---built ship, so slot identity cannot be part of the comparison.
local function loadoutCounts(loadout)
  local counts = {}
  for _, entry in ipairs(macroCategories) do
    for i = 0, loadout["num" .. entry.category] - 1 do
      addCount(counts, entry.type, ffi.string(loadout[entry.category][i].macro), 1)
    end
  end
  for _, entry in ipairs(groupCategories) do
    for i = 0, loadout["num" .. entry.category] - 1 do
      local item = loadout[entry.category][i]
      addCount(counts, entry.type, ffi.string(item.macro), tonumber(item.count))
    end
  end
  addCount(counts, "thruster", ffi.string(loadout.thruster.macro), 1)
  return counts
end

---The same multiset read off a live object, the way vanilla's configuration menu reads it: per
---slot for ungrouped slots, per group otherwise. GetCurrentLoadout is a station-module call and
---has no ship form.
local function objectCounts(object)
  local counts = {}
  for _, entry in ipairs(macroCategories) do
    for slot = 1, tonumber(C.GetNumUpgradeSlots(object, "", entry.type)) do
      local grouped = false
      if not entry.pseudogroup then
        local slotGroup = C.GetUpgradeSlotGroup(object, "", entry.type, slot)
        grouped = (ffi.string(slotGroup.path) ~= "..") or (ffi.string(slotGroup.group) ~= "")
      end
      if not grouped then
        addCount(counts, entry.type, ffi.string(C.GetUpgradeSlotCurrentMacro(object, 0, entry.type, slot)), 1)
      end
    end
  end
  local n = tonumber(C.GetNumUpgradeGroups(object, ""))
  local buf = ffi.new("UpgradeGroup[?]", n)
  n = tonumber(C.GetUpgradeGroups(buf, n, object, ""))
  for i = 0, n - 1 do
    local path, group = ffi.string(buf[i].path), ffi.string(buf[i].group)
    if (path ~= "..") or (group ~= "") then
      for _, entry in ipairs(groupCategories) do
        local info = C.GetUpgradeGroupInfo(object, "", path, group, entry.type)
        addCount(counts, entry.type, ffi.string(info.currentmacro), tonumber(info.count))
      end
    end
  end
  for slot = 1, tonumber(C.GetNumVirtualUpgradeSlots(object, "", "thruster")) do
    addCount(counts, "thruster", ffi.string(C.GetVirtualUpgradeSlotCurrentMacro(object, "thruster", slot)), 1)
  end
  return counts
end

---Filled/total per slot category, filled being whatever objectCounts already summed.
local function isFullyEquipped(object, counts)
  local anySlot = false
  for _, entry in ipairs(macroCategories) do
    local slots = tonumber(C.GetNumUpgradeSlots(object, "", entry.type))
    if slots > 0 then
      anySlot = true
      local filled = 0
      for _, amount in pairs(counts[entry.type] or {}) do
        filled = filled + amount
      end
      scpIdentify.scp.trace("Identify: " .. entry.type .. " " .. filled .. "/" .. slots)
      if filled < slots then
        return false
      end
    end
  end
  return anySlot
end

---Which entry of the loadout dropdown an existing ship currently matches.
---@return string|nil id of a named loadout, "scpDefaultHigh" when every slot is full, else nil
function scpIdentify.shipLoadout(object, macro, loadoutOptions)
  if object == nil or macro == nil then return nil end
  local counts = objectCounts(object)
  local currentSignature = countsSignature(counts)
  scpIdentify.scp.trace("Identify: ship equipment " .. currentSignature)

  for _, option in ipairs(loadoutOptions) do
    -- The three generated presets and the separator carry no engine-side loadout to compare to.
    if option.preset == nil and option.id ~= "none" then
      local named = Helper.getLoadoutHelper(C.GetLoadout, C.GetLoadoutCounts, object, macro, option.id)
      local namedSignature = countsSignature(loadoutCounts(named))
      if namedSignature == currentSignature then
        scpIdentify.scp.debug("Identify: ship loadout matches named loadout " .. option.id)
        return option.id
      end
      scpIdentify.scp.trace("Identify: loadout " .. option.id .. " " .. namedSignature)
    end
  end

  if isFullyEquipped(object, counts) then
    scpIdentify.scp.debug("Identify: ship has every slot filled, reporting the High preset")
    return "scpDefaultHigh"
  end
  scpIdentify.scp.debug("Identify: ship loadout matches nothing, reporting Custom")
  return nil
end

local function planMacros(planId)
  local n = tonumber(C.GetNumConstructionPlanInfo(planId))
  local buf = ffi.new("UIConstructionPlanEntry[?]", n)
  n = tonumber(C.GetConstructionPlanInfo(buf, n, planId))
  local macros = {}
  for i = 0, n - 1 do
    macros[#macros + 1] = ffi.string(buf[i].macroid)
  end
  return macros
end

---Sorted module-macro multiset of a stored construction plan.
local function planSignature(planId)
  if planSignatures[planId] then
    return planSignatures[planId]
  end
  local macros = planMacros(planId)
  table.sort(macros)
  planSignatures[planId] = table.concat(macros, ";")
  return planSignatures[planId]
end

---Will the plan's station have a place for a ship trader? A build module is the whole test - it
---makes the wharf, shipyard or equipment dock.
function scpIdentify.planCanEquipShips(planId)
  if planId == nil then return false end
  if planEquips[planId] ~= nil then
    return planEquips[planId]
  end
  local canEquip = false
  for _, macro in ipairs(planMacros(planId)) do
    if IsMacroClass(macro, "buildmodule") then
      canEquip = true
      break
    end
  end
  planEquips[planId] = canEquip
  scpIdentify.scp.debug("Identify: plan " .. planId .. (canEquip and " can" or " cannot") .. " equip ships")
  return canEquip
end

---Will the plan's station have anywhere to put a workforce? Only habitation modules carry capacity.
function scpIdentify.planHasHabitation(planId)
  if planId == nil then return false end
  if planHabitats[planId] ~= nil then
    return planHabitats[planId]
  end
  local hasHabitation = false
  for _, macro in ipairs(planMacros(planId)) do
    if IsMacroClass(macro, "habitation") then
      hasHabitation = true
      break
    end
  end
  planHabitats[planId] = hasHabitation
  scpIdentify.scp.debug("Identify: plan " .. planId .. (hasHabitation and " has" or " has no") .. " habitation modules")
  return hasHabitation
end

---The station's own build sequence. `includeall` false is the pending remainder only, so a
---finished station reports nothing; true is the whole plan, the shape the stored plans have.
local function stationMacros(object)
  local n = tonumber(C.GetNumPlannedStationModules(object, true))
  if n > 0 then
    local buf = ffi.new("UIConstructionPlanEntry[?]", n)
    n = tonumber(C.GetPlannedStationModules(buf, n, object, true))
    local macros = {}
    for i = 0, n - 1 do
      macros[#macros + 1] = ffi.string(buf[i].macroid)
    end
    return macros, "plan"
  end
  -- No plan carried on the station at all - fall back to what is actually standing there.
  n = tonumber(C.GetNumStationModules(object, false, false))
  local buf = ffi.new("UniverseID[?]", n)
  n = tonumber(C.GetStationModules(buf, n, object, false, false))
  local macros = {}
  for i = 0, n - 1 do
    local moduleMacro = GetComponentData(ConvertStringTo64Bit(tostring(buf[i])), "macro")
    if moduleMacro then
      macros[#macros + 1] = moduleMacro
    end
  end
  return macros, "built"
end

---Closest plan by macro overlap, as a fraction of the longer list. Diagnostic only - it says how
---far off a near miss is instead of just "nothing".
local function bestPlanMatch(macros, plans)
  local wanted = {}
  for _, macro in ipairs(macros) do
    wanted[macro] = (wanted[macro] or 0) + 1
  end
  local bestId, bestScore = nil, 0.0
  for _, plan in ipairs(plans) do
    local left, shared, total = {}, 0, 0
    for macro, amount in pairs(wanted) do left[macro] = amount end
    for _, macro in ipairs(planMacros(plan.id)) do
      total = total + 1
      if (left[macro] or 0) > 0 then
        left[macro] = left[macro] - 1
        shared = shared + 1
      end
    end
    local score = shared / math.max(#macros, total, 1)
    if score > bestScore then
      bestId, bestScore = plan.id, score
    end
  end
  return bestId, bestScore
end

---Which construction plan an existing station was built from. The planned-module list uses the
---same struct as the stored plans, so placement and rotation are ignored.
---@return string|nil planId, string|nil planType
function scpIdentify.stationPlan(object, inGamePlans, playerPlans)
  if object == nil then return nil, nil end
  local macros, source = stationMacros(object)
  if #macros == 0 then
    scpIdentify.scp.debug("Identify: station reports no modules at all")
    return nil, nil
  end
  table.sort(macros)
  local signature = table.concat(macros, ";")
  scpIdentify.scp.trace("Identify: station modules (" .. source .. ", " .. #macros .. ") " .. signature)

  for _, entry in ipairs({ { "inGame", inGamePlans }, { "player", playerPlans } }) do
    for _, plan in ipairs(entry[2]) do
      if planSignature(plan.id) == signature then
        scpIdentify.scp.debug("Identify: station modules match plan " .. plan.id .. " (" .. entry[1] .. ")")
        return plan.id, entry[1]
      end
    end
  end

  local bestId, bestScore = bestPlanMatch(macros, inGamePlans)
  local playerId, playerScore = bestPlanMatch(macros, playerPlans)
  if playerScore > bestScore then
    bestId, bestScore = playerId, playerScore
  end
  scpIdentify.scp.debug("Identify: station modules match no known plan, closest is "
    .. (bestId or "none") .. " at " .. math.floor(bestScore * 100) .. "%")
  return nil, nil
end

Register_Require_Response("extensions.safe_cheat_panel.ui.scp_identify", scpIdentify)
return scpIdentify
