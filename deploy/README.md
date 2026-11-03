# GRemote 宝塔静态站点

源码 `website/`；站点 `/www/wwwroot/gremote/current`；版本 `/www/wwwroot/gremote/releases/<完整SHA>`。

`publish_site.py` 先校验白名单、完整性、路径、大小和重复成员，拒绝链接，然后写入新目录并原子切换 current。previous 保留上一版；版本目录不覆盖；部署与回滚共享非阻塞文件锁。

服务器初始化：从已核验的代码目录执行 `sudo bash deploy/install-server.sh /path/to/dedicated-key.pub`，仅安装脚本与受限公钥，不改写 Nginx 或其他项目授权。

服务器安装：root 持有 `/usr/local/lib/gremote-deploy/publish_site.py` 与 `receive_ssh.py`，部署密钥仅绑定 `restrict,command="/usr/bin/python3 /usr/local/lib/gremote-deploy/receive_ssh.py"`。拒绝 shell、转发及任意命令。不得复用 M10V 发布密钥。

`Deploy GRemote website` 支持以下入口：

- 向 `develop` 推送，并且变更包含 `website/**`、`deploy/**`、`.github/workflows/deploy-website.yml` 或 `tests/test_site_deploy.py` 时，自动测试并发布对应提交。
- 推送 `site-*` 标签，保留显式发布入口。GitHub 的路径筛选不限制标签推送。
- 手动触发 workflow，选择 `develop`；其他普通分支由 job 条件拒绝。

只修改 App 源码、APK 版本或 App 发布说明的 `develop` 推送不触发官网部署。混合提交只要包含上述官网路径，就会部署该提交中的官网。

需要 Secret `GREMOTE_DEPLOY_SSH_KEY`、变量 `GREMOTE_DEPLOY_HOST` 与 `GREMOTE_DEPLOY_KNOWN_HOSTS`。继续使用现有受限 SSH 入口与独立密钥，无需更换密钥。部署成功须同时看到本次 SHA 的 `DEPLOY_OK`、Actions 终态成功，以及公网 HTTPS `version.json` 的提交一致。并发发布串行执行，不取消正在发布的版本。

归档仅包含以下普通文件，不含目录项或版本文件（version.json 由服务器生成）：

```sh
COPYFILE_DISABLE=1 tar -czf /tmp/gremote-site.tar.gz -C website index.html style.css app.js releases.json assets/street.jpg assets/camera.png assets/editorial.ttf assets/icon.png assets/OFL.txt assets/brand.png assets/editor-sample.jpg assets/film-33.png assets/film-66.png assets/film-70.png assets/film-71.png
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


2026-11-04：批准的官网视觉稿与 Android v1.2.0 下载入口已发布，提交 `d5afa3f219125b7d997581d1a391ecc2a9499f6d`。

- [Actions 41669541915](https://github.com/zhaoo/gremote/actions/runs/41669541915) 终态成功；公网 [version.json](https://gremote.izhaoo.com/version.json) 精确返回上述 SHA。
- 实际公网浏览器检查覆盖 1440px 桌面、390px 手机与 320px 窄屏，无横向溢出或坏图；手机菜单、M10V 互链、功能页签与发布记录正常。
- v1.2.0 APK 下载实际返回 HTTP 200，文件大小 29,011,014 字节。网页检查不代表 APK 或相机真机验收。
- 上述成功记录发生在自动 `develop` 触发规则接入前；新规则需通过后续符合路径条件的 `develop` 推送验证 Actions 终态与公网 SHA。
