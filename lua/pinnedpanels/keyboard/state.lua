-- ── Keyboard Navigation: Shared State & Key Repeat ────────────────────────────

PinnedPanels._KB = PinnedPanels._KB or {}
local KB = PinnedPanels._KB

KB.IM = PinnedPanels.CursorMode
KB.C  = PinnedPanels.C

-- ── Timing Constants ─────────────────────────────────────────────────────────
KB.KEY_REPEAT_DELAY    = 0.35
KB.KEY_REPEAT_INTERVAL = 0.055

-- ── Navigation Keys ──────────────────────────────────────────────────────────
KB.NAV_KEYS = {
    [KEY_UP]        = true,
    [KEY_DOWN]      = true,
    [KEY_LEFT]      = true,
    [KEY_RIGHT]     = true,
    [KEY_ENTER]     = true,
    [KEY_BACKSPACE] = true,
}

-- ── Key Repeat ───────────────────────────────────────────────────────────────
KB.repeatState = {}

function KB.StartRepeat(key)
    KB.repeatState[key] = { start = CurTime(), last = 0, repeating = false }
end

function KB.StopRepeat(key)
    KB.repeatState[key] = nil
end

function KB.StopAllRepeats()
    KB.repeatState = {}
end

function KB.ShouldRepeat(key)
    local t = KB.repeatState[key]
    if not t then return false end
    local now = CurTime()
    if not t.repeating then
        if now - t.start >= KB.KEY_REPEAT_DELAY then
            t.repeating, t.last = true, now
            return true
        end
        return false
    end
    if now - t.last >= KB.KEY_REPEAT_INTERVAL then
        t.last = now
        return true
    end
    return false
end

-- ── Nav Key State ────────────────────────────────────────────────────────────
KB.navKeyDown = {}

function KB.ResetNavKeyState()
    KB.StopAllRepeats()
    KB.navKeyDown = {}
    for k in pairs(KB.NAV_KEYS) do
        if input.IsKeyDown(k) then
            KB.navKeyDown[k] = true
            KB.StartRepeat(k)
        end
    end
end
