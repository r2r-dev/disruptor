{ pkgs }:
    with pkgs.lib; let
      lines = str:
        filter (s: s != "") (map head (filter isList (builtins.split "([^\n]*)" str)));
      parse = newpath: line: let
        matches = builtins.match "[[:space:]]*([[:graph:]]*)[[:space:]]*=[[:space:]]*callPackage[[:space:]]*([[:graph:]]*)[[:space:]]*.*$" line;
      in
        if (matches == null)
        then matches
        else
          {
            name = elemAt matches 0;
            value = replaceStrings [".."] [newpath] (elemAt matches 1);
          };
      solve = file: newpath:
        listToAttrs (filter (l: l != null) (map (parse newpath) (lines (readFile file))));
    in
      solve "${pkgs.path}/pkgs/top-level/all-packages.nix" "${pkgs.path}/pkgs"
