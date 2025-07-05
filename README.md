# nix-container-image-pin

Pin your container images!

This repo resolves mutable container tags to hashes ([./images-lock.nix ](`./images-lock.nix`)), so that you can pin your containers and update them with all flake inputs.

## Usage

1. Fork this repo
2. Add your container images to `./images.txt`
3. Run `./build-images-lock.sh`
4. Push your change to the remote
5. Add the following flake input:
  ```nix
    containerImagesPin = {
      url = "github:yourfork/nix-container-image-pin";
      inputs.systems.follows = "systems";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  ```

6. Resolve your image name to an image hash, e.g.:
  ```nix
  {
    home-assistant =
    let img = containerImagesPin.containerImages."${pkgs.system}";
    in {
      image =
        img."ghcr.io/home-assistant/home-assistant:stable";
      volumes = [
        "home-assistant:/config"
        "/etc/localtime:/etc/localtime:ro"
        "/run/dbus:/run/dbus:ro"
      ];
      inherit environment;
      extraPodmanArgs =
        [ "--privileged=True" "--userns=keep-id" "--network=host" ];
    };
  }
  ```
7. Build your configuration. Your container image will be pinned.
