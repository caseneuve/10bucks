-- 10bucks: a small, keyboard-first tabbed-stack window manager for Hammerspoon.
-- Modules are kept separate so the state model and layout engine can evolve independently.
local source = debug.getinfo(1, "S").source:sub(2)
local root = source:match("(.*/)")
if root then
  package.path = root .. "?.lua;" .. root .. "?/init.lua;" .. package.path
end

local Config = require("lib.config")
local State = require("lib.state")
local WindowRepository = require("lib.window_repository")
local Bar = require("lib.bar")
local Workspaces = require("lib.workspaces")
local Engine = require("lib.engine")
local Lifecycle = require("lib.lifecycle")
local Bindings = require("lib.bindings")

local Tenbucks = {}
Tenbucks.__index = Tenbucks
Tenbucks.name = "10bucks"
Tenbucks.version = "2026.08.26-alpha.1"
Tenbucks.author = "caseneuve"
Tenbucks.license = "MIT - https://opensource.org/license/mit"
Tenbucks.homepage = "https://github.com/caseneuve/10bucks"
Tenbucks.defaultHotkeys = Config.defaults.hotkeys

function Tenbucks.new()
  local instance = setmetatable({ hotkeyBindings = {} }, Tenbucks)
  instance:configure({})
  return instance
end

function Tenbucks:configure(options)
  assert(not self.started, "Stop 10bucks before changing its configuration")
  self.config = Config.build(options)
  self.state = State.new(self.config)
  self.repository = WindowRepository.new(hs, self.config)
  self.workspaces = Workspaces.new(hs)
  self.engine = Engine.new({
    config = self.config,
    state = self.state,
    repository = self.repository,
    workspaces = self.workspaces,
    statusDisplay = function(message) hs.alert.show(message, self.config.statusDuration) end,
  })
  self.lifecycle = Lifecycle.new(hs, self.engine)
  self.bar = Bar.new(hs, self.engine, self.repository, self.workspaces, self.config.bar)
  return self
end

function Tenbucks:configureFile(path)
  assert(not self.started, "Stop 10bucks before changing its configuration")

  if path == nil then
    local xdgConfigHome = os.getenv("XDG_CONFIG_HOME")
    if xdgConfigHome and xdgConfigHome ~= "" then
      path = xdgConfigHome .. "/10bucks/config.lua"
    else
      local home = os.getenv("HOME")
      if not home or home == "" then
        error("10bucks config: XDG_CONFIG_HOME or HOME must be set", 0)
      end
      path = home .. "/.config/10bucks/config.lua"
    end
  end

  return self:configure(Config.loadFile(path))
end

-- Bind a full replacement map, or omit the argument to use configured defaults.
-- Each item is: actionName = { { modifiers... }, key }.
function Tenbucks:bindHotkeys(mapping)
  Bindings.delete(self.hotkeyBindings)
  self.hotkeyBindings = Bindings.bind(hs, self.engine, mapping or self.config.hotkeys)
  return self
end

function Tenbucks:start()
  if self.started then return self end
  self.engine:start()
  self.lifecycle:start()
  self.workspaces:start(function()
    self.engine:workspaceChanged()
    self.bar:refresh()
  end)
  self.bar:start()
  self.started = true
  return self
end

function Tenbucks:stop()
  if not self.started then return self end
  self.engine:cancelWorkspaceSelection()
  self.engine:cancelWindowSelection()
  self.lifecycle:stop()
  self.repository:stop()
  self.workspaces:stop()
  self.bar:stop()
  Bindings.delete(self.hotkeyBindings)
  self.hotkeyBindings = {}
  self.started = false
  return self
end

return Tenbucks.new()
