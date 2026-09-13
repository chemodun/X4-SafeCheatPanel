local ffi = require("ffi")
local C = ffi.C

-- Signatures as vanilla declares them in ego_detailmonitor/menu_mapeditor.lua:78,79,85.
ffi.cdef [[
    const char* GetMacroClass(const char* macroname);
    uint32_t GetMacrosStartingWith(const char** result, uint32_t resultlen, const char* partialmacroname);
    uint32_t GetNumMacrosStartingWith(const char* partialmacroname);
]]

-- Pre-built installations: station macros flagged isfixedstation. They carry no construction plan,
-- so they spawn from the macro alone.
local scpInstallations = {}

-- The engine answers 0 to an empty prefix, so one call per leading character is the only way in.
local PREFIX_CHARS = "abcdefghijklmnopqrstuvwxyz0123456789_"

-- Never stations. Skipped before GetMacroClass, so absent map macros cost no failed file lookup.
local SKIP_PREFIXES = {
  "cluster", "sector", "zone", "region", "test",
  "engine_", "thruster_", "shield_", "weapon_", "turret_", "bullet_", "missile_",
  "ship_", "prop_", "effect_", "scs_",
}

local function isSkippedFamily(macro)
  for i = 1, #SKIP_PREFIXES do
    local prefix = SKIP_PREFIXES[i]
    if macro:sub(1, #prefix) == prefix then return true end
  end
  return false
end

local entries = nil -- dropdown rows, sorted by label

---Macro names for one prefix. Returns nil when the engine refuses the prefix outright.
local function macrosFor(prefix)
  local n = tonumber(C.GetNumMacrosStartingWith(prefix))
  if n == nil or n <= 0 then return nil end
  local buf = ffi.new("const char*[?]", n)
  n = tonumber(C.GetMacrosStartingWith(buf, n, prefix))
  local out = {}
  for i = 0, n - 1 do out[#out + 1] = ffi.string(buf[i]) end
  return out
end

---Every macro the engine knows. An empty prefix answers 0, so the sweep goes character by character.
function scpInstallations.allMacros()
  local all = macrosFor("")
  if all then return all, "empty prefix" end
  local seen = {}
  all = {}
  for i = 1, #PREFIX_CHARS do
    for _, macro in ipairs(macrosFor(PREFIX_CHARS:sub(i, i)) or {}) do
      if not seen[macro] then
        seen[macro] = true
        all[#all + 1] = macro
      end
    end
  end
  return all, "per-character sweep"
end

---Display name, or nil when there is none: the engine then returns the macro id, not an empty string.
local function macroName(macro)
  local name = GetMacroData(macro, "name")
  if name == nil or name == "" then return nil end
  if name == macro or macro == name .. "_macro" then return nil end
  return name
end

---Is this macro a pre-built installation rather than a plan-built base?
function scpInstallations.isInstallation(macro)
  if macro == nil or macro == "" then return false end
  return GetMacroData(macro, "isfixedstation") == true
end

---Sweeps every macro once, at init. No list of installations in the code: class, isfixedstation and
---a display name decide, the last of which drops unnamed scenario-map placements.
local function build(scp)
  local all, source = scpInstallations.allMacros()
  entries = {}

  local names, skipped, unresolved, ignored = {}, 0, 0, 0
  local macros = {}
  for _, macro in ipairs(all) do
    if isSkippedFamily(macro) then
      ignored = ignored + 1
    else
      -- NULL when the component file is absent, and ffi.string would then read address 0.
      local class = C.GetMacroClass(macro)
      if class == nil then
        unresolved = unresolved + 1
      elseif ffi.string(class) == "station" and scpInstallations.isInstallation(macro) then
        local name = macroName(macro)
        if name == nil then
          skipped = skipped + 1
        else
          macros[#macros + 1] = macro
          names[macro] = name
        end
      end
    end
  end
  table.sort(macros)

  -- Several macros share one name, so the id only joins the label where it disambiguates.
  local nameCount = {}
  for _, macro in ipairs(macros) do
    nameCount[names[macro]] = (nameCount[names[macro]] or 0) + 1
  end

  for _, macro in ipairs(macros) do
    local name = names[macro]
    local label = nameCount[name] > 1 and (name .. " (" .. macro .. ")") or name
    entries[#entries + 1] = { id = macro, text = label, active = true, icon = "", displayremoveoption = false }
  end
  table.sort(entries, function(a, b) return a.text < b.text end)

  if scp then
    scp.debug(string.format(
      "Installations: %d named of %d fixed stations; swept %d macros, %d skipped by family, %d unresolved (%s)",
      #entries, #entries + skipped, #all, ignored, unresolved, source))
    for _, entry in ipairs(entries) do
      scp.trace("Installations: " .. entry.id .. " = " .. entry.text)
    end
  end
end

---Dropdown rows for every pre-built installation.
---@return table
function scpInstallations.getAll(scp)
  if entries == nil then build(scp) end
  return entries or {}
end

---Label for a macro that is not in the swept list, for an installation loaded into edit mode.
function scpInstallations.getLabel(macro)
  return macroName(macro) or macro
end

Register_Require_Response("extensions.safe_cheat_panel.ui.scp_installations", scpInstallations)
return scpInstallations
