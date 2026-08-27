-- Equipment candidate pools for MD, derived from the ship macro's own slots and maker race.
-- generate_loadout draws from a faction's default items, keyed off ware blueprint ownership,
-- so gear owned by anyone else (e.g. "ownerless") is never picked and its slots stay empty.

local ffi = require("ffi")
local C = ffi.C

ffi.cdef [[
	typedef uint64_t UniverseID;

	typedef struct {
		const char* tag;
		const char* name;
	} EquipmentCompatibilityInfo;

	typedef struct {
		const char* type;
		const char* ware;
		const char* macro;
		int amount;
	} EquipmentWareInfo;

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

	UpgradeGroup GetUpgradeSlotGroup(UniverseID destructibleid, const char* macroname, const char* upgradetypename, size_t slot);
	uint32_t GetNumUpgradeGroups(UniverseID destructibleid, const char* macroname);
	uint32_t GetUpgradeGroups(UpgradeGroup* result, uint32_t resultlen, UniverseID destructibleid, const char* macroname);
	UpgradeGroupInfo GetUpgradeGroupInfo(UniverseID destructibleid, const char* macroname, const char* path, const char* group, const char* upgradetypename);
	bool IsUpgradeGroupMacroCompatible(UniverseID destructibleid, const char* macroname, const char* path, const char* group, const char* upgradetypename, const char* upgrademacroname);
	bool IsAmmoMacroCompatible(const char* weaponmacroname, const char* ammomacroname);

	uint32_t GetNumAllEquipment(bool playerblueprint);
	uint32_t GetAllEquipment(EquipmentWareInfo* result, uint32_t resultlen, bool playerblueprint);
	uint32_t GetNumAllEquipment2(bool playerblueprint, bool customgamestart);
	uint32_t GetAllEquipment2(EquipmentWareInfo* result, uint32_t resultlen, bool playerblueprint, bool customgamestart);
	size_t GetNumUpgradeSlots(UniverseID destructibleid, const char* macroname, const char* upgradetypename);
	uint32_t GetNumSlotCompatibilities(UniverseID defensibleid, UniverseID moduleid, const char* macroname, bool ismodule, const char* upgradetypename, size_t slot);
	uint32_t GetSlotCompatibilities(EquipmentCompatibilityInfo* result, uint32_t resultlen, UniverseID defensibleid, UniverseID moduleid, const char* macroname, bool ismodule, const char* upgradetypename, size_t slot);
	const char* GetSlotSize(UniverseID defensibleid, UniverseID moduleid, const char* macroname, bool ismodule, const char* upgradetypename, size_t slot);
	bool IsSlotMandatory(UniverseID defensibleid, UniverseID moduleid, const char* macroname, bool ismodule, const char* upgradetypename, size_t slot);
	bool IsUpgradeMacroCompatible(UniverseID objectid, UniverseID moduleid, const char* macroname, bool ismodule, const char* upgradetypename, size_t slot, const char* upgrademacroname);
	size_t GetNumVirtualUpgradeSlots(UniverseID objectid, const char* macroname, const char* upgradetypename);
	bool IsVirtualUpgradeMacroCompatible(UniverseID defensibleid, const char* macroname, const char* upgradetypename, size_t slot, const char* upgrademacroname);
]]

local scpEquipment = {}

local scpHelpers = require("extensions.safe_cheat_panel.ui.scp_helpers")

local isV9 = false

-- Slot-bearing upgrade types with the MD loadout flag each is applied under. No thruster ware
-- carries an <owner> faction, so the faction pass never fits one and the plan must.
local slotTypes = {
  { type = "engine", flag = "engines", groups = true },
  { type = "shield", flag = "shields", groups = true },
  { type = "weapon", flag = "weapons", groups = false },
  { type = "turret", flag = "turrets", groups = true },
  { type = "thruster", flag = "thrusters", groups = false, virtual = true },
}

function scpEquipment.init(isVersion9)
  isV9 = isVersion9 and true or false
end

