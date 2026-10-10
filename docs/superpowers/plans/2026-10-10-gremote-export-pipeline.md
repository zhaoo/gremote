# gremote 出图管线 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** 本机 GR III JPEG → 原创/导入 LUT → 三种边框 → JPEG 副本导出（单张 + 批量）。

**Architecture:** C++17 图像核心（libjpeg-turbo 3.0.4）经 C ABI + Dart FFI 提供预览解码、LUT 与流式合成导出；Kotlin 负责 MediaStore、EXIF 白名单和发布；Dart 负责布局、叠层栅格化、SQLite 与 UI。设计见 `docs/superpowers/specs/2026-10-10-gremote-export-pipeline-design.md`。

**Tech Stack:** C++17、CMake ≥ 3.22、NDK 27.0.12077973、libjpeg-turbo 3.0.4、Dart FFI、sqflite 2.x / sqflite_common_ffi、file_selector、Pigeon 22.7、androidx.exifinterface 1.3.7。

---

所有路径相对 `gremote/`。每个任务遵循 RED → GREEN → 提交；提交只 `git add` 本任务路径，不触碰仓库内其他项目。

### Task 1: 工具链与 C++ 骨架

**Files:** `native/third_party/libjpeg-turbo-3.0.4/`、`native/third_party/VERSION.md`、`native/imaging/CMakeLists.txt`、`native/imaging/include/gremote_imaging.h`、`native/imaging/tests/test_main.h`、`scripts/build_native_host.sh`、`docs/testing/toolchain.md`

- [x] 安装 NDK 27.0.12077973、SDK CMake 3.22.1、主机 cmake；下载 libjpeg-turbo 3.0.4 源码包，记录 URL 与 SHA-256，只保留构建所需源码与许可证。
- [x] `CMakeLists.txt`：通过 `ExternalProject` 构建 libjpeg-turbo（`ENABLE_SHARED=OFF`、`WITH_TURBOJPEG=OFF`、`REQUIRE_SIMD=OFF`），构建 `gremote_imaging` 共享库与 `gremote_imaging_tests`，`enable_testing()` + `add_test`。
- [x] 测试框架为单头文件 `test_main.h`（`TEST(name)` 注册、`EXPECT_EQ/EXPECT_NEAR/EXPECT_TRUE`、失败计数、非零退出）。
- [x] `build_native_host.sh` 构建到 `native/imaging/build/host/` 并运行 `ctest --output-on-failure`。

### Task 2: `.cube` 解析与四面体插值

**Files:** `native/imaging/src/cube_lut.{h,cpp}`、`native/imaging/tests/cube_lut_test.cpp`

- [x] RED：解析 17/33/65 点恒等 LUT；`DOMAIN_MIN/MAX` 与注释、`TITLE` 跳过；`LUT_3D_SIZE 16` → `LUT_PARSE`；行数不符 → `LUT_PARSE`；非数字 / NaN → `LUT_PARSE`；超出 DOMAIN 的数值 → `LUT_RANGE`；恒等 LUT 对全部 256 灰阶与随机像素逐像素不变；“交换 R/B”的 LUT 在格点上精确；强度 0 等于原图、强度 0.5 为中点。
- [x] GREEN：`ParseCube(bytes) -> Result<CubeLut>`；`ApplyLut(rgb, stride, w, h, channels, lut, strength)` 按行分块最多 4 线程，四面体插值，输出 round + clamp。

### Task 3: 方向与缩放

**Files:** `native/imaging/src/orientation.{h,cpp}`、`native/imaging/src/resize.{h,cpp}`、对应测试

- [x] RED：2×3 图在 Orientation 1–8 下的像素位置与输出尺寸；面积缩放 4×4 → 2×2 求均值；目标尺寸 ≥ 源时原样拷贝；非整数比例下的均值误差 ≤ 1。
- [x] GREEN：`Orient(Image, int) -> Image`；`ResizeArea(Image, w, h) -> Image`。

### Task 4: JPEG 读写

**Files:** `native/imaging/src/jpeg_io.{h,cpp}`、测试

- [x] RED：编码合成渐变 64×48 再解码，尺寸一致、均值误差 < 3；`ChooseScale(6000×4000, 2048)` 返回 1/2；解码损坏字节 → `DECODE`；超过 100 MP 的头 → `TOO_LARGE`；`JpegRowWriter` 逐行写入，行数不足时返回 `ENCODE`。
- [x] GREEN：用 `jpeg_mem_src` + `setjmp` 错误处理；`scale_num/scale_denom` 缩放解码；`JpegRowWriter` 写文件（`jpeg_stdio_dest`），质量 1–100，4:4:4 采样。

