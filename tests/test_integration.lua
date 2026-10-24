local eq = MiniTest.expect.equality
local fixture = vim.fs.joinpath(vim.fn.getcwd(), "tests/fixtures/flake")

local T = MiniTest.new_set({
  hooks = {
    post_case = function()
      for _, client in ipairs(vim.lsp.get_clients({ name = "flake-nav" })) do
        client:stop(true)
      end
      vim.cmd("silent! %bwipeout!")
    end,
  },
})

local function open(rel)
  vim.cmd.edit(vim.fs.joinpath(fixture, rel))
  local buf = vim.api.nvim_get_current_buf()
  local client
  vim.wait(2000, function()
    client = vim.lsp.get_clients({ name = "flake-nav", bufnr = buf })[1]
    return client ~= nil and client.initialized
  end)
  return buf, client
end

local function params(buf, line, character)
  return {
    textDocument = { uri = vim.uri_from_bufnr(buf) },
    position = { line = line, character = character },
  }
end

T["setup merges options"] = function()
  local flake_nav = require("flake-nav")
  flake_nav.setup({ ignore = { "vendor" }, ignore_underscore = false, hover = { max_lines = 5 } })
  eq(flake_nav.config.ignore, { "vendor" })
  eq(flake_nav.config.ignore_underscore, false)
  eq(flake_nav.config.hover.max_lines, 5)
  eq(flake_nav.config.root_markers, { "flake.nix" })
  flake_nav.setup()
  eq(flake_nav.config.ignore, { ".git", ".direnv", "result", "result-*", "node_modules" })
  eq(flake_nav.config.ignore_underscore, true)
end

T["setup merges the diagnostics option"] = function()
  local flake_nav = require("flake-nav")
  flake_nav.setup()
  eq(flake_nav.config.diagnostics, { unknown = true, unused = true })
  flake_nav.setup({ diagnostics = { unused = false } })
  eq(flake_nav.config.diagnostics, { unknown = true, unused = false })
  flake_nav.setup({ diagnostics = false })
  eq(flake_nav.config.diagnostics, false)
  flake_nav.setup({ diagnostics = true })
  eq(flake_nav.config.diagnostics, { unknown = true, unused = true })
end

T["diagnostics end to end"] = function()
  require("flake-nav").setup()
  local buf = open("modules/profiles/base.nix")
  local found
  vim.wait(2000, function()
    found = vim.diagnostic.get(buf)
    return #found > 0
  end)
  eq(#found, 1)
  eq(found[1].message, "Module nixos.dev-rust is never used")
  eq(found[1].severity, vim.diagnostic.severity.HINT)
end

T["setup turns diagnostics off for running clients"] = function()
  require("flake-nav").setup()
  local buf = open("modules/profiles/base.nix")
  vim.wait(2000, function()
    return #vim.diagnostic.get(buf) > 0
  end)
  require("flake-nav").setup({ diagnostics = false })
  vim.wait(1000, function()
    return #vim.diagnostic.get(buf) == 0
  end)
  eq(vim.diagnostic.get(buf), {})
  require("flake-nav").setup()
end

T["attaches to nix buffers under a flake"] = function()
  require("flake-nav").setup()
  local _, client = open("modules/hosts/laptop.nix")
  eq(client ~= nil, true)
  eq(client.root_dir, fixture)
end

T["gd, gr and K end to end"] = function()
  require("flake-nav").setup()
  local buf, client = open("modules/hosts/laptop.nix")
  local def = client:request_sync("textDocument/definition", params(buf, 6, 59), 2000, buf)
  eq(vim.uri_to_fname(def.result[1].uri), vim.fs.joinpath(fixture, "modules/features/locale.nix"))
  eq(def.result[1].range.start, { line = 5, character = 22 })

  local refs_params = params(buf, 6, 59)
  refs_params.context = { includeDeclaration = false }
  local refs = client:request_sync("textDocument/references", refs_params, 2000, buf)
  eq(#refs.result, 2)

  local hover = client:request_sync("textDocument/hover", params(buf, 6, 59), 2000, buf)
  eq(hover.result.contents.value:find("`nixos.locale`", 1, true) ~= nil, true)
end

T["unsaved edits move the definition"] = function()
  require("flake-nav").setup()
  local locale = open("modules/features/locale.nix")
  vim.api.nvim_buf_set_lines(locale, 0, 0, false, { "" })
  vim.wait(500)
  local buf, client = open("modules/hosts/laptop.nix")
  local def = client:request_sync("textDocument/definition", params(buf, 6, 59), 2000, buf)
  eq(def.result[1].range.start, { line = 6, character = 22 })
end

return T
