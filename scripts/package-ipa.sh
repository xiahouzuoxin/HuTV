#!/bin/bash
# Build a device IPA for re-signing by Sideloadly. No Apple credentials required.
set -euo pipefail
repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if [[ $# -gt 0 ]]; then
    echo 'Usage: ./scripts/package-ipa.sh' >&2
    echo 'Optional: HUTV_BUNDLE_ID=your.existing.bundle.id ./scripts/package-ipa.sh' >&2
    exit 2
fi
for tool in xcodegen xcodebuild xcrun python3; do
    command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 1; }
done
output_dir="$repo_dir/output"
mkdir -p "$output_dir"
# Serialize builds sharing the same DerivedData and output file.
lock_dir="$output_dir/.package-ipa.lock"
mkdir "$lock_dir" 2>/dev/null || { echo "Another build is running (lock: $lock_dir)." >&2; exit 1; }
staging_dir=''
cleanup() {
    result=$?
    trap - EXIT
    [[ -z "$staging_dir" ]] || rm -rf "$staging_dir"
    rmdir "$lock_dir"
    if [[ $result -ne 0 ]]; then
        echo 'Packaging failed. Do not import an older output/HuTV.ipa as this build.' >&2
    fi
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
staging_dir=$(mktemp -d "$output_dir/.package-ipa.XXXXXX")
cd "$repo_dir"
./scripts/fetch-vlckit.sh
xcodegen generate
build_args=("CODE_SIGNING_ALLOWED=NO")
if [[ -n "${HUTV_BUNDLE_ID:-}" ]]; then
    build_args+=("PRODUCT_BUNDLE_IDENTIFIER=$HUTV_BUNDLE_ID")
fi
echo "Building Release for arm64; log: $output_dir/package-ipa.log"
if ! xcodebuild -project HuTV.xcodeproj -scheme HuTV -configuration Release \
    -destination 'generic/platform=iOS' -derivedDataPath "$repo_dir/DerivedData/Sideloadly" \
    CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= \
    ARCHS=arm64 ONLY_ACTIVE_ARCH=NO "${build_args[@]}" build \
    > "$output_dir/package-ipa.log" 2>&1; then
    tail -n 60 "$output_dir/package-ipa.log" >&2
    echo 'Build failed. No new IPA was published; do not import an older output.' >&2
    exit 1
fi
mkdir "$staging_dir/Payload"
app="$staging_dir/Payload/HuTV.app"
/usr/bin/ditto "$repo_dir/DerivedData/Sideloadly/Build/Products/Release-iphoneos/HuTV.app" "$app"
[[ -f "$app/Frameworks/MobileVLCKit.framework/MobileVLCKit" ]] || { echo 'Missing VLC framework' >&2; exit 1; }
# Normalize every Mach-O, including embedded frameworks, in the staging copy only.
while IFS= read -r -d '' binary; do
    if /usr/bin/file -b "$binary" | /usr/bin/grep -q 'Mach-O'; then
        archs=$(xcrun lipo -archs "$binary")
        if [[ "$archs" != arm64 ]]; then
            xcrun lipo "$binary" -thin arm64 -output "$staging_dir/thinned"
            cat "$staging_dir/thinned" > "$binary"
            rm "$staging_dir/thinned"
        fi
        if /usr/bin/codesign -d "$binary" >/dev/null 2>&1; then
            /usr/bin/codesign --remove-signature "$binary"
        fi
    fi
done < <(/usr/bin/find "$app" -type f -print0)
/usr/bin/find "$app" -type d -name _CodeSignature -prune -exec rm -rf {} +
/usr/bin/find "$app" -type f -name '*.mobileprovision' -delete
/usr/bin/xattr -cr "$app"
/usr/bin/ditto -c -k --norsrc --keepParent "$staging_dir/Payload" "$staging_dir/HuTV.ipa"
# Validate the actual archive, including architecture, platform and signature commands.
python3 -I - "$staging_dir/HuTV.ipa" <<'PY'
import plistlib, struct, sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as archive:
    assert archive.testzip() is None, 'Corrupt ZIP'
    names = archive.namelist()
    assert all(n.startswith('Payload/') for n in names), 'Unexpected ZIP root'
    assert not any('_CodeSignature' in n.split('/') or n.endswith('.mobileprovision') for n in names), 'Old signing files remain'
    info = plistlib.loads(archive.read('Payload/HuTV.app/Info.plist'))
    assert info['CFBundleSupportedPlatforms'] == ['iPhoneOS'], 'Not a device build'
    required = {'Payload/HuTV.app/' + info['CFBundleExecutable'],
                'Payload/HuTV.app/Frameworks/MobileVLCKit.framework/MobileVLCKit'}
    checked = set()
    for name in names:
        if name.endswith('/'):
            continue
        with archive.open(name) as f:
            magic = f.read(4)
        if magic in (b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca', b'\xca\xfe\xba\xbf', b'\xbf\xba\xfe\xca', b'\xce\xfa\xed\xfe', b'\xfe\xed\xfa\xce', b'\xfe\xed\xfa\xcf'):
            raise AssertionError('Unsupported/unthinned Mach-O: ' + name)
        if magic != b'\xcf\xfa\xed\xfe':
            continue
        data = archive.read(name)
        header = struct.unpack_from('<8I', data)
        assert header[1] == 0x100000c, 'Not arm64: ' + name
        offset = 32
        platform_ok = False
        for _ in range(header[4]):
            command, size = struct.unpack_from('<II', data, offset)
            assert size >= 8 and offset + size <= 32 + header[5] <= len(data), 'Invalid Mach-O'
            assert command != 0x1d, 'Code signature remains: ' + name
            if command == 0x32:  # LC_BUILD_VERSION: iOS device == 2
                assert struct.unpack_from('<I', data, offset + 8)[0] == 2, 'Not iOS device: ' + name
                platform_ok = True
            if command == 0x25:  # LC_VERSION_MIN_IPHONEOS, used by older VLC
                platform_ok = True
            if command == 0x2c:
                assert struct.unpack_from('<I', data, offset + 16)[0] == 0, 'Encrypted binary'
            offset += size
        assert platform_ok, 'Missing iOS platform: ' + name
        checked.add(name)
    assert required <= checked, 'Missing main executable or VLC'
    print('Verified: unsigned arm64 iOS device IPA, including VLC.')
    print('Bundle ID:', info['CFBundleIdentifier'])
PY
# Same-filesystem rename: only a fully validated IPA replaces the previous output.
mv -f "$staging_dir/HuTV.ipa" "$output_dir/HuTV.ipa"
(cd "$output_dir" && /usr/bin/shasum -a 256 HuTV.ipa > HuTV.ipa.sha256)
echo "Ready: $output_dir/HuTV.ipa"
echo 'Import this IPA into Sideloadly with automatic refresh enabled.'
echo 'Replacing this file does not update the Sideloadly cache; re-import and install it.'
