{ pkgs ? import <nixpkgs> { } }:
pkgs.mkShell {
  buildInputs = with pkgs; [
    cacert
    coreutils-full
    curlFull
    direnv
    gnutar
    nix
    # Dynamically load nix envs
    nix-direnv
  ];
  shellHook = ''
    export TERM=xterm
    export DIRENV_CONFIG=$(pwd)/.cache
    export NIX_USER_CONF_FILES=${./nix.conf}
    . ${pkgs.nix-direnv}/share/nix-direnv/direnvrc
    eval "$(direnv hook bash)"
  '';
  TMPDIR = "/tmp";
}
