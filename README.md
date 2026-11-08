# GCP 私有代理

在 Compute Engine Debian 12（amd64）上运行 sing-box VLESS + REALITY + Vision，通过 TCP 443 接入。Windows 客户端提供本地 HTTP/SOCKS5 代理并可接管系统代理设置。

## 1. 创建服务器

准备已启用结算的 GCP 项目、具有创建 Compute Engine 资源权限的 gcloud 登录，以及 SSH 密钥对。在 Bash 中从仓库根目录执行。使用新项目或确认其中没有同名资源。默认创建独立 VPC、子网、防火墙、e2-micro 实例和 30 GB 系统盘。

```bash
gcloud auth login
ssh-keygen -t ed25519 -f ~/.ssh/gcp_private_proxy
printf 'proxyadmin:%s\n' "$(cat ~/.ssh/gcp_private_proxy.pub)" > ssh-keys.txt
export PROJECT=your-gcp-project
export REGION=us-west1 ZONE=us-west1-a
export ADMIN_SOURCE_RANGES=203.0.113.10/32  # 替换为自己的公网出口 IPv4 /32
bash create-resources.sh
```

从脚本输出的 networkInterfaces 获取公网地址。首次开机等待 `/var/log/private-proxy-bootstrap.log` 出现 `PRIVATE_PROXY_BOOTSTRAP_DONE`。公网地址为临时 IP，停机再启动后需重新查询。

## 2. 安装代理和流量保护

```bash
export PROXY_IP=your-instance-public-ip
scp -i ~/.ssh/gcp_private_proxy install-services.sh configure-proxy.py traffic-guard.py "proxyadmin@$PROXY_IP:~"
ssh -i ~/.ssh/gcp_private_proxy "proxyadmin@$PROXY_IP"
sudo env STOP_ON_UTC_DATE=YYYY-MM-DD MONTHLY_TX_GIB=150 bash ~/install-services.sh
```

将 YYYY-MM-DD 替换为计划停止日期（UTC）。首次安装时生成两套设备 UUID 和一套 REALITY 密钥。后续运行沿用现有凭证及限制，调整限制用 `sudoedit /etc/private-proxy/limits.json`。计数基于整台服务器网卡的 UTC 自然月出站量，每 30 秒检查。达到上限或日期时停止代理，VM、磁盘及 IP 的费用另行管理。新月份需要手动启动服务。

## 3. 配置客户端

通过 SSH 在服务器本地使用 `sudo cat /etc/private-proxy/credentials.json` 查看配置。客户端只需对应设备的 UUID、public_key 和 short_id，服务器 private_key 留在服务端。

- Windows 将 sing-box 1.14.3 Windows amd64 官方发行包解压到 `client/sing-box-1.14.3-windows-amd64/`。复制 `sing-box-windows.example.json` 为 `sing-box-windows.json`，替换四个占位符，双击 `Enable-GCP-Proxy.cmd`。Ctrl+C 正常停止。窗口被强制关闭后可双击 `Restore-Previous-Proxy.cmd`。仅开本地端口时使用 `powershell -ExecutionPolicy Bypass -File .\Start-GcpProxy.ps1 -NoSystemProxy`。遵循系统代理的应用经本地端口 17899 出站，其他应用可单独指定代理。
- 手机使用支持 REALITY 和 Vision 的客户端，用 mobile UUID 填写以下导入链接。是否使用 TUN 由客户端控制。

```text
vless://MOBILE_UUID@PROXY_IP:443?encryption=none&security=reality&sni=www.microsoft.com&fp=chrome&pbk=PUBLIC_KEY&sid=SHORT_ID&type=tcp&flow=xtls-rprx-vision#GCP
```

发行包见 [sing-box v1.14.3](https://github.com/SagerNet/sing-box/releases/tag/v1.14.3)。服务端 bootstrap 已内置包的 SHA-256 校验。

## 4. 验证、维护与清理

- Windows 代理验证用 `curl.exe -x http://127.0.0.1:17899 -I https://www.google.com/generate_204`，预期 HTTP 204。服务端用 `sudo journalctl -u sing-box -n 50 --no-pager` 确认设备标签。
- 服务状态和用量用 `sudo systemctl status sing-box private-proxy-traffic.timer`、`sudo /usr/local/sbin/private-proxy-traffic --status`、`sudo vnstat -d`。SSH 超时先核对公网出口 IP 和 SSH 防火墙规则。
- 可选数据盘脚本 `prepare-data-disk.sh` 适用于手动挂载到 VM、设备名为 private-proxy-data 的 200 GiB 专用盘。脚本会在空盘上创建 ext4，并在 `/srv/data` 创建目录。先核对磁盘身份再执行 `sudo bash prepare-data-disk.sh`。
- 停用后在 GCP 控制台删除专用实例、磁盘和防火墙规则，再删除子网和 VPC。检查是否仍有额外数据盘或保留的公网地址。
