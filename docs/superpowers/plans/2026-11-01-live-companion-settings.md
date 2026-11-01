# 最新 M10V 机内设置读取与装卷接通实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在最新 M10V 十槽状态上接通真实快照读取、经机身提交及回读确认的写入和 App 装卷。

**Architecture:** 沿用已批准的专用 Wi-Fi 伴侣服务及认证、revision、幂等收据协议；实机只读探针已提供读取方向证据。读取复用机身发布的版本化有效状态，持续提交通过有生命周期的 RTOS 配置所有者执行。旧五槽合同与最新十槽/184-byte状态明确区分，不能静默截断或伪造fresh/write能力。

**Tech Stack:** C/ARM、Python、Flutter/Dart、既有 Node 合同生成器。

**Spec:** ../specs/2026-10-21-integrated-film-workbench-design.md；本计划是原 B1–B5/C3 的继续实施，用户已明确要求继续，保留原视觉，不新增 UI 方向审批。

## Global Constraints
- GRemote在develop，保留现有改动；M10V从最新origin/main a24ccc2隔离工作树实施，线上同SHA，原脏工作区不动。
- 保留十槽、184-byte version5 M10V6A/B存档及旧104-byte迁移、现有所有胶卷/ISP/RAW/拍摄快照；不把旧五槽实现覆盖最新源码。
- 手机USB/相机Wi-Fi可读写调试已授权；SD脚本持久开关已获用户同意并反馈Enable/Complete。Mac只读SD，包先传手机，由用户关机后写卡或升级；不重复申请同一授权。
- Linux不调用RTOS函数，不写照片卷。设置写入须通过RTOS提交所有者、busy/版本检查、单次保存及回读；保存与正式切槽分开。
- 不改变对焦/快门协议；不自动触发拍照。认证/配对材料与固件、用户设置不进Git。
- App仅展示层中文；不改配方协议值。不用模拟/ARM通过冒充设备写入。

## Review Focus
1. 第6–10槽、空槽、现有新胶卷ID及保留字节不能丢失或改写。
2. 读到坏CRC/半更新/换owner/旧版本时必须拒绝或明确未确认，不能fresh。
3. 本地菜单并发、忙态、重复请求或丢ACK不得导致二次保存或伪报回滚。
4. owner失效和相机重启后旧请求不得继续访问旧内存或提交。
5. 旧App/旧协议/过期catalog与renderer只读或拒绝，不能绕过兼容检查装卷。

## Task 1: 当前运行状态读取
**Files:** GRemote native/camera_probe/state_reader.{h,c}、scripts/camera_probe_tests/test_state_reader.py、scripts/build_camera_probe.py；M10V native/gr3/m10v_library_camera.c作为固定来源。
**Interfaces:** mc_state_observe(target, io, out)返回184-byte状态、版本、来源和错误；复用只读内存接口，无写入口。
- [ ] RED: 十槽有效快照读取；错误CRC/版本、奇数版本、换owner/版本变化、越界和读失败拒绝，原字段保持。
- [ ] GREEN: 验证ROM、owner和两次完整状态/版本；状态本身CRC有效。暂不把该读法当RTOS提交入口。
- [ ] 验证宿主及实际ARM读取路径，记录命令/失败/通过。

## Task 2: 最新合同与 App 接入
**Files:** scripts/templates/companion_protocol.dart.tmpl、lib/camera/companion/*、lib/features/film_workbench/camera_films_page.dart、相关test；隔离M10V contracts及native/companion。
**Interfaces:** 版本化十槽快照/参数能力；拒绝不匹配的旧五槽写请求，保留已存本地配方。
- [ ] RED: 十槽完整读出、当前槽9/空槽与新ID、未知字段只读、schema不匹配禁写；原幂等/重启恢复不变。
- [ ] GREEN: 从最新源生成合同和清单，认证服务接真实只读adapter，App显示真实设置；协议生成源同步修改。
- [ ] 跑相关Dart/合同/host-HTTP与ARM检查，构建APK。

## Task 3: RTOS提交所有者和回读
**Files:** 隔离M10V native/gr3/m10v_companion_owner.c、m10v_companion_target.c、native/companion/{mailbox,transaction}.*及相关测试/构建接点。
**Interfaces:** 同一RTOS owner串行snapshot、persist_once、formal tone setter/readback；ownerGeneration/lease/cache具备目标证据。
- [ ] 定向核实原厂UI派发/唤醒/生命周期；证据不足继续研究具体入口，不填ready占位。
- [ ] RED: 竞争、busy、CRC/字段无效、其他槽/保留字节保持、一次保存、读回失败、重复请求和重启未知结果。
- [ ] GREEN: 接真实owner和目标cache；本地/远程共享提交，操作收据返回真实回读。
- [ ] 跑settings/SD/capture/RAW相关回归，默认关闭扩展时原行为保持。

## Task 4: 真实设备读写与装卷
**Files:** scripts构建/打包、docs/testing设备证据、App集成测试。
- [ ] 一次独立整体验证/审查，重要项RED→GREEN；测试包包含构建身份、备份与撤除。
- [ ] 先将新组件传手机，需SD或固件更新时由用户操作；不尝试越过公司Mac只读限制。
- [ ] 真机读出十槽；一次已授权的最小设置修改→机内/持久回读→正式切槽；App装卷走同一事务，故障/重连不重复保存。
- [ ] 记录实际通过/未测边界，未通过不开放生产能力或发布。
