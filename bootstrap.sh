#!/bin/bash
set -euo pipefail
exec > >(tee -a /var/log/private-proxy-bootstrap.log) 2>&1
if [ -f /var/lib/private-proxy-bootstrap.done ]; then exit 0; fi
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl python3 vnstat nftables
curl --fail --silent --show-error --location --retry 3 https://github.com/SagerNet/sing-box/releases/download/v1.14.3/sing-box_1.14.3_linux_amd64.deb -o /var/tmp/private-proxy-sing-box.deb
echo 'eb8a5f1f2643baf1a060d0b5f0d1d015e28b72afa446be2d180f366a5dde18b1  /var/tmp/private-proxy-sing-box.deb' | sha256sum -c -
dpkg -i /var/tmp/private-proxy-sing-box.deb
systemctl disable --now sing-box || true
systemctl enable --now vnstat
cat > /etc/sysctl.d/90-private-proxy.conf <<'SYSCTL'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
SYSCTL
sysctl --system
install -d -m 700 /var/lib/private-proxy
touch /var/lib/private-proxy-bootstrap.done
echo PRIVATE_PROXY_BOOTSTRAP_DONE
