{
  description = "";
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
    systems.url = "github:nix-systems/default";
    utils.url = "github:numtide/flake-utils";
    utils.inputs.systems.follows = "systems";
  };

  outputs = { nixpkgs, utils, ... }:

    let images = import ./images-lock.nix;
    in utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        deps = with pkgs; [ jq skopeo ];

        # wrap a shell script, adding programs to its PATH
        wrap = { paths ? [ ], vars ? { }, file ? null, script ? null
          , name ? "wrap" }:
          assert file != null || script != null
            || abort "wrap needs 'file' or 'script' argument";
          let
            set = with pkgs.lib;
              n: v:
              "--set ${escapeShellArg (escapeShellArg n)} "
              + "'\"'${escapeShellArg (escapeShellArg v)}'\"'";
            args = (map (p: "--prefix PATH : ${p}/bin") paths)
              ++ (pkgs.lib.attrValues (pkgs.lib.mapAttrs set vars));
          in pkgs.runCommand name {
            f = if file == null then pkgs.lib.writeScript name script else file;
            buildInputs = [ pkgs.makeWrapper ];
          } ''
            makeWrapper "$f" "$out" ${toString args}
          '';
      in {
        apps = {
          build-images-lock = {
            type = "app";
            program = (wrap {
              name = "build-images-lock";
              paths = deps;
              file = ./build-images-lock.sh;
            }).outPath;
          };
        };

        devShells.default = pkgs.mkShell { packages = deps; };

        containers.images = images."${system}" or null;

        formatter = pkgs.nixfmt-classic;
      });
}
