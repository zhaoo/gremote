# Photo Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 完整实现已批准视觉稿与首批修图工具，预览和导出使用相同原生算法。

**Architecture:** 不可变 PhotoEdits + CropEdit + ToneCurve 参数模型持久化至 ExportRecipe；C++ 共用几何/色彩/质感流水线；Flutter 控制器处理草稿、合并预览和历史，工具网格与单工具面板承载交互。

**Tech Stack:** Flutter/Riverpod, Dart FFI/isolates, C++17, libjpeg-turbo, existing SQLite.

**Spec:** docs/superpowers/specs/2026-11-02-photo-editor-design.md

## Global Constraints

- develop 分支，不覆盖用户改动；不修改相机、AF/快门、固件或网络写入逻辑。
- 预览/导出使用同一1062 float参数ABI及原生实现；旧文档/批量导出保持兼容。
- 照片数据无损；工具取消恢复完整状态；seed稳定；主线程不进行图像处理。
- 可访问文字与减少动态效果；小屏面板可滚动、照片完整适屏。
- 测试/构建不等于真机性能结论；不 push/发布。

## Review Focus

- 裁切、90°、EXIF方向组合不应双转或导出错误尺寸。
- 快速拖动/退出/切照片不能让过期预览覆盖新参数或写错文档。
- 混合 LUT、曲线、模糊和纹理在预览与导出中顺序一致。
- 取消工具、撤销整段拖动、重新打开必须恢复相同参数/seed。
- 低分辨率、极细裁切和大字体/横屏不应零尺寸、越界或不可操作。

### Task 1: 参数模型与旧数据迁移

**Files:** Create lib/darkroom/model/photo_edits.dart; modify export_recipe.dart; test/darkroom/photo_edits_test.dart.
**Interfaces:** PhotoEdits const默认、fromJson/toJson/copyWith/withValue、nativeParameters；CropEdit.outputSize(width,height)；ToneCurve.samples()；ExportRecipe.edits。
- [ ] RED: JSON旧数据恒等、曲线排序去重/有限值、裁切旋转换轴/至少1像素、参数1062且曲线端点恒等、所有新参数roundtrip测试。
- [ ] Run flutter test test/darkroom/photo_edits_test.dart; expected missing behavior.
- [ ] Implement model/serialization/validation, then rerun targeted tests green.
- [ ] Commit model and tests.

### Task 2: 统一原生修图处理

**Files:** native/imaging/{include/gremote_imaging.h,src/photo_edits.h,src/photo_edits.cpp,src/api.cpp,CMakeLists.txt,tests/photo_edits_test.cpp}.
**Interfaces:** Spec C ABI gremote_render_edit_rgba and appended export request fields; same core RenderPhoto for export and preview.
- [ ] RED: neutral unchanged, adjustments/LUT/curves/effects behavior, seed stability, rotate/crop including EXIF, invalid params and cancellation, preview against exported JPEG tests.
- [ ] Run scripts/build_native_host.sh and native tests; expected missing ABI/behavior.
- [ ] Implement validated bounded processing, release buffers and descriptor ownership, preserve legacy null params path.
- [ ] Build host and ctest --test-dir native/imaging/build/host --output-on-failure green; commit native files/tests.

### Task 3: FFI 与导出接线

**Files:** lib/imaging/{imaging_engine.dart,imaging_bindings.dart,ffi_imaging_engine.dart}; test/support/fake_imaging_engine.dart; test/imaging/photo_edits_ffi_test.dart; lib/darkroom/export/export_service.dart; frame/frame_layout.dart; model/export_recipe.dart.
**Interfaces:** renderPhoto signature from spec; ExportJob.adjustments; frame width/style/date options shared by EditorState.layout and ExportService.
- [ ] RED: same-size native rendered vs JPEG result, input unmodified, geometry dims, all options passed through service and frames pixel geometry tests.
- [ ] Implement FFI copy/release in isolate and native params export; crop-aware photo sizing and additional border/date layout.
- [ ] Run flutter test test/imaging test/darkroom; expected green. Commit only owned files.

### Task 4: 编辑状态与交互调度

**Files:** editor_controller.dart; test/features/editor_workflow_test.dart.
**Interfaces:** beginTool/commitTool/cancelTool, beginGesture/endGesture, setEdits, undo/redo, flushPreview and existing metadata/export/preset methods.
- [ ] RED: tool draft cancel, one drag one undo, redo/reset, roundtrip persisted params, max one render active/stale discard, error recovery/disposal and export captures same recipe.
- [ ] Implement bounded history, serial latest-only preview loop, commit autosave queue and error status. Disable editing while export pending.
- [ ] Run workflow/controller/export tests green; commit.

### Task 5: 已确认视觉稿 UI

**Files:** editor_page.dart; new widgets/editor_tools.dart,adjustment_panel.dart,curve_panel.dart,crop_panel.dart; existing editor_panels.dart/frame_preview.dart; test/features/editor_page_test.dart.
**Interfaces:** Controller methods from Task4; PhotoEdits from Task1; existing FramePreview and metadata/export panels preserved.
- [ ] RED: tools grid navigation, slider immediate value + final render, press cancel comparison, curve point operation, crop presets/free handles, finish/cancel, LUT import/selection, presets/history/export and narrow/landscape large text.
- [ ] Implement responsive grid and scrollable tools; animated panel transitions respect reduced motion; zoom and direct drag scopes do not conflict; full original comparison layout.
- [ ] Run flutter test test/features/editor_page_test.dart test/features/editor_workflow_test.dart green. Commit.

### Task 6: 整体验证与独立审查

**Files:** docs/testing/2026-11-02-photo-editor.md; dist/verification/photo-editor.
- [ ] Native ctest, full flutter test, flutter analyze, arm64 APK build; inspect widget captures and pixel comparison evidence. Record skipped/hardware limits precisely.
- [ ] Fresh reviewer for whole changed range, fix material findings with RED/GREEN tests, rerun required suites.
- [ ] Record report, package APK, commit final changes. Preserve develop, do not push or publish; provide reviewable result.
