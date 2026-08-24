local ffi = require("ffi")
local C = ffi.C

ffi.cdef [[
    typedef uint64_t UniverseID;
    typedef uint64_t NPCSeed;

    typedef struct {
        const char* id;
        const char* name;
        const char* desc;
        uint32_t amount;
        uint32_t numtiers;
        bool canhire;
    } PeopleInfo;

    typedef struct {
        const char* name;
        int32_t skilllevel;
        uint32_t amount;
    } RoleTierData;

    uint32_t GetNumAllRoles(void);
    uint32_t GetPeople2(PeopleInfo* result, uint32_t resultlen, UniverseID controllableid, bool includearriving);
    int32_t GetEntityCombinedSkill(UniverseID entityid, const char* role, const char* postid);
    int32_t GetPersonCombinedSkill(UniverseID controllableid, NPCSeed person, const char* role, const char* postid);
    uint32_t GetRoleTierNPCs(NPCSeed* result, uint32_t resultlen, UniverseID controllableid, const char* role, int32_t skilllevel);
    uint32_t GetRoleTiers(RoleTierData* result, uint32_t resultlen, UniverseID controllableid, const char* role);
    bool IsComponentClass(UniverseID componentid, const char* classname);
]]

local menu = Helper.getMenu("MapMenu")

local PAGE_ID = 1972092427

local scpCrew = {
  -- Whole stars the sliders work in; MD multiplies by 3 to reach the 0-15 skill scale.
  minStars    = 1,
  maxStars    = 5,
  starSuffix  = "\27[menu_star_04]",
  -- Categories a ship and a station offer, in render order.
  shipCategories    = { "pilot", "marine", "service" },
  stationCategories = { "manager", "trader", "defence", "engineer" },
}

function scpCrew.join(scp)
  scpCrew.scp = scp
end

---Fresh crew-skill state, shared by the spawn and the edit path.
---`enabled` is the opt-in checkbox in spawn mode and is forced true in edit mode.
function scpCrew.newState()
  return {
    enabled   = false,
    allSkills = false,
    targets   = {},
    initial   = {},
  }
end

function scpCrew.resetState(state)
  state.enabled   = false
  state.allSkills = false
  state.targets   = {}
  state.initial   = {}
end

function scpCrew.starsFromAvg15(avg15)
  local stars = math.floor(avg15 / 3 + 0.5)
  if stars < scpCrew.minStars then stars = scpCrew.minStars end
  if stars > scpCrew.maxStars then stars = scpCrew.maxStars end
  return stars
end

---Average role-relative combined skill (0-15) over all persons of a role on the object.
---@return number count, number avg15
function scpCrew.getRoleAverageSkill(object, role)
  local count = 0
  local sum = 0
  local numRoles = tonumber(C.GetNumAllRoles())
  local peopleBuffer = ffi.new("PeopleInfo[?]", numRoles)
  numRoles = C.GetPeople2(peopleBuffer, numRoles, object, true)
  local numTiers = 0
  for i = 0, numRoles - 1 do
    if ffi.string(peopleBuffer[i].id) == role then
      numTiers = peopleBuffer[i].numtiers
      break
    end
  end
  if numTiers == 0 then
    return 0, 0
  end
  local tierBuffer = ffi.new("RoleTierData[?]", numTiers)
  numTiers = C.GetRoleTiers(tierBuffer, numTiers, object, role)
  for i = 0, numTiers - 1 do
    local numPersons = tierBuffer[i].amount
    if numPersons > 0 then
      local personBuffer = ffi.new("NPCSeed[?]", numPersons)
      numPersons = C.GetRoleTierNPCs(personBuffer, numPersons, object, role, tierBuffer[i].skilllevel)
      for j = 0, numPersons - 1 do
        count = count + 1
        sum = sum + tonumber(C.GetPersonCombinedSkill(object, personBuffer[j], role, nil))
      end
    end
  end
  if count == 0 then
    return 0, 0
  end
  return count, (sum / count) * 15 / 100
end

---Post-relative combined skill (0-15) of a control entity, or nil when the post is vacant.
local function getPostSkill(object, dataKey, postId)
  local entity = GetComponentData(object, dataKey)
  if entity == nil or entity == 0 then
    return nil
  end
  entity = ConvertStringTo64Bit(tostring(entity))
  if not IsValidComponent(entity) then
    return nil
  end
  local name, isfemale = GetComponentData(entity, "name", "isfemale")
  return tonumber(C.GetEntityCombinedSkill(entity, nil, postId)) * 15 / 100, name, isfemale
end

