local _G = _G
local C_SpellBook = _G.C_SpellBook
local CreateFrame = _G.CreateFrame
local Enum = _G.Enum
local GetBindingAction = _G.GetBindingAction
local GetBindingKey = _G.GetBindingKey
local GetBindingText = _G.GetBindingText
local GetCurrentBindingSet = _G.GetCurrentBindingSet
local GetNumGroupMembers = _G.GetNumGroupMembers
local GetNumSubgroupMembers = _G.GetNumSubgroupMembers
local GetPartyAssignment = _G.GetPartyAssignment
local InCombatLockdown = _G.InCombatLockdown
local IsAltKeyDown = _G.IsAltKeyDown
local IsControlKeyDown = _G.IsControlKeyDown
local IsInRaid = _G.IsInRaid
local IsMetaKeyDown = _G.IsMetaKeyDown
local IsShiftKeyDown = _G.IsShiftKeyDown
local RAID_CLASS_COLORS = _G.RAID_CLASS_COLORS
local SaveBindings = _G.SaveBindings
local SetBinding = _G.SetBinding
local SetBindingClick = _G.SetBindingClick
local STANDARD_TEXT_FONT = _G.STANDARD_TEXT_FONT
local UIParent = _G.UIParent
local UISpecialFrames = _G.UISpecialFrames
local UnitClass = _G.UnitClass
local UnitExists = _G.UnitExists
local UnitGUID = _G.UnitGUID
local UnitGroupRolesAssigned = _G.UnitGroupRolesAssigned
local UnitIsUnit = _G.UnitIsUnit
local UnitName = _G.UnitName
local canaccessvalue = _G.canaccessvalue
local math_max = _G.math.max
local string_find = _G.string.find
local string_upper = _G.string.upper
local table_concat = _G.table.concat
local table_insert = _G.table.insert

local MISDIRECTION_SPELL_ID = 34477
local TRICKS_OF_THE_TRADE_SPELL_ID = 57934
local SMART_MISDIRECT_BINDING =
  "CLICK PleebDirect_SmartMisdirect:LeftButton"

local DIRECT_SPELLS = {
  HUNTER = {
    id = MISDIRECTION_SPELL_ID,
    name = "Misdirection",
    shortName = "MD",
    allowPet = true,
  },
  ROGUE = {
    id = TRICKS_OF_THE_TRADE_SPELL_ID,
    name = "Tricks of the Trade",
    shortName = "Tricks",
  },
}

local PANEL_BACKDROP = {
  bgFile = "Interface\\Buttons\\WHITE8X8",
  edgeFile = "Interface\\Buttons\\WHITE8X8",
  edgeSize = 1,
}

local COLORS = {
  accent = { 0.18, 0.55, 0.90, 1 },
  active = { 0.20, 1, 0.20, 1 },
  background = { 0.035, 0.035, 0.045, 0.96 },
  border = { 0.18, 0.18, 0.22, 1 },
  control = { 0.075, 0.075, 0.095, 0.92 },
  selected = { 0.18, 0.55, 0.90, 0.24 },
  text = { 0.92, 0.92, 0.94, 1 },
}

local SOURCE_LABELS = {
  PLEEB = "Priority target",
  RAID_MAINTANK = "Raid Main Tank",
  PARTY_TANK = "Party Tank",
  PET = "Pet",
}

local SmartMisdirectButton
local SmartMisdirectDirty = false
local SmartMisdirectResolvedUnit
local SmartMisdirectResolvedSource
local SmartMisdirectResolvedName
local SmartMisdirectResolvedClass
local SmartMisdirectSelector
local SmartMisdirectStatusFrame
local SmartMisdirectStatusLabel
local SmartMisdirectStatusName
local DirectSpell
local DirectSpellKnown = false
local SpellStateDirty = true
local RefreshSmartMisdirectSelector

_G.BINDING_HEADER_PLEEBDIRECT = "PleebDirect"
_G["BINDING_NAME_CLICK PleebDirect_SmartMisdirect:LeftButton"] =
  "Smart Misdirection / Tricks"

local function GetDirectSpell()
  local _, class = UnitClass("player")
  if not canaccessvalue(class) then
    return nil
  end

  return DIRECT_SPELLS[class]
end

local function IsAccessibleTrue(value)
  return canaccessvalue(value) and value == true
end

