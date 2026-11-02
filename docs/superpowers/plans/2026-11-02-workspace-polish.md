# GRemote Workspace Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 将已确认的全工作区视觉稿落地到 Flutter，保留现有功能并增加克制动效。

**Architecture:** 复用原服务、Riverpod 控制器与平台 API。新增只读能力展示模型和公共动效组件，分别更新胶卷/扩展、相册/编辑器和拍摄布局，不改变协议或成片算法。

**Tech Stack:** Flutter、Dart、Riverpod、GoRouter、现有测试网关。

**Spec:** `docs/superpowers/specs/2026-11-02-workspace-polish-design.md`

## Global Constraints

- 全部修改在 `develop`，保留已有提交；不修改旧 daily worktree、M10V 固件或发布流程。
- 拍摄、传输 UI 使用中文；不改变请求字段和值。
- 不支持时置灰禁用，普通 GR 的传输、拍摄与手机编辑不受影响。
- 不能由超时或缺少配对文件断定未安装 M10V；断连与过期快照不能解锁。
- 实机取景完整显示；点按对焦、独立 AF 与快门保持分开。
- 左右 20dp、列距 14dp、行距 16dp 的三列胶卷网格。
- 动效遵守减少动态效果设置，不动画实时图像帧或重复提交业务请求。

## Review Focus

1. 缓存能力存在但网络断开、配对变化或快照过期：机内操作必须保持禁用。
2. 320dp/568dp 与大文字、横屏：工具栏、长胶卷名、参数和快门可用，无溢出。
3. 相册切源、搜索开关、导入/导出期间过渡：不丢选择、不重建传输、不重复请求。
4. 对焦点落在预览黑边、对焦失败、按住快门时断连：不得错误拍摄或映射坐标。
5. 扩展仅支持部分字段或存在 pending 写入：只开放实有能力，确认后仍由原控制器校验。

---

### Task 1: 公共视觉与动效

**Files:** `lib/app/theme/app_colors.dart`, `app_theme.dart`, `lib/app/widgets/workspace_motion.dart`, `workspace_tabs.dart`, `lib/app/router.dart`, `test/app/workspace_motion_test.dart`。

**Interfaces:** 产生 `WorkspaceMotion.duration(BuildContext, int)`、`WorkspaceReveal(visible, child)`、`WorkspaceTabs<T>(items, value, onChanged)`；组件不得执行网络动作。

- [x] 补 reduced-motion 下展开/切换仍可操作且不重复回调的行为测试，运行看到 RED。
- [x] 实现公共组件和中性色主题；保留首页布局和无下划线底栏。
- [x] 运行组件测试与现有首页/导航测试，GREEN；提交。

### Task 2: 相机能力与胶卷库

**Files:** 新增 `lib/features/camera/camera_availability.dart`；修改 `camera_page.dart`, `film_library_page.dart`；测试 `test/features/camera/camera_availability_test.dart`, `camera_page_test.dart`。

**Interfaces:** 产生只读 `CameraAvailability`、`cameraAvailabilityProvider`；消费当前连接、CompanionSyncState 和配对控制器。暴露 `canReadFilms`, `canInstallFilms`, `hint`，通过监听原控制器刷新，不自行发明固件状态。

- [x] 补断连/过期/部分能力/超时不解锁的门禁测试，以及紧凑搜索、来源和置灰预览测试，RED。
- [x] 保留配对和诊断入口，使用当前连接与能力的组合；按需执行原有只读刷新。
- [x] 胶卷表格换成带真实封面的三列网格，来源工具栏与展开搜索；详情和十槽入口按当前能力禁用。
- [x] 检查 320dp、大文字和长名称；运行相关能力/胶卷测试，GREEN；提交。

### Task 3: 扩展设置

**Files:** `lib/features/camera/extensions_page.dart`；测试 `test/features/camera/extensions_page_test.dart`。

**Interfaces:** 消费原 `CameraExtensionsController` 的 capabilities/snapshot/canWrite，保留 `_confirm`、revision 和 acknowledge 路径。

- [x] 补未连接和部分能力的禁用行为测试，RED。
- [x] 将整页阻断替换为可见的灰色分组设置；删去重复卡片说明，保留必要状态、配对和 pending 核对入口。
- [x] 支持字段继续确认/保存/读回；已不可用的设置不得被过渡动画保留为可点击。
- [x] 运行扩展 UI 和控制器测试，GREEN；提交。

### Task 4: 相册与编辑器

**Files:** `lib/features/library/library_page.dart`, `widgets/media_grid.dart`, `camera_gallery.dart`, `lib/features/darkroom/editor/editor_page.dart`, `widgets/editor_panels.dart`；对应现有 UI 测试。

**Interfaces:** 消费公共 tabs/motion；保留 IndexedStack、LibraryController、媒体网关和 EditorController。

- [x] 补切源期间选择/传输保留、按住对比释放后恢复及小屏导出入口的交互测试，RED。
- [x] 相册顶部改为标题与右侧操作、下面简洁切源；日期和三列图库保留，点击/长按行为保持。
- [x] 编辑器预览居中、顶部导出和方案操作、紧凑工具区；所有现有工具可达，面板切换加入轻过渡。
- [x] 运行相册、传输、编辑器回归和小屏检查，GREEN；提交。

### Task 5: 拍摄与交付验证

**Files:** `lib/features/shoot/shoot_page.dart`, `widgets/top_bar.dart`, `bottom_bar.dart`, `param_row.dart`, `shutter_button.dart`, `viewfinder.dart`；`test/features/shoot_page_test.dart`；`docs/testing/2026-11-02-workspace-polish.md`。

**Interfaces:** 底栏新增独立 `onFocus` 回调，直接调用既有 `_tapAf`；保留原按压/释放快门、程序执行与恢复。取景继续消费原隔离解码面，不每帧重建控制区。

- [x] 补独立 AF 不拍摄、小屏/横屏底部布局、完整图像点映射及 reduce-motion 行为测试，RED。
- [x] 大取景区域、简化顶部、默认曝光参数、底部模式和快门/相册/AF；其他已有功能从设置和模式入口保留。
- [x] 参数面板/组合方案展开和 AF 状态使用轻动效；无持续装饰动效。
- [x] 运行针对性测试、完整 `flutter test`、`flutter analyze`、arm64 debug APK 构建；记录实际结果和未执行的设备检查。
- [x] 按 executing-plans 进行一次独立全量代码审查，修复重要问题并完成回归，提交和交付可识别 APK；不 push 或发布。