---Post titles. The four station control posts use vanilla page 20208 (male id, female id);
---defence has no vanilla station-post wording, so it keeps the mod's own text.
local categoryTitles = {
  pilot    = { 1001, 4848 },
  marine   = { 20208, 20203 },
  service  = { 20208, 20103 },
  manager  = { 20208, 30301, 30302 },
  trader   = { 20208, 30501, 30502 },
  defence  = { PAGE_ID, 7426 },
  engineer = { 20208, 30401, 30402 },
}

local function categoryTitle(category, isfemale)
  local ref = categoryTitles[category]
  return ReadText(ref[1], (isfemale and ref[3]) or ref[2])
end

---Per-category crew picture of a ship: the pilot post plus the two crew roles.
function scpCrew.collectShip(object)
  local data = {}

  local pilotTitle = C.IsComponentClass(object, "ship_s") and ReadText(1001, 4847) or ReadText(1001, 4848) -- Pilot, Captain
  local pilot = GetComponentData(object, "assignedaipilot")
  if pilot and IsValidComponent(pilot) then
    local pilotName, pilotSkill = GetComponentData(pilot, "name", "combinedskill")
    data.pilot = { exists = true, title = pilotTitle, name = pilotName, avg15 = pilotSkill * 15 / 100 }
  else
    data.pilot = { exists = false, title = pilotTitle }
  end

  for _, entry in ipairs({ { "marine", 20208, 20203 }, { "service", 20208, 20103 } }) do
    local count, avg15 = scpCrew.getRoleAverageSkill(object, entry[1])
    data[entry[1]] = { exists = count > 0, count = count, title = ReadText(entry[2], entry[3]), avg15 = avg15 }
  end

  return data
end

---Per-category crew picture of a station's four control posts. The ship trader post declares no
---skills of its own, so it is read and written as management + morale, like the manager.
function scpCrew.collectStation(object)
  local data = {}
  for _, entry in ipairs({
    { "manager",  "tradenpc",   "manager" },
    { "trader",   "shiptrader", "manager" },
    { "defence",  "defencenpc", "defence" },
    { "engineer", "engineer",   "engineer" },
  }) do
    local avg15, name, isfemale = getPostSkill(object, entry[2], entry[3])
    data[entry[1]] = { exists = avg15 ~= nil, name = name, title = categoryTitle(entry[1], isfemale), avg15 = avg15 or 0 }
  end
  return data
end

---Baseline for hasChanges(); a category with nobody in it is left out entirely.
function scpCrew.seedInitial(state, data, categories)
  state.initial = {}
  for _, category in ipairs(categories) do
    local entry = data[category]
    if entry and entry.exists then
      state.initial[category] = scpCrew.starsFromAvg15(entry.avg15)
    end
  end
end

---The all-skills flag is a change on its own: it rewrites skills an untouched slider would not.
function scpCrew.hasChanges(state)
  if state.allSkills then
    return true
  end
  for category, value in pairs(state.targets) do
    if value ~= state.initial[category] then
      return true
    end
  end
  return false
end

---Only this mode's categories: sliders write straight into `targets`, which a mode switch would
---otherwise carry across.
function scpCrew.pickCategories(state, categories)
  local picked = {}
  local any = false
  for _, category in ipairs(categories) do
    if state.targets[category] then
      picked[category] = state.targets[category]
      any = true
    end
  end
  return any and picked or nil
end

---Changed categories only, as { category = stars }. Untouched ones keep their fractional average;
---with `allSkills` on every category is sent, since the flag changes what gets written anyway.
function scpCrew.getChanges(state)
  local changes = {}
  local any = false
  if state.allSkills then
    for category, value in pairs(state.initial) do
      changes[category] = value
      any = true
    end
  end
  for category, value in pairs(state.targets) do
    if state.allSkills or value ~= state.initial[category] then
      changes[category] = value
      any = true
    end
  end
  return any and changes or nil
end

local function addSliderRow(frameTable, numDisplayed, scp, state, category, labelText, avg15, active)
  local start = state.targets[category] or state.initial[category] or scpCrew.starsFromAvg15(avg15)
  return scp.menuHelper.createSliderRow(frameTable, "crew_" .. category, numDisplayed, {
    text                = labelText .. " " .. Helper.displaySkill(math.floor(avg15 + 0.5)),
    mouseOverText       = string.format("%.2f / %d", avg15 / 3, scpCrew.maxStars),
    startValue          = start,
    onSliderChanged     = function(_, value)
      state.targets[category] = math.floor(value + 0.5)
      scpCrew.scp.trace("Crew: slider " .. category .. " -> " .. tostring(state.targets[category]))
    end,
    onSliderActivated   = function() menu.noupdate = true end,
    onSliderDeactivated = function() menu.noupdate = false end,
    min                 = scpCrew.minStars,
    max                 = scpCrew.maxStars,
    step                = 1,
    suffix              = scpCrew.starSuffix,
    sliderColIndex      = 7,
    readOnly            = not active,
    fixed               = true,
  })