local function RefreshKnownSpell()
  if InCombatLockdown() then
    SpellStateDirty = true
    return false
  end

  DirectSpell = GetDirectSpell()
  local known = false
  if DirectSpell then
    known = C_SpellBook.IsSpellKnown(
      DirectSpell.id,
      Enum.SpellBookSpellBank.Player
    ) == true
  end

  local changed = DirectSpellKnown ~= known
  DirectSpellKnown = known
  SpellStateDirty = false
  return changed
end

local function IsAvailableSmartMisdirectUnit(unit)
  if not IsAccessibleTrue(UnitExists(unit)) then
    return false
  end

  local isPlayer = UnitIsUnit(unit, "player")
  return canaccessvalue(isPlayer) and isPlayer ~= true
end

local function GetAccessibleUnitIdentity(unit)
  local guid = UnitGUID(unit)
  local name = UnitName(unit)
  local _, class = UnitClass(unit)

  if not canaccessvalue(guid)
    or not canaccessvalue(name)
    or not canaccessvalue(class)
  then
    return nil
  end

  if not guid or not name then
    return nil
  end

  return guid, name, class
end

local function FindSelectedSmartMisdirectUnit()
  local selectedGUID = _G.PleebDirectDB.smartMisdirectTargetGUID
  if not selectedGUID then
    return nil
  end

  if IsInRaid() then
    for index = 1, GetNumGroupMembers() do
      local unit = "raid" .. index
      local guid = UnitGUID(unit)

      if canaccessvalue(guid)
        and guid == selectedGUID
        and IsAvailableSmartMisdirectUnit(unit)
      then
        return unit
      end
    end
  else
    for index = 1, GetNumSubgroupMembers() do
      local unit = "party" .. index
      local guid = UnitGUID(unit)

      if canaccessvalue(guid)
        and guid == selectedGUID
        and IsAvailableSmartMisdirectUnit(unit)
      then
        return unit
      end
    end
  end

  return nil
end

local function ResolveSmartMisdirectUnit()
  local selectedUnit = FindSelectedSmartMisdirectUnit()
  if selectedUnit then
    return selectedUnit, "PLEEB"
  end

  if IsInRaid() then
    for index = 1, GetNumGroupMembers() do
      local unit = "raid" .. index
      local mainTank = GetPartyAssignment("MAINTANK", unit)

      if IsAccessibleTrue(mainTank)
        and IsAvailableSmartMisdirectUnit(unit)
      then
        return unit, "RAID_MAINTANK"
      end
    end
  else
    for index = 1, GetNumSubgroupMembers() do
      local unit = "party" .. index
      local role = UnitGroupRolesAssigned(unit)

      if canaccessvalue(role)
        and role == "TANK"
        and IsAvailableSmartMisdirectUnit(unit)
      then
        return unit, "PARTY_TANK"
      end
    end
  end

  if DirectSpell.allowPet
    and IsAvailableSmartMisdirectUnit("pet")
  then
    return "pet", "PET"
  end

  return nil, nil
end

local function ClearSmartMisdirectResolution()
  SmartMisdirectResolvedUnit = nil
  SmartMisdirectResolvedSource = nil
  SmartMisdirectResolvedName = nil
  SmartMisdirectResolvedClass = nil
end

local function CacheSmartMisdirectResolution(unit, source)
  local name = UnitName(unit)
  if not canaccessvalue(name) then
    name = nil
  end

  local class
  if source ~= "PET" then
    local _, classToken = UnitClass(unit)
    if canaccessvalue(classToken) then
      class = classToken
    end
  end

  SmartMisdirectResolvedUnit = unit
  SmartMisdirectResolvedSource = source
  SmartMisdirectResolvedName = name
  SmartMisdirectResolvedClass = class
end

local function EnsureSmartMisdirectButton()
  if SmartMisdirectButton then
    return SmartMisdirectButton
  end

  local button = CreateFrame(
    "Button",
    "PleebDirect_SmartMisdirect",
    UIParent,
    "SecureActionButtonTemplate"
  )

  SmartMisdirectButton = button

  button:SetAttribute("typerelease", "spell")
  button:SetAttribute("pressAndHoldAction", "1")
  button:SetAttribute("allowVehicleTarget", false)
  button:SetAttribute("checkselfcast", false)
  button:SetAttribute("checkfocuscast", false)
  button:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
  button:SetSize(1, 1)
  button:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -20, 20)
  button:SetAlpha(0)
  button:Show()

  return button
end

