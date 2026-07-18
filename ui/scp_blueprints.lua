local ffi = require("ffi")
local C = ffi.C

ffi.cdef [[
    typedef struct {
        const char* macro;
        const char* ware;
        const char* productionmethodid;
    } UIBlueprint;

    uint32_t GetBlueprints(UIBlueprint* result, uint32_t resultlen, const char* set, const char* category, const char* macroname);
    const char* GetMacroClass(const char* macroname);
    uint32_t GetNumBlueprints(const char* set, const char* category, const char* macroname);
    uint32_t GetNumWares(const char* tags, bool research, const char* licenceownerid, const char* exclusiontags);
    uint32_t GetWares(const char** result, uint32_t resultlen, const char* tags, bool research, const char* licenceownerid, const char* exclusiontags);
    void LearnBlueprint(const char* wareid);
]]

local menu              = Helper.getMenu("MapMenu")
local scpMenuHelper   = require("extensions.safe_cheat_panel.ui.scp_menu_helper")

-- *** Static config ***

local PAGE_ID           = 1972092427

local blueprintOrder    = {
  module = {
    { key = "moduletypes_production" },
    { key = "moduletypes_build" },
    { key = "moduletypes_storage" },
    { key = "moduletypes_habitation" },
    { key = "moduletypes_welfare" },
    { key = "moduletypes_defence" },
    { key = "moduletypes_dock" },
    { key = "moduletypes_processing" },
    { key = "moduletypes_other",     additionalCategories = { "moduletypes_radar" } },
    { key = "moduletypes_venture" },
  },
  ship = {
    { key = "ship_xl" },
    { key = "ship_l" },
    { key = "ship_m" },
    { key = "ship_s" },
  },
}

local categoryNames     = {
  ["moduletypes_production"] = ReadText(1001, 2421),
  ["moduletypes_build"]      = ReadText(1001, 2439),
  ["moduletypes_storage"]    = ReadText(1001, 2422),
  ["moduletypes_habitation"] = ReadText(1001, 2451),
  ["moduletypes_welfare"]    = ReadText(1001, 9620),
  ["moduletypes_defence"]    = ReadText(1001, 2424),
  ["moduletypes_dock"]       = ReadText(1001, 2452),
  ["moduletypes_processing"] = ReadText(1001, 9621),
  ["moduletypes_other"]      = ReadText(1001, 2453),
  ["moduletypes_venture"]    = ReadText(1001, 2454),
  ["ship_xl"]                = ReadText(1001, 11003),
  ["ship_l"]                 = ReadText(1001, 11002),
  ["ship_m"]                 = ReadText(1001, 11001),
  ["ship_s"]                 = ReadText(1001, 11000),
}

local primaryTags       = { "module", "ship", "equipment" }
local primaryTagNames   = { ReadText(1001, 7924), ReadText(1001, 6), ReadText(1001, 7935) }

local equipmentTags     = { "weapon", "turret", "shield", "engine", "thruster", "missile", "drone", "consumables", "countermeasure" }
local equipmentTagNames = {
  ReadText(1001, 1301), ReadText(1001, 1319), ReadText(1001, 1317),
  ReadText(1001, 1103), ReadText(1001, 8001), ReadText(1001, 1304),
  ReadText(1001, 8), ReadText(1001, 8003), ReadText(1001, 8063),
}
local consumableSubTags = { "lasertower", "satellite", "mine", "navbeacon", "resourceprobe" }

-- *** Data loading ***

local function getOwnedBlueprints()
  local num = tonumber(C.GetNumBlueprints("", "", ""))
  if num == 0 then return {} end
  local buf = ffi.new("UIBlueprint[?]", num)
  num = tonumber(C.GetBlueprints(buf, num, "", "", ""))
  local owned = {}
  for i = 0, num - 1 do
    owned[ffi.string(buf[i].ware)] = true
  end
  return owned
end

