#!/usr/bin/env bash
# 构建 iOS 未签名 ipa 并同步到夸克网盘
#
#   ./release-ios.sh           用 project.yml 里现在的版本构建
#   ./release-ios.sh 0.5       先升到 0.5（CURRENT_PROJECT_VERSION 自动 +1）
#
# 流程：推 main → GitHub Actions 跑 macos-15 → 下载 ipa → 存 分享/ 和 夸克「iOS 测试版」
set -euo pipefail
PROJ="$(cd "$(dirname "$0")" && pwd)"
QUARK="/1000-1-e8adecdf/iOS 测试版"
SHARE="/1000/AI/icar-mod/分享"

cd "$PROJ"

if [ $# -ge 1 ]; then
  NEW="$1"
  OLD_BUILD=$(sed -n 's/.*CURRENT_PROJECT_VERSION: "\([0-9]*\)".*/\1/p' project.yml | head -1)
  NEW_BUILD=$(( ${OLD_BUILD:-0} + 1 ))
  sed -i -e "s/MARKETING_VERSION: \"[^\"]*\"/MARKETING_VERSION: \"$NEW\"/" \
         -e "s/CURRENT_PROJECT_VERSION: \"[0-9]*\"/CURRENT_PROJECT_VERSION: \"$NEW_BUILD\"/" \
         -e "s/CFBundleShortVersionString: \"[^\"]*\"/CFBundleShortVersionString: \"$NEW\"/" \
         -e "s/CFBundleVersion: \"[0-9]*\"/CFBundleVersion: \"$NEW_BUILD\"/" project.yml
fi

VER=$(sed -n 's/.*MARKETING_VERSION: "\([^"]*\)".*/\1/p' project.yml | head -1)
BUILD=$(sed -n 's/.*CURRENT_PROJECT_VERSION: "\([0-9]*\)".*/\1/p' project.yml | head -1)
echo "== iOS v$VER ($BUILD) =="

git add -A
if ! git diff --cached --quiet; then
  git commit -q -m "v$VER ($BUILD)"
fi
# GitHub 偶尔 TLS 断（GnuTLS recv error），重试几次
for i in 1 2 3; do
  git push -q origin main && break
  [ "$i" = 3 ] && { echo "push 失败（试了 3 次）"; exit 1; }
  sleep 3
done

# 等这次推送触发的 run（按 commit sha 匹配，避免抓到上一次的 run）
SHA=$(git rev-parse HEAD)
RUN=""
for i in $(seq 1 30); do
  RUN=$(gh run list --limit 20 --json databaseId,headSha -q ".[] | select(.headSha==\"$SHA\") | .databaseId" | head -1)
  [ -n "$RUN" ] && break
  sleep 4
done
[ -z "$RUN" ] && { echo "没等到 Actions run（sha=$SHA）"; exit 1; }
echo "run=$RUN"
gh run watch "$RUN" --exit-status >/dev/null || { gh run view "$RUN" --log-failed | tail -40; exit 1; }

TMP=/tmp/ios-ipa-$BUILD
rm -rf "$TMP"; mkdir -p "$TMP"
gh run download "$RUN" -n iCar-unsigned-ipa -D "$TMP"

NAME="岁岁长安-iOS原生-v${VER}-unsigned.ipa"
cp "$TMP/iCar-unsigned.ipa" "$SHARE/$NAME"
mkdir -p "$QUARK"
cp "$TMP/iCar-unsigned.ipa" "$QUARK/$NAME"
sync

# ---- 发到 GitHub Release，给 App 里的「去下载」用 ----
# 资产固定叫 iCar-unsigned.ipa，链接就能长期不变：
# https://github.com/mu12138/icar-ios/releases/latest/download/iCar-unsigned.ipa
REL_TAG="v$VER"
UP="$TMP/upload"; rm -rf "$UP"; mkdir -p "$UP"
cp "$TMP/iCar-unsigned.ipa" "$UP/iCar-unsigned.ipa"
if gh release view "$REL_TAG" >/dev/null 2>&1; then
  gh release upload "$REL_TAG" "$UP/iCar-unsigned.ipa" --clobber
else
  gh release create "$REL_TAG" "$UP/iCar-unsigned.ipa" \
    --title "v$VER ($BUILD)" \
    --notes "未签名 ipa，用 Sideloadly + 免费 Apple ID 安装（7 天有效）"
fi

# ---- 更新 App 自己读的那份 version.json（iOS 独立，不动安卓） ----
python3 - "$BUILD" "$VER" <<'PYEOF'
import json, sys
build, ver = sys.argv[1], sys.argv[2]
p = 'update/version.json'
try:
    d = json.load(open(p))
except Exception:
    d = {}
d['code'] = int(build)
d['version'] = ver
d['url'] = 'https://github.com/mu12138/icar-ios/releases/latest/download/iCar-unsigned.ipa'
d['note'] = '未签名 ipa，用 Sideloadly 安装（7 天有效）'
d.setdefault('code_text', '')
d.setdefault('notice', '')
d.setdefault('notice_url', '')
d.setdefault('notice_btn', '')
json.dump(d, open(p, 'w'), ensure_ascii=False, indent=2)
open(p, 'a').write('\n')
PYEOF

git add update/version.json
if ! git diff --cached --quiet; then
  git commit -q -m "版本源：v$VER ($BUILD)"
  for i in 1 2 3; do
    git push -q origin main && break
    [ "$i" = 3 ] && echo "version.json push 失败（不影响 install，手动推一次）"
    sleep 3
  done
fi

echo "== 完成 =="
ls -lh "$SHARE/$NAME" "$QUARK/$NAME"
gh release view "$REL_TAG" --json tagName,assets -q '.tagName + " → " + (.assets[0].name // "-")' 2>/dev/null || true
