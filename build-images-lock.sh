#!/usr/bin/env bash

set -euo pipefail

# Single-line echo to fd 3 (saved stderr) is atomic (< PIPE_BUF) — safe from parallel jobs
exec 3>&2
log() { echo "$*" >&3; }

declare -A nixmap

declare -A platform_map=(
  ["linux/amd64"]="x86_64-linux"
  ["linux/arm64"]="aarch64-linux"
  ["linux/arm/v7"]="armv7l-linux"
  ["linux/arm/v6"]="armv6l-linux"
  ["linux/386"]="i686-linux"
)

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# Phase 1: resolve all image digests from manifests (no downloads)
declare -a job_keys job_imgrefs job_images job_archs job_oss job_variants
job_count=0

while read -r image; do
  log "Resolving manifest: $image"
  manifest_json=$(skopeo --insecure-policy inspect --raw "docker://$image")
  mapfile -t entries < <(echo "$manifest_json" | jq -c '.manifests[] | select(.platform.os != "unknown")')
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
    imgname="${image%%:*}"

    key="$nixsys|$image"
    nixmap["$key"]="$imgname@$digest"
    job_keys[$job_count]="$key"
    job_imgrefs[$job_count]="$imgname@$digest"
    job_images[$job_count]="$image"
    job_archs[$job_count]="$arch"
    job_oss[$job_count]="$os"
    job_variants[$job_count]="$variant"
    ((job_count++)) || true
  done
done < images.txt

# Phase 2: download and hash all images in parallel
log "Downloading and hashing $job_count image(s) in parallel..."
declare -a pids
for ((i = 0; i < job_count; i++)); do
  imgref="${job_imgrefs[$i]}"
  image="${job_images[$i]}"
  arch="${job_archs[$i]}"
  os="${job_oss[$i]}"
  variant="${job_variants[$i]}"
  label="[${imgref##*/} $arch${variant:+/$variant}]"
  log "$label queued"
  (
    tmptar=$(mktemp "$tmpdir/image-XXXXX.tar")
    skopeo_args=(--override-arch "$arch" --override-os "$os")
    [[ -n "$variant" ]] && skopeo_args+=(--override-variant "$variant")
    log "$label downloading..."
    skopeo --insecure-policy copy "${skopeo_args[@]}" "docker://$imgref" "docker-archive://$tmptar:$image" >/dev/null 2>&1
    log "$label hashing..."
    nix hash file --sri "$tmptar"
    log "$label done"
    rm -f "$tmptar"
  ) > "$tmpdir/hash-$i" 2>"$tmpdir/err-$i" &
  pids[$i]=$!
done

# Wait for all jobs and collect results
declare -A nixmap_sha256
fail=0
for ((i = 0; i < job_count; i++)); do
  if wait "${pids[$i]}"; then
    nixmap_sha256["${job_keys[$i]}"]=$(< "$tmpdir/hash-$i")
  else
    log "ERROR: job $i (${job_keys[$i]}) failed:"
    cat "$tmpdir/err-$i" >&2
    fail=1
  fi
done
(( fail )) && exit 1

{
  echo "{"
  for sys in x86_64-linux aarch64-linux armv7l-linux armv6l-linux i686-linux; do
    echo "  $sys = {"
    for key in "${!nixmap[@]}"; do
      if [[ $key == "$sys|"* ]]; then
        attrname="${key#*|}"
        echo "    \"$attrname\" = {"
        echo "      ref = \"${nixmap[$key]}\";"
        echo "      sha256 = \"${nixmap_sha256[$key]}\";"
        echo "    };"
      fi
    done
    echo "  };"
  done
  echo "}"
} > images-lock.nix
log "Written images-lock.nix"
