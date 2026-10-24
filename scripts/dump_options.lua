vim.opt.runtimepath:prepend(vim.fn.getcwd())
for dir in vim.gsplit(vim.env.FLAKE_NAV_RTP or "", ",", { plain = true, trimempty = true }) do
  vim.opt.runtimepath:append(dir)
end

local root = (vim.fs.normalize(vim.fn.fnamemodify(arg[1], ":p")):gsub("/$", ""))
local class = arg[2]
local index = require("flake-nav.index").new(root, {
  ignore = { ".git", ".direnv", "result", "result-*", "node_modules" },
  ignore_underscore = true,
})
index:refresh()

local lines = {}
for path, entry in pairs(index.files) do
  for _, decl in ipairs(entry.parsed.options.decls) do
    if decl.leaf and decl.class == class then
      lines[#lines + 1] = ("%s %s:%d"):format(
        decl.path,
        vim.fs.relpath(root, path),
        decl.scope_range[1] + 1
      )
    end
  end
end
table.sort(lines)
io.write(table.concat(lines, "\n"), "\n")
