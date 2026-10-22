local M = {}

local DEFAULTS = {
  root_markers = { "flake.nix" },
  ignore = { ".git", ".direnv", "result", "result-*", "node_modules" },
  ignore_underscore = true,
  hover = { max_lines = 30 },
}

M.config = vim.deepcopy(DEFAULTS)

local warned = false

local function merge(opts)
  opts = opts or {}
  local config = vim.deepcopy(DEFAULTS)
  config.root_markers = opts.root_markers and vim.deepcopy(opts.root_markers) or config.root_markers
  config.ignore = opts.ignore and vim.deepcopy(opts.ignore) or config.ignore
  if opts.ignore_underscore ~= nil then
    config.ignore_underscore = opts.ignore_underscore
  end
  config.hover = vim.tbl_extend("force", config.hover, opts.hover or {})
  return config
end

function M.setup(opts)
  local config = merge(opts)
  M.config = config
  vim.lsp.config("flake-nav", {
    cmd = require("flake-nav.server").create(config),
    filetypes = { "nix" },
    root_dir = function(bufnr, on_dir)
      if not require("flake-nav.parse").available() then
        if not warned then
          warned = true
          vim.notify("flake-nav: tree-sitter parser for nix not found", vim.log.levels.WARN)
        end
        return
      end
      local root = vim.fs.root(bufnr, config.root_markers)
      if root then
        on_dir(root)
      end
    end,
  })
  vim.lsp.enable("flake-nav")
end

return M
