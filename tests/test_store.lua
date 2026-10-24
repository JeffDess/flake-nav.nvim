local T = MiniTest.new_set()
local eq = MiniTest.expect.equality
local store = require("flake-nav.store")

T["source path of a locked input"] = function()
  eq(
    store.source("sha256-SBL/761cGhDjEWW9bNBUg2khQSMDkIqj5IlYYSVeOk0=", "/nix/store"),
    "/nix/store/8y738vc0j1gplfngjlj2i6l7inzp3mhb-source"
  )
end

T["nothing for an unusable hash"] = function()
  eq(store.source("sha512-AAAA", "/nix/store"), nil)
  eq(store.source("sha256-AAAA", "/nix/store"), nil)
  eq(store.source(nil, "/nix/store"), nil)
end

return T
