local WindowChooser = require("lib.window_chooser")

local function fakeWindow(id, title, application)
  return {
    id = function() return id end,
    title = function() return title end,
    application = function()
      return {
        name = function() return application end,
        bundleID = function() return "com.example." .. application end,
        pid = function() return 1000 + id end,
      }
    end,
  }
end

return {
  ["window chooser fuzzily searches live window titles and application names"] = function()
    local first = fakeWindow(1, "10bucks README", "Terminal")
    local second = fakeWindow(2, "Issue tracker", "Linear")
    local selected
    local nativeChooser = {}
    function nativeChooser:searchSubText(value) self.searchesSubText = value end
    function nativeChooser:choices(choices) self.windowChoices = choices end
    function nativeChooser:show() self.shown = true end
    function nativeChooser:hide() self.hidden = true end
    local hs = {
      chooser = {
        new = function(callback)
          nativeChooser.callback = callback
          return nativeChooser
        end,
      },
      image = {
        imageFromAppBundle = function(bundleId) return "bundle-icon-" .. bundleId end,
      },
    }
    local picker = WindowChooser.new(hs, {
      allLiveWindows = function() return { first, second } end,
    }, function(window)
      selected = window
    end)

    assert(picker:show())
    assert(nativeChooser.shown)
    assert(nativeChooser.searchesSubText)
    assert(#nativeChooser.windowChoices == 2)
    -- Choices sort by app then title. The searchable secondary text includes
    -- owning GUI-process metadata, while the title remains primary text.
    assert(nativeChooser.windowChoices[1].text == "Issue tracker")
    assert(nativeChooser.windowChoices[1].subText == "Linear · com.example.Linear · pid 1002")
    assert(nativeChooser.windowChoices[2].text == "10bucks README")
    assert(nativeChooser.windowChoices[2].subText == "Terminal · com.example.Terminal · pid 1001")
    assert(nativeChooser.windowChoices[2].image == "bundle-icon-com.example.Terminal")

    nativeChooser.callback(nativeChooser.windowChoices[2])
    assert(selected == first)
    nativeChooser.callback(nil)
    assert(selected == first)
    picker:hide()
    assert(nativeChooser.hidden)
  end,

  ["window chooser labels titleless windows without omitting their application"] = function()
    local nativeChooser = {}
    function nativeChooser:searchSubText() end
    function nativeChooser:choices(choices) self.windowChoices = choices end
    function nativeChooser:show() end
    local picker = WindowChooser.new({ chooser = { new = function(callback)
      nativeChooser.callback = callback
      return nativeChooser
    end } }, {
      allLiveWindows = function() return { fakeWindow(1, "", "Finder") } end,
    }, function() end)

    assert(picker:show())
    assert(nativeChooser.windowChoices[1].text == "Untitled window")
    assert(nativeChooser.windowChoices[1].subText == "Finder · com.example.Finder · pid 1001")
  end,
}
