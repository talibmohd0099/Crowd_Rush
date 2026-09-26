#!/usr/bin/env bash
# Builds the Android APK with Godot's headless editor.
# Used by .github/workflows/android-apk.yml, and runnable locally too.
#
# Required env:
#   GODOT_BIN         path to the Godot 4.6 editor binary
#   ANDROID_SDK_ROOT  Android SDK with build-tools (apksigner, zipalign)
#   JAVA_HOME         JDK 17
# Optional env:
#   OUTPUT_APK        default: build/CrowdRush.apk
#   VERSION_NAME      default: 0.1.0
#   VERSION_CODE      default: 1
#   ANDROID_KEYSTORE_BASE64 / ANDROID_KEYSTORE_ALIAS / ANDROID_KEYSTORE_PASSWORD
#       your own release keystore (recommended, so every build can update the
#       previous install). If missing, a throwaway keystore is generated.
set -euo pipefail

: "${GODOT_BIN:?set GODOT_BIN}"
: "${ANDROID_SDK_ROOT:?set ANDROID_SDK_ROOT}"
: "${JAVA_HOME:?set JAVA_HOME}"
OUTPUT_APK="${OUTPUT_APK:-build/CrowdRush.apk}"
VERSION_NAME="${VERSION_NAME:-0.1.0}"
VERSION_CODE="${VERSION_CODE:-1}"
PRESET="Android"

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"
cd "$ROOT"

# 1. Point the editor at the Android SDK + JDK (editor settings file of 4.6).
GODOT_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/godot"
mkdir -p "$GODOT_CONFIG"
cat > "$GODOT_CONFIG/editor_settings-4.6.tres" <<CFG
[gd_resource type="EditorSettings" format=3]

[resource]
export/android/android_sdk_path = "$ANDROID_SDK_ROOT"
export/android/java_sdk_path = "$JAVA_HOME"
CFG

# 2. Signing keystore.
KEYSTORE="$WORK/release.keystore"
if [[ -n "${ANDROID_KEYSTORE_BASE64:-}" ]]; then
  echo "Using keystore from ANDROID_KEYSTORE_BASE64"
  echo "$ANDROID_KEYSTORE_BASE64" | base64 -d > "$KEYSTORE"
  ALIAS="${ANDROID_KEYSTORE_ALIAS:?set ANDROID_KEYSTORE_ALIAS}"
  PASS="${ANDROID_KEYSTORE_PASSWORD:?set ANDROID_KEYSTORE_PASSWORD}"
else
  echo "::warning::No ANDROID_KEYSTORE_BASE64 secret - signing with a throwaway key. Uninstall the old app before installing a new build."
  ALIAS="crowdrush"
  PASS="crowdrush"
  "$JAVA_HOME/bin/keytool" -genkeypair -v -keystore "$KEYSTORE" -alias "$ALIAS" \
    -keyalg RSA -keysize 2048 -validity 10000 -storepass "$PASS" -keypass "$PASS" \
    -dname "CN=Crowd Rush, O=Crowd Rush, C=US" >/dev/null 2>&1
fi
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$KEYSTORE"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER="$ALIAS"
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$PASS"

# 3. Stamp the version into the export preset (CI copy only).
sed -i "s/^version\/code=.*/version\/code=${VERSION_CODE}/" export_presets.cfg
sed -i "s/^version\/name=.*/version\/name=\"${VERSION_NAME}\"/" export_presets.cfg

# 4. Import assets, then export.
mkdir -p "$(dirname "$OUTPUT_APK")"
"$GODOT_BIN" --headless --path . --import 2>&1 | grep -vE "^\s*$|reimport|loading_editor" || true
"$GODOT_BIN" --headless --path . --export-release "$PRESET" "$OUTPUT_APK" 2>&1 | tee "$WORK/export.log"

if [[ ! -s "$OUTPUT_APK" ]]; then
  echo "::error::Export failed - no APK produced. See log above."
  exit 1
fi
"$ANDROID_SDK_ROOT"/build-tools/*/apksigner verify "$OUTPUT_APK"
ls -lh "$OUTPUT_APK"
echo "APK ready: $OUTPUT_APK (version $VERSION_NAME / code $VERSION_CODE)"
