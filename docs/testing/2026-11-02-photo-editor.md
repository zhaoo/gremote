# 第一批照片编辑器验证记录

日期：2026-11-02。工作分支 develop，起点 c6aca49。用户已批准交互视觉稿后实施；未修改固件、相机协议或 SD 服务，未 push 或发布。

## 交付功能

- 工具网格与单工具编辑；基础、白平衡/色彩、真实裁切/校正/旋转/翻转、LUT、RGB/独立通道曲线。
- 暗角、颗粒、漏光、光晕、柔光、褪色、黑白；白/黑边框、留白、拍立得及既有胶片边框；边框宽度与 EXIF 日期印记。
- 当前照片真实 LUT 缩略图、自定义 cube 导入、强度；方案保存和应用。锁定裁切比例的方案按目标照片尺寸重新适配。
- 工具草稿完成/取消、一次手势一次撤销、重做、单项/整体还原、自动保存及失败重试。未保存成功时保留页面；退出保存期间阻止新操作。
- 原图按住对比及取消恢复、双指查看细节、直接横向拖动当前选中参数。轻量面板动效遵守系统减少动态效果设置，小屏面板滚动，横屏分栏。
- 新编辑默认无边框；旧编辑保持原设置。保留信息字段、画布留白比例、导出尺寸/质量/GPS、保存副本与分享。

## 一致性与证据

预览与 JPEG 导出均调用同一 C++ RenderPhoto，1062 float v1 参数覆盖几何、基础、LUT、曲线、光学与纹理效果。边框/文字复用 FramePainter。颗粒和漏光保存固定种子，半径按画面长边缩放。

同尺寸原生组合夹具包含 EXIF6、旋转、翻转、校正、裁切和所有处理阶段：质量100 JPEG 重新解码后，与 RGBA 预览相比平均 RGB 通道误差 **0.4747/255**、最大 **4/255**。不同尺寸光晕夹具64/192对齐比较平均误差约1.1419。JPEG 编码有损，缩略图与原尺寸也存在采样差异；这些结果不代表任意图片逐像素一致或真机显示色彩已验收。

原生与 Dart 对裁切统一使用 float32 乘法取整，覆盖 .525/.265 等半像素边界，避免导出尺寸与 native 几何差一像素。

测试与日志位于 `dist/verification/photo-editor/`：

| 检查 | 结果 | 记录 |
|---|---|---|
| 完整 Flutter 测试 | 528 通过、3 条件跳过 | full-test.log |
| Native host / CTest | 57 个测试用例通过 | native-tests.log、native-final.log |
| Dart/Flutter 静态检查 | 无问题 | analyze.log |
| Android arm64 debug 构建 | 成功 | android-build.log |
| 实际 Flutter 编辑器截图 | 工具、基础、颗粒、曲线、边框、横屏；本地夹具走真实 native | capture.log、editor-*.png |

条件跳过为依赖 `M10V_CURRENT_HOST_ROOT`、`M10V_HOST_ROOT` 的两个 host 测试，以及需 `FILM_VISUALS` 启用的旧视觉测试。未用跳过测试声称相机同步完成。

截图使用宿主测试字体，部分西文会显示 Ahem 方块，不能代替 Android 字体和动画验收。初始原生、模型、FFI、UI 和审查修复的 RED/GREEN 记录均保留在同目录。

## 独立审查与修复

对 c6aca49..240e26a 进行了独立只读审查。Critical 0，Important 5，Minor 0。以下全部先复现失败、再修复，并重跑完整套件：

1. ExportRecipe equality 漏掉 frameWidth/dateStamp，导致单独修改无效：补齐比较，控制器与 widget 验证应用、撤销、持久化。
2. 保存重试泄漏工具草稿：只重试最近确认文档；分离预览与保存错误重试；取消后数据库保持已确认值。
3. 自动保存失败后退出丢失编辑：停留并提供重试；保存待完成期间禁用编辑、更多与导出，避免新草稿竞争。
4. 迟到 LUT 导入覆盖取消/新选择：工具和选择 generation 校验；库导入可完成，选择只在原事务仍有效时应用。
5. 横竖照片间应用锁定裁切方案失真：按目标旋转后的尺寸重算矩形，保留中心和尽可能多的面积，验证物理输出1:1。

证据：review-fixes-red.log、import-red.log、exit-gate-red.log、review-fixes-green.log、full-test.log。未执行第二轮独立审查；修复通过回归测试验证。

## 测试包与未验证范围

APK：`dist/gremote-photo-editor-1.2.0-dev+11-arm64-debug.apk`

- 包名 com.izhaoo.gremote，versionCode11，versionName1.2.0-dev，minSdk26，targetSdk34。
- SHA256：d96cfa2ffe2dde200e31ccf5e2fb45612f82c8d831923706b0493e4d373ef37d。
- pubspec 发行版本保持1.1.0+5，以上是构建覆盖参数。

最终 ADB 列表为空，没有安装到手机。Android 真机拖动帧率、内存峰值、照片编码/相机兼容性仍需设备验收；iOS 二进制本轮未构建验证。完整 RAW 显影、局部蒙版、透视、降噪和 HSL 不在本批范围。
