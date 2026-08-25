local ffi = require("ffi")
local C = ffi.C

ffi.cdef [[
    typedef uint64_t UniverseID;

    typedef struct {
        const char* id;
        const char* name;
        const char* desc;
        uint32_t amount;
        uint32_t numtiers;
        bool canhire;
    } PeopleInfo;

    uint32_t GetNumAllRoles(void);
    uint32_t GetPeople2(PeopleInfo* result, uint32_t resultlen, UniverseID controllableid, bool includearriving);
    uint32_t GetPeopleCapacity(UniverseID controllableid, const char* macroname, bool includepilot);
]]

local menu = Helper.getMenu("MapMenu")

local PAGE_ID = 1972092427

local scpCrewSize = {
  min                = 0,
  max                = 100,
  step               = 1,
  -- A spawn has no ship to read: a full crew, split down the middle.
  spawnPercent       = 100,
  spawnMarinePercent = 50,
}

function scpCrewSize.join(scp)
  scpCrewSize.scp = scp
end

local function round(value)
  return math.floor(value + 0.5)
end

---`initial` is also the "already seeded" flag, so a render mid-edit never pulls the sliders back.
function scpCrewSize.newState()
  return {
    percent       = scpCrewSize.spawnPercent,
    marinePercent = scpCrewSize.spawnMarinePercent,
    initial       = nil,
    initialMarine = nil,
  }
end

function scpCrewSize.resetState(state)
  state.percent       = scpCrewSize.spawnPercent
  state.marinePercent = scpCrewSize.spawnMarinePercent
  state.initial       = nil
  state.initialMarine = nil
end

---Crew capacity of a bare macro, pilot excluded.
function scpCrewSize.getMacroCapacity(macro)
  if macro == nil then
    return 0
  end
  return tonumber(C.GetPeopleCapacity(0, macro, false)) or 0
end

---Live crew picture of a ship. Only hireable roles count, so passengers and prisoners are left alone.
---@return number capacity, number total, number marines
function scpCrewSize.collect(object)
  local capacity = tonumber(C.GetPeopleCapacity(object, "", false)) or 0
  local numRoles = tonumber(C.GetNumAllRoles())
  local buffer = ffi.new("PeopleInfo[?]", numRoles)
  numRoles = C.GetPeople2(buffer, numRoles, object, true)
  ---@type number, number
  local total, marines = 0, 0
  for i = 0, numRoles - 1 do
    if buffer[i].canhire then
      local amount = tonumber(buffer[i].amount) or 0
      total = total + amount
      if ffi.string(buffer[i].id) == "marine" then
        marines = marines + amount
      end
    end
  end
  return capacity, total, marines
end

---Slider positions as head counts.
---@return number total, number marines, number service
function scpCrewSize.targets(state, capacity)
  local total = round(capacity * state.percent / 100)
  local marines = round(total * state.marinePercent / 100)
  return total, marines, total - marines
end

---Seeds both sliders from the ship, so an untouched slider is a no-op. Percentages are unsnapped
---so a seeded position resolves back to the exact head count the ship has.
---@return number capacity, number total, number marines
function scpCrewSize.seedInitial(state, object)
  local capacity, total, marines = scpCrewSize.collect(object)
  if capacity == 0 then
    return capacity, total, marines
  end
  local percent = math.max(scpCrewSize.min, math.min(scpCrewSize.max, round(total / capacity * 100)))
  local marinePercent = (total > 0) and round(marines / total * 100) or scpCrewSize.spawnMarinePercent
  if state.initial == nil then
    state.percent = percent
    state.marinePercent = marinePercent
  end
  state.initial = percent
  state.initialMarine = marinePercent
  return capacity, total, marines
end

---Edit mode only: a slider that never left its seeded position asks for nothing.
function scpCrewSize.hasChanges(state)
  if state.initial == nil then
    return false
  end
  return state.percent ~= state.initial or state.marinePercent ~= state.initialMarine
end

---Absolute head counts, not percentages: MD reconciles the ship against these directly.
function scpCrewSize.getChange(state, capacity)
  local _, marines, service = scpCrewSize.targets(state, capacity)
  return { marines = marines, service = service }
end

---Title and the two sliders. `current`/`currentMarines` are nil for a spawn; the caller skips the
---whole block when capacity is 0.
function scpCrewSize.addRows(frameTable, numDisplayed, scp, state, capacity, current, currentMarines)
  local total, marines, service = scpCrewSize.targets(state, capacity)

  numDisplayed = scp.menuHelper.createTitle(frameTable, numDisplayed, {
    text  = ReadText(PAGE_ID, 7450),
    fixed = nil,
  })

  local crewMouseOver = ReadText(PAGE_ID, 7451)
  if current ~= nil then
    crewMouseOver = string.format("%s\n%s: %d", crewMouseOver, ReadText(1001, 80), current)
  end
  numDisplayed = scp.menuHelper.createSliderRow(frameTable, "crewsize_percent", numDisplayed, {
    text                = string.format("%s: %d / %d", ReadText(1001, 80), total, capacity),
    mouseOverText       = crewMouseOver,
    startValue          = state.percent,
    onSliderChanged     = function(_, value)
      state.percent = round(value)
      scpCrewSize.scp.trace("CrewSize: crew slider -> " .. tostring(state.percent) .. "%")
    end,
    onSliderActivated   = function() menu.noupdate = true end,
    -- Refreshed on release: both labels carry the head counts the sliders resolve to.
    onSliderDeactivated = function()
      menu.noupdate = false
      menu.refreshInfoFrame()
    end,
    onSliderConfirm     = function() menu.refreshInfoFrame() end,
    min                 = scpCrewSize.min,
    max                 = scpCrewSize.max,
    step                = scpCrewSize.step,
    suffix              = "%",
    sliderColIndex      = 7,
    fixed               = true,
  })

  local splitMouseOver = ReadText(PAGE_ID, 7452)
  if currentMarines ~= nil then
    splitMouseOver = string.format("%s\n%s: %d", splitMouseOver, ReadText(20208, 20203), currentMarines)
  end
  return scp.menuHelper.createSliderRow(frameTable, "crewsize_marines", numDisplayed, {
    text                = string.format("%s: %d - %s: %d", ReadText(20208, 20203), marines, ReadText(20208, 20103), service),
    mouseOverText       = splitMouseOver,
    startValue          = state.marinePercent,
    onSliderChanged     = function(_, value)
      state.marinePercent = round(value)
      scpCrewSize.scp.trace("CrewSize: marine slider -> " .. tostring(state.marinePercent) .. "%")
    end,
    onSliderActivated   = function() menu.noupdate = true end,
    onSliderDeactivated = function()
      menu.noupdate = false
      menu.refreshInfoFrame()
    end,
    onSliderConfirm     = function() menu.refreshInfoFrame() end,
    min                 = scpCrewSize.min,
    max                 = scpCrewSize.max,
    step                = scpCrewSize.step,
    suffix              = "%",
    sliderColIndex      = 7,
    textColor           = (total > 0) and Color["text_normal"] or Color["text_inactive"],
    readOnly            = total == 0,
    fixed               = true,
  })
end

Register_Require_Response("extensions.safe_cheat_panel.ui.scp_crewsize", scpCrewSize)
return scpCrewSize