--- All equipment as { macro, ware } pairs, bucketed by upgrade type ("weapon", "engine", ...).
local function getEquipmentPool()
  local pool = {}
  local n, buf
  if isV9 then
    n = C.GetNumAllEquipment2(false, false)
    buf = ffi.new("EquipmentWareInfo[?]", n)
    n = C.GetAllEquipment2(buf, n, false, false)
  else
    n = C.GetNumAllEquipment(false)
    buf = ffi.new("EquipmentWareInfo[?]", n)
    n = C.GetAllEquipment(buf, n, false)
  end
  for i = 0, n - 1 do
    local equipmentType = ffi.string(buf[i].type)
    pool[equipmentType] = pool[equipmentType] or {}
    table.insert(pool[equipmentType], { macro = ffi.string(buf[i].macro), ware = ffi.string(buf[i].ware) })
  end
  return pool
end

local function getMakerRaces(macro)
  local set, list = {}, {}
  local races = GetMacroData(macro, "makerraceid")
  if races then
    for _, race in ipairs(races) do
      set[race] = true
      table.insert(list, race)
    end
  end
  return set, list
end

--- Fittable = maker-race match, gear naming no race at all, or a blueprint held by the
--- spawning faction or a faction of the ship's race. Never another race's equipment.
local function makeRaceFilter(raceSet, factionSet)
  local verdicts, factionRaces = {}, {}
  return function(macro, ware)
    local verdict = verdicts[macro]
    if verdict ~= nil then return verdict end
    verdict = false
    local races = GetMacroData(macro, "makerraceid")
    if races == nil or #races == 0 then
      verdict = true
    else
      for _, race in ipairs(races) do
        if raceSet[race] then verdict = true end
      end
    end
    if not verdict and ware ~= nil and ware ~= "" then
      for _, owner in ipairs(GetWareData(ware, "blueprintsowners") or {}) do
        if factionRaces[owner] == nil then
          factionRaces[owner] = GetFactionData(owner, "primaryrace") or false
        end
        if factionSet[owner] or (factionRaces[owner] and raceSet[factionRaces[owner]]) then
          verdict = true
        end
      end
    end
    verdicts[macro] = verdict
    return verdict
  end
end

local function getSlotTags(macro, upgradeType, slot)
  local n = C.GetNumSlotCompatibilities(0, 0, macro, false, upgradeType, slot)
  if n == 0 then return {} end
  local buf = ffi.new("EquipmentCompatibilityInfo[?]", n)
  n = C.GetSlotCompatibilities(buf, n, 0, 0, macro, false, upgradeType, slot)
  ---@type string[]
  local tags = {}
  for i = 0, n - 1 do
    table.insert(tags, ffi.string(buf[i].tag))
  end
  table.sort(tags)
  return tags
end

--- A bucket's candidates: everything that fits, and of those what the race filter allows.
--- Both counts are returned, so a pool starved by the race rule is visible in the log.
local function collect(candidates, fits, allowed)
  ---@type string[], integer
  local picks, compatible = {}, 0
  for _, entry in ipairs(candidates or {}) do
    if fits(entry.macro) then
      compatible = compatible + 1
      if allowed(entry.macro, entry.ware) then
        table.insert(picks, entry.macro)
      end
    end
  end
  table.sort(picks)
  return picks, compatible
end

