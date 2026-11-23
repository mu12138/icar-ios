# 岁岁长安 · iOS 原生版

SwiftUI 写的车控 App，界面用 iOS 原生毛玻璃材质（`.ultraThinMaterial`）。

## 功能（v0.2，对齐 Android 公开版）

**车控**
- 手机号 + 短信验证码登录（token 存 Keychain，自动刷新）
- 车况：油量、续航、车速、车外温度、车锁、空调、总里程、四门/四窗/天窗状态
- 14 个快捷指令：解锁、锁车、开窗、留缝、关窗、天窗翘起、天窗全开、关天窗、启动、熄火、开空调、关空调、闪灯、寻车
- 空调走开放平台（`open.iov.changan.com.cn`，自动完成二维码授权链路）
- 车辆位置 + 一键导航
- 操作二次确认（可关）

**其他页**
- 轨迹：今天 / 7 天 / 30 天，含里程、油耗、均速汇总
- 360 全景：查看、车外拍照、长按删除（服务端）/ 隐藏（本机）
- 设置：控车码、二次确认、操作记录、退出登录

## 更新记录

### v0.15 (14)
- **iOS 网页改成独立一套**：`iCar/WebUI/` 是 iOS 自己的分支，不再从安卓 `core/assets/web`
  同步覆盖；安卓改动不会自动过来，iOS 这边想加功能手动挑。
- 直接从 iOS 那份源码里删掉用不到的功能（不再是运行时藏）：
  - 设置页：通知触发、后台常驻、锁屏保护、通知使用权、通知记录、自启动、省电策略、
    「语音触发」标题和抖音按钮、「指令写法」列表、小组件自动刷新
  - 弹层：通知记录面板（`#ntf-sheet`）
  - JS：`openNtfLog / ntfOn / watchAuth / paintNtf`、通知使用权轮询、`Native.keepAlive`、
    指令写法复制、`#dy-home` 绑定
  - `app.js` 过了 `node --check`，全文已无这些 id/函数引用
- 顺带去掉上一版那段运行时隐藏的注入脚本（不再需要）。

### v0.14 (13)
- **自定义主题 / 背景在 iOS 上真能用了**（之前 `pickBg` 是空实现，点了没反应）：
  - 「选择背景图片」走系统 PHPicker，选完压到长边 1600 存成 `Documents/bg.jpg`，
    本地服务加了一条 `/__bg.jpg` 路由喂给页面，页面照安卓那套 `url("__bg.jpg?v=…")` 用。
  - 模糊、暗度、卡片样式（玻璃/清透）、圆角、阴影、卡片色、文字色、图标色、强调色
    全部落到 `kvGet/kvSet`（UserDefaults），换端口、重启 App 都不丢。
- **9 套预设主题一起带进来**：樱粉 / 暖砂 / 墨灰 / 晴空 / 宝石 / 藕粉 / 冬夜 / 青空 / 深海，
  用的就是安卓 `app.js` 里的 `THEMES` + `bg/*.jpg`（图片随 WebUI 打进包），
  点一下整套换（背景 + 强调色 + 图标色 + 暗度 + 模糊）。
- Info.plist 加 `NSPhotoLibraryUsageDescription`。

### v0.13 (12)
- 加应用图标：`iCar/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`，
  用的就是安卓那份「白色车侧影 + 黑底」图标（`/1000/AI/icar-mod/icon/final_icon_1024.png`），
  透明底先压成纯黑（iOS 图标不能带 alpha），单张 1024 通用尺寸。
- `project.yml` 设 `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`。

### v0.12 (11)
- **隐掉 iOS 上用不了的设置项**（网页是安卓共用那份，用注入 JS 藏，不改原文件）：
  通知触发、后台常驻、锁屏保护、通知使用权、通知记录、自启动、省电策略、「语音触发」标题和
  抖音主页按钮、「指令写法」列表、小组件自动刷新。
- **360 车外拍照改流程**：之前跟着指令轮询走，最多干等 20 秒才刷列表（界面一直「拍摄中…」）。
  现在下发完就先去拉照片，列表空就每 3 秒再拉一次（最多 4 次）；指令失败也照样刷新列表，
  并把失败原因带进提示里。
- ATS 打开 `NSAllowsArbitraryLoads`：长安的照片 CDN 有走 http 的，iOS 默认会拦成裂图。

### v0.11 (10)
- **主界面直接换成安卓那套网页界面**：`iCar/WebUI/` 放的就是安卓 `core/assets/web` 的
  `index.html / app.css / app.js / overlay.js / viewer3d.js`，iOS 只做两件事——
  起本地 HTTP 服务喂页面、用 `NativeBridge` 实现安卓那 38 个 `Native.*` 桥方法。
  这样两边 UI 天然一模一样，以后安卓改了网页，把文件复制过来就行（不用重写 SwiftUI）。
- 桥的两种通道：同步（`state / kvGet / version / pinCode / accepted …`）走
  `prompt("icar:{…}")` 当场返回；异步（`status / exec / trips / photos …`）走
  `window.webkit.messageHandlers.icar` + `window.__cb(id, ok, msg)` 回调。
- 车况 JSON 按安卓 `Ui.statusJson()` 逐字段搬过来（油量三档、门/窗/灯、胎压、发动机转速归一）。
- 3D 模型不重复存：网页里 `3D/*.glb` 由服务器映射到已有的 `CarWeb/3D/`。
- iOS 更新提示暂时关掉（`versionCode` 返回 0）：Gitee 上那份 version.json 是安卓 versionCode，
  拿它比 iOS build 会一直误报「有新版本」。等做 iOS 专用版本源再开。

