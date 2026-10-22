vim.opt.runtimepath:prepend(vim.fn.getcwd())
for dir in vim.gsplit(vim.env.FLAKE_NAV_RTP or "", ",", { plain = true, trimempty = true }) do
  vim.opt.runtimepath:append(dir)
end

local root = (vim.fs.normalize(vim.fn.fnamemodify(arg[1], ":p")):gsub("/$", ""))
local index = require("flake-nav.index").new(root, {
  ignore = { ".git", ".direnv", "result", "result-*", "node_modules" },
  ignore_underscore = true,
})
index:refresh()

local lines = {}
for path, entry in pairs(index.files) do
  for _, def in ipairs(entry.parsed.defs) do
    lines[#lines + 1] = ("%s.%s %s:%d:%d"):format(
      def.class,
      def.name,
      path,
      def.scope_range[1] + 1,
      def.scope_range[2] + 1
    )
  end
end
table.sort(lines)
io.write(table.concat(lines, "\n"), "\n")
