local ffi = require("ffi")
local C = ffi.C

ffi.cdef [[
	typedef uint64_t UniverseID;
	uint32_t GetNumSectorsByOwner(const char* factionid);
	uint32_t GetSectorsByOwner(UniverseID* result, uint32_t resultlen, const char* factionid);
]]

local menu = Helper.getMenu("MapMenu")

local PAGE_ID = 1972092427

local scpMap = {
  sectors = {},
  superHighways = nil,
}

local cache = {}

function scpMap.createSection(frameTable, numDisplayed, scp)
  -- scpMap.sectors and .superHighways come from MD through the blackboard, see requestSectors.
  local sectors = {}

  -- True when the sector still has an active gate or highway the player has not discovered.
  local function hasUnknownGates(sectorLuaId)
    local gates = GetGates(sectorLuaId)
    for _, gateId in ipairs(gates) do
      local gate64 = ConvertStringTo64Bit(tostring(gateId))
      if gate64 and gate64 ~= 0 then
        local isactive, destination, gateKnown = GetComponentData(gate64, "isactive", "destination", "isknown")
        if isactive and not gateKnown then
          return true
        end
        if isactive and destination then
          local dest64 = ConvertStringTo64Bit(tostring(destination))
          if dest64 and dest64 ~= 0 then
            local destKnown = GetComponentData(dest64, "isknown")
            if not destKnown then
              return true
            end
          end
        end
      end
    end
    local highways = scpMap.superHighways[tostring(sectorLuaId)]
    for _, highway in ipairs(highways or {}) do
      local entryGateKnown = GetComponentData(highway.entryGate, "isknown")
      local exitGateKnown = GetComponentData(highway.exitGate, "isknown")
      if not entryGateKnown or not exitGateKnown then
        return true
      end
    end
    return false
  end

  local function revealGates(sectorLuaId, listToReveal)
    if not listToReveal then listToReveal = {} end
    local gates = GetGates(sectorLuaId)
    for _, gateId in ipairs(gates) do
      local gate64 = ConvertStringTo64Bit(tostring(gateId))
      if gate64 and gate64 ~= 0 then
        local isactive, destination, gateKnown = GetComponentData(gate64, "isactive", "destination", "isknown")
        if isactive and not gateKnown then
          listToReveal[#listToReveal + 1] = gate64
        end
        if isactive and destination then
          local dest64 = ConvertStringTo64Bit(tostring(destination))
          if dest64 and dest64 ~= 0 then
            local destKnown = GetComponentData(dest64, "isknown")
            if not destKnown then
              listToReveal[#listToReveal + 1] = dest64
            end
          end
        end
      end
    end
    for _, highway in ipairs(scpMap.superHighways[tostring(sectorLuaId)] or {}) do
      if not GetComponentData(highway.entryGate, "isknown") then
        listToReveal[#listToReveal + 1] = highway.entryGate
      end
      if not GetComponentData(highway.exitGate, "isknown") then
        listToReveal[#listToReveal + 1] = highway.exitGate
      end
      if not GetComponentData(highway.highway, "isknown") then
        listToReveal[#listToReveal + 1] = highway.highway
      end
    end
    return listToReveal
  end

  local isAllRevealed = true
  local isUnknownGates = false
  for i = 1, #scpMap.sectors do
    local sectorId = scpMap.sectors[i]
    if sectorId then
      local isknown, macro, cluster, owner = GetComponentData(sectorId, "isknown", "macro", "cluster", "owner")
      if macro ~= nil and macro ~= "" --[[ and macro ~= "cluster_black2_sector01_macro" ]] then
        local name = GetMacroData(macro, "name")
        local sectorHasUnknownGates = hasUnknownGates(sectorId)
        sectors[#sectors + 1] = { id = sectorId, name = name or key, isknown = isknown, factionId = owner, cluster = cluster, macro = macro, hasUnknownGates = sectorHasUnknownGates }
        if not isknown then
          isAllRevealed = false
        end
        if sectorHasUnknownGates then
          isUnknownGates = true
        end
      end
    end
  end
  table.sort(sectors, Helper.sortName)

  numDisplayed = scp.menuHelper.createTitle(frameTable, numDisplayed, {
    text  = ReadText(1001, 9181),
    fixed = true,
  })

  if isAllRevealed then
    if isUnknownGates then
      numDisplayed = scp.menuHelper.createButton(frameTable, "map_reveal_all", numDisplayed, {
        text            = ReadText(1001, 2809),
        active          = isUnknownGates,
        mouseOverText   = "",
        buttonText      = ReadText(PAGE_ID, 6007),
        onClick         = function()
          local gates = {}
          for _, sector in ipairs(sectors) do
            revealGates(sector.id, gates)
          end
          if gates and #gates > 0 then
            menu.noupdate = true
            AddUITriggeredEvent("scp_main", "scp_reveal_path", gates)
          end
        end,
        textColIndex    = nil,
        buttonColIndex  = nil,
        textColor       = nil,
        buttonTextColor = nil,
        fixed           = true,
        isHeader        = true,
      })
    else
        numDisplayed = scp.menuHelper.createDoubleText(frameTable, false, numDisplayed, {
        text               = ReadText(1001, 2809),
        mouseOverText      = "",
        secondText         = ReadText(1001, 12),
        textColIndex       = nil,
        secondTextColIndex = nil,
        textColor          = nil,
        secondTextColor    = Color["text_positive"],
        fixed              = true,
        isHeader           = true,
        })
    end
  else
    numDisplayed = scp.menuHelper.createButton(frameTable, "map_reveal_all", numDisplayed, {
      text            = ReadText(1001, 2809),
      active          = true,
      mouseOverText   = "",
      buttonText      = ReadText(PAGE_ID, 6002),
      onClick         = function()
        menu.noupdate = true
        local unknownMacros = {}
        for _, sector in ipairs(sectors) do
          if not sector.isknown then
            unknownMacros[#unknownMacros + 1] = sector.macro
          end
        end
        AddUITriggeredEvent("scp_main", "scp_reveal_sector", unknownMacros)
      end,
      textColIndex    = nil,
      buttonColIndex  = nil,
      textColor       = nil,
      buttonTextColor = nil,
      fixed           = true,
      isHeader        = true,
    })
  end

  -- True when the sector connects to somewhere already known, or has no connections at all.
  local function hasKnownPath(sectorLuaId)
    local gates = GetGates(sectorLuaId)
    for _, gateId in ipairs(gates) do
      local gate64 = ConvertStringTo64Bit(tostring(gateId))
      if gate64 and gate64 ~= 0 then
        local isactive, destination = GetComponentData(gate64, "isactive", "destination")
        if isactive and destination then
          local dest64 = ConvertStringTo64Bit(tostring(destination))
          if dest64 and dest64 ~= 0 then
            local destKnown = GetComponentData(dest64, "isknown")
            if destKnown then
              return true
            end
          end
        end
      end
    end
    local highways = scpMap.superHighways[tostring(sectorLuaId)]
    for _, highway in ipairs(highways or {}) do
      local entryGateKnown = GetComponentData(highway.entryGate, "isknown")
      local exitGateKnown = GetComponentData(highway.exitGate, "isknown")
      if entryGateKnown and exitGateKnown then
        return true
      end
    end
    return (not gates or #gates == 0) and (highways == nil or #highways == 0)
  end

  -- Shortest gate-hop path from startSectorId to targetSectorId, or to any known sector when
  -- no target is given. Returns the components to reveal along it, nil when there is no path.
  local function findRevealPath(startSectorId, targetSectorId)
    local MAX_DEPTH = 100
    -- queue entries: { sectorId, path (flat list of LuaIDs to reveal), depth, incomingGate }
    local queue = { { sectorId = startSectorId, path = {}, depth = 0, incomingGate = nil } }
    local visited = { [tostring(startSectorId)] = true }
    local head = 1

    while head <= #queue do
      local current = queue[head]
      head = head + 1

      if current.depth < MAX_DEPTH then
        local gates = GetGates(current.sectorId)
        if gates then
          for _, gateId in ipairs(gates) do
            local gate64 = ConvertStringTo64Bit(tostring(gateId))
            if gate64 and gate64 ~= 0 and gate64 ~= current.incomingGate then
              local isactive, destination = GetComponentData(gate64, "isactive", "destination")
              if isactive and destination then
                local destSectorId = GetContextByClass(destination, "sector", false)
                if destSectorId and destSectorId ~= 0 then
                  local destSectorKey = tostring(destSectorId)
                  if not visited[destSectorKey] then
                    local newPath = {}
                    for i = 1, #current.path do newPath[i] = current.path[i] end
                    -- With a target, keep walking past known sectors instead of stopping at one.
                    local forceNext = targetSectorId and current.sectorId ~= targetSectorId

                    if not GetComponentData(gate64, "isknown") or forceNext then
                      newPath[#newPath + 1] = gate64
                    end

                    local dest64 = ConvertStringTo64Bit(tostring(destination))
                    if dest64 and dest64 ~= 0 and (not GetComponentData(dest64, "isknown") or forceNext) then
                      newPath[#newPath + 1] = dest64
                    end

                    local destSector64 = ConvertStringTo64Bit(destSectorKey)
                    local destKnown = GetComponentData(destSector64, "isknown")
                    if destKnown and not forceNext or destSector64 == targetSectorId then
                      return newPath
                    end

                    newPath[#newPath + 1] = destSector64
                    visited[destSectorKey] = true
                    queue[#queue + 1] = { sectorId = destSector64, path = newPath, depth = current.depth + 1, incomingGate = dest64 }
                  end
                end
              end
            end
          end
        end
        local superHighways = scpMap.superHighways[tostring(current.sectorId)]
        if superHighways then
          for _, highway in ipairs(superHighways) do
            local destSectorId = highway.exitSector
            local destSectorKey = tostring(destSectorId)
            if not visited[destSectorKey] then
              local newPath = {}
              for i = 1, #current.path do newPath[i] = current.path[i] end
              local forceNext = targetSectorId and current.sectorId ~= targetSectorId

              if not GetComponentData(highway.highway, "isknown") or forceNext then
                newPath[#newPath + 1] = highway.highway
              end

              if not GetComponentData(highway.entryGate, "isknown") or forceNext then
                newPath[#newPath + 1] = highway.entryGate
              end

              if not GetComponentData(highway.exitGate, "isknown") or forceNext then
                newPath[#newPath + 1] = highway.exitGate
              end

              local destSector64 = ConvertStringTo64Bit(destSectorKey)
              local destKnown = GetComponentData(destSector64, "isknown")
              if destKnown and not forceNext or destSector64 == targetSectorId then
                return newPath
              end

              newPath[#newPath + 1] = destSector64
              visited[destSectorKey] = true
              queue[#queue + 1] = { sectorId = destSector64, path = newPath, depth = current.depth + 1, incomingGate = nil }
            end
          end
        end
      end
    end

    return nil
  end

  local rowGroup = scp.isV9 and frameTable:addRowGroup({}) or frameTable
  for _, sector in ipairs(sectors) do
    local nameColor = (sector.factionId ~= "ownerless") and GetFactionData(sector.factionId, "color") or Color["text_normal"]
    if sector.isknown then
      local pathKnown = hasKnownPath(sector.id)
      if pathKnown then
        if sector.hasUnknownGates then
          numDisplayed = scp.menuHelper.createButton(rowGroup, sector.id, numDisplayed, {
            text            = sector.name,
            active          = true,
            mouseOverText   = nil,
            buttonText      = ReadText(PAGE_ID, 6006),
            onClick         = function()
              local gates = revealGates(sector.id)
              if gates and #gates > 0 then
                menu.noupdate = true
                AddUITriggeredEvent("scp_main", "scp_reveal_path", gates)
              end
            end,
            textColIndex    = nil,
            buttonColIndex  = nil,
            textColor       = nameColor,
            buttonTextColor = nil,
            fixed           = nil,
            isHeader        = nil,
          })
        else
          numDisplayed = scp.menuHelper.createDoubleText(rowGroup, sector.id, numDisplayed, {
            text               = sector.name,
            mouseOverText      = nil,
            secondText         = ReadText(PAGE_ID, 6004),
            textColIndex       = nil,
            secondTextColIndex = nil,
            textColor          = nameColor,
            secondTextColor    = Color["text_positive"],
            fixed              = nil,
            isHeader           = nil,
          })
        end
      else
        numDisplayed = scp.menuHelper.createButton(rowGroup, sector.id, numDisplayed, {
          text            = sector.name,
          active          = true,
          mouseOverText   = nil,
          buttonText      = ReadText(PAGE_ID, 6005),
          onClick         = function()
            local path = findRevealPath(sector.id, ConvertStringTo64Bit(tostring(C.GetContextByClass(C.GetPlayerID(), "sector", false))))
            if not path or #path == 0 then
              -- No route to the player's own sector, so settle for the nearest known one.
              path = findRevealPath(sector.id)
            end
            if path and #path > 0 then
              menu.noupdate = true
              AddUITriggeredEvent("scp_main", "scp_reveal_path", path)
            end
          end,
          textColIndex    = nil,
          buttonColIndex  = nil,
          textColor       = nameColor,
          buttonTextColor = nil,
          fixed           = nil,
          isHeader        = nil,
        })
      end
    else
      numDisplayed = scp.menuHelper.createButton(rowGroup, -1, numDisplayed, {
        text            = sector.name,
        active          = true,
        mouseOverText   = nil,
        buttonText      = ReadText(PAGE_ID, 6001),
        onClick         = function()
          menu.noupdate = true
          AddUITriggeredEvent("scp_main", "scp_reveal_sector", { sector.macro })
        end,
        textColIndex    = nil,
        buttonColIndex  = nil,
        textColor       = nameColor,
        buttonTextColor = nil,
        fixed           = nil,
        isHeader        = nil,
      })
    end
    local row = frameTable.rows[#frameTable.rows]
    if sector.id == menu.infoSubmenuObject then
      menu.setrow = row.index
      scpMap.scp.currentRow = {}
    end
  end

  return numDisplayed
end

function scpMap.collectSuperHighways()
  local superHighways = GetNPCBlackboard(scpMap.scp.playerId, scpMap.scpConfig.variableId) or {}
  scpMap.superHighways = {}
  for i = 1, #superHighways do
    local highway = superHighways[i]
    if highway then
      local superHighway = {
        entryGate = ConvertStringTo64Bit(tostring(highway.entryGate)),
        exitGate = ConvertStringTo64Bit(tostring(highway.exitGate)),
        entrySector = ConvertStringTo64Bit(tostring(highway.entryGateSector)),
        exitSector = ConvertStringTo64Bit(tostring(highway.exitGateSector)),
        highway = ConvertStringTo64Bit(tostring(highway.highway))
      }
      local entrySectorString = tostring(superHighway.entrySector)
      if scpMap.superHighways[entrySectorString] == nil then
        scpMap.superHighways[entrySectorString] = {superHighway}
      else
        table.insert(scpMap.superHighways[entrySectorString], superHighway)
      end
    end
  end
end

function scpMap.requestSuperHighways()
  if scpMap.superHighways == nil then
    SetNPCBlackboard(scpMap.scp.playerId, scpMap.scpConfig.variableId, {})
    AddUITriggeredEvent("scp_main", "scp_collect_super_highways")
  end
end

-- The sector and highway lists are not reachable from Lua: MD fills the blackboard and
-- signals back, so both requests clear it first and the section renders empty until then.
function scpMap.requestSectors()
  if #scpMap.sectors == 0 then
    SetNPCBlackboard(scpMap.scp.playerId, scpMap.scpConfig.variableId, {})
    AddUITriggeredEvent("scp_main", "scp_collect_sectors")
  else
    scpMap.requestSuperHighways()
  end
end

function scpMap.collectSectors()
  local sectors = GetNPCBlackboard(scpMap.scp.playerId, scpMap.scpConfig.variableId) or {}
  local seen = {}
  for i = 1, #sectors do
    sectors[i] = ConvertStringTo64Bit(tostring(sectors[i]))
  end
  scpMap.sectors = sectors
  scpMap.requestSuperHighways()
end

function scpMap.onSelectElement(uiTable, modified, row, isDblClick, input, rowData)
  if input == "mouse" and not modified then
    local componentId = ConvertStringTo64Bit(tostring(rowData))
    if componentId and componentId ~= 0 then
      C.SetFocusMapComponent(menu.holomap, componentId, true)
      menu.infoSubmenuObject = componentId
      if menu.infoMode.right == "objectinfo" then
        menu.refreshInfoFrame2()
      end
    end
  end
end


function scpMap.init(scp, config)
  scpMap.scp = scp
  scpMap.scpConfig = config
  RegisterEvent("scp_main.collected_sectors", scpMap.collectSectors)
  RegisterEvent("scp_main.collected_superhighways", scpMap.collectSuperHighways)
end

Register_Require_Response("extensions.safe_cheat_panel.ui.scp_map", scpMap)
return scpMap
