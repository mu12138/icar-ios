# 岁岁长安 · iOS 版（新会话从这里接手）

给接手的人/AI 看的项目说明。读完这一篇就能干活，不用再问上下文。

## 一句话

长安车控 App 的 iOS 原生版（SwiftUI），功能和界面以**安卓公开版**为基准 1:1 对齐。
安卓版源码在同项目 `../localapp`（`core/assets/web` 是网页版界面，`core/src/com/icar/core` 是 Java 桥）。

## 位置

- 项目：`/1000/AI/icar-mod/ios-native`（fnOS「我的文件/AI/icar-mod/ios-native」）
- 仓库：`https://github.com/mu12138/icar-ios`（分支 `main`，公开）
- 安卓参考实现：`/1000/AI/icar-mod/localapp`（**只作参考**：iOS 的 `iCar/WebUI` 是独立分支，两边分开更新，别互相覆盖）
- 出包落点：`/1000/AI/icar-mod/分享/` 和夸克网盘根目录 **iOS 测试版**
  （挂载路径 `/1000-1-e8adecdf/iOS 测试版`，可直接写）

## 当前版本

`0.20`（build 19）。改动必须升版本号，**四个字段一起改**（`release-ios.sh` 会自动改）：

```
project.yml:  MARKETING_VERSION / CURRENT_PROJECT_VERSION
project.yml:  CFBundleShortVersionString / CFBundleVersion（在 info.properties 里）
```

只改前两个会出现「装上去显示 0.3」这种问题（0.5/0.6 就是踩了这个坑，已删）。

## 出包（不自动推更新）

```bash
cd /1000/AI/icar-mod/ios-native
./release-ios.sh 0.8      # 升到 0.8 并出包；不带参数 = 用当前版本重编
./push-update.sh <版本> <build> <链接>  # 需要时手动推更新提示
./push-notice.sh "公告文字" [链接]      # 需要时手动发公告
```

脚本做四件事：改版本号 → commit & push → 等 GitHub Actions（macos-15，xcodegen，不签名）→
下载 ipa 存到 `分享/` 和夸克「iOS 测试版」。

已知坑（脚本里已处理）：
- `git push` 走 HTTPS 会间歇性 `GnuTLS recv error`，脚本重试 3 次；真失败就手动多重试几次
- 仓库本地身份已设 `icar <icar@local>`，换机器要重设，否则 commit 失败
- `gh run download` 必须在仓库目录里执行（否则报 not a git repository）

装到手机：Sideloadly + 免费 Apple ID（7 天有效），需开开发者模式并信任证书。

## 已完成（v0.20）

- 手机号 + 验证码登录，token 存 Keychain
- 车况首页（油量/续航/车速/温度/车锁/空调/里程/门窗天窗）
- 14 个快捷指令，含二次确认
- 空调走开放平台 `open.iov.changan.com.cn`（二维码授权链路）
- 3D 车模（与安卓同款 GLB，13 车型，走 WKWebView + three.js）
- 轨迹、360 全景（查看/拍照/长按删除隐藏）、车辆位置、操作记录
- 设置：控车码、二次确认、强调色、抖音入口、更新提示、调试信息
- v0.8 修车况空：`/app2/api/car/data` 改成 POST（GET 现在回 40005），错误弹窗带 code/msg
- v0.9 二级页（设置/轨迹/全景）右上角加 X 关闭按钮，所有弹层显示拖拽条
- v0.20：瘦身（删 1844 行死代码 + 无用资源）、WebView 崩溃恢复、键盘/缓存/固定端口/流式发送/写盘防抖/日志落盘
- v0.19：360 拍照/列表回空时保留旧数据，不再显示成“照片没了”
- v0.18：POST 空 body 对齐安卓（修定位 500）、错误带服务端原文、拍照列表错误可见
- v0.17：出包自动发 GitHub Release + 自动改 update/version.json（更新链接自动推送）
- v0.16：iOS 公告（update/version.json 独立源，jsDelivr + raw 兜底）+ 顶部浮层 + 安全区高度注入
- v0.15：iOS 网页独立（不再同步安卓），已物理删除通知触发/语音/后台常驻/指令写法等源码
- v0.14：自定义背景图（PHPicker → Documents/bg.jpg → /__bg.jpg）+ 9 套预设主题（THEMES/bg）
- v0.13：加 AppIcon（安卓同款车侧影）；单张 1024 通用图标，透明底压黑
- v0.12：iOS 隐藏通知触发/语音入口/后台常驻等安卓专属设置（`WebUIView.iosHideJS`）；360 拍照改「先刷列表」；ATS 允许明文
- **v0.11 主界面改为安卓同款网页界面**：`iCar/WebUI/`（安卓 web 资源）+ `NativeBridge.swift`（38 个桥方法）+ `WebUIView.swift`（WKWebView 容器），SwiftUI 旧页保留但不再用
- v0.10 控车提示分阶段：正在下发 → 已下发等回执 → 成功/失败，不再卡在「等待车端确认」

