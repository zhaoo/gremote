# GR III Hardware Gate 1

本门禁用于小米 14 与 RICOH GR III 固件 2.10 的人工验证。记录中禁止包含 Wi‑Fi 密码、相机序列号、完整 BLE 地址、照片内容或精确 GPS 坐标。

## 构建信息

| 字段 | 值 | 状态 |
|---|---|---|
| gremote 构建源 commit | `7bd1cdf` | pass |
| APK 文件名 | `gremote-0.1.0+1-arm64-debug-20261009-210913.apk` | pass |
| APK SHA-256 | `c8b37422c4a5ceb8c02133710c6fd7cca0f597c8902c76458a31530d51f3c1f5` | pass |
| HyperOS 版本 | `not-recorded` | not-run |
| Android build | `not-recorded` | not-run |
| GR III BLE 固件值 | `not-recorded` | not-run |

状态只允许填写：`pass`、`fail`、`unsupported`、`not-run`。

## 自动化软件门禁

| 检查项 | 证据 | 状态 |
|---|---|---|
| `flutter analyze` | No issues found | pass |
| `flutter test` | 246 tests passed | pass |
| Android arm64 debug build | assembleDebug succeeded | pass |
| APK/Git 敏感文件扫描 | 未发现固件、密钥或私密测试值 | pass |
| Android 集成测试 | 当前未连接 Android 设备 | not-run |

## BLE 与重连

| 检查项 | 证据 | 状态 |
|---|---|---|
| 扫描名称为 RICOH 相机 | `not-recorded` | not-run |
| 广播包含已知服务 UUID | `not-recorded` | not-run |
| 系统配对提示可完成 | `not-recorded` | not-run |
| 强制停止 App 后可重连 | `not-recorded` | not-run |
| Model 原始字节长度 | `not-recorded` | not-run |
| Firmware 原始字节长度 | `not-recorded` | not-run |
| Battery 原始字节长度 | `not-recorded` | not-run |
| SSID 原始字节长度 | `not-recorded` | not-run |
| Passphrase 原始字节长度 | `not-recorded` | not-run |
| Battery 通知 | `not-recorded` | not-run |
| Capture Status 通知 | `not-recorded` | not-run |

只记录地址是否稳定及脱敏后缀，不记录完整 BLE 地址；只记录凭证长度，不记录内容。

## Wi‑Fi 与 HTTP

| 检查项 | 证据 | 状态 |
|---|---|---|
| BLE 开启 AP 耗时（ms） | `not-recorded` | not-run |
| 系统 Wi‑Fi 同意弹窗行为 | `not-recorded` | not-run |
| 成功相机 IP | `not-recorded` | not-run |
| `/v1/ping` HTTP 状态 | `not-recorded` | not-run |
| `/v1/ping` JSON 键名 | `not-recorded` | not-run |
| `/v1/props` HTTP 状态 | `not-recorded` | not-run |
| `/v1/props` JSON 键名 | `not-recorded` | not-run |
| 相机流量绑定专用 Network | `not-recorded` | not-run |
| 蜂窝网络同时可用 | `not-recorded` | not-run |
| App 后台再回前台 | `not-recorded` | not-run |

JSON 只记录键名和字段类型，不复制响应值或 body。

## Live View 与快门

| 检查项 | 证据 | 状态 |
|---|---|---|
| multipart boundary 实际值 | `not-recorded` | not-run |
| 首帧分辨率 | `not-recorded` | not-run |
| 平均 FPS | `not-recorded` | not-run |
| 5 分钟温度/断连 | `not-recorded` | not-run |
| 15 分钟温度/断连 | `not-recorded` | not-run |
| 30 分钟温度/断连 | `not-recorded` | not-run |
| BLE AF 快门按下/释放 | `not-recorded` | not-run |
| HTTP 快门回退 | `not-recorded` | not-run |
| 竖屏进入与横屏返回 | `not-recorded` | not-run |

## 遥控参数、程序拍摄与配方

| 检查项 | 证据 | 状态 |
|---|---|---|
| 协议探测页只读报告完成且无敏感值 | `not-recorded` | not-run |
| query / form / JSON 写入格式结果 | `not-recorded` | not-run |
| `/v1/changes` 握手、消息与断线重连 | `not-recorded` | not-run |
| WebSocket 不可用时 1 秒轮询 | `not-recorded` | not-run |
| av/tv/sv/xv 写入后回读一致 | `not-recorded` | not-run |
| WB、测光、对焦设置、effect 写入 | `not-recorded` | not-run |
| 原生包围、间隔与自拍模式 | `not-recorded` | not-run |
| 自定义包围 5 张顺序 `0,-,+,-2,+2` | `not-recorded` | not-run |
| 配方包围逐张 effect 与文件标记 | `not-recorded` | not-run |
| 计划渐变先延长快门、到上限后提 ISO | `not-recorded` | not-run |
| 测光渐变死区与每帧 1/3 EV 上限 | `not-recorded` | not-run |
| 后台、断连、过热时程序暂停 | `not-recorded` | not-run |
| 程序结束/中止恢复原相机参数 | `not-recorded` | not-run |
| 暗屏与程序期间屏幕常亮 | `not-recorded` | not-run |
| 组合配方切换、脱离检测与图库角标 | `not-recorded` | not-run |
| RAW+JPEG 合并为一条 CaptureRecord | `not-recorded` | not-run |
| 文件名 + 相机时间 ±2 秒强匹配 | `not-recorded` | not-run |
| phone 时间弱匹配需人工确认 | `not-recorded` | not-run |
| 按配方导出使用每张照片对应方案 | `not-recorded` | not-run |

Gate 1 不得把固件静态推导项改成 `pass`；只有连接真机并记录脱敏证据后才能更新。

## 诊断导出

| 检查项 | 证据 | 状态 |
|---|---|---|
| 导出 schema 为 `gremote-diagnostics/1` | `not-recorded` | not-run |
| SSID 与密码已脱敏 | `not-recorded` | not-run |
| BLE 地址与序列号已脱敏 | `not-recorded` | not-run |
| 路径、GPS 与 HTTP body 已脱敏 | `not-recorded` | not-run |
| 诊断 JSON SHA-256 | `not-recorded` | not-run |

## Gate 结论

- 结论：`not-run`
- 已接受的 unsupported 项：`none`
- 阻塞缺陷：`none-recorded`
- 测试人：`not-recorded`
- 测试时间：`not-recorded`
