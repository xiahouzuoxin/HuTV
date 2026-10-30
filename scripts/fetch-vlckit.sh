#!/bin/sh
set -eu
repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
[ -d "$repo_dir/Vendor/MobileVLCKit.xcframework" ] && exit 0
archive_path="${TMPDIR:-/tmp}/HuTV-MobileVLCKit-3.7.3.tar.xz"
checksum=0d04059906962ddc9a7bd1ebaa12e1f9ae85eb2466116a97a2f46886dd27a0a9
url=https://download.videolan.org/pub/cocoapods/prod/MobileVLCKit-3.7.3-319ed2c0-79128878.tar.xz
if [ ! -f "$archive_path" ] || [ "$(shasum -a 256 "$archive_path" | cut -d ' ' -f 1)" != "$checksum" ]; then
    curl -fL --retry 3 --connect-timeout 20 --continue-at - "$url" -o "$archive_path"
fi
actual_checksum=$(shasum -a 256 "$archive_path" | cut -d ' ' -f 1)
[ "$actual_checksum" = "$checksum" ] || { echo 'MobileVLCKit checksum mismatch' >&2; exit 1; }
# Unpack upstream samples/docs outside the repository and discard them on exit.
staging_dir=$(mktemp -d "${TMPDIR:-/tmp}/HuTV-vlckit.XXXXXX")
trap 'rm -rf "$staging_dir"' EXIT HUP INT TERM
tar -xJf "$archive_path" -C "$staging_dir"
mkdir -p "$repo_dir/Vendor" "$repo_dir/App/Resources"
cp "$staging_dir/MobileVLCKit-binary/COPYING.txt" "$repo_dir/App/Resources/MobileVLCKit-LGPL.txt"
mv "$staging_dir/MobileVLCKit-binary/MobileVLCKit.xcframework" "$repo_dir/Vendor/MobileVLCKit.xcframework"
