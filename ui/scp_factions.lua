local ffi = require("ffi")
local C = ffi.C

ffi.cdef [[
	typedef struct {
		int relationStatus;
		int relationValue;
		int relationLEDValue;
		bool isBoostedValue;
	} RelationDetails;

	RelationDetails GetFactionRelationStatus2(const char* factionid);
	void SetFactionRelationToPlayerFaction(const char* factionid, const char* reason, float newrelation);
]]

local menu = Helper.getMenu("MapMenu")

local PAGE_ID    = 1972092427
local SLIDER_MIN = -30
local SLIDER_MAX = 30

local relations_t = {
  [1] = 0.00064, [2] = 0.00128, [3] = 0.00192, [4] = 0.00256, [5] = 0.00320,
  [6] = 0.00402, [7] = 0.00505, [8] = 0.00634, [9] = 0.00797, [10] = 0.01000,
  [11] = 0.01262, [12] = 0.01593, [13] = 0.02010, [14] = 0.02536, [15] = 0.03200,
  [16] = 0.04020, [17] = 0.05048, [18] = 0.06340, [19] = 0.07963, [20] = 0.10000,
  [21] = 0.12620, [22] = 0.15925, [23] = 0.20096, [24] = 0.25359, [25] = 0.32000,
  [26] = 0.40000, [27] = 0.50000, [28] = 0.62996, [29] = 0.79370, [30] = 1.00000,
}

local function calculateRelationValue(newValue, isNegative)
  if isNegative then
    newValue = -newValue
  end
  local newRelation = relations_t[newValue] or 0
  if isNegative then
    newRelation = -newRelation
  end
  return newRelation
end

local state = {
  factionFor = "player",
  data       = {},
  refreshed  = 0,
}

-- References set during init
local _playerId      = nil
local _variableId    = nil
local _blacklisted   = nil

local scpFactions = {}
scpFactions.state = state

function scpFactions.init(playerId, variableId, blacklistedFactions)
  _playerId    = playerId
  _variableId  = variableId
  _blacklisted = blacklistedFactions
end

function scpFactions.requestFactionRelations(factionId)
  factionId = factionId or "player"
  if state.factionFor ~= factionId then
    state.factionFor = factionId
    if state.factionFor ~= "player" then
      menu.noupdate = true
      state.data = {}
      SetNPCBlackboard(_playerId, _variableId, {})
      AddUITriggeredEvent("scp_main", "scp_get_faction_relation", factionId)
      return true
    else
      menu.refreshInfoFrame()
    end
  end
  return false
end

function scpFactions.onRelationsData()
  menu.noupdate = false
  local data = GetNPCBlackboard(_playerId, _variableId)
  if data and type(data) == "table" then
    state.data     = data
    state.refreshed = getElapsedTime()
    menu.refreshInfoFrame()
  end
end

function scpFactions.setRelation(factionId, newValue, isNegative)
  local newRelation = calculateRelationValue(newValue, isNegative)
  if state.factionFor == "player" then
    C.SetFactionRelationToPlayerFaction(factionId, "missioncompleted", newRelation)
    menu.refreshInfoFrame()
  else
    state.data = {}
    SetNPCBlackboard(_playerId, _variableId, {})
    AddUITriggeredEvent("scp_main", "scp_set_faction_relation", {
      factionId      = state.factionFor,
      otherFactionId = factionId,
      newRelation    = newRelation
    })
  end
end

