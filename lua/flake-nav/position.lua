local M = {}

function M.to_lsp(line, byte_col)
  return vim.str_utfindex(line, "utf-16", math.min(byte_col, #line), false)
end

function M.to_byte(line, utf16_col)
  return vim.str_byteindex(line, "utf-16", utf16_col, false)
end

function M.lsp_range(lines, range)
  return {
    start = { line = range[1], character = M.to_lsp(lines[range[1] + 1] or "", range[2]) },
    ["end"] = { line = range[3], character = M.to_lsp(lines[range[3] + 1] or "", range[4]) },
  }
end

return M
