args:
with {
  fetch = import ./scripts/fetch.nix { };
};
let
  inherit (import fetch.nixpkgs { }) lib;
  nix_config = { } // args;
in
import fetch.nixpkgs
  {
    overlays = [
      (final: prev: {
        disruptorPkgs = {
          paths = import ./scripts/paths.nix;
        };
      })
    ] ++
    # map all remaining channels as overlays
    lib.attrsets.mapAttrsToList
      (
        name: value:
          final: prev: {
            "${name}" = import value nix_config;
          }
      )
      fetch;
  } // nix_config