local function DisableSmartMisdirection()
  if not SmartMisdirectButton then
    SmartMisdirectDirty = false
    ClearSmartMisdirectResolution()
    return
  end

  if InCombatLockdown() then
    SmartMisdirectDirty = true
    return
  end

  SmartMisdirectDirty = false
  SmartMisdirectButton:SetAttribute("type", nil)
  SmartMisdirectButton:SetAttribute("spell", nil)
  SmartMisdirectButton:SetAttribute("unit", nil)
  ClearSmartMisdirectResolution()
end

local function RefreshSmartMisdirection()
  if not DirectSpell or DirectSpellKnown ~= true then
    DisableSmartMisdirection()
    return
  end

  if InCombatLockdown() then
    SmartMisdirectDirty = true
    return
  end

  SmartMisdirectDirty = false

  local button = EnsureSmartMisdirectButton()
  local unit, source = ResolveSmartMisdirectUnit()

  if not unit then
    if SmartMisdirectResolvedUnit then
      button:SetAttribute("type", nil)
      button:SetAttribute("spell", nil)
      button:SetAttribute("unit", nil)
    end
    ClearSmartMisdirectResolution()
    return
  end

  if unit == SmartMisdirectResolvedUnit
    and source == SmartMisdirectResolvedSource
  then
    CacheSmartMisdirectResolution(unit, source)
    return
  end

  button:SetAttribute("type", "spell")
  button:SetAttribute("spell", DirectSpell.id)
  button:SetAttribute("unit", unit)
  CacheSmartMisdirectResolution(unit, source)
end

local function SetSmartMisdirectSelection(guid, name, class)
  if InCombatLockdown() then
    return
  end

  _G.PleebDirectDB.smartMisdirectTargetGUID = guid
  _G.PleebDirectDB.smartMisdirectTargetName = name
  _G.PleebDirectDB.smartMisdirectTargetClass = class

  RefreshSmartMisdirection()
  RefreshSmartMisdirectSelector()
end

local function GetSmartMisdirectSelectorUnits()
  local units = {}

  if IsInRaid() then
    for index = 1, GetNumGroupMembers() do
      local unit = "raid" .. index
      local isPlayer = UnitIsUnit(unit, "player")

      if canaccessvalue(isPlayer)
        and isPlayer ~= true
        and IsAccessibleTrue(UnitExists(unit))
      then
        local guid, name, class = GetAccessibleUnitIdentity(unit)
        if guid then
          table_insert(units, {
            guid = guid,
            name = name,
            class = class,
          })
        end
      end
    end
  else
    for index = 1, GetNumSubgroupMembers() do
      local unit = "party" .. index

      if IsAccessibleTrue(UnitExists(unit)) then
        local guid, name, class = GetAccessibleUnitIdentity(unit)
        if guid then
          table_insert(units, {
            guid = guid,
            name = name,
            class = class,
          })
        end
      end
    end
  end

  return units
end

local function SetBackdrop(frame, background, border)
  frame:SetBackdrop(PANEL_BACKDROP)
  frame:SetBackdropColor(
    background[1],
    background[2],
    background[3],
    background[4]
  )
  frame:SetBackdropBorderColor(
    border[1],
    border[2],
    border[3],
    border[4]
  )
end

local function SetSmartMisdirectTextColor(fontString, class, fallback)
  local color = class and RAID_CLASS_COLORS[class]
  if color then
    fontString:SetTextColor(color.r, color.g, color.b, 1)
    return
  end

  fontString:SetTextColor(
    fallback[1],
    fallback[2],
    fallback[3],
    fallback[4]
  )
end

local function ApplySmartMisdirectSelectorRow(row, selected)
  if selected then
    SetBackdrop(row, COLORS.selected, COLORS.accent)
    return
  end

  SetBackdrop(row, COLORS.control, COLORS.border)
end

local function GetSmartMisdirectBindingText()
  local bindingKeys = { GetBindingKey(SMART_MISDIRECT_BINDING) }
  local displayKeys = {}

  for index = 1, #bindingKeys do
    local key = bindingKeys[index]
    table_insert(displayKeys, GetBindingText(key) or key)
  end

  if #displayKeys == 0 then
    return "Not bound"
  end

  return table_concat(displayKeys, ", ")
end

