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
    int32_t GetPersonCombinedSkill(UniverseID controllableid, NPCSeed person, const char* role, const char* postid);
    uint32_t GetRoleTierNPCs(NPCSeed* result, uint32_t resultlen, UniverseID controllableid, const char* role, int32_t skilllevel);
    uint32_t GetRoleTiers(RoleTierData* result, uint32_t resultlen, UniverseID controllableid, const char* role);
    bool IsComponentClass(UniverseID componentid, const char* classname);
]]

local menu         = Helper.getMenu("MapMenu")
local interactMenu = Helper.getMenu("InteractMenu")

local PAGE_ID = 1972092427

local config = {
  mapRowHeight = Helper.standardTextHeight,
  starSuffix = "\27[menu_star_04]",
}

local scpPromote = {
  state = {
    object = nil, -- 64-bit converted player ship id, set only via the interact menu action
    targets = {}, -- category id -> slider stars (1-5) set by the user
    initial = {}, -- category id -> slider start stars, derived from the current averages
    allSkills = false, -- set every skill (not just the role-relevant ones) to the target level
  },
}

function scpPromote.join(scp)
  scpPromote.scp = scp
end

function scpPromote.init()
  RegisterEvent("scp_main.crewPromoted", scpPromote.onCrewPromoted)
end

function scpPromote.onCrewPromoted()
  scpPromote.scp.debug("Promote: MD confirmed promotion, refreshing")
  scpPromote.state.targets = {}
  menu.refreshInfoFrame()
end

function scpPromote.isValidPromoteCrew()
  -- Only offered while the Promote Crew tab is the visible panel tab
  if menu.infoTableMode ~= "safeCheatPanel" or scpPromote.scp.tableMode ~= "scpPromote" then
    return false
  end
  local component = interactMenu.componentSlot and interactMenu.componentSlot.component
  if component == nil or component == 0 then
    return false
  end
  if not C.IsComponentClass(component, "ship") then
    return false
  end
  local convertedComponent = ConvertStringTo64Bit(tostring(component))
  if convertedComponent == 0 or not IsValidComponent(convertedComponent) then
    return false
  end
  return GetComponentData(convertedComponent, "isplayerowned") == true
end

function scpPromote.startPromote()
  scpPromote.state.object = ConvertStringTo64Bit(tostring(interactMenu.componentSlot.component))
  scpPromote.state.targets = {}
  scpPromote.state.allSkills = false
  scpPromote.scp.debug("Promote: ship set to " .. tostring(scpPromote.state.object))
  scpPromote.scp.helpers.interactMenuFinishAction()
  menu.refreshInfoFrame()
end

function scpPromote.reset()
  scpPromote.scp.debug("Promote: reset pressed")
  scpPromote.state.targets = {}
  menu.refreshInfoFrame()
end

function scpPromote.hasChanges()
  for category, value in pairs(scpPromote.state.targets) do
    if value ~= scpPromote.state.initial[category] then
      return true
    end
  end
  return false
end

function scpPromote.apply()
  -- MD receives event.param3 via AddUITriggeredEvent; component references crossing that
  -- boundary must be LuaID-converted (ConvertStringToLuaID), not the C-style 64bit id used
  -- for local GetComponentData/FFI calls elsewhere in this module.
  local data = { ship = ConvertStringToLuaID(tostring(scpPromote.state.object)), allSkills = scpPromote.state.allSkills }
  local anyChange = false
  local changes = ""
  for category, value in pairs(scpPromote.state.targets) do
    if value ~= scpPromote.state.initial[category] then
      data[category] = value
      anyChange = true
      changes = changes .. string.format(" %s=%d", category, value)
    end
  end
  scpPromote.scp.debug("Promote: apply pressed, allSkills=" .. tostring(scpPromote.state.allSkills) .. ", changes:" .. (anyChange and changes or " none"))
  if not anyChange then
    return
  end
  AddUITriggeredEvent("scp_main", "scp_promote_crew", data)
  scpPromote.scp.debug("Promote: promote event sent")
end

---Average role-relative combined skill (0-15) over all persons of a role on the ship.
---@return number count, number avg15
local function getRoleAverageSkill(object, role)
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

local function starsFromAvg15(avg15)
  local stars = math.floor(avg15 / 3 + 0.5)
  if stars < 1 then stars = 1 end
  if stars > 5 then stars = 5 end
  return stars
end

function scpPromote.collectData()
  local object = scpPromote.state.object
  local data = {}

  local pilotTitle = C.IsComponentClass(object, "ship_s") and ReadText(1001, 4847) or ReadText(1001, 4848) -- Pilot, Captain
  local pilot = GetComponentData(object, "assignedaipilot")
  if pilot and IsValidComponent(pilot) then
    local pilotName, pilotSkill = GetComponentData(pilot, "name", "combinedskill")
    data.pilot = { exists = true, title = pilotTitle, name = pilotName, avg15 = pilotSkill * 15 / 100 }
  else
    data.pilot = { exists = false, title = pilotTitle }
  end

  local marineCount, marineAvg = getRoleAverageSkill(object, "marine")
  data.marine = { count = marineCount, name = ReadText(20208, 20203), avg15 = marineAvg }

  local serviceCount, serviceAvg = getRoleAverageSkill(object, "service")
  data.service = { count = serviceCount, name = ReadText(20208, 20103), avg15 = serviceAvg }

  scpPromote.state.initial = {}
  if data.pilot.exists then
    scpPromote.state.initial.pilot = starsFromAvg15(data.pilot.avg15)
  end
  if marineCount > 0 then
    scpPromote.state.initial.marine = starsFromAvg15(marineAvg)
  end
  if serviceCount > 0 then
    scpPromote.state.initial.service = starsFromAvg15(serviceAvg)
  end

  return data
