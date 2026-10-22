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

T[":FlakeNav info and reindex"] = function()
  vim.cmd.runtime("plugin/flake-nav.lua")
  require("flake-nav").setup()
  open("modules/hosts/laptop.nix")
  local messages = {}
  local notify = vim.notify
  vim.notify = function(msg)
    messages[#messages + 1] = msg
  end
  vim.cmd("FlakeNav reindex")
  vim.cmd("FlakeNav info")
  vim.notify = notify
  eq(messages[1], "flake-nav: reindexed " .. fixture)
  eq(messages[2]:find("definitions: 5", 1, true) ~= nil, true)
  eq(messages[2]:find("uses: 6", 1, true) ~= nil, true)
  eq(messages[2]:find("scope: import-tree (modules)", 1, true) ~= nil, true)
end

return T
