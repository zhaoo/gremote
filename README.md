<div align="center">

# GRemote

### 为街头摄影而生的 RICOH GR III Android 伴侣

连接相机 · 专注拍摄 · 整理照片 · 打磨色彩

![GRemote 封面](assets/images/street_moment.jpg)

**Flutter** · **Android** · **RICOH GR III** · **本地优先**

</div>

---

GRemote 想把拍摄现场和照片后期放在一处：通过蓝牙与相机 Wi-Fi 建立连接，在手机上查看取景画面和拍摄状态，再从本地图库进入暗房，制作属于自己的照片风格。

> **项目状态：开发中。** 当前仓库包含相机连接、遥控拍摄和本地创作流程的实现与自动化测试。真实 GR III 与 Android 设备的完整兼容性、长时间稳定性及出图质量仍在验收中。请勿将它用于不可重拍的重要拍摄。

## 可以做什么

| 场景 | 当前实现 |
| --- | --- |
| **连接相机** | BLE 扫描与连接、相机 Wi-Fi 接入、手动 Wi-Fi 入口、分阶段连接诊断 |
| **遥控拍摄** | Live View、快门与参数控制界面、包围与渐变拍摄程序、拍摄配方 |
| **整理图库** | 本地照片浏览、GR III 照片筛选、选择与批量处理入口 |
| **暗房创作** | `.cube` LUT 导入、内置色彩风格、画框与文字叠加、JPEG 副本导出 |

界面以中文为主，所有编辑和导出流程以本地文件为核心。原始照片不应被覆盖；导出结果写入新文件。有关设备与隐私验证的具体状态，请看下方的「验证状态」。

## 下载

[下载 GRemote 1.0.0 Android arm64 APK](https://github.com/zhaoo/gremote/releases/download/v1.0.0/gremote-1.0.0-android-arm64.apk) · [发布说明与校验文件](https://github.com/zhaoo/gremote/releases/tag/v1.0.0)

最低 Android 8.0。功能和真机验证范围见 [1.0.0 发布记录](docs/releases/v1.0.0.md)。

## 快速开始

### 环境

- Flutter SDK，包含 Dart `>=3.5.4 <4.0.0`
- Android SDK 与 JDK 17
- Android 真机；相机连接功能需要 RICOH GR III

```bash
flutter pub get
flutter run
```

如果要执行完整的 Android 构建检查并生成 arm64 APK：

```bash
./scripts/build_android.sh
```

脚本会运行原生模块构建、Flutter 静态分析与测试、Android 单元测试，然后将 APK 放入 `dist/`。构建产物不会提交到 Git。

首次连接相机时，请在 GR III 上开启蓝牙并完成配对；若走手动 Wi-Fi 连接，请在相机中开启无线 LAN。连接排查步骤见 [GR III 与 Android 调试指南](docs/testing/gr3-xiaomi14-connection.md)。

## 项目结构

```text
lib/
  app/          导航、主题与启动流程
  camera/       连接、协议、实时取景与拍摄控制
  features/     首页、拍摄、图库、暗房与诊断界面
  darkroom/     LUT、画框、导出与编辑数据
  media/        本地媒体访问
android/        BLE、Wi-Fi 与媒体平台实现
native/imaging/ JPEG 与图像处理原生模块
test/           Flutter 自动化测试
docs/           协议资料、设计与验收记录
```

主要技术栈为 Flutter、Riverpod、GoRouter、Android Kotlin、SQLite 和 C++ 图像处理模块。相机通信涉及 BLE GATT 与相机本地 HTTP 接口。

## 验证状态

- 仓库中有 Flutter、Android 和原生图像模块的测试，以及 Android 构建脚本。
- [GR III 硬件验收清单](docs/testing/gr3-hardware-gate-1.md) 中记录了早期自动化检查；其 BLE、Wi-Fi、Live View 和遥控真机项目仍标为 `not-run`。
- [创作与导出验收清单](docs/testing/creative-gate-export.md) 仍待真实设备和照片验证。

文档中的设计目标不代表已完成或已通过真机验收的功能。运行前请检查当前代码和设备环境。

## 隐私与边界

项目不需要云账号。不要在 Issue、日志或截图中公开相机 Wi-Fi 密码、完整 BLE 地址、序列号、精确位置或私人照片。固件文件、构建输出、签名密钥和本地配置均不应提交到仓库。

本项目为独立开发，与 RICOH IMAGING 无官方关联。RICOH 与 GR III 是各自权利人的商标。
