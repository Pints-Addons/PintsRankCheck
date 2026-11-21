-- Pint's Rank Check: when you learn a new rank of a spell, the old rank stays on your action bars. This finds every
-- action-bar button holding a lower rank than the best one you know and offers to swap them, all at once or one by one.
-- Buttons you keep on a low rank on purpose (a cheap heal, say) can be marked "Keep" and are left alone from then on.
-- Classic Era and WoW Forever (the modern game client: its spellbook calls moved to C_SpellBook / C_Spell).
local ADDON = ...
local db
local MODERN = (C_SpellBook and C_SpellBook.GetSpellBookItemInfo and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookSkillLineInfo) and true or false
local SLOTS = MODERN and 180 or 120

local function Say(msg) print("|cffd4a24cRank Check|r: " .. msg) end
local function SpellName(id)
  if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
  return (GetSpellInfo(id))
end
local function SpellIcon(id)
  if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
  return GetSpellTexture and GetSpellTexture(id) or select(3, GetSpellInfo(id))
end
local function Subtext(id)
  if C_Spell and C_Spell.GetSpellSubtext then return C_Spell.GetSpellSubtext(id) end
  return GetSpellSubtext and GetSpellSubtext(id)
end
local function RankOf(sub) return tonumber((sub or ""):match("(%d+)")) end

-- best rank you know of each spell, by name: { name = { id = spellID, rank = n } }
local function BestRanks()
  local best = {}
  local function consider(name, sub, id)
    if not (name and id) then return end
    local r = RankOf(sub)
    if not r then return end                       -- (spells without ranks aren't our business)
    local b = best[name]
    if not b or r > b.rank then best[name] = { id = id, rank = r } end
  end
  if MODERN then
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
    for line = 1, C_SpellBook.GetNumSpellBookSkillLines() or 0 do
      local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
      if info and not info.shouldHide then
        for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
          local it = C_SpellBook.GetSpellBookItemInfo(i, bank)
          local isSpell = it and (it.itemType == (Enum.SpellBookItemType and Enum.SpellBookItemType.Spell or 1))
          if isSpell and it.spellID and not it.isPassive then consider(it.name, it.subName, it.spellID) end
        end
      end
    end
  else
    for t = 1, GetNumSpellTabs() do
      local _, _, offset, n = GetSpellTabInfo(t)
      for i = offset + 1, offset + n do
        local kind, id = GetSpellBookItemInfo(i, BOOKTYPE_SPELL or "spell")
        if kind == "SPELL" and id then
          local name, sub = GetSpellBookItemName(i, BOOKTYPE_SPELL or "spell")
          consider(name, sub, id)
        end
      end
    end
  end
  return best
end

-- every action-bar button holding a lower rank than the best you know
local function Scan()
  local best, found = BestRanks(), {}
  for slot = 1, SLOTS do
    local kind, id = GetActionInfo(slot)
    if kind == "spell" and id then
      local name = SpellName(id)
      local b = name and best[name]
      local r = RankOf(Subtext(id))
      if b and r and r < b.rank and b.id ~= id then
        local keep = db.keep[slot] and db.keep[slot] == id
        found[#found + 1] = { slot = slot, old = id, new = b.id, name = name, from = r, to = b.rank, keep = keep }
      end
    end
  end
  return found
end

local function Replace(e)
  if InCombatLockdown() then return false end
  local pickup = (C_Spell and C_Spell.PickupSpell) or PickupSpell
  ClearCursor()
  pickup(e.new)
  if not GetCursorInfo() then return false end
  PlaceAction(e.slot)
  ClearCursor()
  local _, now = GetActionInfo(e.slot)
  return now == e.new
end

---------------------------------------------------------------- the window
local win, rows = nil, {}
local list = {}
local Refresh
local function BarName(slot)
  local bar = math.floor((slot - 1) / 12) + 1
  return ("Bar %d, button %d"):format(bar, (slot - 1) % 12 + 1)
end
local function Build()
  win = CreateFrame("Frame", "PintsRankCheckFrame", UIParent, "BackdropTemplate")
  win:SetSize(420, 120); win:SetPoint("CENTER", 0, 120); win:SetFrameStrata("DIALOG")
  win:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
    tile = true, tileSize = 32, edgeSize = 24, insets = { left = 6, right = 6, top = 6, bottom = 6 } })
  win:EnableMouse(true); win:SetMovable(true); win:RegisterForDrag("LeftButton"); win:SetClampedToScreen(true)
  win:SetScript("OnDragStart", win.StartMoving); win:SetScript("OnDragStop", win.StopMovingOrSizing)
  local t = win:CreateFontString(nil, "OVERLAY"); t:SetFont("Fonts\\MORPHEUS.TTF", 18, ""); t:SetTextColor(1, 0.82, 0.35)
  t:SetPoint("TOPLEFT", 16, -14); t:SetText("New spell ranks to put on your bars")
  local close = CreateFrame("Button", nil, win, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", -2, -2)
  win.all = CreateFrame("Button", nil, win, "UIPanelButtonTemplate"); win.all:SetSize(150, 24); win.all:SetPoint("BOTTOMLEFT", 16, 14)
  win.all:SetText("Replace all")
  win.all:SetScript("OnClick", function()
    if InCombatLockdown() then Say("can't change your action bars in combat - try again after."); return end
    local n = 0
    for _, e in ipairs(list) do if not e.keep and Replace(e) then n = n + 1 end end
    Say(("%d button%s now on the new rank."):format(n, n == 1 and "" or "s"))
    Refresh(true)
  end)
  win.later = CreateFrame("Button", nil, win, "UIPanelButtonTemplate"); win.later:SetSize(100, 24); win.later:SetPoint("LEFT", win.all, "RIGHT", 8, 0)
  win.later:SetText("Not now"); win.later:SetScript("OnClick", function() win:Hide() end)
  win.note = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); win.note:SetPoint("BOTTOMRIGHT", -16, 20)
  win.note:SetText("Tick Keep to leave a button on its rank")
  win:Hide()
