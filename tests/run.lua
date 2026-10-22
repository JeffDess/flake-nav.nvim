local file = vim.env.FLAKE_NAV_TEST_FILE or ""
local ok, err = pcall(function()
  if file ~= "" then
    MiniTest.run_file(file)
  else
    MiniTest.run()
  end
end)
if not ok then
  io.stderr:write(tostring(err) .. "\n")
  vim.cmd("cquit 1")
end
