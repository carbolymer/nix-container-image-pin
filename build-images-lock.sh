#!/usr/bin/env bash

set -euo pipefail

declare -A nixmap

# Map docker platforms to Nix system names
declare -A platform_map=(
  ["linux/amd64"]="x86_64-linux"
  ["linux/arm64"]="aarch64-linux"
  ["linux/arm/v7"]="armv7l-linux"
  ["linux/arm/v6"]="armv6l-linux"
  ["linux/386"]="i686-linux"
)

while read -r image; do
  manifest_json=$(skopeo inspect --raw "docker://$image")
  # Read all manifest entries into an array in the main shell
  mapfile -t entries < <(echo "$manifest_json" | jq -c '.manifests[]')
  for entry in "${entries[@]}"; do
    os=$(echo "$entry" | jq -r '.platform.os')
    arch=$(echo "$entry" | jq -r '.platform.architecture')
    variant=$(echo "$entry" | jq -r '.platform.variant // empty')
    digest=$(echo "$entry" | jq -r '.digest')
    platform="$os/$arch"
    if [[ "$arch" == "arm" && -n "$variant" ]]; then
      platform="$platform/$variant"
    fi
    nixsys="${platform_map[$platform]:-$platform}"
    attrname="$image"
    imgname="${image%%:*}"
    nixmap["$nixsys|$attrname"]="\"$imgname@$digest\""
  done
done < images.txt

# Write to images-lock.nix
{
  echo "{"
  for sys in x86_64-linux aarch64-linux armv7l-linux armv6l-linux i686-linux; do
    echo "  $sys = {"
    for key in "${!nixmap[@]}"; do
      [[ $key == "$sys|"* ]] && echo "    \"${key#*|}\" = ${nixmap[$key]};"
    done
    echo "  };"
  done
  echo "}"
} > images-lock.nix
