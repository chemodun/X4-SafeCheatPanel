local ffi = require("ffi")
local C = ffi.C

ffi.cdef [[
	uint32_t GetNumWares(const char* tags, bool research, const char* licenceownerid, const char* exclusiontags);
	uint32_t GetWares(const char** result, uint32_t resultlen, const char* tags, bool research, const char* licenceownerid, const char* exclusiontags);
	void AddPlayerMoney(int64_t money);
]]

local menu         = Helper.getMenu("MapMenu")
local interactMenu = Helper.getMenu("InteractMenu")

local PAGE_ID = 1972092427

local scpPlayer = {}

function scpPlayer.SetPlayerMoney(newBalance)
  if not newBalance then
    menu.refreshInfoFrame()
    return
  end
  local maxMoney = 1e15
  newBalance = math.max(0, math.min(newBalance, maxMoney))
  local currentBalance = GetPlayerMoney()
  C.AddPlayerMoney(-currentBalance * 100)
  C.AddPlayerMoney(newBalance * 100)
  menu.refreshInfoFrame()
end

function scpPlayer.createSection(frameTable, numDisplayed, scp)
  local spacesuitUpgrades = {}
  local spacesuitAmmo = {}
  local numWares = C.GetNumWares("personalupgrade", false, nil, "")
  local wares = ffi.new("const char*[?]", numWares)
  numWares = C.GetWares(wares, numWares, "personalupgrade", false, nil, "")
  for i = 0, numWares - 1 do
    local ware = ffi.string(wares[i])
    local wareName, isAmmo = GetWareData(ware, "name", "isammo")
    local amount = 0
    if GetPlayerInventory()[ware] ~= nil then
      amount = GetPlayerInventory()[ware].amount
    end
    if isAmmo then
      spacesuitAmmo[#spacesuitAmmo + 1] = { id = ware, name = wareName, amount = amount }
    else
      spacesuitUpgrades[#spacesuitUpgrades + 1] = { id = ware, name = wareName, amount = amount }
    end
  end
  table.sort(spacesuitUpgrades, Helper.sortName)
  table.sort(spacesuitAmmo, Helper.sortName)

  -- Header: Player
  numDisplayed = scp.menuHelper.createTitle(frameTable, numDisplayed, {
    text  = ReadText(20203, 101),
    fixed = nil,
  })

  local rowGroup = scp.isV9 and frameTable:addRowGroup({}) or frameTable
  -- Player Money
  numDisplayed = scp.menuHelper.createEditBox(rowGroup, "player_money", numDisplayed, {
    active               = true,
    text                 = ReadText(PAGE_ID, 1100),
    mouseOverText        = ReadText(PAGE_ID, 1101),
    editText             = function() return ConvertMoneyString(GetPlayerMoney(), false, false, 0, true) end,
    onEditBoxDeactivated = function(_, text) scpPlayer.SetPlayerMoney(tonumber(text)) end,
    textColIndex         = nil,
    editBoxColIndex      = nil,
    textColor            = nil,
    fixed                = nil,
    isHeader             = nil,
  })

  -- Title: Spacesuit Upgrades
  numDisplayed = scp.menuHelper.createTitle(frameTable, numDisplayed, {
    text  = ReadText(PAGE_ID, 1200),
    fixed = nil,
  })

  rowGroup = scp.isV9 and frameTable:addRowGroup({}) or frameTable

  for _, upgrade in pairs(spacesuitUpgrades) do
    if upgrade.amount == 0 then
      numDisplayed = scp.menuHelper.createButton(rowGroup, true, numDisplayed, {
        text            = upgrade.name,
        active          = true,
        mouseOverText   = nil,
        buttonText      = ReadText(PAGE_ID, 1201),
        onClick         = function() scp.inventory.SetWare(upgrade.id, 0, 1) end,
        textColIndex    = nil,
        buttonColIndex  = nil,
        textColor       = Color["text_inactive"],
        buttonTextColor = nil,
        fixed           = nil,
        isHeader        = nil,
      })
    else
      numDisplayed = scp.menuHelper.createDoubleText(rowGroup, false, numDisplayed, {
        text               = upgrade.name,
        mouseOverText      = "",
        secondText         = ReadText(PAGE_ID, 1202),
        textColIndex       = nil,
        secondTextColIndex = nil,
        textColor          = nil,
        secondTextColor    = Color["text_positive"],
        fixed              = true,
        isHeader           = false,
      })
    end
  end

  -- Title: Spacesuit Ammo
  numDisplayed = scp.menuHelper.createTitle(frameTable, numDisplayed, {
    text  = ReadText(PAGE_ID, 1300),
    fixed = nil,
  })

  rowGroup = scp.isV9 and frameTable:addRowGroup({}) or frameTable

  for _, ammo in pairs(spacesuitAmmo) do
    numDisplayed = scp.menuHelper.createEditBox(rowGroup, true, numDisplayed, {
      active               = true,
      text                 = ammo.name,
      mouseOverText        = ReadText(PAGE_ID, 1110),
      editText             = ammo.amount,
      onEditBoxDeactivated = function(_, text) scp.inventory.SetWare(ammo.id, ammo.amount, tonumber(text)) end,
      textColIndex         = nil,
      editBoxColIndex      = nil,
      textColor            = nil,
      fixed                = nil,
      isHeader             = nil,
    })
  end

  return numDisplayed
end

function scpPlayer.isValidTeleportPlayer(seat)
  local isValid = false
  if interactMenu.componentSlot.component ~= nil then
    local object64 = ConvertStringTo64Bit(tostring(interactMenu.componentSlot.component))
    if C.IsComponentClass(object64, "ship") or C.IsComponentClass(object64, "station") then
      isValid = true
      if seat then
        isValid = C.IsComponentClass(object64, "ship_s") or C.IsComponentClass(object64, "ship_m")
            and GetComponentData(object64, "owner") == "player" and GetComponentData(object64, "assignedpilot")
      end
    end
  end
  return isValid
end

function scpPlayer.teleportPlayer(seat)
  C.TeleportPlayerTo(interactMenu.componentSlot.component, true, true, true)
  interactMenu.onCloseElement("close")
end

Register_Require_Response("extensions.safe_cheat_panel.ui.scp_player", scpPlayer)
return scpPlayer