### Task 5: 合成器与 C ABI

**Files:** `native/imaging/src/frame_compositor.{h,cpp}`、`native/imaging/src/api.cpp`、测试

- [x] RED：画布底色；照片像素出现在指定矩形；半透明叠层与底色/照片正确混合（预乘前 straight alpha）；叠层越界 → `INVALID_ARGUMENT`；照片矩形越界 → `INVALID_ARGUMENT`；`gremote_export_jpeg` 生成文件可解码且尺寸为画布尺寸；取消标志置 1 返回 `CANCELLED` 并删除输出文件；`gremote_decode_preview` 长边 ≤ max_edge 且方向正确；fd 在成功与失败路径都被关闭。
- [x] GREEN：`ComposeRow(y, out_row)`；`api.cpp` 实现头文件全部函数，读 fd 到内存（上限 200 MiB）。

### Task 6: Android 原生构建与 Dart FFI

**Files:** `android/app/build.gradle`、`lib/imaging/{imaging_bindings,imaging_engine,ffi_imaging_engine,imaging_exception}.dart`、`test/imaging/ffi_imaging_engine_test.dart`

- [x] Gradle：`ndkVersion "27.0.12077973"`，`externalNativeBuild { cmake { path "../../native/imaging/CMakeLists.txt"; version "3.22.1" } }`，只构建 `gremote_imaging` 目标。
- [x] RED：Dart 通过主机 dylib（`GREMOTE_IMAGING_LIB` 或默认 `native/imaging/build/host/libgremote_imaging.dylib`）验证：恒等 `.cube` 校验返回 33；坏 `.cube` 抛 `ImagingException(lutParse)`；`decodePreview` 从临时 JPEG 文件 fd 解码；`exportJpeg` 输出画布尺寸。
- [x] GREEN：`ImagingEngine` 接口 `validateLut`、`decodePreview`、`applyLut`、`exportJpeg`、`cancel`；FFI 实现在 `Isolate.run` 中调用，主机测试用 `dart:io` 打开文件取 fd（经 `libc.open`）。

### Task 7: 原创 LUT

**Files:** `lib/darkroom/lut/builtin_looks.dart`、`lib/darkroom/lut/cube_writer.dart`、`tool/generate_luts.dart`、`assets/luts/*.cube`、`test/darkroom/builtin_luts_test.dart`

- [x] RED：5 个 slug（`warm-positive`、`cool-negative`、`hard-mono`、`pale`、`night-teal-gold`）生成的文本与资产逐字节一致；每个 LUT 均为 33 点、值域 [0,1]；`hard-mono` 输出 R=G=B；恒等 look 输出恒等 LUT。
- [x] GREEN：纯 Dart 参数化 look（曝光、S 曲线、饱和度、分离色调、通道混合），`.cube` 写出 6 位小数、R 最快变化；运行生成脚本产出资产并在 pubspec 注册。

### Task 8: 出图领域模型

**Files:** `lib/darkroom/model/{export_recipe,edit_document,photo_meta}.dart`、`lib/darkroom/frame/{frame_style,frame_layout}.dart`、测试

- [x] RED：`ExportRecipe` JSON 往返与默认值；未知字段忽略；`PhotoMeta` 格式化（`1/250s`、`1.3s`、`f/2.8`、`ISO200`、`28mm`、`2026.10.10`）；`orientedSize`（5–8 交换宽高）；`FrameLayout`：三样式 original 画幅的边距按 §5，3:4/4:5/1:1 精确比例且照片尺寸不变、照片完整在画布内；`long1440` 照片长边 1440；隐藏全部字段后信息区仍保留但无文本元素。
- [x] GREEN：实现模型与布局；布局输出 `canvas`、`background`、`photoRect`、`overlays`（区域 + 元素：文本/矩形/片孔）。

### Task 9: 叠层绘制

**Files:** `lib/darkroom/frame/frame_painter.dart`、`lib/darkroom/frame/overlay_rasterizer.dart`、测试

- [x] RED：widget 测试中栅格化经典白边信息区，输出 RGBA 长度 = w×h×4，且存在非底色像素；隐藏全部字段时信息区像素全为底色；片孔区域包含底色以外的像素。
- [x] GREEN：`FramePainter.paintOverlay(canvas, overlay, scale)`；`OverlayRasterizer.rasterize(layout) -> List<RasterOverlay>`（`PictureRecorder` → `toImage` → `rawStraightRgba`）。

