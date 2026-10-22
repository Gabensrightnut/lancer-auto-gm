#!/usr/bin/env bash
# Downloads Godot's official WebRTC add-on (needed for online play on desktop) into
# addons/webrtc_native. Its binaries aren't committed; CI and developers run this instead.
#   bash addons/fetch_webrtc_native.sh
# Source: https://github.com/godotengine/webrtc-native (MIT). Pinned version + SHA-256.
set -euo pipefail
VERSION="1.2.2-stable"
SHA256="98e9446921740d995bd9ca1be48798dc3c2ceed51e044a25ce18b3cff11f56e5"
URL="https://github.com/godotengine/webrtc-native/releases/download/${VERSION}/godot-extension-webrtc_native.zip"

root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fsSL -o "$tmp/webrtc.zip" "$URL"
echo "${SHA256}  $tmp/webrtc.zip" | sha256sum -c -
# Windows x86_64 only: that's the only platform we ship.
unzip -o -q "$tmp/webrtc.zip" 'addons/webrtc_native/LICENSE*' 'addons/webrtc_native/webrtc_native.gdextension' \
	'addons/webrtc_native/lib/*windows*x86_64*' -d "$root"
echo "webrtc_native ${VERSION} installed in addons/webrtc_native"
