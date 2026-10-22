local eq = MiniTest.expect.equality
local remap = require("flake-nav.remap")

local tmp, root, store, copy, input

local function write(path, text)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile(vim.split(text, "\n"), path)
end

local RANGE = { start = { line = 13, character = 8 }, ["end"] = { line = 13, character = 8 } }

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      tmp = vim.fn.tempname()
      root = vim.fs.joinpath(tmp, "repo")
      store = vim.fs.joinpath(tmp, "store")
      copy = vim.fs.joinpath(store, "abc123-source")
      input = vim.fs.joinpath(store, "def456-source")
      for _, dir in ipairs({ root, copy }) do
        write(vim.fs.joinpath(dir, "flake.lock"), '{ "version": 7 }')
        write(vim.fs.joinpath(dir, "modules/audio.nix"), "{ }")
      end
      write(vim.fs.joinpath(input, "flake.lock"), '{ "version": 7, "other": true }')
      write(vim.fs.joinpath(input, "modules/audio.nix"), "{ }")
    end,
    post_case = function()
      vim.fn.delete(tmp, "rf")
    end,
  },
})

local function loc(dir, rel)
  return { uri = vim.uri_from_fname(vim.fs.joinpath(dir, rel)), range = RANGE }
end

T["a store copy of the flake points to the working tree"] = function()
  eq(remap.locations(loc(copy, "modules/audio.nix"), root, store), loc(root, "modules/audio.nix"))
end

T["lists and LocationLinks are remapped"] = function()
  local link = {
    targetUri = loc(copy, "modules/audio.nix").uri,
    targetRange = RANGE,
    targetSelectionRange = RANGE,
  }
  local out = remap.locations({ loc(copy, "modules/audio.nix"), link }, root, store)
  eq(out[1], loc(root, "modules/audio.nix"))
  eq(out[2].targetUri, loc(root, "modules/audio.nix").uri)
end

T["another source with a different lock is kept"] = function()
  eq(remap.locations(loc(input, "modules/audio.nix"), root, store), loc(input, "modules/audio.nix"))
end

T["files missing from the working tree are kept"] = function()
  write(vim.fs.joinpath(copy, "modules/gone.nix"), "{ }")
  eq(remap.locations(loc(copy, "modules/gone.nix"), root, store), loc(copy, "modules/gone.nix"))
end

T["non store locations and nil are kept"] = function()
  eq(remap.locations(loc(root, "modules/audio.nix"), root, store), loc(root, "modules/audio.nix"))
  eq(remap.locations(nil, root, store), nil)
end

return T
