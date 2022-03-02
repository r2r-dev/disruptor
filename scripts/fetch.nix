{ src }:
let
  versions = builtins.fromJSON (builtins.readFile "${src}/versions.json");
  fetchTarball =
    { url, sha256 }@attrs:
    let
      inherit (builtins) lessThan nixVersion fetchTarball;
    in
    if lessThan nixVersion "1.12" then
      fetchTarball { inherit url; }
    else
      fetchTarball attrs;
in
builtins.mapAttrs
  (_: spec:
    fetchTarball {
      url =
        with spec;
        "https://github.com/${owner}/${repo}/archive/${rev}.tar.gz";
      inherit (spec) sha256;
    }
  )
  versions