end
local function Row(i)
  local r = rows[i]
  if r then return r end
  r = CreateFrame("Frame", nil, win); r:SetSize(388, 26); r:SetPoint("TOPLEFT", 16, -44 - (i - 1) * 28)
  r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(22, 22); r.icon:SetPoint("LEFT")
  r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 6); r.text:SetJustifyH("LEFT")
  r.sub = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); r.sub:SetPoint("LEFT", r.icon, "RIGHT", 6, -7)
  r.swap = CreateFrame("Button", nil, r, "UIPanelButtonTemplate"); r.swap:SetSize(64, 20); r.swap:SetPoint("RIGHT", -70, 0); r.swap:SetText("Swap")
  r.keep = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate"); r.keep:SetSize(22, 22); r.keep:SetPoint("RIGHT", -40, 0)
  r.keepT = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); r.keepT:SetPoint("LEFT", r.keep, "RIGHT", 0, 0); r.keepT:SetText("Keep")
  r.swap:SetScript("OnClick", function(self)
    local e = self:GetParent().e
    if InCombatLockdown() then Say("can't change your action bars in combat."); return end
    if Replace(e) then Refresh(true) end
  end)
  r.keep:SetScript("OnClick", function(self)
    local e = self:GetParent().e
    db.keep[e.slot] = self:GetChecked() and e.old or nil
    Refresh(true)
  end)
  rows[i] = r
  return r
