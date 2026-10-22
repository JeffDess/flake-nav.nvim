local T = MiniTest.new_set()
local eq = MiniTest.expect.equality
local position = require("flake-nav.position")

T["to_lsp is identity on ASCII"] = function()
  eq(position.to_lsp("abc def", 4), 4)
end

T["to_lsp counts UTF-16 units"] = function()
  eq(position.to_lsp("aé€b", 6), 3)
  eq(position.to_lsp("😀x", 4), 2)
end

T["to_lsp clamps past the end"] = function()
  eq(position.to_lsp("ab", 10), 2)
end

T["to_byte inverts to_lsp"] = function()
  eq(position.to_byte("aé€b", 3), 6)
  eq(position.to_byte("😀x", 2), 4)
end

T["lsp_range converts both ends"] = function()
  local lines = { "x = 1;", "  é = fm.nixos.locale;" }
  eq(position.lsp_range(lines, { 1, 15, 1, 21 }), {
    start = { line = 1, character = 14 },
    ["end"] = { line = 1, character = 20 },
  })
end

return T
