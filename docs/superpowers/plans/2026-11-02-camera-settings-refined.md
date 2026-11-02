# Camera Settings Refinement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Tasks may be delegated in parallel for disjoint UI files per dispatching-parallel-agents.

**Goal:** 落地已确认的固定首页图、拍摄设置、紧凑十槽/装卷及分组扩展界面。
**Architecture:** 复用Flutter/Riverpod现有控制器与状态机，只调整展示和可解释状态。相机协议、native服务、固件及事务保护不变。
**Tech Stack:** Flutter, Riverpod, existing native/photo engine.
**Spec:** docs/superpowers/specs/2026-11-02-camera-settings-refined-design.md

## Global Constraints
- develop；保留用户改动；不刷相机/改SD/变更机内设置，不真实装卷。
- 所有wire字段和值保持原样，AF不能以拍照回退。
- 保留原能力、并发、pending和结果未知保护。
- UI中文、简洁、尊重减少动态效果；主机证据与真机证据分开。

## Review Focus
- 关闭封面功能不能删除照片/影响导入计数；不得继续后台读取封面。
- 拍摄设置中的动态值不得使用旧状态，未知wire值不可译成错误选项。
- 装卷简化不能藏掉覆盖信息、冲突选择或导致未经最终确认写入。
- 扩展分组不能遗漏21字段及原灰态门禁，GET失败不能误报写入未完成。
- 小屏、大字体、横屏和读取中/结果未知时操作必须仍明确可达。

### Task 1: 固定首页与拍摄设置
**Files:** lib/features/home/home_page.dart, widgets/home_cover.dart, home_cover_settings.dart/manager.dart入口引用；lib/features/shoot/shoot_page.dart,shoot_labels.dart；相关home/shoot测试。
**Interfaces:** 既有route、connection、gallery、cameraState接口不变；首页不再watch封面相册provider；设置继续使用当前state和原ruler/action回调。
- [x] 写回归：首页固定图且不读取封面；拍摄设置分组、开关、timer选择、原字段、窄屏和动态值。
- [x] 运行RED，最小实现；目标测试GREEN，保留现有拍摄/导入测试；不操作设备。

### Task 2: 十槽与装卷确认
**Files:** lib/features/film_workbench/camera_films_page.dart,必要新增展示widgets；test/features/camera_films_page_test.dart。
**Interfaces:** 现有CompanionSyncController.prepare/confirm/readback/retry接口不变。
- [x] RED覆盖紧凑列表、目标/当前状态、导入/调整入口、覆盖提示、折叠参数、unknown/conflict和禁用条件。
- [x] 实现中性灰样式及真实进度，目标测试GREEN；不真实发写入。

### Task 3: 分组扩展与精确状态文案
**Files:** lib/features/camera/extensions_page.dart,extensions_providers.dart如必要；lib/camera/companion/extensions_controller.dart仅错误展示分类；test/features/camera/extensions_page_test.dart及controller测试。
**Interfaces:** 保留全部协议字段与控制器apply/readback/pending机制；仅GET失败与unknown状态展示分开。
- [x] RED覆盖展开分组、全部字段、能力不支持/未就绪/读取失败/unknown文案、灰态与并发门禁、320px大字。
- [x] 实现分组/确认，不虚构原子批量保存；目标测试GREEN。

### Task 4: 集成、构建与App设备验收
- [ ] 独立审查完整改动；修复重要问题并补RED/GREEN；完整Flutter测试、analyze与Android arm64包。
- [ ] 样式最终候选用v13安装，保留手机App数据；用户2026-11-03明确延后修图真机验收，不能声称已验证。
- [ ] 安装后按用户要求恢复相机设置只读诊断：先核对GRIII街拍版、2.10改造构建身份/boot和能力，再读取机身及扩展设置；未经确认的操作不盲重试，不刷固件/改SD。记录限制；提交develop，不push/发布。
