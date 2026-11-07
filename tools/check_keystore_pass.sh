#!/usr/bin/env bash
# 检查正式签名密钥的密码对不对；对了才（可选）存进密码文件，供 tools/build_apk_local.sh 用。
# 用法（在自己的终端里跑，要输入密码）：tools/check_keystore_pass.sh [keystore.p12] [对照用的 bob.apk]
#   - 密码不回显、不进命令行、不进历史；只通过环境变量交给 keytool，用完就清掉。
#   - 打对了：显示密钥里的别名和证书指纹（指纹是公开信息，不是密码）。
#   - 给了一个已签名的 APK（比如 bob 的）：顺便比对是不是同一把密钥。
#   - 打错了可以重试，最多 5 次；什么都不会被改动。
set -uo pipefail
KS="${1:-$HOME/credentials/bobbik-release.p12}"
REF_APK="${2:-}"
PASSF="${APK_KEY_PASS_FILE:-$HOME/.config/winter-shelter/keystore-pass}"
[ -f "$KS" ] || { echo "keystore not found: $KS" >&2; exit 1; }
command -v keytool >/dev/null || { echo "keytool not found (install a JDK)" >&2; exit 1; }
echo "Keystore: $KS"

for try in 1 2 3 4 5; do
  read -rs -p "Keystore password (attempt $try/5): " KS_PASS; echo
  export KS_PASS
  if out=$(keytool -list -v -keystore "$KS" -storetype PKCS12 -storepass:env KS_PASS 2>&1); then
    alias_=$(printf '%s\n' "$out" | sed -n 's/^Alias name: //p' | head -n1)
    sha=$(printf '%s\n' "$out" | sed -n 's/^[[:space:]]*SHA256: //p' | head -n1)
    owner=$(printf '%s\n' "$out" | sed -n 's/^Owner: //p' | head -n1)
    echo "Password is CORRECT."
    echo "  key alias:   $alias_"
    echo "  certificate: $owner"
    echo "  SHA-256:     $sha"
    if [ -n "$REF_APK" ]; then
      if command -v apksigner >/dev/null; then
        ref=$(apksigner verify --print-certs "$REF_APK" 2>/dev/null | sed -n 's/^Signer #1 certificate SHA-256 digest: //p' | head -n1)
        mine=$(printf '%s' "$sha" | tr -d ':' | tr 'A-F' 'a-f')
        if [ -n "$ref" ] && [ "$ref" = "$mine" ]; then
          echo "  $REF_APK is signed with this same key."
        else
          echo "  $REF_APK is NOT signed with this key (its certificate: ${ref:-unreadable})."
        fi
      else
        echo "  (apksigner not found, skipped the APK comparison)"
      fi
    fi
    read -r -p "Save the password to $PASSF for APK builds? [y/N] " yn
    if [ "${yn,,}" = "y" ]; then
      mkdir -p "$(dirname "$PASSF")"
      ( umask 077; printf '%s' "$KS_PASS" > "$PASSF" )
      chmod 600 "$PASSF"
      echo "Saved (readable only by you)."
    else
      echo "Not saved."
    fi
    unset KS_PASS
    exit 0
  fi
  unset KS_PASS
  if printf '%s' "$out" | grep -qiE "password|integrity|tampered|BadPadding|keystore was"; then
    echo "Wrong password."
  else
    echo "keytool could not open the keystore: $(printf '%s' "$out" | head -n1)"
  fi
done
echo "Gave up after 5 attempts; nothing was changed."
exit 1
