# LAB-062 — Solution

## Summary

Educational intent: network engineers read Python as they read a config (types, loops, branches, exceptions), run it from a pinned venv, and judge an AI-proposed script on evidence. Libraries: `requests` (RESTCONF), `ncclient` (NETCONF), `netmiko` (SSH, `cisco_ios` for iol-xe, `cisco_xe` for cat8000v). Blueprint: 6.1:I (Python: reading, running, modifying, reviewing), 6.5:R (RESTCONF codes and Catalyst Center response/task patterns reinforced). No intentional faults; the one audit finding is RTR1 `logging buffered 8192`.

Start state = stage A1 + RTR1 `logging buffered 8192` + `/home/cisco/auto/` on AUTO-MGMT1 (no venv). End state = stage A2 (`environments/AUTO/A2/README.md`).

Build-time design decisions (teaching): (1) credentials hard-coded at the top of each script (Q6); (2) `rc_get.py` as shipped catches connection errors (exit 2) but not HTTP 4xx/5xx, so a bad path ends in a `KeyError` traceback (motivates R3); (3) `audit.py` accepts `ntp server` OR `ntp master` as a time source, because RTR1 is the pod clock source and has no `ntp server`; (4) audit exit codes 0 clean / 1 findings / 2 device unreadable; (5) the final Catalyst Center task poll says "completed on 4 of 5 devices" with no `isError`, so a script that only stops on `endTime` misses a partial result (Q5); (6) **R4 and locking:** RESTCONF `lock-denied` (409) is not reproducible on 17.16.1a; the measured behaviour is that a held NETCONF `<lock>` makes a RESTCONF write block, so `set_desc.py` retries on `ReadTimeout` and on 409 with back-off. The 409 branch itself was never exercised on this platform.

## Intentional Faults

None (I lab). Documented finding the audit must detect: AUTO-RTR1 `logging buffered 8192` (standard: at least 64000).

## Diagnosis / Methodology

Reading method for R2 (predictions the student should reach, then the real output below under Verification):
- `rc_get.py`: one HTTPS GET (`verify=` the pinned PEM), status 200, `.json()` gives a dict; `data["ietf-interfaces:interfaces"]["interface"]` is a list of 6 dicts (Gi1-Gi4, Lo0, Lo101); the loop prints 6 lines, `"description" in itf` is the branch; only Gi1 has one at the start (type of `itf["name"]` is str, `described` int).
- `nc_get.py`: NETCONF session id (int, differs each run), two `get_config` subtree filters, hostname `AUTO-RTR3`, 6 names; the `hostkey_verify=False` is the trust difference from `rc_get.py`.
- `show_cmds.py`: for each of two devices a prompt, then per command the output is one `str` (`type str`); the `"FULL" in output` branch prints the adjacency line, else the first 6 lines of the interface table; line counts include header lines. `find_prompt()` gives `AUTO-RTR1#` / `AUTO-RTR3#`.
- Typical prediction differences: students expect `send_command` to return a list or a dict (it is a string); expect Lo0 on RTR1 in the first six lines (the `| exclude unassigned` leaves 4 lines on RTR1 and 5 on RTR3); expect NETCONF `session id` fixed.

R6 audit review path: read `audit.py` (RTR1 via netmiko `show` commands, RTR3 via RESTCONF native model), then confirm each verdict on the router (`show ip ssh`, `show run | section line vty`, `show run | include ^ntp`, `show run | include logging buffered` on RTR1; RESTCONF/CLI on RTR3). Findings: the verdicts are right; RTR1 time source is `ntp master 3` and is accepted deliberately; RTR3 SSH v2 passes because the `native/ip/ssh` model has no version leaf on cat8000v 17.x (a verdict inferred from absence: state the assumption); style note: RTR3 reads `native/line` and then `native/line/vty` again (one redundant call, no wrong verdict). Verdict: **approve with notes** (redundant call, assumption about the absent leaf, hard-coded credentials, exit codes documented).

## Solution Configuration

