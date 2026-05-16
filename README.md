# 防御塔攻略 — 手机 App (Flutter)

Android（真悬浮窗，浮在其他 app 上）+ iOS（app 内悬浮按钮）。
连接现有网站 API：`https://info-share.onrender.com`。

代码已经写好（`lib/`）。你机器上还没有工具链，按下面装一次即可。

---

## 1. 装工具链（一次性，Windows）

### a. Flutter SDK
1. 下载：https://docs.flutter.dev/get-started/install/windows
2. 解压到例如 `C:\flutter`
3. 把 `C:\flutter\bin` 加进系统环境变量 `Path`
4. 新开一个终端，跑 `flutter --version` 确认能跑

### b. Android Studio（自带 Android SDK + 正确版本的 JDK）
1. 下载安装：https://developer.android.com/studio
2. 第一次启动它会自动下载 Android SDK
3. 装好后跑：`flutter doctor --android-licenses`（一路 y 接受）
4. 跑 `flutter doctor`，确保 Flutter 和 Android toolkit 都打勾

> 注意：你现在的 Java 是 8，太旧。Android Studio 会带自己的 JDK 17，
> `flutter` 会自动用它，不用手动管 Java。

---

## 2. 生成平台脚手架（在本项目目录里）

`lib/` 和 `pubspec.yaml` 已经写好。只缺自动生成的 `android/` `ios/` 目录。
在 `C:\Users\hres9\info_share_app` 里跑：

```
flutter create . --org com.infoshare --project-name info_share_app --platforms=android,ios
```

`flutter create` **不会覆盖已存在的文件**，所以它只会补出 `android/`、`ios/`、
`.metadata` 等，不动你的 `lib/` 和 `pubspec.yaml`。

然后：

```
flutter pub get
```

---

## 3. Android 悬浮窗需要的手动改动（生成 android/ 之后做一次）

`flutter_overlay_window` 需要权限和一个 overlay 服务。
打开 `android/app/src/main/AndroidManifest.xml`：

### a. 在 `<manifest>` 里、`<application>` 之前加权限：

```xml
<uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>
```

（`REQUEST_INSTALL_PACKAGES` 是自更新装新 APK 用的；首次更新时系统会让用户
开启「允许此来源安装应用」。）

### b. 在 `<application> ... </application>` 里面加 overlay 服务：

```xml
<service
    android:name="flutter.overlay.window.flutter_overlay_window.OverlayService"
    android:exported="false"
    android:foregroundServiceType="specialUse" />
```

（`flutter_overlay_window` 0.4.x 的标准接法，插件 README 也有，如版本不同以插件页为准。）

---

## 4. 跑起来（Android）

手机用 USB 连电脑，打开「开发者选项 → USB 调试」，然后：

```
flutter devices          # 确认看到你的手机
flutter run              # 装上去并实时调试
```

出正式安装包：

```
flutter build apk --release
```

产物在 `build/app/outputs/flutter-apk/app-release.apk`，传给队友直接装。

---

## 5. 发布新版本（自更新流程）

App 不上商店，靠 GitHub Releases 自更新。App 启动时查
`hres91101-create/info_share_app` 的最新 Release，比对版本号，有新版就弹窗问。

每次发版步骤：

1. 改 `pubspec.yaml` 的 `version:`，例如 `0.1.0+1` → `0.2.0+2`
   （`+` 后面是 build number，每次递增）
2. `flutter build apk --release`
3. 去 GitHub repo → Releases → Draft a new release
   - Tag 填 `v0.2.0`（**必须 `v` + 和 pubspec 一致的版本号**）
   - 把 `app-release.apk` 拖进 assets
   - 写更新说明（会显示在 app 的弹窗里）
   - Publish
4. 队友下次打开 app 就会被提示「发现新版本 0.2.0」，点立即更新即可
   （首次会要求开启「允许安装未知应用」）

> 一次性前置：app repo 要先推上 GitHub（见下方「GitHub 仓库」一节）。

---

## 6. iOS 怎么办

- iOS 代码已经在 `lib/` 里（app 内悬浮按钮，**不能**浮在其他 app 上，这是 Apple 限制）
- 编译 iOS 包**必须 macOS**。你在 Windows，两条路：
  1. 借/租一台 Mac，装 Xcode，`flutter build ipa`
  2. 用云 Mac CI（Codemagic 免费额度 / GitHub Actions macOS runner）
     —— 需要时我可以帮你配 CI，让它在云端帮你出 iOS 包
- 在搞定 iOS 之前，先把 Android 跑通用着

---

## 已实现功能

- 设定/记住名字（对应网站的 author 身份）
- 塔列表（笔记数/图片数/战斗中状态，下拉刷新）
- 塔详情：笔记 + 图片按时间线混排，锁定横幅
- 写笔记
- 进攻锁定 / 解锁
- **聊天头式悬浮窗（Android）**：平常一颗球，点开展开成面板，
  滚动看全站最新图片+文字（`/api/recent`），收起回球，关闭按钮关掉。
  底下 app 照常运行，互不影响。
- **iOS**：app 内同款面板（Apple 不允许浮在其他 app 上，这是系统限制，
  连 FB Messenger 的 iOS 版也没有聊天头）

- **自更新**：启动时查 GitHub Releases，有新版弹窗，确认后下载新 APK
  并触发系统安装

## GitHub 仓库（一次性，需要你操作）

机器上没有 `gh` CLI，git 本身不能远程建仓，所以空 repo 要你手动建一次：

1. 上 github.com → New repository
2. 名字填 **`info_share_app`**，账号 `hres91101-create`
3. **不要**勾 README / .gitignore / license（建空仓）
4. 建好后告诉我，我执行：
   ```
   git remote add origin https://github.com/hres91101-create/info_share_app.git
   git push -u origin main
   ```

仓库名写死在 `lib/services/updater.dart`（`owner`/`repo`），如果你用别的名字
告诉我改。

## 之后可加（说一声就做）

- 悬浮窗里点条目跳转到具体塔
- App 内上传图片（文件选择 + multipart）
- 推送通知（有人锁了你关注的塔）
- iOS 云端打包 CI
