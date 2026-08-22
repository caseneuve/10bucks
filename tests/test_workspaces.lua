local Workspaces = require("lib.workspaces")

local screen = {
  getUUID = function() return "screen-a" end,
}

local function fakeSpaces(active)
  local calls = {}
  return {
    calls = calls,
    spacesForScreen = function() return { 11, 12, 13, 14 } end,
    spaceType = function(spaceId)
      return ({ [11] = "user", [12] = "fullscreen", [13] = "user", [14] = "fullscreen" })[spaceId]
    end,
    activeSpaceOnScreen = function() return active end,
    gotoSpace = function(spaceId) calls.target = spaceId return true end,
  }
end

local function workspace(active)
  local spaces = fakeSpaces(active)
  return Workspaces.new({ spaces = spaces }), spaces
end

return {
  ["workspace service maps only user Spaces to desktops"] = function()
    local service = workspace(13)
    local desktops = service:desktopSpaces(screen)
    assert(#desktops == 2)
    assert(desktops[1] == 11 and desktops[2] == 13)
    local active = service:activeDesktop(screen)
    assert(active.id == 13 and active.index == 2)
    assert(service:label(screen) == "1 [2]")
  end,

  ["workspace navigation skips fullscreen scratchpads from a desktop"] = function()
    local service = workspace(11)
    local destination = service:neighboringDesktop(screen, 1)
    assert(destination.id == 13 and destination.index == 2)
  end,

  ["workspace service resolves a mapped desktop by its displayed number"] = function()
    local service = workspace(11)
    local destination = service:desktopAt(screen, 2)
    assert(destination.id == 13 and destination.index == 2)
    assert(service:desktopAt(screen, 3) == nil)
    assert(service:desktopAt(screen, 1.5) == nil)
  end,

  ["workspace service tracks the previously focused mapped desktop"] = function()
    local active = 11
    local spaces = {
      spacesForScreen = function() return { 11, 12, 13 } end,
      spaceType = function(spaceId) return ({ [11] = "user", [12] = "user", [13] = "user" })[spaceId] end,
      activeSpaceOnScreen = function() return active end,
      gotoSpace = function() return true end,
    }
    local service = Workspaces.new({ spaces = spaces })

    assert(service:rememberActiveDesktop(screen).id == 11)
    active = 13
    assert(service:rememberActiveDesktop(screen).id == 13)
    assert(service:previouslyFocusedDesktop(screen).id == 11)
    active = 11
    service:rememberActiveDesktop(screen)
    assert(service:previouslyFocusedDesktop(screen).id == 13)
  end,

  ["workspace navigation leaves a fullscreen scratchpad for its adjacent desktop"] = function()
    local service = workspace(12)
    local nextDesktop = service:neighboringDesktop(screen, 1)
    local previousDesktop = service:neighboringDesktop(screen, -1)
    assert(nextDesktop.id == 13 and nextDesktop.index == 2)
    assert(previousDesktop.id == 11 and previousDesktop.index == 1)
  end,

  ["workspace service only switches to mapped desktop Spaces"] = function()
    local service, spaces = workspace(11)
    assert(service:gotoDesktop(13))
    assert(spaces.calls.target == 13)
    assert(not service:gotoDesktop(12))
    assert(spaces.calls.target == 13)
  end,

  ["workspace service creates and identifies a new empty desktop"] = function()
    local spaces = fakeSpaces(11)
    local service = Workspaces.new({ spaces = spaces })
    spaces.addSpaceToScreen = function(receivedScreen, closeMissionControl)
      spaces.calls.addedOn = receivedScreen
      spaces.calls.closeMissionControl = closeMissionControl
      spaces.spacesForScreen = function() return { 11, 12, 13, 14, 15 } end
      spaces.spaceType = function(spaceId)
        return ({ [11] = "user", [12] = "fullscreen", [13] = "user", [14] = "fullscreen", [15] = "user" })[spaceId]
      end
      return true
    end

    local added, desktop = service:addDesktop(screen)
    assert(added)
    assert(desktop.id == 15 and desktop.index == 3)
    assert(spaces.calls.addedOn == screen)
    assert(spaces.calls.closeMissionControl == false)
  end,

  ["workspace labels survive deletion and explicit-number creation"] = function()
    local active, spacesForScreen, saved = 11, { 11, 12, 13, 14 }, {}
    local spaces = {
      spacesForScreen = function() return spacesForScreen end,
      spaceType = function() return "user" end,
      activeSpaceOnScreen = function() return active end,
      gotoSpace = function() return true end,
      addSpaceToScreen = function()
        table.insert(spacesForScreen, 15)
        return true
      end,
    }
    local settings = {
      get = function(key) return saved[key] end,
      set = function(key, value) saved[key] = value end,
    }
    local service = Workspaces.new({ spaces = spaces, settings = settings })
    assert(service:label(screen) == "[1] 2 3 4")

    table.remove(spacesForScreen, 3)
    assert(service:label(screen) == "[1] 2 4")
    local added, desktop = service:addDesktop(screen, 7)
    assert(added and desktop.index == 7)
    assert(service:label(screen) == "[1] 2 4 7")

    local restarted = Workspaces.new({ spaces = spaces, settings = settings })
    assert(restarted:label(screen) == "[1] 2 4 7")
  end,

  ["workspace creation closes Mission Control when the new desktop is unavailable"] = function()
    local spaces = fakeSpaces(11)
    local service = Workspaces.new({ spaces = spaces })
    spaces.addSpaceToScreen = function() return true end
    spaces.closeMissionControl = function() spaces.calls.closed = true end

    local added, error = service:addDesktop(screen)
    assert(not added)
    assert(error == "Created desktop workspace could not be identified")
    assert(spaces.calls.closed)
  end,

  ["workspace service removes a queued desktop only after its destination is active"] = function()
    local active, removed = 13, nil
    local spaces = {
      spacesForScreen = function() return { 11, 13 } end,
      spaceType = function() return "user" end,
      activeSpaceOnScreen = function() return active end,
      gotoSpace = function() return true end,
      removeSpace = function(spaceId) removed = spaceId return true end,
    }
    local service = Workspaces.new({ spaces = spaces })
    assert(service:queueDesktopRemoval(screen, { id = 13, index = 2 }, { id = 11, index = 1 }))
    assert(not service:completePendingRemoval(screen))
    assert(removed == nil)

    assert(service:queueDesktopRemoval(screen, { id = 13, index = 2 }, { id = 11, index = 1 }))
    active = 11
    local completed, source = service:completePendingRemoval(screen)
    assert(completed and source.id == 13)
    assert(removed == 13)
  end,

  ["workspace label immediately reflects a pending desktop switch"] = function()
    local service = workspace(11)
    service:setPendingDesktop(screen, { id = 13, index = 2 })
    assert(service:label(screen) == "1 [2]")
    service:clearPendingDesktop(screen)
    assert(service:label(screen) == "[1] 2")
  end,
}
