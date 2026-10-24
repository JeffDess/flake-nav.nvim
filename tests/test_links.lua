local eq = MiniTest.expect.equality

local root

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      root = vim.fn.tempname()
      vim.fn.mkdir(root, "p")
      vim.fn.writefile({
        "{",
        '  inputs.hooks.url = "github:cachix/git-hooks.nix";',
        "  outputs = _: { };",
        "}",
      }, vim.fs.joinpath(root, "flake.nix"))
      vim.fn.writefile(
        { '{ url = "github:cachix/git-hooks.nix"; }' },
        vim.fs.joinpath(root, "other.nix")
      )
    end,
    post_case = function()
      for _, client in ipairs(vim.lsp.get_clients({ name = "flake-nav" })) do
        client:stop(true)
      end
      vim.cmd("silent! %bwipeout!")
      vim.fn.delete(root, "rf")
      require("flake-nav").setup()
    end,
  },
})

local function open(name)
  vim.cmd.edit(vim.fs.joinpath(root, name))
  local buf = vim.api.nvim_get_current_buf()
  vim.wait(2000, function()
    local client = vim.lsp.get_clients({ name = "flake-nav", bufnr = buf })[1]
    return client ~= nil and client.initialized
  end)
  return buf
end

local function urls_at(row, text)
  local line = vim.api.nvim_buf_get_lines(0, row, row + 1, false)[1]
  vim.api.nvim_win_set_cursor(0, { row + 1, (line:find(text, 1, true)) })
  return require("vim.ui")._get_urls()
end

T["gx sees the web URL of an input"] = function()
  require("flake-nav").setup()
  open("flake.nix")
  eq(urls_at(1, "git-hooks"), { "https://github.com/cachix/git-hooks.nix" })
end

T["links follow edits"] = function()
  require("flake-nav").setup()
  local buf = open("flake.nix")
  vim.api.nvim_buf_set_lines(buf, 1, 2, false, { '  inputs.hooks.url = "github:nixos/nixpkgs";' })
  vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf })
  eq(urls_at(1, "nixpkgs"), { "https://github.com/nixos/nixpkgs" })
end

T["only flake.nix gets links"] = function()
  require("flake-nav").setup()
  open("other.nix")
  local urls = urls_at(0, "git-hooks")
  eq(vim.tbl_contains(urls, "https://github.com/cachix/git-hooks.nix"), false)
end

T["input_links = false disables them"] = function()
  require("flake-nav").setup({ input_links = false })
  open("flake.nix")
  local urls = urls_at(1, "git-hooks")
  eq(vim.tbl_contains(urls, "https://github.com/cachix/git-hooks.nix"), false)
end

return T