R1 (venv; the apt step is needed because `python3.12-venv`/ensurepip is missing, measured 64 s with NAT):

```
sudo apt-get update
sudo apt-get install -y python3.12-venv
python3 -m venv /home/cisco/venv
/home/cisco/venv/bin/pip install requests==2.31.0 ncclient==0.7.1 netmiko==4.8.0
```

R3 `rc_get.py` changes (tested as `rc_get_fixed.py`): a `get_json(path)` helper that does the GET, and

```python
    if resp.status_code >= 400:
        print(f"ERROR {resp.status_code} for {path}: {resp.text[:100]}")
        sys.exit(1)
```

then the table loop printing `itf['name']`, `itf.get('enabled')` and the addresses from `itf.get("ietf-ip:ipv4", {}).get("address", [])` (`ip/netmask`). `raise_for_status()` inside a `try/except requests.exceptions.HTTPError` is an equally valid answer.

R4: `cd /home/cisco/auto; /home/cisco/venv/bin/python set_desc.py` twice; for the lock case remove the three descriptions on RTR3 (`interface Loopback0` / `no description`, same for Loopback101 and GigabitEthernet2), start `python /home/cisco/hold.py 40` in a second session, run `set_desc.py` at once.

R6 fix of AUTO-RTR1 with netmiko (own script):

```python
from netmiko import ConnectHandler
conn = ConnectHandler(device_type="cisco_ios", host="10.90.50.1", username="admin", password="Cisco123!")
out = conn.send_config_set(["logging buffered 64000"])
print(conn.send_command("show running-config | include ^logging buffered"))
conn.disconnect()
```

Second non-compliance and restore (RTR3 console): `no ntp server 10.255.90.1`, then `ntp server 10.255.90.1`.

## Verification

R1 / V1: `pip list` -> requests 2.31.0, ncclient 0.7.1, netmiko 4.8.0 (paramiko 5.0.0 pulled in by netmiko). Stage boot test: venv complete about 99 s after MGMT1 boot.

R2 / V2 (real output, venv python):

```
rc_get.py:   HTTP status: 200 / interfaces returned: 6 / GigabitEthernet1 AUTO-SW API segment / ... / with description: 1
nc_get.py:   session id: 43 / hostname: AUTO-RTR3 / interfaces: 6 / - GigabitEthernet1 ... Loopback101
show_cmds.py:
=== AUTO-RTR1# (cisco_ios) ===
--- show ip ospf neighbor: 3 lines, type str
    OSPF adjacency is FULL
--- show ip interface brief | exclude unassigned: 4 lines, type str
    Interface  IP-Address  OK? Method Status Protocol / Ethernet0/0 10.90.50.1 ... up up / Ethernet0/2 10.90.255.2 / Loopback0 10.255.90.1
=== AUTO-RTR3# (cisco_xe) ===
--- show ip ospf neighbor: 3 lines, type str / OSPF adjacency is FULL
--- show ip interface brief | exclude unassigned: 5 lines, type str (Gi1, Gi2, Lo0, Lo101)
```

(the `rc_get.py` description count is 4 after R4 has run.)

R3 / V3: fixed script:

```
interface             enabled  ipv4
GigabitEthernet1      True     10.90.50.11/255.255.255.0
GigabitEthernet2      True     10.90.255.3/255.255.255.254
GigabitEthernet3      False    -
GigabitEthernet4      False    -
Loopback0             True     10.255.90.11/255.255.255.255
Loopback101           True     10.255.90.101/255.255.255.255
rc=0
$ python rc_get_fixed.py ietf-interfaces:interfaces/interface=Loopback999
ERROR 404 for ietf-interfaces:interfaces/interface=Loopback999: {  "ietf-restconf:errors": { "error": [ ...
rc=1
```

The shipped `rc_get.py` against a wrong container name ends in `KeyError: 'ietf-interfaces:interfacesX'` (traceback, no status shown).

R4 / V4: first run (clean state) three `204 on attempt 1`; second run the same (idempotent PATCH, no DMI change log). **Lock case (measured, fresh import, MGMT1 clock):**

