# GPU 修图实施记录 — 2026-11-03

本文件区分已验证的 CPU 数值参考、待接入的 GPU 后端与真实手机结果。相机固件、SD 和协议未修改。

## 外观 APK 检查点

外观 APK 为 `gremote-appearance-1.2.0-dev+15-arm64-debug.apk`，包名 com.izhaoo.gremote，aapt 实读 versionCode=15、versionName=1.2.0-dev。SHA256 `63c6e640d0321bc6a3137228fbae129c2685a5e6e21bf4b89c0b06cd869061b7`。

该 APK 对应外观修复检查点 3db80db，不包含以下调色 V2/GPU 工作，不能用它声称 GPU 修图已交付。安装待 ADB 连接。

## Task 1：版本与 CPU 调色参考

- 新编辑默认 processVersion=2。旧 JSON 缺失版本按 1 读取；预设和参数复制、序列化、等价比较保留版本；未知将来版本拒绝处理，不猜测降级。
- 1062-float ABI 保持，首项区分 1/2。C++ 的空参数旧入口继续为 V1；V1 原基础处理代码和逐阶段量化保留。
- ToneV2 独立实现：规范化 SDR sRGB 解码到线性值，白平衡增益与 2^EV；以线性 0.18 为对比枢轴；明暗区域采用具有正导数的连续 log-light 映射，白场和黑场作用于相应区域；过量高光使用有界有理肩部；围绕亮度压缩色度，避免独立通道截断。最终转换至 sRGB。
- 参考输入必须已规范化为 sRGB。ICC 识别/转换属于后续解码边界，尚未凭此核心宣称实现。无法从 JPEG 已全白区域恢复不存在的细节。
- 此阶段只替换 CPU 参考的 Basic；旧 CPU LUT/光学/纹理仍在各阶段使用 byte buffer。它不代表最终浮点 GPU 图，也不满足“全面 GPU”验收。GPU 中间缓冲、预览/导出、分块及性能仍待实施。

### 固定数值样本（真实 host 动态库调用）

| 输入灰阶 | 64 | 128 | 192 | 224 | 255 |
| --- | ---: | ---: | ---: | ---: | ---: |
| V1 +1EV | 128 | 255 | 255 | 255 | 255 |
| V2 +1EV | 90 | 176 | 244 | 252 | 255 |
| V2 +1EV / 高光 -1 | 90 | 166 | 218 | 241 | 255 |

中性灰阶恒等，alpha 不变。另覆盖所有基础控件极值的灰阶单调、肤色色块/高饱和 RGB 的浮点 finite/范围及去饱和中性。

参考 JSON：dist/verification/editor-v2-research/tone-v2-reference.json（本地测试证据，不随源码发布）。这是合成色块和数值验证，不是用户真实 GR 照片的主观画质验收。

### 检查

- 初始 RED：Dart 无版本字段；native V2 解析失败、+1EV 得到 255 而非 176。
- GREEN：64 native tests（ctest 汇总 1 executable），Dart 模型与 FFI 专项通过；完整 Flutter 603 passed / 3 conditional skips。
- 待手机提供实际 GPU 信息、真实 GR JPEG、原尺寸导出与画质 A/B。当前 ADB 无设备，尚无 GPU PASS、帧率/延迟/内存或真机画质结论。

## GPU 硬件预检准备

`bash scripts/build_gpu_probe_android.sh` 已交叉编译 arm64 Android ELF。它只创建 EGL pbuffer、编译 ES3 shader，并实际向 RGBA16F 写入红色 2.0，再经采样/缩放读回 RGBA8；红色应约 128，若中间提前截断则约 64。探针不会读照片或调用相机接口。

输出包含 ES 版本、GPU renderer、最大纹理/目标尺寸和半浮点绘制回读结果。编译成功不能代替执行成功；本轮 ADB 无设备，尚未运行。即便 adb-native-probe 通过，也要在后续 App 会话内再核对驱动、SurfaceProducer 和资源生命周期，不能把独立进程能力等同于 App 已完成 GPU 接入。

同时已成功交叉编译包含 ToneV2 的 Android arm64 `gremote_imaging` 原生库。这不更新前述外观 APK，不代表 GPU session、shader 图、分块导出或新版 Studio 交互已完成。
