# 拍照搜题助手 — iOS 原生版（侧载）

这是一个真正的 iOS 原生 App（Swift + WKWebView），不是网页套壳那么简单——网络请求走**原生 URLSession**，彻底绕开浏览器的 CORS 跨域限制，可以填任意 OpenAI 兼容接口（硅基流动 / DeepSeek / 通义 / 自定义都行）。

**不需要上架 App Store，不需要付费开发者账号**，用免费 Apple ID 就能侧载到自己的手机。

**系统要求：iOS 14.0 及以上**（已针对 iOS 14 适配：部署目标设为 14.0，网页样式避免用了 iOS 14.5+ 才支持的 CSS 写法，无 iOS 15+ 专属 API）。更低版本无法安装。

---

## 重要前提

- 编译 iOS App **必须在 macOS 上**（苹果硬性要求）。本机是 Windows，无法在这里编译。
- 但你可以用 **GitHub Actions 的免费云 Mac** 编译，全程在网页上操作，不用自己有 Mac。
- 侧载需要一台电脑（Windows 或 Mac 都行）+ 一根数据线。

---

## 第一步：用 GitHub Actions 云编译出 IPA

### 1. 创建 GitHub 仓库并上传工程

1. 打开 https://github.com ，登录（没有账号就免费注册一个）。
2. 点右上角 `+` → `New repository`，仓库名随便填（如 `tips-ios`），选 **Private** 或 Public 都行，点 `Create repository`。
3. 把整个 `ios-build` 目录里的**所有文件和文件夹**上传到这个仓库（包括 `.github` 隐藏文件夹）：
   - 在仓库页面点 `uploading an existing file`
   - 把 `ios-build` 里的 `.github/`、`TipScan.xcodeproj/`、`TipScan/` 全选拖进去
   - 点 `Commit changes`

   > 如果不会用网页上传，也可以在电脑上安装 Git 后用命令行：
   > ```bash
   > cd ios-build
   > git init
   > git add .
   > git commit -m "init"
   > git remote add origin https://github.com/你的用户名/仓库名.git
   > git branch -M main
   > git push -u origin main
   > ```

### 2. 触发自动编译

1. 上传后，进入仓库的 `Actions` 标签页。
2. 左侧点 `Build iOS IPA` → 右侧点 `Run workflow` → 再点绿色的 `Run workflow`。
3. 等几分钟（首次约 5-10 分钟），编译成功后，在本次运行的页面往下拉，会看到 `Artifacts` 区域有一个 **`TipScan-IPA`**。
4. 点它下载（需要登录 GitHub），得到一个 zip，解压后里面有 `TipScan.ipa`。

> 如果编译失败，点进失败的步骤看日志，把报错发我，我帮你改。

---

## 第二步：把 IPA 侧载到 iPhone

这里用 **Sideloadly**（免费，Windows/Mac 都支持），用你自己的 Apple ID 签名。

### 1. 安装 Sideloadly

去 https://sideloadly.io/ 下载对应系统的版本并安装。

### 2. 签名安装

1. 手机用数据线连上电脑，iPhone 上弹出的「信任此电脑」点信任。
2. 打开 Sideloadly：
   - **IPA** 栏：选刚才下载的 `TipScan.ipa`
   - **Apple ID** 栏：填你的 Apple ID（用日常的那个免费账号即可，建议专门注册一个）
   - 连接设备会自动识别到你的 iPhone
3. 点 `Start` 开始签名安装。
4. Apple ID 第一次使用会要求登录验证：按提示输入密码，二重验证时选「短信验证码」并输入收到的验证码。
5. 等进度条走完，手机上会出现「搜题助手」图标。

### 3. 信任开发者（首次打开前）

iPhone 上进入 **设置 → 通用 → VPN与设备管理**（或「描述文件与设备管理」）→ 点你的 Apple ID → 点「信任」。

然后就能打开 App 了。

---

## 7 天续签（重要）

免费 Apple ID 签名的 App **7 天后过期**，过期后打不开。续签方法：

- 手机保持连接电脑，重新打开 Sideloadly，再点一次 `Start` 即可（数据会保留）。
- 建议每 6 天续一次。

> 如果你有付费开发者账号（¥688/年），用 Sideloadly 填入对应证书可签 1 年，不用每周续。

---

## 使用

1. 首次打开会自动弹「API 设置」窗口，也可随时点右上角「设置」。
2. 选服务商、填 API Key。推荐**硅基流动**（国内快、注册送额度，cloud.siliconflow.cn）。
   - 接口地址、模型名留空即用预设。
   - 选「自定义」时填你自己的接口地址和模型名（需 OpenAI 兼容格式）。
   - OCR 和 AI 可以选不同服务商。
3. 点「保存」，配置生效。
4. 回到主界面拍照搜题。网络走原生通道，**不受 CORS 限制**，任意兼容接口都能用。

---

## 工程结构

```
ios-build/
├── .github/workflows/build.yml   # 云编译工作流
├── TipScan.xcodeproj/            # Xcode 工程（含共享 scheme）
└── TipScan/
    ├── AppDelegate.swift         # 入口
    ├── ViewController.swift      # 主界面：WKWebView + 原生HTTP桥接 + 拍照
    ├── SettingsViewController.swift  # 原生设置表单
    ├── Info.plist                # 权限配置
    └── Assets/
        ├── index.html            # 内联后的完整页面（532K，与安卓同源）
        └── icon-192.png
```

### 技术要点

- **原生网络桥接**：JS 调 `NativeHttpBridge.post(...)`，经 `WKScriptMessageHandler` 转到原生 `URLSession`，回调 `window.__nativeCb`。iOS 用注入的适配脚本把 `postMessage` 包装成 app.js 期望的形态，**app.js 一行没改**，三端共用。
- **原生设置**：用原生 `UIViewController` + `UIPickerView` 实现，不依赖网页 DOM（安卓版曾踩过网页面板打不开的坑，iOS 直接规避）。
- **拍照**：实现 `WKUIDelegate.runOpenPanelWith`，用 `UIImagePickerController` 支持拍照/相册。
- **更新页面内容**：Assets 里的 `index.html` 是从安卓内联版复制的快照。改了 `mobile/` 后需重新内联并复制到这里，再推送触发重编译。

---

## 常见问题

**Q：编译失败怎么办？**
把 Actions 里的错误日志发我。

**Q：Sideloadly 安装报错「无法验证 App」？**
确认已在 iPhone 设置里信任了开发者证书；或换用 AltStore。

**Q：拍照点不动？**
确认 Info.plist 里相机/相册权限已包含（已配好）；首次使用时系统会弹权限请求，选允许。

**Q：和安卓版数据互通吗？**
不互通，各自独立存储。用设置里的「导出/导入题库」迁移。

**Q：安装时报 bundle id 冲突 / 已安装同名 App？**
工程默认 bundle id 是 `com.tipsscan.ios`。上传 GitHub 前，用文本编辑器打开 `TipScan.xcodeproj/project.pbxproj`，把里面的 `com.tipsscan.ios` 全部替换成你自己的（如 `com.你的名字.tipsscan`），例如 `com.zhangsan.tipsscan`。这能避免和别人侧载的 App 冲突。不改一般也能用，只是如果手机上有同 bundle id 的 App 会覆盖。
