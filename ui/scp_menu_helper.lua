local menu = Helper.getMenu("MapMenu")
local scp = {
  subHeaderRowCenteredProperties = { }
}

local config = {
  mapRowHeight = Helper.standardTextHeight,
  mapFontSize = Helper.standardFontSize,
  defaultSecondColumn = 8
}

---Create a double text (two "columns") in the current table.
---@param frameTable table
---@param id any
---@param options table { text, mouseOverText, secondText, numDisplayed, textColIndex, secondTextColIndex, textColor, secondTextColor, fixed, isHeader }
---@return integer
function scp.createDoubleText(frameTable, id, options)
  local textColumnIndex = options.textColIndex or 1
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
  return options.numDisplayed + 1
end

---Create a button in the current table.
---@param frameTable table
---@param id any
---@param options table { text, active, mouseOverText, buttonText, onClick, numDisplayed, textColIndex, buttonColIndex, textColor, buttonTextColor, fixed, isHeader }
---@return integer
function scp.createButton(frameTable, id, options)
  local textColumnIndex = options.textColIndex or 1
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
  return options.numDisplayed + 1
end

---Create a checkbox in the current table.
---@param frameTable table
---@param id any
---@param options table { active, text, mouseOverText, numDisplayed, textColIndex, checkBoxColIndex, textColor, fixed }
---@return integer
function scp.createCheckBox(frameTable, id, options)
  local textColumnIndex = options.textColIndex or 1
  local checkboxColumnIndex = options.checkBoxColIndex or config.defaultSecondColumn

  local rowProps = { width = config.mapRowHeight, height = config.mapRowHeight }
  if options.fixed then rowProps.fixed = true end
  local row = frameTable:addRow(id, rowProps)
  row[textColumnIndex]:setColSpan(checkboxColumnIndex - 1):createText(options.text, { mouseOverText = options.mouseOverText, color = options.textColor })
  row[checkboxColumnIndex]:createCheckBox(scp.spawnCentered, { active = options.active, width = Helper.standardButtonHeight, mouseOverText = options.mouseOverText })
  row[checkboxColumnIndex].handlers.onClick = function(_, checked) scp.spawnCentered = checked end
  return options.numDisplayed + 1
end

---Create an edit box in the current table.
---@param frameTable table
---@param id any
---@param options table { active, text, mouseOverText, editText, onEditBoxDeactivated, numDisplayed, textColIndex, editBoxColIndex, textColor, fixed, isHeader }
---@return integer
function scp.createEditBox(frameTable, id, options)
  local textColumnIndex = options.textColIndex or 1
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
  return options.numDisplayed + 1
end

---Create a drop down in the current table.
---@param frameTable table
---@param id any
---@param options table { active, dropDownData, startOption, text, textOverride, onConfirmed, numDisplayed, textColIndex, dropDownColIndex, dropDownSpan, textColor, fixed, isHeader }
---@return integer
function scp.createDropDown(frameTable, id, options)
  local textColumnIndex = options.textColIndex or 1
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
  return options.numDisplayed + 1
end

---Create a text title in the current table.
---@param frameTable table
---@param options table { text, numDisplayed, fixed }
---@return integer
function scp.createTitle(frameTable, options)
  local rowProps = { bgColor = Color["row_title_background"] }
  if options.fixed then rowProps.fixed = true end
  local title = frameTable:addRow(nil, rowProps)
  title[1]:setColSpan(12):createText(options.text, Helper.headerRowCenteredProperties)
  return options.numDisplayed + 1
end

---Create a text subtitle in the current table.
---@param frameTable table
---@param options table { text, numDisplayed }
---@return integer
function scp.createSubTitle(frameTable, options)
  local title = frameTable:addRow(nil, { bgColor = Color["row_title_background"] })
  title[1]:setColSpan(12):createText(options.text, scp.subHeaderRowCenteredProperties)
  return options.numDisplayed + 1
end

---Create a slider in the current table.
---@param frameTable table
---@param id any
---@param options table { text, mouseOverText, startValue, onSliderChanged, onSliderConfirm, onSliderActivated, onSliderDeactivated, numDisplayed, min, max, step, fromCenter, readOnly, rowBgColor, textColIndex, sliderColIndex, sliderSpan, textColor }
---@return integer
function scp.createSliderRow(frameTable, id, options)
  local textColumnIndex = options.textColIndex or 1
  local sliderColumnIndex = options.sliderColIndex or config.defaultSecondColumn
  local numColumns = frameTable.table and frameTable.table.numcolumns or frameTable.numcolumns or 12
  local sliderColumnSpan = options.sliderSpan or (numColumns - sliderColumnIndex + 1)
  local min = options.min or 1
  local max = options.max or 10
  local step = options.step or 1

  local rowProps = { bgColor = options.rowBgColor or Color["row_background_unselectable"] }
  local row = frameTable:addRow(id, rowProps)
  row[textColumnIndex]:setColSpan(sliderColumnIndex - 1):createText(options.text, { mouseOverText = options.mouseOverText, color = options.textColor })
  row[sliderColumnIndex]:setColSpan(sliderColumnSpan):createSliderCell({ min = min, max = max, start = options.startValue, mouseOverText = options.mouseOverText, fromCenter = options.fromCenter or false, step = step, readOnly = options.readOnly or false, height = Helper.standardTextHeight })
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
  return options.numDisplayed + 1
end

function scp.init()
  scp.subHeaderRowCenteredProperties = Helper.subHeaderTextProperties
  scp.subHeaderRowCenteredProperties.halign = "center"
end

Register_Require_Response("extensions.safe_cheat_panel.ui.scp_menu_helper", scp)
return scp
