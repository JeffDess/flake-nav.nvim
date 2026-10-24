local bit = require("bit")

local M = {}

local ALPHABET = "0123456789abcdfghijklmnpqrsvwxyz"

local function base32(bytes)
  local out = {}
  for n = math.floor((#bytes * 8 - 1) / 5), 0, -1 do
    local b = n * 5
    local i, j = math.floor(b / 8) + 1, b % 8
    local value = bit.rshift(bytes[i], j)
    if bytes[i + 1] then
      value = bit.bor(value, bit.lshift(bytes[i + 1], 8 - j))
    end
    local c = bit.band(value, 31) + 1
    out[#out + 1] = ALPHABET:sub(c, c)
  end
  return table.concat(out)
end

-- NOTE: Fixed-output store paths: https://nix.dev/manual/nix/latest/protocols/store-path
function M.source(nar_hash, store_dir)
  local encoded = type(nar_hash) == "string" and nar_hash:match("^sha256%-(.+)$")
  local ok, raw = pcall(vim.base64.decode, encoded or "")
  if not encoded or not ok or #raw ~= 32 then
    return nil
  end
  local hex = raw:gsub(".", function(c)
    return ("%02x"):format(c:byte())
  end)
  local digest = vim.fn.sha256(("source:sha256:%s:%s:source"):format(hex, store_dir))
  local compressed = {}
  for i = 1, 20 do
    compressed[i] = 0
  end
  for i = 0, 31 do
    local byte = tonumber(digest:sub(i * 2 + 1, i * 2 + 2), 16)
    compressed[i % 20 + 1] = bit.bxor(compressed[i % 20 + 1], byte)
  end
  return ("%s/%s-source"):format(store_dir, base32(compressed))
end

return M