-- Loads module or ship wares, grouped by infolibrary (modules) or class (ships).
-- Returns a table keyed by group key, each value being a sorted list of { ware, name }.
local function loadGroupedWares(tag)
  local num = tonumber(C.GetNumWares(tag, false, "", "deprecated noplayerblueprint"))
  if num == 0 then return {} end
  local buf = ffi.new("const char*[?]", num)
  num = tonumber(C.GetWares(buf, num, tag, false, "", "deprecated noplayerblueprint"))
  local groups = {}
  for i = 0, num - 1 do
    local ware = ffi.string(buf[i])
    local wareName, macro, hasBlueprint = GetWareData(ware, "name", "component", "hasblueprint")
    if hasBlueprint then
      local groupKey
      local icon = ""
      if tag == "ship" then
        groupKey = ffi.string(C.GetMacroClass(macro))
        local shipIcon = GetMacroData(macro, "icon")
        if shipIcon == nil or shipIcon == "" then
          shipIcon = "mapob_unknown"
        end
        icon = "\027[" .. shipIcon .. "] "
      else
        groupKey = GetMacroData(macro, "infolibrary")
      end
      if groupKey then
        if not groups[groupKey] then
          groups[groupKey] = {}
        end
        table.insert(groups[groupKey], { ware = ware, name = icon .. wareName, sortName = wareName })
      end
    end
  end
  for _, entries in pairs(groups) do
    table.sort(entries, function(a, b) return (a.sortName or a.name) < (b.sortName or b.name) end)
  end
  return groups
end

-- Loads equipment wares for one equipment sub-tag.
-- Returns a sorted flat list of { ware, name }.
local function loadEquipmentWares(equipmentTag)
  local concatTag = equipmentTag
  if equipmentTag == "consumables" then
    concatTag = table.concat(consumableSubTags, " ")
  end
  local num = tonumber(C.GetNumWares(concatTag, false, "", "noplayerblueprint"))
  if num == 0 then return {} end
  local buf = ffi.new("const char*[?]", num)
  num = tonumber(C.GetWares(buf, num, concatTag, false, "", "noplayerblueprint"))
  local entries = {}
  for i = 0, num - 1 do
    local ware = ffi.string(buf[i])
    local wareName, macro = GetWareData(ware, "name", "component")
    local hasInfoAlias = (macro ~= "") and GetMacroData(macro, "hasinfoalias")
    if not hasInfoAlias then
      table.insert(entries, { ware = ware, name = wareName })
    end
  end
  table.sort(entries, Helper.sortName)
  return entries
end

local scpBlueprints = {}

-- Loads all blueprint data: owned map + all module/ship/equipment groups.
function scpBlueprints.loadData()
  local data = {
    owned           = getOwnedBlueprints(),
    moduleGroups    = loadGroupedWares("module"),
    shipGroups      = loadGroupedWares("ship"),
    equipmentGroups = {},
  }
  for _, tag in ipairs(equipmentTags) do
    data.equipmentGroups[tag] = loadEquipmentWares(tag)
  end
  return data
end

-- *** Blueprint scope helpers ***

function scpBlueprints.isAllOwnedForScope(data, primaryTag, secondaryTag)
  local function checkGroup(group)
    if not group then return true end
    for _, entry in ipairs(group) do
      if not data.owned[entry.ware] then return false end
    end
    return true
  end

  if primaryTag == "all" or primaryTag == "module" then
    if primaryTag == "module" and secondaryTag ~= "all" then
      if not checkGroup(data.moduleGroups[secondaryTag]) then return false end
    else
      for _, orderEntry in ipairs(blueprintOrder.module) do
        if not checkGroup(data.moduleGroups[orderEntry.key]) then return false end
        if orderEntry.additionalCategories then
          for _, key in ipairs(orderEntry.additionalCategories) do
            if not checkGroup(data.moduleGroups[key]) then return false end
          end
        end
      end
    end
  end
  if primaryTag == "all" or primaryTag == "ship" then
    if primaryTag == "ship" and secondaryTag ~= "all" then
      if not checkGroup(data.shipGroups[secondaryTag]) then return false end
    else
      for _, orderEntry in ipairs(blueprintOrder.ship) do
        if not checkGroup(data.shipGroups[orderEntry.key]) then return false end
      end
    end
  end
  if primaryTag == "all" or primaryTag == "equipment" then
    local tagsToCheck = (secondaryTag ~= "all") and { secondaryTag } or equipmentTags
    for _, tag in ipairs(tagsToCheck) do
      if not checkGroup(data.equipmentGroups[tag]) then return false end
    end
  end
  return true
