local T = MiniTest.new_set()
local eq = MiniTest.expect.equality
local Index = require("flake-nav.index")

local fixture = vim.fs.joinpath(vim.fn.getcwd(), "tests/fixtures/options")

local function index()
  local idx = Index.new(fixture, {})
  idx:refresh()
  return idx
end

local function where(list)
  local out = {}
  for _, entry in ipairs(list) do
    out[#out + 1] = ("%s:%d:%d"):format(
      vim.fs.relpath(fixture, entry.path),
      entry.item.range[1],
      entry.item.range[2]
    )
  end
  return out
end

local function pos(rel, row, word, nth)
  local line = vim.fn.readfile(vim.fs.joinpath(fixture, rel))[row + 1]
  local col = 0
  for _ = 1, nth or 1 do
    col = line:find(word, col + 1, true)
  end
  return ("%s:%d:%d"):format(rel, row, col - 1)
end

local AUDIO = "modules/features/audio.nix"
local HOST = "modules/hosts/desktop.nix"
local CONFIGURATIONS = "modules/flake/configurations.nix"

T["definitions of intermediate nodes and leaves"] = function()
  local idx = index()
  eq(where(idx:option_definitions("nixos", "modules.audio")), { pos(AUDIO, 7, "audio") })
  eq(where(idx:option_definitions("nixos", "modules.audio.enable")), { pos(AUDIO, 8, "enable") })
end

T["an unknown class matches any class"] = function()
  eq(
    where(index():option_definitions(nil, "modules.editor.theme")),
    { pos("modules/features/editor.nix", 5, "theme") }
  )
end

T["no definitions for another class or an undeclared path"] = function()
  local idx = index()
  eq(idx:option_definitions("nixos", "modules.editor.theme"), {})
  eq(idx:option_definitions("nixos", "services.pipewire.enable"), {})
end

T["references are assignments and reads of the exact path"] = function()
  local idx = index()
  eq(where(idx:option_references("nixos", "modules.audio.enable", false)), {
    pos(AUDIO, 17, "enable", 1),
    pos(HOST, 11, "enable"),
  })
  eq(where(idx:option_references("nixos", "modules.audio.enable", true)), {
    pos(AUDIO, 8, "enable"),
    pos(AUDIO, 17, "enable", 1),
    pos(HOST, 11, "enable"),
  })
end

T["references of a flake-parts option"] = function()
  eq(where(index():option_references("flake", "configurations.nixos", false)), {
    pos(CONFIGURATIONS, 7, "nixos", 2),
    pos(HOST, 5, "nixos"),
  })
end

T["no references for an undeclared path"] = function()
  eq(index():option_references("nixos", "services.pipewire.enable", true), {})
end

T["stats count option declarations and usages"] = function()
  local stats = index():stats()
  eq(stats.option_declarations, 12)
  eq(stats.option_uses > 0, true)
end

return T
