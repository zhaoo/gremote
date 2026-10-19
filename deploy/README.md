# GRemote 宝塔静态站点

源码 `website/`；站点 `/www/wwwroot/gremote/current`；版本 `/www/wwwroot/gremote/releases/<完整SHA>`。

`publish_site.py` 先校验白名单、完整性、路径、大小和重复成员，拒绝链接，然后写入新目录并原子切换 current。previous 保留上一版；版本目录不覆盖；部署与回滚共享非阻塞文件锁。

服务器初始化：从已核验的代码目录执行 `sudo bash deploy/install-server.sh /path/to/dedicated-key.pub`，仅安装脚本与受限公钥，不改写 Nginx 或其他项目授权。

服务器安装：root 持有 `/usr/local/lib/gremote-deploy/publish_site.py` 与 `receive_ssh.py`，部署密钥仅绑定 `restrict,command="/usr/bin/python3 /usr/local/lib/gremote-deploy/receive_ssh.py"`。拒绝 shell、转发及任意命令。不得复用 M10V 发布密钥。

GitHub 手动触发 `Deploy GRemote website`，选择 develop。需要 Secret `GREMOTE_DEPLOY_SSH_KEY`、变量 `GREMOTE_DEPLOY_HOST` 与 `GREMOTE_DEPLOY_KNOWN_HOSTS`。部署成功须同时看到本次 SHA 的 DEPLOY_OK 和公网 HTTPS version.json 一致。工作流尚不在默认分支时，在 develop 提交上创建并推送 `site-*` 标签触发发布；普通 develop 推送不发布，不修改默认分支。

归档仅包含以下普通文件，不含目录项或版本文件（version.json 由服务器生成）：

```sh
COPYFILE_DISABLE=1 tar -czf /tmp/gremote-site.tar.gz -C website index.html style.css app.js releases.json assets/street.jpg assets/camera.png assets/editorial.ttf assets/icon.png assets/OFL.txt
```

回滚：使用专用 SSH 密钥执行固定命令 `rollback`，或管理员 `sudo python3 /usr/local/lib/gremote-deploy/publish_site.py --rollback`。回查 version.json 并与 previous 对照。不要删除当前或 previous 引用的版本目录。

Nginx 初始配置在 nginx.conf；正式部署后单独配置 ACME、TLS 与续期。不能把 HTTP/内网检查当作 HTTPS 公网验收。修改前备份现有配置，`nginx -t` 成功后 reload，保留 M10V 站点。

## 当前 HTTPS

2026-10-19 DNS-01 手动签发，证书有效至 2027-01-17。公网 HTTPS 已验证。当前未配置 DNS 自动化续期，需要到期前重复 DNS 验证，不能依赖默认 certbot timer。命令：`sudo certbot certonly --manual --preferred-challenges dns -d gremote.izhaoo.com`；完成后先 `nginx -t` 再 reload。

## 已验证发布

2026-10-19：`site-2026.10.19.1` 发布提交 `eb5491b75f6fed735589f182f86bea1c9b57cf57`。

- [Actions 39205850137](https://github.com/zhaoo/gremote/actions/runs/39205850137) 成功；包含 8 项部署测试、准确 SHA 的 DEPLOY_OK 与公网 HTTPS version.json 核验。
- 专用密钥已安装；任意命令测试被受限入口拒绝。
- 实测回滚至前版 `5a82fc827a1dfde7980d16778ad490ccc8980b52`，再恢复当前版本。
- 用户完成域名加白后，正式 HTTPS 页面浏览器验收通过：1280px 桌面与 360px 手机均无横向溢出，图片、手机菜单、锚点及说明展开正常。
