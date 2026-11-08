#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "$0")"
install -m 755 traffic-guard.py /usr/local/sbin/private-proxy-traffic
python3 configure-proxy.py
chown root:sing-box /etc/sing-box/config.json
chmod 640 /etc/sing-box/config.json
install -d /etc/systemd/system/sing-box.service.d
cat > /etc/systemd/system/sing-box.service.d/private-proxy.conf <<'UNIT'
[Service]
CapabilityBoundingSet=
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=
AmbientCapabilities=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=strict
ReadWritePaths=/var/lib/private-proxy
ExecCondition=+/usr/local/sbin/private-proxy-traffic --check-only
UNIT
cat > /etc/systemd/system/private-proxy-traffic.service <<'UNIT'
[Unit]
Description=Record proxy interface traffic and enforce the monthly limit
After=network-online.target
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/private-proxy-traffic
UNIT
cat > /etc/systemd/system/private-proxy-traffic.timer <<'UNIT'
[Unit]
Description=Check private proxy traffic every 30 seconds
[Timer]
OnBootSec=20
OnUnitActiveSec=30
AccuracySec=1
[Install]
WantedBy=timers.target
UNIT
systemctl daemon-reload
/usr/local/sbin/private-proxy-traffic --status
systemctl enable --now private-proxy-traffic.timer
systemctl enable --now sing-box
systemctl --no-pager --full status sing-box private-proxy-traffic.timer