### Task 10: SQLite 与本机相册仓库

**Files:** `lib/storage/gremote_database.dart`、`lib/media/local/{local_media_item,local_media_repository,media_gateway}.dart`、`lib/darkroom/store/darkroom_store.dart`、测试

- [x] RED（`sqflite_common_ffi` 内存库）：首次扫描写入全部条目并读 EXIF；`date_modified` 不变不重读；消失条目被删除；GR 筛选只返回 `RICOH GR III`；扫描进度事件单调递增至总数；编辑文档 / 方案 / 导入 LUT 的增删改查；同哈希 LUT 去重。
- [x] GREEN：`MediaGateway` 抽象 + fake；仓库按 50 张一批读 EXIF。

### Task 11: Kotlin 媒体平台层

**Files:** `pigeons/media_api.dart`、生成文件、`android/.../media/{GRemoteMediaHostApi,ExifPolicy,MediaStorePublisher}.kt`、`MainActivity.kt`、Manifest、`android/.../test/.../media/ExifPolicyTest.kt`、`lib/media/local/native_media_gateway.dart`

- [x] RED（JVM）：`ExifPolicy` 去除序列号/所有者/MakerNote/UserComment；`keepGps=false` 去除所有 `GPS*`；`keepGps=true` 保留；`Orientation=1`；宽高覆盖；`Software=gremote`。
- [x] GREEN：Pigeon 生成；实现查询、EXIF 摘要（`ACCESS_MEDIA_LOCATION` 授权时用 `setRequireOriginal`）、缩略图、`openReadFd`、发布（`IS_PENDING`，失败删除）、分享（FileProvider 不需要，直接分享 MediaStore uri）；权限声明。

### Task 12: 导出服务与批量队列

**Files:** `lib/darkroom/export/{export_service,export_queue}.dart`、测试

- [x] RED（fake engine + fake gateway）：单张导出按“fd → 叠层 → C++ → 发布”调用，临时文件路径在缓存目录；C++ 失败时不调用发布并删除临时文件；队列中第 2 张失败后第 3 张仍执行，结果汇总 2 成功 1 失败；取消后剩余项标记 cancelled；重试只重跑失败项。
- [x] GREEN：实现服务与 Riverpod `ExportQueueController`。

### Task 13: 图库 Tab

**Files:** `lib/features/library/{library_page,library_controller}.dart`、`lib/features/library/widgets/*`、`lib/features/library/batch_export_page.dart`、测试

- [x] RED：未授权显示授权卡；部分授权显示提示条；扫描中显示进度；GR/全部切换改变数量；长按进入多选并显示“批量出图 (n)”；点击照片路由到 `/edit/:id`；相机分栏显示门禁提示。
- [x] GREEN：实现页面与控制器。

### Task 14: 暗房编辑页

**Files:** `lib/features/darkroom/editor/{editor_page,editor_controller}.dart`、`widgets/*`、`lib/app/router.dart`、测试

- [x] RED（fake engine）：打开后显示预览；选择 LUT 调用 `applyLut`；切换边框/画幅更新预览宽高比；隐藏字段后文本消失；未授予媒体位置权限时“保留 GPS”禁用；点击导出调用服务并提示成功；“存为方案”写入方案库；编辑文档自动保存。
- [x] GREEN：实现页面、控制器与根路由 `/edit/:mediaId`。

### Task 15: 暗房 Tab

**Files:** `lib/features/darkroom/darkroom_page.dart`、`lib/features/darkroom/lut_library.dart`、测试

- [x] RED：最近编辑列表；内置 5 个 LUT 列出；导入坏 `.cube` 显示具体原因；导入成功出现在列表并可删除；方案重命名与删除。
- [x] GREEN：实现，导入用 `file_selector` 的 `openFile`。

### Task 16: 构建、真机清单与评审

**Files:** `scripts/build_android.sh`、`pubspec.yaml`（0.2.0+2）、`docs/testing/creative-gate-export.md`

- [x] 构建脚本先跑 `build_native_host.sh` 再跑 analyze/test，并构建 arm64 APK。
- [x] 全部测试、analyze、CTest、Kotlin 单测通过；APK 与 Git 敏感文件扫描。
- [x] 写真机清单；派发一次 CodeReview；按 1.md 询问发布模式。
