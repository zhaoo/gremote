# 拍摄参数回读与公开固件胶卷设置修复

日期：2026-11-05。App 基线为 GitHub 最新 `044ce47`，分支 `develop`，修改前工作区干净。本轮仅修改 GRemote；未改写用户固件、SD 文件或 M10V 源码，未推送或发布。

## 定位与修复

1. 参数写入：`ParamWriter` 收到 PUT 响应中的同名参数后直接返回确认，跳过 `/v1/props`；这个回显没有进入共享 `CameraState`，界面依赖的 WebSocket 若无参数通知，就继续显示旧值。现每次成功写入后都回读完整 props，再根据实际值返回确认或修正；回读失败不把回显当作成功。快门、光圈、ISO、曝光补偿、白平衡、对焦模式、画幅、驱动模式和机内效果共用此路径。请求字段、原始 wire 值及 AF/快门分离保持不变。
2. 胶卷设置：用户提供的公开固件 catalog/renderer 组合没有列入 App 固定可信版本，触发只读保护；扩展设置不依赖这组胶卷身份，所以能够读取。现在加入完整、独立校验的公开目录和精确身份配对，继续沿既有合同校验、签名、冲突、未知结果及读回确认流程操作十槽。旧配套版本继续支持，没有放宽未知版本门禁。

以上是源码和离线回归确认的缺陷；尚未采集截图所示运行会话的原始响应，不能断言覆盖全部真机问题。

## 固件证据

来源：用户提供的 `m10v-gr3-gremote` 目录；目录内固件与 FILMS.M10 已被重命名，按实际文件内容计算 SHA-256，均与 manifest 一致。

| 对象 | SHA-256 |
| --- | --- |
| GR III 2.10 固件 | `14310c9c4daaa3404202b3677462f59f8437389bb203bf28d5b360d9d7b93c1e` |
| SERVICE.BIN | `657faadef88a8d01e5a955d5ae4103495162a094db45b19f2eab972f3bb00c71` |
| FILMS.M10 | `970f73d5bf813f9b03c6eacf110b3c4a60ea40676287e655257c139aae748bb6` |
| service receipt 的 registry/contract | `65fd172e7d9d1db82866659ddbb058cc557c0bfb046fd1638d328b21dff2486b` |

Build ID：`eb01f53cba9b1e69d6505cb90d22277e5a1dcd331737d942c5906e4b68f2a34d`。

公开目录 hash：`dec78e808816dd21e7e6225a7a3c539699bd0572bb018b719e7fcc5c328be696`；renderer hash：`db7fdff7b13e23447f4a58c561b92813319acf249b8922f75b4ffdad3bb74f30`。

M10V owning source 为 `35d4235c5805f42405b6aeb0cc45654ba3eefd0f`。从该 checkout 执行 `node scripts/read_gr3_gremote_camera_metadata.mjs --catalog`，重新生成的完整目录计算 canonical hash 后与包身份一致；`contracts/companion-v1.json` 的文件 hash 与 service receipt 一致，JSON 内容与 App 现有 camera contract 一致。可移植来源记录见 `assets/films/camera-profiles/public-gr3-20261105-provenance.json`。

原始目录共 57 条，新增 Marlboro 327，但该包服务的 generated contract 仍只接受到 326。App 保留原始目录用于完整 hash 校验，只展示可写的 56 条，不发送 327。若机身已使用合同无法表达的胶卷/参数，仍保留只读保护，不能把 App 配套修复当作固件扩展。

## 验证

- RED：新增回归在旧代码中出现 14 项预期失败，包括回显不更新共享状态/界面、依赖值和选项不刷新、回读失败仍错误确认、公开固件未受信任。
- GREEN：针对参数、界面和公开固件配套的目标测试通过。之后新增回显与实际回读冲突用例，确认实际值优先。
- 最终完整 Flutter：702 通过、3 个条件跳过；其中真实 C HTTP 服务集成已针对原当前版本和本次公开固件身份各执行一次。跳过项为官网在线同步、可选视觉截图、历史五槽 C 服务集成；未把跳过项记为通过。
- 真实 C 回环验证覆盖签名认证、十槽状态、326 号装卷、单次存档、独立启用槽位、重复胶卷复用已有槽及保留字段。它运行于主机，不能替代 Linux/RTOS 真机兼容性。
- `flutter analyze`：无问题。Android JVM：54 项、0 失败，Gradle 复用未变化的测试结果（UP-TO-DATE）。Android arm64 Debug 构建成功。
- 独立只读审查：Critical 0、Important 0；Minor 1（缺少可移植来源记录）已补齐。

本轮 ADB 设备列表为空，没有安装 App、操作相机、拍照、写卡或刷机。没有真机耗时、持久化或成像兼容性结论。

## 候选安装包

构建参数：`flutter build apk --release --build-name 1.2.6-dev --build-number 25 --target-platform android-arm64`。源 pubspec 发布版本未修改，候选的版本标识由构建参数提供。

产物：`dist/gremote-camera-state-films-1.2.6-dev+25-arm64-release.apk`。包名 `com.izhaoo.gremote`、versionName `1.2.6-dev`、versionCode `25`、minSdk 26、targetSdk 34。Release 构建成功；apksigner 校验通过，签名证书 SHA-256 与已有 v1.2.5 Release 一致：`442d55ef48b0a29d917fe267e79c6d2941aba05157ac9b0a3175217a3ed60a29`。

APK SHA-256：`6e18f49f143f7c631229edc40960cf58d0ba58add40173ebdc9d23e29f1a8eda`，大小 29,079,723 字节。

APK 中公开目录和来源记录逐字节匹配源码，包含 arm64 应用库。构建出现已有的字体树摇裁剪提示和 CupertinoIcons 字体缺失提示；未将构建成功等同于手机 UI 验收。验证日志保留于本地忽略目录 `dist/verification/camera-state-films-20261105/`。

## 真机复测

1. 用候选 App 连接这份固件，分别调整光圈、快门、ISO、补偿；核对参数栏和标尺选中态与机身一致，检查机身限制可选值时控件同步改变。
2. 核对十槽、启用槽位和胶卷名称；选已有胶卷只改一项参数，确认保存并读回，之后独立启用；其余槽与保留参数应保持。
3. 重新读取扩展设置，检查原功能仍可使用；断连和未知结果不能自动重复提交装卷。
4. 正常关机重启后重新连接，核对保存结果。性能、RAW/JPEG、连拍与出图仍需各自真机证据。