function scpFactions.createSection(frameTable, numDisplayed, scp)
  if state.factionFor ~= "player" and next(state.data) == nil then
    scpFactions.requestFactionRelations(state.factionFor)
    return numDisplayed
  end

  local factionsOptions = {}
  local isRelationLocked = false

  if scp.helpers.isExtendedMode() then
    factionsOptions = scp.helpers.getAllFactions(_blacklisted)
    for i = 1, #factionsOptions do
      local faction = factionsOptions[i]
      if faction ~= nil then
        faction["isrelationlocked"] = GetFactionData(factionsOptions[i].id, "isrelationlocked")
        if faction.id == state.factionFor then
          isRelationLocked = faction.isrelationlocked
        end
      end
    end
  else
    local factions = GetLibrary("factions")
    table.sort(factions, Helper.sortName)
    local playerFactionOptions = nil
    for i = 1, #factions do
      local faction = factions[i]
      if faction.id ~= "player" then
        factions[i]["isrelationlocked"] = GetFactionData(faction.id, "isrelationlocked")
        if faction.id == state.factionFor then
          isRelationLocked = factions[i].isrelationlocked
        end
        factionsOptions[#factionsOptions + 1] = { id = faction.id, text = string.format("\027[%s] %s", faction.icon, faction.name), name = faction.name, active = true, icon = "", displayremoveoption = false }
      else
        faction.icon = GetFactionData(faction.id, "icon")
        playerFactionOptions = { id = faction.id, text = string.format("\027[%s] %s", faction.icon, faction.name), name = faction.name, active = true, icon = "", displayremoveoption = false }
      end
    end
    if playerFactionOptions == nil then
      local name, icon = GetFactionData("player", "name", "icon")
      playerFactionOptions = { id = "player", text = string.format("\027[%s] %s", icon, name), name = name, active = true, icon = "", displayremoveoption = false }
    end
    table.insert(factionsOptions, 1, playerFactionOptions)
  end

  numDisplayed = scp.menuHelper.createTitle(frameTable, numDisplayed, {
    text  = ReadText(PAGE_ID, 5000),
    fixed = nil,
  })

  local rowGroup = scp.isV9 and frameTable:addRowGroup({}) or frameTable
  numDisplayed = scp.menuHelper.createDropDown(rowGroup, "faction", numDisplayed, {
    active           = scp.helpers.isExtendedMode(),
    dropDownData     = factionsOptions,
    startOption      = state.factionFor,
    text             = ReadText(PAGE_ID, 5005),
    textOverride     = "",
    onConfirmed      = function(_, value) scpFactions.requestFactionRelations(value) end,
    textColIndex     = nil,
    dropDownColIndex = nil,
    dropDownSpan     = nil,
    textColor        = nil,
    fixed            = nil,
    isHeader         = nil,
  })

  for i = 1, #factionsOptions do
    local faction = factionsOptions[i]
    if faction.id ~= state.factionFor then
      local relationValue = 0
      if state.factionFor == "player" then
        local factionrelation = C.GetFactionRelationStatus2(faction.id)
        relationValue = factionrelation.relationValue
      else
        relationValue = state.data[faction.id]
      end

      local factionTextColor = GetFactionData(faction.id, "color") or Color["text_normal"]
      local isLocked = faction.isrelationlocked or isRelationLocked

      numDisplayed = scp.menuHelper.createSliderRow(rowGroup, nil, numDisplayed, {
        text                = faction.text,
        mouseOverText       = faction.name,
        startValue          = relationValue,
        onSliderChanged     = not isLocked and function(_, value)
          menu.noupdate = true; faction.newrelation = value
        end or nil,
        onSliderConfirm     = not isLocked and function()
          menu.noupdate = false
          scpFactions.setRelation(faction.id, faction.newrelation, faction.newrelation < 0)
        end or nil,
        onSliderActivated   = nil,
        onSliderDeactivated = nil,
        min                 = SLIDER_MIN,
        max                 = SLIDER_MAX,
        step                = 1,
        fromCenter          = true,
        readOnly            = isLocked,
        textColIndex        = nil,
        sliderColIndex      = nil,
        sliderSpan          = nil,
        textColor           = factionTextColor,
      })
    end
  end

  if state.factionFor ~= "player" then
    if getElapsedTime() - state.refreshed > 10 then
      local currentFaction = state.factionFor
      state.factionFor = ""
      scpFactions.requestFactionRelations(currentFaction)
    end
  end

  return numDisplayed
end

Register_Require_Response("extensions.safe_cheat_panel.ui.scp_factions", scpFactions)
return scpFactions
