local ffi = require("ffi")
local C = ffi.C

local menu = Helper.getMenu("MapMenu")

local scpCargo = {}

function scpCargo.join(scp)
  scpCargo.scp = scp
end

-- *** Wares ***

local wareInfo = {}
local waresByTransport = nil

local function getWareInfo(ware)
  local info = wareInfo[ware]
  if info == nil then
    local name, transport, volume = GetWareData(ware, "name", "transport", "volume")
    info = { name = name or ware, transport = transport, volume = tonumber(volume) or 0 }
    wareInfo[ware] = info
  end
  return info
end

---Wares a hold of one transport type takes: vanilla's ware pickers use `economy`, `recycling` adds the raw scrap.
local function getWaresForTag(tag)
  if waresByTransport == nil then
    waresByTransport = {}
    local seen = {}
    for _, query in ipairs({ "economy", "recycling" }) do
      local n = tonumber(C.GetNumWares(query, false, "", "deprecated"))
      if n > 0 then
        local buf = ffi.new("const char*[?]", n)
        n = tonumber(C.GetWares(buf, n, query, false, "", "deprecated"))
        for i = 0, n - 1 do
          local ware = ffi.string(buf[i])
          local info = getWareInfo(ware)
          if not seen[ware] and info.transport ~= nil and info.volume > 0 then
            seen[ware] = true
            waresByTransport[info.transport] = waresByTransport[info.transport] or {}
            table.insert(waresByTransport[info.transport], ware)
          end
        end
      end
    end
  end
  return waresByTransport[tag] or {}
end

-- *** Storage groups: { name, tags, capacity }, one per independent hold ***

function scpCargo.macroGroups(macro)
  if macro == nil or macro == "" then return {} end
  local library, tags = GetMacroData(macro, "infolibrary", "storagetags")
  local entry = library and GetLibraryEntry(library, macro)
  local capacity = entry and tonumber(entry.storagecapacity) or 0
  if capacity <= 0 or type(tags) ~= "table" or next(tags) == nil then return {} end
  return { { name = nil, tags = tags, capacity = capacity } }
end