local function NormalizeSmartMisdirectBindingKey(key)
  if not canaccessvalue(key)
    or key == "UNKNOWN"
    or key == "LSHIFT"
    or key == "RSHIFT"
    or key == "LCTRL"
    or key == "RCTRL"
    or key == "LALT"
    or key == "RALT"
    or key == "LMETA"
    or key == "RMETA"
  then
    return nil
  end

  if key == "LeftButton" or key == "RightButton" then
    return nil, "Left and right mouse buttons are reserved"
  end

  if key == "MiddleButton" then
    key = "BUTTON3"
  elseif string_find(key, "^Button%d+$") then
    key = string_upper(key)
  end

  local alt = IsAltKeyDown() and "ALT-" or ""
  local control = IsControlKeyDown() and "CTRL-" or ""
  local shift = IsShiftKeyDown() and "SHIFT-" or ""
  local meta = IsMetaKeyDown() and "META-" or ""

  return alt .. control .. shift .. meta .. key
end

local function RefreshSmartMisdirectBindingControl(frame)
  local button = frame.bindingButton

  if button.captureActive == true then
    SetBackdrop(button, COLORS.selected, COLORS.accent)

    if button.pendingKey then
      local keyText = GetBindingText(button.pendingKey)
        or button.pendingKey
      button.text:SetText("Press " .. keyText .. " again")
      button.help:SetText(
        "Replace " .. button.pendingActionName .. " · Esc cancels"
      )
      button.help:SetTextColor(1, 0.55, 0.15, 1)
    else
      button.text:SetText("Press a key...")
      button.help:SetText("Backspace clears · Esc cancels")
      button.help:SetTextColor(
        COLORS.text[1],
        COLORS.text[2],
        COLORS.text[3],
        0.72
      )
    end

    return
  end

  SetBackdrop(button, COLORS.control, COLORS.border)
  button.text:SetText(GetSmartMisdirectBindingText())
  button.help:SetText("Click to change")
  button.help:SetTextColor(
    COLORS.text[1],
    COLORS.text[2],
    COLORS.text[3],
    0.72
  )
end

local function StopSmartMisdirectBindingCapture(frame)
  local button = frame.bindingButton

  button.captureActive = false
  button.pendingKey = nil
  button.pendingActionName = nil
  button:EnableKeyboard(false)
  button:SetPropagateKeyboardInput(true)
  RefreshSmartMisdirectBindingControl(frame)
end

local function StartSmartMisdirectBindingCapture(frame)
  if InCombatLockdown() then
    return
  end

  local button = frame.bindingButton
  button.captureActive = true
  button.pendingKey = nil
  button.pendingActionName = nil
  button:EnableKeyboard(true)
  button:SetPropagateKeyboardInput(false)
  RefreshSmartMisdirectBindingControl(frame)
end

local function ClearSmartMisdirectBinding(frame)
  if InCombatLockdown() then
    return
  end

  local key = GetBindingKey(SMART_MISDIRECT_BINDING)
  while key do
    SetBinding(key)
    key = GetBindingKey(SMART_MISDIRECT_BINDING)
  end

  SaveBindings(GetCurrentBindingSet())
  StopSmartMisdirectBindingCapture(frame)
end

local function SetSmartMisdirectBinding(frame, key)
  if InCombatLockdown() then
    return
  end

  local button = frame.bindingButton
  local existingAction = GetBindingAction(key)
  if not canaccessvalue(existingAction) then
    return
  end

  if existingAction
    and existingAction ~= ""
    and existingAction ~= SMART_MISDIRECT_BINDING
  then
    if button.pendingKey ~= key then
      button.pendingKey = key
      button.pendingActionName =
        _G["BINDING_NAME_" .. existingAction] or existingAction
      RefreshSmartMisdirectBindingControl(frame)
      return
    end
  end

  local oldKey = GetBindingKey(SMART_MISDIRECT_BINDING)
  while oldKey do
    SetBinding(oldKey)
    oldKey = GetBindingKey(SMART_MISDIRECT_BINDING)
  end

  SetBindingClick(key, "PleebDirect_SmartMisdirect", "LeftButton")
  SaveBindings(GetCurrentBindingSet())
  StopSmartMisdirectBindingCapture(frame)
end

local function HandleSmartMisdirectBindingInput(frame, key)
  if not canaccessvalue(key) then
    return
  end

  local button = frame.bindingButton
  button:SetPropagateKeyboardInput(false)

  if key == "ESCAPE" then
    StopSmartMisdirectBindingCapture(frame)
    return
  end

  if key == "BACKSPACE" or key == "DELETE" then
    ClearSmartMisdirectBinding(frame)
    return
  end

  local normalizedKey, rejection = NormalizeSmartMisdirectBindingKey(key)
  if not normalizedKey then
    if rejection then
      button.help:SetText(rejection)
      button.help:SetTextColor(1, 0.30, 0.30, 1)
    end
    return
  end

  SetSmartMisdirectBinding(frame, normalizedKey)
