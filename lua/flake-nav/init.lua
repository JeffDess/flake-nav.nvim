local M = {}

local DEFAULTS = {
  root_markers = { "flake.nix" },
  ignore = { ".git", ".direnv", "result", "result-*", "node_modules" },
  ignore_underscore = true,
  hover = { max_lines = 30 },
  filter_with_definitions = true,
  remap_store_paths = true,
  input_links = true,
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
  for _, key in ipairs({ "filter_with_definitions", "remap_store_paths", "input_links" }) do
    if opts[key] ~= nil then
      config[key] = opts[key]
    end
  end
  return config
end

function M.open_input()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local url = require("flake-nav.links").url_at(0, cursor[1] - 1, cursor[2])
  if not url then
    vim.notify("flake-nav: no flake input under the cursor", vim.log.levels.WARN)
    return
  end
  vim.ui.open(url)
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

  local links = require("flake-nav.links")
  links.enabled = config.input_links
  local links_group = vim.api.nvim_create_augroup("flake-nav-links", { clear = true })
  vim.api.nvim_create_autocmd({ "LspAttach", "LspDetach" }, {
    group = links_group,
    callback = function(args)
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      if client and client.name == "flake-nav" then
        if args.event == "LspAttach" then
          links.attach(args.buf)
        else
          links.detach(args.buf)
        end
      end
    end,
  })
end

return M
