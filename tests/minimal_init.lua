local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)
for dir in vim.gsplit(vim.env.FLAKE_NAV_RTP or "", ",", { plain = true, trimempty = true }) do
  vim.opt.runtimepath:append(dir)
end
vim.cmd("filetype on")
require("mini.test").setup()
