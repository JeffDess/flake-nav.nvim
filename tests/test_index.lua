local T = MiniTest.new_set()
local eq = MiniTest.expect.equality
local Index = require("flake-nav.index")

local fixture = vim.fs.joinpath(vim.fn.getcwd(), "tests/fixtures/flake")
local IGNORE = { ".git", ".direnv", "result", "result-*", "node_modules" }

local function file(rel)
  return vim.fs.joinpath(fixture, rel)
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

local function write(path, text)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local fd = assert(io.open(path, "w"))
  fd:write(text)
  fd:close()
end

T["indexes the fixture"] = function()
  local index = Index.new(fixture, { ignore = IGNORE })
  index:refresh()
  local stats = index:stats()
  eq(stats.files, 5)
  eq(stats.definitions, 5)
  eq(stats.uses, 6)
  eq(stats.skipped, {})
  eq(stats.with_errors, {})
end

T["definitions"] = function()
  local index = Index.new(fixture, { ignore = IGNORE })
  index:refresh()
  eq(where(index:definitions("nixos", "locale")), { "modules/features/locale.nix:5:22" })
  eq(where(index:definitions("homeManager", "ssl")), { "modules/users/demo.nix:3:24" })
  eq(index:definitions("nixos", "missing"), {})
end

T["references"] = function()
  local index = Index.new(fixture, { ignore = IGNORE })
  index:refresh()
  eq(where(index:references("nixos", "locale", false)), {
    "modules/hosts/laptop.nix:6:59",
    "modules/users/demo.nix:6:43",
  })
  eq(where(index:references("nixos", "locale", true)), {
    "modules/features/locale.nix:5:22",
    "modules/hosts/laptop.nix:6:59",
    "modules/users/demo.nix:6:43",
  })
  eq(index:references("nixos", "hardware", false), {})
end

T["open documents override disk"] = function()
  local index = Index.new(fixture, { ignore = IGNORE })
  index:refresh()
  local path = file("modules/features/locale.nix")
  local moved = "\n" .. table.concat(index:lines(path), "\n")
  index:set_document(path, moved)
  index:refresh()
  eq(where(index:definitions("nixos", "locale")), { "modules/features/locale.nix:6:22" })
  eq(index:lines(path)[1], "")
  index:clear_document(path)
  index:refresh()
  eq(where(index:definitions("nixos", "locale")), { "modules/features/locale.nix:5:22" })
end

