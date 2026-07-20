local ffi = require("ffi")
local C = ffi.C

ffi.cdef [[
    typedef uint64_t UniverseID;

    UniverseID GetPlayerObjectID(void);
    bool IsComponentClass(UniverseID componentid, const char* classname);
]]

local menu         = Helper.getMenu("MapMenu")
local interactMenu = Helper.getMenu("InteractMenu")

local PAGE_ID = 1972092427

local scpDestroy = {
  state = {
    object = nil, -- 64-bit converted component id, set only via the interact menu action
    confirmed = false,
  },
}

function scpDestroy.join(scp)
  scpDestroy.scp = scp
end

function scpDestroy.isValidDestroyObject()
  -- Only offered while the Destroy tab is the visible panel tab
  if menu.infoTableMode ~= "safeCheatPanel" or scpDestroy.scp.tableMode ~= "scpDestroy" then
    return false
  end
  local component = interactMenu.componentSlot and interactMenu.componentSlot.component
  if component == nil or component == 0 then
    return false
  end
  if not C.IsComponentClass(component, "destructible") then
    return false
  elseif C.IsComponentClass(component, "gate") or C.IsComponentClass(component, "highway") or C.IsComponentClass(component, "highwayentrygate") or C.IsComponentClass(component, "highwayexitgate") then
    return false
  end
  if component == C.GetPlayerObjectID() then
    return false
  end
  local convertedComponent = ConvertStringTo64Bit(tostring(component))
  if convertedComponent == nil or convertedComponent == 0 or not IsValidComponent(convertedComponent) then
    return false
  end
  return true
end

function scpDestroy.startDestroy()
  scpDestroy.state.object = ConvertStringTo64Bit(tostring(interactMenu.componentSlot.component))
  scpDestroy.state.confirmed = false
  scpDestroy.scp.debug("Destroy: target set to " .. tostring(scpDestroy.state.object))
  scpDestroy.scp.helpers.interactMenuFinishAction()
  menu.refreshInfoFrame()
end

function scpDestroy.cancel()
  scpDestroy.scp.debug("Destroy: cancelled")
  scpDestroy.state.object = nil
  scpDestroy.state.confirmed = false
  menu.refreshInfoFrame()
end

function scpDestroy.executeDestroy()
  local object = scpDestroy.state.object
  scpDestroy.scp.debug("Destroy: button pressed, object = " .. tostring(object) .. ", confirmed = " .. tostring(scpDestroy.state.confirmed))
  if object == nil or not scpDestroy.state.confirmed then
    return
  end
  -- MD receives event.param3 via AddUITriggeredEvent; component references crossing that
  -- boundary must be LuaID-converted (ConvertStringToLuaID), not the C-style 64bit id used
  -- for local GetComponentData/FFI calls above.
  AddUITriggeredEvent("scp_main", "scp_destroy_object", { object = ConvertStringToLuaID(tostring(object)) })
  scpDestroy.scp.debug("Destroy: destroy event sent")
  scpDestroy.state.object = nil
  scpDestroy.state.confirmed = false
  menu.refreshInfoFrame()
end

function scpDestroy.createSection(frameTable, numDisplayed, scp)
  local isV9 = scp.isV9

  numDisplayed = scp.menuHelper.createTitle(frameTable, numDisplayed, {
    text  = ReadText(PAGE_ID, 9000),
    fixed = true,
  })

  local rowGroupMain = isV9 and frameTable:addRowGroup({}) or frameTable

  if not isV9 then
    frameTable:addEmptyRow(Helper.standardTextHeight / 2, { fixed = true })
  end

  local object = scpDestroy.state.object
  if object ~= nil and not IsValidComponent(object) then
    scpDestroy.state.object = nil
    scpDestroy.state.confirmed = false
    object = nil
  end

  if object == nil then
    local row = rowGroupMain:addRow(nil, { bgColor = Color["row_background_unselectable"] })
    row[1]:setColSpan(12):createText(ReadText(PAGE_ID, 9010), { halign = "center", color = Color["text_inactive"] })
    return numDisplayed + 1
  end

  local name, idcode, icon, sector, owner = GetComponentData(object, "name", "idcode", "icon", "sector", "owner")
  local factionColor = owner and Helper.convertColorToText(GetFactionData(owner, "color")) or ""
  local displayIcon = (icon ~= nil and icon ~= "") and icon or "menu_info"

  numDisplayed = scp.menuHelper.createIconWithTextRow(rowGroupMain, "destroy_object_info", numDisplayed, {
    icon      = displayIcon,
    textLeft  = string.format("%s%s (%s)", factionColor, name, idcode),
    textRight = sector or "",
    fixed     = true,
  })

  local rowGroupCheckbox = isV9 and rowGroupMain:addRowGroup({}) or frameTable

  numDisplayed = scp.menuHelper.createCheckBoxOnLeft(rowGroupCheckbox, "destroy_confirm", numDisplayed, {
    active      = true,
    checked     = scpDestroy.state.confirmed,
    text        = ReadText(PAGE_ID, 9020),
    textColIndex = 2,
    textColor   = Color["text_normal"],
    fixed       = true,
    onClick     = function(_, checked)
      scpDestroy.scp.debug("Destroy: confirmation set to " .. tostring(checked))
      scpDestroy.state.confirmed = checked
      menu.refreshInfoFrame()
    end,
  })

  if not isV9 then
    frameTable:addEmptyRow(Helper.standardTextHeight / 2, { fixed = true })
  end

  local row = frameTable:addRow("destroy_buttons", { fixed = true, bgColor = Color["row_background_unselectable"] })
  row[1]:setColSpan(6):createButton({ active = true }):setText(ReadText(1001, 64), { halign = "center" })
  row[1].handlers.onClick = scpDestroy.cancel
  row[7]:setColSpan(6):createButton({ active = scpDestroy.state.confirmed }):setText(ReadText(PAGE_ID, 9030), { halign = "center", color = Color["text_negative"] })
  row[7].handlers.onClick = scpDestroy.executeDestroy
  numDisplayed = numDisplayed + 1

  return numDisplayed
end

Register_Require_Response("extensions.safe_cheat_panel.ui.scp_destroy", scpDestroy)
return scpDestroy