end

local function EnsureSmartMisdirectSelectorRow(frame, index)
  local row = frame.rows[index]
  if row then
    return row
  end

  row = CreateFrame("Button", nil, frame.content, "BackdropTemplate")
  frame.rows[index] = row

  row:SetHeight(26)
  row:RegisterForClicks("LeftButtonUp")

  row.marker = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.marker:SetPoint("LEFT", row, "LEFT", 8, 0)
  row.marker:SetJustifyH("LEFT")

  row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.text:SetPoint("LEFT", row.marker, "RIGHT", 6, 0)
  row.text:SetPoint("RIGHT", row, "RIGHT", -8, 0)
  row.text:SetJustifyH("LEFT")
  row.text:SetWordWrap(false)

  local highlight = row:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetAllPoints(row)
  highlight:SetColorTexture(1, 1, 1, 0.05)
  row:SetHighlightTexture(highlight)

  row:SetScript("OnClick", function(self)
    if InCombatLockdown() then
      return
    end

    if self.isAutomatic == true then
      SetSmartMisdirectSelection(nil, nil, nil)
      return
    end

    SetSmartMisdirectSelection(
      self.targetGUID,
      self.targetName,
      self.targetClass
    )
  end)

  return row
end

local function EnsureSmartMisdirectSelector()
  if SmartMisdirectSelector then
    return SmartMisdirectSelector
  end

  local frame = CreateFrame(
    "Frame",
    "PleebDirect_SmartMisdirectSelector",
    UIParent,
    "BackdropTemplate"
  )

  SmartMisdirectSelector = frame

  frame:SetSize(370, 450)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("DIALOG")
  frame:SetToplevel(true)
  frame:SetClampedToScreen(true)
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:Hide()

  SetBackdrop(frame, COLORS.background, COLORS.border)

  local header = CreateFrame("Frame", nil, frame)
  frame.header = header
  header:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -2)
  header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
  header:SetHeight(32)
  header:EnableMouse(true)
  header:RegisterForDrag("LeftButton")
  header:SetScript("OnDragStart", function()
    if not InCombatLockdown() then
      frame:StartMoving()
    end
  end)
  header:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
  end)

  frame.title = header:CreateFontString(
    nil,
    "OVERLAY",
    "GameFontHighlightLarge"
  )
  frame.title:SetPoint("LEFT", header, "LEFT", 10, 0)
  frame.title:SetText("Smart " .. DirectSpell.name)

  frame.close = CreateFrame("Button", nil, header, "UIPanelCloseButton")
  frame.close:SetPoint("RIGHT", header, "RIGHT", -2, 0)
  frame.close:SetScript("OnClick", function()
    frame:Hide()
  end)

  frame.preferenceLabel = frame:CreateFontString(
    nil,
    "OVERLAY",
    "GameFontHighlight"
  )
  frame.preferenceLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -46)
  frame.preferenceLabel:SetText("Pleeb target:")

  frame.preferenceName = frame:CreateFontString(
    nil,
    "OVERLAY",
    "GameFontHighlight"
  )
  frame.preferenceName:SetPoint(
    "LEFT",
    frame.preferenceLabel,
    "RIGHT",
    5,
    0
  )

  frame.activeLabel = frame:CreateFontString(
    nil,
    "OVERLAY",
    "GameFontHighlight"
  )
  frame.activeLabel:SetPoint(
    "TOPLEFT",
    frame.preferenceLabel,
    "BOTTOMLEFT",
    0,
    -6
  )
  frame.activeLabel:SetText("Active:")

  frame.activeName = frame:CreateFontString(
    nil,
    "OVERLAY",
    "GameFontHighlight"
  )
  frame.activeName:SetPoint("LEFT", frame.activeLabel, "RIGHT", 5, 0)

  frame.sourceText = frame:CreateFontString(
    nil,
    "OVERLAY",
    "GameFontHighlightSmall"
  )
  frame.sourceText:SetPoint(
    "TOPLEFT",
    frame.activeLabel,
    "BOTTOMLEFT",
    0,
    -6
  )
  frame.sourceText:SetJustifyH("LEFT")

  frame.bindingLabel = frame:CreateFontString(
    nil,
    "OVERLAY",
    "GameFontHighlight"
  )
  frame.bindingLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -108)
  frame.bindingLabel:SetText("Keybind:")

  frame.bindingButton = CreateFrame(
    "Button",
    nil,
    frame,
    "BackdropTemplate"
  )
  frame.bindingButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 82, -101)
  frame.bindingButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, -101)
  frame.bindingButton:SetHeight(26)
  frame.bindingButton:RegisterForClicks("AnyUp")
  frame.bindingButton:EnableKeyboard(false)
  frame.bindingButton:EnableMouseWheel(true)

  frame.bindingButton.text = frame.bindingButton:CreateFontString(
    nil,
    "OVERLAY",
    "GameFontHighlight"
  )
  frame.bindingButton.text:SetPoint("CENTER")

  frame.bindingButton.help = frame.bindingButton:CreateFontString(
    nil,
    "OVERLAY",
    "GameFontHighlightSmall"
  )
  frame.bindingButton.help:SetPoint(
    "TOPLEFT",
    frame.bindingButton,
    "BOTTOMLEFT",
    0,
    -3
  )
  frame.bindingButton.help:SetPoint(
    "TOPRIGHT",
    frame.bindingButton,
    "BOTTOMRIGHT",
    0,
    -3
  )
  frame.bindingButton.help:SetJustifyH("LEFT")
  frame.bindingButton.help:SetWordWrap(false)

  local bindingHighlight = frame.bindingButton:CreateTexture(
    nil,
    "HIGHLIGHT"
  )
  bindingHighlight:SetAllPoints(frame.bindingButton)
  bindingHighlight:SetColorTexture(1, 1, 1, 0.05)
  frame.bindingButton:SetHighlightTexture(bindingHighlight)

  frame.bindingButton:SetScript("OnClick", function(self, mouseButton)
    if self.captureActive == true then
      HandleSmartMisdirectBindingInput(frame, mouseButton)
      return
    end

    StartSmartMisdirectBindingCapture(frame)
  end)
  frame.bindingButton:SetScript("OnKeyDown", function(_, key)
    HandleSmartMisdirectBindingInput(frame, key)
  end)
  frame.bindingButton:SetScript("OnMouseWheel", function(self, delta)
    if self.captureActive ~= true then
      return
    end

    if delta > 0 then
      HandleSmartMisdirectBindingInput(frame, "MOUSEWHEELUP")
    else
      HandleSmartMisdirectBindingInput(frame, "MOUSEWHEELDOWN")
    end
  end)

  RefreshSmartMisdirectBindingControl(frame)

  frame.scroll = CreateFrame(
    "ScrollFrame",
    nil,
    frame,
    "UIPanelScrollFrameTemplate"
  )
  frame.scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -150)
  frame.scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -32, 14)

  frame.content = CreateFrame("Frame", nil, frame.scroll)
  frame.content:SetSize(318, 1)
  frame.scroll:SetScrollChild(frame.content)
  frame.rows = {}

  frame:SetScript("OnHide", function()
    StopSmartMisdirectBindingCapture(frame)
  end)

  table_insert(UISpecialFrames, frame:GetName())

  return frame
