local T = MiniTest.new_set()
local eq = MiniTest.expect.equality
local server = require("flake-nav.server")

local OPTS = {
  ignore = { ".git" },
  hover = { max_lines = 30 },
  diagnostics = { unknown = true, unused = true },
}

local function project(files)
  local root = vim.fn.tempname()
  for rel, lines in pairs(files) do
    local path = vim.fs.joinpath(root, rel)
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    vim.fn.writefile(lines, path)
  end
  return root
end

local function start(root, opts)
  local published = {}
  local dispatchers = {
    notification = function(method, params)
      if method == "textDocument/publishDiagnostics" then
        published[#published + 1] = params
      end
    end,
    server_request = function() end,
    on_exit = function() end,
    on_error = function() end,
  }
  return server.create(opts or OPTS)(dispatchers, { root_dir = root }), published
end

local function messages(published, uri)
  local last
  for _, params in ipairs(published) do
    if params.uri == uri then
      last = params
    end
  end
  return last and vim.tbl_map(function(d)
    return d.message
  end, last.diagnostics)
end

local BASE = "{ flake.modules.nixos.base = { }; }"
local HOST = "{ config, ... }: { x = with config.flake.modules.nixos; [ base missing ]; }"

T["open documents are republished after each change"] = function()
  local root = project({ ["flake.nix"] = { "{ outputs = _: { }; }" } })
  local rpc, published = start(root)
  local base = vim.uri_from_fname(vim.fs.joinpath(root, "base.nix"))
  local host = vim.uri_from_fname(vim.fs.joinpath(root, "host.nix"))
  vim.fn.writefile({ BASE }, vim.fs.joinpath(root, "base.nix"))
  vim.fn.writefile({ HOST }, vim.fs.joinpath(root, "host.nix"))
  rpc.notify("textDocument/didOpen", { textDocument = { uri = base, text = BASE } })
  rpc.notify("textDocument/didOpen", { textDocument = { uri = host, text = HOST } })
  vim.wait(1000, function()
    return messages(published, host) ~= nil
  end)
  eq(#published, 2)
  eq(messages(published, base), {})
  eq(messages(published, host), { "Unknown module nixos.missing" })

  rpc.notify("textDocument/didChange", {
    textDocument = { uri = host },
    contentChanges = { { text = "{ }" } },
  })
  vim.wait(1000, function()
    return #published == 4
  end)
  eq(messages(published, base), { "Module nixos.base is never used" })
  eq(messages(published, host), {})

  rpc.notify("textDocument/didClose", { textDocument = { uri = base } })
  vim.wait(1000, function()
    return #published == 6
  end)
  eq(messages(published, base), {})
  vim.fn.delete(root, "rf")
end

T["a document whose diagnostics fail is cleared, the others are still published"] = function()
  local root = project({ ["flake.nix"] = { "{ outputs = _: { }; }" } })
  local diagnostics = require("flake-nav.diagnostics")
  local compute = diagnostics.compute
  diagnostics.compute = function(index, path, cfg)
    if vim.fs.basename(path) == "base.nix" then
      error("boom")
    end
    return compute(index, path, cfg)
  end
  local rpc, published = start(root)
  local base = vim.uri_from_fname(vim.fs.joinpath(root, "base.nix"))
  local host = vim.uri_from_fname(vim.fs.joinpath(root, "host.nix"))
  rpc.notify("textDocument/didOpen", { textDocument = { uri = base, text = BASE } })
  rpc.notify("textDocument/didOpen", { textDocument = { uri = host, text = HOST } })
  vim.wait(1000, function()
    return messages(published, base) ~= nil and messages(published, host) ~= nil
  end)
  diagnostics.compute = compute
  eq(messages(published, base), {})
  eq(messages(published, host), { "Unknown module nixos.missing" })
  vim.fn.delete(root, "rf")
end

T["an unsaved document is in scope"] = function()
  local root = project({ ["flake.nix"] = { "{ outputs = _: { }; }" }, ["host.nix"] = { HOST } })
  local rpc, published = start(root)
  local host = vim.uri_from_fname(vim.fs.joinpath(root, "host.nix"))
  local new = vim.uri_from_fname(vim.fs.joinpath(root, "mods/new.nix"))
  local hidden = vim.uri_from_fname(vim.fs.joinpath(root, "_new.nix"))
  rpc.notify("textDocument/didOpen", { textDocument = { uri = host, text = HOST } })
  rpc.notify("textDocument/didOpen", {
    textDocument = { uri = hidden, text = "{ flake.modules.nixos.missing = { }; }" },
  })
  vim.wait(1000, function()
    return messages(published, hidden) ~= nil
  end)
  eq(messages(published, host), { "Unknown module nixos.base", "Unknown module nixos.missing" })
  rpc.notify("textDocument/didOpen", {
    textDocument = { uri = new, text = "{ flake.modules.nixos.missing = { }; }" },
  })
  vim.wait(1000, function()
    return messages(published, new) ~= nil
  end)
  eq(messages(published, host), { "Unknown module nixos.base" })
  vim.fn.delete(root, "rf")
end

T["edits reuse the index and share one context per publication"] = function()
  local root = project({ ["flake.nix"] = { "{ outputs = _: { }; }" } })
  local rpc, published = start(root)
  local base = vim.uri_from_fname(vim.fs.joinpath(root, "base.nix"))
  local host = vim.uri_from_fname(vim.fs.joinpath(root, "host.nix"))
  rpc.notify("textDocument/didOpen", { textDocument = { uri = base, text = BASE } })
  rpc.notify("textDocument/didOpen", { textDocument = { uri = host, text = HOST } })
  vim.wait(1000, function()
    return messages(published, host) ~= nil
  end)
  local index = server.indexes[root]
  local diagnostics = require("flake-nav.diagnostics")
  local refresh, context, entries = index.refresh, diagnostics.context, index.entries
  local counts = { refresh = 0, context = 0, entries = 0 }
  index.refresh = function(self)
    counts.refresh = counts.refresh + 1
    return refresh(self)
  end
  index.entries = function(self)
    counts.entries = counts.entries + 1
    return entries(self)
  end
  diagnostics.context = function(idx)
    counts.context = counts.context + 1
    return context(idx)
  end
  local count = #published
  for _, text in ipairs({ "{ }", HOST }) do
    rpc.notify("textDocument/didChange", {
      textDocument = { uri = host },
      contentChanges = { { text = text } },
    })
  end
  vim.wait(1000, function()
    return #published > count
  end)
  diagnostics.context = context
  eq({ refresh = counts.refresh, context = counts.context }, { refresh = 0, context = 1 })
  index:refresh()
  eq(counts.entries, 1)
  vim.fn.delete(root, "rf")
end

T["running servers follow a new diagnostics setting"] = function()
  local root = project({ ["flake.nix"] = { "{ outputs = _: { }; }" }, ["host.nix"] = { HOST } })
  local rpc, published = start(root)
  local host = vim.uri_from_fname(vim.fs.joinpath(root, "host.nix"))
  rpc.notify("textDocument/didOpen", { textDocument = { uri = host, text = HOST } })
  vim.wait(1000, function()
    return messages(published, host) ~= nil
  end)
  eq(#messages(published, host), 2)
  server.set_diagnostics(false)
  eq(messages(published, host), {})
  rpc.notify("textDocument/didChange", {
    textDocument = { uri = host },
    contentChanges = { { text = HOST } },
  })
  vim.wait(50)
  eq(messages(published, host), {})
  server.set_diagnostics({ unknown = true, unused = false })
  vim.wait(1000, function()
    return #messages(published, host) > 0
  end)
  eq(#messages(published, host), 2)
  server.set_diagnostics(OPTS.diagnostics)
  vim.fn.delete(root, "rf")
end

T["documents are republished once an input source is read"] = function()
  local nar = "sha256-SBL/761cGhDjEWW9bNBUg2khQSMDkIqj5IlYYSVeOk0="
  local host = "{ config, ... }: { x = with config.flake.modules.nixos; [ shared typo ]; }"
  local root = project({
    ["flake.nix"] = { '{ inputs.lib.url = "github:a/lib"; outputs = _: { }; }' },
    ["flake.lock"] = {
      '{ "nodes": { "root": { "inputs": { "lib": "lib" } },',
      '  "lib": { "locked": { "narHash": "' .. nar .. '" } } },',
      '  "root": "root", "version": 7 }',
    },
    ["module.nix"] = { "{ inputs, ... }: { imports = [ inputs.lib.flakeModules.default ]; }" },
  })
  local store = vim.fn.tempname()
  local source = require("flake-nav.store").source(nar, store)
  vim.fn.mkdir(source, "p")
  vim.fn.writefile({ "{ flake.modules.nixos.shared = { }; }" }, source .. "/shared.nix")
  local rpc, published = start(root)
  server.indexes[root].store_dir = store
  local uri = vim.uri_from_fname(vim.fs.joinpath(root, "host.nix"))
  rpc.notify("textDocument/didOpen", { textDocument = { uri = uri, text = host } })
  vim.wait(1000, function()
    local found = messages(published, uri)
    return found ~= nil and #found == 1
  end)
  eq(messages(published, uri), { "Unknown module nixos.typo" })
  vim.fn.delete(root, "rf")
  vim.fn.delete(store, "rf")
end

T["nothing is published when disabled"] = function()
  local root = project({ ["flake.nix"] = { "{ outputs = _: { }; }" }, ["host.nix"] = { HOST } })
  local rpc, published = start(root, { ignore = {}, hover = { max_lines = 30 } })
  local host = vim.uri_from_fname(vim.fs.joinpath(root, "host.nix"))
  rpc.notify("textDocument/didOpen", { textDocument = { uri = host, text = HOST } })
  vim.wait(50)
  eq(published, {})
  vim.fn.delete(root, "rf")
end

return T
