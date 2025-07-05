#!/bin/bash

declare -A nixmap

while read -r image; do
  # Save manifest output to a variable to avoid subshells
  manifest=$(podman manifest inspect "$image")
  # Use jq to extract platform and digest, then read in the main shell
  while IFS=' ' read -r platform digest; do
    case "$platform" in
      linux/amd64) nixsys="x86_64-linux" ;;
      linux/arm64) nixsys="aarch64-linux" ;;
      linux/arm/v7) nixsys="armv7l-linux" ;;
      linux/arm/v6) nixsys="armv6l-linux" ;;
      linux/386) nixsys="i686-linux" ;;
      *) nixsys="$platform" ;;
    esac
    imgname="${image%%:*}"
    nixmap["$nixsys|$image"]="\"$imgname@${digest}\""
  done < <(echo "$manifest" | jq -r '.manifests[] | "\(.platform.os)/\(.platform.architecture) \(.digest)"')
done < images.txt

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