end

RefreshSmartMisdirectSelector = function()
  local frame = EnsureSmartMisdirectSelector()
  RefreshSmartMisdirectBindingControl(frame)
  local selectedGUID = _G.PleebDirectDB.smartMisdirectTargetGUID
  local selectedName = _G.PleebDirectDB.smartMisdirectTargetName
  local selectedClass = _G.PleebDirectDB.smartMisdirectTargetClass

  if selectedName then
    frame.preferenceName:SetText(selectedName)
    SetSmartMisdirectTextColor(
      frame.preferenceName,
      selectedClass,
      COLORS.text
    )
  else
    frame.preferenceName:SetText("Automatic")
    SetSmartMisdirectTextColor(frame.preferenceName, nil, COLORS.text)
  end

  if SmartMisdirectResolvedName then
    frame.activeName:SetText(SmartMisdirectResolvedName)
    SetSmartMisdirectTextColor(
      frame.activeName,
      SmartMisdirectResolvedClass,
      COLORS.active
    )
    frame.sourceText:SetText(
      SOURCE_LABELS[SmartMisdirectResolvedSource] or "Smart target"
    )
  else
    frame.activeName:SetText("None")
    frame.activeName:SetTextColor(1, 0.20, 0.20, 1)
    frame.sourceText:SetText(
      "No usable Smart " .. DirectSpell.name .. " target"
    )
  end

  local units = GetSmartMisdirectSelectorUnits()
  local rowCount = #units + 1

  for index = 1, rowCount do
    local row = EnsureSmartMisdirectSelectorRow(frame, index)
    row:ClearAllPoints()
    row:SetPoint(
      "TOPLEFT",
      frame.content,
      "TOPLEFT",
      0,
      -((index - 1) * 30)
    )
    row:SetPoint(
      "TOPRIGHT",
      frame.content,
      "TOPRIGHT",
      0,
      -((index - 1) * 30)
    )
    row.isAutomatic = index == 1

    local selected
    if index == 1 then
      row.targetGUID = nil
      row.targetName = nil
      row.targetClass = nil
      row.text:SetText("Automatic")
      SetSmartMisdirectTextColor(row.text, nil, COLORS.text)
      selected = selectedGUID == nil
    else
      local data = units[index - 1]
      row.targetGUID = data.guid
      row.targetName = data.name
      row.targetClass = data.class
      row.text:SetText(data.name)
      SetSmartMisdirectTextColor(row.text, data.class, COLORS.text)
      selected = selectedGUID ~= nil and data.guid == selectedGUID
    end

    row.marker:SetText(selected and ">" or "")
    row:SetEnabled(InCombatLockdown() ~= true)
    row:SetAlpha(InCombatLockdown() and 0.55 or 1)
    ApplySmartMisdirectSelectorRow(row, selected)
    row:Show()
  end

  for index = rowCount + 1, #frame.rows do
    frame.rows[index]:Hide()
  end

  frame.content:SetHeight(math_max(1, rowCount * 30))
