# 交接：岁岁长安 · iOS 原生版

> 新会话接手先读这篇，再读同目录 `AGENTS.md`（更细的约定）。读完就能干活，不用问上下文。

---

## 1. 一句话

iOS 客户端是个**原生壳**：界面直接用安卓那套网页（`iCar/WebUI`，WKWebView 加载本地 HTTP 服务），
Swift 只负责数据与系统能力（`NativeBridge` 实现安卓 `Native.*` 那 38 个桥方法）。
所以两端 UI 天然一致，**iOS 的网页是独立分支，不再从安卓同步**。

## 2. 当前状态（2026-11-25）

| 项 | 值 |
|---|---|
| 版本 | **1.1 (24)**（`project.yml` 四个字段一起改，脚本会自动改） |
| 仓库 | `https://github.com/mu12138/icar-ios`（main，公开） |
| 出包落点 | `/1000/AI/icar-mod/分享/`、夸克「iOS 测试版」、「我的分享/iOS控车（先下载后解压）」 |
| 更新/公告源 | 仓库里的 `update/version.json`（iOS 专用，与安卓 `icar-update` 隔离） |
| 线上推送内容 | `code=24 / version=1.1 / url=https://pan.quark.cn/s/99af162ad542`（与安卓同一个网盘链接） |
| 安装方式 | Sideloadly + 免费 Apple ID（7 天重签）；**企业签不稳，别用** |

## 3. 目录

```
/1000/AI/icar-mod/ios-native          ← fnOS：我的文件/AI/icar-mod/ios-native
├─ iCar/
│  ├─ WebUI/            网页界面（index.html / css / js / bg / img / xm / textures / 3D 缩略图）
│  ├─ CarWeb/3D/        3D 车模 glb（25M，网页通过本地服务按 /3D/xxx.glb 取）
│  ├─ NativeBridge.swift  JS 桥：38 个方法 + 车况 JSON 组装 + 背景图选择 + 地图跳转
│  ├─ WebUIView.swift    WKWebView 容器：加载/重试/崩溃恢复/安全区/键盘
│  ├─ CarWebServer.swift 本机 HTTP 服务：端口 17822 优先，分块流式发大文件
│  ├─ ChangAnAPI.swift   登录/车况/下发指令/轮询（含 RSA-OAEP 加密）
│  ├─ API+Features.swift 轨迹/操作记录/定位/360 照片/开放平台空调
│  ├─ Hardening.swift    调试器·越狱探测 + 网页资源 SHA-256 自检
│  ├─ WebHashes.swift    构建时生成，别手改
│  ├─ DebugLog.swift     日志落 Documents/bridge.log
│  ├─ Keychain.swift / RSACrypto.swift / RootView.swift / iCarApp.swift
│  └─ Assets.xcassets    AppIcon（安卓同款白车侧影，1024 已压黑）
├─ update/version.json  iOS 更新/公告源
├─ scripts/gen-web-hashes.py
├─ release-ios.sh   publish-ios.sh   push-update.sh   push-notice.sh
└─ project.yml   AGENTS.md   README.md（更新记录）
```

## 4. 架构要点

- **桥两条通道**：同步（`state/kvGet/version/pinCode/accepted…`）走 `prompt("icar:{…}")` 当场返回；
  异步（`status/exec/trips/photos…`）走 `messageHandlers.icar` + `window.__cb(id, ok, msg)` 回调。
- 网页启动脚本 `NativeBridge.shimJS` 注入 `window.Native`（atDocumentStart）。
- 车况 JSON 按安卓 `Ui.statusJson()` 逐字段搬（油量三档/门窗灯/胎压/转速归一）。
- 网页请求 `__bg.jpg` 由本地服务读 `Documents/bg.jpg`（自定义背景）。
- 安全区：`didFinish` 时把 `--sat/--sab` 写进页面，顶栏不压状态栏。
- 加固：网页 5 个关键文件哈希对不上 → 界面照常、控车指令返回「执行失败，请稍后重试」。

