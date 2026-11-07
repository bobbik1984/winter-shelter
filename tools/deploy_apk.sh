#!/usr/bin/env bash
# 把 GitHub Actions 打好的 APK 放到 test.bobbik.org/winter/download/（vps1 上 /opt/test/winter/download）。
# 用法：tools/deploy_apk.sh [run-id | path/to/file.apk]
#   不给参数：取 android.yml 最近一次成功的构建。
# 只写 /opt/test/winter/download/；deploy_web.sh 的 --delete-after 不会删这个目录。
set -euo pipefail
cd "$(dirname "$0")/.."
KEY="${DEPLOY_KEY:-$HOME/.ssh/vps1_deploy_ed25519}"
DEST="ubuntu@100.64.0.1:/opt/test/winter/download/"
URL="https://test.bobbik.org/winter/download/"
REPO="bobbik1984/winter-shelter"

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
mkdir -p "$work/dl" "$work/site"
arg="${1:-}"
if [ -n "$arg" ] && [ -f "$arg" ]; then
  cp "$arg" "$work/dl/"
else
  run="$arg"
  if [ -z "$run" ]; then
    run=$(gh run list -R "$REPO" -w android.yml -s success -L 1 --json databaseId -q '.[0].databaseId')
    [ -n "$run" ] || { echo "no successful android.yml run" >&2; exit 1; }
  fi
  gh run download "$run" -R "$REPO" -D "$work/dl"
fi
apk=$(find "$work/dl" -name '*.apk' | head -n1)
[ -n "$apk" ] || { echo "no .apk found" >&2; exit 1; }
name=$(basename "$apk")
cp "$apk" "$work/site/$name"

python3 - "$work/site" "$name" <<'PY'
import hashlib, html, os, re, sys, datetime
d, name = sys.argv[1], sys.argv[2]
p = os.path.join(d, name)
size = os.path.getsize(p)
sha256 = hashlib.sha256(open(p, 'rb').read()).hexdigest()
m = re.match(r'winter-shelter-([0-9a-f]+)(-TESTKEY)?\.apk$', name)
commit = m.group(1) if m else '?'
testkey = bool(m and m.group(2))
cfg = open('export_presets.cfg', encoding='utf-8').read()
ver = re.search(r'^version/name="([^"]*)"', cfg, re.M)
ver = ver.group(1) if ver else '?'
date = datetime.datetime.now().strftime('%Y-%m-%d %H:%M')
warn = ('''<p class="warn"><b>测试签名 / Test-signed.</b> 以后用正式签名的版本不能直接覆盖安装，需要先卸载这个（存档会丢）。<br>
Later builds with the real key will not install over this one: uninstall it first (saves are lost).</p>''' if testkey else '')
page = f'''<!doctype html>
<html lang="zh"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Snow Shelter · Android</title>
<style>
:root{{--bg:#f4f6f8;--fg:#1d2329;--muted:#5c6670;--card:#fff;--line:#d9dee3;--accent:#2f6fa8;--warnbg:#fff4e0;--warnfg:#6b4a00}}
@media (prefers-color-scheme:dark){{:root{{--bg:#13171b;--fg:#e4e8ec;--muted:#9aa4ae;--card:#1c2228;--line:#2c343c;--accent:#6aa8e0;--warnbg:#3a2e14;--warnfg:#f0d9a8}}}}
body{{margin:0;background:var(--bg);color:var(--fg);font:16px/1.55 system-ui,-apple-system,"PingFang SC","Noto Sans CJK SC",sans-serif}}
main{{max-width:560px;margin:0 auto;padding:28px 16px 40px}}
h1{{font-size:24px;margin:0 0 4px}} .sub{{color:var(--muted);margin:0 0 22px}}
.btn{{display:block;text-align:center;background:var(--accent);color:#fff;text-decoration:none;font-weight:600;padding:14px;border-radius:10px;font-size:18px}}
.card{{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:14px 16px;margin-top:18px}}
.warn{{background:var(--warnbg);color:var(--warnfg);border-radius:10px;padding:12px 14px;font-size:14px}}
dl{{display:grid;grid-template-columns:auto 1fr;gap:4px 12px;margin:0;font-size:14px}} dt{{color:var(--muted)}} dd{{margin:0;word-break:break-all}}
ol{{padding-left:20px;margin:6px 0 0}} li{{margin:4px 0}} h2{{font-size:16px;margin:0}}
a{{color:var(--accent)}} code{{font-size:12px}}
</style></head><body><main>
<h1>雪中庇护所 Snow Shelter</h1>
<p class="sub">Android 测试版 · Android test build</p>
<a class="btn" href="{html.escape(name)}" download>下载 APK · Download ({size/1048576:.1f} MB)</a>
{warn}
<div class="card"><h2>安装 / Install</h2><ol>
<li>用手机浏览器点上面的按钮下载。<br>Tap the button on the phone to download.</li>
<li>打开下载的文件；系统会要求允许这个浏览器“安装未知应用”，允许一次。<br>Open the file; allow this browser to “install unknown apps” when asked.</li>
<li>需要 64 位手机（arm64），Android 5.0 以上，横屏玩。<br>Needs a 64-bit (arm64) phone, Android 5.0+; plays in landscape.</li>
</ol></div>
<div class="card"><dl>
<dt>版本</dt><dd>{ver} ({commit})</dd>
<dt>包名</dt><dd>org.bobbik.wintershelter</dd>
<dt>签名</dt><dd>{'测试密钥 test key' if testkey else '正式密钥 release key'}</dd>
<dt>上传</dt><dd>{date}</dd>
<dt>SHA-256</dt><dd><code>{sha256}</code></dd>
</dl></div>
<p class="sub" style="margin-top:18px">网页版 / Web version: <a href="../">test.bobbik.org/winter/</a></p>
</main></body></html>
'''
open(os.path.join(d, 'index.html'), 'w', encoding='utf-8').write(page)
print('page for', name, size, sha256[:12])
PY

# APK 先传，页面最后切换；旧 APK 最后删
rsync -rtz --delete-after --delay-updates --info=stats1 \
  -e "ssh -i $KEY -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=15" "$work/site/" "$DEST"

curl -sS -m 30 -H 'Cache-Control: no-cache' "$URL?v=$RANDOM" | grep -q "$name" || { echo "verify failed: page does not link $name" >&2; exit 1; }
hdr=$(curl -sSI -m 60 "$URL$name")
echo "$hdr" | grep -qiE '^HTTP/[0-9.]+ 200' || { echo "verify failed: $name"; echo "$hdr"; exit 1; } >&2
echo "$hdr" | grep -iE '^(content-type|content-length):' || true
echo "deployed $name to $URL"
