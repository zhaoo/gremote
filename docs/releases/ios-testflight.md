# iOS TestFlight 准备

当前状态：**代码准备，尚未通过 iOS SDK 编译或真机验收，不可作为可用版本分发。**

## 已加入

- iOS 14+ Runner 工程、应用图标、中文权限说明及 Hotspot Configuration entitlement。
- 由 Pigeon 22.7.4 生成的 Swift 通道；`python3 scripts/generate_ios_bridges.py` 仅刷新 Swift，不覆盖原 Android/Dart 输出。
- CoreBluetooth 扫描、连接、GATT 读写及超时；URLSession 本地 HTTP、实时取景流、照片下载和变更 WebSocket。
- Photos 图库、缩略图、EXIF、文件描述符、导出副本与分享；前台位置记录。
- Dart 的 iOS 蓝牙权限分流、禁止扫描 Wi-Fi 的明确提示；iOS 原生图像 framework 加载路径。
- CMake iOS framework / XCFramework 构建脚本、CocoaPods 接入。

以上为实现清单，**不是已通过的功能清单**。当前机器没有完整 Xcode，Swift 的完整编译测试还被 Command Line Tools 的 SwiftBridging 模块冲突阻塞。只完成 `swiftc -frontend -parse -parse-stdlib` 语法解析、plist/工程语法检查及 Dart 权限分支自动化测试；纯 Swift 测试二进制执行以 exit 137 终止，未取得运行通过结果；这些不能验证 Apple SDK 类型或运行行为。

## 在具备 Xcode 的 Mac 上继续

1. 安装完整 Xcode，并在系统设置选择该开发目录，接受 Xcode 许可；安装 CocoaPods 与 CMake。
2. 执行 `flutter pub get`、`python3 scripts/generate_ios_bridges.py`。
3. 执行 `bash scripts/build_ios_imaging.sh` 生成 dist/ios/gremote_imaging.xcframework；该脚本当前未通过 iOS SDK 实际构建。
4. `cd ios && pod install`，打开 Runner.xcworkspace。选择团队并核对包名 `com.izhaoo.gremote`、Hotspot Configuration 能力、iOS 14 最低版本和权限文案。
5. 先 `flutter build ios --no-codesign` 修正 SDK 编译错误，再用 iPhone / GR III 验收下列项目。
6. 注册付费 Apple Developer 后创建 App Store Connect 应用，配置签名。完成 `flutter build ipa`、签名核验、上传、处理和测试组配置，再公布真实 TestFlight 邀请链接。

## 必须完成的设备验收

- 首次蓝牙授权、拒绝/设置修复、扫描、配对、bootstrap、掉线、重连及 ATT 超时。
- 系统 Wi-Fi 加入确认、本地网络授权、手动系统设置接入、前后台与重新连接。
- Live View、独立对焦/快门、参数写入/恢复、程序取消、变更 WebSocket。
- JPG 与 DNG 保存、RAW+JPG 成对行为、文件进度、断线、取消后续任务及失败重试。
- 完整/有限/拒绝相册权限；本地 JPEG 暗房处理、云端原图不可用提示、原图不覆盖、GPS 保留开关与元数据白名单。
- 竖屏/横屏/iPad 分享弹窗，前台位置记录与后台停止，内存峰值与长时间会话。

## 平台边界

iOS 不提供普通应用扫描附近 Wi-Fi 的能力；进入系统设置连接相机网络，或在用户确认后使用 NEHotspotConfiguration。当前本地网络只允许相机地址 192.168.0.1 的 /v1/ 接口；如真机需要其他地址，先取得证据再扩展白名单。

原生出图遵循既有 JPEG 契约，不把 HEIC/PNG/DNG 当作可编辑 JPEG。下载 DNG 与用 DNG 进入暗房是不同能力。iCloud 照片未下载到本机时提示先在系统照片中下载，不在后台自动拉取私人原图。

参考：[Apple Hotspot Configuration](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.hotspotconfiguration)、[Photos 资源创建](https://developer.apple.com/documentation/photos/phassetcreationrequest)、[Flutter 原生代码集成](https://docs.flutter.dev/platform-integration/legacy-ffi-plugin)。
