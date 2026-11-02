# 第一批照片编辑器

用户已批准 `gr-photo-editor.html` 视觉与第一批完整落地，直接执行，不重复请求确认。工作在 develop，保留现有功能，不修改相机协议或 M10V 固件。

## 范围与体验

工具网格 → 单工具编辑 → 取消/完成。照片优先，深灰背景与中性白控件，滑杆/照片横向拖动调节，参数按钮可点选；动画遵守减少动态效果设置。双指缩放、原图对比、单工具重置、撤销/重做、自动保存、方案与导出。一次拖动为一次历史操作，取消工具恢复进入工具前的完整文档。长按对比恢复未裁切、无边框原图，松开/取消恢复编辑后。

首批：基础（曝光、对比、高光、阴影、白、黑、色温、色调、饱和度、自然饱和度），裁切（自由/固定横竖比例、移动/缩放裁切框、校正±45°、四分之一转、双向翻转），LUT（已有库、自定义导入与强度），RGB/R/G/B 曲线，暗角（强度/范围/羽化），颗粒（强度/大小/粗糙度），光晕与柔光（强度/范围/阈值），漏光（强度/位置/范围/颜色/换一个），边框（无/等宽白/等宽黑/留白/拍立得/现有胶片印样），以及视觉稿已有的褪色/黑白与日期印记。现有信息字段、画布留白比例、方案保存及尺寸/质量/GPS 导出保留入口。照片编辑不依赖 M10V。新建编辑默认无边框，与视觉稿一致；旧文档保留已保存样式。

## 技术方案

采用既有 Flutter + C++/libjpeg FFI，新增统一参数模型和共用原生处理流水线。另行维护 Dart 预览滤镜会产生结果差异；仅缩略图滤镜会丢失原尺寸导出，所以二者不采用。

固定处理顺序：EXIF方向 → 90°旋转/翻转 → 校正（放大填满以免黑角）→ 归一化裁切 → 目标尺寸缩放 → 基础 → LUT → 曲线 → 光晕/柔光 → 暗角/褪色/黑白/漏光/颗粒 → 原有 FramePainter 统一文字/边框 → JPEG。

预览与导出共用参数和原生算法。纹理以归一化坐标和固定 seed 定位，半径与照片长边成比例；同尺寸 RGBA 路径一致，JPEG 允许编码损失，缩略预览不承诺与原尺寸逐像素相等。测试实际比较解码后的 JPEG 与同尺寸原生预览，不用构建代替效果证据。RAW 完整显影、局部蒙版、透视、降噪与 HSL 为后续范围。

## 数据与原生 ABI

`PhotoEdits` 不可变，存入 `ExportRecipe.edits`，旧 JSON 缺省为恒等。曲线为归一化控制点，序列化后生成四条256点保形三次插值 LUT（单调区间无过冲，允许用户绘制反转曲线）；用户参数与曲线越界/NaN 防御处理。`CropEdit` 归一化矩形基于旋转后画面，尺寸使用 round、至少1像素；旋转换轴，输出不放大。

Native 浮点协议 v1 长度 **1062**：0 version=1；1 exposureEV；2 contrast；3 highlights；4 shadows；5 whites；6 blacks；7 temperature；8 tint；9 saturation；10 vibrance；11 vignette；12 vignetteSize；13 vignetteFeather；14 grain；15 grainSize；16 grainRoughness；17 halation；18 halationRadius；19 halationThreshold；20 bloom；21 bloomRadius；22 bloomThreshold；23 leak；24 leakPosition；25 leakSpread；26 leakHue；27 fade；28 monochrome；29 seed（1..16777215）；30 cropLeft；31 cropTop；32 cropWidth；33 cropHeight；34 quarterTurns；35 flipX；36 flipY；37 straightenDegrees；38..1061 四条256点 RGB/R/G/B曲线。除EV、角度、turns、seed外数值归一化，双向参数[-1,1]，其余[0,1]。seed默认7331。几何默认0,0,1,1、turns=0、flip=0、angle=0；范围/羽化/粒径/粗糙度/效果半径阈值有模型默认但强度默认0。曲线默认恒等。

新增 C ABI `gremote_render_edit_rgba(const uint8_t* rgba,int32_t width,int32_t height,const float* edits,int32_t edit_count,const uint8_t* cube,int64_t cube_length,float lut_strength,int32_t target_width,int32_t target_height,uint8_t** out_rgba)`；输入RGBA不变，out用gremote_free释放。现有 export request 尾部追加 `const float* edits; int32_t edit_count;`，空指针/count0保留旧行为。无效输入失败且不泄漏内存/fd。导出取消和原子写保留。

`ImagingEngine.renderPhoto(PreviewImage source, {required Float32List adjustments, Uint8List? cube, double strength=1, required int width, required int height})` 返回处理后的 RGBA；`ExportJob.adjustments` 为可空 Float32List。

## 调度与一致性

仅一个预览任务在途，拖动更新合并，过期结果丢弃并接续最新参数；主线程不处理像素。预览尺寸根据裁切后的1600长边原图计算。导出捕获当前已确认文档，禁用导出中的编辑与重复提交。工具内草稿不写数据库，完成后自动保存；退出时提交当前草稿，取消明确恢复。保存失败反馈可见且可重试。改变裁切时预览布局只采用最新已渲染几何，避免旧像素拉伸成新形状。

## 验证

模型迁移、曲线边界、裁切方向/极限、序列化；native 中性恒等、参数生效、色阶不反转、曲线、稳定seed、几何与各方向、预览/JPEG误差、无效输入与取消；控制器合并任务/过期结果/草稿撤销/保存失败/导出参数；widget 网格、面板、手势取消、320px大字/横屏、导出入口。完整 Flutter/native 测试、analyze、Android arm64 构建。硬件未接通时明确记录未进行真机流畅度与相机兼容性验收。