end

local function addVacantRow(frameTable, numDisplayed, labelText)
  local row = frameTable:addRow(nil, { fixed = true, bgColor = Color["row_background_unselectable"] })
  row[1]:setColSpan(12):createText(string.format("%s: %s", labelText, ReadText(PAGE_ID, 7404)), { color = Color["text_inactive"] })
  return numDisplayed + 1
end

---The "set crew skills explicitly" checkbox. Unchecked, a spawn keeps the loadout preset's
---randomised skill ranges; in edit mode the caller keeps `enabled` true and skips this row.
function scpCrew.addEnableRow(frameTable, numDisplayed, scp, state)
  return scp.menuHelper.createCheckBoxOnLeft(frameTable, "crew_enabled", numDisplayed, {
    active       = true,
    checked      = state.enabled,
    text         = ReadText(PAGE_ID, 7411),
    mouseOverText = ReadText(PAGE_ID, 7412),
    textColIndex = 2,
    fixed        = true,
    onClick      = function(_, checked)
      state.enabled = checked
      scpCrew.scp.debug("Crew: explicit skills toggled to " .. tostring(checked))
      menu.refreshInfoFrame()
    end,
  })
end

function scpCrew.addAllSkillsRow(frameTable, numDisplayed, scp, state, active)
  return scp.menuHelper.createCheckBoxOnLeft(frameTable, "crew_all_skills", numDisplayed, {
    active       = active,
    checked      = state.allSkills,
    text         = ReadText(PAGE_ID, 7413),
    textColIndex = 2,
    textColor    = active and Color["text_normal"] or Color["text_inactive"],
    fixed        = true,
    onClick      = function(_, checked)
      state.allSkills = checked
      scpCrew.scp.debug("Crew: set-all-skills toggled to " .. tostring(checked))
      menu.refreshInfoFrame()
    end,
  })
end

---Slider block for a ship's crew. `data` comes from collectShip; a category with nobody in it
---renders as an inactive "Not assigned" line instead of a slider.
function scpCrew.addShipRows(frameTable, numDisplayed, scp, state, data, active)
  if data.pilot.exists then
    numDisplayed = addSliderRow(frameTable, numDisplayed, scp, state, "pilot",
      string.format("%s: %s", data.pilot.title, data.pilot.name), data.pilot.avg15, active)
  else
    numDisplayed = addVacantRow(frameTable, numDisplayed, data.pilot.title)
  end
  for _, category in ipairs({ "marine", "service" }) do
    local entry = data[category]
    local label = string.format("%s (%d)", entry.title, entry.count)
    if entry.exists then
      numDisplayed = addSliderRow(frameTable, numDisplayed, scp, state, category, label, entry.avg15, active)
    else
      local row = frameTable:addRow(nil, { fixed = true, bgColor = Color["row_background_unselectable"] })
      row[1]:setColSpan(12):createText(label, { color = Color["text_inactive"] })
      numDisplayed = numDisplayed + 1
    end
  end
  return numDisplayed
end

---Slider block for a station's control posts. A post that neither exists nor is `pending` gets no row.
function scpCrew.addStationRows(frameTable, numDisplayed, scp, state, data, active, pending)
  for _, category in ipairs(scpCrew.stationCategories) do
    local entry = data[category]
    if entry.exists or pending[category] then
      local label = entry.name and string.format("%s: %s", entry.title, entry.name) or entry.title
      numDisplayed = addSliderRow(frameTable, numDisplayed, scp, state, category, label, entry.avg15, active)
    end
  end
  return numDisplayed
end

---Sliders for a spawn, one per category the caller offers. Nothing renders while `enabled` is off.
function scpCrew.addSpawnRows(frameTable, numDisplayed, scp, state, categories)
  if not state.enabled then
    return numDisplayed
  end
  for _, category in ipairs(categories) do
    local start = state.targets[category] or 3
    state.targets[category] = start
    numDisplayed = scp.menuHelper.createSliderRow(frameTable, "crew_" .. category, numDisplayed, {
      text                = categoryTitle(category),
      startValue          = start,
      onSliderChanged     = function(_, value) state.targets[category] = math.floor(value + 0.5) end,
      onSliderActivated   = function() menu.noupdate = true end,
      onSliderDeactivated = function() menu.noupdate = false end,
      min                 = scpCrew.minStars,
      max                 = scpCrew.maxStars,
      step                = 1,
      suffix              = scpCrew.starSuffix,
      sliderColIndex      = 7,
      fixed               = true,
    })
  end
  return numDisplayed
end

Register_Require_Response("extensions.safe_cheat_panel.ui.scp_crew", scpCrew)
return scpCrew
