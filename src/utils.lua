local PWB = PizzaWorldBuffs
PWB.utils = {}

setfenv(1, PWB:GetEnv())

-- Convert a time (duration) table to a number of minutes.
function PWB.utils.toMinutes(h, m)
  return h * 60 + m
end

-- Convert a number of minutes to a time table representing the same duration.
function PWB.utils.toTime(minutes)
  local m = math.mod(minutes, 60)
  local h = (minutes - m) / 60
  return h, m
end

function PWB.utils.isTipsie()
  local name = UnitName('player')
  local len = string.len(name)
  if len < 8 then return false end
  return string.sub(name, len - 5, len) == 'tipsie'
end

function PWB.utils.toRoughTimeString(seconds)
  if seconds < 60 then return seconds .. 's' end

  local minutes = seconds / 60
  if minutes < 60 then return math.floor(minutes) .. 'm' end

  local hours = minutes / 60
  if hours < 24 then return '~ ' .. math.floor(hours) .. 'h' end

  local days = hours / 24
  return '~ ' .. math.floor(days + 0.5) .. 'd'
end

-- Convert a time table to string in Hh Mm format, e.g. 1h 52m.
function PWB.utils.toString(h, m)
  if not h and not m then return T['N/A'] end
  return (h > 0 and h .. 'h ' or '') .. m .. 'm'
end

-- Get a time table representing a certain number of hours from now.
function PWB.utils.hoursFromNow(hours)
  local h, m = PWB.utils.getServerTime()
  if not h or not m then
    return nil, nil
  end
  h = math.mod(h + hours, 24)
  return h, m
end

-- Storage for server time from .server info command
PWB.serverTime = nil
PWB.serverTimeReceivedAt = nil
PWB.serverTimeLastRefresh = nil
PWB.serverTimeDriftSamples = {} -- Track received server times to detect drift

-- Parse server time from .server info output
-- Format: "Server Time: Sun, 07.12.2025 14:47:24"
function PWB.utils.parseServerTime(msg)
  local _, _, hStr, mStr, sStr = string.find(msg, 'Server Time:%s*[^,]+,%s+[%d%.]+%s+(%d%d):(%d%d):(%d%d)')
  if not hStr or not mStr or not sStr then return nil, nil end
  
  local h = tonumber(hStr)
  local m = tonumber(mStr)
  local s = tonumber(sStr)
  
  if h and m and s then
    PWB.serverTime = { h = h, m = m, s = s }
    PWB.serverTimeReceivedAt = time()
    PWB.serverTimeLastRefresh = time()
    return h, m
  end
  
  return nil, nil
end

-- Get current server time, using ONLY .server info time (no fallback to GetGameTime())
-- Returns nil, nil if server time from .server info is not available
function PWB.utils.getServerTime()
  -- Only use server time from .server info, never use GetGameTime()
  if PWB.serverTime and PWB.serverTimeReceivedAt then
    -- Calculate elapsed time using stored server time and seconds
    local elapsed = time() - PWB.serverTimeReceivedAt
    local elapsedSeconds = math.floor(elapsed)
    local elapsedMinutes = math.floor(elapsedSeconds / 60)
    local elapsedSecs = math.mod(elapsedSeconds, 60)
    
    local h = PWB.serverTime.h
    local m = PWB.serverTime.m + elapsedMinutes
    local s = (PWB.serverTime.s or 0) + elapsedSecs
    
    -- Handle second overflow
    if s >= 60 then
      m = m + math.floor(s / 60)
      s = math.mod(s, 60)
    end
    
    -- Handle minute overflow
    if m >= 60 then
      h = h + math.floor(m / 60)
      m = math.mod(m, 60)
    end
    
    -- Handle hour overflow
    h = math.mod(h, 24)
    
    return h, m
  end
  
  -- Return nil if server time from .server info is not available
  return nil, nil
end