end

function scpBlueprints.learnAllVisible(blueprint)
  local data = blueprint.data
  if data == nil then return end

  local function learnGroup(group)
    if not group then return end
    for _, entry in ipairs(group) do
      if not data.owned[entry.ware] then
        C.LearnBlueprint(entry.ware)
      end
    end
  end

  local primaryTag   = blueprint.primaryTag
  local secondaryTag = blueprint.secondaryTag

  if primaryTag == "all" or primaryTag == "module" then
    if primaryTag == "module" and secondaryTag ~= "all" then
      learnGroup(data.moduleGroups[secondaryTag])
    else
      for _, orderEntry in ipairs(blueprintOrder.module) do
        learnGroup(data.moduleGroups[orderEntry.key])
        if orderEntry.additionalCategories then
          for _, key in ipairs(orderEntry.additionalCategories) do
            learnGroup(data.moduleGroups[key])
          end
        end
      end
    end
  end
  if primaryTag == "all" or primaryTag == "ship" then
    if primaryTag == "ship" and secondaryTag ~= "all" then
      learnGroup(data.shipGroups[secondaryTag])
    else
      for _, orderEntry in ipairs(blueprintOrder.ship) do
        learnGroup(data.shipGroups[orderEntry.key])
      end
    end
  end
  if primaryTag == "all" or primaryTag == "equipment" then
    local tagsToLearn = (secondaryTag ~= "all") and { secondaryTag } or equipmentTags
    for _, tag in ipairs(tagsToLearn) do
      learnGroup(data.equipmentGroups[tag])
    end
  end

  blueprint.data = nil
  menu.refreshInfoFrame()
end

-- *** UI rendering helpers ***

-- Column layout (12 total):
--   Col buttonCol  : expand/collapse button (+/-)
--   Cols buttonCol+1 .. 7  : section label (or full width when no unlock button)
--   Cols 6 .. 12 (span 5) : "Unlock All" button or "All Unlocked" text (optional)
-- For entry rows:
--   Cols textStartCol .. 7  : item name
--   Cols 8 .. 12 (span 5)  : "Owned" text or "Unlock" button

-- Returns true if every entry in the list is already owned.
local function isAllOwnedInList(owned, entries)
  for _, e in ipairs(entries) do
    if not owned[e.ware] then return false end
  end
  return true
end

-- Calls LearnBlueprint for every unowned entry in the list.
local function learnGroup(owned, entries)
  if not entries then return end
  for _, e in ipairs(entries) do
    if not owned[e.ware] then C.LearnBlueprint(e.ware) end
  end
end

-- Renders a collapsible section header row.
-- allOwned and onUnlock are optional; when provided, an unlock button (cols 8-12) is added.
local function addExpandRow(frameTable, key, label, buttonCol, isExpanded, onToggle, allOwned, onUnlock)
  local row = frameTable:addRow("expand_" .. key, { bgColor = Color["row_background_unselectable"] })
  local buttonX = 0
  for i = 1, buttonCol - 1 do
    buttonX = buttonX + row[i]:getWidth() + Helper.borderSize
  end
  local buttonWidth = row[buttonCol]:getWidth()
  row[1]:setColSpan(buttonCol):createButton({
    active  = true,
    height  = Helper.scaleY(Helper.standardTextHeight),
    scaling = false,
    x       = buttonX,
    width   = buttonWidth,
  }):setText(isExpanded and "-" or "+", { halign = "center" })
  row[1].handlers.onClick = onToggle
  local textCol = buttonCol + 1
  if onUnlock then
    row[textCol]:setColSpan(7 - buttonCol):createText(label)
    row[8]:setColSpan(5):createButton({ active = not allOwned })
        :setText(allOwned and ReadText(PAGE_ID, 4021) or ReadText(PAGE_ID, 4020), { halign = "center" })
    row[8].handlers.onClick = function()
      if not allOwned then onUnlock() end
    end
  else
    row[textCol]:setColSpan(12 - buttonCol):createText(label)
  end