```
15:08:49 start (hold.py 40 had started ~3 s earlier: "lock held for 40 s")
Loopback0: no answer in 10 s on attempt 1, waiting 5 s
Loopback0: no answer in 10 s on attempt 2, waiting 10 s
Loopback0: 204 on attempt 3
Loopback101: 204 on attempt 1
GigabitEthernet2: 204 on attempt 1
failures: 0          rc=0
15:09:30 end ("lock released")
```

RTR3 `%DMI-5-CONFIG_I: Configured from NETCONF/RESTCONF by apiuser, transaction-id 73` at 15:09:29, right when the lock ended: the blocked PATCH was applied after the release (RTR logs UTC = MGMT1 clock here). Earlier on the build lab: a lock held 25 s made one PATCH take 25 s (`timeout=30`: 204 on attempt 1); a lock held 50 s with the old timeout 30 raised an unhandled `ReadTimeout`. No `409`/`lock-denied` appeared in about 50 writes (rapid fire, 3 parallel processes x 8 PATCH, CLI changes immediately before, `shutdown`, NTP re-add), so the 409 branch is code the student reads, not output.

R5 / V5 (`catc_inventory.py`): five devices, one "Ping Reachable"/"Partial Collection Failure", one Unreachable; `not reachable: BR1-RTR1, BR2-ACC1`; `accepted: taskId 6c0b1f7e-... url /api/v1/task/6c0b1f7e-...`; `poll: running, progress: Executing template deployment`; `poll: finished, progress: Deployment completed on 4 of 5 devices` (derived fixtures: no Catalyst Center in the pod).

R6 / V6: `audit.py` start state (read twice, with other SSH sessions to both routers in between: identical):

```
== AUTO-RTR1 ==
  PASS  SSH version 2 (SSH Enabled - version 2.0)
  PASS  VTY transport ssh only (transport input ssh)
  PASS  time source configured (ntp master 3)
  FAIL  logging buffered >= 64000 (size 8192)
== AUTO-RTR3 ==
  PASS  SSH version 2 (version leaf absent)
  PASS  VTY transport ssh only (1 vty range(s))
  PASS  time source configured (1 ntp server(s))
  PASS  logging buffered >= 64000 (size 64000)
findings: 1, errors: 0       rc=1
```

RTR3 `no ntp server 10.255.90.1` -> `FAIL time source configured (0 ntp server(s))`, findings 2; restored -> findings 1. After the netmiko fix (`send_config_set` returns the echo text ending `AUTO-RTR1(config)#end` / `AUTO-RTR1#`, no status) `show run` shows 64000 and `audit.py` -> `findings: 0, errors: 0`, rc 0.

V7: RTR3 `%SSH-5-SSH2_USERAUTH: User 'apiuser' ... from 10.90.50.31` for NETCONF sessions, `%DMI-5-AUTH_PASSED: User 'apiuser' authenticated successfully from 10.90.50.31 ... for rest over http` per RESTCONF request and `for netconf over ssh` (15:08:47) for the lock helper; `%DMI-5-CONFIG_I ... transaction-id N` per changing write; RTR1 `%SSH-5-SSH2_USERAUTH: User 'admin' ... from 10.90.50.31` per netmiko connection (two per `audit.py`).

## Failure / Recovery Behaviour

Failure method: RTR3 **node stop** (silent failure for RTR1 and MGMT1; `write memory` first).

| Scenario (trigger -> end condition) | Runs | Documented range | Basis |
|---|---|---|---|
| `audit.py` with RTR3 stopped -> script exits | 1 run: RTR1 block PASS/FAIL printed, `ERROR ConnectionError: HTTPSConnectionPool(host='rtr3...' Max retries exceeded`, `findings: 0, errors: 1`, exit 2, 18 s | 15-30 s | ARP/connect failure on the unreachable address; single run, bound by the 30 s request timeout |
| `node start` RTR3 -> first RESTCONF 200 (`curl -k`) | 357, 349, 344 s (polled every 10 s) | 330-400 s typical (other runs: 336 and 392 s); a loaded server can take far longer (one 903 s outlier while other labs ran), so poll | cat8000v boot plus DMI start (000, then 502, then 200) |
| `set_desc.py` PATCH with NETCONF lock held 40 s -> exit 0 | 1 run: 41 s, 204 on attempt 3 (attempts at 0, 15, 35 s; third blocks until release) | 35-45 s for a 40 s lock | TIMEOUT 10, back-off 5 and 10 s, then blocked until release; plus 25 s lock -> 25 s block (build lab) |

