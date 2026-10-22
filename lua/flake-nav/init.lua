local M = {}

local DEFAULTS = {
  root_markers = { "flake.nix" },
  ignore = { ".git", ".direnv", "result", "result-*", "node_modules" },
  ignore_underscore = true,
  hover = { max_lines = 30 },
  filter_with_definitions = true,
  remap_store_paths = true,
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
  for _, key in ipairs({ "filter_with_definitions", "remap_store_paths" }) do
    if opts[key] ~= nil then
      config[key] = opts[key]
    end
  end
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

  local filter = require("flake-nav.filter")
  filter.enabled = config.filter_with_definitions
  filter.remap = config.remap_store_paths
  vim.api.nvim_create_autocmd("LspAttach", {
    group = vim.api.nvim_create_augroup("flake-nav-filter", { clear = true }),
    callback = function(args)
      if vim.bo[args.buf].filetype == "nix" then
        filter.wrap(vim.lsp.get_client_by_id(args.data.client_id))
      end
    end,
  })
end

return M