end

local function addBlueprintEntryRow(frameTable, entry, data, blueprint, textStartCol)
  local isOwned = data.owned[entry.ware]
  local rowId   = isOwned and nil or ("unlock_" .. entry.ware)
  local row     = frameTable:addRow(rowId, { bgColor = Color["row_background_unselectable"] })
  local textX   = Helper.standardTextOffsetx
  for i = 1, textStartCol - 1 do
    textX = textX + row[i]:getWidth() + Helper.borderSize
  end
  if textStartCol > 1 then textX = textX + Helper.borderSize end
  row[1]:setColSpan(7):createText(entry.name, {
    color = isOwned and Color["text_normal"] or Color["text_inactive"], x = textX,
  })
  if isOwned then
    row[8]:setColSpan(5):createText(ReadText(1001, 84), {
      halign = "center",
      color  = Color["text_player"],
    })
  else
    row[8]:setColSpan(5):createButton({ active = true })
        :setText(ReadText(PAGE_ID, 4022), { halign = "center" })
    row[8].handlers.onClick = function()
      C.LearnBlueprint(entry.ware)
      blueprint.data = nil
      menu.refreshInfoFrame()
    end
  end
end

-- Renders all module sub-category sections.
-- expandButtonCol : column index used for the +/- buttons at this level
local function renderModuleSection(frameTable, data, blueprint, expandButtonCol)
  local entryTextStartCol = expandButtonCol + 1
  for _, orderEntry in ipairs(blueprintOrder.module) do
    local group = data.moduleGroups[orderEntry.key]
    local hasEntries = group and #group > 0
    if not hasEntries and orderEntry.additionalCategories then
      for _, key in ipairs(orderEntry.additionalCategories) do
        local addGroup = data.moduleGroups[key]
        if addGroup and #addGroup > 0 then
          hasEntries = true
          break
        end
      end
    end
    if hasEntries then
      local sectionKey = "modsec_" .. orderEntry.key
      local isExpanded = blueprint.expanded[sectionKey]
      -- Collect all entries in this section for allOwned check and unlock callback
      local sectionEntries = {}
      if group then
        for _, e in ipairs(group) do table.insert(sectionEntries, e) end
      end
      if orderEntry.additionalCategories then
        for _, key in ipairs(orderEntry.additionalCategories) do
          local addGroup = data.moduleGroups[key]
          if addGroup then
            for _, e in ipairs(addGroup) do table.insert(sectionEntries, e) end
          end
        end
      end
      local sectionAllOwned = isAllOwnedInList(data.owned, sectionEntries)
      addExpandRow(frameTable, sectionKey,
        categoryNames[orderEntry.key] or orderEntry.key,
        expandButtonCol, isExpanded,
        function()
          blueprint.expanded[sectionKey] = not blueprint.expanded[sectionKey]
          menu.noupdate = false
          menu.refreshInfoFrame()
        end,
        sectionAllOwned,
        function()
          learnGroup(data.owned, sectionEntries)
          blueprint.data = nil
          menu.refreshInfoFrame()
        end)
      if isExpanded then
        if group then
          for _, entry in ipairs(group) do
            addBlueprintEntryRow(frameTable, entry, data, blueprint, entryTextStartCol)
          end
        end
        if orderEntry.additionalCategories then
          for _, key in ipairs(orderEntry.additionalCategories) do
            local addGroup = data.moduleGroups[key]
            if addGroup then
              for _, entry in ipairs(addGroup) do
                addBlueprintEntryRow(frameTable, entry, data, blueprint, entryTextStartCol)
              end
            end
          end
        end
      end
    end
  end