end

local function addCategorySliderRow(frameTable, category, labelText, avg15)
  local row = frameTable:addRow("promote_" .. category, { fixed = true, bgColor = Color["row_background_unselectable"] })
  local mouseOverText = string.format("%.2f / 5", avg15 / 3)
  row[1]:setColSpan(6):createText(labelText .. " " .. Helper.displaySkill(math.floor(avg15 + 0.5)), { mouseOverText = mouseOverText })
  local start = scpPromote.state.targets[category] or scpPromote.state.initial[category]
  row[7]:setColSpan(6):createSliderCell({
    height = config.mapRowHeight,
    min = 1,
    max = 5,
    start = start,
    step = 1,
    suffix = config.starSuffix,
    mouseOverText = mouseOverText,
  })
  row[7].handlers.onSliderCellChanged = function(_, value)
    scpPromote.state.targets[category] = math.floor(value + 0.5)
    scpPromote.scp.trace("Promote: slider " .. category .. " -> " .. tostring(scpPromote.state.targets[category]))
  end
  row[7].handlers.onSliderCellActivated = function() menu.noupdate = true end
  row[7].handlers.onSliderCellDeactivated = function() menu.noupdate = false end
  return row
end

function scpPromote.createSection(frameTable, numDisplayed, scp)
  numDisplayed = scp.menuHelper.createTitle(frameTable, numDisplayed, {
    text  = ReadText(PAGE_ID, 10000),
    fixed = true,
  })

  local object = scpPromote.state.object
  if object ~= nil and (not IsValidComponent(object) or GetComponentData(object, "isplayerowned") ~= true) then
    scpPromote.state.object = nil
    scpPromote.state.targets = {}
    object = nil
  end

  if object == nil then
    local row = frameTable:addRow(nil, { bgColor = Color["row_background_unselectable"] })
    row[1]:setColSpan(12):createText(ReadText(PAGE_ID, 10010), { halign = "center", color = Color["text_inactive"] })
    return numDisplayed + 1
  end

  local name, idcode, icon, sector, owner = GetComponentData(object, "name", "idcode", "icon", "sector", "owner")
  local factionColor = owner and Helper.convertColorToText(GetFactionData(owner, "color")) or ""
  local displayIcon = (icon ~= nil and icon ~= "") and icon or "menu_info"

  local row = frameTable:addRow("promote_ship_info", { fixed = true, bgColor = Color["row_background_unselectable"] })
  local iconCell = row[1]:setColSpan(12):createIcon(displayIcon, { height = config.mapRowHeight, width = config.mapRowHeight })
  iconCell:setText(string.format("%s%s (%s)", factionColor, name, idcode), { x = config.mapRowHeight, halign = "left" })
  iconCell:setText2(sector or "", { halign = "right" })
  numDisplayed = numDisplayed + 1

  local data = scpPromote.collectData()

  if data.pilot.exists then
    addCategorySliderRow(frameTable, "pilot", string.format("%s: %s", data.pilot.title, data.pilot.name), data.pilot.avg15)
  else
    row = frameTable:addRow(nil, { bgColor = Color["row_background_unselectable"] })
    row[1]:setColSpan(12):createText(string.format("%s: %s", data.pilot.title, ReadText(PAGE_ID, 10011)), { color = Color["text_inactive"] })
  end
  numDisplayed = numDisplayed + 1

  for _, category in ipairs({ "marine", "service" }) do
    local categoryData = data[category]
    local labelText = string.format("%s (%d)", categoryData.name, categoryData.count)
    if categoryData.count > 0 then
      addCategorySliderRow(frameTable, category, labelText, categoryData.avg15)
    else
      row = frameTable:addRow(nil, { bgColor = Color["row_background_unselectable"] })
      row[1]:setColSpan(12):createText(labelText, { color = Color["text_inactive"] })
    end
    numDisplayed = numDisplayed + 1
  end

  row = frameTable:addRow("promote_all_skills", { fixed = true, bgColor = Color["row_background_unselectable"] })
  row[1]:createCheckBox(scpPromote.state.allSkills, { active = true, width = config.mapRowHeight, height = config.mapRowHeight })
  row[1].handlers.onClick = function(_, checked)
    scpPromote.scp.debug("Promote: set-all-skills toggled to " .. tostring(checked))
    scpPromote.state.allSkills = checked
    menu.refreshInfoFrame()
  end
  row[2]:setColSpan(11):createText(ReadText(PAGE_ID, 10040), { color = Color["text_normal"] })
  numDisplayed = numDisplayed + 1

  row = frameTable:addRow("promote_buttons", { fixed = true, bgColor = Color["row_background_unselectable"] })
  row[1]:setColSpan(6):createButton({ active = function() return scpPromote.hasChanges() end }):setText(ReadText(1001, 3318), { halign = "center" }) -- Reset
  row[1].handlers.onClick = scpPromote.reset
  row[7]:setColSpan(6):createButton({ active = function() return scpPromote.hasChanges() end }):setText(ReadText(PAGE_ID, 10031), { halign = "center", color = Color["text_positive"] })
  row[7].handlers.onClick = scpPromote.apply
  numDisplayed = numDisplayed + 1

  return numDisplayed
end

Register_Require_Response("extensions.safe_cheat_panel.ui.scp_promote", scpPromote)
return scpPromote
