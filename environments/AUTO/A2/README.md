# AUTO A2 stage (scripted change)

Proven by LAB-062.

Built by LAB-062. Topology, addressing and credentials as in `../A0/README.md`; certificate bootstrap as in `../A1/README.md`.

**Profile:** AUTO lite, 4 nodes counted (AUTO-MGMT1, AUTO-RTR1, AUTO-RTR3 cat8000v, AUTO-SW) plus the NAT connector (not counted).

**A2 = A1 + on AUTO-MGMT1:** `/home/cisco/auto/` (owned by `cisco`): `rc_get.py` (requests), `nc_get.py` (ncclient), `show_cmds.py` (netmiko, RTR1 `cisco_ios`, RTR3 `cisco_xe`), `set_desc.py` + `descriptions.csv` (RESTCONF PATCH), `audit.py` (compliance audit), `catc_inventory.py` + `fixtures/` (derived Catalyst Center responses), and a venv `/home/cisco/venv` with `requests==2.31.0 ncclient==0.7.1 netmiko==4.8.0` (paramiko 5.0.0 comes with netmiko). RTR1 and RTR3 day-0 files are A1's, byte for byte (RTR1 already has `logging buffered 64000`). LAB-062's own start state is A2 minus the venv and with RTR1 `logging buffered 8192`; a student who completes LAB-062 R1 and R6 is at A2.

Files: `AUTO-MGMT1.user-data` (A1's plus the `auto/` files, the chown line and the venv install), `AUTO-MGMT1.network-config` (= A1), `AUTO-RTR1.cfg` (= A1), `AUTO-RTR3.cfg` (= A1).

## Gotchas

- **/home/cisco ownership.** cloud-init `write_files` runs before the `cisco` user exists, so `/home/cisco` ends up root-owned (A1 still has this defect). The first `runcmd` entry is `chown cisco:cisco /home/cisco; chown -R cisco:cisco /home/cisco/auto`. Without it the student cannot create files or a venv.
- **venv timing and source.** `python3-venv` is not installed (ensurepip missing), so the venv `runcmd` runs in the background (`nohup`, log `/var/log/a2-venv.log`): `apt-get update` + `apt-get install python3.12-venv` over the NAT connector, then `python3 -m venv` and `pip install` of the pins, retried every 15 s until apt works. Measured: install chain 64 s; in a stage boot the venv was complete about 100 s after MGMT1 boot (242 s after lab start). It needs the Internet path; without NAT only `requests` (system python) exists, so `rc_get.py`, `set_desc.py` and `catc_inventory.py` run, while `nc_get.py`, `show_cmds.py` and `audit.py` need the venv.
- **Certificate timing.** `/home/cisco/trust/rtr3.pem` appears about 4-6 min after boot (A1 mechanism); until then `audit.py` shows `ERROR OSError ... rtr3.pem` for RTR3. After every RTR3 reload the router presents a NEW self-signed certificate (also after `write memory`), so a pinned `rtr3.pem` gives `SSLError` / curl exit 60 until it is fetched again (`/home/cisco/trust/fetch-rtr3-cert.sh`-style fetch, or wipe and restart MGMT1).
- **Locks.** A NETCONF `<lock>` on running held by another session makes a RESTCONF write block until the lock is released (no 409 was reproducible). `set_desc.py` therefore retries on `ReadTimeout` and on 409 with back-off.
- **set_desc.py version.** The `/home/cisco/auto/set_desc.py` entry is the final script from `LAB-062.yaml` (TIMEOUT 10, WAIT 5 x attempt, retry on ReadTimeout and 409).
- **Credentials.** `apiuser` / `Api#Pass2026` for RESTCONF/NETCONF, `admin` / `Cisco123!` for RTR1 netmiko, hard-coded at the top of the scripts (a LAB-062 analysis question).
- **RTR3 DMI.** Every change to RTR3's console line (some console automation makes one at each connect) triggers a DMI running-config sync; scripted writes at that moment can wait a few seconds.
