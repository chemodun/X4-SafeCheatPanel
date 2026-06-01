local ffi = require("ffi")
local C = ffi.C

ffi.cdef [[
	typedef uint64_t UniverseID;
	uint32_t GetNumWares(const char* tags, bool research, const char* licenceownerid, const char* exclusiontags);
	uint32_t GetWares(const char** result, uint32_t resultlen, const char* tags, bool research, const char* licenceownerid, const char* exclusiontags);
	UniverseID GetPlayerZoneID(void);
]]

local menu = Helper.getMenu("MapMenu")
local scpMenuHelper = require("extensions.safe_cheat_panel.ui.scp_menu_helper")

local PAGE_ID = 1972092427

local inventoryCategories = {
  { id = "crafting",    name = ReadText(1001, 2827) },
  { id = "upgrade",     name = ReadText(1001, 7716) },
  { id = "modParts",    name = ReadText(PAGE_ID, 2901) },
  { id = "seminars",    name = ReadText(PAGE_ID, 2902) },
  { id = "tradeOnly",   name = ReadText(1001, 2829) },
  { id = "curiosity",   name = ReadText(20215, 3101) },
  { id = "luxuryItem",  name = ReadText(20215, 3401) },
  { id = "useful",      name = ReadText(1001, 2828) },
  { id = "paintMod",    name = ReadText(1001, 8510) },
  { id = "missionOnly", name = ReadText(PAGE_ID, 2903) },
}

local state = {
  wares          = {},
  category       = 1,
  categories     = {},
  categoryOptions = {},
  selected       = nil,
  newAmount      = nil,
}

local scpInventory = {}
scpInventory.state = state

