# App Appearance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 落地已确认的首页设置入口、全局深浅/系统主题、触感开关和透明Logo，保持照片及机身行为。
**Architecture:** 本地App偏好与相机存储隔离；以ThemeExtension提供可响应的语义色，MaterialApp选择ThemeMode。已有图片内容颜色不迁移为UI色。
**Tech Stack:** Flutter 3.24.5, Riverpod, sqflite, native system haptics.
**Spec:** docs/superpowers/specs/2026-11-03-studio-ui-and-appearance-design.md

## Global Constraints
- develop，保留既有改动；用户已2026-11-03确认最新视觉稿。
- 深色沿用#171A1D/#23272A/#EFEEE8；浅色#F7F6F2/#F2F1EC/#222725。
- 旧安装/损坏偏好默认为dark；system随系统变化，显式主题不跟随；冷启动先加载偏好。
- UI中文；主题不能更改照片、边框/文字导出颜色、编辑记录、相机请求；对焦与快门分离。
- 本轮不刷机、不改SD、不push或发布；host测试不代表真机外观/流畅度。

## Review Focus
- 异步偏好读写失败或快速连续点选：只接受最新意图，失败可见且可重试；不覆盖其他App键。
- 弹层、禁用/错误、加载及拍摄画面叠加色在浅色下可读，原照片内容不反色。
- 深浅切换发生在修图草稿/导出/相机连接期间：文档、导出参数、连接状态不变。
- 旧版RGB Logo没有alpha：只有光圈/字标可着色，无白/黑矩形块。
- 320px、大字体、系统减少动态效果：入口、主题选项及返回均可用。

### Task 1: App偏好与启动主题
**Files:** Create lib/settings/app_preferences.dart, preferences_repository.dart, preferences_controller.dart; test/settings/app_preferences_test.dart; Modify lib/main.dart, lib/app/app.dart and databaseProvider wiring only as needed.
**Interfaces:** ThemePreference {dark,light,system}; AppPreferences(theme,haptics); PreferencesRepository(Database).load()/save(AppPreferences); appPreferencesProvider returns hydrated state including saving/error, setTheme(ThemePreference), setHaptics(bool), retry(). Bootstrap loaded preference before routed UI.
- [ ] RED：缺键/坏键→dark+触感true；读写只操作settings.appearance/settings.haptics；快速写入后最新选择生效；保存失败可重试；不清空其他键。
- [ ] Run `flutter test test/settings/app_preferences_test.dart --reporter expanded`; Expected FAIL before implementation.
- [ ] 实现模型、repository及有序保存controller；App启动依赖可覆盖，失败保留默认及错误状态；无相机调用。
- [ ] 同命令GREEN；`flutter analyze`无新增问题；提交feat(settings): persist app appearance preferences。

### Task 2: 语义主题与透明字标
**Files:** Modify lib/app/theme/app_colors.dart, app_theme.dart, lib/app/app.dart; Create lib/app/theme/app_palette.dart, lib/app/widgets/brand_wordmark.dart; Modify lib/features/home/widgets/home_brand.dart (actual name via rg) and UI color consumers in lib/app, lib/features, lib/camera diagnostic widgets only; Test test/app/app_appearance_test.dart, test/widgets/brand_wordmark_test.dart.
**Interfaces:** AppPalette extends ThemeExtension<AppPalette> with background/surface/raised/text/muted/divider/accent/danger and dark/light constants; context.palette getter. GRemoteTheme.dark/light + ThemeMode mapping. BrandWordmark(width: double) uses existing source geometry and true alpha mask, theme tint.
- [ ] RED：主题切换真实MaterialApp brightness/页面语义色更新，系统与显式模式隔离；Logo的alpha阈值数学角点0、前景1、边缘连续，主题颜色不是背景贴片；原FrameLayout颜色不随主题变动。
- [ ] Run `flutter test test/app/app_appearance_test.dart test/widgets/brand_wordmark_test.dart --reporter expanded`; Expected FAIL.
- [ ] 定义AppPalette并迁移展示层颜色。保存模型/渲染参数/FramePainter中的图片内容色不替换；照片上的控件用明确overlay对比色。保留legacy颜色常量供非UI数据消费者，防止请求或图片ABI受影响。
- [ ] 同命令GREEN，跑现有home/shoot/library/camera/editor widget套件；视觉核对所有主题下的弹层/禁用/错误；提交feat(theme): add adaptive palette and transparent brand mask。

### Task 3: 设置页面与首页入口
**Files:** Create lib/features/settings/app_settings_page.dart; Modify lib/features/home/home_page.dart, lib/app/router.dart; Create lib/app/interaction/app_haptics.dart; Test test/features/app_settings_page_test.dart.
**Interfaces:** route /settings outside bottom shell; AppSettingsPage watches appPreferencesProvider and writes only local prefs. AppHaptics.selection() checks app haptics before platform feedback. Existing home WiFi/diagnostics preserved.
- [ ] RED：点击首页…出现设置且原两项保留；进入/返回不改连接controller；3主题互斥且保存；触感关闭不发平台调用；版本/许可证真实；320px与1.6字体无溢出。
- [ ] Run `flutter test test/features/app_settings_page_test.dart --reporter expanded`; Expected FAIL.
- [ ] 按确认稿实现设置与about，偏好失败显示重试；不增加缓存/固件操作；读取真实包版本和LicenseRegistry。各入口轻动效尊重减少动态效果。
- [ ] 同命令GREEN；完整`flutter test`、`flutter analyze`、Android arm64构建；独立全分支review，修复重要项RED/GREEN；提交feat(settings): expose appearance and haptics from home。
- [ ] 手机可用后覆盖安装保留数据，实测3主题冷启动和系统变化；记录真实版本/哈希及未测项，用户验收前不发布。