**Certificate changes on every RTR3 reload** (also after `write memory`): the pinned `/home/cisco/trust/rtr3.pem` then fails (`curl --cacert` exit 60 / `SSLError`; `audit.py` shows `ERROR SSLError` for RTR3 and exits 2) until the PEM is fetched again. Recovery: re-fetch the certificate the router presents into `rtr3.pem` (for example `openssl s_client -connect 10.90.50.11:443 </dev/null | openssl x509 > /home/cisco/trust/rtr3.pem`), or wipe and restart MGMT1 so the bootstrap runs again. This is the point of Q1.

## Answers to Analysis Questions

- **Q1** `verify=<PEM>` makes TLS check that the server presents that exact (self-signed) certificate and that the name `rtr3.auto.veridian.example` matches its SAN, so a man in the middle or another host with another certificate is rejected; `verify=False` accepts anything and silences the warning. The price: after RTR3 reloads it presents a new self-signed certificate, the pinned PEM no longer matches and the script fails with `SSLError` (measured) until the PEM is refreshed; production uses a CA-signed certificate and a CA bundle. On this pod the certificate is regenerated at every reload or boot (measured); in general a pinned self-signed certificate breaks whenever the key pair or certificate is regenerated or renewed, which is why production pins a CA, not a leaf.
- **Q2** `send_config_set` types the commands into the CLI and returns the terminal text, because SSH has no structured result; the device reports errors as text (`% Invalid input`). The script must inspect that text and then read back the state (`show run | include ...`), as the R6 fix does, rather than assume success.
- **Q3** RESTCONF/NETCONF when the device has a YANG API: structured data, validation, (NETCONF) transactions and locks, idempotent merge/replace; RESTCONF for single objects over HTTP tooling, NETCONF for multi-step transactions or `candidate`. SSH screen-scraping for devices without an API or for operational `show` output (the iol-xe RTR1 here), accepting that text parsing is brittle.
- **Q4** Correct = right verdicts on all inputs, including the student's added non-compliance and the `ntp master` case; efficient = fewer calls. The redundant `native/line` then `native/line/vty` GET costs one request and changes no verdict: a note. The assumption to ask for: RTR3 SSH v2 is inferred from an absent version leaf; also hard-coded credentials and the choice to accept `ntp master`. Verdict: approve with notes.
- **Q5** Catalyst Center answers a change with 202 plus a `taskId`/`url`; the script must poll the task until it finishes and then read the result (here "4 of 5 devices": a partial result with no error flag). RESTCONF answers 201/204 when the change is committed, so the status code is the result (with the DMI commit, a write may take a second or block on a lock).
- **Q6** In plain text at the top of each script (and in the sample CSV-free code), visible to anyone with read access and in history. Before production: read from the environment or a secrets store/vault, use per-script service accounts with least privilege, a CA-signed certificate, and no passwords in files or command lines.
- **Q7** The RESTCONF PATCH did not get an error: it blocked until the lock was released (no 409 was observed). With a client timeout shorter than the lock, `requests` raises `ReadTimeout`; `set_desc.py` catches it, waits 5 then 10 s (back-off) and tries again; the third attempt landed just after the release, so the run ended with three 204 and the change appeared on the router (DMI log) at the release. A script that handled only status codes would have crashed with a traceback.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-17 |
| CML | 2.10.0 |
| Node types | cat8000v (IOS XE 17.16.1a), external_connector, iol-xe (IOS XE 17.16.1a), ubuntu (Ubuntu 24.04), unmanaged_switch |