end

-- Renders all ship size-class sections.
local function renderShipSection(frameTable, data, blueprint, expandButtonCol)
  local entryTextStartCol = expandButtonCol + 1
  for _, orderEntry in ipairs(blueprintOrder.ship) do
    local group = data.shipGroups[orderEntry.key]
    if group and #group > 0 then
      local sectionKey = "shipsec_" .. orderEntry.key
      local isExpanded = blueprint.expanded[sectionKey]
      local sectionAllOwned = isAllOwnedInList(data.owned, group)
      addExpandRow(frameTable, sectionKey,
        categoryNames[orderEntry.key] or orderEntry.key,
        expandButtonCol, isExpanded,
        function()
          blueprint.expanded[sectionKey] = not blueprint.expanded[sectionKey]
          menu.noupdate = false
          menu.refreshInfoFrame()
        end,
        sectionAllOwned,
        function()
          learnGroup(data.owned, group)
          blueprint.data = nil
          menu.refreshInfoFrame()
        end)
      if isExpanded then
        for _, entry in ipairs(group) do
          addBlueprintEntryRow(frameTable, entry, data, blueprint, entryTextStartCol)
        end
      end
    end
  end
end

-- Renders the given equipment sub-tags as collapsible sections.
local function renderEquipmentSection(frameTable, data, blueprint, tagsToRender, tagNamesToRender, expandButtonCol)
  local entryTextStartCol = expandButtonCol + 1
  for i, tag in ipairs(tagsToRender) do
    local group = data.equipmentGroups[tag]
    if group and #group > 0 then
      local sectionKey = "equipsec_" .. tag
      local isExpanded = blueprint.expanded[sectionKey]
      local sectionAllOwned = isAllOwnedInList(data.owned, group)
      addExpandRow(frameTable, sectionKey, tagNamesToRender[i], expandButtonCol, isExpanded,
        function()
          blueprint.expanded[sectionKey] = not blueprint.expanded[sectionKey]
          menu.noupdate = false
          menu.refreshInfoFrame()
        end,
        sectionAllOwned,
        function()
          learnGroup(data.owned, group)
          blueprint.data = nil
          menu.refreshInfoFrame()
        end)
      if isExpanded then
        for _, entry in ipairs(group) do
          addBlueprintEntryRow(frameTable, entry, data, blueprint, entryTextStartCol)
        end
      end
    end
  end
end

-- *** Expand/collapse helpers ***

local function getVisibleSectionKeys(blueprint)
  local keys = {}
  local pt = blueprint.primaryTag
  local st = blueprint.secondaryTag
  if pt == "all" then
    table.insert(keys, "primary_module")
    table.insert(keys, "primary_ship")
    table.insert(keys, "primary_equipment")
    for _, e in ipairs(blueprintOrder.module) do table.insert(keys, "modsec_" .. e.key) end
    for _, e in ipairs(blueprintOrder.ship) do table.insert(keys, "shipsec_" .. e.key) end
    for _, t in ipairs(equipmentTags) do table.insert(keys, "equipsec_" .. t) end
  elseif pt == "module" and st == "all" then
    for _, e in ipairs(blueprintOrder.module) do table.insert(keys, "modsec_" .. e.key) end
  elseif pt == "ship" and st == "all" then
    for _, e in ipairs(blueprintOrder.ship) do table.insert(keys, "shipsec_" .. e.key) end
  elseif pt == "equipment" and st == "all" then
    for _, t in ipairs(equipmentTags) do table.insert(keys, "equipsec_" .. t) end
  end
  return keys
end

