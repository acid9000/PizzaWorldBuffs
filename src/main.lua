PizzaWorldBuffs = CreateFrame('Frame', 'PizzaWorldBuffs', UIParent)
local PWB = PizzaWorldBuffs
PWB.abbrev = 'PWB'
PWB.abbrevDmf = 'PWB_DMF'
PWB.abbrevTents = 'PWB_T'

PWB.Colors = {
  primary = '|cffa050ff',
  secondary = '|cffffffff',

  alliance = '|cff0070dd',
  horde = '|cffc41e3a',
  white = '|cffffffff',
  grey = '|cffaaaaaa',
  green = '|cff00ff98',
  orange = '|cffff7c0a',
  red = '|cffc41e3a',
}

local dmfNpcNames = {
  'Flik',
  'Sayge',
  'Burth',
  'Lhara',
  'Morja',
  'Jubjub',
  'Chronos',
  'Felinni',
  'Rinling',
  'Sylannia',
  'Hornsley',
  'Kerri Hicks',
  'Flik\'s Frog',
  'Yebb Neblegear',
  'Silas Darkmoon',
  'Selina Dourman',
  'Khaz Modan Ram',
  'Pygmy Cockatrice',
  'Gelvas Grimegate',
  'Stamp Thunderhorn',
  'Maxima Blastenheimer',
  'Professor Thaddeus Paleo',
}

PWB.env = {}
setmetatable(PWB.env, { __index = function (self, key)
  if key == 'T' then return end
  return getfenv(0)[key]
end})
function PWB:GetEnv()
  if not PWB.env.T then
    local locale = GetLocale() or 'enUS'
    PWB.env.T = setmetatable((PWB_translations or {})[locale] or {}, {
      __index = function(tbl, key)
        local value = tostring(key)
        rawset(tbl, key, value)
        return value
      end
    })
  end
  PWB.env._G = getfenv(0)
  return PWB.env
end
setfenv(1, PWB:GetEnv())

PWB.Bosses = {
  O = T['Onyxia'],
  N = T['Nefarian'],
}

PWB.DmfLocations = {
  E = T['Elwynn Forest'],
  M = T['Mulgore'],
}

function PWB:Print(msg, withPrefix)
  local prefix = withPrefix == false and '' or PWB.Colors.primary .. 'Pizza' .. PWB.Colors.secondary .. 'WorldBuffs:|r '
  DEFAULT_CHAT_FRAME:AddMessage(prefix .. msg)
end

function PWB:PrintClean(msg)
  PWB:Print(msg, false)
end