end
function Refresh(keepOpen)
  if not win then Build() end
  list = Scan()
  local pending = 0
  for _, e in ipairs(list) do if not e.keep then pending = pending + 1 end end
  for i, e in ipairs(list) do
    local r = Row(i); r.e = e
    r.icon:SetTexture(SpellIcon(e.new))
    r.text:SetText(("%s  |cffa0a0a0Rank %d|r  ->  |cff40ff40Rank %d|r"):format(e.name, e.from, e.to))
    r.sub:SetText(BarName(e.slot) .. (e.keep and "  - kept on purpose" or ""))
    r.keep:SetChecked(e.keep); r.swap:SetEnabled(not e.keep); r.icon:SetDesaturated(e.keep)
    r:Show()
  end
  for i = #list + 1, #rows do rows[i]:Hide() end
  win:SetHeight(100 + math.max(1, #list) * 28)
  win.all:SetEnabled(pending > 0)
  if pending == 0 and not keepOpen then win:Hide(); return 0 end
  if #list == 0 then win:Hide(); return 0 end
  win:Show()
  return pending
end

---------------------------------------------------------------- when to look
local pend
local function Check(quiet)
  if InCombatLockdown() then pend = true; if not quiet then Say("in combat - I'll look once the fight is over.") end return end
  if not db then PintsRankCheckDB = PintsRankCheckDB or {}; db = PintsRankCheckDB; db.keep = db.keep or {} end
  local ok, n = pcall(Refresh, false)
  if not ok then Say("couldn't read your spells or bars: " .. tostring(n)); return end
  if not quiet and n == 0 then Say("every spell on your bars is the best rank you know.") end
end
local ev = CreateFrame("Frame")
-- (the modern client has dropped some of these events: register each only if the game knows it)
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "LEARNED_SPELL_IN_TAB", "LEARNED_SPELL_IN_SKILL_LINE", "SPELLS_CHANGED",
  "PLAYER_REGEN_ENABLED", "ACTIONBAR_SLOT_CHANGED",
  -- switching spec with dual spec swaps your bars: look them over again
  "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_SPECIALIZATION_CHANGED", "ACTIVE_PLAYER_SPECIALIZATION_CHANGED" }) do
  if not C_EventUtils or not C_EventUtils.IsEventValid or C_EventUtils.IsEventValid(e) then pcall(ev.RegisterEvent, ev, e) end
end
local timer
ev:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 == ADDON then PintsRankCheckDB = PintsRankCheckDB or {}; db = PintsRankCheckDB; db.keep = db.keep or {} end
    return
  end
  if not db then return end
  if event == "PLAYER_REGEN_ENABLED" then if pend then pend = nil; Check(true) end return end
  if event == "ACTIONBAR_SLOT_CHANGED" then if win and win:IsShown() and not InCombatLockdown() then Refresh(true) end return end
  -- (spell learning fires several events at once: look once, a moment later)
  if timer then return end
  timer = true
  local wait = (event == "PLAYER_LOGIN" and 4) or ((event:find("TALENT") or event:find("SPECIALIZATION")) and 2.5) or 1.5
  C_Timer.After(wait, function() timer = nil; Check(true) end)
end)

SLASH_PINTSRANKCHECK1 = "/ranks"; SLASH_PINTSRANKCHECK2 = "/rankcheck"
SlashCmdList.PINTSRANKCHECK = function(msg)
  msg = (msg or ""):lower()
  if not db then PintsRankCheckDB = PintsRankCheckDB or {}; db = PintsRankCheckDB; db.keep = db.keep or {} end
  if msg == "reset" then db.keep = {}; Say("forgot every Keep - all low ranks will be offered again."); Check(false); return end
  if msg == "debug" then
    local ok, best = pcall(BestRanks)
    if not ok then Say("spellbook read failed: " .. tostring(best)); return end
    local n = 0; for _ in pairs(best) do n = n + 1 end
    local spells, ranked = 0, 0
    for slot = 1, SLOTS do
      local kind, id = GetActionInfo(slot)
      if kind == "spell" and id then spells = spells + 1; if RankOf(Subtext(id)) then ranked = ranked + 1 end end
    end
    Say(("%s client - %d ranked spells in your spellbook; %d spells on your bars, %d of them with a rank."):format(MODERN and "modern" or "Classic", n, spells, ranked))
    return
  end
  Check(false)
end
