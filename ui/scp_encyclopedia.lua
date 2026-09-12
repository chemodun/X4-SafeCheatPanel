local ffi = require("ffi")
local C = ffi.C

ffi.cdef [[
    typedef uint64_t UniverseID;

    typedef struct {
        const char* id;
        const char* name;
        const char* shortname;
        const char* description;
        const char* icon;
    } RaceInfo;

    uint32_t GetAllFactions(const char** result, uint32_t resultlen, bool includehidden);
    uint32_t GetAllFactionStations(UniverseID* result, uint32_t resultlen, const char* factionid);
    uint32_t GetAllRaces(RaceInfo* result, uint32_t resultlen);
    uint32_t GetFixedStations(UniverseID* result, uint32_t resultlen, UniverseID spaceid);
    uint32_t GetNumAllFactions(bool includehidden);
    uint32_t GetNumAllFactionStations(const char* factionid);
    uint32_t GetNumAllRaces(void);
    uint32_t GetNumFixedStations(UniverseID spaceid);
    uint32_t GetNumWares(const char* tags, bool research, const char* licenceownerid, const char* exclusiontags);
    uint32_t GetWares(const char** result, uint32_t resultlen, const char* tags, bool research, const char* licenceownerid, const char* exclusiontags);
]]

local menu           = Helper.getMenu("MapMenu")

-- *** Static config ***

local PAGE_ID        = 1972092427

-- Groups, libraries and their order mirror the vanilla encyclopedia index (menu_encyclopedia.lua).
local primaryTags    = { "race", "faction", "ship", "station", "module", "weapon", "equipment", "ware" }
local primaryNames   = {
  ReadText(1001, 99),   -- Races
  ReadText(1001, 44),   -- Factions
  ReadText(1001, 6),    -- Ships
  ReadText(1001, 4),    -- Stations
  ReadText(1001, 9610), -- Station Modules
  ReadText(1001, 2417), -- Military
  ReadText(1001, 7935), -- Equipment
  ReadText(1001, 46),   -- Wares
}

local libraryOrder   = {
  race      = { "races" },
  faction   = { "factions", "licences" },
  ship      = { "shiptypes_xl", "shiptypes_l", "shiptypes_m", "shiptypes_s", "shiptypes_xs" },
  station   = { "stationtypes" },
  module    = {
    "moduletypes_production", "moduletypes_build", "moduletypes_storage", "moduletypes_habitation",
    "moduletypes_welfare", "moduletypes_defence", "moduletypes_dock", "moduletypes_processing",
    "moduletypes_other", "moduletypes_venture",
  },
  weapon    = {
    "weapons_lasers", "weapons_missilelaunchers", "weapons_turrets", "weapons_missileturrets",
    "missiletypes", "mines", "bombs",
  },
  equipment = {
    "enginetypes", "thrustertypes", "shieldgentypes", "satellites", "navbeacons",
    "resourceprobes", "lasertowers", "software", "paintmods",
  },
  ware      = { "wares", "inventory_wares" },
}

local libraryNames   = {
  ["races"]                    = ReadText(1001, 99),
  ["factions"]                 = ReadText(1001, 44),
  ["licences"]                 = ReadText(1001, 62),
  ["shiptypes_xl"]             = ReadText(1001, 11003),
  ["shiptypes_l"]              = ReadText(1001, 11002),
  ["shiptypes_m"]              = ReadText(1001, 11001),
  ["shiptypes_s"]              = ReadText(1001, 11000),
  ["shiptypes_xs"]             = ReadText(1001, 8), -- Drones: what the XS class actually holds; vanilla has no XS size label
  ["stationtypes"]             = ReadText(1001, 4),
  ["moduletypes_production"]   = ReadText(1001, 2421),
  ["moduletypes_build"]        = ReadText(1001, 2439),
  ["moduletypes_storage"]      = ReadText(1001, 2422),
  ["moduletypes_habitation"]   = ReadText(1001, 2451),
  ["moduletypes_welfare"]      = ReadText(1001, 9620),
  ["moduletypes_defence"]      = ReadText(1001, 2424),
  ["moduletypes_dock"]         = ReadText(1001, 2452),
  ["moduletypes_processing"]   = ReadText(1001, 9621),
  ["moduletypes_other"]        = ReadText(1001, 2453),
  ["moduletypes_venture"]      = ReadText(1001, 2454),
  ["weapons_lasers"]           = ReadText(1001, 1301),
  ["weapons_missilelaunchers"] = ReadText(1001, 9030),
  ["weapons_turrets"]          = ReadText(1001, 1319),
  ["weapons_missileturrets"]   = ReadText(1001, 9031),
  ["missiletypes"]             = ReadText(1001, 1304),
  ["mines"]                    = ReadText(1001, 1326),
  ["bombs"]                    = ReadText(1001, 1330),
  ["enginetypes"]              = ReadText(1001, 1103),
  ["thrustertypes"]            = ReadText(1001, 8001),
  ["shieldgentypes"]           = ReadText(1001, 1317),
  ["satellites"]               = ReadText(1001, 1327),
  ["navbeacons"]               = ReadText(1001, 1328),
  ["resourceprobes"]           = ReadText(1001, 1329),
  ["lasertowers"]              = ReadText(1001, 1333),
  ["software"]                 = ReadText(1001, 87),
  ["paintmods"]                = ReadText(1001, 8510),
  ["wares"]                    = ReadText(1001, 46),
  ["inventory_wares"]          = ReadText(1001, 2434),
}

