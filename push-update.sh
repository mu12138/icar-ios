#!/usr/bin/env bash
# 按需推送更新提示（不自动执行，用户给了下载链接再跑）
#
#   ./push-update.sh 0.18 17 https://pan.quark.cn/s/xxxx "点「去下载」拿新 ipa"
#
# 只改 iOS 自己的 update/version.json，安卓的 icar-update 完全不动。
set -euo pipefail
cd "$(dirname "$0")"

VER="${1:?用法: ./push-update.sh <版本> <build号> <下载链接> [说明]}"
BUILD="${2:?缺 build 号}"
URL="${3:?缺下载链接}"
NOTE="${4:-}"

python3 - "$VER" "$BUILD" "$URL" "$NOTE" <<'PY'
import json, sys
ver, build, url, note = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
p = 'update/version.json'
d = json.load(open(p))
d.update({'code': int(build), 'version': ver, 'url': url, 'note': note or d.get('note', '')})
json.dump(d, open(p, 'w'), ensure_ascii=False, indent=2)
open(p, 'a').write('\n')
print(json.dumps(d, ensure_ascii=False, indent=2))
PY

git add update/version.json
git commit -q -m "推送更新：v$VER ($BUILD)"
for i in 1 2 3; do git push -q origin main && { echo "== 已推送 =="; exit 0; }; sleep 4; done
echo "push 失败，稍后重试一次即可（文件已改好并 commit）"; exit 1
