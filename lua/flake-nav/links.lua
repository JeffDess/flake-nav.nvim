local parse = require("flake-nav.parse")

local M = { enabled = true }

local ns = vim.api.nvim_create_namespace("flake-nav-links")

local function group(buf)
  return "flake-nav-links-" .. buf
end

function M.refresh(buf)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  if not M.enabled then
    return
  end
  local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  for _, input in ipairs(parse.inputs(text)) do
    local range = input.range
    vim.api.nvim_buf_set_extmark(buf, ns, range[1], range[2], {
      end_row = range[3],
      end_col = range[4],
      url = input.url,
    })
  end
end

-- NOTE: gx reads the `url` of extmarks under the cursor (vim.ui._get_urls) on Neovim 0.11 and
-- 0.12, while only 0.12 also asks LSP servers for document links.
function M.attach(buf)
  if vim.fs.basename(vim.api.nvim_buf_get_name(buf)) ~= "flake.nix" then
    return
  end
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = vim.api.nvim_create_augroup(group(buf), { clear = true }),
    buffer = buf,
    callback = function()
      M.refresh(buf)
    end,
  })
  M.refresh(buf)
end

function M.detach(buf)
  pcall(vim.api.nvim_del_augroup_by_name, group(buf))
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  end
end

return M
