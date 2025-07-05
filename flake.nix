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
    in
    utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

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
              paths = with pkgs; [ git curl jq podman ];
              file = ./build-images-lock.sh;
            }).outPath;
          };
        };

        devShells.default = pkgs.mkShell {
          packages = with pkgs; [ git curl jq podman ];
        };

        containers.images = images."${system}" or null;

        formatter = pkgs.nixfmt-classic;
      });

  nixConfig = {
    extra-substituters = [ "https://cache.iog.io" ];
    extra-trusted-public-keys =
      [ "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ=" ];
    allow-import-from-derivation = true;
  };
}
