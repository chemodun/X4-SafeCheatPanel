local menu = Helper.getMenu("MapMenu")
local scp = {
  subHeaderRowCenteredProperties = { }
}

local config = {
  mapRowHeight = Helper.standardTextHeight,
  mapFontSize = Helper.standardFontSize,
  defaultFirstColumn = 1,
  defaultSecondColumn = 8
}

---Create a double text (two "columns") in the current table.
---@param frameTable table
---@param id any
---@param numDisplayed integer
---@param options table { text, mouseOverText, secondText, textColIndex, secondTextColIndex, textColor, secondTextColor, fixed, isHeader }
---@return integer
function scp.createDoubleText(frameTable, id, numDisplayed, options)
  local textColumnIndex = options.textColIndex or config.defaultFirstColumn
  local secondTextColumnIndex = options.secondTextColIndex or config.defaultSecondColumn
  local numColumns = frameTable.table and frameTable.table.numcolumns or frameTable.numcolumns or 12
  local secondTextColumnSpan = numColumns - secondTextColumnIndex + 1

  local rowProps = { bgColor = Color["row_background_unselectable"] }
  if options.fixed then rowProps.fixed = true end
  local row = frameTable:addRow(id, rowProps)
  if options.isHeader then
    row[textColumnIndex]:setColSpan(secondTextColumnIndex - 1):createText(options.text, scp.subHeaderRowCenteredProperties)
  else
    row[textColumnIndex]:setColSpan(secondTextColumnIndex - 1):createText(options.text, { color = options.textColor })
  end
  row[textColumnIndex].properties.mouseOverText = options.text
  if options.isHeader then
    row[secondTextColumnIndex]:setColSpan(secondTextColumnSpan):createText(options.secondText, scp.subHeaderRowCenteredProperties)
  else
    row[secondTextColumnIndex]:setColSpan(secondTextColumnSpan):createText(options.secondText, { halign = "center", color = options.secondTextColor, mouseOverText = options.mouseOverText })
  end
  return numDisplayed + 1
end

---Create a button in the current table.
---@param frameTable table
---@param id any
---@param numDisplayed integer
---@param options table { text, active, mouseOverText, buttonText, onClick, textColIndex, buttonColIndex, textColor, buttonTextColor, fixed, isHeader }
---@return integer
function scp.createButton(frameTable, id, numDisplayed, options)
  local textColumnIndex = options.textColIndex or config.defaultFirstColumn
  local buttonColumnIndex = options.buttonColIndex or config.defaultSecondColumn
  local numColumns = frameTable.table and frameTable.table.numcolumns or frameTable.numcolumns or 12
  local buttonColumnSpan = numColumns - buttonColumnIndex + 1

  local rowProps = { bgColor = Color["row_background_unselectable"] }
  if options.fixed then rowProps.fixed = true end
  local row = frameTable:addRow(id, rowProps)
  if options.isHeader then
    row[textColumnIndex]:setColSpan(buttonColumnIndex - 1):createText(options.text, scp.subHeaderRowCenteredProperties)
  else
    row[textColumnIndex]:setColSpan(buttonColumnIndex - 1):createText(options.text, { color = options.textColor })
  end
  row[textColumnIndex].properties.mouseOverText = options.text
  row[buttonColumnIndex]:setColSpan(buttonColumnSpan):createButton({ active = options.active, mouseOverText = options.mouseOverText }):setText(options.buttonText, { halign = "center", color = options.buttonTextColor })
  row[buttonColumnIndex].handlers.onClick = options.onClick
  return numDisplayed + 1
end

---Create a checkbox in the current table.
---@param frameTable table
---@param id any
---@param numDisplayed integer
---@param options table { active, text, mouseOverText, textColIndex, checkBoxColIndex, textColor, fixed }
---@return integer
function scp.createCheckBox(frameTable, id, numDisplayed, options)
  local textColumnIndex = options.textColIndex or config.defaultFirstColumn
  local checkboxColumnIndex = options.checkBoxColIndex or config.defaultSecondColumn
  local rowProps = { width = config.mapRowHeight, height = config.mapRowHeight }
  if options.fixed then rowProps.fixed = true end
  local row = frameTable:addRow(id, rowProps)
  row[textColumnIndex]:setColSpan(checkboxColumnIndex - 1):createText(options.text, { mouseOverText = options.mouseOverText, color = options.textColor })
  row[checkboxColumnIndex]:createCheckBox(scp.spawnCentered, { active = options.active, width = Helper.standardButtonHeight, mouseOverText = options.mouseOverText })
  row[checkboxColumnIndex].handlers.onClick = function(_, checked) scp.spawnCentered = checked end
  return numDisplayed + 1