## 5. 发布（用户定的固定流程，顺序别换）

```bash
cd /1000/AI/icar-mod/ios-native
./publish-ios.sh 1.2      # 一条龙：出包 → 压 zip → 上传夸克 → 推更新提示 → 校验两个源
```

拆开是：

1. `./release-ios.sh <版本>`：升版本四个字段 → commit&push → 等 GitHub Actions（macos-15）→
   下载 ipa 到 `分享/` 与夸克「iOS 测试版」→ 发 GitHub Release（资产固定 `iCar-unsigned.ipa`）
2. 压 `岁岁长安-iOS原生-v<版本>.zip`
3. 拷到 `/1000-1-e8adecdf/我的分享/iOS控车（先下载后解压）/`，`chown 1001:1001`
4. `./push-update.sh <版本> <build> https://pan.quark.cn/s/99af162ad542 "点「去下载」到网盘拿压缩包（长按压缩包下载后解压）"`
5. 校验 raw / jsDelivr 两个源

只发公告：`./push-notice.sh "文字" [链接] [按钮文字]`（更新条和公告条可同时存在）。

## 6. 已知限制 / 待办

1. **长安服务端故障**：定位（`/appserver/api/cardata/getCarLocation`）和 360 照片列表
   （`/appserver/api/file/getMediaFilesByUserIdAndCarId`）返回 500「内部服务器错误」，用户其他软件也一样。
   → 等官方恢复后再验；客户端已做「拿不到就保留上次照片」。
2. **小组件**：技术上可做（WidgetKit + App Group），但 **App Group 需要付费开发者账号**；
   免费 ID 重签下小组件读不到数据。等用户决定是否买 $99/年账号再做。
3. **更新提示**：`url` 指向夸克分享页；raw 源约 5 分钟缓存，jsDelivr 推送时自动清。
4. **分享版**：保留捐赠二维码与作者抖音入口（用户明确要求，不做去物料处理）。
5. 网页是 iOS 独立 fork：要安卓的新功能得手动挑；改 UI 只动 `iCar/WebUI`。

## 7. 踩过的坑（别再踩）

- 改完 `iCar/WebUI` 里任何文件，**必须** `python3 scripts/gen-web-hashes.py`，否则 App 判定资源被改 → 控车失败。
  只改 `bg/` 图片不影响（不在哈希表里）。
- POST 不要自动带 `token=…` 表单：安卓这些接口是空 body，多余 body 会让服务端 500。
- 地图 URL 里的中文必须百分号转义，否则 `URL(string:)` 返回 nil（点了没反应）。
- `LSApplicationQueriesSchemes` 不加（iosamap/baidumap/maps），`canOpenURL` 永远 false。
- 端口随机会导致页面 localStorage 失效 → 现在固定 17822，占用才回退。
- `git push` 走 HTTPS 经常 GnuTLS/连接失败，脚本已重试；真失败就再跑一次。
- 版本号四个字段必须一起改（`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` / `CFBundleShortVersionString` / `CFBundleVersion`）。
- `update/**`、`*.md`、`*.sh` 的提交不触发重新编译（workflow `paths-ignore`）。

## 8. 常用命令

```bash
cd /1000/AI/icar-mod/ios-native
./release-ios.sh 1.2          # 只出包
./publish-ios.sh 1.2          # 出包 + 压缩 + 夸克 + 推提示 + 校验
./push-update.sh 1.2 25 <url> # 只推更新提示
./push-notice.sh "公告" [url]  # 只发公告
python3 scripts/gen-web-hashes.py
gh run list --limit 3         # 看 CI
```

日志：手机 文件 App → 岁岁长安 → `bridge.log`（每次网络请求 + 桥调用）。

## 9. 跟用户沟通的约定

- 回答短，先结论再证据；步骤一条一条列。
- 交付物给完整路径 + fnOS 位置；改完必须升版本号并写更新记录。
- 真机/车辆验证由用户做；不要替他点手机上的确认。
- 只有用户明确说「推送」才发更新/公告；默认静默。
