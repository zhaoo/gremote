# 多机型连接 · App 候选验证

## 范围与基线

开发日期：2026-11-20，分支 `develop`，基线 HEAD `8689683`。核对时 GitHub 最新 App 为 v1.2.13+38；官网版本提交为 `f4d725fea0fc38504e58d01e756b4f1db7290016`。

保留开始时已有的胶卷、Live、传输及 iOS 未提交改动。本轮没有提交、推送或发布线上版本；构建使用当前工作区，因此候选也包含原有未提交功能。

用户确认视觉稿 v2，并要求不增加界面解释文本。后续明确：先完成 App，IIIx 配套固件下一步做。

## App 行为

- 自动读取 BLE 型号与 Wi-Fi `/v1/props`；两端机型不一致时拒绝进入 ready，避免连接到另一台热点。未知机型在蓝牙电源写入前拒绝。
- Android / iOS 扫描同时接纳原厂信息服务和配对广播服务 `0f291746-0c80-4726-87a7-3c501fd3b4b6`，不依赖相机名称包含 GR / RICOH；改名设备仍在握手后校验真实型号。新增原生广告匹配 JVM 回归先缺失失败、实现后通过（1 项），覆盖自定义名称、空名称与无关服务拒绝。
- GR III / IIIx / IV / IV Monochrome 及对应 HDF 型号允许连接。协议原始型号、参数和值不翻译或覆盖。
- 切换面板先扫描附近真实设备，保留当前连接；选定后断开并连接所选设备，不二次扫描。关闭面板不会断开相机；旧扫描完成不能更新已销毁组件。
- GR IV / IV Monochrome 不探测 M10V，不使用已有 GR III 配对凭据。胶卷浏览保留，扩展、机内胶卷、机内配方与装入相机禁用，不重复展示能力说明。
- IIIx App 接入支持配对、能力协商、固件身份校验、便携胶卷与机型匹配。受信任目录、渲染器、槽数和回读保护保留。现有 GR III 服务不能冒充 IIIx 服务。
- 相同固件版本号在不同机型上独立保存 HTTP 写入编码；保留 GR III 原有缓存键。
- 本地 GR 照片筛选包含新增机型，避免传入后的 IIIx / IV 照片被旧筛选漏掉。
- 对焦继续只走独立 lens/focus，未添加拍照回退。

## 官方固件静态证据

