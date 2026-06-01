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
  -- Collect all sectors via faction list + ownerless
  -- In DevMode: all factions (including unknown); otherwise: known factions only (GetLibrary)
  local sectors = {}

  -- Helper: check if a known sector has at least one active gate whose destination is not known
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

  -- Header
  numDisplayed = scp.menuHelper.createTitle(frameTable, {
    text         = ReadText(1001, 9181),
    numDisplayed = numDisplayed,
    fixed        = true,
  })

  if isAllRevealed then
    if isUnknownGates then
      numDisplayed = scp.menuHelper.createButton(frameTable, "map_reveal_all", {
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
        numDisplayed    = numDisplayed,
        textColIndex    = nil,
        buttonColIndex  = nil,
        textColor       = nil,
        buttonTextColor = nil,
        fixed           = true,
        isHeader        = true,
      })
    else
        numDisplayed = scp.menuHelper.createDoubleText(frameTable, false, {
        text               = ReadText(1001, 2809),
        mouseOverText      = "",
        secondText         = ReadText(1001, 12),
        numDisplayed       = numDisplayed,
        textColIndex       = nil,
        secondTextColIndex = nil,
        textColor          = nil,
        secondTextColor    = Color["text_positive"],
        fixed              = true,
        isHeader           = true,
        })
    end
  else
    numDisplayed = scp.menuHelper.createButton(frameTable, "map_reveal_all", {
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
      numDisplayed    = numDisplayed,
      textColIndex    = nil,
      buttonColIndex  = nil,
      textColor       = nil,
      buttonTextColor = nil,
      fixed           = true,
      isHeader        = true,
    })
  end

  -- Helper: check if a known sector has at least one active gate whose destination is also known
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

  -- BFS: find shortest gate-hop path from startSectorId to any known sector.
  -- Returns a flat list of 64-bit component IDs to reveal (gates, dest components,
  -- intermediate sectors) — only includes components not already known.
  -- nil if no path found.
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
                    local forceNext = targetSectorId and current.sectorId ~= targetSectorId

                    -- outgoing gate (if not already known)
                    if not GetComponentData(gate64, "isknown") or forceNext then
                      newPath[#newPath + 1] = gate64
                    end

                    -- destination component/gate on the other side (if not already known)
                    local dest64 = ConvertStringTo64Bit(tostring(destination))
                    if dest64 and dest64 ~= 0 and (not GetComponentData(dest64, "isknown") or forceNext) then
                      newPath[#newPath + 1] = dest64
                    end

                    -- destination sector
                    local destSector64 = ConvertStringTo64Bit(destSectorKey)
                    local destKnown = GetComponentData(destSector64, "isknown")
                    if destKnown and not forceNext or destSector64 == targetSectorId then
                      return newPath  -- BFS: this is the shortest path
                    end

                    -- intermediate sector (not known) — add and continue BFS
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

              -- entry gate (if not already known)
              if not GetComponentData(highway.entryGate, "isknown") or forceNext then
                newPath[#newPath + 1] = highway.entryGate
              end

              -- exit gate (if not already known)
              if not GetComponentData(highway.exitGate, "isknown") or forceNext then
                newPath[#newPath + 1] = highway.exitGate
              end

              -- destination sector
              local destSector64 = ConvertStringTo64Bit(destSectorKey)
              local destKnown = GetComponentData(destSector64, "isknown")
              if destKnown and not forceNext or destSector64 == targetSectorId then
                return newPath  -- BFS: this is the shortest path
              end

              -- intermediate sector (not known) — add and continue BFS
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
          numDisplayed = scp.menuHelper.createButton(rowGroup, sector.id, {
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
            numDisplayed    = numDisplayed,
            textColIndex    = nil,
            buttonColIndex  = nil,
            textColor       = nameColor,
            buttonTextColor = nil,
            fixed           = nil,
            isHeader        = nil,
          })
        else
          numDisplayed = scp.menuHelper.createDoubleText(rowGroup, sector.id, {
            text               = sector.name,
            mouseOverText      = nil,
            secondText         = ReadText(PAGE_ID, 6004),
            numDisplayed       = numDisplayed,
            textColIndex       = nil,
            secondTextColIndex = nil,
            textColor          = nameColor,
            secondTextColor    = Color["text_positive"],
            fixed              = nil,
            isHeader           = nil,
          })
        end
      else
        numDisplayed = scp.menuHelper.createButton(rowGroup, sector.id, {
          text            = sector.name,
          active          = true,
          mouseOverText   = nil,
          buttonText      = ReadText(PAGE_ID, 6005),
          onClick         = function()
            local path = findRevealPath(sector.id, ConvertStringTo64Bit(tostring(C.GetContextByClass(C.GetPlayerID(), "sector", false))))
            if not path or #path == 0 then
              -- fallback: reveal sector to nearest known sector
              path = findRevealPath(sector.id)
            end
            if path and #path > 0 then
              menu.noupdate = true
              AddUITriggeredEvent("scp_main", "scp_reveal_path", path)
            end
          end,
          numDisplayed    = numDisplayed,
          textColIndex    = nil,
          buttonColIndex  = nil,
          textColor       = nameColor,
          buttonTextColor = nil,
          fixed           = nil,
          isHeader        = nil,
        })
      end
    else
      numDisplayed = scp.menuHelper.createButton(rowGroup, -1, {
        text            = sector.name,
        active          = true,
        mouseOverText   = nil,
        buttonText      = ReadText(PAGE_ID, 6001),
        onClick         = function()
          menu.noupdate = true
          AddUITriggeredEvent("scp_main", "scp_reveal_sector", { sector.macro })
        end,
        numDisplayed    = numDisplayed,
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
