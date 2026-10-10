# gremote 出图管线设计（二期）

本设计细化主 spec（`2026-10-09-gremote-design.md`）§11–§12 中不依赖相机的部分：本机相册 → LUT → 边框 → JPEG 导出副本。DNG、GPS 轨迹补写、相机下载不在本期。

## 1. 范围

本期交付：

- 图库 Tab 本机相册网格：默认仅显示 EXIF 机型为 `RICOH GR III` 的 JPEG，可切换全部 JPEG；
- 单张暗房编辑：LUT、强度、三种边框、画幅、信息字段、导出参数，长按预览看原图；
- 网格多选后批量套用同一出图方案并串行导出；
- 5 个脚本生成的原创 33 点 LUT，导入 17/33/65 点 `.cube`；
- 导出为 JPEG 副本，原图永不覆盖，默认去除 GPS；
- 暗房 Tab：最近编辑、LUT 库、已保存的出图方案。

不在本期：DNG、MOV、系统分享接收、反向地理编码、自定义 logo、复制/粘贴逐张微调、导出前台服务、Live View LUT shader。

## 2. 门禁关系

主 spec §17 修订为“开发可并行，验收按序”：不依赖相机的模块可以提前开发并独立测试，但“创作功能门禁”必须在“核心相机功能门禁”通过后才能判定通过。本期产出可安装测试 APK 与真机清单，状态标记为“已开发／待前置门禁”。

## 3. 模块与职责

### 3.1 C++ 核心 `native/imaging/`

C++17，唯一对外头文件 `include/gremote_imaging.h`（C ABI）。

| 模块 | 职责 |
|---|---|
| `jpeg_io` | libjpeg-turbo 3.0.4：从内存整图解码 RGB8、DCT 缩放解码、逐行流式编码 |
| `orientation` | 按 EXIF Orientation 1–8 把 RGB8 转成正向 |
| `resize` | 只缩不放的面积平均缩放 |
| `cube_lut` | 解析 `.cube`（`LUT_3D_SIZE` 17/33/65、`DOMAIN_MIN/MAX`、`TITLE`、注释），值域校验，四面体插值，强度线性混合，按行多线程（最多 4 线程） |
| `frame_compositor` | 按 Dart 给出的几何逐行拼“底色 + 照片 + RGBA 叠层”并直接送编码器，不分配整张输出画布 |
| `api.cpp` | C ABI、错误码、取消标志 |

C ABI：

```c
int32_t gremote_decode_preview(int32_t fd, int32_t orientation, int32_t max_edge,
                            uint8_t** out_rgba, int32_t* out_w, int32_t* out_h);
int32_t gremote_lut_validate(const uint8_t* cube, int64_t len, int32_t* out_size);
int32_t gremote_apply_lut_rgba(uint8_t* rgba, int32_t w, int32_t h,
                            const uint8_t* cube, int64_t len, float strength);
int32_t gremote_export_jpeg(const gremote_export_request* request,
                         const volatile int32_t* cancel);
void gremote_free(void* ptr);
```

- `fd` 为 Kotlin `detachFd()` 交出的只读描述符，C++ 读完立即 `close`，无论成败；
- `gremote_export_request` 包含 fd、方向、LUT 字节与强度、照片输出宽高、画布宽高、底色 RGB、照片位置、叠层数组（x/y/w/h/RGBA 指针）、JPEG 质量、输出路径；
- 错误码：`0 OK`、`1 INVALID_ARGUMENT`、`2 IO`、`3 DECODE`、`4 LUT_PARSE`、`5 LUT_RANGE`、`6 TOO_LARGE`（> 100 MP）、`7 OUT_OF_MEMORY`、`8 CANCELLED`、`9 ENCODE`；
- 导出内存峰值约为原图 RGB8 + 一行输出缓冲 + 叠层（24 MP 约 80 MB）；
- 主机端 CMake + CTest 运行全部 C++ 测试；Android 端 Gradle `externalNativeBuild` 构建 arm64-v8a 的 `libgremote_imaging.so`；
- libjpeg-turbo 源码固定在 `native/third_party/libjpeg-turbo-3.0.4/`，`VERSION.md` 记录来源 URL 与 SHA-256，保留其许可证文件，构建不联网。

### 3.2 Kotlin（Pigeon `MediaHostApi`）