## 待补（对齐安卓 5.73）

1. **数据来源三档 + 油箱容量** —— 服务器 / 本地计算 / 车端升数；油量百分比按自填油箱算
2. **卡片点按切换** —— 油量 %⇄L、总里程⇄小计、车外⇄车内、平均⇄本次油耗、续航⇄本次里程
3. **外观主题** —— 背景图、玻璃、清透、字体（现在只有强调色）
4. **360 照片删除 / 隐藏**（安卓有服务端删除接口 `removeFileByRecordIds`，可参考 Api.java）
5. **快捷指令排序**
6. **捐赠二维码**（公开版有）
7. **桌面小组件**（WidgetKit）

安卓侧对应实现位置：油量/续航逻辑在 `localapp/core/assets/web/js/app.js` 的
`pickFuel / pickRange / dataSource / tankL`，Java 侧在 `Ui.statusJson`、`WidgetProvider.tankL`。

## 明确不做

- 通知监听（iOS 系统不允许读别的 App 通知）
- 后台常驻刷新
- 快捷指令独立包（安卓那 14 个 APK）

## 关键坑

- **3D 车模不能用 `file://`**：WKWebView 下 three.js 的 GLTFLoader/RGBELoader 走 `fetch`，
  WebKit 会拦，表现是「背景有、车是空的」。必须走 `CarWebServer`（Network.framework，
  监听 127.0.0.1 随机端口）喂页面，Info.plist 要有 127.0.0.1 / localhost 的 ATS 例外。
- 版本号别写死，见上面「当前版本」。
- 指令下发要即时反馈：先弹「正在下发 · 解锁」，5 秒改「等待车端确认」，失败弹原因。
  安卓版有同样的「操作记录」页，可对照。

## 文件职责

| 文件 | 作用 |
|---|---|
| `iCarApp.swift` / `RootView.swift` | 入口、登录/主界面切换 |
| `AppModel.swift` | 全局状态（登录、车况、busy、toast），指令下发入口 `run()` |
| `ChangAnAPI.swift` | 长安接口：登录、车况、指令（PIN→RSA-OAEP→execute→轮询） |
| `API+Features.swift` | 轨迹、全景、位置、操作记录、空调开放平台 `openExec` |
| `RSACrypto.swift` / `Keychain.swift` | 加密、本地存储 |
| `Models.swift` | `CarStatus`（数字字段用 `num()` 解析，兼容字符串）、指令表 |
| `HomeView.swift` | 首页：车况卡、快捷指令格、入口卡片 |
| `CarStageView.swift` / `CarWebServer.swift` | 3D 车模视图 + 本机 HTTP 服务 |
| `CarWeb/` | three.js、GLB 车模（`3D/`）、`carview.html`、`viewer3d.js` |
| `DetailSheet.swift` / `CabinView.swift` / `TripsView.swift` / `PanoramaView.swift` | 详情、车内视角、轨迹、全景 |
| `SettingsView.swift` / `Theme.swift` / `Update.swift` / `DebugLog.swift` | 设置、主题、更新检查、调试日志 |

## 用户习惯（照做）

- 回答短，先结论后证据；不一次性贴大段
- 每次改完必须升版本号 + 写更新记录（`README.md` 的「更新记录」）
- 真机验证由用户做，不要替他点确认
- 不发通知（IM/站内都算），除非他明确说「给通知」
- iOS 出包后自动传到夸克「iOS 测试版」，这条已授权
