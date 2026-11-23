#!/usr/bin/env bash
# 一条龙发布：出包 → 压成 zip → 上传夸克 → 推送更新提示 → 校验两个源
#
#   ./publish-ios.sh 1.2
#
# 规矩（用户定的）：任何推送都走这套，先打包成压缩包，再上传夸克，最后才推提示。
set -euo pipefail
cd "$(dirname "$0")"

VER="${1:?用法: ./publish-ios.sh <版本号，如 1.2>}"
QUARK_DIR="/1000-1-e8adecdf/我的分享/iOS控车（先下载后解压）"
SHARE_LINK="https://pan.quark.cn/s/99af162ad542"
NOTE="点「去下载」到网盘拿压缩包（长按压缩包下载后解压）"

echo "== 1/5 出包 =="
./release-ios.sh "$VER"
BUILD=$(sed -n 's/.*CURRENT_PROJECT_VERSION: "\([0-9]*\)".*/\1/p' project.yml | head -1)
IPA="/1000/AI/icar-mod/分享/岁岁长安-iOS原生-v${VER}-unsigned.ipa"
[ -f "$IPA" ] || { echo "找不到 ipa：$IPA"; exit 1; }

echo "== 2/5 压缩 =="
TMP=$(mktemp -d)
cp "$IPA" "$TMP/"
ZIP="岁岁长安-iOS原生-v${VER}.zip"
(cd "$TMP" && zip -q "$ZIP" "$(basename "$IPA")")
cp "$TMP/$ZIP" "/1000/AI/icar-mod/分享/$ZIP"
echo "== 3/5 上传夸克 =="
mkdir -p "$QUARK_DIR"
cp "$TMP/$ZIP" "$QUARK_DIR/"
chown 1001:1001 "/1000/AI/icar-mod/分享/$ZIP" "$QUARK_DIR/$ZIP" 2>/dev/null || true
sync
rm -rf "$TMP"

echo "== 4/5 推送更新提示 =="
./push-update.sh "$VER" "$BUILD" "$SHARE_LINK" "$NOTE"

echo "== 5/5 校验两个源 =="
for u in "https://raw.githubusercontent.com/mu12138/icar-ios/main/update/version.json" \
         "https://cdn.jsdelivr.net/gh/mu12138/icar-ios@main/update/version.json"; do
  echo "--- $u"
  curl -sL -m 20 "$u?t=$(date +%s)" | python3 -c "import json,sys;d=json.load(sys.stdin);print('code',d['code'],'ver',d['version'],'url',d['url'])" || echo "（还没刷新，稍等几分钟）"
done

echo "== 完成 =="
ls -lh "$IPA" "/1000/AI/icar-mod/分享/$ZIP" "$QUARK_DIR/$ZIP"
