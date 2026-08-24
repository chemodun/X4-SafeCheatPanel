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

	void GetCurrentLoadout(UILoadout* result, UniverseID defensibleid, UniverseID moduleid);
	void GetCurrentLoadoutCounts(UILoadoutCounts* result, UniverseID defensibleid, UniverseID moduleid);
	void GetLoadout(UILoadout* result, UniverseID defensibleid, const char* macroname, const char* loadoutid);
	uint32_t GetLoadoutCounts(UILoadoutCounts* result, UniverseID defensibleid, const char* macroname, const char* loadoutid);
	size_t GetNumUpgradeSlots(UniverseID destructibleid, const char* macroname, const char* upgradetypename);
	size_t GetNumConstructionPlanInfo(const char* constructionplanid);
	size_t GetConstructionPlanInfo(UIConstructionPlanEntry* result, size_t resultlen, const char* constructionplanid);
	size_t GetNumPlannedStationModules(UniverseID defensibleid, bool includeall);
	size_t GetPlannedStationModules(UIConstructionPlanEntry* result, uint32_t resultlen, UniverseID defensibleid, bool includeall);
]]

local scpIdentify = {}

-- Slot categories the signature covers. Ammo, units and software drift with use, so they are left out.
local macroCategories = {
  { category = "weapons", type = "weapon" },
  { category = "turrets", type = "turret" },
  { category = "shields", type = "shield" },
  { category = "engines", type = "engine" },
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

---Order-independent equipment fingerprint of a UILoadout struct.
local function loadoutSignature(loadout)
  local parts = {}
  for _, entry in ipairs(macroCategories) do
    for i = 0, loadout["num" .. entry.category] - 1 do
      local item = loadout[entry.category][i]
      parts[#parts + 1] = string.format("%s:%d=%s", entry.type, tonumber(item.slot), ffi.string(item.macro))
    end
  end
  for _, entry in ipairs(groupCategories) do
    for i = 0, loadout["num" .. entry.category] - 1 do
      local item = loadout[entry.category][i]
      parts[#parts + 1] = string.format("%sg:%s|%s=%s*%d", entry.type, ffi.string(item.path), ffi.string(item.group), ffi.string(item.macro), tonumber(item.count))
    end
  end
  parts[#parts + 1] = "thruster=" .. ffi.string(loadout.thruster.macro)
  table.sort(parts)
  return table.concat(parts, ";")
end

---Filled/total slot counts per category. Grouped slots contribute their `count`, individual
---ones one each - the same arithmetic the MD passes report.
local function isFullyEquipped(object, loadout)
  local anySlot = false
  for _, entry in ipairs(macroCategories) do
    local slots = tonumber(C.GetNumUpgradeSlots(object, "", entry.type))
    if slots > 0 then
      anySlot = true
      local filled = tonumber(loadout["num" .. entry.category])
      for _, group in ipairs(groupCategories) do
        if group.type == entry.type then
          for i = 0, loadout["num" .. group.category] - 1 do
            filled = filled + tonumber(loadout[group.category][i].count)
          end
        end
      end
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
  local current = Helper.getLoadoutHelper(C.GetCurrentLoadout, C.GetCurrentLoadoutCounts, object, 0)
  local currentSignature = loadoutSignature(current)

  for _, option in ipairs(loadoutOptions) do
    -- The three generated presets and the separator carry no engine-side loadout to compare to.
    if option.preset == nil and option.id ~= "none" then
      local named = Helper.getLoadoutHelper(C.GetLoadout, C.GetLoadoutCounts, 0, macro, option.id)
      if loadoutSignature(named) == currentSignature then
        scpIdentify.scp.debug("Identify: ship loadout matches named loadout " .. option.id)
        return option.id
      end
    end
  end

  if isFullyEquipped(object, current) then
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

---Which construction plan an existing station was built from. GetPlannedStationModules returns
---the same struct the stored plans use, so placement and rotation are ignored.
---@return string|nil planId, string|nil planType
function scpIdentify.stationPlan(object, inGamePlans, playerPlans)
  if object == nil then return nil, nil end
  local n = tonumber(C.GetNumPlannedStationModules(object, false))
  if n == 0 then return nil, nil end
  local buf = ffi.new("UIConstructionPlanEntry[?]", n)
  n = tonumber(C.GetPlannedStationModules(buf, n, object, false))
  local macros = {}
  for i = 0, n - 1 do
    macros[#macros + 1] = ffi.string(buf[i].macroid)
  end
  table.sort(macros)
  local signature = table.concat(macros, ";")

  for _, entry in ipairs({ { "inGame", inGamePlans }, { "player", playerPlans } }) do
    for _, plan in ipairs(entry[2]) do
      if planSignature(plan.id) == signature then
        scpIdentify.scp.debug("Identify: station modules match plan " .. plan.id .. " (" .. entry[1] .. ")")
        return plan.id, entry[1]
      end
    end
  end
  scpIdentify.scp.debug("Identify: station modules match no known plan")
  return nil, nil
end

Register_Require_Response("extensions.safe_cheat_panel.ui.scp_identify", scpIdentify)
return scpIdentify
