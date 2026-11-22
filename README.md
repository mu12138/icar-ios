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
