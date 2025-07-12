#!/usr/bin/env nu

let platform_map = {
  "linux/amd64": "x86_64-linux"
  "linux/arm64": "aarch64-linux"
  "linux/arm/v7": "armv7l-linux"
  "linux/arm/v6": "armv6l-linux"
  "linux/386": "i686-linux"
}

open images.txt | lines | par-each { |image|
  let res = skopeo inspect --raw $'docker://($image)' | from json
  $res.manifests | each {|manifest|
    let os = $manifest.platform.os
    let arch = $manifest.platform.architecture
    let variant = $manifest.platform.variant? | default ""
    let platform = if $arch == "arm" and $variant != "" {
      $"($os)/($arch)/($variant)"
    } else {
      $"($os)/($arch)"
    }
    let imgname = $image | split row ":" | get 0
    let nix_platform = $platform_map | get -i $platform
    if ($nix_platform | is-not-empty) {
      {
        $nix_platform: {
          $image: $"($imgname)@($manifest.digest)"
        }
      }
    } else {
      null
    }
  } | reduce {|it| merge $it}
} | reduce {|it| merge deep $it}
  | to json -i 2
  | save -f 'images-lock.json'