end

local function RefreshSmartMisdirectSelectorIfShown()
  if InCombatLockdown() then
    return
  end

  if SmartMisdirectSelector and SmartMisdirectSelector:IsShown() then
    RefreshSmartMisdirectSelector()
  end
end

local function ToggleSmartMisdirectSelector()
  if not GetDirectSpell() or InCombatLockdown() then
    return
  end

  local frame = EnsureSmartMisdirectSelector()
  if frame:IsShown() then
    frame:Hide()
    return
  end

  if SpellStateDirty and RefreshKnownSpell() then
    RefreshSmartMisdirection()
  end

  RefreshSmartMisdirectSelector()
  frame:Show()
end

local function EnsureSmartMisdirectStatusFrame()
  if SmartMisdirectStatusFrame then
    return SmartMisdirectStatusFrame
  end

  local frame = CreateFrame(
    "Frame",
    "PleebDirect_SmartMisdirectStatus",
    UIParent
  )

  SmartMisdirectStatusFrame = frame

  frame:SetSize(520, 44)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 140)
  frame:SetFrameStrata("HIGH")
  frame:SetFrameLevel(100)
  frame:EnableMouse(false)
  frame:Hide()

  SmartMisdirectStatusLabel = frame:CreateFontString(
    nil,
    "OVERLAY",
    "GameFontHighlightLarge"
  )
  SmartMisdirectStatusLabel:SetPoint("CENTER", frame, "CENTER", 0, 0)
  SmartMisdirectStatusLabel:SetJustifyH("CENTER")
  SmartMisdirectStatusLabel:SetFont(STANDARD_TEXT_FONT, 24, "OUTLINE")

  SmartMisdirectStatusName = frame:CreateFontString(
    nil,
    "OVERLAY",
    "GameFontHighlightLarge"
  )
  SmartMisdirectStatusName:SetJustifyH("LEFT")
  SmartMisdirectStatusName:SetFont(STANDARD_TEXT_FONT, 24, "OUTLINE")

  return frame
end

local function HideSmartMisdirectReadyCheckStatus()
  if SmartMisdirectStatusFrame then
    SmartMisdirectStatusFrame:Hide()
  end
end

