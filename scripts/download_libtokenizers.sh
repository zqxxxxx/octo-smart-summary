#!/bin/sh
set -eu

output_dir=${1:-/usr/local/lib}
chunk_size=262144
arch=$(uname -m)

case "$arch" in
  x86_64)
    asset_arch=amd64
    asset_size=14310968
    asset_sha256=8043d2f258b2f4d84d2bef6868e2b971a37b9979afb9000965b38bce706d52d4
    ;;
  aarch64)
    asset_arch=arm64
    asset_size=14212078
    asset_sha256=8c64d719b7b35d824b7e2ff7fc8c2c49eca806169c11ea71a9c494e909a76399
    ;;
  *)
    printf 'Unsupported architecture: %s\n' "$arch" >&2
    exit 1
    ;;
esac

asset_name="libtokenizers.linux-musl-${asset_arch}.tar.gz"
asset_url="https://github.com/daulet/tokenizers/releases/download/v1.27.0/${asset_name}"
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cached_archive="$script_dir/cache/$asset_name"
work_dir=$(mktemp -d)
archive="$work_dir/$asset_name"
part="$work_dir/part"
trap 'rm -rf "$work_dir"' EXIT INT TERM

if [ -f "$cached_archive" ]; then
  actual=$(wc -c < "$cached_archive" | tr -d ' ')
  if [ "$actual" != "$asset_size" ]; then
    printf 'Cached archive had %s bytes; expected %s\n' "$actual" "$asset_size" >&2
    exit 1
  fi
  cp "$cached_archive" "$archive"
else
  : > "$archive"
  start=0
  while [ "$start" -lt "$asset_size" ]; do
    end=$((start + chunk_size - 1))
    if [ "$end" -ge "$asset_size" ]; then
      end=$((asset_size - 1))
    fi
    expected=$((end - start + 1))
    attempt=1
    while :; do
      rm -f "$part"
      if curl -fLsS --connect-timeout 20 --max-time 45 \
        --range "${start}-${end}" \
        --output "$part" "$asset_url"; then
        actual=$(wc -c < "$part" | tr -d ' ')
        if [ "$actual" = "$expected" ]; then
          break
        fi
        printf 'Range %s-%s had %s bytes; expected %s\n' "$start" "$end" "$actual" "$expected" >&2
      fi
      if [ "$attempt" -ge 5 ]; then
        printf 'Failed to download range %s-%s\n' "$start" "$end" >&2
        exit 1
      fi
      attempt=$((attempt + 1))
      sleep 1
    done
    cat "$part" >> "$archive"
    start=$((end + 1))
  done
fi

printf '%s  %s\n' "$asset_sha256" "$archive" | sha256sum -c -
mkdir -p "$work_dir/extract" "$output_dir"
tar -xzf "$archive" -C "$work_dir/extract"
test -s "$work_dir/extract/libtokenizers.a"
mv "$work_dir/extract/libtokenizers.a" "$output_dir/libtokenizers.a"
