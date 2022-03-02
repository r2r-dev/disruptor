{ pkgs ? (import versions.nixpkgs { })
, versions ? (import ./fetch.nix { src = ../.; })
}:
let
  inherit (versions) nixpkgs-2111;
  pkgs-2111 = import nixpkgs-2111 { };
  paths = import ./paths.nix { pkgs = pkgs-2111; };
  bazel_4 = pkgs.callPackage paths.bazel_4 {
    inherit (pkgs.darwin) cctools;
    inherit (pkgs.darwin.apple_sdk.frameworks) CoreFoundation CoreServices Foundation;
    buildJdk = pkgs.jdk11_headless;
    buildJdkName = "java11";
    runJdk = pkgs.jdk11_headless;
    stdenv = if pkgs.stdenv.cc.isClang then pkgs.llvmPackages.stdenv else pkgs.stdenv;
    bazel_self = bazel_4;
  };

  go_1_17 = pkgs.callPackage "${pkgs-2111.path}/pkgs/development/compilers/go/1.17.nix" ({
    inherit (pkgs.darwin.apple_sdk.frameworks) Security Foundation;
  } // pkgs.lib.optionalAttrs (pkgs.stdenv.cc.isGNU && pkgs.stdenv.isAarch64) {
    stdenv = pkgs.gcc8Stdenv;
    buildPackages = pkgs.buildPackages // { stdenv = pkgs.buildPackages.gcc8Stdenv; };
  });

in
pkgs.mkShell {
  buildInputs = with pkgs; [
    bazel_4
    go_1_17
    python37Full
  ];
}