function scpCargo.shipGroups(ship)
  local groups = {}
  local n = C.GetNumCargoTransportTypes(ship, true)
  if n == 0 then return groups end
  local buf = ffi.new("StorageInfo[?]", n)
  n = C.GetCargoTransportTypes(buf, n, ship, true, false)
  for i = 0, n - 1 do
    if buf[i].capacity > 0 then
      local tags = {}
      for tag in string.gmatch(ffi.string(buf[i].transport), "%S+") do
        tags[tag] = true
      end
      groups[#groups + 1] = { name = ffi.string(buf[i].name), tags = tags, capacity = buf[i].capacity }
    end
  end
  return groups
end

local function groupOf(groups, ware)
  local transport = getWareInfo(ware).transport
  for _, group in ipairs(groups) do
    if transport ~= nil and group.tags[transport] then return group end
  end
  return nil
end

-- *** State: rows = { { ware, amount } }, initial = ware -> amount on the edited ship, nil for a spawn ***

function scpCargo.newState()
  return { rows = {}, initial = nil }
end

function scpCargo.resetState(state)
  state.rows = {}
  state.initial = nil
end

local function sortRows(rows)
  table.sort(rows, function(a, b) return getWareInfo(a.ware).name < getWareInfo(b.ware).name end)
end

function scpCargo.seed(state, ship)
  state.rows = {}
  state.initial = {}
  local cargo = GetComponentData(ship, "cargo") or {}
  for ware, rawAmount in pairs(cargo) do
    local amount = tonumber(rawAmount) or 0
    if amount > 0 then
      state.initial[ware] = amount
      state.rows[#state.rows + 1] = { ware = ware, amount = amount }
    end
  end
  sortRows(state.rows)
end

---Back to the seeded cargo; a spawn has none.
function scpCargo.revert(state)
  if state.initial == nil then
    state.rows = {}
    return
  end
  state.rows = {}
  for ware, amount in pairs(state.initial) do
    state.rows[#state.rows + 1] = { ware = ware, amount = amount }
  end
  sortRows(state.rows)
end

---The rows whose amount differs from the ship's: { wares, amounts } with absolute targets, or nil.
function scpCargo.getChange(state)
  local wares, amounts = {}, {}
  for _, row in ipairs(state.rows) do
    local before = state.initial and state.initial[row.ware] or 0
    if row.amount ~= before then
      wares[#wares + 1] = row.ware
      amounts[#amounts + 1] = row.amount
    end
  end
  if #wares == 0 then return nil end
  return { wares = wares, amounts = amounts }
end

function scpCargo.hasChanges(state)
  return scpCargo.getChange(state) ~= nil
end

function scpCargo.describe(change)
  if change == nil then return "none" end
  local parts = {}
  for i, ware in ipairs(change.wares) do
    parts[#parts + 1] = ware .. "=" .. tostring(change.amounts[i])
  end
  return table.concat(parts, ", ")
end

---Drops rows the hold cannot take and fits the rest in, earlier rows first. Runs during frame setup.
local function fitRows(state, groups)
  local used = {}
  local kept = {}
  for _, row in ipairs(state.rows) do
    local group = groupOf(groups, row.ware)
    if group ~= nil then
      local volume = getWareInfo(row.ware).volume
      local fits = math.floor((group.capacity - (used[group] or 0)) / volume)
      if row.amount > fits then row.amount = math.max(fits, 0) end
      used[group] = (used[group] or 0) + row.amount * volume
      kept[#kept + 1] = row
    elseif state.initial ~= nil and state.initial[row.ware] ~= nil then
      -- Edited ship's cargo that no hold claims: keep it visible so it can still be set to 0.
      kept[#kept + 1] = row
    end
  end
  state.rows = kept
  return used
end

---getChange after fitting the rows to `groups`: the hull at spawn time may not be the one last rendered.
function scpCargo.getFittedChange(state, groups)
  fitRows(state, groups)
  return scpCargo.getChange(state)
end

-- *** UI ***

local function addWare(state, ware, groups)
  local used = fitRows(state, groups)
  local group = groupOf(groups, ware)
  local amount = 0
  if group ~= nil then
    amount = math.max(math.floor((group.capacity - (used[group] or 0)) / getWareInfo(ware).volume), 0)
  end
  state.rows[#state.rows + 1] = { ware = ware, amount = amount }
  scpCargo.scp.debug("Cargo: added " .. ware .. " at " .. amount)
  menu.refreshInfoFrame()
end

local function addWareOptions(state, groups)
  local listed = {}
  for _, row in ipairs(state.rows) do listed[row.ware] = true end
  local seenTag, options = {}, {}
  for _, group in ipairs(groups) do
    for tag in pairs(group.tags) do
      if not seenTag[tag] then
        seenTag[tag] = true
        for _, ware in ipairs(getWaresForTag(tag)) do
          if not listed[ware] then
            options[#options + 1] = { id = ware, text = getWareInfo(ware).name, icon = "", displayremoveoption = false }
          end
        end
      end
    end
  end
  table.sort(options, function(a, b) return a.text < b.text end)
  return options
end

local function formatVolume(value)
  return ConvertIntegerString(value, true, 0, true)
end

---Cargo section: title, one slider per ware, the add dropdown and the free space per hold.
function scpCargo.addRows(frameTable, numDisplayed, scp, state, groups)
  local isV9 = scp.isV9
  numDisplayed = scp.menuHelper.createTitle(frameTable, numDisplayed, {
    text  = ReadText(1001, 63), -- Cargo
    fixed = nil,
  })
  local rowGroup = isV9 and frameTable:addRowGroup({}) or frameTable

  if #groups == 0 then
    return scp.menuHelper.createDoubleText(rowGroup, nil, numDisplayed, {
      text               = ReadText(1026, 20020), -- This ship does not have any cargo capacity.
      secondText         = "",
      secondTextColIndex = 7,
      textColor          = Color["text_inactive"],
    })
  end

  local used = fitRows(state, groups)
  for index, row in ipairs(state.rows) do
    local info = getWareInfo(row.ware)
    local group = groupOf(groups, row.ware)
    local max = row.amount
    if group ~= nil then
      max = math.floor((group.capacity - (used[group] or 0) + row.amount * info.volume) / info.volume)
    end
    numDisplayed = scp.menuHelper.createSliderRow(rowGroup, "cargo_" .. index, numDisplayed, {
      text                = info.name,
      mouseOverText       = string.format("%s: %s %s", info.name, formatVolume(info.volume), ReadText(1001, 110)),
      startValue          = row.amount,
      onSliderChanged     = function(_, value)
        row.amount = math.floor(value + 0.5)
        scpCargo.scp.trace("Cargo: " .. row.ware .. " slider -> " .. tostring(row.amount))
      end,
      onSliderActivated   = function() menu.noupdate = true end,
      -- Refreshed on release: the other rows' limits and the free space depend on this one.
      onSliderDeactivated = function()
        menu.noupdate = false
        menu.refreshInfoFrame()
      end,
      onSliderConfirm     = function() menu.refreshInfoFrame() end,
      min                 = 0,
      max                 = math.max(max, 1),
      step                = 1,
      readOnly            = max == 0,
      sliderColIndex      = 7,
      textColor           = (row.amount > 0) and Color["text_normal"] or Color["text_inactive"],
    })
  end

  local options = addWareOptions(state, groups)
  numDisplayed = scp.menuHelper.createDropDown(rowGroup, true, numDisplayed, {
    active           = #options > 0,
    dropDownData     = options,
    startOption      = "",
    text             = nil,
    textOverride     = ReadText(1001, 3278), -- Add new ware
    onConfirmed      = function(_, id) addWare(state, id, groups) end,
    textColIndex     = 1,
    dropDownColIndex = 1,
    dropDownSpan     = 12,
    textColor        = nil,
    fixed            = nil,
    isHeader         = nil,
  })

  for _, group in ipairs(groups) do
    local label = ReadText(1001, 2911) -- Cargo free
    if #groups > 1 and group.name ~= nil then
      label = group.name .. " - " .. label
    end
    numDisplayed = scp.menuHelper.createDoubleText(rowGroup, nil, numDisplayed, {
      text               = label,
      secondText         = string.format("%s / %s %s", formatVolume(group.capacity - (used[group] or 0)), formatVolume(group.capacity), ReadText(1001, 110)),
      secondTextColIndex = 7,
    })
  end
  return numDisplayed
end

Register_Require_Response("extensions.safe_cheat_panel.ui.scp_cargo", scpCargo)
return scpCargo