end

---Create a checkbox (on the left) in the current table.
---@param frameTable table
---@param id any
---@param numDisplayed integer
---@param options table { checked, active, onClick, text, mouseOverText, textColIndex, checkBoxColIndex, textColor, fixed }
---@return integer
function scp.createCheckBoxOnLeft(frameTable, id, numDisplayed, options)
  local checkboxColumnIndex = options.checkBoxColIndex or config.defaultFirstColumn
  local textColumnIndex = options.textColIndex or config.defaultSecondColumn
  local numColumns = frameTable.table and frameTable.table.numcolumns or frameTable.numcolumns or 12
  local textColumnSpan = numColumns - textColumnIndex + 1

  local rowProps = { width = config.mapRowHeight, height = config.mapRowHeight }
  if options.fixed then rowProps.fixed = true end
  local row = frameTable:addRow(id, rowProps)
  row[checkboxColumnIndex]:createCheckBox(options.checked, { active = options.active, width = Helper.standardButtonHeight, mouseOverText = options.mouseOverText })
  row[checkboxColumnIndex].handlers.onClick = options.onClick
  row[textColumnIndex]:setColSpan(textColumnSpan):createText(options.text, { mouseOverText = options.mouseOverText, color = options.textColor })
  return numDisplayed + 1
end

---Create an edit box in the current table.
---@param frameTable table
---@param id any
---@param numDisplayed integer
---@param options table { active, text, mouseOverText, editText, onEditBoxDeactivated, textColIndex, editBoxColIndex, textColor, fixed, isHeader }
---@return integer
function scp.createEditBox(frameTable, id, numDisplayed, options)
  local textColumnIndex = options.textColIndex or config.defaultFirstColumn
  local editBoxColumnIndex = options.editBoxColIndex or config.defaultSecondColumn
  local numColumns = frameTable.table and frameTable.table.numcolumns or frameTable.numcolumns or 12
  local editBoxColumnSpan = numColumns - editBoxColumnIndex + 1

  local rowProps = { bgColor = Color["row_background_unselectable"], interactive = false }
  if options.fixed then rowProps.fixed = true end
  local row = frameTable:addRow(id, rowProps)
  if options.isHeader then
    row[textColumnIndex]:setColSpan(editBoxColumnIndex - 1):createText(options.text, scp.subHeaderRowCenteredProperties)
  else
    row[textColumnIndex]:setColSpan(editBoxColumnIndex - 1):createText(options.text, { color = options.textColor })
  end
  row[textColumnIndex].properties.mouseOverText = options.text
  row[editBoxColumnIndex]:setColSpan(editBoxColumnSpan):createEditBox({ height = config.mapRowHeight, mouseOverText = options.mouseOverText, active = options.active }):setText(options.editText)
  row[editBoxColumnIndex].handlers.onEditBoxDeactivated = options.onEditBoxDeactivated
  return numDisplayed + 1
end

---Create a drop down in the current table.
---@param frameTable table
---@param id any
---@param numDisplayed integer
---@param options table { active, dropDownData, startOption, text, textOverride, onConfirmed, textColIndex, dropDownColIndex, dropDownSpan, textColor, fixed, isHeader }
---@return integer
function scp.createDropDown(frameTable, id, numDisplayed, options)
  local textColumnIndex = options.textColIndex or config.defaultFirstColumn
  local dropdownColumnIndex = options.dropDownColIndex or config.defaultSecondColumn
  local numColumns = frameTable.table and frameTable.table.numcolumns or frameTable.numcolumns or 12
  local dropdownColumnSpan = options.dropDownSpan or (numColumns - dropdownColumnIndex + 1)

  local rowProps = { bgColor = Color["row_background_unselectable"] }
  if options.fixed then rowProps.fixed = true end
  local row = frameTable:addRow(id, rowProps)
  if dropdownColumnSpan ~= 12 then
    if options.isHeader then
      row[textColumnIndex]:setColSpan(dropdownColumnIndex - 1):createText(options.text, scp.subHeaderRowCenteredProperties)
    else
      row[textColumnIndex]:setColSpan(dropdownColumnIndex - 1):createText(options.text, { color = options.textColor })
    end
    row[textColumnIndex].properties.mouseOverText = options.text
  else
    dropdownColumnIndex = 1
  end
  row[dropdownColumnIndex]:setColSpan(dropdownColumnSpan):createDropDown(options.dropDownData,
    { textOverride = options.textOverride, active = options.active, startOption = options.startOption }):setTextProperties({ fontsize = config.mapFontSize })
  row[dropdownColumnIndex].handlers.onDropDownConfirmed = options.onConfirmed
  row[dropdownColumnIndex].handlers.onDropDownActivated = function() menu.noupdate = true end
  return numDisplayed + 1
