vim.api.nvim_create_user_command("FlakeNav", function(cmd)
  local root = vim.fs.root(0, require("flake-nav").config.root_markers)
  local index = root and require("flake-nav.server").indexes[root]
  if not index then
    vim.notify("flake-nav: no index for this buffer", vim.log.levels.WARN)
    return
  end
  if cmd.args == "reindex" then
    index:reset()
    index:refresh()
    vim.notify("flake-nav: reindexed " .. root)
    return
  end
  index:refresh()
  local stats = index:stats()
  local scope = {
    detected = "import-tree (" .. table.concat(stats.scope.paths, ", ") .. ")",
    none = "whole root (no import-tree call in flake.nix)",
    unsupported = "whole root (import-tree form not recognised in flake.nix)",
  }
  local lines = {
    "root: " .. stats.root,
    "scope: " .. scope[stats.scope.origin],
    "files: " .. stats.files,
    "definitions: " .. stats.definitions,
    "uses: " .. stats.uses,
  }
  for _, path in ipairs(stats.skipped) do
    lines[#lines + 1] = "unreadable: " .. path
  end
  for _, path in ipairs(stats.with_errors) do
    lines[#lines + 1] = "syntax errors: " .. path
  end
  vim.notify(table.concat(lines, "\n"))
end, {
  nargs = "?",
  complete = function()
    return { "info", "reindex" }
  end,
})