- `queryImages()`：MediaStore 中 `image/jpeg` 条目（id、uri、修改时间、拍摄时间、宽高、大小、显示名）；
- `readExifSummaries(ids)`：机型、厂商、方向、光圈、快门、ISO、35mm 等效焦距、拍摄时间、是否有 GPS；
- `thumbnail(id, edge)`：系统缩略图 JPEG 字节；
- `openReadFd(id)`：只读 fd；
- `publishExport(tempPath, sourceId, displayName, keepGps, width, height)`：按 `ExifPolicy` 把源图元数据写入临时 JPEG，再以 `IS_PENDING` 原子发布到 `Pictures/gremote/`，返回新 uri；
- `share(uri)`：系统 Sharesheet。

`ExifPolicy` 是纯 Kotlin 函数：输入源标签表和 `keepGps`，输出写入标签表。保留机型、镜头、时间、曝光参数、焦距、白平衡、色彩空间；始终去除 `BodySerialNumber`、`LensSerialNumber`、`CameraOwnerName`、`ImageUniqueID`、`MakerNote`、`UserComment`；`keepGps=false` 时去除全部 GPS 标签；`Orientation` 固定为 1，宽高写输出尺寸，`Software` 写 `gremote`。

权限：`READ_MEDIA_IMAGES`、`READ_MEDIA_VISUAL_USER_SELECTED`、`READ_EXTERNAL_STORAGE`（maxSdk 32）、`WRITE_EXTERNAL_STORAGE`（maxSdk 28）、`ACCESS_MEDIA_LOCATION`。未授予 `ACCESS_MEDIA_LOCATION` 时系统会抹掉 EXIF GPS，“保留 GPS”开关禁用并说明原因。

### 3.3 Dart

- `lib/imaging/`：手写 FFI 绑定和 `ImagingEngine` 接口；真实实现在后台 isolate 调用 C++，取消标志用 native 内存跨 isolate 共享；
- `lib/media/local/`：`LocalMediaRepository`，增量扫描 EXIF 并写 SQLite；
- `lib/darkroom/`：
  - `ExportRecipe`：`lutId`、`strength`、`frameStyle`、`ratio`、`sizePreset`、`quality`、`keepGps`；
  - `EditDocument`：`mediaId`、`recipe`、`title`、`location`、`hiddenFields`；
  - `FrameLayout`：纯几何计算，输出画布尺寸、底色、照片矩形和叠层区域；
  - `FramePainter`：在给定 `Canvas` 上绘制叠层内容；预览按比例缩放绘制，导出在输出像素下逐个叠层栅格化，保证一致；
  - `ExportService`：取 fd → 栅格化叠层 → C++ 导出临时文件 → Kotlin 发布；
  - `ExportQueue`：批量串行、单张失败不中断、可取消；
- `lib/darkroom/lut/builtin_looks.dart`（纯 Dart）+ `tool/generate_luts.dart` 生成 `assets/luts/*.cube`，测试校验产物与生成结果逐字节一致。

## 4. 数据模型与存储

SQLite（`sqflite`；主机测试用 `sqflite_common_ffi`），库文件 `gremote.db`：

| 表 | 字段 |
|---|---|
| `local_media` | `media_id` PK、`uri`、`date_modified`、`date_taken`、`width`、`height`、`display_name`、`model`、`orientation`、`exif_json`、`scanned` |
| `edit_documents` | `media_id` PK、`recipe_json`、`title`、`location`、`hidden_fields_json`、`updated_at` |
| `export_presets` | `id` PK、`name`、`recipe_json`、`created_at` |
| `luts` | `id` PK、`name`、`source`（builtin/imported）、`size`、`file_path`、`sha256`、`created_at` |

- 扫描键为 `media_id + date_modified`，变化才重读 EXIF；MediaStore 中已消失的条目删除；
- 内置 LUT id 固定为 `builtin:<slug>`；导入 LUT 先经 C++ 校验，再复制到应用私有目录 `luts/<sha256>.cube`，同哈希去重；
- 编辑只存参数，不存中间大图；
- 默认出图方案：无 LUT、强度 1.0、经典白边、跟随原图画幅、原始尺寸、质量 95、不保留 GPS。

## 5. 边框与画幅

三种样式（`L` 为照片长边像素）：

| 样式 | 底色 | 照片外边距 | 信息区 |
|---|---|---|---|
| 经典白边（默认） | `#FFFFFF` | 上/左/右 `0.035L` | 底部 `0.11L`：左侧机型（衬线粗体）与日期，右侧“28mm f/2.8 1/250s ISO200”，标题/地点在机型下方 |
| 街拍暗蓝金 | `#0C100E` | 四周 `0.045L`，底部 `0.12L` | 照片外 `max(2, 0.0012L)` 像素金色细线；金色衬线机型，参数用等宽字体 |
| 胶片接触印样 | `#111111` | 左右 `0.03L`，上下 `0.085L` | 上下片孔条与片边字（橙色 `#E0913C`，内容为“gremote · 机型 · 日期 · 帧号 01”） |