官方来源：[GR IIIx](https://www.ricoh-imaging.co.jp/english/support/digital/gr3x_s.html)、[GR IV](https://www.ricoh-imaging.co.jp/english/support/digital/gr4_s.html)、[GR IV Monochrome](https://www.ricoh-imaging.co.jp/english/support/digital/gr-4-mono_s.html)。归档下载位于官方 `/resources/japan/support/download/digital/FIRMWARE/`，使用 `gr3x_v160.zip`、`gr3x_v171.zip`、`gr4_v121.zip`、`gr4_mono_v111.zip`。

| 固件 | BIN SHA-256 |
| --- | --- |
| IIIx 1.60 | `708e79f3b7b96a7e1581b4acf4c412233050a1832718ef7f06c8397db1b431c7` |
| IIIx 1.71 | `7d7e9d8173bcc8bcc8bab1df185ae66671ff2a33c870067a6f4c029c628bedc9` |
| IV 1.21 / IV Monochrome 1.11 | `bf4d6c35f6da1c16ed5f2943af570eab8fef326f7501a2b3ce5413fa55ec5c99` |

IV 与 IV Monochrome 官方归档不同，但 BIN 相同，不能仅用固件哈希区分机型；以连接时的真实设备型号为准。

已解码更新容器并只读提取 INITFS：IIIx 为 ROMFS 内 gzip CPIO，IV 为 SquashFS/LZ4。`bled` 内确认型号、固件、SSID 与快门特征 UUID；`webapid` 确认 ping、props、liveview、changes、独立对焦、快门和照片路由。详细哈希、字符串与 UUID 字节偏移见同目录 `2026-11-20-multicamera-protocol-evidence.json`。

官方固件、提取二进制仅存本机 `/tmp/gremote-multimodel-firmware`，不进入 Git。以上是静态协议依据，不能证明实际握手、性能、传输或机身操作已通过。

## 自动化与视觉检查

- Flutter 3.50.0 / Dart 3.14.0；全量测试当前记录：771 通过、9 跳过。跳过包含需要显式 fixture / 原生环境的用例及默认关闭的截图测试。
- Android `:app:testDebugUnitTest -Ptarget-platform=android-arm64` 完整执行成功：22 个测试类、69 项通过，0 失败、0 错误、0 跳过；包含新增蓝牙广播匹配回归。结果核对自 JUnit XML，构建日志 `/tmp/gremote-android-unit-online.log`。
- 静态分析 `flutter analyze --no-fatal-infos`：无 error / warning；189 条 info，主要为该 SDK 的既有 Material 导入弃用提示。
- 独立代码审查发现快门状态更新会重建 M10V API 工厂；回归测试已先失败，再修复为稳定机型/会话选择器后通过。
- 窄屏 320、常规 390 及大字体验证；全量测试发现下方延迟构建的控件不能通过 ensureVisible 定位，改为真实滚动查找，保留可达性断言。
- 真实 Flutter 视觉截图：`docs/design/2026-11-20-flutter-multicamera-{home,switch,stock}.png`。使用演示连接和字体，仅证明主机渲染。
- Swift 修改文件通过 `xcrun swiftc -frontend -parse`。完整 iOS 构建受到本机 Xcode 插件依赖损坏阻塞：`IDESimulatorFoundation` 找不到 `DVTDownloads` 符号，尚未得到 iOS 构建通过结论。
- 额外启用 `M10V_HOST_ROOT` 的旧 C loopback 用例未通过：`real C HTTP: authenticated state, resumed upload, verified data then one journal install`。当前 M10V fixture 返回十槽 schema 2，而该旧集成测试按历史五槽 contract 读取，触发 `相机状态格式无效`；不放宽正式解析器或可信目录校验来迁就 fixture。此项默认跳过，不包含在 771 项通过结论中。

## 真机待验收

逐机型验证 BLE 配对、系统 Wi-Fi 接入、自动识别、独立对焦、取景、快门按下/松开、JPG/DNG 下载、断线重连和多相机切换。IIIx M10V 联动等待下一步配套固件/SD 服务，不能用本轮 App 模拟测试替代。

本轮不刷机、不写 SD 卡、不启用服务、不发布线上版本。

## 候选构建身份

源码版本：`1.2.14+45`；Android 测试候选使用 `--build-name 1.2.14-rc.1 --build-number 45`。沿用项目正式签名配置，尚未发布为正式版。

已成功构建并校验：`dist/iterations/1.2.14-rc.1/gremote-1.2.14-rc.1-android-arm64.apk`，30,021,810 字节，SHA-256 `d4e42f89137a39a6ce31638fd2972efcd985466193e88f1a79087edf2c44ca28`。

包名 `com.izhaoo.gremote`，versionName `1.2.14-rc.1`，versionCode `45`，minSdk `26`，targetSdk `34`，compileSdk `36`，仅含 `arm64-v8a`；包含 `libapp.so` 与 `libgremote_imaging.so`。AOT 中确认包含新机型名称与切换相机入口。

`apksigner verify --print-certs` 通过，证书 SHA-256 `442d55ef48b0a29d917fe267e79c6d2941aba05157ac9b0a3175217a3ed60a29`，与本地 v1.2.13 正式包一致。APK 构建通过不代表已经安装验收或新机型真机兼容通过。

构建 SDK：`/Users/zhaoo/development/flutter-gremote-3.50.0/flutter`；JDK 17：`/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home`。Android 对齐 AGP 9.1.1 / Gradle 9.3.1 / Kotlin 2.4.10，保留官方迁移期 `android.builtInKotlin=false` 与 `android.newDsl=false` 配置；依据 [Flutter 迁移说明](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers) 与 [AGP / Gradle 对照](https://developer.android.com/build/releases/about-agp)。首次构建需下载 Gradle 及新增插件依赖。

该 SDK 的 integration_test 插件要求 compileSdk 36，因此编译 SDK 同步为 36；targetSdk 仍为 34，minSdk 仍为 26。首次构建发生 Google Maven 读取超时，Flutter 自动重试，须以最终构建终态为准。

构建过程还发现测试与 release 构建不能并行运行：Flutter 3.50 的 release 模式排除 dev 插件，但测试会把同一 `GeneratedPluginRegistrant.java` 改回包含 integration_test，导致发行 Java 编译找不到该类。该生成文件不手改；完成测试后单独运行 release 构建重新生成正确注册器。后续验证保持串行。

该 SDK 还会在构建时覆盖 DefaultConfig 的原生 ABI 过滤器，导致意外构建原项目未支持的 armeabi-v7a。使用 SDK 提供的 `disable-abi-filtering=true` 禁用其自动覆盖，保留项目已有 `ndk.abiFilters = arm64-v8a`；不为本轮新增 32 位支持或修改图像引擎去迁就意外 ABI。产物须核对只包含 arm64。
