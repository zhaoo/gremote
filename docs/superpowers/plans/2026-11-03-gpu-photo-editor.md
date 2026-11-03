# GPU Photo Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将Android照片预览和原尺寸导出的全部像素处理迁移GPU，并改善自然调色和曲线手感，保留V1记录外观。
**Architecture:** Flutter保留文档/事务；常驻Android渲染线程拥有EGL上下文和图像纹理，参数代次合并。GPU预览与FBO分块导出使用相同shader图；JPEG/EXIF/文件发布保留成熟CPU路径，C++参考后端用于对照。
**Tech Stack:** Flutter 3.24.5/Riverpod, Android SurfaceProducer, C++17/NDK, OpenGL ES, libjpeg-turbo.
**Spec:** docs/superpowers/specs/2026-11-03-gpu-photo-editor-design.md; docs/superpowers/specs/2026-11-03-studio-ui-and-appearance-design.md

## Global Constraints
- develop；已有未提交改动保留；不改M10V固件/SD/相机协议；AF与快门分开。
- Android为本轮完整GPU验收平台；iOS保留现有路径，另列验收，不能声称已经GPU化。
- 全部现有14工具+预设/记录保持；基础/曲线/几何/LUT/光学/纹理/边框都属于GPU范围。
- 新编辑processVersion=2，旧JSON缺省1；同一版本preview/export共用shader、曲线表、seed、半径和色域合同。
- 16F或更高浮点中间结果，基础调色不提前RGBA8截断；JPEG编码前最终量化一次（V1按旧阶段量化合同复现）。
- 原尺寸含24MP及超纹理上限长图；空间效果邻域和全局坐标正确，不静默缩小、不以屏幕截图导出。
- 性能目标为真机profile/release：UI frame p95≤16.7ms、持续照片更新≥30fps、input-to-visible p95≤50ms、停手清晰帧≤150ms；未达就报告真实值和继续定位。
- 同尺寸GPU预览与导出编码前buffer一致；JPEG Q100平均误差目标≤1/255；真实样张需用户验收。

## Review Focus
- 打开旧编辑/应用旧预设不得重解释为V2，GPU迁移失败不能静默使用另一套调色导出。
- Surface销毁/后台/低内存/快速换图：旧纹理ID、旧generation、旧错误不能回写或泄漏资源。
- 24MP/长图/大半径光晕/旋转裁切跨tile：全局seed与halo无接缝，不重复量化/取整。
- 跨色域JPEG、饱和肤色/夜景、高光回拉：ICC规范化，亮度操作不造成明显色相偏转或假细节。
- 导出时切主题/权限丢失/取消：冻结文档，照片色不变，临时文件及pending媒体项清理，原图不覆盖。

### Task 1: 版本化编辑与调色数值合同
**Files:** Modify lib/darkroom/model/photo_edits.dart, export_recipe.dart, native/imaging/src/photo_edits.h/.cpp; Create native/imaging/src/tone_v2.h/.cpp; Test test/darkroom/photo_edits_test.dart, native/imaging/tests/tone_v2_test.cpp; update CMakeLists.txt.
**Interfaces:** PhotoEdits(processVersion=2)/fromJson missing→1; nativeParameters[0] version, same1062 length. ParsePhotoEdits accepts1/2 only. ToneV2::build(params) produces shared tone data; CPU RenderPhoto dispatches by version and remains reference.
- [ ] RED：旧JSON/预设版本1、new默认2、序列化/equality/undo包含版本；neutral像素恒等；sRGB灰128的+1EV在未进入肩部区域应约176而非255；灰阶单调与极值finite；曝光后高光回拉保留输入阶梯差异，alpha不变。
- [ ] Run `flutter test test/darkroom/photo_edits_test.dart`; build/ctest tone_v2; Expected FAIL.
- [ ] 实现线性浮点基础调色、亮度分区与高光肩部/色域压缩，定义固定数值与测试夹具；保留旧Basic逐阶段量化；不改已有V1语义。source/ICC与JPEG不可恢复边界写入合同。
- [ ] GREEN并跑native全套、Dart模型；保存肤色/灰阶/色块/真实参考图对照；提交feat(editor): version tone processing and define linear-light core。

