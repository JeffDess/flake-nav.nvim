local eq = MiniTest.expect.equality
local fixture = vim.fs.joinpath(vim.fn.getcwd(), "tests/fixtures/flake")
local filter = require("flake-nav.filter")

local URI = "file:///flake/a.nix"
local WITH = { start = { line = 6, character = 37 }, ["end"] = { line = 6, character = 41 } }
local OTHER = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 4 } }

local T = MiniTest.new_set({
  hooks = {
    post_case = function()
      for _, client in ipairs(vim.lsp.get_clients()) do
        client:stop(true)
      end
      vim.cmd("silent! %bwipeout!")
      filter.store = "/nix/store"
      require("flake-nav").setup()
    end,
  },
})

T["locations"] = MiniTest.new_set()

T["locations"]["drops a single Location on the with keyword"] = function()
  eq(filter.locations({ uri = URI, range = WITH }, URI, WITH), {})
end

T["locations"]["drops matching entries from a Location list"] = function()
  local other = { uri = URI, range = OTHER }
  eq(filter.locations({ { uri = URI, range = WITH }, other }, URI, WITH), { other })
end

T["locations"]["drops a LocationLink on the with keyword"] = function()
  local link = { targetUri = URI, targetRange = OTHER, targetSelectionRange = WITH }
  eq(filter.locations({ link }, URI, WITH), {})
end

T["locations"]["keeps other files and nil"] = function()
  local elsewhere = { uri = "file:///flake/b.nix", range = WITH }
  eq(filter.locations(elsewhere, URI, WITH), elsewhere)
  eq(filter.locations(nil, URI, WITH), nil)
end

local function fake_server(answer)
  return function()
    return {
      request = function(method, params, callback)
        vim.schedule(function()
          if method == "initialize" then
            callback(nil, {
              capabilities = { definitionProvider = true, referencesProvider = true },
            })
          elseif method == "textDocument/definition" or method == "textDocument/references" then
            callback(nil, answer(params))
          else
            callback(nil, nil)
          end
        end)
        return true, 1
      end,
      notify = function()
        return true
      end,
      is_closing = function()
        return false
      end,
      terminate = function() end,
    }
  end
end

local function open_with_fake(answer)
  vim.cmd.edit(vim.fs.joinpath(fixture, "modules/hosts/laptop.nix"))
  local buf = vim.api.nvim_get_current_buf()
  local fake_id = vim.lsp.start(
    { name = "fake-nixd", cmd = fake_server(answer), root_dir = fixture },
    { bufnr = buf }
  )
  vim.wait(2000, function()
    local clients = vim.lsp.get_clients({ bufnr = buf })
    for _, client in ipairs(clients) do
      if not client.initialized then
        return false
      end
    end
    return #clients == 2
  end)
  return buf, fake_id
end

local function definitions(buf, line, character)
  local params = {
    textDocument = { uri = vim.uri_from_bufnr(buf) },
    position = { line = line, character = character },
  }
  local by_name = {}
  for id, response in pairs(vim.lsp.buf_request_sync(buf, "textDocument/definition", params, 2000)) do
    local result = response.result
    local list = result == nil and {} or vim.islist(result) and result or { result }
    by_name[vim.lsp.get_client_by_id(id).name] = #list
  end
  return by_name
end

local function with_keyword(params)
  return { uri = params.textDocument.uri, range = WITH }
end

T["drops the with location another server returns for a resolved module"] = function()
  require("flake-nav").setup()
  local buf = open_with_fake(with_keyword)
  eq(definitions(buf, 6, 59), { ["flake-nav"] = 1, ["fake-nixd"] = 0 })
end

T["keeps it where flake-nav resolves nothing"] = function()
  require("flake-nav").setup()
  local buf = open_with_fake(with_keyword)
  eq(definitions(buf, 6, 20), { ["flake-nav"] = 0, ["fake-nixd"] = 1 })
end

T["keeps other locations of a resolved module"] = function()
  require("flake-nav").setup()
  local buf = open_with_fake(function(params)
    return { uri = params.textDocument.uri, range = OTHER }
  end)
  eq(definitions(buf, 6, 59), { ["flake-nav"] = 1, ["fake-nixd"] = 1 })
end

T["filter_with_definitions = false keeps it"] = function()
  require("flake-nav").setup({ filter_with_definitions = false })
  local buf = open_with_fake(with_keyword)
  eq(definitions(buf, 6, 59), { ["flake-nav"] = 1, ["fake-nixd"] = 1 })
end

local function store_copy()
  local tmp = vim.fn.tempname()
  local root = vim.fs.joinpath(tmp, "repo")
  local copy = vim.fs.joinpath(tmp, "store", "abc123-source")
  for _, dir in ipairs({ root, copy }) do
    vim.fn.mkdir(vim.fs.dirname(dir), "p")
    vim.fn.system({ "cp", "-r", fixture, dir })
    vim.fn.writefile({ "{}" }, vim.fs.joinpath(dir, "flake.lock"))
  end
  filter.store = vim.fs.joinpath(tmp, "store")
  return tmp, root, copy
end

local function open_in(root, answer)
  vim.cmd.edit(vim.fs.joinpath(root, "modules/hosts/laptop.nix"))
  local buf = vim.api.nvim_get_current_buf()
  vim.lsp.start({ name = "fake-nixd", cmd = fake_server(answer), root_dir = root }, { bufnr = buf })
  vim.wait(2000, function()
    local clients = vim.lsp.get_clients({ bufnr = buf })
    for _, client in ipairs(clients) do
      if not client.initialized then
        return false
      end
    end
    return #clients == 2
  end)
  return buf
end

local function fake_uris(buf, method)
  local params = {
    textDocument = { uri = vim.uri_from_bufnr(buf) },
    position = { line = 6, character = 20 },
    context = { includeDeclaration = true },
  }
  for id, response in pairs(vim.lsp.buf_request_sync(buf, method, params, 2000)) do
    if vim.lsp.get_client_by_id(id).name == "fake-nixd" then
      return vim.tbl_map(function(loc)
        return vim.uri_to_fname(loc.uri)
      end, response.result)
    end
  end
end

T["store copies of the flake open in the working tree"] = function()
  local tmp, root, copy = store_copy()
  require("flake-nav").setup()
  local buf = open_in(root, function()
    return {
      {
        uri = vim.uri_from_fname(vim.fs.joinpath(copy, "modules/features/locale.nix")),
        range = OTHER,
      },
    }
  end)
  local expected = { vim.fs.joinpath(root, "modules/features/locale.nix") }
  eq(fake_uris(buf, "textDocument/definition"), expected)
  eq(fake_uris(buf, "textDocument/references"), expected)
  vim.fn.delete(tmp, "rf")
end

T["remap_store_paths = false keeps store locations"] = function()
  local tmp, root, copy = store_copy()
  require("flake-nav").setup({ remap_store_paths = false })
  local target = vim.fs.joinpath(copy, "modules/features/locale.nix")
  local buf = open_in(root, function()
    return { { uri = vim.uri_from_fname(target), range = OTHER } }
  end)
  eq(fake_uris(buf, "textDocument/definition"), { target })
  vim.fn.delete(tmp, "rf")
end

return T
