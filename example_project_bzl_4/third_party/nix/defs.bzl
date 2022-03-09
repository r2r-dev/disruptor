load("@io_tweag_rules_nixpkgs//nixpkgs:nixpkgs.bzl", "nixpkgs_local_repository")

NIX_REPOSITORIES = {
    "nixpkgs": "@nixpkgs",
}

def nix_repositories():
    """ Define nix repositories being used. """
    native.new_local_repository(
	name = "nixpkgs-src",
	path = "../",
	build_file_content = '''
	exports_files([
	  "default.nix",
	  "versions.json",
	  "scripts/fetch.nix",
	])
	''',
    )
    nixpkgs_local_repository(
        name = "nixpkgs",
	nix_file = "@nixpkgs-src//:default.nix",
	nix_file_deps = [
	    "@nixpkgs-src//:versions.json",
	    "@nixpkgs-src//:scripts/fetch.nix",
	],
    )
