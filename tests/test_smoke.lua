local T = MiniTest.new_set()

T["nix parser is available"] = function()
  local ok, loaded = pcall(vim.treesitter.language.add, "nix")
  MiniTest.expect.equality(ok and loaded, true)
end

return T