T["ignores configured names and tracks changes on disk"] = function()
  local root = vim.fn.tempname()
  write(root .. "/a.nix", "{ flake.modules.nixos.a = { }; }")
  write(root .. "/result/b.nix", "{ flake.modules.nixos.b = { }; }")
  write(root .. "/result-1/c.nix", "{ flake.modules.nixos.c = { }; }")
  local index = Index.new(root, { ignore = IGNORE })
  index:refresh()
  eq(index:stats().definitions, 1)

  write(root .. "/a.nix", "{ flake.modules.nixos.renamed = { }; }")
  vim.uv.fs_utime(root .. "/a.nix", os.time() + 10, os.time() + 10)
  index:refresh()
  eq(#index:definitions("nixos", "renamed"), 1)

  os.remove(root .. "/a.nix")
  index:refresh()
  eq(index:stats().files, 0)
  vim.fn.delete(root, "rf")
end

T["reports files with syntax errors"] = function()
  local root = vim.fn.tempname()
  write(root .. "/bad.nix", "{ broken = ; }")
  local index = Index.new(root, { ignore = IGNORE })
  index:refresh()
  eq(index:stats().with_errors, { root .. "/bad.nix" })
  vim.fn.delete(root, "rf")
end

T["reset reparses from scratch and keeps documents"] = function()
  local index = Index.new(fixture, { ignore = IGNORE })
  index:refresh()
  local path = file("modules/profiles/base.nix")
  index:set_document(path, "{ flake.modules.nixos.only = { }; }")
  index:reset()
  index:refresh()
  eq(#index:definitions("nixos", "only"), 1)
  eq(#index:definitions("nixos", "base"), 0)
end

T["follows import-tree and skips underscore paths"] = function()
  local index = Index.new(fixture, { ignore = IGNORE })
  index:refresh()
  eq(index:stats().scope, { origin = "detected", paths = { "modules" } })
  eq(index:definitions("nixos", "hidden"), {})
  eq(index:definitions("nixos", "old"), {})
  eq(index:definitions("nixos", "stray"), {})
end

T["indexes the whole root without import-tree"] = function()
  local root = vim.fn.tempname()
  write(root .. "/flake.nix", "{ outputs = _: { }; }")
  write(root .. "/a.nix", "{ flake.modules.nixos.a = { }; }")
  write(root .. "/_lib/b.nix", "{ flake.modules.nixos.b = { }; }")
  write(root .. "/sub/_c.nix", "{ flake.modules.nixos.c = { }; }")
  local index = Index.new(root, { ignore = IGNORE })
  index:refresh()
  eq(index:stats().scope, { origin = "none", paths = { "." } })
  eq(index:stats().definitions, 1)
  local keep = Index.new(root, { ignore = IGNORE, ignore_underscore = false })
  keep:refresh()
  eq(keep:stats().definitions, 3)
  vim.fn.delete(root, "rf")
end

T["indexes the whole root on an unrecognised import-tree form"] = function()
  local root = vim.fn.tempname()
  write(
    root .. "/flake.nix",
    "{ outputs = inputs: mk { } (inputs.import-tree.filter f ./modules); }"
  )
  write(root .. "/modules/a.nix", "{ flake.modules.nixos.a = { }; }")
  write(root .. "/other/b.nix", "{ flake.modules.nixos.b = { }; }")
  local index = Index.new(root, { ignore = IGNORE })
  index:refresh()
  eq(index:stats().scope, { origin = "unsupported", paths = { "." } })
  eq(index:stats().definitions, 2)
  vim.fn.delete(root, "rf")
end

T["an open flake.nix drives the scope"] = function()
  local root = vim.fn.tempname()
  write(root .. "/flake.nix", "{ outputs = _: { }; }")
  write(root .. "/modules/a.nix", "{ flake.modules.nixos.a = { }; }")
  write(root .. "/other/b.nix", "{ flake.modules.nixos.b = { }; }")
  local index = Index.new(root, { ignore = IGNORE })
  index:refresh()
  eq(index:stats().definitions, 2)
  index:set_document(
    root .. "/flake.nix",
    "{ outputs = inputs: mk { } (inputs.import-tree ./modules); }"
  )
  index:refresh()
  eq(index:stats().definitions, 1)
  index:set_document(root .. "/other/b.nix", "{ flake.modules.nixos.b = { }; }")
  index:refresh()
  eq(#index:definitions("nixos", "b"), 0)
  eq(index:parsed(root .. "/other/b.nix") ~= nil, true)
  vim.fn.delete(root, "rf")
end

T["modules mapped from a flake option are defined where the option is set"] = function()
  local root = vim.fn.tempname()
  write(root .. "/flake.nix", "{ outputs = _: { }; }")
  write(
    root .. "/users.nix",
    "{ lib, config, ... }: { config.flake.modules.nixos = lib.mapAttrs mk config.users; }"
  )
  write(root .. "/alice.nix", "{ users.alice = { groups = [ ]; }; }")
  write(root .. "/bob.nix", "{\n  users = { bob.groups = [ ]; };\n}")
  write(root .. "/reader.nix", "{ config, ... }: { x = config.users.carol; }")
  local index = Index.new(root, { ignore = IGNORE })
  index:refresh()
  local function at(class, name)
    return vim.tbl_map(function(entry)
      return ("%s:%d:%d"):format(
        vim.fs.relpath(root, entry.path),
        entry.item.range[1],
        entry.item.range[2]
      )
    end, index:definitions(class, name))
  end
  eq(at("nixos", "alice"), { "alice.nix:0:8" })
  eq(at("nixos", "bob"), { "bob.nix:1:12" })
  eq(at("nixos", "carol"), {})
  eq(index:definitions("nixos", "alice")[1].item.scope_range[1], 0)
  index:set_document(root .. "/alice.nix", "{ users.dave = { }; }")
  eq(at("nixos", "alice"), {})
  eq(at("nixos", "dave"), { "alice.nix:0:8" })
  vim.fn.delete(root, "rf")
end

return T