-- Check if received server time indicates we have drift
-- Returns true if we should refresh our server time
function PWB.utils.checkServerTimeDrift(receivedH, receivedM)
  if not PWB.serverTime or not receivedH or not receivedM then
    return false
  end
  
  local ourH, ourM = PWB.utils.getServerTime()
  if not ourH or not ourM then
    return false
  end
  
  local ourMinutes = ourH * 60 + ourM
  local receivedMinutes = receivedH * 60 + receivedM
  
  -- Calculate time difference, handling midnight rollover
  local timeDiff
  if ourMinutes >= receivedMinutes then
    timeDiff = ourMinutes - receivedMinutes
    if timeDiff > 12 * 60 then -- More than 12 hours, probably rollover
      timeDiff = (24 * 60) - ourMinutes + receivedMinutes
    end
  else
    timeDiff = receivedMinutes - ourMinutes
    if timeDiff > 12 * 60 then -- More than 12 hours, probably rollover
      timeDiff = (24 * 60) - receivedMinutes + ourMinutes
    end
  end
  
  -- If difference is more than 2 minutes, we might have drift
  -- Store this sample
  if timeDiff > 2 or timeDiff < -2 then
    table.insert(PWB.serverTimeDriftSamples, {
      received = receivedMinutes,
      ours = ourMinutes,
      diff = timeDiff,
      at = time()
    })
    
    -- Keep only last 5 samples
    local sampleCount = 0
    for _ in ipairs(PWB.serverTimeDriftSamples) do
      sampleCount = sampleCount + 1
    end
    if sampleCount > 5 then
      table.remove(PWB.serverTimeDriftSamples, 1)
      sampleCount = sampleCount - 1
    end
    
    -- If we have 3+ samples all showing similar drift, refresh
    if sampleCount >= 3 then
      local consistentDrift = true
      local avgDrift = 0
      local count = 0
      for _, sample in ipairs(PWB.serverTimeDriftSamples) do
        count = count + 1
        avgDrift = avgDrift + sample.diff
        if count > 1 and math.abs(sample.diff - PWB.serverTimeDriftSamples[1].diff) > 1 then
          consistentDrift = false
          break
        end
      end
      
      if consistentDrift and count > 0 then
        avgDrift = avgDrift / count
        -- If average drift is more than 2 minutes, refresh
        if math.abs(avgDrift) > 2 then
          PWB.serverTimeDriftSamples = {} -- Clear samples
          SendChatMessage('.server info', 'SAY')
          return true
        end
      end
    end
  end
  
  return false
end

-- Get local PizzaWorldBuffs version as a semantic versioning string
function PWB.utils.getVersion()
  return tostring(GetAddOnMetadata(PWB:GetName(), 'Version'))
end

-- Get local PizzaWorldBuffs version as a single number
function PWB.utils.getVersionNumber()
  local major, minor, patch = PWB.utils.strSplit(PWB.utils.getVersion(), '.')
  major = tonumber(major) or 0
  minor = tonumber(minor) or 0
  patch = tonumber(patch) or 0

  return major*10000 + minor*100 + patch
end

-- Identity function
function PWB.utils.identity(x)
  return x
end

-- Check if condition applies to any of our timers.
function PWB.utils.someTimer(fn)
  if not PWB_timers then return false end

  for _, timers in pairs(PWB_timers) do
    for _, timer in pairs(timers) do
      if fn(timer) then return true end
    end
  end
  return false
end

-- Invoke fn for each timer we have stored currently.
function PWB.utils.forEachTimer(fn)
  if not PWB_timers then return end

  for _, timers in pairs(PWB_timers) do
    for _, timer in pairs(timers) do
      fn(timer)
    end
  end
end

function PWB.utils.hasDmf()
  return PWB_dmf and PWB_dmf.location and PWB_dmf.seenAt and PWB_dmf.witness
end

-- Check if we currently have any timers stored.
function PWB.utils.hasTimers()
  return PWB.utils.someTimer(PWB.utils.identity)
end

-- Check if we currently have a timer for a specific faction & boss stored.
function PWB.utils.hasTimer(faction, boss)
  if not PWB_timers then return false end
  return PWB_timers[faction][boss] and true or false
end

-- Check if we have any timers stored in a deprecated format (pre-v0.0.15)
function PWB.utils.hasDeprecatedTimerFormat()
  return PWB.utils.someTimer(function (timer)
    return timer.deadline ~= nil
  end)
end

-- Check if I'm the direct witness for any of my timers.
function PWB.utils.isWitness()
  return PWB.utils.someTimer(function (timer)
    return timer.witness == PWB.me
  end)
end

-- Split the provided string by the specified delimiter.
function PWB.utils.strSplit(str, delimiter)
  if not str then return nil end
  local delimiter, fields = delimiter or ':', {}
  local pattern = string.format('([^%s]+)', delimiter)
  string.gsub(str, pattern, function(c) fields[table.getn(fields)+1] = c end)
  return unpack(fields)
end

function PWB.utils.getId(t)
  return string.gsub(tostring(t), 'table: ', '', 1)
end

-- Get the color that should be used for a timer, based on how confident we are in it.
function PWB.utils.getTimerColor(witness, receivedFrom)
  if witness == PWB.me then return PWB.Colors.green end
  if receivedFrom == witness then return PWB.Colors.orange end
  return PWB.Colors.red
end

function PWB.utils.getTimerConfidence(witness, receivedFrom)
  if witness == PWB.me then return 1 end
  if receivedFrom == witness then return 2 end
  return 3
end

function PWB.utils.contains(table, value)
  for _, val in pairs(table) do
    if val == value then return true end
  end
  return false
end

function PWB.utils.getChannelId(channelName)
  local channels = {}
  local chanList = { GetChannelList() }

  for i = 1, length(chanList), 2 do
    if string.lower(chanList[i+1]) == channelName then
      return chanList[i]
    end
  end
end

function PWB.utils.getCurrentMapZoneName()
  local cid = GetCurrentMapContinent()
  local mid = GetCurrentMapZone()
  local list = { GetMapZones(cid) }
  return list[mid]
end