local function isAnyExpanded(blueprint)
  for _, key in ipairs(getVisibleSectionKeys(blueprint)) do
    if blueprint.expanded[key] then return true end
  end
  return false
end

local function toggleExpandAll(blueprint)
  local keys = getVisibleSectionKeys(blueprint)
  if isAnyExpanded(blueprint) then
    for _, key in ipairs(keys) do blueprint.expanded[key] = nil end
  else
    for _, key in ipairs(keys) do blueprint.expanded[key] = true end
  end
  menu.noupdate = false
  menu.refreshInfoFrame()
end

local function getSecondaryName(blueprint)
  local pt = blueprint.primaryTag
  local st = blueprint.secondaryTag
  if pt == "module" or pt == "ship" then
    return categoryNames[st] or st
  elseif pt == "equipment" then
    for i, tag in ipairs(equipmentTags) do
      if tag == st then return equipmentTagNames[i] end
    end
  end
  return st
end

-- Returns a human-readable label for the current filter selection.
-- Examples: "All", "Ships: All", "Ships: Large"
local function getFilterLabel(blueprint)
  local pt = blueprint.primaryTag
  if pt == "all" then
    return ReadText(PAGE_ID, 4011)
  end
  local primaryName
  for i, tag in ipairs(primaryTags) do
    if tag == pt then
      primaryName = primaryTagNames[i]; break
    end
  end
  local secondaryName = (blueprint.secondaryTag == "all") and ReadText(PAGE_ID, 4011) or getSecondaryName(blueprint)
  return (primaryName or pt) .. ": " .. secondaryName
end

-- *** Main section render ***