- 画幅：`original`（按样式边距）、`3:4`、`4:5`、`1:1`；固定画幅时只增加留白补足，绝不裁切；照片与信息区作为整体居中，多出的空间加在上下或左右两侧；
- 字段：机型、焦距、光圈、快门、ISO、日期、标题、地点，均可单独隐藏；标题和地点手填，其余来自 EXIF，缺失时该字段不显示；
- 格式：快门 `<1s` 显示 `1/Ns`（N = round(1/t)），`≥1s` 显示 `1.3s`；光圈 `f/2.8`；ISO `ISO200`；焦距优先用 35mm 等效值；日期 `2026.10.10`；
- 文字字体：机型与标题用 `GRemoteEditorial` 衬线并回退系统中文字体，参数用等宽字体；不内置任何 RICOH 商标图形。

## 6. 导出

- 尺寸：`original`、`long2560`、`long1440`（只缩不放，照片缩放后再计算边框）；
- JPEG 质量默认 95，可选 85/90/95/100；
- 文件名 `gremote_<原文件名去扩展名>_<yyyyMMdd-HHmmss>.jpg`；
- 流程：在应用缓存目录写临时文件 → Kotlin 写 EXIF → `IS_PENDING` 发布 → 删除临时文件；任何失败都删除临时文件和未完成的 MediaStore 条目；
- 批量导出只在 App 前台运行；切到后台可能被系统暂停，界面提示保持前台。

## 7. 界面

- 图库 Tab：顶部“本机 / 相机”分段（相机分栏显示“相机下载在核心相机门禁开放”），筛选“GR III / 全部”，扫描进度条；3 列缩略图网格；未授权显示授权卡，部分授权显示“仅显示你允许的照片 · 继续添加”；长按进入多选，底栏“批量出图 (n)”弹出方案选择，确认后进入队列进度页；
- 暗房编辑页（根导航全屏路由 `/edit/:mediaId`）：上方边框预览，长按看原图；下方分页：LUT（名称 + 小色样）/强度滑杆、边框、画幅、信息（标题、地点、字段开关）、导出（尺寸、质量、保留 GPS）；右上“存为方案”，底部“导出”，完成后提示可分享；
- 暗房 Tab：最近编辑（点击回到编辑页）、LUT 库（内置/导入，导入走系统文件选择器 `file_selector`，可删除导入项）、出图方案（重命名、删除）。

## 8. 错误处理

- C++ 错误码在 Dart 映射为 `ImagingException(code)`；Kotlin 失败映射为 `MediaException(code)`；
- 用户提示包含阶段（读取/调色/合成/编码/保存）、对象（文件名）、错误码、原因和下一步；
- `.cube` 导入错误逐项说明：尺寸不支持、数据行数不符、数值越界或非数字、文件过大（> 16 MiB）；
- 批量导出结束显示成功数与失败明细，可重试失败项；
- 权限被拒、部分授权、存储空间不足都给出明确操作入口。

## 9. 测试

- C++（CTest）：`.cube` 解析（三种尺寸、DOMAIN、注释、尺寸错误、行数不符、越界、NaN）；恒等 LUT 逐像素不变；已知 LUT 采样值；强度 0 等于原图；8 种方向；面积缩放；合成器底色、照片位置与叠层 alpha；JPEG 编解码往返尺寸与均值误差；缩放解码因子选择；取消返回 `CANCELLED`；
- Dart 单元：`FrameLayout`（3 样式 × 4 画幅 × 字段隐藏）、EXIF 格式化、`ExportRecipe` 序列化、LUT 生成器与资产逐字节一致、SQLite 仓库（`sqflite_common_ffi`）、`ExportQueue` 失败继续与取消；
- FFI 集成：主机先构建 `libgremote_imaging.dylib`，Dart 测试通过真实 FFI 校验 LUT、预览解码和导出；
- Kotlin JVM：`ExifPolicy` 白名单、GPS 开关、方向与尺寸覆盖；
- Widget：图库授权/部分授权/扫描/筛选/多选，编辑页控件与导出流程，暗房 Tab 三个分区；
- 真机清单：GR III JPEG 竖拍方向、24 MP 导出耗时与内存、三种边框 × 四种画幅、批量 20 张、GPS 开关、部分授权、导入 65 点 LUT。