function scpInventory.prepareData()
  local numItems = C.GetNumWares("inventory", false, "", "clothingmod personalupgrade deprecated seminar missiononly")
  local inventoryItems = ffi.new("const char*[?]", numItems)
  numItems = C.GetWares(inventoryItems, numItems, "inventory", false, "", "clothingmod personalupgrade deprecated seminar missiononly")

  local wareCategories = {}
  local wareCategoryIdx = {}
  for i = 1, #inventoryCategories do
    local entry = inventoryCategories[i]
    wareCategoryIdx[entry.id] = i
    table.insert(wareCategories, { id = entry.id, name = entry.name, data = {} })
  end

  local wares = {}
  for i = 0, numItems - 1 do
    local ware = ffi.string(inventoryItems[i])
    local name, isCraftingResource, isModPart, isPrimaryModpart, isPersonalUpgrade, tradeOnly, isPaintMod, isBraneItem, group =
        GetWareData(ware, "name", "iscraftingresource", "ismodpart", "isprimarymodpart", "ispersonalupgrade", "tradeonly", "ispaintmod", "isbraneitem", "groupID")
    wares[ware] = { id = ware, name = name, group = group }

    if isModPart or isPrimaryModpart then
      table.insert(wareCategories[wareCategoryIdx["modParts"]].data, ware)
    elseif isCraftingResource then
      table.insert(wareCategories[wareCategoryIdx["crafting"]].data, ware)
    elseif isPersonalUpgrade then
      table.insert(wareCategories[wareCategoryIdx["upgrade"]].data, ware)
    elseif tradeOnly then
      table.insert(wareCategories[wareCategoryIdx["tradeOnly"]].data, ware)
    elseif isPaintMod then
      table.insert(wareCategories[wareCategoryIdx["paintMod"]].data, ware)
    elseif not isBraneItem then
      if group == "curiosity" then
        table.insert(wareCategories[wareCategoryIdx["curiosity"]].data, ware)
      elseif group == "luxuryitem" then
        table.insert(wareCategories[wareCategoryIdx["luxuryItem"]].data, ware)
      else
        table.insert(wareCategories[wareCategoryIdx["useful"]].data, ware)
      end
    end
  end

  local numSeminars = C.GetNumWares("seminar", false, "", "deprecated")
  local seminars = ffi.new("const char*[?]", numSeminars)
  numSeminars = C.GetWares(seminars, numSeminars, "seminar", false, "", "deprecated")
  for i = 0, numSeminars - 1 do
    local ware = ffi.string(seminars[i])
    local name = GetWareData(ware, "name")
    wares[ware] = { id = ware, name = name }
    table.insert(wareCategories[wareCategoryIdx["seminars"]].data, ware)
  end

  local numMissionItems = C.GetNumWares("missiononly", false, "", "deprecated")
  local missionItems = ffi.new("const char*[?]", numMissionItems)
  numMissionItems = C.GetWares(missionItems, numMissionItems, "missiononly", false, "", "deprecated")
  for i = 0, numMissionItems - 1 do
    local ware = ffi.string(missionItems[i])
    local name = GetWareData(ware, "name")
    wares[ware] = { id = ware, name = name }
    table.insert(wareCategories[wareCategoryIdx["missionOnly"]].data, ware)
  end

  local categoryOptions = {}
  for i = 1, #inventoryCategories do
    local category = wareCategories[i]
    if category ~= nil and #category.data > 0 then
      table.sort(category.data, function(a, b) return wares[a].name < wares[b].name end)
      categoryOptions[#categoryOptions + 1] = { id = i, text = category.name, active = true, icon = "", displayremoveoption = false }
    end
  end

  state.wares          = wares
  state.categories     = wareCategories
  state.categoryOptions = categoryOptions
end

function scpInventory.reset()
  state.selected = nil
end

function scpInventory.SetWare(wareId, oldAmount, newAmount)
  if not oldAmount or not newAmount then
    menu.refreshInfoFrame()
    return
  end
  local maxAmount = 10000
  newAmount = math.max(0, math.min(newAmount, maxAmount))
  RemoveInventory(nil, wareId, oldAmount)
  AddInventory(nil, wareId, newAmount, true)
  PlaySound("ui_crafting_success")
  menu.refreshInfoFrame()
end

function scpInventory.setCategory(value)
  state.category = value ~= nil and math.floor(tonumber(value)) or 1
  menu.refreshInfoFrame()
end

function scpInventory.createSection(frameTable, numDisplayed, scp)
  local policeFaction = GetComponentData(ConvertStringToLuaID(tostring(C.GetPlayerZoneID())), "policefaction")
  numDisplayed = scp.menuHelper.createTitle(frameTable, {
    text         = ReadText(1001, 2202),
    numDisplayed = numDisplayed,
    fixed        = true,
  })

  local playerInventory = GetPlayerInventory()
  local onlineItems     = OnlineGetUserItems()

  numDisplayed = scp.menuHelper.createDropDown(frameTable, "inventory_category", {
    active           = true,
    dropDownData     = state.categoryOptions,
    startOption      = state.category,
    text             = ReadText(PAGE_ID, 2010),
    textOverride     = "",
    onConfirmed      = function(_, value)
      menu.noupdate = false
      scp.currentRow[scp.tableMode] = nil
      SetTopRow(menu.infoTable, scp.table.numfixedrows + 1)
      return scpInventory.setCategory(value)
    end,
    numDisplayed     = numDisplayed,
    textColIndex     = nil,
    dropDownColIndex = nil,
    dropDownSpan     = nil,
    textColor        = nil,
    fixed            = true,
    isHeader         = nil,
  })

  local category = state.categories[state.category]
  if category ~= nil and #category.data > 0 then
    table.sort(category.data, function(a, b) return state.wares[a].name < state.wares[b].name end)
    numDisplayed = scp.menuHelper.createTitle(frameTable, {
      text         = category.name,
      numDisplayed = numDisplayed,
      fixed        = true,
    })
    local wareRowGroup = scp.isV9 and frameTable:addRowGroup({}) or frameTable
    for j = 1, #category.data do
      local wareId = category.data[j]
      if category.id ~= "useful" or not onlineItems[wareId] then
        local ware = wareId and state.wares[wareId] or nil
        if ware ~= nil then
          local amount    = playerInventory[wareId] and playerInventory[wareId].amount or 0
          local isIllegal = policeFaction and IsWareIllegalTo(wareId, "player", policeFaction)
          local textColor = amount == 0 and Color["text_inactive"] or isIllegal and Color["text_illegal"] or nil
          if state.selected == wareId then
            numDisplayed = scp.menuHelper.createSliderRow(wareRowGroup, true, {
              text                = ware.name,
              mouseOverText       = ReadText(PAGE_ID, 2003),
              startValue          = amount,
              onSliderChanged     = function(_, value)
                menu.noupdate = true
                state.newAmount = value
              end,
              onSliderConfirm     = function()
                state.selected = nil
                if state.newAmount ~= amount and state.newAmount ~= nil then
                  scp.inventory.SetWare(wareId, amount, state.newAmount)
                end
                state.newAmount = nil
              end,
              onSliderActivated   = function() menu.noupdate = true end,
              onSliderDeactivated = function() menu.noupdate = false end,
              numDisplayed        = numDisplayed,
              min                 = 0,
              max                 = 10000,
              step                = 1,
              textColIndex        = nil,
              sliderColIndex      = nil,
              sliderSpan          = nil,
              textColor           = textColor,
            })
          else
            numDisplayed = scp.menuHelper.createButton(wareRowGroup, true, {
              text            = ware.name,
              active          = true,
              mouseOverText   = ReadText(PAGE_ID, 2002),
              buttonText      = ConvertMoneyString(amount, false, true),
              onClick         = function()
                state.selected = state.selected == wareId and nil or wareId
                return menu.refreshInfoFrame()
              end,
              numDisplayed    = numDisplayed,
              textColIndex    = nil,
              buttonColIndex  = nil,
              textColor       = textColor,
              buttonTextColor = amount > 0 and Color["text_positive"] or nil,
              fixed           = nil,
              isHeader        = nil,
            }) or numDisplayed
          end
        end
      end
    end
  end
  return numDisplayed
end

Register_Require_Response("extensions.safe_cheat_panel.ui.scp_inventory", scpInventory)
return scpInventory
