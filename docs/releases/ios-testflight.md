# iOS TestFlight 准备

本次交接使用 **GRemote 1.2.2+21**。GitHub 预发布包含未签名的 iPhone Release 构建、依赖锁文件和 SHA-256 校验文件。TestFlight 需由 Apple Developer 团队签名上传。

## 已加入

- iOS 14+ Runner 工程、应用图标、中文权限说明及 Hotspot Configuration entitlement。
- 由 Pigeon 22.7.4 生成的 Swift 通道；`python3 scripts/generate_ios_bridges.py` 仅刷新 Swift，不覆盖原 Android/Dart 输出。
- CoreBluetooth 扫描、连接、GATT 读写及超时；URLSession 本地 HTTP、实时取景流、照片下载和变更 WebSocket。
- Photos 图库、缩略图、EXIF、文件描述符、导出副本与分享；前台位置记录。
- Dart 的 iOS 蓝牙权限分流、禁止扫描 Wi-Fi 的明确提示；iOS 原生图像 framework 加载路径。
- CMake iOS framework / XCFramework 构建脚本、CocoaPods 接入。
- 识别已加入的 GR III 相机热点，与 Android 共用 M10V 自动配对、无线装卷、扩展设置及写入回读流程。GR III 2.10 须启用 M10V 的 GRemote 连接并安装该构建配套的 SD 服务。

GitHub Actions 已编译设备和模拟器的图像框架，并将设备框架嵌入未签名 App。发布时需要 Apple Developer 团队和签名。iOS 的 M10V 扩展设置及自动连接尚未接入，Android 版的真机验收不覆盖 iOS。

## 在具备 Xcode 的 Mac 上继续

1. 检出 GitHub 预发布标签 `v1.2.2-ios-unsigned`。安装 Xcode 26.3、Flutter 3.24.5、CocoaPods 与 CMake，选择完整 Xcode 开发目录并接受许可。
2. 将发布附件 `ios-pubspec.lock` 复制为项目根目录的 `pubspec.lock`，执行 `flutter pub get --enforce-lockfile`。Swift 通道已随源码提交。
3. 执行 `bash scripts/build_ios_imaging.sh` 生成 dist/ios/gremote_imaging.xcframework；该脚本已在 GitHub Actions 验证。
4. `cd ios && pod install`，打开 Runner.xcworkspace。由团队账号选择签名团队并核对包名 `com.izhaoo.gremote`、Hotspot Configuration 能力、iOS 14 最低版本和权限文案。
5. 用签名的开发构建在 iPhone / GR III 上验收下列项目。
6. 在获授权的 Apple Developer 团队中注册 Bundle ID、创建 App Store Connect 应用并配置签名。完成 `flutter build ipa`、签名核验、上传、处理和测试组配置，再公布真实 TestFlight 邀请链接。

## 必须完成的设备验收

- 首次蓝牙授权、拒绝/设置修复、扫描、配对、bootstrap、掉线、重连及 ATT 超时。
- 在系统设置加入相机 Wi-Fi，回到 GRemote 并允许本地网络访问。验证已加入热点的自动识别、前后台恢复及切回日常 Wi-Fi 后的断开状态。
- 在已启用 GRemote 连接的 M10V GR III 2.10 上，验证冷启动后无需导入配对文件、无需打开机身焦距菜单，App 即可读取机内胶卷和扩展设置。向空槽装入胶卷并回读，修改一项扩展设置并核对机身显示，再恢复测试前的设置。
- Live View、独立对焦/快门、参数写入/恢复、程序取消、变更 WebSocket。
- JPG 与 DNG 保存、RAW+JPG 成对行为、文件进度、断线、取消后续任务及失败重试。
- 完整/有限/拒绝相册权限；本地 JPEG 暗房处理、云端原图不可用提示、原图不覆盖、GPS 保留开关与元数据白名单。
- 竖屏/横屏/iPad 分享弹窗，前台位置记录与后台停止，内存峰值与长时间会话。

## 平台边界

iOS 不提供普通应用扫描附近 Wi-Fi 的能力；进入系统设置连接相机网络，或在用户确认后使用 NEHotspotConfiguration。相机普通接口使用 192.168.0.1，M10V 扩展接口通过当前相机 Wi-Fi 访问 192.168.0.1:18743。临时加入的 Wi-Fi 若由 iOS 断开，需先重新加入热点。

原生出图遵循既有 JPEG 契约，不把 HEIC/PNG/DNG 当作可编辑 JPEG。下载 DNG 与用 DNG 进入暗房是不同能力。iCloud 照片未下载到本机时提示先在系统照片中下载，不在后台自动拉取私人原图。

参考：[Apple Hotspot Configuration](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.hotspotconfiguration)、[Photos 资源创建](https://developer.apple.com/documentation/photos/phassetcreationrequest)、[Flutter 原生代码集成](https://docs.flutter.dev/platform-integration/legacy-ffi-plugin)。
