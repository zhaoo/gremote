# GRemote 的 Xcode 分发工程

以后统一通过 Xcode 归档和上传 iOS 版本。工程已固定为：

- Workspace：`GRemote.xcworkspace`
- Scheme：`GRemote`
- Product：`GRemote.app`
- 应用：GRemote
- Bundle ID：`com.izhaoo.gremote`
- Apple Developer Team：从本机 `ios/LocalSigning.xcconfig` 读取，不提交到仓库
- 签名：Automatic Signing
- Flutter：官方 stable `3.24.5`（与 iOS CI 一致）
- 最低系统：iOS 14.0
- 能力：Hotspot Configuration

## 打开工程

始终打开 `ios/GRemote.xcworkspace`，不要单独打开底层兼容工程 `Runner.xcodeproj`。Workspace 包含 CocoaPods 依赖和 GRemote 图像处理框架。

同一份工程只打开一个 Workspace。如果旧的 `Runner.xcworkspace` 已打开，先关闭它再打开 GRemote；同时打开会导致后开的窗口未载入工程目标，Scheme 列表为空、Build/Run/Archive 全部变灰。遇到这种情况，关闭这两个工程窗口，重新打开 `GRemote.xcworkspace`，选择 `GRemote` Scheme 和 `Any iOS Device (arm64)`。

首次克隆仓库或依赖变化后，在仓库根目录执行：

```bash
flutter pub get
python3 scripts/generate_ios_bridges.py
bash scripts/build_ios_imaging.sh
cd ios && pod install
```

使用官方 Flutter stable 3.24.5，并确认 `flutter --version` 输出与之匹配。使用 FVM 时可通过 `fvm flutter` 执行 Flutter 命令；SDK 安装路径由每台机器自行配置。

## 本机签名配置

首次在一台新 Mac 上分发时执行：

```bash
cp ios/LocalSigning.xcconfig.example ios/LocalSigning.xcconfig
```

将本地文件中的 `YOUR_TEAM_ID` 替换为你的 Apple Developer Team ID，并在 Xcode → Settings → Accounts 登录该团队账号。已有正确本地文件时不要覆盖。`LocalSigning.xcconfig` 已被 Git 忽略，项目的 Debug、Profile、Release 配置和测试目标都会继承它；日常归档无需额外命令行参数。

团队信息应在此本地文件中维护。不要在 Xcode 的 Target 设置中另行写死 Team，否则 Xcode 可能把它保存到公开的 `project.pbxproj`。提交前检查 `git diff`，确认没有新增 `DEVELOPMENT_TEAM` 实际值或 `DevelopmentTeam` 属性。仓库不包含签名私钥、证书或描述文件，新机器仍需自己的 Apple Developer 访问权限。

如果 `dist/ios/gremote_imaging.xcframework` 已存在，不需要重复执行图像框架构建脚本。随后打开：

```bash
open ios/GRemote.xcworkspace
```

图像框架必须包含设备和模拟器各自的 dSYM。`scripts/build_ios_imaging.sh` 会生成调试信息、检查 UUID，并将 dSYM 打入 XCFramework。更新旧的无符号框架时，先将旧产物移出该路径，再执行脚本、`pod install` 并重新 Archive；已有归档不会自动更新。不要用新框架的 dSYM 填补旧归档中 UUID 不同的框架。

## 通过 Xcode 上传 TestFlight

1. 在 Xcode 顶部选择 `GRemote` Scheme 和 `Any iOS Device (arm64)`。
2. 上传新构建前先在根目录 `pubspec.yaml` 递增 `version` 或 `+build`，再执行官方 Flutter 的 `flutter pub get`；Xcode 会读取并显示该版本，不要只在 Xcode 中单独修改版本号。
3. 选择 Product → Archive。
4. Archive 完成后在 Organizer 中选择 Distribute App → App Store Connect → Upload。
5. 保持 Automatically manage signing，由 Xcode 使用本机签名配置中的团队完成正式签名。
6. 上传完成后到 App Store Connect 等待处理，再加入 TestFlight 测试组。

上传前可以执行 `python3 scripts/verify_ios_archive.py /完整路径/GRemote.xcarchive`，检查 App/Framework 的必填版本信息、图标尺寸和透明通道、图像框架 dSYM UUID 以及签名。检查通过仍需要 Apple 服务端验证；它不替代上传结果。

构建成功不代表真机验收完成。每个候选版本仍需按 `docs/releases/ios-testflight.md` 记录 iPhone 与 GR III 的连接、实时取景、独立对焦/快门、JPG/DNG 传输、相册权限和导出结果。
