# GR III 2.10 原厂协议证据

## 证据范围

- 固件输入：`fwdc239b.bin`
- SHA-256：`d6a3c9c288d784080e7b283222ecdd8752adfeed6faa36dab44f73115354bfd4`
- 固件内证据：INITFS 的 `bled`、`webapid` 和 `libcamera-controller.so`
- 交叉参考：`dm-zharov/ricoh-gr-bluetooth-api`
- 当前状态：GR III 2.10 + 小米 14 已验证 BLE 配对、自动 Wi-Fi、手动 Wi-Fi 及基础 HTTP 探测；其余接口按下文标注

状态定义：

- `firmware-confirmed`：官方固件中存在对应服务、字符串或 UUID；
- `hardware-unverified`：编码来自静态逆向或公开交叉参考，尚未读取用户相机；
- `hardware-verified`：已在 GR III 2.10 上记录实测结果。

## BLE GATT

| Service | Characteristic | UUID | 属性 | 格式 | 状态 |
|---|---|---|---|---|---|
| Camera Information | Model | `35FE6272-6AA5-44D9-88E1-F09427F51A71` | R | UTF-8 | firmware-confirmed / hardware-unverified |
| Camera Information | Firmware | `B4EB8905-7411-40A6-A367-2834C2157EA7` | R | UTF-8 | firmware-confirmed / hardware-unverified |
| Camera | Power | `B58CE84C-0666-4DE9-BEC8-2D27B27B3211` | R/W/N | uint8 | firmware-confirmed / hardware-unverified |
| Camera | Battery | `875FC41D-4980-434C-A653-FD4A4D4410C4` | R/N | GR III 2.10 实测为单字节电量值；兼容双字节 `[level, source]` | hardware-verified (单字节) |
| Camera | Operation Mode | `1452335A-EC7F-4877-B8AB-0F72E18BB295` | R/W/N | uint8 | firmware-confirmed / hardware-unverified |
| WLAN | Network Type | `9111CDD0-9F01-45C4-A2D4-E09E8FB0424D` | R/W/N | uint8 | firmware-confirmed / hardware-unverified |
| WLAN | SSID | `90638E5A-E77D-409D-B550-78F7E1CA5AB4` | R/W | UTF-8 | firmware-confirmed / hardware-unverified |
| WLAN | Passphrase | `0F38279C-FE9E-461B-8596-81287E8C9A81` | R/W | UTF-8 | firmware-confirmed / hardware-unverified |
| Shooting | Operation Request | `559644B8-E0BC-4011-929B-5CF9199851E7` | W | 2 bytes | firmware-confirmed / hardware-unverified |
| Shooting | Capture Status | `B5589C08-B5FD-46F5-BE7D-AB1B8C074CAA` | R/N | structured bytes | firmware-confirmed / hardware-unverified |

服务 UUID：

- Camera Information：`9A5ED1C5-74CC-4C50-B5B6-66A48E7CCFF1`
- Camera：`4B445988-CAA0-4DD3-941D-37B4F52ACA86`
- WLAN：`F37F568F-9071-445D-A938-5441F2E82399`
- Shooting：`9F00F387-8345-4BBC-8B92-B87B52E3091A`

操作编码：Camera Power 为 `0=off, 1=on, 2=sleep`；Network Type 为 `0=off, 1=AP`；Operation Request 为 `[operationCode, parameter]`，其中 `1=start, 2=stop, 0=no AF, 1=AF`。

## Wi-Fi HTTP

固件 `webapid` 已确认以下路由，具体 JSON 字段与相机 IP 等待 Gate 1 真机报告：

- `GET /v1/ping`
- `GET /v1/props`
- `GET /v1/liveview`
- `GET /v1/changes`（WebSocket）
- `GET /v1/debug/revisions`
- `PUT /v1/params/camera`
- `PUT /v1/params/lens`
- `PUT /v1/params/device`
- `POST /v1/lens/focus`
- `POST /v1/camera/shoot`
- `POST /v1/camera/shoot/cancel`
- `GET /v1/photos`
- `GET /v1/photos/{dir}/{file}`
- `GET /v1/photos/{dir}/{file}/info`
- `PUT /v1/photos/{dir}/{file}/transfer`

Live View 的静态证据为 `multipart/x-mixed-replace; boundary=--boundary`，帧类型为 `image/jpeg`。固件中未发现 HTTP `Range` 或 `Content-Range` 字符串。

## 小米 14 / 澎湃 OS 3 真机记录（2026-10-10）

- 首次连接出现 Android 系统 PIN 配对弹窗；确认后 GATT 连接、MTU 协商和服务发现成功。
- BLE 已读取 GR III 型号、固件 `2.10`、SSID 和密码。电池特征实际返回 `0x64`，长度为 1 字节，代表 100%；原先固定要求 2 字节会报 `invalidPayload`。
- 补齐 Android `CHANGE_NETWORK_STATE` 后，应用可申请并绑定相机无互联网 Wi-Fi；将 HTTP 响应体读取移出主线程后，`/v1/ping` 与 `/v1/props` 探测通过，首页显示 ready。
- 手动 Wi-Fi 入口已在同一真机上完成连接，`/v1/ping` 与 `/v1/props` 可用。首次真机操作暴露了弹窗退出时提前释放输入框的错误，已修复。
- Wi-Fi 模式优先读取 `/v1/props` 中的 `firmwareVersion` 与 `battery`；若相机未提供，界面明确显示未读取，不把缺失信息伪装成 `0%`。
- 此记录证明该机上的两条连接路径与基础 HTTP 探测；Live View 和遥控拍摄仍需各自验证。

### 请求参数（firmware-derived / hardware-unverified）

- `webapid` 含 `ParseKeyValuesString`，参数以 `key=value` 形式解析；gremote 先以 query string 发送，Gate 1 记录相机是否也接受表单 body。
- `/v1/camera/shoot` 参数键为 `af`；gremote 自动对焦使用社区实测值 `af=camera`，非自动对焦暂用 `af=off`，需真机确认。
- `/v1/lens/focus` 参数键为 `pos`，`focus_pos::GetFromKeyValues` 解析为整数二元组，日志格式为 `Focus : pos({}, {})`；gremote 发送 `pos=x,y`，其中 x/y 为 0–100 的画面百分比，坐标单位需真机确认。
- 参数键（均为 `firmware-confirmed / hardware-unverified`）：`av/avList`、`tv/tvList`、`sv/svList`、`xv/xvList`、`WBMode/WBModeList`、`exposureMode/exposureModeList`、`meteringMode/meteringModeList`、`focusSetting/focusSettingList`、`effect/effectList`、`shootMode/shootModeList`、`captureMode/captureModeList`、`aspectRatio/aspectRatioList`、`stillFormat/stillFormatList`、`stillSize/stillSizeList`、`movieSize/movieSizeList`。
- 状态与文件键（均为 `firmware-confirmed / hardware-unverified`）：`storages/remain`、`hot`、`battery`、`captureId`、`liveState`、`state/stateStill/stateMovie`、`focused`、`dir/dirs/file/files`、`thumb/xs/full`。
- 参数写入格式仍需真机探测；App 按 query → form → JSON 顺序探测并把结果按固件版本保存。`/v1/changes` 按 WebSocket 实现，连续三次握手失败后仅在拍摄页前台轮询 `/v1/props`。
- 响应头写入 `Content-Type: application/json`；错误字段 `errCode`、`errMsg` 由 App 保留，响应原文不进入异常文本。
- Live View 解析同时接受 `--boundary` 和 RFC 派生的 `----boundary` 分隔行。
