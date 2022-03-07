{ pkgs ? import <nixpkgs> { } }:
let
  paths =
    let
      inherit (pkgs)
        disruptorPkgs
        nixpkgs-2111
        ;
    in
    (disruptorPkgs.paths { pkgs = nixpkgs-2111; }) // {
      go_1_17 = "${nixpkgs-2111.path}/pkgs/development/compilers/go/1.17.nix";
    };

  bazel_4 =
    let
      inherit (pkgs)
        callPackage darwin jdk11_headless llvmPackages stdenv
        ;
    in
    callPackage paths.bazel_4 {
      inherit (darwin)
        cctools
        ;
      inherit (darwin.apple_sdk.frameworks)
        CoreFoundation CoreServices Foundation
        ;

      buildJdk = jdk11_headless;
      buildJdkName = "java11";
      runJdk = jdk11_headless;
      stdenv = if stdenv.cc.isClang then llvmPackages.stdenv else stdenv;
      bazel_self = bazel_4;
    };

  go_1_17 =
    let
      inherit (pkgs)
        buildPackages callPackage darwin gcc8Stdenv lib stdenv
        ;
    in
    callPackage paths.go_1_17 (
      {
        inherit (darwin.apple_sdk.frameworks)
          Foundation Security
          ;
      } // lib.optionalAttrs (stdenv.cc.isGNU && stdenv.isAarch64)
        {
          stdenv = gcc8Stdenv;
          buildPackages = buildPackages // {
            stdenv = buildPackages.gcc8Stdenv;
          };
        }
    );
in
pkgs.mkShell {
  buildInputs = with pkgs; [
    cacert
    coreutils-full
    curlFull
    direnv
    gnutar
    nix
    bazel-buildtools
    bazel_4
    go_1_17
    pkgs.python37Full
  ];
  shellHook = ''
    export TERM=xterm
    # readlink as absolute path is needed
    echo "startup --output_base $(readlink -f ./bazel-output)" > "$(pwd)"/.output-bazelrc
  '';
  TMPDIR = "/tmp";
}
