local T = MiniTest.new_set()
local eq = MiniTest.expect.equality
local flakeref = require("flake-nav.flakeref")

local CASES = {
  { "github:cachix/git-hooks.nix", "https://github.com/cachix/git-hooks.nix" },
  { "github:nixos/nixpkgs/nixos-unstable", "https://github.com/nixos/nixpkgs/tree/nixos-unstable" },
  {
    "github:nixos/nixpkgs?ref=nixos-unstable",
    "https://github.com/nixos/nixpkgs/tree/nixos-unstable",
  },
  { "github:nixos/nixpkgs?rev=abc123", "https://github.com/nixos/nixpkgs/commit/abc123" },
  { "github:nixos/nixpkgs/main?rev=abc123", "https://github.com/nixos/nixpkgs/commit/abc123" },
  { "github:numtide/treefmt?dir=nix", "https://github.com/numtide/treefmt/tree/HEAD/nix" },
  { "github:numtide/treefmt/main?dir=nix", "https://github.com/numtide/treefmt/tree/main/nix" },
  { "github:owner/repo?host=git.example.org", "https://git.example.org/owner/repo" },
  { "gitlab:veloren/veloren", "https://gitlab.com/veloren/veloren" },
  { "gitlab:veloren/veloren/master", "https://gitlab.com/veloren/veloren/-/tree/master" },
  { "gitlab:veloren/veloren?rev=abc123", "https://gitlab.com/veloren/veloren/-/commit/abc123" },
  { "gitlab:veloren/veloren?dir=nix", "https://gitlab.com/veloren/veloren/-/tree/HEAD/nix" },
  { "gitlab:group%2Fsub/repo", "https://gitlab.com/group/sub/repo" },
  { "gitlab:owner/repo?host=gitlab.example.org", "https://gitlab.example.org/owner/repo" },
  { "sourcehut:~user/repo", "https://git.sr.ht/~user/repo" },
  { "sourcehut:~user/repo/main", "https://git.sr.ht/~user/repo/tree/main" },
  { "git+https://codeberg.org/owner/repo.git?ref=main", "https://codeberg.org/owner/repo" },
  { "git+http://git.example.org/repo", "http://git.example.org/repo" },
  { "https://example.org/archive.tar.gz", nil },
  { "http://example.org/archive.zip", nil },
  { "tarball+https://example.org/flake", nil },
  { "https://example.org/flake.nix", "https://example.org/flake.nix" },
  { "file+http://example.org/flake.nix", "http://example.org/flake.nix" },
  {
    "https://github.com/nixos/nixpkgs/archive/nixos-unstable.tar.gz",
    "https://github.com/nixos/nixpkgs/tree/nixos-unstable",
  },
  {
    "https://github.com/nixos/nixpkgs/archive/refs/heads/main.zip",
    "https://github.com/nixos/nixpkgs/tree/main",
  },
  {
    "https://github.com/numtide/treefmt/archive/refs/tags/v2.0.tar.gz?dir=nix",
    "https://github.com/numtide/treefmt/tree/v2.0/nix",
  },
  {
    "tarball+https://github.com/nixos/nixpkgs/archive/abc123",
    "https://github.com/nixos/nixpkgs/tree/abc123",
  },
  {
    "https://gitlab.com/group/sub/repo/-/archive/main/repo-main.tar.gz",
    "https://gitlab.com/group/sub/repo/-/tree/main",
  },
  {
    "https://git.sr.ht/~user/repo/archive/v1.0.tar.gz",
    "https://git.sr.ht/~user/repo/tree/v1.0",
  },
  { "https://codeberg.org/owner/repo/archive/main.tar.gz", nil },
  { "tarball+file:///srv/flake.tar.gz", nil },
  { "path:./vendor/flake", nil },
  { "git+file:///srv/repo", nil },
  { "git+ssh://git@example.org/team/repo.git", "https://example.org/team/repo" },
  { "git+ssh://git@git.example.org:2222/team/repo", "https://git.example.org/team/repo" },
  { "git+ssh://git@git.example.org:team/repo.git", "https://git.example.org/team/repo" },
  {
    "git+ssh://git@github.com:nixos/nixpkgs?ref=nixos-unstable",
    "https://github.com/nixos/nixpkgs/tree/nixos-unstable",
  },
  {
    "git+ssh://git@github.com/nixos/nixpkgs.git?ref=nixos-unstable",
    "https://github.com/nixos/nixpkgs/tree/nixos-unstable",
  },
  {
    "git+ssh://git@gitlab.com/veloren/veloren?rev=abc123",
    "https://gitlab.com/veloren/veloren/-/commit/abc123",
  },
  { "git+https://github.com/nixos/nixpkgs?ref=main", "https://github.com/nixos/nixpkgs/tree/main" },
  { "nixpkgs", nil },
  { "flake:nixpkgs", nil },
  { "github:incomplete", nil },
}

for _, case in ipairs(CASES) do
  T["to_url " .. case[1]] = function()
    eq(flakeref.to_url(case[1]), case[2])
  end
end

T["from_attrs builds the same URL as the string form"] = function()
  eq(
    flakeref.from_attrs({
      type = "github",
      owner = "nixos",
      repo = "nixpkgs",
      ref = "nixos-unstable",
    }),
    "https://github.com/nixos/nixpkgs/tree/nixos-unstable"
  )
  eq(
    flakeref.from_attrs({ type = "gitlab", owner = "veloren", repo = "veloren", rev = "abc123" }),
    "https://gitlab.com/veloren/veloren/-/commit/abc123"
  )
  eq(
    flakeref.from_attrs({ type = "git", url = "https://codeberg.org/owner/repo.git" }),
    "https://codeberg.org/owner/repo"
  )
  eq(
    flakeref.from_attrs({
      type = "tarball",
      url = "https://github.com/nixos/nixpkgs/archive/main.tar.gz",
    }),
    "https://github.com/nixos/nixpkgs/tree/main"
  )
  eq(flakeref.from_attrs({ type = "tarball", url = "https://example.org/flake" }), nil)
  eq(
    flakeref.from_attrs({ type = "file", url = "https://example.org/flake.nix" }),
    "https://example.org/flake.nix"
  )
  eq(flakeref.from_attrs({ type = "path", path = "/srv/flake" }), nil)
  eq(flakeref.from_attrs({ type = "github", owner = "nixos" }), nil)
end

return T
