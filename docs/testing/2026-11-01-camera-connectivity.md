# GR III 手机连接只读诊断 · 2026-11-01

经用户授权通过 USB/ADB 调试 Android 手机。安装包版本1.1.0、versionCode5。

- 手机 Wi-Fi 已关联相机热点，wlan0 有192.168.0.0/24直连路由。
- 从手机显式经 wlan0、关闭代理，GET http://192.168.0.1/v1/props 返回 HTTP200。仅记录脱敏字段：model=RICOH GR III、firmwareVersion=2.10。
- 相同路径下访问 TCP18743 /m10v/v1/capabilities，连接失败（curl exit7），没有获得HTTP/能力响应。只能证明服务当前不可达，不能据此确认未安装或实际构建身份。
- 既有隔离候选的 target/owner getter unavailable，服务生成配置wifi_verified=0、能力默认false，不能靠导入配对文件使其获得真实写入能力。
- 最新远端M10V main=a24ccc2618aff06baf9359808120ce6a4e881ab0；现有App的五槽旧合同需适配最新十槽和能力描述。机身2.10版本号不足以标识M10V扩展构建。

未调用相机POST/PUT/DELETE、对焦、快门、格式化或配置写入；未刷机、安装App或导入配对密钥。本记录不包含Wi-Fi凭据、设备序列号、MAC、GPS或照片内容。

下一步：对照实际固件产物/安装回执确定相机端构建；以最新main建立独立适配，先验证扩展只读能力，再完成一个设置的提交、读回、机身核对及菜单反向同步。禁止只放开App按钮冒充支持。