### Task 2: GPU会话与纹理生命周期
**Files:** Create native/imaging/src/gpu/{gpu_context.h/.cpp,gpu_session.h/.cpp,gpu_api.h/.cpp}; Android CMake add EGL/GLES dependencies; Create android/.../imaging/GpuEditorHost.kt; bind MainActivity lifecycle; Test native/imaging/tests/gpu_session_device_test.cpp, android/.../GpuSessionLifecycleTest.kt.
**Interfaces:** SessionId/create(sourceFd,orientation,maxEdge), update(generation,RenderDescriptor), attachSurface(Surface,width,height), detachSurface(), close(); opaque IDs validated, single render thread. Capabilities includes version/renderer/maxTexture/floatTarget with actual FBO/shader checks.
- [ ] RED：create/update→offscreen neutral GPU buffer，close与重复close安全；FD归属/非法ID/无浮点FBO拒绝；旧context/generation结果被丢弃；surface重建恢复最新参数。
- [ ] Run Android native GPU harness on /data/local/tmp with synthetic data only, plus Kotlin tests; absent device record待测而不伪造GPU PASS。
- [ ] 实现常驻EGL上下文、SurfaceProducer接入及资源RAII，参数只发小数据；优先检测现有设备ES能力，选用能支持全部passes的版本，按实际SDK回调API处理Surface。
- [ ] GREEN on realGPU + lifecycle tests，记录设备GPU与能力；提交feat(imaging): add resident GPU rendering sessions。

### Task 3: GPU基础、LUT与曲线
**Files:** Create native/imaging/src/gpu/shaders/{geometry,tonal,lut,curves,present}.glsl + shader registry; Modify GPU session/cache keys; Test native/imaging/tests/gpu_color_device_test.cpp, gpu_pipeline_test.cpp.
**Interfaces:** RenderDescriptor contains processVersion/1062 params/LUT hash/strength/sourceGeneration/target geometry; upload cube as bounded texture with domain metadata, curves as small sampled texture; per-stage cache key includes all upstream identity.
- [ ] RED：GPU↔CPU V1/V2中性/曝光/对比/色块/任意曲线/非标准cube域；曲线更新不重新运行未变上游；改变上游必须失效下游；alpha/ICC与错误LUT无黑图。
- [ ] 运行device harness与模型测试，Expected FAIL before shaders。
- [ ] 实现正确颜色空间与量化合同的passes；曲线表与CPU同源，不另外拟合一套近似曲线；纹理驻留，无逐触摸大图Dart往返。
- [ ] GREEN，保存实际输出buffer/checksum与误差，提交feat(imaging): run tone LUT and curves on GPU。

### Task 4: 全部质感与几何GPU化
**Files:** Create GPU shaders/dispatch for vignette/grain/fade/monochrome/leak/halation/bloom/geometry; GPU multi-pass cache; Test native/imaging/tests/gpu_effects_device_test.cpp.
**Interfaces:** Same RenderDescriptor; spatial passes use full-image logical size/origin and normalized radii; V1 quantization separately preserved.
- [ ] RED：强度0恒等、固定seed重复稳定、全部参数生效、曲线改变后光晕正确重算、EXIF/旋转/翻转/校正/裁切输出尺寸和采样一致。
- [ ] Run device/host reference comparisons; Expected FAIL before passes。
- [ ] 实现有明确资源上限的空间passes，禁止每像素大半径二维暴力卷积；用户反向曲线允许但不额外过冲。
- [ ] GREEN全组合矩阵与极限，提交feat(imaging): complete GPU photo effect pipeline。

