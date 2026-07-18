local ffi = require("ffi")
local C = ffi.C

ffi.cdef [[
	void AddResearch(const char* wareid);
]]

local mapMenu = Helper.getMenu("MapMenu")

local PAGE_ID = 1972092427

local scpResearch = {}

function scpResearch.processResearch(researchItems, researchIndex)
  local researchToUnlock = {}
  local function addResearchAndPrecursors(id)
    for i = 1, #researchItems do
      local research = researchItems[i]
      if research ~= nil and research.id == id and not research.completed then
        researchToUnlock[#researchToUnlock + 1] = research.id
        if research.precursors ~= nil and #research.precursors > 0 then
          for j = 1, #research.precursors do
            addResearchAndPrecursors(research.precursors[j])
          end
        end
        break
      end
    end
  end

  local researchSuccessors = {}
  local function collectResearchedSuccessors(id)
    for i = 1, #researchItems do
      local research = researchItems[i]
      if research ~= nil and research.completed then
        if research.precursors ~= nil and #research.precursors > 0 then
          for j = 1, #research.precursors do
            if research.precursors[j] == id then
              researchSuccessors[#researchSuccessors + 1] = research.id
              collectResearchedSuccessors(research.id)
              break
            end
          end
        end
      end
    end
  end

  if researchIndex == 0 then
    for i = 1, #researchItems do
      local research = researchItems[i]
      if research ~= nil and not research.completed then
        C.AddResearch(research.id)
      end
    end
  else
    local researchItem = researchItems[researchIndex]
    if researchItem == nil then return end
    if researchItem.completed then
      researchSuccessors[#researchSuccessors + 1] = researchItem.id
      collectResearchedSuccessors(researchItem.id)
      AddUITriggeredEvent("scp_main", "scp_remove_research", researchSuccessors)
      return
    else
      addResearchAndPrecursors(researchItems[researchIndex].id)
      for _, id in ipairs(researchToUnlock) do
        C.AddResearch(id)
      end
    end
  end
  mapMenu.refreshInfoFrame()
end

function scpResearch.createSection(frameTable, numDisplayed, scp)
  local researchItems, isAllUnlocked = scp.helpers.getAllResearch()
  numDisplayed = scp.menuHelper.createTitle(frameTable, numDisplayed, {
    text  = ReadText(PAGE_ID, 3000),
    fixed = true,
  })

  numDisplayed = scp.menuHelper.createButton(frameTable, "player_add_research", numDisplayed, {
    text            = ReadText(PAGE_ID, 3000),
    active          = isAllUnlocked == false,
    mouseOverText   = "",
    buttonText      = isAllUnlocked and ReadText(PAGE_ID, 3012) or ReadText(PAGE_ID, 3011),
    onClick         = function() scpResearch.processResearch(researchItems, 0) end,
    textColIndex    = nil,
    buttonColIndex  = nil,
    textColor       = nil,
    buttonTextColor = nil,
    fixed           = true,
    isHeader        = true,
  })

  local rowGroup = scp.isV9 and frameTable:addRowGroup({}) or frameTable
  for i = 1, #researchItems do
    local research = researchItems[i]
    if research ~= nil then
      numDisplayed = scp.menuHelper.createButton(rowGroup, "player_add_research", numDisplayed, {
        text            = string.rep(" ", research.depth) .. research.name,
        active          = true,
        mouseOverText   = research.description,
        buttonText      = research.completed and ReadText(PAGE_ID, 3022) or ReadText(PAGE_ID, 3021),
        onClick         = function() scpResearch.processResearch(researchItems, i) end,
        textColIndex    = nil,
        buttonColIndex  = nil,
        textColor       = not research.completed and Color["text_inactive"] or nil,
        buttonTextColor = research.completed and Color["text_negative"] or Color["text_positive"],
        fixed           = nil,
        isHeader        = nil,
      }) or numDisplayed
    end
  end
  return numDisplayed
end

Register_Require_Response("extensions.safe_cheat_panel.ui.scp_research", scpResearch)
return scpResearch
