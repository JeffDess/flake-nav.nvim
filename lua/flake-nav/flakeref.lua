local M = {}

-- NOTE: Flake reference syntax: https://nix.dev/manual/nix/latest/command-ref/new-cli/nix3-flake#flake-references
local FORGES = {
  github = { host = "github.com", tree = "/tree/", commit = "/commit/" },
  gitlab = { host = "gitlab.com", tree = "/-/tree/", commit = "/-/commit/" },
  sourcehut = { host = "git.sr.ht", tree = "/tree/", commit = "/commit/" },
}

local GIT = { ["git+https"] = "https", ["git+http"] = "http", ["git+ssh"] = "https" }
local KNOWN_HOSTS =
  { ["github.com"] = "github", ["gitlab.com"] = "gitlab", ["git.sr.ht"] = "sourcehut" }

local function query(text)
  local params = {}
  for key, value in (text or ""):gmatch("([^&=]+)=([^&]*)") do
    params[key] = value
  end
  return params
end

local function forge_url(kind, owner, repo, ref, params)
  local forge = FORGES[kind]
  local base = ("https://%s/%s/%s"):format(
    params.host or forge.host,
    (owner:gsub("%%2[Ff]", "/")),
    repo
  )
  if params.rev then
    return base .. forge.commit .. params.rev
  end
  ref = params.ref or ref
  if params.dir then
    return base .. forge.tree .. (ref or "HEAD") .. "/" .. params.dir
  end
  if ref then
    return base .. forge.tree .. ref
  end
  return base
end

function M.to_url(ref)
  local scheme, rest = ref:match("^([%w+]+):(.*)$")
  if not scheme then
    return nil
  end
  local body, params = rest:match("^([^?]*)%??(.*)$")
  if FORGES[scheme] then
    local owner, repo, tail = body:match("^([^/]+)/([^/]+)/?(.*)$")
    if not owner then
      return nil
    end
    return forge_url(scheme, owner, repo, tail ~= "" and tail or nil, query(params))
  end
  if GIT[scheme] then
    local authority, path = body:match("^//([^/]+)/(.+)$")
    if not authority then
      return nil
    end
    local host = authority:gsub("^.*@", "")
    -- NOTE: Best guess for SSH remotes: the forge serves its web pages over HTTPS on the same host.
    if scheme == "git+ssh" then
      local name, seg = host:match("^([^:]+):(.+)$")
      if seg and not seg:match("^%d+$") then
        host, path = name, seg .. "/" .. path
      else
        host = name or host
      end
    end
    path = path:gsub("%.git$", "")
    local kind = KNOWN_HOSTS[host]
    local owner, repo = path:match("^(.+)/([^/]+)$")
    if kind and owner then
      return forge_url(kind, owner, repo, nil, query(params))
    end
    return GIT[scheme] .. "://" .. host .. "/" .. path
  end
  if scheme == "https" or scheme == "http" then
    return ref
  end
  return nil
end

function M.from_attrs(attrs)
  if FORGES[attrs.type] then
    if not (attrs.owner and attrs.repo) then
      return nil
    end
    return forge_url(
      attrs.type,
      attrs.owner,
      attrs.repo,
      attrs.ref,
      { rev = attrs.rev, dir = attrs.dir, host = attrs.host }
    )
  end
  if attrs.type == "git" and attrs.url then
    return M.to_url("git+" .. attrs.url)
  end
  if (attrs.type == "tarball" or attrs.type == "file") and attrs.url then
    return attrs.url
  end
  return nil
end

return M