### Task 5: 原尺寸分块导出与画布
**Files:** Create native/imaging/src/gpu/{tile_plan.h/.cpp,gpu_export.h/.cpp}; Modify native/imaging/src/api.cpp/jpeg_io streaming interface and lib/darkroom/export/export_service.dart backend adapter only; Tests tile_plan_test.cpp, gpu_export_device_test.cpp and existing export tests.
**Interfaces:** ExportGpu(immutable descriptor, sourceFd, ExportJob, cancel) renders offscreen with same passes; TilePlan includes output rect, halo rect, source ROI and global origin; CPU JPEG writer consumes final rows, no old CPU pixel pipeline invoked on GPU export.
- [ ] RED：24MP/超maxTexture长图、有halo的全图↔tile对照；seed跨tile一致、边框/文字全局定位、JPEGQ100误差、取消/存储满/权限丢失不发布半成品、不覆盖原图。
- [ ] Run host tile tests + realGPU export harness and Flutter export tests; Expected FAIL.
- [ ] 实现全局坐标/足够halo/多尺度约束的tile，内存/纹理预算在分配前校验；复用FramePainter overlay，最终一次readback/编码，原子发布与EXIF/GPS保持。
- [ ] GREEN并记录内存峰值/耗时/接缝检查；提交feat(export): render full resolution through GPU tiles。

### Task 6: Dart GPU服务和编辑器事务接入
**Files:** Create lib/imaging/gpu/{gpu_editor.dart,gpu_editor_channel.dart,gpu_render_descriptor.dart}; Modify editor_controller.dart, frame_preview.dart and providers; Tests test/imaging/gpu_editor_test.dart, test/features/editor_workflow_test.dart.
**Interfaces:** GpuEditor.open(mediaId)->session; previewTextureId stream/frame generation metadata; update(recipe,generation), export(frozen job), dispose(); native channel returns no per-frameRGBA. Rendered geometry metadata binds to emitted frame.
- [ ] RED：快速输入只保留最新、取消/undo/redo/切图不会旧帧复活；导出冻结版本/参数，主题切换不触碰内容；未保存错误可重试，后台恢复无泄漏。
- [ ] Run target Flutter tests; Expected FAIL.
- [ ] 以平台Texture替换逐帧decodeImageFromPixels，保留原图对比/缩放/原图权限与草稿语义；CPU参考不冒充GPU后端；iOS明确现有路径。
- [ ] GREEN，运行整套Flutter，提交feat(editor): connect resident GPU preview and export。

### Task 7: 确认的Studio交互
**Files:** Modify editor_page.dart and focused widgets adjustment_panel/curve_panel/lut_picker/editor_tools; create studio navigation/preset/history widgets as needed; use AppPalette from appearance plan; Test editor_page_test.dart, curve_panel_test.dart and workflow tests.
**Interfaces:** existing controller edit transactions + GPU frame metadata; AppPalette/theme/haptics read-only to document; gestures update local pointer position before backend.
- [ ] RED：预设/调整/记录、选择与强度确认/取消、数值精调、曲线扩大热区/精确坐标/单通道还原、双指手势与单工具拖动隔离、全部14工具/导出入口保留、320px大字体与减少动态效果。
- [ ] Run widget/workflow tests; Expected FAIL for new interactions。
- [ ] 按gr-editor-studio-themes.html落地；正常状态不堆文案，错误不隐藏；直方图基于真实输入后台限频，曲线控件不做拖尾动画。
- [ ] GREEN，深浅/横竖实际截图核对；提交feat(editor): refine studio tools and precision interaction。

### Task 8: 集成审查、真机与交付
**Files:** docs/testing/2026-11-03-gpu-editor.md and task-owned dist/verification evidence; instrumentation only behind debug test entry, no production upload.
- [ ] 完整Flutter/native/Kotlin检查，fresh whole-branch review，重要问题逐项RED/GREEN后重跑全套，记录所有skip与限制。
- [ ] 构建可识别APK、核对SHA/版本、保留App数据覆盖安装；不触碰相机固件或SD。
- [ ] 真机profile/release采集首帧/热拖动/停手清晰帧、UI frame p95/input→visible、30fps目标、组合效果/发热持续性、24MP峰值、后台/旋转/取消与全部深浅状态。
- [ ] 用户查看真实照片自然调色及导出对照，确认GPU实际后台与V1旧记录外观；未通过不宣称全面迁移完成。
- [ ] 提交develop，仅在用户要求的范围交付；不自行push main或发布。
