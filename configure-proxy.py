#!/usr/bin/env python3
import datetime
import json
import os
from pathlib import Path
import secrets
import subprocess
import uuid

root = Path('/etc/private-proxy')
root.mkdir(mode=0o700, exist_ok=True)
credentials_path = root / 'credentials.json'
if credentials_path.exists():
    credentials = json.loads(credentials_path.read_text())
else:
    keypair = subprocess.check_output(['sing-box', 'generate', 'reality-keypair'], text=True)
    keys = dict(line.split(':', 1) for line in keypair.splitlines() if ':' in line)
    credentials = {'private_key': keys['PrivateKey'].strip(), 'public_key': keys['PublicKey'].strip(), 'short_id': secrets.token_hex(4), 'users': {name: str(uuid.uuid4()) for name in ['windows', 'mobile']}}
    credentials_path.write_text(json.dumps(credentials, indent=2) + '\n')
    os.chmod(credentials_path, 0o600)

config = {
    'log': {'level': 'info', 'timestamp': True},
    'inbounds': [{
        'type': 'vless', 'tag': 'private-reality', 'listen': '0.0.0.0', 'listen_port': 443,
        'users': [{'name': n, 'uuid': u, 'flow': 'xtls-rprx-vision'} for n, u in credentials['users'].items()],
        'tls': {'enabled': True, 'server_name': 'www.microsoft.com', 'reality': {'enabled': True, 'handshake': {'server': 'www.microsoft.com', 'server_port': 443}, 'private_key': credentials['private_key'], 'short_id': [credentials['short_id']]}}
    }],
    'outbounds': [{'type': 'direct', 'tag': 'direct'}],
    'route': {'rules': [{'ip_is_private': True, 'action': 'reject'}], 'final': 'direct'}
}
Path('/etc/sing-box/config.json').write_text(json.dumps(config, indent=2) + '\n')
os.chmod('/etc/sing-box/config.json', 0o600)
limits = root / 'limits.json'
if not limits.exists():
    stop_date = datetime.date.fromisoformat(os.environ['STOP_ON_UTC_DATE'])
    monthly_tx_gib = int(os.environ.get('MONTHLY_TX_GIB', '150'))
    if stop_date <= datetime.datetime.now(datetime.timezone.utc).date() or monthly_tx_gib <= 0:
        raise ValueError('Set a future UTC stop date and a positive monthly TX limit')
    limits.write_text(json.dumps({'monthly_tx_gib': monthly_tx_gib, 'stop_on_utc_date': stop_date.isoformat()}, indent=2) + '\n')
subprocess.run(['sing-box', 'check', '-c', '/etc/sing-box/config.json'], check=True)
print('Proxy configuration validated; credentials saved privately.')