### v0.10 (9)
- 修「操作成功后顶部还挂着等待车端确认」：把下发和等回执拆成两步——
  指令发出去（拿到 taskId）立刻显示「已下发 · 解锁，等车端回执」，车端回执到了再变「解锁 · 成功」。
  之前是下发+轮询一整段跑完才更新，中间那 20 秒只有一句「等待车端确认」，看着像卡住。
- 车端回执明确失败 / 超时 / 离线时立刻报错（带车端给的原因），不再干等 20 秒超时。
- 顶部提示只清自己那一条：旧定时器不会再把新提示提前抹掉。
- 网络慢时的提示改成「下发中，网络慢」，不再借用「等待车端确认」这种容易误读的说法。

### v0.9 (8)
- 二级页都能返回了：设置、我的轨迹、360 全景 右上角各加一个 X（`CloseButton`），
  之前这几页只能靠下滑关，进了就出不来；所有弹层同时显示拖拽指示条。
- 设置页底部版本号改成读 Info.plist，不再写死「0.3」。

### v0.8 (7)
- 修「车况为空」：`/app2/api/car/data` 服务端现在只收 **POST**，原来用 GET 会被回
  40005「请求方法不支持：GET」，`data` 拿不到 → 首页全空、顶部弹「车况为空」。
  改成 POST 并按安卓版带全参数（`ErrorAutoProjectile=false&toast=false&keys=*&isNev=0`），
  另外留一次 GET 兜底，免得服务端哪天又改回去。
- 错误提示带原因：车况失败时弹的是「车况为空（code msg）」，不再只有四个字，方便直接看出是
  token 过期、方法不支持还是车辆没绑定。
- `code` 兼容字符串：media 等接口把 code 回成 `"2"`，原来只认数字，导致 token 过期不自动刷新；
  现在统一按安卓 `optInt` 的习惯取整。

### v0.7 (6)
- 修 3D 车模加载不出来：WKWebView 用 file:// 打开时，three.js 的 GLTFLoader/RGBELoader
  走 fetch 会被 WebKit 拦掉，表现为「有背景、中间是空的」。改成内置本机 HTTP 服务
  （`CarWebServer`，Network.framework，127.0.0.1 随机端口）喂 three.js，和安卓同一套做法。
  Info.plist 加了 127.0.0.1 / localhost 的 ATS 例外。
- 控车指令加即时反馈：点下去立刻显示「正在下发 · 解锁」，5 秒没回来改「等待车端确认」，
  失败时明确显示「解锁 失败：原因」，不再出现点了没反应也没提示的情况。
- 指令全过程写进「调试信息」，方便排查。
- 修版本号：之前 Info.plist 里写死 0.3/1，导致更新提示一直误报；现在和 project.yml 同步。

### v0.5 (4)
- 内部测试版，版本号有误，已删除。

## 怎么编译

没有 Mac 也能编，用 GitHub Actions 的免费 macOS 机器。

### 1. 传到 GitHub

```bash
cd ios-native
git init
git add .
git commit -m "init"
git branch -M main
git remote add origin git@github.com:你的用户名/icar-ios.git
git push -u origin main
```

**仓库要设为 Public**，公开仓库的 macOS 构建额度是每月 2000 分钟免费。

### 2. 等它自动编译

推上去之后 Actions 会自动跑，大约 3-5 分钟。成功后：

```
Actions → 最新一次运行 → Artifacts → iCar-unsigned-ipa
```

下载得到一个 `iCar-unsigned.ipa`（**未签名**，还不能装）。

### 3. 自签名安装

用电脑上的 **Sideloadly**（Windows/Mac 都有，免费）：

1. 下载 https://sideloadly.io
2. 手机连电脑
3. 把 `iCar-unsigned.ipa` 拖进 Sideloadly
4. Apple ID 填你的（免费账号就行）
5. 点 Start，等它签名并安装

装完第一次打开会提示「不受信任的开发者」，去
**设置 → 通用 → VPN与设备管理** 里信任一下你的 Apple ID。

### 4. 7 天续签

免费 Apple ID 签的 App **7 天过期**，到期打不开。重新用 Sideloadly 走一遍第 3 步即可，不用重新编译。

## 代码结构

```
iCar/
├── iCarApp.swift       入口
├── AppModel.swift      状态管理（@MainActor ObservableObject）
├── ChangAnAPI.swift    接口层（登录、车况、下发指令、token 刷新）
├── RSACrypto.swift     RSA-OAEP(SHA-256) 加密 + SPKI 解析
├── Keychain.swift      Keychain 存储
├── Models.swift        车况模型 + 指令表
├── Theme.swift         玻璃主题（Backdrop / GlassCard / GlassButton / StatTile）
├── LoginView.swift     登录页
└── HomeView.swift      主界面 + 设置页
```

## 和 Android 版的关系

接口完全一致，逻辑是从 Android 版移植的：

| 项 | 说明 |
|---|---|
| 登录 | `/app2/api/oauth2login/token/stageOne` |
| 车辆列表 | `/app2/api/user/cars?type=0` |
| 车况 | `/app2/api/car/data?carId=…&keys=*` |
| 下发指令 | 取一次性码 → 取公钥 → RSA-OAEP 加密 → `/app2/api/v3/control/execute` → 轮询 `getControlInfo` |
| token 刷新 | `m.iov.changan.com.cn` 的 refresh_token |

## 注意

- 这个 App 用了逆向出来的非公开接口，仅自己使用
- 免费账号签名的 App 只有 7 天有效期
- 想长期用需要 $99/年的 Apple 开发者账号
