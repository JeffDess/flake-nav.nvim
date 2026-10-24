local T = MiniTest.new_set()
local eq = MiniTest.expect.equality
local Index = require("flake-nav.index")

local fixture = vim.fs.joinpath(vim.fn.getcwd(), "tests/fixtures/inputs")

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

T["definitions come from the root flake.nix only"] = function()
  local idx = index()
  eq(where(idx:input_definitions("hooks")), { pos("flake.nix", 3, "hooks") })
  eq(idx:input_definitions("unknown"), {})
end

T["a nested flake.nix does not use the root flake's inputs"] = function()
  local idx = index()
  local nested = vim.fs.joinpath(fixture, "vendor/local/flake.nix")
  eq(idx:parsed(nested).inputs, { decls = {}, uses = {} })
  idx:set_document(nested, table.concat(vim.fn.readfile(nested), "\n"))
  eq(idx:parsed(nested).inputs, { decls = {}, uses = {} })
end

T["references across files, flake-only usages from the root flake.nix"] = function()
  local idx = index()
  eq(where(idx:input_references("hooks", false)), {
    pos("flake.nix", 7, "hooks"),
    pos("flake.nix", 19, "hooks", 2),
    pos("modules/default.nix", 2, "hooks"),
  })
  eq(where(idx:input_references("nixpkgs", true)), {
    pos("flake.nix", 2, "nixpkgs"),
    pos("flake.nix", 5, "nixpkgs", 2),
    pos("flake.nix", 16, "nixpkgs"),
    pos("flake.nix", 18, "nixpkgs"),
  })
end

T["no references for an unknown input"] = function()
  eq(index():input_references("unknown", true), {})
end

T["locked revisions follow follows paths"] = function()
  local idx = index()
  eq(idx:locked("hooks").rev, "0123456789abcdef0123456789abcdef01234567")
  eq(idx:locked("pkgs").rev, "fedcba9876543210fedcba9876543210fedcba98")
  eq(idx:locked("local"), nil)
end

T["stats count inputs and their usages"] = function()
  local stats = index():stats()
  eq(stats.inputs, 5)
  eq(stats.input_uses > 0, true)
end

T["a missing or broken lock gives nothing"] = function()
  local root = vim.fn.tempname()
  vim.fn.mkdir(root, "p")
  vim.fn.writefile({ '{ inputs.a.url = "github:a/b"; outputs = _: { }; }' }, root .. "/flake.nix")
  local idx = Index.new(root, {})
  idx:refresh()
  eq(idx:locked("a"), nil)
  vim.fn.writefile({ "{ not json" }, root .. "/flake.lock")
  eq(idx:locked("a"), nil)
  vim.fn.delete(root, "rf")
end

return T