--- Slots of one upgrade type, bucketed by (size, tag signature) - one bucket accepts one set
--- of equipment. Returned split into loose slots and the ones hanging off a group.
local function getSlotBuckets(macro, upgradeType, candidates, allowed)
  local numSlots = tonumber(C.GetNumUpgradeSlots(0, macro, upgradeType))
  ---@type table<string, table>, table[], table[]
  local byKey, loose, grouped = {}, {}, {}
  for slot = 1, numSlots do
    local inGroup = ffi.string(C.GetUpgradeSlotGroup(0, macro, upgradeType, slot).group) ~= ""
    local size = ffi.string(C.GetSlotSize(0, 0, macro, false, upgradeType, slot))
    local tags = getSlotTags(macro, upgradeType, slot)
    local key = tostring(inGroup) .. "|" .. size .. "|" .. table.concat(tags, ",")
    if byKey[key] == nil then
      local picks, compatible = collect(candidates, function(candidate)
        return C.IsUpgradeMacroCompatible(0, 0, macro, false, upgradeType, slot, candidate)
      end, allowed)
      byKey[key] = {
        label = string.format("%ssize=%s tags=%s", inGroup and "grouped " or "",
          size ~= "" and size or "-", #tags > 0 and table.concat(tags, ",") or "-"),
        slots = 0,
        mandatory = 0,
        picks = picks,
        compatible = compatible,
      }
      table.insert(inGroup and grouped or loose, byKey[key])
    end
    local bucket = byKey[key]
    bucket.slots = bucket.slots + 1
    if C.IsSlotMandatory(0, 0, macro, false, upgradeType, slot) then
      bucket.mandatory = bucket.mandatory + 1
    end
  end
  return loose, grouped
end

--- Virtual slots (thrusters) carry no size, tags or group, so one bucket per compatible macro
--- set is all there is to bucket by.
local function getVirtualSlotBuckets(macro, upgradeType, candidates, allowed)
  local numSlots = tonumber(C.GetNumVirtualUpgradeSlots(0, macro, upgradeType))
  ---@type table<string, table>, table[]
  local byKey, buckets = {}, {}
  for slot = 1, numSlots do
    local picks, compatible = collect(candidates, function(candidate)
      return C.IsVirtualUpgradeMacroCompatible(0, macro, upgradeType, slot, candidate)
    end, allowed)
    local key = table.concat(picks, ",")
    if byKey[key] == nil then
      byKey[key] = { label = "virtual", slots = 0, mandatory = 0, picks = picks, compatible = compatible }
      table.insert(buckets, byKey[key])
    end
    byKey[key].slots = byKey[key].slots + 1
  end
  return buckets
end

--- Slot groups of one upgrade type, bucketed by their compatible macro set: a group is
--- addressed as a whole and its compatibility can be narrower than the per-slot test.
local function getGroupBuckets(macro, upgradeType, candidates, allowed)
  local n = tonumber(C.GetNumUpgradeGroups(0, macro))
  if n == 0 then return {} end
  local buf = ffi.new("UpgradeGroup[?]", n)
  n = C.GetUpgradeGroups(buf, n, 0, macro)
  ---@type table<string, table>, table[]
  local byKey, buckets = {}, {}
  for i = 0, n - 1 do
    local path, group = ffi.string(buf[i].path), ffi.string(buf[i].group)
    if path ~= ".." or group ~= "" then
      local info = C.GetUpgradeGroupInfo(0, macro, path, group, upgradeType)
      local total = tonumber(info.total)
      if total > 0 then
        local picks, compatible = collect(candidates, function(candidate)
          return C.IsUpgradeGroupMacroCompatible(0, macro, path, group, upgradeType, candidate)
        end, allowed)
        local size = ffi.string(info.slotsize)
        local key = size .. "|" .. table.concat(picks, ",")
        if byKey[key] == nil then
          byKey[key] = {
            size = size,
            slots = 0,
            mandatory = 0,
            picks = picks,
            compatible = compatible,
            names = {},
          }
          table.insert(buckets, byKey[key])
        end
        local bucket = byKey[key]
        bucket.slots = bucket.slots + total
        table.insert(bucket.names, group ~= "" and group or path)
      end
    end
  end
  for _, bucket in ipairs(buckets) do
    bucket.label = string.format("group size=%s in %s", bucket.size ~= "" and bucket.size or "-",
      table.concat(bucket.names, "+"))
  end
  return buckets
end

--- The missiles the planned launchers can fire, preceded by those launchers: generated ammo
--- is keyed off the launchers in the same loadout, though only the ammo is ever applied.
--- Launchers taking no ammo are left out so they cannot crowd the others out of the slots.
local function getAmmoPool(pool, launchers, allowed)
  ---@type table<string, boolean>, table<string, boolean>, string[], string[]
  local seenAmmo, seenGun, missiles, guns = {}, {}, {}, {}
  for _, entry in ipairs(pool["missile"] or {}) do
    if allowed(entry.macro, entry.ware) then
      for _, launcher in ipairs(launchers) do
        if C.IsAmmoMacroCompatible(launcher, entry.macro) then
          if not seenAmmo[entry.macro] then
            seenAmmo[entry.macro] = true
            table.insert(missiles, entry.macro)
          end
          if not seenGun[launcher] then
            seenGun[launcher] = true
            table.insert(guns, launcher)
          end
        end
      end
    end
  end
  table.sort(guns)
  table.sort(missiles)
  for _, missile in ipairs(missiles) do
    table.insert(guns, missile)
  end
  return guns, #missiles
end

--- Per loadout flag, one pool per slot bucket, always the full candidate set: how many slots
--- get filled is left to generate_loadout's <quantity level="$preset">, since a capped pool
--- starves grouped slots. Buckets with no usable candidate are omitted, nil if none are left.
function scpEquipment.buildLoadoutPlan(macro, preset, faction)
  if macro == nil or preset == nil or preset <= 0 then
    -- A named or hull-default loadout brings its own equipment; there is nothing to plan for it.
    scpHelpers.debug(string.format("No equipment plan for %s: preset is %s", tostring(macro), tostring(preset)))
    return nil
  end

  local raceSet, raceList = getMakerRaces(macro)
  local races = #raceList > 0 and table.concat(raceList, "+") or "<none>"
  local factionSet = {}
  if faction ~= nil and faction ~= "" then factionSet[faction] = true end
  local allowed = makeRaceFilter(raceSet, factionSet)
  local pool = getEquipmentPool()
  ---@type table<string, string[][]>, string[]
  local plan, launchers = {}, {}
  local hasAny = false

  scpHelpers.trace(string.format("Equipment plan for %s at preset %s, maker races: %s, faction: %s",
    macro, tostring(preset), races, faction or "<none>"))

  for _, entry in ipairs(slotTypes) do
    ---@type string[][]
    local pools = {}
    ---@type table[], table[]
    local buckets, grouped
    if entry.virtual then
      buckets, grouped = getVirtualSlotBuckets(macro, entry.type, pool[entry.type], allowed), {}
    else
      buckets, grouped = getSlotBuckets(macro, entry.type, pool[entry.type], allowed)
    end
    if #grouped > 0 then
      -- Per group where the engine reports them, else fall back to the plain slot buckets.
      local groupBuckets = entry.groups and getGroupBuckets(macro, entry.type, pool[entry.type], allowed) or {}
      if #groupBuckets == 0 then
        if entry.groups then
          scpHelpers.debug(string.format("No %s groups reported for %s - planning its grouped slots by slot tags",
            entry.type, macro))
        end
        groupBuckets = grouped
      end
      for _, bucket in ipairs(groupBuckets) do
        table.insert(buckets, bucket)
      end
    end
    for _, bucket in ipairs(buckets) do
      if #bucket.picks == 0 then
        scpHelpers.debug(string.format(
          "No %s of race %s fits the [%s] %s slots of %s - %d slot(s) will stay empty (%d fit but are of another race)",
          entry.type, races, bucket.label, entry.type, macro, bucket.slots, bucket.compatible))
      else
        table.insert(pools, bucket.picks)
        if entry.type == "weapon" or entry.type == "turret" then
          for _, pick in ipairs(bucket.picks) do
            table.insert(launchers, pick)
          end
        end
        scpHelpers.trace(string.format("  %s [%s]: %d slot(s), %d mandatory, %d fit / %d usable -> %s",
          entry.type, bucket.label, bucket.slots, bucket.mandatory, bucket.compatible, #bucket.picks,
          table.concat(bucket.picks, " ")))
      end
    end
    if #pools > 0 then
      plan[entry.flag] = pools
      hasAny = true
    end
  end

  if hasAny then
    local ammoPool, missiles = getAmmoPool(pool, launchers, allowed)
    if missiles > 0 then
      plan.ammo = { ammoPool }
      scpHelpers.trace(string.format("  ammo: %d missile(s) for %d launcher(s) -> %s",
        missiles, #ammoPool - missiles, table.concat(ammoPool, " ")))
    end
  end

  return hasAny and plan or nil
end

Register_Require_Response("extensions.safe_cheat_panel.ui.scp_equipment", scpEquipment)
return scpEquipment
