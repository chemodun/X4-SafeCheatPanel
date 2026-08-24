local ffi = require("ffi")
local C = ffi.C

ffi.cdef [[
    typedef uint64_t UniverseID;

    typedef struct {
        uint32_t current;
        uint32_t capacity;
        uint32_t optimal;
        uint32_t available;
        uint32_t maxavailable;
        double timeuntilnextupdate;
    } WorkForceInfo;

    WorkForceInfo GetWorkForceInfo(UniverseID containerid, const char* raceid);
]]

local menu = Helper.getMenu("MapMenu")

local PAGE_ID = 1972092427

local scpWorkforce = {
  min          = 0,
  max          = 100,
  step         = 5,
  -- A spawn cannot know the plan's capacity before create_station, so it needs a flat default.
  spawnPercent = 30,
}

function scpWorkforce.join(scp)
  scpWorkforce.scp = scp
end

---`enabled` is the opt-in checkbox in both modes: unticked, the workforce is left exactly as the
---game left it. `initial` is the station's own fill in edit mode, nil for a spawn.
function scpWorkforce.newState()
  return {
    enabled = false,
    percent = scpWorkforce.spawnPercent,
    initial = nil,
  }
end

function scpWorkforce.resetState(state)
  state.enabled = false
  state.percent = scpWorkforce.spawnPercent
  state.initial = nil
end

---Aggregate workforce of a station: pass "" for every race at once, the way vanilla's own
---station overview reads it.
---@return number current, number capacity
function scpWorkforce.getFill(object)
  local info = C.GetWorkForceInfo(object, "")
  return tonumber(info.current) or 0, tonumber(info.capacity) or 0
end

---Current fill as a slider position, snapped to the slider's step so an untouched slider is a no-op.
local function snappedPercent(current, capacity)
  if capacity == 0 then
    return 0
  end
  local percent = current / capacity * 100
  percent = math.floor(percent / scpWorkforce.step + 0.5) * scpWorkforce.step
  return math.max(scpWorkforce.min, math.min(scpWorkforce.max, percent))
end

---Seeds `initial` (and, while the box is unticked, `percent`) from the live station, so edit mode
---opens on what the station actually has.
function scpWorkforce.seedInitial(state, object)
  local current, capacity = scpWorkforce.getFill(object)
  if capacity == 0 then
    state.initial = nil
    return 0, 0
  end
  state.initial = snappedPercent(current, capacity)
  if not state.enabled then
    state.percent = state.initial
  end
  return current, capacity
end

---A ticked box counts as a change only where it would actually move the workforce.
function scpWorkforce.hasChanges(state)
  return state.enabled and state.percent ~= state.initial
end

---The percentage to send, or nil when the box is unticked and MD should not touch the workforce.
function scpWorkforce.getChange(state)
  return state.enabled and state.percent or nil
end

---The whole block: title, opt-in checkbox and the percentage slider. `object` is nil for a spawn,
---in which case there is no capacity to report and the slider keeps the flat default.
function scpWorkforce.addRows(frameTable, numDisplayed, scp, state, object)
  ---@type number, number
  local current, capacity = 0, 0
  if object ~= nil then
    current, capacity = scpWorkforce.seedInitial(state, object)
    -- A station with no habitation modules has nowhere to put anybody.
    if capacity == 0 then
      return numDisplayed
    end
  end

  numDisplayed = scp.menuHelper.createTitle(frameTable, numDisplayed, {
    -- Vanilla's own wording, both from page 1001: "Station Workforce" and "Workforce".
    text  = ReadText(1001, 2456),
    fixed = nil,
  })
  numDisplayed = scp.menuHelper.createCheckBoxOnLeft(frameTable, "workforce_enabled", numDisplayed, {
    active        = true,
    checked       = state.enabled,
    text          = ReadText(PAGE_ID, 7440),
    mouseOverText = ReadText(PAGE_ID, 7441),
    textColIndex  = 2,
    fixed         = true,
    onClick       = function(_, checked)
      state.enabled = checked
      scpWorkforce.scp.debug("Workforce: explicit fill toggled to " .. tostring(checked))
      menu.refreshInfoFrame()
    end,
  })
  if not state.enabled then
    return numDisplayed
  end

  local label = ReadText(1001, 9415)
  if capacity > 0 then
    label = string.format("%s (%s / %s)", label, ConvertIntegerString(current, true, 0, true, false),
      ConvertIntegerString(capacity, true, 0, true, false))
  end
  return scp.menuHelper.createSliderRow(frameTable, "workforce_percent", numDisplayed, {
    text                = label,
    mouseOverText       = ReadText(PAGE_ID, 7442),
    startValue          = state.percent,
    onSliderChanged     = function(_, value)
      state.percent = math.floor(value + 0.5)
      scpWorkforce.scp.trace("Workforce: slider -> " .. tostring(state.percent) .. "%")
    end,
    onSliderActivated   = function() menu.noupdate = true end,
    onSliderDeactivated = function() menu.noupdate = false end,
    min                 = scpWorkforce.min,
    max                 = scpWorkforce.max,
    step                = scpWorkforce.step,
    suffix              = "%",
    sliderColIndex      = 7,
    fixed               = true,
  })
end

Register_Require_Response("extensions.safe_cheat_panel.ui.scp_workforce", scpWorkforce)
return scpWorkforce
