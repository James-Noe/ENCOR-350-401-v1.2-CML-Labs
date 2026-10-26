"""Add SDW-MGMT1 (ubuntu, 172.16.0.50/24) to the csdwan-built lab on a free VPN0 port.

Run (CML_URL/CML_USERNAME/CML_PASSWORD set; lab title in SDWAN_LAB):
  SDWAN_LAB="ENCOR LAB-073 SD-WAN Pilot" PY=$(uv tool dir)/catalyst-sdwan-lab/bin/python
  $PY scripts/add_mgmt.py
Static network-config, no NAT, no DHCP. Cloud-init writes /home/cisco/sdwan/README.txt and report/.
"""
import os
import sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "..", "..", "..", "tools", "sdwan"))
from common import cml, find_lab

README = """Veridian SD-WAN pilot - API host
Manager API base URL: https://172.16.0.1/dataservice  (self-signed certificate)
Session login: POST https://172.16.0.1/j_security_check  (form j_username, j_password)
Write your results under /home/cisco/sdwan/report/
"""
import base64
USER_DATA = """#cloud-config
hostname: sdw-mgmt1
password: cisco
chpasswd: { expire: False }
ssh_pwauth: True
system_info:
  default_user:
    name: cisco
manage_etc_hosts: True
write_files:
  - path: /home/cisco/sdwan/README.txt
    permissions: '0644'
    encoding: b64
    content: %s
runcmd:
  - mkdir -p /home/cisco/sdwan/report
  - chown -R cisco:cisco /home/cisco/sdwan
""" % base64.b64encode(README.encode()).decode()
NET = """network:
  version: 2
  ethernets:
    ens2:
      addresses: [172.16.0.50/24]
"""

c = cml()
lab = find_lab(c)
if any(n.label == "SDW-MGMT1" for n in lab.nodes()):
    raise SystemExit("SDW-MGMT1 already present")
vpn0 = lab.get_node_by_label("VPN0")
used = {i.label for i in vpn0.interfaces() if i.connected}
print("VPN0 used ports:", sorted(used))
n = lab.create_node("SDW-MGMT1", "ubuntu", 0, 0)
n.configuration = [{"name": "user-data", "content": USER_DATA},
                   {"name": "network-config", "content": NET}]
free = [i for i in vpn0.interfaces() if not i.connected]
print("free VPN0 ports:", [i.label for i in free])
a = n.create_interface(slot=0) if not n.interfaces() else n.interfaces()[0]
lab.create_link(a, free[0])
print("linked SDW-MGMT1 to VPN0", free[0].label)
n.start()
