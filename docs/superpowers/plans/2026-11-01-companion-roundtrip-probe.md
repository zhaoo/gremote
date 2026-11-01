# 相机跨域往返探针实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 交付在GR III2.10/e78dd1d7上验证TTL所有缓冲经Linux读取并向手机连续传输的SD探针，作为原B1/B2缺少的设备证据；不开放设置写入。

**Architecture:** 独立TTL脚本分配唯一16-word数组并在同步lcmd调用期间持有；Linux freestanding ARM ELF只读验证已安装候选的ROM指纹/数组表/边界，再输出带run_id/序号/输入值的回执，退出前解除映射。Linux以O_RDONLY/PROT_READ映射，完全不写相机RAM。TTL连续16轮发布临时数组，共3遍且沿用同一run_id，最多48次调用；每轮Linux只绑定核实的相机Wi-Fi接口，短时提供固定只读探针路径，手机采集器验证全部16个不同轮次响应（可跨遍历，重复去重）。TTL只通过RTOS API记录发布报告；没有后台驻留监听或固件Hook。

**Tech Stack:** C11、Python3、Clang/LLD、相机TTL、现有Node固件解码器。

**Spec:** docs/superpowers/specs/2026-10-21-integrated-film-workbench-design.md（B1/B2前置所有权/缓存证明）；本计划不扩大read/write能力。

## Global Constraints

- GRemote在develop，M10V/GRKit原工作区只读；新增探针不修改固件、相机配置、照片、原有STARTUP或PLUGINS。
- 地址来自固定GRKit目标与本次已验证BIN，禁止堆扫描、未知机型、扩大数组容量或绕过指纹检查。
- 探针仅实验性验证往返；即使16轮通过，也不证明RTOS写设置所有者、FS提交域、长期缓存或拍摄性能。
- 模拟/ARM构建不能替代设备结果；只生成独立可审阅包，不自动启用SD脚本。

## Review Focus

1. 其他脚本分配额外数组、对象替换及容量不足必须零写。
2. ROM不符、缓存维护失败、重复/跳序请求必须零写或保留未确认，不能伪报成功。
3. Linux不能写RAM，输出仅stdout及绑定相机Wi-Fi的固定探针HTTP响应，不写SD；不能触及机内存档或照片。
4. TTL必须保持数组直到Linux退出，不异步后台或先退出；脚本异常不留下Hooks/后台进程。
5. 安装包不能覆盖现有STARTUP/其他SD脚本，权限启用与实际跑探针需要用户操作。

### Task 1: 有界往返核心
- [ ] 用宿主稀疏内存harness写真实成功、错误指纹/维度/数量/重入/跳序/边界/换对象/失败cache测试，观察RED。
- [ ] 实现只读校验与有界回执，GREEN，审计内存接口中没有写入口。

### Task 2: Linux ARM与目标绑定
- [ ] 测试实际候选sha/CRC/buildId绑定，缺输入拒绝和ELF无动态依赖，观察RED。
- [ ] 分离全部内存O_RDONLY/PROT_READ映射；直接syscall，核对最终ELF；所有错误关闭映射/fd。

### Task 3: TTL与配套包
- [ ] 测试16轮、同步等待、canary、失败退出、无STARTUP覆盖/ModeSet自动开启、拒绝覆盖输出目录，观察RED。
- [ ] 生成TTL与同步执行包装器、手机采集器、说明、SHA、source/target manifest和自有文件恢复清单。

### Task 4: 审查与交付
- [ ] 全部探针测试、ARM ELF和包CRC/SHA检查。
- [ ] 一次独立完整审查，修正重要问题（每项RED/GREEN），不发起重复审查。
- [ ] 交付仅供用户手动启用的探针，收集16轮/失败阶段；未回传前设备项not-run。
