repo: configuration:
let
  flake = builtins.getFlake repo;
  root = "${flake.outPath}/";
  segments = builtins.filter builtins.isString (builtins.split "\\." configuration);
  evaluated = builtins.foldl' (acc: name: acc.${name}) flake segments;
  isOption = v: builtins.isAttrs v && (v._type or null) == "option";
  inRepo = p: builtins.substring 0 (builtins.stringLength root) p.file == root;
  rel = p: builtins.substring (builtins.stringLength root) (-1) p.file;
  # NOTE: builtins.tryEval only catches throw and assert, and the result must be forced inside it.
  walk =
    path: v:
    let
      lines =
        if isOption v then
          map (p: "${builtins.concatStringsSep "." path} ${rel p}:${toString p.line}") (
            builtins.filter inRepo (v.declarationPositions or [ ])
          )
        else if builtins.isAttrs v then
          builtins.concatMap (n: walk (path ++ [ n ]) v.${n}) (
            builtins.filter (n: n != "_module") (builtins.attrNames v)
          )
        else
          [ ];
      attempt = builtins.tryEval (builtins.deepSeq lines lines);
    in
    if attempt.success then attempt.value else [ ];
in
builtins.concatStringsSep "\n" (walk [ ] evaluated.options) + "\n"
