# 2026-10-19 发布交付验证

## Android

- `bash scripts/build_android.sh --release`：通过，版本 1.0.1+4。
- Flutter 静态分析、当时完整 328 项测试、Android 单元测试及主机原生图像 CTest 通过。
- APK 为 com.izhaoo.gremote、Android 8.0+、arm64；apksigner 验证为项目专用证书，SHA-256 与 v1.0.1 发布记录一致。
- 正式密钥配置临时移开后运行真实 `flutter build apk --release --target-platform android-arm64`，按预期拒绝构建并提示禁止 debug 回退；配置由 finally 恢复。
- 无新增真机验收，不扩大 v1.0.0 已记录的小米 14 / GR III 2.10 证据范围。

## 官网与部署

- 浏览器实际检查：桌面首屏、360px 布局无横向溢出、图片加载、手机菜单打开/导航后关闭、使用说明展开。后续文案精简版在 472px 复查无溢出，菜单 Escape 关闭。
- JS 语法检查通过；本地 releases.json 渲染真实版本，静态 HTML 在数据加载失败时保留下载和发布说明入口。
- 8 项 Python 部署单测通过：完整发布及回滚、路径穿越、符号链接、缺失资源不切换、非法版本、版本不覆盖、并发锁、压缩炸弹展开预算。
- 压缩炸弹测试先实测解压 41,953,280 字节、超预算失败；实现有限展开后通过。
- 首次宝塔部署返回 SHA 5a82fc827a1dfde7980d16778ad490ccc8980b52 的 DEPLOY_OK；Nginx -t 通过，HTTPS version.json 曾公网证书校验通过。后续最新版本与 CI 结果另记录。
- 证书为手动 DNS-01，有效至 2027-01-17；尚无自动续期。

## iOS 代码准备

- Flutter 权限分流新增 2 项测试：首次因缺少接口而失败，实现后通过。完整 Flutter suite 为 330 项通过，静态分析无问题。
- Swift 通道生成脚本可运行，原 Android/Dart 生成文件未改变。
- `swiftc -frontend -parse -parse-stdlib` 通过；Info.plist、entitlements、pbxproj 校验通过；Podfile、podspec 与 shell 脚本语法检查通过。
- iOS SDK 不存在；`scripts/build_ios.sh` 明确拒绝继续。未运行 CocoaPods 安装、iOS 编译、链接、签名、真机或 TestFlight。
- Foundation Swift 测试被本机 CLT 的 SwiftBridging 重定义阻塞；纯 Swift 测试可执行文件运行被系统以 exit 137 终止，未取得通过结果。不能用语法解析替代运行结论。
- 审查指出的连接状态、JPEG 输入限制、云端照片跳过、WebSocket 握手事件已修正；涉及 Apple API 的修复仍须 SDK 编译和设备验证。