local timerStrs = {}
PWB:RegisterEvent('ADDON_LOADED')
PWB:RegisterEvent('PLAYER_ENTERING_WORLD')
PWB:RegisterEvent('CHAT_MSG_ADDON')
PWB:RegisterEvent('CHAT_MSG_CHANNEL')
PWB:RegisterEvent('CHAT_MSG_MONSTER_YELL')
PWB:RegisterEvent('CHAT_MSG_WHISPER')
PWB:RegisterEvent('CHAT_MSG_SYSTEM')
PWB:RegisterEvent('UPDATE_MOUSEOVER_UNIT')
PWB:SetScript('OnEvent', function ()
  if event == 'ADDON_LOADED' and arg1 == 'PizzaWorldBuffs' then
    -- Initialize config with default values if necessary
    PWB.config.init()

    if PWB_config.autoLogout then
      PWB_config.autoLogout = false
      PWB:Print(T['Auto-logout disabled automatically. To enable it again, use /wb logout 1'])
    end

    if PWB_config.autoExit then
      PWB_config.autoExit = false
      PWB:Print(T['Auto-exit disabled automatically. To enable it again, use /wb exit 1'])
    end
  end

  if event == 'PLAYER_ENTERING_WORLD' then
    -- Store player's name & faction ('A' or 'H') for future use
    PWB.me = UnitName('player')
    PWB.myFaction = string.sub(UnitFactionGroup('player'), 1, 1)
    -- Workaround for Turtle WoW's Spanish localization
    if PWB.myFaction ~= "A" and PWB.myFaction ~= "H" then
        local _, raceEn = UnitRace('player')
        local hordeRaces = {
            Orc = true,
            Scourge = true,
            Troll = true,
            Tauren = true,
            Goblin = true,
        }
        PWB.myFaction = hordeRaces[raceEn] and "H" or "A"
    end
    PWB.isOnKalimdor = GetCurrentMapContinent() == 1

    -- If we don't have any timers or we still have timers in a deprecated format, clear/initialize them first.
    if not PWB.utils.hasTimers() or PWB.utils.hasDeprecatedTimerFormat() then
      PWB.core.clearAllTimers()
    end

    -- Initialize publish delay if we have timers but haven't set a publish time yet
    if PWB.utils.hasTimers() and not PWB.nextPublishAt then
      PWB.core.resetPublishDelay()
    end

    -- Trigger delayed joining of the PWB chat channel
    PWB.channelJoinDelay:Show()
    
    -- Request server time from .server info command with a small delay
    -- Use a frame to delay this slightly to ensure the world is ready
    if not PWB.serverTimeDelay then
      PWB.serverTimeDelay = CreateFrame('Frame', 'PizzaWorldBuffsServerTimeDelay', UIParent)
      PWB.serverTimeDelay:Hide()
      PWB.serverTimeDelay:SetScript('OnShow', function()
        this.startTime = GetTime()
      end)
      PWB.serverTimeDelay:SetScript('OnUpdate', function()
        local delay = 0.5 -- 0.5 second delay
        local gt = GetTime()
        local st = this.startTime + delay
        if gt >= st then
          SendChatMessage('.server info', 'SAY')
          PWB.serverTimeDelay:Hide()
        end
      end)
    end
    PWB.serverTimeDelay:Show()
  end

  if event == 'CHAT_MSG_MONSTER_YELL' then
    local boss, faction = PWB.core.parseMonsterYell(arg1)
    if boss and faction then
      -- Request fresh server time when witnessing a buff to get accurate time
      SendChatMessage('.server info', 'SAY')
      -- Store that we're waiting for server time to create a timer
      PWB.pendingTimerCreation = { boss = boss, faction = faction, requestedAt = time() }
      return
    end
  end

  if event == 'CHAT_MSG_SYSTEM' then
    -- Always parse server time first - this stores it regardless of pending timers
    local h, m = PWB.utils.parseServerTime(arg1)
    
    if h and m then
      if PWB_config.log then
        PWB:Print('Server time parsed and stored: ' .. string.format("%02d:%02d", h, m))
      end
      -- Check if we're waiting to create a timer and just got server time
      if PWB.pendingTimerCreation then
        -- We just got fresh server time, use it for the pending timer
        local boss = PWB.pendingTimerCreation.boss
        local faction = PWB.pendingTimerCreation.faction
        local serverH, serverM = h, m
        local timerH, timerM = PWB.utils.hoursFromNow(2)
        if timerH and timerM then
          PWB.core.setTimer(faction, boss, timerH, timerM, PWB.me, PWB.me, serverH, serverM)
          
          if PWB_config.autoLogout or PWB_config.autoExit then
            local message = PWB_config.autoExit and T['About to receive buff and auto-exit is enabled. Will exit game in 1 minute.'] or T['About to receive buff and auto-logout is enabled. Will log out in 1 minute.']
            PWB:Print(message)
            PWB.logoutAt = time() + 60
          end
        end
        PWB.pendingTimerCreation = nil
        return
      end
      
      -- Check if we're waiting to force create a timer
      if PWB.pendingForceTimer then
        local faction = PWB.pendingForceTimer.faction
        local boss = PWB.pendingForceTimer.boss
        local serverH, serverM = h, m
        local timerH, timerM = PWB.utils.hoursFromNow(2)
        if timerH and timerM then
          PWB.core.setTimer(faction, boss, timerH, timerM, PWB.me, PWB.me, serverH, serverM)
          
          local timeStr = string.format("%02d:%02d", timerH, timerM)
          local serverTimeStr = string.format("%02d:%02d", serverH, serverM)
          PWB:Print('Forced timer created: Alliance Onyxia at ' .. timeStr .. ' (witnessed at server time ' .. serverTimeStr .. ')')
        end
        PWB.pendingForceTimer = nil
        return
      end
      
      -- Normal case: server time parsed and stored (on login/reload)
      -- parseServerTime() already stored it in PWB.serverTime above
    end
  end

  if event == 'CHAT_MSG_CHANNEL' and arg2 ~= UnitName('player') then
    local _, _, source = string.find(arg4, '(%d+)%.')
    local channelName

    if source then
      _, channelName = GetChannelName(source)
    end

    if string.lower(channelName) == string.lower(PWB.channelName) then
      local _, _, addonName, remoteVersion, msg = string.find(arg1, '(.*)%:(.*)%:(.*)')
      if addonName == PWB.abbrev then
        -- Ignore timers from players with pre-1.1.4 versions that contain a bug where it sometimes
        -- shares invalid/expired timers with everyone.
        if tonumber(remoteVersion) < 10104 then
          return
        end

        -- Only reset publish delay if versions match
        if tonumber(remoteVersion) == PWB.utils.getVersionNumber() then
          PWB.core.resetPublishDelay()
        end

        timerStrs[1], timerStrs[2], timerStrs[3], timerStrs[4] = PWB.utils.strSplit(msg, ';')
        for _, timerStr in next, timerStrs do
          local faction, boss, h, m, witness, witnessServerH, witnessServerM = PWB.core.decode(timerStr)
          if not faction or not boss or not h or not m or not witness then return end

          -- Ignore timers without server time (old format)
          if not witnessServerH or not witnessServerM then
            return
          end

          local receivedFrom = arg2
          
          -- Check for server time drift and refresh if needed
          PWB.utils.checkServerTimeDrift(witnessServerH, witnessServerM)
          
          -- Log if received timer uses new format (with server time)
          if PWB_config.log and witnessServerH and witnessServerM then
            local currentH, currentM = PWB.utils.getServerTime()
            local senderTimeStr = string.format("%02d:%02d", witnessServerH, witnessServerM)
            local currentTimeStr = string.format("%02d:%02d", currentH, currentM)
            PWB:Print('Received timer from ' .. receivedFrom .. ' (their current time: ' .. senderTimeStr .. ', your current time: ' .. currentTimeStr .. '): ' .. timerStr)
          end
          
          if PWB.core.shouldAcceptNewTimer(faction, boss, h, m, witness, receivedFrom, witnessServerH, witnessServerM) then
            PWB.core.setTimer(faction, boss, h, m, witness, receivedFrom, witnessServerH, witnessServerM)
            
            -- Log zu Chat wenn Timer empfangen wurde (wenn Logging aktiviert ist)
            if PWB_config.log then
              local factionName = faction == 'A' and 'Alliance' or 'Horde'
              local bossName = boss == 'O' and 'Onyxia' or 'Nefarian'
              local timeStr = string.format("%02d:%02d", h, m)
              PWB:Print(factionName .. ' ' .. bossName .. ' timer received: ' .. timeStr .. ' (from ' .. receivedFrom .. ')')
            end
          end
        end

        if tonumber(remoteVersion) > PWB.utils.getVersionNumber() and not PWB.updateNotified then
          PWB:Print(T['New version available! https://github.com/Pizzahawaiii/PizzaWorldBuffs'])
          PWB.updateNotified = true
        end
      elseif addonName == PWB.abbrevDmf then
        -- Only reset publish delay if versions match
        if tonumber(remoteVersion) == PWB.utils.getVersionNumber() then
          PWB.core.resetPublishDelay()
        end
        local location, seenAt, witness = PWB.core.decodeDmf(msg)
        if PWB.core.shouldAcceptDmfLocation(seenAt, tonumber(remoteVersion)) then
          PWB.core.setDmfLocation(location, seenAt, witness)
        end
      end
    end
  end

  if event == 'CHAT_MSG_WHISPER' and string.find(UnitName('player'), 'Pizza') then
    local msg, from = string.lower(string.gsub(string.gsub(arg1, '?', ''), '!', '')), arg2
    if msg == 'ony when' or msg == 'nef when' or msg == 'buff when' or msg == 'buf when' or msg == 'head when' then
      local aOnyText = PWB.share.getText('timer', { faction = 'A', boss = 'O' })
      local aNefText = PWB.share.getText('timer', { faction = 'A', boss = 'N' })
      local hOnyText = PWB.share.getText('timer', { faction = 'H', boss = 'O' })
      local hNefText = PWB.share.getText('timer', { faction = 'H', boss = 'N' })
      SendChatMessage(aOnyText, 'WHISPER', nil, from)
      SendChatMessage(aNefText, 'WHISPER', nil, from)
      SendChatMessage(hOnyText, 'WHISPER', nil, from)
      SendChatMessage(hNefText, 'WHISPER', nil, from)
    elseif msg == 'dmf where' or msg == 'dmf' or msg == 'dmf loc' or msg == 'dmf location' then
      local dmfText = PWB.share.getText('dmf')
      SendChatMessage(dmfText, 'WHISPER', nil, from)
    end
  end

  if event == 'UPDATE_MOUSEOVER_UNIT' and not UnitIsPlayer('mouseover') and PWB.utils.contains(dmfNpcNames, UnitName('mouseover')) then
    local zone = GetZoneText()
    if zone == T['Elwynn Forest'] or zone == T['Mulgore'] then
      PWB.core.setDmfLocation(string.sub(zone, 1, 1), time(), PWB.me)
    end
  end
end)

PWB:SetScript('OnUpdate', function ()
  -- Throttle this function so it doesn't run on every frame render
  if (this.tick or 1) > GetTime() then return else this.tick = GetTime() + 1 end

  -- Timer-Bereinigung deaktiviert - Timer werden immer behalten
  -- PWB.core.clearExpiredTimers()

  if (PWB_config.autoLogout or PWB_config.autoExit) and PWB.logoutAt and time() >= PWB.logoutAt then
    PWB.logoutAt = nil
    if PWB_config.autoLogout then
      PWB:Print(T['Logging out...'])
      Logout()
    else
      PWB:Print(T['Exiting game...'])
      Quit()
    end
  elseif PWB.core.shouldPublish() then
    PWB.core.publishAll()
  end
end)