end

---Create a text title in the current table.
---@param frameTable table
---@param numDisplayed integer
---@param options table { text, fixed }
---@return integer
function scp.createTitle(frameTable, numDisplayed, options)
  local rowProps = { bgColor = Color["row_title_background"] }
  if options.fixed then rowProps.fixed = true end
  local title = frameTable:addRow(nil, rowProps)
  title[1]:setColSpan(12):createText(options.text, Helper.headerRowCenteredProperties)
  return numDisplayed + 1
end

---Create a text subtitle in the current table.
---@param frameTable table
---@param numDisplayed integer
---@param options table { text }
---@return integer
function scp.createSubTitle(frameTable, numDisplayed, options)
  local title = frameTable:addRow(nil, { bgColor = Color["row_title_background"] })
  title[1]:setColSpan(12):createText(options.text, scp.subHeaderRowCenteredProperties)
  return numDisplayed + 1
end

---Create a slider in the current table.
---@param frameTable table
---@param id any
---@param numDisplayed integer
---@param options table { text, mouseOverText, startValue, onSliderChanged, onSliderConfirm, onSliderActivated, onSliderDeactivated, min, max, step, suffix, fromCenter, readOnly, rowBgColor, textColIndex, sliderColIndex, sliderSpan, textColor, fixed }
---@return integer
function scp.createSliderRow(frameTable, id, numDisplayed, options)
  local textColumnIndex = options.textColIndex or config.defaultFirstColumn
  local sliderColumnIndex = options.sliderColIndex or config.defaultSecondColumn
  local numColumns = frameTable.table and frameTable.table.numcolumns or frameTable.numcolumns or 12
  local sliderColumnSpan = options.sliderSpan or (numColumns - sliderColumnIndex + 1)
  local min = options.min or 1
  local max = options.max or 10
  local step = options.step or 1

  local rowProps = { bgColor = options.rowBgColor or Color["row_background_unselectable"] }
  if options.fixed then rowProps.fixed = true end
  local row = frameTable:addRow(id, rowProps)
  row[textColumnIndex]:setColSpan(sliderColumnIndex - 1):createText(options.text, { mouseOverText = options.mouseOverText, color = options.textColor })
  row[sliderColumnIndex]:setColSpan(sliderColumnSpan):createSliderCell({ min = min, max = max, start = options.startValue, mouseOverText = options.mouseOverText, fromCenter = options.fromCenter or false, step = step, suffix = options.suffix, readOnly = options.readOnly or false, height = Helper.standardTextHeight })
  row[sliderColumnIndex].handlers.onSliderCellChanged = options.onSliderChanged
  if options.onSliderConfirm then
    row[sliderColumnIndex].handlers.onSliderCellConfirm = options.onSliderConfirm
  end
  if options.onSliderActivated then
    row[sliderColumnIndex].handlers.onSliderCellActivated = options.onSliderActivated
  end
  if options.onSliderDeactivated then
    row[sliderColumnIndex].handlers.onSliderCellDeactivated = options.onSliderDeactivated
  end
  return numDisplayed + 1
end

---Create an icon with text row in the current table.
---@param frameTable table
---@param id any
---@param numDisplayed integer
---@param options table { icon, textLeft, textRight, mouseOverText, rowBgColor, textLeftColor, textRightColor, fixed }
---@return integer
function scp.createIconWithTextRow(frameTable, id, numDisplayed, options)
  local numColumns = frameTable.table and frameTable.table.numcolumns or frameTable.numcolumns or 12
  local rowProps = { bgColor = options.rowBgColor or Color["row_background_unselectable"] }
  if options.fixed then rowProps.fixed = true end
  local row = frameTable:addRow(id, rowProps)
  local iconColumn = config.defaultFirstColumn
  local iconColumnSpan = numColumns - iconColumn + 1

  row[iconColumn]:setColSpan(iconColumnSpan):createIcon(options.icon, { height = config.mapRowHeight, width = config.mapRowHeight })
  if options.textLeft ~= nil then
    row[iconColumn]:setText(options.textLeft, { x = config.mapRowHeight, halign = "left", color = options.textLeftColor })
  end
  if options.textRight ~= nil then
    row[iconColumn]:setText2(options.textRight, { halign = "right", color = options.textRightColor })
  end
  return numDisplayed + 1
end

function scp.init()
  scp.subHeaderRowCenteredProperties = Helper.subHeaderTextProperties
  scp.subHeaderRowCenteredProperties.halign = "center"
end

Register_Require_Response("extensions.safe_cheat_panel.ui.scp_menu_helper", scp)
return scp
