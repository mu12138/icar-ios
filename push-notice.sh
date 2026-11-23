#!/usr/bin/env bash
# 按需发公告（和更新提示互不影响，和安卓也互不影响）
#
#   ./push-notice.sh "今晚 23:00 维护，控制指令可能延迟"
#   ./push-notice.sh "新主题上线" https://example.com 查看
set -euo pipefail
cd "$(dirname "$0")"

TEXT="${1:?用法: ./push-notice.sh <公告文字> [跳转链接] [按钮文字]}"
URL="${2:-}"
BTN="${3:-查看}"

python3 - "$TEXT" "$URL" "$BTN" <<'PY'
import json, sys
text, url, btn = sys.argv[1], sys.argv[2], sys.argv[3]
p = 'update/version.json'
d = json.load(open(p))
d.update({'notice': text, 'notice_url': url, 'notice_btn': btn if url else ''})
json.dump(d, open(p, 'w'), ensure_ascii=False, indent=2)
open(p, 'a').write('\n')
print(json.dumps(d, ensure_ascii=False, indent=2))
PY

git add update/version.json
git commit -q -m "推送公告"
for i in 1 2 3; do git push -q origin main && { echo "== 已推送 =="; exit 0; }; sleep 4; done
echo "push 失败，稍后重试一次即可"; exit 1
