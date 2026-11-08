#!/usr/bin/env python3
"""Persist whole-interface hourly/daily traffic and stop the proxy at its TX cap."""
import datetime
import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path('/var/lib/private-proxy')
ROOT.mkdir(mode=0o700, parents=True, exist_ok=True)
lock = (ROOT / 'traffic.lock').open('a')
fcntl.flock(lock, fcntl.LOCK_EX)
state_path = ROOT / 'traffic.json'
config = json.loads(Path('/etc/private-proxy/limits.json').read_text())
now = datetime.datetime.now(datetime.timezone.utc)
month, day, hour = now.strftime('%Y-%m'), now.strftime('%Y-%m-%d'), now.strftime('%Y-%m-%dT%H:00Z')
interface = subprocess.check_output(['ip', '-j', 'route', 'show', 'default'], text=True)
interface = json.loads(interface)[0]['dev']
rx = int(Path(f'/sys/class/net/{interface}/statistics/rx_bytes').read_text())
tx = int(Path(f'/sys/class/net/{interface}/statistics/tx_bytes').read_text())
boot = Path('/proc/sys/kernel/random/boot_id').read_text().strip()
state = json.loads(state_path.read_text()) if state_path.exists() else {'months': {}, 'days': {}, 'hours': {}}
previous = state.get('last')
drx = max(0, rx - previous['rx']) if previous and previous['boot'] == boot else rx
dtx = max(0, tx - previous['tx']) if previous and previous['boot'] == boot else tx
for table, key in [('months', month), ('days', day), ('hours', hour)]:
    row = state[table].setdefault(key, {'rx': 0, 'tx': 0})
    row['rx'] += drx
    row['tx'] += dtx
state['last'] = {'boot': boot, 'rx': rx, 'tx': tx, 'interface': interface, 'time': now.isoformat()}
limit = int(config['monthly_tx_gib']) * 1024**3
expired = now.date().isoformat() >= config['stop_on_utc_date']
over = state['months'][month]['tx'] >= limit
state['blocked_reason'] = 'trial-expiry' if expired else 'monthly-tx-cap' if over else None
temp = state_path.with_suffix('.tmp')
temp.write_text(json.dumps(state, indent=2) + '\n')
os.chmod(temp, 0o600)
os.replace(temp, state_path)
if over or expired:
    if '--check-only' in sys.argv:
        print('Proxy start refused:', state['blocked_reason'])
        sys.exit(1)
    subprocess.run(['systemctl', 'stop', 'sing-box'], check=True)
    print('Proxy stopped:', state['blocked_reason'])
if '--status' in sys.argv:
    print(json.dumps({'utc_month': month, 'month': state['months'][month], 'today': state['days'][day], 'limit_tx_gib': config['monthly_tx_gib'], 'stop_on_utc_date': config['stop_on_utc_date'], 'blocked_reason': state['blocked_reason'], 'interface': interface}, indent=2))