-- Nothing at runtime reports race tags; in races.xml only the hidden race has an empty shortname
-- (its missing icon is no use, the engine substitutes one). The list overrides that test.
local hiddenRaces    = { ["drone"] = true }

-- Vanilla folds the radar modules into "other" as an additional category of the same section.
local libraryAliases = { ["moduletypes_radar"] = "moduletypes_other" }

-- Wares carrying a component macro: the macro is the item, and its own infolibrary is the bucket.
local macroTags      =
"ship drone module weapon turret missilelauncher missile mine bomb engine thruster shield satellite navbeacon resourceprobe lasertower"

-- The rest are addressed by ware id; paintmods are their own library, not part of inventory.
local wareSources    = {
  { tags = "economy",   library = "wares",           exclude = "deprecated" },
  { tags = "inventory", library = "inventory_wares", exclude = "deprecated paintmod" },
  { tags = "software",  library = "software",        exclude = "deprecated" },
  { tags = "paintmod",  library = "paintmods",       exclude = "deprecated" },
}

local presentedLibraries = {}
for _, tag in ipairs(primaryTags) do
  for _, library in ipairs(libraryOrder[tag]) do
    presentedLibraries[library] = true
  end
end

-- *** Data loading ***

local function getWares(tags, exclusionTags)
  local num = tonumber(C.GetNumWares(tags, false, "", exclusionTags))
  if num == 0 then return {} end
  local buf = ffi.new("const char*[?]", num)
  num = tonumber(C.GetWares(buf, num, tags, false, "", exclusionTags))
  local list = {}
  for i = 0, num - 1 do
    list[#list + 1] = ffi.string(buf[i])
  end
  return list
end

-- Hidden factions included: the landmark stations are mostly ownerless, itself a hidden faction.
local function getAllFactionIds()
  local ids, seen = {}, {}
  local num = tonumber(C.GetNumAllFactions(true))
  if num > 0 then
    local buf = ffi.new("const char*[?]", num)
    num = tonumber(C.GetAllFactions(buf, num, true))
    for i = 0, num - 1 do
      local faction = ffi.string(buf[i])
      seen[faction] = true
      ids[#ids + 1] = faction
    end
  end
  if not seen["ownerless"] then ids[#ids + 1] = "ownerless" end
  return ids
end

-- The catalogue bucketed by info library, static for the session; known state is read live.
local function loadData(scp)
  local libraries = {}
  local seen = {}

  -- macros: the further library items this row also stands for, see the station block.
  local function add(library, id, name, icon, component, macros)
    library = libraryAliases[library] or library
    if not presentedLibraries[library] then return end
    local key = library .. "/" .. id
    if seen[key] then return end
    seen[key] = true
    if name == nil or name == "" then name = id end
    libraries[library] = libraries[library] or {}
    table.insert(libraries[library], {
      library   = library,
      id        = id,
      name      = (icon and icon ~= "") and ("\27[" .. icon .. "] " .. name) or name,
      sortName  = name,
      component = component,
      macros    = macros,
    })
  end

  for _, ware in ipairs(getWares(macroTags, "deprecated")) do
    local macro, name = GetWareData(ware, "component", "name")
    if macro and macro ~= "" then
      local hasInfoAlias, library, icon = GetMacroData(macro, "hasinfoalias", "infolibrary", "icon")
      -- An aliased macro is a duplicate of the entry it aliases.
      if not hasInfoAlias and library and library ~= "" then
        add(library, macro, name, (library:sub(1, 10) == "shiptypes_") and icon or nil)
      end
    end
  end

  for _, source in ipairs(wareSources) do
    for _, ware in ipairs(getWares(source.tags, source.exclude)) do
      add(source.library, ware, GetWareData(ware, "name"))
    end
  end

  local numRaces = tonumber(C.GetNumAllRaces())
  if numRaces > 0 then
    local raceBuf = ffi.new("RaceInfo[?]", numRaces)
    numRaces = tonumber(C.GetAllRaces(raceBuf, numRaces))
    -- "<id>(list)" marks a race only the list caught: hidden, but with a shortname.
    local hidden = {}
    for i = 0, numRaces - 1 do
      local race = ffi.string(raceBuf[i].id)
      local icon = ffi.string(raceBuf[i].icon)
      local shortname = ffi.string(raceBuf[i].shortname)
      local isHidden = (shortname == "")
      scp.trace(string.format("Encyclopedia: RaceInfo[%d]: id=[%s] name=[%s] shortname=[%s] icon=[%s] isHidden=[%s]",
        i, race, ffi.string(raceBuf[i].name), shortname, icon, isHidden))
      if isHidden or hiddenRaces[race] then
        hidden[#hidden + 1] = isHidden and race or (race .. "(list)")
      else
        add("races", race, ffi.string(raceBuf[i].name), icon)
      end
    end
    scp.trace("Encyclopedia: hidden races: " .. ((#hidden > 0) and table.concat(hidden, " ") or "none"))
  end

  -- includehidden = false as every vanilla listing does; the player faction has no entry.
  local numFactions = tonumber(C.GetNumAllFactions(false))
  if numFactions > 0 then
    local factionBuf = ffi.new("const char*[?]", numFactions)
    numFactions = tonumber(C.GetAllFactions(factionBuf, numFactions, false))
    for i = 0, numFactions - 1 do
      local faction = ffi.string(factionBuf[i])
      if faction ~= "player" then
        local name, icon = GetFactionData(faction, "name", "icon")
        add("factions", faction, name, icon)
        -- Vanilla auto-adds a known faction's own licences (menu_encyclopedia.lua:560).
        for _, licence in ipairs(GetOwnLicences(faction) or {}) do
          add("licences", licence.id, licence.name)
        end
      end
    end
  end

  -- Stations are components, not library items: those flagged encyclopedia="true" in god.xml or
  -- create_station, listed once known (menu_encyclopedia.lua:578-586). spaceid 0 is the universe.
  local numStations = tonumber(C.GetNumFixedStations(0))
  if numStations > 0 then
    local stationBuf = ffi.new("UniverseID[?]", numStations)
    numStations = tonumber(C.GetFixedStations(stationBuf, numStations, 0))
    for i = 0, numStations - 1 do
      -- The raw id string is the key; the converted number is not stable.
      local idString = tostring(stationBuf[i])
      local component = ConvertStringTo64Bit(idString)
      add("stationtypes", idString, GetComponentData(component, "name"), nil, component)
    end
  end

  -- The category also renders isfixedstation macros (menu_encyclopedia.lua:572-577). GetLibrary
  -- holds only known ones and no catalogue exists, so the rest come from a universe sweep.
  local fixedMacros = {}
  for _, entry in ipairs(GetLibrary("stationtypes") or {}) do
    if GetMacroData(entry.id, "isfixedstation") then fixedMacros[entry.id] = true end
  end
  local seenMacro = {}
  for _, faction in ipairs(getAllFactionIds()) do
    local numOwned = tonumber(C.GetNumAllFactionStations(faction))
    if numOwned > 0 then
      local ownedBuf = ffi.new("UniverseID[?]", numOwned)
      numOwned = tonumber(C.GetAllFactionStations(ownedBuf, numOwned, faction))
      for i = 0, numOwned - 1 do
        local macro = GetComponentData(ConvertStringTo64Bit(tostring(ownedBuf[i])), "macro")
        if macro and macro ~= "" and not seenMacro[macro] then
          seenMacro[macro] = true
          if GetMacroData(macro, "isfixedstation") then fixedMacros[macro] = true end
        end
      end
    end
  end

  -- Several macros share one name; vanilla collapses them into one row that reveals them all.
  local macrosByName = {}
  local numMacros, numGroups = 0, 0
  for macro in pairs(fixedMacros) do
    local name = GetMacroData(macro, "name")
    if name == nil or name == "" then name = macro end
    numMacros = numMacros + 1
    if macrosByName[name] then
      table.insert(macrosByName[name], macro)
    else
      macrosByName[name] = { macro }
      numGroups = numGroups + 1
    end
  end
  for name, macros in pairs(macrosByName) do
    table.sort(macros)
    add("stationtypes", macros[1], name, nil, nil, macros)
  end
  scp.trace(string.format("Encyclopedia: %d fixed stations, %d fixed-station macros in %d rows",
    numStations, numMacros, numGroups))

  for _, entries in pairs(libraries) do
    table.sort(entries, function(a, b) return a.sortName < b.sortName end)
  end
  return libraries
end

-- *** Scope helpers ***

-- A station entry is a component: only MD's set_known reveals it, not AddKnownItem.
local function isEntryKnown(entry)
  if entry.component then
    return GetComponentData(entry.component, "isknown")
  end
  if entry.macros then
    for _, macro in ipairs(entry.macros) do
      if not IsKnownItem(entry.library, macro) then return false end
    end
    return true
  end
  return IsKnownItem(entry.library, entry.id)
end

local function isAllKnown(entries)
  for _, entry in ipairs(entries) do
    if not isEntryKnown(entry) then return false end
  end
  return true
end

local function revealEntries(entries)
  local components
  for _, entry in ipairs(entries) do
    if not isEntryKnown(entry) then
      if entry.component then
        components = components or {}
        components[#components + 1] = entry.component
      elseif entry.macros then
        for _, macro in ipairs(entry.macros) do AddKnownItem(entry.library, macro) end
      else
        AddKnownItem(entry.library, entry.id)
      end
    end
  end
  if components then
    -- MD answers with scp_main.sectorRevealed, which the main module refreshes the frame on.
    menu.noupdate = true
    AddUITriggeredEvent("scp_main", "scp_reveal_path", components)
  else
    menu.refreshInfoFrame()
  end
end

-- A single-library group is its own section, so it needs no section header.
local function isSingleLibrary(primaryTag)
  return #libraryOrder[primaryTag] == 1
end

local function collectPrimary(data, primaryTag)
  local entries = {}
  for _, library in ipairs(libraryOrder[primaryTag]) do
    for _, entry in ipairs(data[library] or {}) do
      entries[#entries + 1] = entry
    end
  end
  return entries
end

local function collectScope(data, primaryTag, secondaryTag)
  if primaryTag == "all" then
    local entries = {}
    for _, tag in ipairs(primaryTags) do
      for _, entry in ipairs(collectPrimary(data, tag)) do
        entries[#entries + 1] = entry
      end
    end
    return entries
  elseif secondaryTag == "all" then
    return collectPrimary(data, primaryTag)
  end
  return data[secondaryTag] or {}
end

-- *** UI rendering helpers ***

-- 12 columns: the +/- button up to buttonCol, the label to col 7, cols 8-12 the reveal button
-- or the revealed marker. Entry rows indent by starting their text at textStartCol.
local function addExpandRow(frameTable, key, label, buttonCol, isExpanded, onToggle, allKnown, onReveal)
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
  if onReveal then
    row[textCol]:setColSpan(7 - buttonCol):createText(label)
    row[8]:setColSpan(5):createButton({ active = not allKnown })
        :setText(allKnown and ReadText(PAGE_ID, 10021) or ReadText(PAGE_ID, 10020), { halign = "center" })
    row[8].handlers.onClick = function()
      if not allKnown then onReveal() end
    end
  else
    row[textCol]:setColSpan(12 - buttonCol):createText(label)
  end
end

local function addEntryRow(frameTable, entry, textStartCol)
  local isKnown = isEntryKnown(entry)
  local rowId   = isKnown and nil or ("reveal_" .. entry.library .. "_" .. entry.id)
  local row     = frameTable:addRow(rowId, { bgColor = Color["row_background_unselectable"] })
  local textX   = Helper.standardTextOffsetx
  for i = 1, textStartCol - 1 do
    textX = textX + row[i]:getWidth() + Helper.borderSize
  end
  if textStartCol > 1 then textX = textX + Helper.borderSize end
  row[1]:setColSpan(7):createText(entry.name, {
    color = isKnown and Color["text_normal"] or Color["text_inactive"], x = textX,
  })
  if isKnown then
    row[8]:setColSpan(5):createText(ReadText(PAGE_ID, 10023), {
      halign = "center",
      color  = Color["text_player"],
    })
  else
    row[8]:setColSpan(5):createButton({ active = true })
        :setText(ReadText(PAGE_ID, 10022), { halign = "center" })
    row[8].handlers.onClick = function() revealEntries({ entry }) end
  end
end

-- expandButtonCol is the +/- column for this nesting level; entries indent one past it.
local function renderLibrarySections(frameTable, data, state, primaryTag, expandButtonCol)
  local entryTextStartCol = expandButtonCol + 1
  for _, library in ipairs(libraryOrder[primaryTag]) do
    local entries = data[library]
    if entries and #entries > 0 then
      local sectionKey = "encsec_" .. library
      local isExpanded = state.expanded[sectionKey]
      addExpandRow(frameTable, sectionKey, libraryNames[library] or library,
        expandButtonCol, isExpanded,
        function()
          state.expanded[sectionKey] = not state.expanded[sectionKey]
          menu.noupdate = false
          menu.refreshInfoFrame()
        end,
        isAllKnown(entries),
        function() revealEntries(entries) end)
      if isExpanded then
        for _, entry in ipairs(entries) do
          addEntryRow(frameTable, entry, entryTextStartCol)
        end
      end
    end
  end
end

-- *** Expand/collapse helpers ***

local function getVisibleSectionKeys(state)
  local keys = {}
  local pt = state.primaryTag
  if pt == "all" then
    for _, tag in ipairs(primaryTags) do
      table.insert(keys, "primary_" .. tag)
      if not isSingleLibrary(tag) then
        for _, library in ipairs(libraryOrder[tag]) do table.insert(keys, "encsec_" .. library) end
      end
    end
  elseif (state.secondaryTag == "all") and not isSingleLibrary(pt) then
    for _, library in ipairs(libraryOrder[pt]) do table.insert(keys, "encsec_" .. library) end
  end
  return keys
end

local function isAnyExpanded(state)
  for _, key in ipairs(getVisibleSectionKeys(state)) do
    if state.expanded[key] then return true end
  end
  return false
end

local function toggleExpandAll(state)
  local keys = getVisibleSectionKeys(state)
  if isAnyExpanded(state) then
    for _, key in ipairs(keys) do state.expanded[key] = nil end
  else
    for _, key in ipairs(keys) do state.expanded[key] = true end
  end
  menu.noupdate = false
  menu.refreshInfoFrame()
end

local function getFilterLabel(state)
  local pt = state.primaryTag
  if pt == "all" then
    return ReadText(PAGE_ID, 10011)
  end
  local primaryName = pt
  for i, tag in ipairs(primaryTags) do
    if tag == pt then
      primaryName = primaryNames[i]
      break
    end
  end
  local secondaryName = (state.secondaryTag == "all") and ReadText(PAGE_ID, 10011)
      or (libraryNames[state.secondaryTag] or state.secondaryTag)
  return primaryName .. ": " .. secondaryName
end

-- *** Main section render ***

local scpEncyclopedia = {
  state = {
    primaryTag   = "all",
    secondaryTag = "all",
    expanded     = {},
    data         = nil,
  },
}

function scpEncyclopedia.createSection(frameTable, numDisplayed, scp)
  -- Cols 1 and 2 hold the top-level and sub-section +/- buttons, sized like the vanilla infotable.
  local expandColWidth = Helper.scaleY(Helper.standardTextHeight) + Helper.standardContainerOffset
  frameTable:setColWidth(1, expandColWidth, false)
  frameTable:setColWidth(2, expandColWidth, false)
  local state = scpEncyclopedia.state
  local isV9 = scp.isV9

  if state.data == nil then
    state.data = loadData(scp)
  end
  local data = state.data

  -- fixed = true keeps a row out of the scrolling area.
  numDisplayed = scp.menuHelper.createTitle(frameTable, numDisplayed, {
    text  = ReadText(PAGE_ID, 10000),
    fixed = true,
  })

  local primaryOptions = {
    { id = "all", text = ReadText(PAGE_ID, 10011), icon = "", displayremoveoption = false },
  }
  for i, tag in ipairs(primaryTags) do
    table.insert(primaryOptions, { id = tag, text = primaryNames[i], icon = "", displayremoveoption = false })
  end

  numDisplayed = scp.menuHelper.createDropDown(frameTable, "encyclopedia_primary", numDisplayed, {
    active           = true,
    dropDownData     = primaryOptions,
    startOption      = state.primaryTag,
    text             = ReadText(PAGE_ID, 10010),
    textOverride     = "",
    onConfirmed      = function(_, value)
      menu.noupdate                 = false
      state.primaryTag              = value
      state.secondaryTag            = "all"
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

  if (state.primaryTag ~= "all") and not isSingleLibrary(state.primaryTag) then
    local secondaryOptions = {
      { id = "all", text = ReadText(PAGE_ID, 10011), icon = "", displayremoveoption = false },
    }
    for _, library in ipairs(libraryOrder[state.primaryTag]) do
      table.insert(secondaryOptions, {
        id                  = library,
        text                = libraryNames[library] or library,
        icon                = "",
        displayremoveoption = false,
      })
    end
    numDisplayed = scp.menuHelper.createDropDown(frameTable, "encyclopedia_secondary", numDisplayed, {
      active           = true,
      dropDownData     = secondaryOptions,
      startOption      = state.secondaryTag,
      text             = ReadText(PAGE_ID, 10012),
      textOverride     = "",
      onConfirmed      = function(_, value)
        menu.noupdate      = false
        state.secondaryTag = value
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

  -- A fully narrowed filter has nothing left to expand.
  local isFlat = (state.primaryTag ~= "all")
      and ((state.secondaryTag ~= "all") or isSingleLibrary(state.primaryTag))
  local scopeEntries = collectScope(data, state.primaryTag, state.secondaryTag)
  local allKnown = isAllKnown(scopeEntries)
  local ctrlRow = frameTable:addRow("encyclopedia_controls", { bgColor = Color["row_background_unselectable"], fixed = true })
  if isFlat then
    ctrlRow[1]:setColSpan(7):createText(getFilterLabel(state))
  else
    ctrlRow[1]:createButton({
      active  = true,
      height  = Helper.scaleY(Helper.standardTextHeight),
      scaling = false,
    }):setText(isAnyExpanded(state) and "-" or "+", { halign = "center" })
    ctrlRow[1].handlers.onClick = function() toggleExpandAll(state) end
    ctrlRow[2]:setColSpan(6):createText(getFilterLabel(state))
  end
  ctrlRow[8]:setColSpan(5):createButton({ active = not allKnown })
      :setText(allKnown and ReadText(PAGE_ID, 10021) or ReadText(PAGE_ID, 10020), { halign = "center" })
  ctrlRow[8].handlers.onClick = function()
    if not allKnown then revealEntries(scopeEntries) end
  end
  numDisplayed = numDisplayed + 1

  local listGroup = isV9 and frameTable:addRowGroup({}) or frameTable

  if state.primaryTag == "all" then
    for i, tag in ipairs(primaryTags) do
      local groupEntries = collectPrimary(data, tag)
      if #groupEntries > 0 then
        local groupKey = "primary_" .. tag
        local isExpanded = state.expanded[groupKey]
        addExpandRow(listGroup, groupKey, primaryNames[i], 1, isExpanded,
          function()
            state.expanded[groupKey] = not state.expanded[groupKey]
            menu.noupdate = false
            menu.refreshInfoFrame()
          end,
          isAllKnown(groupEntries),
          function() revealEntries(groupEntries) end)
        if isExpanded then
          if isSingleLibrary(tag) then
            for _, entry in ipairs(groupEntries) do
              addEntryRow(listGroup, entry, 2)
            end
          else
            renderLibrarySections(listGroup, data, state, tag, 2)
          end
        end
      end
    end
  elseif (state.secondaryTag == "all") and not isSingleLibrary(state.primaryTag) then
    renderLibrarySections(listGroup, data, state, state.primaryTag, 1)
  else
    for _, entry in ipairs(scopeEntries) do
      addEntryRow(listGroup, entry, 1)
    end
  end

  return numDisplayed
end

Register_Require_Response("extensions.safe_cheat_panel.ui.scp_encyclopedia", scpEncyclopedia)
return scpEncyclopedia