function scpBlueprints.createSection(frameTable, numDisplayed, scp)
  -- Match the expand/collapse button column width to the vanilla infotable (e.g. propertyowned).
  -- col 1 = top-level +/- button; col 2 = sub-section +/- button.
  local expandColWidth = Helper.scaleY(Helper.standardTextHeight) + Helper.standardContainerOffset
  frameTable:setColWidth(1, expandColWidth, false)
  frameTable:setColWidth(2, expandColWidth, false)
  local blueprint = scp.blueprint
  local isV9 = scp.isV9

  -- Load blueprint data if not yet cached (or invalidated after learning)
  if blueprint.data == nil then
    blueprint.data = scpBlueprints.loadData()
  end
  local data = blueprint.data

  -- Title (fixed - does not scroll)
  numDisplayed = scpMenuHelper.createTitle(frameTable, numDisplayed, {
    text  = ReadText(PAGE_ID, 4000),
    fixed = true,
  })

  -- Filter dropdowns (fixed - does not scroll)
  local primaryOptions = {
    { id = "all",       text = ReadText(PAGE_ID, 4011), icon = "", displayremoveoption = false },
    { id = "module",    text = primaryTagNames[1],      icon = "", displayremoveoption = false },
    { id = "ship",      text = primaryTagNames[2],      icon = "", displayremoveoption = false },
    { id = "equipment", text = primaryTagNames[3],      icon = "", displayremoveoption = false },
  }

  numDisplayed = scpMenuHelper.createDropDown(frameTable, "blueprint_primary", numDisplayed, {
    active           = true,
    dropDownData     = primaryOptions,
    startOption      = blueprint.primaryTag,
    text             = ReadText(PAGE_ID, 4010),
    textOverride     = "",
    onConfirmed      = function(_, value)
      menu.noupdate                         = false
      blueprint.primaryTag                  = value
      blueprint.secondaryTag                = "all"
      scp.currentRow[scp.tableMode] = nil
      SetTopRow(menu.infoTable, scp.table.numfixedrows + 1)
      menu.refreshInfoFrame()
    end,
    textColIndex     = nil,
    dropDownColIndex = nil,
    dropDownSpan     = nil,
    textColor        = nil,
    fixed            = true,
    isHeader         = true,
  })

  -- Secondary dropdown: shown for module, ship, and equipment
  local secondaryOptions = nil
  if blueprint.primaryTag == "module" then
    secondaryOptions = {
      { id = "all", text = ReadText(PAGE_ID, 4011), icon = "", displayremoveoption = false },
    }
    for _, orderEntry in ipairs(blueprintOrder.module) do
      table.insert(secondaryOptions, {
        id                  = orderEntry.key,
        text                = categoryNames[orderEntry.key] or orderEntry.key,
        icon                = "",
        displayremoveoption = false,
      })
    end
  elseif blueprint.primaryTag == "ship" then
    secondaryOptions = {
      { id = "all", text = ReadText(PAGE_ID, 4011), icon = "", displayremoveoption = false },
    }
    for _, orderEntry in ipairs(blueprintOrder.ship) do
      table.insert(secondaryOptions, {
        id                  = orderEntry.key,
        text                = categoryNames[orderEntry.key] or orderEntry.key,
        icon                = "",
        displayremoveoption = false,
      })
    end
  elseif blueprint.primaryTag == "equipment" then
    secondaryOptions = {
      { id = "all", text = ReadText(PAGE_ID, 4011), icon = "", displayremoveoption = false },
    }
    for i, tag in ipairs(equipmentTags) do
      table.insert(secondaryOptions, {
        id                  = tag,
        text                = equipmentTagNames[i],
        icon                = "",
        displayremoveoption = false,
      })
    end
  end
  if secondaryOptions then
    numDisplayed = scpMenuHelper.createDropDown(frameTable, "blueprint_secondary", numDisplayed, {
      active           = true,
      dropDownData     = secondaryOptions,
      startOption      = blueprint.secondaryTag,
      text             = ReadText(PAGE_ID, 4012),
      textOverride     = "",
      onConfirmed      = function(_, value)
        menu.noupdate = false
        blueprint.secondaryTag = value
        menu.refreshInfoFrame()
      end,
      textColIndex     = nil,
      dropDownColIndex = nil,
      dropDownSpan     = nil,
      textColor        = nil,
      fixed            = true,
      isHeader         = nil,
    })
  end

  -- Expand/collapse + unlock all combined row (fixed - does not scroll)
  local isFlat = (blueprint.primaryTag ~= "all") and (blueprint.secondaryTag ~= "all")
  local allOwned = scpBlueprints.isAllOwnedForScope(data, blueprint.primaryTag, blueprint.secondaryTag)
  local ctrlRow = frameTable:addRow("blueprint_controls", { bgColor = Color["row_background_unselectable"], fixed = true })
  if isFlat then
    ctrlRow[1]:setColSpan(7):createText(getFilterLabel(blueprint))
  else
    ctrlRow[1]:createButton({
      active  = true,
      height  = Helper.scaleY(Helper.standardTextHeight),
      scaling = false,
    }):setText(isAnyExpanded(blueprint) and "-" or "+", { halign = "center" })
    ctrlRow[1].handlers.onClick = function() toggleExpandAll(blueprint) end
    ctrlRow[2]:setColSpan(6):createText(getFilterLabel(blueprint))
  end
  ctrlRow[8]:setColSpan(5):createButton({ active = not allOwned })
      :setText(allOwned and ReadText(PAGE_ID, 4021) or ReadText(PAGE_ID, 4020), { halign = "center" })
  ctrlRow[8].handlers.onClick = function()
    if not allOwned then scpBlueprints.learnAllVisible(blueprint) end
  end
  numDisplayed = numDisplayed + 1

  -- Blueprint list
  local listGroup = isV9 and frameTable:addRowGroup({}) or frameTable

  if blueprint.primaryTag == "all" then
    -- Three top-level expand sections: Modules, Ships, Equipment
    local modKey      = "primary_module"
    local modExpanded = blueprint.expanded[modKey]
    local modAllOwned = scpBlueprints.isAllOwnedForScope(data, "module", "all")
    addExpandRow(listGroup, modKey, primaryTagNames[1], 1, modExpanded,
      function()
        blueprint.expanded[modKey] = not blueprint.expanded[modKey]
        menu.noupdate = false
        menu.refreshInfoFrame()
      end,
      modAllOwned,
      function()
        for _, orderEntry in ipairs(blueprintOrder.module) do
          learnGroup(data.owned, data.moduleGroups[orderEntry.key])
          if orderEntry.additionalCategories then
            for _, key in ipairs(orderEntry.additionalCategories) do
              learnGroup(data.owned, data.moduleGroups[key])
            end
          end
        end
        blueprint.data = nil
        menu.refreshInfoFrame()
      end)
    if modExpanded then
      renderModuleSection(listGroup, data, blueprint, 2)
    end

    local shipKey      = "primary_ship"
    local shipExpanded = blueprint.expanded[shipKey]
    local shipAllOwned = scpBlueprints.isAllOwnedForScope(data, "ship", "all")
    addExpandRow(listGroup, shipKey, primaryTagNames[2], 1, shipExpanded,
      function()
        blueprint.expanded[shipKey] = not blueprint.expanded[shipKey]
        menu.noupdate = false
        menu.refreshInfoFrame()
      end,
      shipAllOwned,
      function()
        for _, orderEntry in ipairs(blueprintOrder.ship) do
          learnGroup(data.owned, data.shipGroups[orderEntry.key])
        end
        blueprint.data = nil
        menu.refreshInfoFrame()
      end)
    if shipExpanded then
      renderShipSection(listGroup, data, blueprint, 2)
    end

    local equipKey      = "primary_equipment"
    local equipExpanded = blueprint.expanded[equipKey]
    local equipAllOwned = scpBlueprints.isAllOwnedForScope(data, "equipment", "all")
    addExpandRow(listGroup, equipKey, primaryTagNames[3], 1, equipExpanded,
      function()
        blueprint.expanded[equipKey] = not blueprint.expanded[equipKey]
        menu.noupdate = false
        menu.refreshInfoFrame()
      end,
      equipAllOwned,
      function()
        for _, tag in ipairs(equipmentTags) do
          learnGroup(data.owned, data.equipmentGroups[tag])
        end
        blueprint.data = nil
        menu.refreshInfoFrame()
      end)
    if equipExpanded then
      renderEquipmentSection(listGroup, data, blueprint, equipmentTags, equipmentTagNames, 2)
    end
  elseif blueprint.primaryTag == "module" then
    if blueprint.secondaryTag == "all" then
      renderModuleSection(listGroup, data, blueprint, 1)
    else
      -- Specific module type selected — show entries flat
      local group = data.moduleGroups[blueprint.secondaryTag]
      if group then
        for _, entry in ipairs(group) do
          addBlueprintEntryRow(listGroup, entry, data, blueprint, 1)
        end
      end
    end
  elseif blueprint.primaryTag == "ship" then
    if blueprint.secondaryTag == "all" then
      renderShipSection(listGroup, data, blueprint, 1)
    else
      -- Specific ship size class selected — show entries flat
      local group = data.shipGroups[blueprint.secondaryTag]
      if group then
        for _, entry in ipairs(group) do
          addBlueprintEntryRow(listGroup, entry, data, blueprint, 1)
        end
      end
    end
  elseif blueprint.primaryTag == "equipment" then
    if blueprint.secondaryTag == "all" then
      renderEquipmentSection(listGroup, data, blueprint, equipmentTags, equipmentTagNames, 1)
    else
      -- Specific secondary tag selected — show entries directly with no section header
      local group = data.equipmentGroups[blueprint.secondaryTag]
      if group then
        for _, entry in ipairs(group) do
          addBlueprintEntryRow(listGroup, entry, data, blueprint, 1)
        end
      end
    end
  end

  return numDisplayed
end

Register_Require_Response("extensions.safe_cheat_panel.ui.scp_blueprints", scpBlueprints)
return scpBlueprints