local function ShowSmartMisdirectReadyCheckStatus()
  if DirectSpellKnown ~= true then
    HideSmartMisdirectReadyCheckStatus()
    return
  end

  local frame = EnsureSmartMisdirectStatusFrame()

  SmartMisdirectStatusLabel:ClearAllPoints()
  SmartMisdirectStatusName:ClearAllPoints()

  if SmartMisdirectResolvedUnit
    and SmartMisdirectResolvedName
  then
    SmartMisdirectStatusLabel:SetPoint(
      "RIGHT",
      frame,
      "CENTER",
      -3,
      0
    )
    SmartMisdirectStatusLabel:SetText(DirectSpell.shortName .. " Target:")
    SmartMisdirectStatusLabel:SetTextColor(0.20, 1, 0.20, 1)

    SmartMisdirectStatusName:SetPoint(
      "LEFT",
      frame,
      "CENTER",
      3,
      0
    )
    SmartMisdirectStatusName:SetText(SmartMisdirectResolvedName)
    SetSmartMisdirectTextColor(
      SmartMisdirectStatusName,
      SmartMisdirectResolvedClass,
      COLORS.active
    )
    SmartMisdirectStatusName:Show()
  else
    SmartMisdirectStatusLabel:SetPoint("CENTER", frame, "CENTER", 0, 0)
    SmartMisdirectStatusLabel:SetText(
      "NO " .. string_upper(DirectSpell.shortName) .. " TARGET"
    )
    SmartMisdirectStatusLabel:SetTextColor(1, 0.15, 0.15, 1)
    SmartMisdirectStatusName:SetText("")
    SmartMisdirectStatusName:Hide()
  end

  frame:Show()
end

local function RegisterDirectEvents(frame)
  frame:RegisterEvent("GROUP_ROSTER_UPDATE")
  frame:RegisterEvent("PLAYER_ENTERING_WORLD")
  frame:RegisterEvent("PLAYER_REGEN_DISABLED")
  frame:RegisterEvent("PLAYER_REGEN_ENABLED")
  frame:RegisterEvent("PLAYER_ROLES_ASSIGNED")
  frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
  frame:RegisterEvent("PLAYER_TALENT_UPDATE")
  frame:RegisterEvent("READY_CHECK")
  frame:RegisterEvent("READY_CHECK_FINISHED")
  frame:RegisterEvent("ROLE_CHANGED_INFORM")
  frame:RegisterEvent("SPELLS_CHANGED")
  frame:RegisterEvent("UNIT_PET")
  frame:RegisterEvent("UPDATE_BINDINGS")
end

local function HandleDirectEvent(event, unit)
  if event == "UPDATE_BINDINGS" then
    RefreshSmartMisdirectSelectorIfShown()
    return
  end

  if event == "UNIT_PET" and unit ~= "player" then
    return
  end

  if event == "READY_CHECK_FINISHED" then
    HideSmartMisdirectReadyCheckStatus()
    return
  end

  if event == "PLAYER_REGEN_DISABLED" then
    if SmartMisdirectSelector then
      SmartMisdirectSelector:Hide()
    end
    return
  end

  if event == "READY_CHECK" then
    ShowSmartMisdirectReadyCheckStatus()
    return
  end

  if event == "PLAYER_REGEN_ENABLED" then
    local spellChanged = false
    if SpellStateDirty then
      spellChanged = RefreshKnownSpell()
    end

    if SmartMisdirectDirty or spellChanged then
      RefreshSmartMisdirection()
    end

    RefreshSmartMisdirectSelectorIfShown()
    return
  end

  if event == "PLAYER_ENTERING_WORLD" then
    HideSmartMisdirectReadyCheckStatus()
    RefreshKnownSpell()
    RefreshSmartMisdirection()
    RefreshSmartMisdirectSelectorIfShown()
    return
  end

  if event == "PLAYER_TALENT_UPDATE"
    or event == "PLAYER_SPECIALIZATION_CHANGED"
    or event == "SPELLS_CHANGED"
  then
    if RefreshKnownSpell() then
      RefreshSmartMisdirection()
    end
    RefreshSmartMisdirectSelectorIfShown()
    return
  end

  if event == "GROUP_ROSTER_UPDATE"
    or event == "PLAYER_ROLES_ASSIGNED"
    or event == "ROLE_CHANGED_INFORM"
    or event == "UNIT_PET"
  then
    RefreshSmartMisdirection()
    RefreshSmartMisdirectSelectorIfShown()
  end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(self, event, unit)
  if event == "PLAYER_LOGIN" then
    self:UnregisterEvent("PLAYER_LOGIN")
    _G.PleebDirectDB = _G.PleebDirectDB or {}

    if not GetDirectSpell() then
      return
    end

    RegisterDirectEvents(self)
    RefreshKnownSpell()
    RefreshSmartMisdirection()
    return
  end

  HandleDirectEvent(event, unit)
end)

_G.SLASH_PLEEBDIRECT1 = "/pd"
_G.SLASH_PLEEBDIRECT2 = "/pleebdirect"
_G.SLASH_PLEEBDIRECT3 = "/md"
_G.SlashCmdList.PLEEBDIRECT = ToggleSmartMisdirectSelector
