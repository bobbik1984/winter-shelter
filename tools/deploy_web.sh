#!/usr/bin/env bash
# 导出网页版并上传到 test.bobbik.org/winter/（vps1 上 /opt/test/winter，Caddy 静态文件，前面是 Cloudflare）。
# 用法：tools/deploy_web.sh [--build-only] [--allow-dirty]
# 只写 /opt/test/winter/，不碰服务器上别的东西。
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
KEY="${DEPLOY_KEY:-$HOME/.ssh/vps1_deploy_ed25519}"
DEST="${DEPLOY_DEST:-ubuntu@100.64.0.1:/opt/test/winter/}"
URL="${DEPLOY_URL:-https://test.bobbik.org/winter/}"
build_only=0; allow_dirty=0
for a in "$@"; do
  case "$a" in
    --build-only) build_only=1 ;;
    --allow-dirty) allow_dirty=1 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

sha=$(git rev-parse --short HEAD)
if ! git diff --quiet HEAD -- . ; then
  if [ $allow_dirty = 0 ]; then
    echo "有未提交的改动：线上版本会对不上任何提交。先提交，或加 --allow-dirty。" >&2
    exit 1
  fi
  sha="$sha-dirty"
fi
echo "$sha" > build_info.txt

stage_parent="${WINTER_STAGE_ROOT:-$HOME/work/local/stage/winter-shelter}"
mkdir -p "$stage_parent"
out_dir=$(mktemp -d "$stage_parent/web-XXXXXXXX")
"$GODOT" --headless --path . --import >/dev/null 2>&1
# 导出缓存可能留着旧的脚本默认值（见 tools/dump_resource_values.gd），每次都重新转换
rm -rf .godot/exported
export_log=$(mktemp)
trap 'rm -f "$export_log"' EXIT
if ! "$GODOT" --headless --path . --export-release "Web" "$out_dir/index.html" > "$export_log" 2>&1; then
  tail -n 60 "$export_log" >&2
  exit 1
fi
if grep -E 'SCRIPT ERROR|Parse Error|ERROR:' "$export_log"; then
  echo "Web export reported errors" >&2
  exit 1
fi
[ -s "$out_dir/index.pck" ] || { echo "export failed: no index.pck" >&2; exit 1; }

# 游戏数据按内容命名，手机浏览器不会用缓存里的旧版；再加上手机专用的 <head>
python3 - "$sha" "$out_dir" <<'PY'
import hashlib, os, re, sys
sha = sys.argv[1]
d = sys.argv[2]
h = hashlib.sha256(open(f'{d}/index.pck', 'rb').read()).hexdigest()[:10]
pck = f'index-{h}.pck'
os.rename(f'{d}/index.pck', f'{d}/{pck}')
html = open(f'{d}/index.html', encoding='utf-8').read()
assert '"index.pck"' in html and 'GODOT_CONFIG = {' in html
html = html.replace('"index.pck"', f'"{pck}"')
html = html.replace('GODOT_CONFIG = {', f'GODOT_CONFIG = {{"mainPack":"{pck}",', 1)
head = open('web/phone_head.html', encoding='utf-8').read() + open('web/wind_loops.html', encoding='utf-8').read()
# 网页版风声循环由浏览器直接播放（web/wind_loops.html），文件放在页面旁边
import shutil
for f in ('wind_open.wav', 'wind_muffled.wav'):
    shutil.copy(f'assets/audio/{f}', f'{d}/{f}')
html = html.replace('</head>', head + f'<meta name="build" content="{sha}">\n</head>', 1)
open(f'{d}/index.html', 'w', encoding='utf-8').write(html)
print('built', sha, pck, os.path.getsize(f'{d}/{pck}'))
PY

GODOT="$GODOT" tools/check_export_values.sh "$out_dir/$(ls "$out_dir" | grep -E '^index-.*\.pck$')"

[ $build_only = 1 ] && { echo "build only: $out_dir"; exit 0; }

# 先传新文件，HTML 最后切换，旧的 pck 最后才删，上传途中打开的人不会拿到一半
# /download/ 是 tools/deploy_apk.sh 放的 APK 页面，别删
rsync -rtz --delete-after --delay-updates --info=stats1 --filter='P /download/' \
  -e "ssh -i $KEY -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=15" "$out_dir/" "$DEST"

live=$(curl -sS -m 30 -H 'Cache-Control: no-cache' "$URL?v=$sha" | grep -o 'name="build" content="[^"]*"' || true)
[ "$live" = "name=\"build\" content=\"$sha\"" ] || { echo "verify failed: live says '$live', expected $sha" >&2; exit 1; }
pck=$(ls "$out_dir" | grep -E '^index-.*\.pck$')
code=$(curl -sS -m 60 -o /dev/null -w '%{http_code}' "$URL$pck")
[ "$code" = "200" ] || { echo "verify failed: $pck returned $code" >&2; exit 1; }
echo "deployed $sha to $URL"
