#!/usr/bin/env bash
# 本机打 Android 测试包（GitHub 的构建产物从这边下载太慢、经常断时用）。
# 用法：tools/build_apk_local.sh   → build/android/winter-shelter-<sha>-TESTKEY.apk
# 然后：tools/deploy_apk.sh build/android/winter-shelter-<sha>-TESTKEY.apk
# 需要：Godot 4.3 + Android 导出模板、java、apksigner（Debian 的 android-sdk 包即可）。
# 不改你的编辑器设置：用临时配置目录指向 Java / SDK；SDK 里缺的 adb 用占位脚本（导出用不到它）。
# 签名用本机固定的测试密钥（~/.local/share/winter-shelter/apk-test.p12）：本机测试包之间能覆盖安装；
# 正式密钥的包不能覆盖它，需要先卸载。
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
sha=$(git rev-parse --short HEAD)
git diff --quiet HEAD -- . || sha="$sha-dirty"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"; git checkout -q -- build_info.txt 2>/dev/null || true' EXIT

jh=$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")
bt=$(ls -d /usr/lib/android-sdk/build-tools/* "${ANDROID_HOME:-/nonexistent}"/build-tools/* 2>/dev/null | tail -n1 || true)
[ -n "$bt" ] || { echo "no Android build-tools found" >&2; exit 1; }
mkdir -p "$tmp/sdk/platform-tools" "$tmp/sdk/build-tools" "$tmp/cfg/godot"
ln -s "$bt" "$tmp/sdk/build-tools/$(basename "$bt")"
if command -v adb >/dev/null; then ln -s "$(command -v adb)" "$tmp/sdk/platform-tools/adb"
else printf '#!/bin/sh\nexit 0\n' > "$tmp/sdk/platform-tools/adb"; chmod +x "$tmp/sdk/platform-tools/adb"; fi
printf '[gd_resource type="EditorSettings" format=3]\n\n[resource]\nexport/android/java_sdk_path = "%s"\nexport/android/android_sdk_path = "%s"\n' "$jh" "$tmp/sdk" \
  > "$tmp/cfg/godot/editor_settings-4.3.tres"

mkdir -p build/android
touch build/.gdignore
echo "$sha-android" > build_info.txt
rm -f build/android/unsigned.apk
XDG_CONFIG_HOME="$tmp/cfg" "$GODOT" --headless --path . --export-release "Android" build/android/unsigned.apk 2>&1 | grep -E "ERROR" || true
[ -s build/android/unsigned.apk ] || { echo "export failed" >&2; exit 1; }

# 测试密钥固定存在本机（不进仓库）：以后的本机测试包能直接覆盖安装，存档保留
KEY="${APK_TEST_KEY:-$HOME/.local/share/winter-shelter/apk-test.p12}"
if [ ! -f "$KEY" ]; then
  mkdir -p "$(dirname "$KEY")"
  keytool -genkeypair -keystore "$KEY" -storetype PKCS12 -alias test -storepass testtest -keypass testtest \
    -dname "CN=Snow Shelter local test key" -keyalg RSA -keysize 2048 -validity 3650 >/dev/null 2>&1
  echo "created test key $KEY"
fi
out="build/android/winter-shelter-$sha-TESTKEY.apk"
apksigner sign --ks "$KEY" --ks-type PKCS12 --ks-key-alias test --ks-pass pass:testtest --key-pass pass:testtest \
  --out "$out" build/android/unsigned.apk
apksigner verify "$out"
rm -f build/android/unsigned.apk
echo "built $out ($(stat -c%s "$out") bytes)"
