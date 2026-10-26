# LAB-078 — Solution

## Summary

Cross-domain task plus a two-fault ticket (X/T, G1). The student builds a tenant service on a cat8000v using only NETCONF (objects in one locked transaction: VRF, loopback, ACL) and RESTCONF (attachments: subinterface, route), proves it from the customer's side and from API reads, then runs the automation team's job `aster_svc.py`. The job prints success for every step but publishes Loopback110 **without an address** (F1) and its SSH permit **behind the logged deny** (F2); the 2xx results and the job's oper-status check prove nothing about the intent. The student diagnoses from evidence, fixes both through the API and rewrites the job so that it is idempotent and verifies the intent itself.

Blueprint mapping: 4.6 (NETCONF/RESTCONF, R), 2.2.a (VRF, R), 6.2 (REST response codes, R), 6.5 (data models/automation, T), 5.2.a (extended ACL, T).

Platform facts (measured on 17.16.1a, cat8000v): the job's step 2 is a native **PUT** (a PATCH of `vrf forwarding` keeps the address on this release); the route-targets sit directly under `vrf definition`, not under address-family; the ACL log message is `%FMANFP-6-IPACCESSLOGP` (not `%SEC`); the deny counter lags behind the log line.

## Intentional Faults

| ID | Device / file | Change | Symptom |
|---|---|---|---|
| F1 | `aster_svc.py` steps 1-2 (job on AUTO-MGMT1) | Step 1 creates Loopback110 with its address (ietf-interfaces POST, 201). Step 2 then does a native **PUT** of `interface/Loopback=110` carrying only the name and `vrf forwarding ASTER` (204). A PUT replaces the interface node, so the address is gone: `interface Loopback110 / vrf forwarding ASTER / no ip address` | 10.90.60.110 is in no table of AUTO-RTR3; Aster's ping to .110 gets unreachable (`U.U`), SSH fails |
| F2 | `aster_svc.py` step 3 | Reads `ASTER-IN`, POSTs the SSH permit for .110 at (highest sequence + 100) = **1000**, behind AUTO-CS-3's logged deny at 900 (201) | After F1 is fixed ping to .110 works (ICMP range permit) but SSH to .110 hits the deny at 900: `%FMANFP-6-IPACCESSLOGP ... denied tcp 10.60.61.10(...) -> 10.90.60.110(22)`; telnet shows `% Destination unreachable` (admin-prohibited), not a timeout |
| RH | job step 4 | Reads Loopback110's operational `oper-status` and prints `Lo110 up - service 10.90.60.110 published` | A loopback is ready with or without an address; the same oper record shows `ipv4 0.0.0.0`. Steers the student away from AUTO-RTR3 |

Series: F1 then F2. Fixing F1 alone makes the ping work (tempting to close the ticket); the ticket's V item is the SSH banner from Aster's source. Not faults: the `lock-denied` retry loop in the job (correct); the 409 `data-exists` on a re-run (expected, 065 F3).

## Diagnosis / Methodology

1. Reproduce from Aster's side (RTR1): `.100` ping 3/3 and SSH banner work; `.110` ping `U.U`, SSH `% Destination unreachable`. Output below ("Ticket state").
2. Ask where the traffic stops. Aster's side and the handoff are eliminated: the same source reaches .100 over the same link. The SSH service is eliminated: the banner comes from .100 in the same VRF with no VTY access class.
3. RTR3 routing: `show ip route vrf ASTER | include 10.90` lists only `10.90.60.100/32`. `show running-config | section interface Loopback110` shows `vrf forwarding ASTER` and `no ip address`. The config GET of `Loopback=110` returns only name and vrf, and the oper GET shows `oper-status if-oper-state-ready`, `vrf ASTER`, `ipv4 0.0.0.0`: the job's "up" is a status, not a reachability test. F1 confirmed.
4. After F1 is fixed alone: ping works, SSH does not. `show ip access-lists ASTER-IN` lists `1000 permit tcp ... host 10.90.60.110 eq 22` below `900 deny ip any any log`; the log shows the deny for the SSH probe to .110. The ACL GET (or CLI) shows the sequence outside AUTO-CS-3's 10-89 block. F2 confirmed. Wrong causes ruled out: no route problem (ping works), no VTY problem (.100 works).
5. Causality: each fix on its own, symptom check after each (below). Masked case: a student whose R1 ACL permits SSH to the whole range (against AUTO-CS-3) sees F1 only; apply the host entries from this document when validating.
6. The re-run of the shipped job stops at step 1 with 409 `data-exists` (expected; the objects exist). The corrected job must handle that case by reading first.

## Solution Configuration

All RTR3 changes by API from AUTO-MGMT1 (`cd /home/cisco/aster/work`, `R=~/venv/bin/python`). RTR3's CLI was used for `show` only.

### R1: one locked NETCONF transaction (`r1_payload.xml`, applied by `nc_apply.py`)

```xml
<config xmlns="urn:ietf:params:xml:ns:netconf:base:1.0">
  <native xmlns="http://cisco.com/ns/yang/Cisco-IOS-XE-native">
    <vrf>
      <definition>
        <name>ASTER</name>
        <rd>65010:300</rd>
        <address-family>
          <ipv4/>
        </address-family>
        <route-target>
          <export><asn-ip>65010:300</asn-ip></export>
          <import><asn-ip>65010:300</asn-ip></import>
        </route-target>
      </definition>
    </vrf>
    <interface>
      <Loopback>
        <name>100</name>
        <vrf><forwarding>ASTER</forwarding></vrf>
        <ip>
          <address>
            <primary>
              <address>10.90.60.100</address>
              <mask>255.255.255.255</mask>
            </primary>
          </address>
        </ip>
      </Loopback>
    </interface>
    <ip>
      <access-list>
        <extended xmlns="http://cisco.com/ns/yang/Cisco-IOS-XE-acl">
          <name>ASTER-IN</name>
          <access-list-seq-rule>
            <sequence>10</sequence>
            <ace-rule>
              <action>permit</action>
              <protocol>icmp</protocol>
              <ipv4-address>10.60.61.0</ipv4-address>
              <mask>0.0.0.255</mask>
              <dest-ipv4-address>10.90.60.96</dest-ipv4-address>
              <dest-mask>0.0.0.15</dest-mask>
            </ace-rule>
          </access-list-seq-rule>
          <access-list-seq-rule>
            <sequence>20</sequence>
            <ace-rule>
              <action>permit</action>
              <protocol>tcp</protocol>
              <ipv4-address>10.60.61.0</ipv4-address>
              <mask>0.0.0.255</mask>
              <dst-host-address>10.90.60.100</dst-host-address>
              <dst-eq>22</dst-eq>
            </ace-rule>
          </access-list-seq-rule>
          <access-list-seq-rule>
            <sequence>900</sequence>
            <ace-rule>
              <action>deny</action>
              <protocol>ip</protocol>
              <any/>
              <dst-any/>
              <log/>
            </ace-rule>
          </access-list-seq-rule>
        </extended>
      </access-list>
    </ip>
  </native>
</config>
```

`nc_apply.py`:

```python
#!/usr/bin/env python3
"""Apply a native-model payload as one locked NETCONF transaction: lock, edit-config, unlock."""
import sys
from ncclient import manager

payload = open(sys.argv[1]).read()
with manager.connect(host="10.90.50.11", port=830, username="apiuser", password="Api#Pass2026",
                     hostkey_verify=False, device_params={"name": "iosxe"}, timeout=120) as m:
    print("session", m.session_id)
    m.lock("running")
    try:
        print(m.edit_config(target="running", config=payload).ok)
    finally:
        m.unlock("running")
        print("unlocked")
```

`nc_getcfg.py` (filtered `<get-config>`; write it next to `nc_apply.py`):

```python
#!/usr/bin/env python3
"""Read back the R1 objects with a subtree filter on the running datastore."""
from ncclient import manager

FILTER_INNER = """
<native xmlns="http://cisco.com/ns/yang/Cisco-IOS-XE-native">
    <vrf><definition><name>ASTER</name></definition></vrf>
    <interface><Loopback><name>100</name></Loopback></interface>
    <ip><access-list><extended xmlns="http://cisco.com/ns/yang/Cisco-IOS-XE-acl"><name>ASTER-IN</name></extended></access-list></ip>
</native>"""
with manager.connect(host="10.90.50.11", port=830, username="apiuser", password="Api#Pass2026",
                     hostkey_verify=False, device_params={"name": "iosxe"}, timeout=120) as m:
    print(m.get_config(source="running", filter=("subtree", FILTER_INNER)).xml)
```

Notes: route-targets are `vrf/definition/route-target/{export,import}/asn-ip` (a first attempt with them under `address-family/ipv4` returned `unknown-element export`). ACE leaves: `ipv4-address`/`mask` (source), `dest-ipv4-address`/`dest-mask` (range) or `dst-host-address` (host), `dst-eq`, `<any/>`, `<dst-any/>`, `<log/>`. Run: `$R nc_apply.py r1_payload.xml` prints `session N`, `True`, `unlocked`. Read back: `$R nc_getcfg.py` (filtered `<get-config>` on the VRF, Loopback100 and `ASTER-IN`).

### R2: RESTCONF (`rc.py METHOD PATH [bodyfile]`: one call, pinned certificate)

`rc.py` (write it in the working directory; same credentials and pinned certificate as the job below; `MAXC` optionally truncates the printed body, default unlimited):

```python
#!/usr/bin/env python3
"""rc.py METHOD PATH [bodyfile]: one RESTCONF call to AUTO-RTR3, prints the HTTP status then the body."""
import json, os, sys, requests

method, path = sys.argv[1], sys.argv[2]
body = json.load(open(sys.argv[3])) if len(sys.argv) > 3 else None
JSON = "application/yang-data+json"
resp = requests.request(method, "https://rtr3.auto.veridian.example/restconf/data" + path,
                        auth=("apiuser", "Api#Pass2026"), headers={"Accept": JSON, "Content-Type": JSON},
                        json=body, verify="/home/cisco/trust/rtr3.pem", timeout=60)
print("HTTP", resp.status_code)
text = json.dumps(resp.json(), indent=2) if resp.text.strip().startswith(("{", "[")) else resp.text
print(text[:int(os.environ.get("MAXC", "100000"))])
```

`gi2.json` (one body: dot1Q, VRF, address and inbound ACL; the address survives):

```json
{"Cisco-IOS-XE-native:GigabitEthernet": {"name": "2.300",
 "encapsulation": {"dot1Q": {"vlan-id": 300}},
 "vrf": {"forwarding": "ASTER"},
 "ip": {"address": {"primary": {"address": "10.200.60.8", "mask": "255.255.255.254"}},
        "access-group": {"in": {"acl": {"acl-name": "ASTER-IN", "in": [null]}}}}}}
```
`route.json`:

```json
{"Cisco-IOS-XE-native:vrf": [{"name": "ASTER", "ip-route-interface-forwarding-list": [{"prefix": "10.60.61.0", "mask": "255.255.255.0", "fwd-list": [{"fwd": "10.200.60.9"}]}]}]}
```

```
$R rc.py POST /Cisco-IOS-XE-native:native/interface gi2.json            # 201
$R rc.py POST /Cisco-IOS-XE-native:native/ip/route route.json           # 201
$R rc.py GET  /Cisco-IOS-XE-native:native/interface/GigabitEthernet=2.300
$R rc.py GET  /Cisco-IOS-XE-native:native/ip/route/vrf=ASTER
```

A 409 `lock-denied` (message: the database is locked by session N `yang_mgmt_infra`) right after the NETCONF transaction is transient: retry after a few seconds (seen once at build, both POSTs; 201 after a 6 s wait).

### TK1 fixes (each alone)

F1: one native PUT with VRF and address together (`lo110_fix.json`):

```
{"Cisco-IOS-XE-native:Loopback":[{"name":110,"vrf":{"forwarding":"ASTER"},"ip":{"address":{"primary":{"address":"10.90.60.110","mask":"255.255.255.255"}}}}]}
$R rc.py PUT /Cisco-IOS-XE-native:native/interface/Loopback=110 lo110_fix.json      # 204
```

F2: delete the misplaced entry and insert the permit in the service block (`ace30.json`: sequence "30", permit tcp 10.60.61.0 0.0.0.255 host 10.90.60.110 eq 22):

```
$R rc.py DELETE /Cisco-IOS-XE-native:native/ip/access-list/extended=ASTER-IN/access-list-seq-rule=1000    # 204
$R rc.py POST   /Cisco-IOS-XE-native:native/ip/access-list/extended=ASTER-IN ace30.json                   # 201
```

Any free sequence 10-89 below the deny is accepted (25, 30, ...).

### R4: corrected job `aster_svc_fixed.py`

Reads before it writes: skips step 1 when Loopback110 already holds the VRF and address, else ONE PUT with both; skips step 2 when a permit for the service already sits below 900, else inserts it at (highest sequence below 90) + 10; verifies config and oper data and the ACL order; exit 2 and `VERIFY FAILED: ...` when the intent does not hold. (A write that is a no-op still logs a `%DMI-5-CONFIG_I` line, so the job must not write when nothing differs.)

```python
#!/usr/bin/env python3
"""AST-2b: publish the second Aster service address 10.90.60.110 on AUTO-RTR3 (RESTCONF)."""
import sys
import time

import requests

HOST = "rtr3.auto.veridian.example"
USER = "apiuser"
PASSWORD = "Api#Pass2026"
CERT = "/home/cisco/trust/rtr3.pem"
BASE = f"https://{HOST}/restconf/data"
JSON = "application/yang-data+json"
HEADERS = {"Accept": JSON, "Content-Type": JSON}

VRF = "ASTER"
ACL = "ASTER-IN"
SERVICE = "10.90.60.110"
LOOP = 110
MONITORING = ("10.60.61.0", "0.0.0.255")

SESSION = requests.Session()


def call(method, path, body=None):
    """One RESTCONF call; a 409 lock-denied is retried with a growing delay."""
    for attempt in range(1, 6):
        resp = SESSION.request(method, BASE + path, auth=(USER, PASSWORD), headers=HEADERS,
                               json=body, verify=CERT, timeout=60)
        if resp.status_code == 409 and "lock-denied" in resp.text and attempt < 5:
            delay = 3 * attempt
            print(f"  409 lock-denied, retry {attempt} in {delay}s")
            time.sleep(delay)
            continue
        return resp
    return resp


def step(num, text, resp):
    ok = 200 <= resp.status_code < 300
    print(f"step {num}: {text}: HTTP {resp.status_code}" + ("" if ok else f" {resp.text[:300]}"))
    if not ok:
        sys.exit(1)


def read_acl():
    resp = call("GET", f"/Cisco-IOS-XE-native:native/ip/access-list/extended={ACL}")
    step(3, f"read {ACL}", resp)
    return {int(r["sequence"]): r for r in resp.json()["Cisco-IOS-XE-acl:extended"][0]["access-list-seq-rule"]}


def loop_ok(data):
    lo = data["Cisco-IOS-XE-native:Loopback"]
    lo = lo[0] if isinstance(lo, list) else lo
    return (lo.get("vrf", {}).get("forwarding") == VRF
            and lo.get("ip", {}).get("address", {}).get("primary", {}).get("address") == SERVICE)


def has_permit(rules):
    return [s for s, r in rules.items() if s < 900 and r.get("ace-rule", {}).get("action") == "permit"
            and r["ace-rule"].get("dst-host-address") == SERVICE and r["ace-rule"].get("dst-eq") in (22, "ssh")]


def main():
    # 1. the loopback: VRF and address in ONE native PUT (idempotent; no address-less moment)
    body = {"Cisco-IOS-XE-native:Loopback": [{"name": LOOP, "vrf": {"forwarding": VRF},
            "ip": {"address": {"primary": {"address": SERVICE, "mask": "255.255.255.255"}}}}]}
    cur = call("GET", f"/Cisco-IOS-XE-native:native/interface/Loopback={LOOP}")
    if cur.ok and loop_ok(cur.json()):
        print(f"step 1: Loopback{LOOP} already in VRF {VRF} with {SERVICE}/32, nothing to do")
    else:
        step(1, f"put Loopback{LOOP} in VRF {VRF} with {SERVICE}/32",
             call("PUT", f"/Cisco-IOS-XE-native:native/interface/Loopback={LOOP}", body))

    # 2. SSH permit in the service block (10-89), only when it is not there yet
    rules = read_acl()
    if has_permit(rules):
        print(f"step 2: permit for {SERVICE} already at sequence {has_permit(rules)[0]}, nothing to do")
    else:
        seq = max(s for s in rules if s < 90) + 10
        body = {"Cisco-IOS-XE-acl:access-list-seq-rule": [{
            "sequence": str(seq),
            "ace-rule": {"action": "permit", "protocol": "tcp",
                         "ipv4-address": MONITORING[0], "mask": MONITORING[1],
                         "dst-host-address": SERVICE, "dst-eq": 22}}]}
        step(2, f"insert SSH permit for {SERVICE} at sequence {seq}",
             call("POST", f"/Cisco-IOS-XE-native:native/ip/access-list/extended={ACL}", body))

    # 3. verify the intent (config and operational data), exit non-zero if it does not hold
    bad = []
    resp = call("GET", f"/Cisco-IOS-XE-native:native/interface/Loopback={LOOP}")
    if not (resp.ok and loop_ok(resp.json())):
        bad.append(f"Loopback{LOOP}: config does not hold VRF {VRF} and {SERVICE}")
    resp = call("GET", f"/Cisco-IOS-XE-interfaces-oper:interfaces/interface=Loopback{LOOP}")
    rec = resp.json()["Cisco-IOS-XE-interfaces-oper:interface"][0] if resp.ok else {}
    if rec.get("ipv4") != SERVICE or rec.get("vrf") != VRF:
        bad.append(f"oper Loopback{LOOP}: ipv4={rec.get('ipv4')} vrf={rec.get('vrf')}")
    rules = read_acl()
    permits = has_permit(rules)
    if not permits or min(permits) > min(s for s in rules if rules[s]["ace-rule"]["action"] == "deny"):
        bad.append(f"ACL {ACL}: no SSH permit for {SERVICE} ahead of the deny")
    SESSION.close()
    if bad:
        print("VERIFY FAILED: " + "; ".join(bad))
        sys.exit(2)
    print(f"verified: Lo{LOOP} {SERVICE} in {VRF}, SSH permit at {permits[0]} ahead of the deny")


if __name__ == "__main__":
    main()
```

## Verification

All outputs captured on a fresh import of the YAML; long records trimmed (`...`).

### R1 and R2 applied by API

```
cd /home/cisco/aster/work; R=~/venv/bin/python
$R nc_apply.py r1_payload.xml
session 35
True
unlocked
```

First RESTCONF POSTs right after the transaction (409 `lock-denied`, `error-message: the configuration database is locked by session 28 yang_mgmt_infra ...`, for both Gi2.300 and the route), repeated after a 6 s wait:

```
cd /home/cisco/aster/work; R=~/venv/bin/python
sleep 6; MAXC=300 $R rc.py POST /Cisco-IOS-XE-native:native/interface gi2.json
HTTP 201
sleep 6; MAXC=300 $R rc.py POST /Cisco-IOS-XE-native:native/ip/route route.json
HTTP 201
```

### R1/R2/R3 read-back (API reads, CLI toolkit, DMI lines, Aster's side)

```
== AUTO-MGMT1 ==
cd /home/cisco/aster/work; R=~/venv/bin/python
$R nc_getcfg.py
<rpc-reply><data>... VRF ASTER (rd 65010:300, export/import 65010:300), Loopback100 (vrf ASTER, 10.90.60.100/32), ASTER-IN seq 10, 20, 900 as sent ...</data></rpc-reply>
MAXC=700 $R rc.py GET /Cisco-IOS-XE-native:native/interface/GigabitEthernet=2.300
HTTP 200
{
  "Cisco-IOS-XE-native:GigabitEthernet": [
    {
      "name": "2.300",
      "encapsulation": {
        "dot1Q": {
          "vlan-id": 300
        }
      },
      "vrf": {
        "forwarding": "ASTER"
      },
      "ip": {
        "access-group": {
          "in": {
            "acl": {
              "acl-name": "ASTER-IN",
              "in": [null]
            }
          }
        },
        "address": {
          "primary": {
            "address": "10.200.60.8",
            "mask": "255.255.255.254"
          }
        }
      }
    }
  ]
}
MAXC=500 $R rc.py GET /Cisco-IOS-XE-native:native/ip/route/vrf=ASTER
HTTP 200
{
  "Cisco-IOS-XE-native:vrf": [
    {
      "name": "ASTER",
      "ip-route-interface-forwarding-list": [
        {
          "prefix": "10.60.61.0",
          "mask": "255.255.255.0",
          "fwd-list": [
            {
              "fwd": "10.200.60.9"
            }
          ]
        }
      ]
    }
  ]
}
MAXC=800 $R rc.py GET /Cisco-IOS-XE-interfaces-oper:interfaces/interface=GigabitEthernet2.300
HTTP 200
{
  "Cisco-IOS-XE-interfaces-oper:interface": [
    {
      "name": "GigabitEthernet2.300",
      "interface-type": "iana-iftype-ethernet-csmacd",
      "admin-status": "if-state-up",
      "oper-status": "if-oper-state-ready",
      "last-change": "2026-10-13T22:16:54.366+00:00",
      "if-index": 9,
      "phys-address": "52:54:00:60:63:d4",
      "speed": "1000000000",
        "discontinuity-time": "1970-01-01T00:00:00+00:00",
        "in-octets": "0",
        "in-unicast-pkts": "0",
        "in-broadcast-pkts": "0",
        "in-multicast-pkts": "0",
        "in-discards": 0,
        "in-errors": 0,
        "in-unknown-protos": 0,
        "out-octets": 0,
        "out-unicast-pkts": "0",
        "out-broadcast-pkts": "0",
        "out-multicast-pkts": "0",
MAXC=500 $R rc.py GET /Cisco-IOS-XE-vrf-oper:vrf-oper-data
HTTP 200
{
  "Cisco-IOS-XE-vrf-oper:vrf-oper-data": {
    "vrf-entry": [
      {
        "vrf-name": "ASTER",
        "interface": ["Loopback100", "GigabitEthernet2.300"],
        "address-family-entry": [
          {
            "address-family": "ipv4-unicast"
          }
        ]
      }
    ]
  }
}
```

```
== AUTO-RTR3 ==
show vrf
  Name                             Default RD            Protocols   Interfaces
  ASTER                            65010:300             ipv4        Lo100
                                                                     Gi2.300
show ip route vrf ASTER
Routing Table: ASTER
      10.0.0.0/8 is variably subnetted, 4 subnets, 3 masks
S        10.60.61.0/24 [1/0] via 10.200.60.9
C        10.90.60.100/32 is directly connected, Loopback100
C        10.200.60.8/31 is directly connected, GigabitEthernet2.300
L        10.200.60.8/32 is directly connected, GigabitEthernet2.300
show access-lists ASTER-IN
Extended IP access list ASTER-IN
    10 permit icmp 10.60.61.0 0.0.0.255 10.90.60.96 0.0.0.15
    20 permit tcp 10.60.61.0 0.0.0.255 host 10.90.60.100 eq 22
    900 deny ip any any log
show running-config interface GigabitEthernet2.300
Building configuration...
Current configuration : 154 bytes
!
interface GigabitEthernet2.300
 encapsulation dot1Q 300
 vrf forwarding ASTER
 ip address 10.200.60.8 255.255.255.254
 ip access-group ASTER-IN in
end
show logging | include DMI-5-CONFIG_I
*Oct 13 22:20:05.044: %DMI-5-CONFIG_I: R0/0: dmiauthd: Configured from NETCONF/RESTCONF by apiuser, transaction-id 27
*Oct 13 22:20:29.360: %DMI-5-CONFIG_I: R0/0: dmiauthd: Configured from NETCONF/RESTCONF by apiuser, transaction-id 82
*Oct 13 22:20:37.046: %DMI-5-CONFIG_I: R0/0: dmiauthd: Configured from NETCONF/RESTCONF by apiuser, transaction-id 133
== AUTO-RTR1 ==
Type escape sequence to abort.
Sending 3, 100-byte ICMP Echos to 10.90.60.100, timeout is 2 seconds:
Packet sent with a source address of 10.60.61.10 
!!!
Success rate is 100 percent (3/3), round-trip min/avg/max = 1/17/49 ms
```

`telnet 10.90.60.100 22 /vrf ASTER /source-interface Loopback300` from RTR1 (run it alone in its block; it once hung when combined with other long commands) and the refused port 23 with its log line (a `deny` counter lags the log: `(1 match)` after two denied probes, `(7 matches)` later; the log line is the immediate evidence):

```
Trying 10.90.60.100 ... 
% Destination unreachable; gateway or host down
```

```
show logging | include IPACCESSLOG
*Oct 13 22:22:49.109: %FMANFP-6-IPACCESSLOGP: F0/0: fman_fp_image: list ASTER-IN denied tcp 10.60.61.10(43169) -> 10.90.60.110(22), 1 packet
*Oct 13 22:25:12.131: %FMANFP-6-IPACCESSLOGP: F0/0: fman_fp_image: list ASTER-IN denied tcp 10.60.61.10(26684) -> 10.90.60.100(23), 1 packet
show access-lists ASTER-IN | include 900
    900 deny ip any any log (3 matches)
```

### Ticket state (TK1: the shipped job, run once; then a re-run)

```
cd /home/cisco/aster; R=~/venv/bin/python
$R aster_svc.py; echo EXIT=$?
step 1: create Loopback110 10.90.60.110/32: HTTP 201
step 2: put Loopback110 in VRF ASTER: HTTP 204
step 3: read ASTER-IN: HTTP 200
  409 lock-denied, retry 1 in 3s
  409 lock-denied, retry 2 in 6s
step 3: append SSH permit for 10.90.60.110 at sequence 1000: HTTP 201
step 4: read Loopback110 state: HTTP 200
Lo110 up - service 10.90.60.110 published
EXIT=0
```

```
cd /home/cisco/aster; R=~/venv/bin/python
$R aster_svc.py; echo EXIT=$?
step 1: create Loopback110 10.90.60.110/32: HTTP 409 {
  "ietf-restconf:errors": {
    "error": [
      {
        "error-type": "application",
        "error-tag": "data-exists",
        "error-path": "/ietf-interfaces:interfaces",
        "error-message": "object already exists: /if:interfaces/if:interface[if:name='Loopback110']"
      }
    ]
  }
}
EXIT=1
```

RTR1 and RTR3 after the first run:

```
ping vrf ASTER 10.90.60.100 source Loopback300 repeat 3
Type escape sequence to abort.
Sending 3, 100-byte ICMP Echos to 10.90.60.100, timeout is 2 seconds:
Packet sent with a source address of 10.60.61.10 
!!!
Success rate is 100 percent (3/3), round-trip min/avg/max = 1/1/2 ms
ping vrf ASTER 10.90.60.110 source Loopback300 repeat 3
Type escape sequence to abort.
Sending 3, 100-byte ICMP Echos to 10.90.60.110, timeout is 2 seconds:
Packet sent with a source address of 10.60.61.10 
U.U
Success rate is 0 percent (0/3)
telnet 10.90.60.110 22 /vrf ASTER /source-interface Loopback300
Trying 10.90.60.110, 22 ... 
% Destination unreachable; gateway or host down
show running-config | section interface Loopback110
interface Loopback110
 vrf forwarding ASTER
 no ip address
show ip route vrf ASTER | include 10.90
C        10.90.60.100/32 is directly connected, Loopback100
show ip access-lists ASTER-IN
Extended IP access list ASTER-IN
    10 permit icmp 10.60.61.0 0.0.0.255 10.90.60.96 0.0.0.15 (9 matches)
    20 permit tcp 10.60.61.0 0.0.0.255 host 10.90.60.100 eq 22
    900 deny ip any any log (2 matches)
    1000 permit tcp 10.60.61.0 0.0.0.255 host 10.90.60.110 eq 22
show logging | include IPACCESSLOG
*Oct 13 22:22:49.109: %FMANFP-6-IPACCESSLOGP: F0/0: fman_fp_image: list ASTER-IN denied tcp 10.60.61.10(43169) -> 10.90.60.110(22), 1 packet
```

### Diagnosis reads (API)

(The ACL GET was cut at 900 characters here; the CLI lines above show the 1000 entry.)

```
cd /home/cisco/aster/work; R=~/venv/bin/python
MAXC=400 $R rc.py GET /Cisco-IOS-XE-native:native/interface/Loopback=110
HTTP 200
{
  "Cisco-IOS-XE-native:Loopback": [
    {
      "name": 110,
      "vrf": {
        "forwarding": "ASTER"
      }
    }
  ]
}
MAXC=3000 $R rc.py GET /Cisco-IOS-XE-interfaces-oper:interfaces/interface=Loopback110 | grep -E 'HTTP|oper-status|"vrf"|"ipv4|ipv4-subnet'
HTTP 200
      "oper-status": "if-oper-state-ready",
      "vrf": "ASTER",
      "ipv4": "0.0.0.0",
      "ipv4-subnet-mask": "0.0.0.0",
      "ipv4-tcp-adjust-mss": 0,
        "mdix-oper-status-enabled": false,
MAXC=900 $R rc.py GET /Cisco-IOS-XE-native:native/ip/access-list/extended=ASTER-IN | grep -E 'HTTP|sequence|action|dst-host|dst-eq'
HTTP 200
          "sequence": "10",
            "action": "permit",
          "sequence": "20",
            "action": "permit",
            "dst-host-address": "10.90.60.100",
            "dst-host": "10.90.60.100",
            "dst-eq": 22
          "sequence": "900",
            "action": "deny",
```

### F1 fixed alone

```
cd /home/cisco/aster/work; R=~/venv/bin/python
$R rc.py PUT /Cisco-IOS-XE-native:native/interface/Loopback=110 lo110_fix.json
HTTP 204
show running-config | section interface Loopback110
interface Loopback110
 vrf forwarding ASTER
 ip address 10.90.60.110 255.255.255.255
show ip route vrf ASTER | include 10.90
C        10.90.60.100/32 is directly connected, Loopback100
C        10.90.60.110/32 is directly connected, Loopback110
Type escape sequence to abort.
Sending 3, 100-byte ICMP Echos to 10.90.60.110, timeout is 2 seconds:
Packet sent with a source address of 10.60.61.10 
!!!
Success rate is 100 percent (3/3), round-trip min/avg/max = 1/1/2 ms
```

RTR1 `telnet 10.90.60.110 22 ...` is still `% Destination unreachable` at this point (F2).

### F2 fixed (after F1)

```
cd /home/cisco/aster/work; R=~/venv/bin/python
$R rc.py DELETE /Cisco-IOS-XE-native:native/ip/access-list/extended=ASTER-IN/access-list-seq-rule=1000
HTTP 204
$R rc.py POST /Cisco-IOS-XE-native:native/ip/access-list/extended=ASTER-IN ace30.json
HTTP 201
Extended IP access list ASTER-IN
    10 permit icmp 10.60.61.0 0.0.0.255 10.90.60.96 0.0.0.15 (12 matches)
    20 permit tcp 10.60.61.0 0.0.0.255 host 10.90.60.100 eq 22
    30 permit tcp 10.60.61.0 0.0.0.255 host 10.90.60.110 eq 22
    900 deny ip any any log (2 matches)
```

```
Trying 10.90.60.110, 22 ... Open
SSH-2.0-Cisco-1.25
telnet 10.90.60.110 22 /vrf ASTER /source-interface Loopback300
[Connection to 10.90.60.110 closed by foreign host]
```

### Corrected job

On a clean pod (Lo110 and ACE 30 removed through the API; `404` for the already-absent seq 1000 is expected):

```
cd /home/cisco/aster/work; R=~/venv/bin/python
$R aster_svc_fixed.py; echo EXIT=$?
step 1: put Loopback110 in VRF ASTER with 10.90.60.110/32: HTTP 201
step 3: read ASTER-IN: HTTP 200
  409 lock-denied, retry 1 in 3s
  409 lock-denied, retry 2 in 6s
step 2: insert SSH permit for 10.90.60.110 at sequence 30: HTTP 201
step 3: read ASTER-IN: HTTP 200
verified: Lo110 10.90.60.110 in ASTER, SSH permit at 30 ahead of the deny
EXIT=0
```

Second run (nothing to do):

```
cd /home/cisco/aster/work; R=~/venv/bin/python
$R aster_svc_fixed.py; echo EXIT=$?
step 1: Loopback110 already in VRF ASTER with 10.90.60.110/32, nothing to do
step 3: read ASTER-IN: HTTP 200
step 2: permit for 10.90.60.110 already at sequence 30, nothing to do
step 3: read ASTER-IN: HTTP 200
verified: Lo110 10.90.60.110 in ASTER, SSH permit at 30 ahead of the deny
EXIT=0
```

Broken variant (PUT body without `ip address`): steps 2xx, then `VERIFY FAILED: Loopback110: config does not hold VRF ASTER and 10.90.60.110; oper Loopback110: ipv4=0.0.0.0 vrf=ASTER`, exit code 2. The shipped job in the same variant prints `Lo110 up - service 10.90.60.110 published`. Idempotence: running config of ASTER, Lo1xx and the ACL identical before and after the second run (`diff`), and no new `%DMI-5-CONFIG_I` line (the first draft always PUT; an identical PUT still logged a DMI line, so the job reads first).

### Operational reads available

| Read | Result on 17.16.1a |
|---|---|
| `Cisco-IOS-XE-interfaces-oper:interfaces/interface=GigabitEthernet2.300` | 200: `oper-status if-oper-state-ready`, `vrf ASTER`, `ipv4 10.200.60.8`, `ipv4-subnet-mask 255.255.255.254` |
| `...interface=Loopback110` (F1 state) | `ready`, `vrf ASTER`, `ipv4 0.0.0.0` |
| `Cisco-IOS-XE-vrf-oper:vrf-oper-data` | 200: VRF membership only (`interface` list, `address-family ipv4-unicast`), **no routes or addresses** |
| `Cisco-IOS-XE-ip-route-oper:routing-state` | 404 `uri keypath not found` |

Routes therefore come from the CLI toolkit (`show ip route vrf ASTER`) or the native config GET of `ip/route/vrf=ASTER`.

### End state

```
show ip access-lists ASTER-IN
Extended IP access list ASTER-IN
    10 permit icmp 10.60.61.0 0.0.0.255 10.90.60.96 0.0.0.15 (12 matches)
    20 permit tcp 10.60.61.0 0.0.0.255 host 10.90.60.100 eq 22
    30 permit tcp 10.60.61.0 0.0.0.255 host 10.90.60.110 eq 22
    900 deny ip any any log (3 matches)
show running-config | section interface Loopback1
interface Loopback100
 vrf forwarding ASTER
 ip address 10.90.60.100 255.255.255.255
interface Loopback101
 ip address 10.255.90.101 255.255.255.255
interface Loopback110
 vrf forwarding ASTER
 ip address 10.90.60.110 255.255.255.255
show running-config | section router ospf
router ospf 1
 router-id 10.255.90.11
 passive-interface default
 no passive-interface GigabitEthernet2
 network 10.255.90.101 0.0.0.0 area 0
ping vrf ASTER 10.90.60.110 source Loopback300 repeat 2
Type escape sequence to abort.
Sending 2, 100-byte ICMP Echos to 10.90.60.110, timeout is 2 seconds:
Packet sent with a source address of 10.60.61.10 
!!
Success rate is 100 percent (2/2), round-trip min/avg/max = 1/1/2 ms
show ip ospf neighbor | include FULL
10.255.90.11      0   FULL/  -        00:00:36    10.90.255.3     Ethernet0/2
```

## Failure / Recovery Behaviour

Scenario: **silent failure** of the handoff parent link, `tools/cml-rest.sh link stop` on AUTO-RTR1 e0/2 - AUTO-RTR3 Gi2 (IOL keeps the interface up/up and drops traffic; a cable pull would be `shutdown` on both ends). Host clock and RTR1 `show clock` agreed within 1 s. No RTR3 reload or node stop in the lab (its API certificate would change).

| Scenario (trigger, end condition) | Runs (raw) | Documented range | Basis |
|---|---|---|---|
| Link stop; Aster's ping/SSH to .100 first lost | first poll after the trigger in all 3 runs (`UNTIL met after 1 s`, 1 s polling) | < 2 s | Silent drop, no protocol involved |
| Link stop; RTR1 OSPF neighbor on Ethernet0/2 FULL to DOWN `Dead timer expired` (global table; ASTER's static routes do not depend on it) | 33.0 s, 32.9-34.3 s, 34.7-35.8 s (stop 22:01:03 -> DOWN 22:01:36.0; 22:03:14.6-16.0 -> 22:03:48.9; 22:04:42.3-43.4 -> 22:05:18.1) | 30-40 s | Dead 40 s minus 0-10 s since the last hello (default timers), derived; measured 33-36 s |
| Link stop; Gi2.300 `oper-status` on the API during the loss | `if-oper-state-ready`, `vrf ASTER`, `ipv4 10.200.60.8` unchanged in 3 runs, checked 25-50 s after the stop and again after OSPF went down; RTR3 `show ip interface brief` Gi2 up/up | stays `ready` | An API status read is not a reachability test |
| Link start; first reply of `ping vrf ASTER 10.90.60.100 source Loopback300` | run 1 ~1-2 s (start 22:02:41.9, ping in the same poll second), run 2 1.5-2.5 s, run 3 1.6-2.7 s | 1-4 s | ARP resolution plus 1 s poll granularity |
| Link start; RTR1 OSPF back to FULL | 1.9 s, 8.1-9.1 s, 1.5-2.6 s | 2-10 s | Hello phase (10 s), derived |

Recovery: after `link start` Aster's ping and SSH to .100 and .110 return with no configuration change on either router; the API state needed no action.

## Answers to Analysis Questions

**Q1.** A 2xx says the device accepted the request and applied it to the datastore as sent (201 created, 204 applied with no body). It does not say the resulting state is what the author meant: step 2 returned 204 and silently removed the address, step 3 returned 201 for an ACE that can never match. Only a read of the result against the intent shows it.

**Q2.** (There are two causes; the student's answer should cover each one they found.) F1: one PUT carrying VRF and address together (so there is no address-less state) or the single NETCONF transaction used in R1; a read of Loopback110 after the write (config GET shows no address, oper GET shows `ipv4 0.0.0.0`) would have caught it. F2: computing the sequence inside the service block 10-89 (or POSTing at a free sequence below 900) and reading the ACL back to check the permit sits ahead of the deny. The individual results (201, 204, 200) each describe only a request, not the interaction of two writes or the order inside an ACL, and the job's oper-status check proves only that the interface is ready.

**Q3.** The single `edit-config` applied the three objects (VRF, loopback, ACL) as one transaction, so it was all or nothing: if the edit failed, nothing was applied. The lock added exclusivity: no other session could write to the datastore while the edit ran. The RESTCONF writes in R2 are separate requests without that lock; each is its own transaction and can be refused with 409 `lock-denied` while another session (here the infrastructure's own `yang_mgmt_infra`, or a forgotten NETCONF session) holds the lock. While a NETCONF session holds the lock, RESTCONF writes are refused (409 `lock-denied`) or, for a session left holding `<lock>`, block until the client times out (the left-open case was not provoked here), so R1 must always unlock, including on errors.

**Q4.** Route-targets control import/export of VRF routes between VRFs through MP-BGP (a PE with VPNv4 or a route-leak design). This router has one VRF and no BGP/VPN, and the return route is a static route inside the VRF, so nothing is exported or imported. They matter once a second VRF or a BGP VPNv4 session joins (071, MS-5), where matching RTs decide which routes cross.

**Q5.** Read the configuration back (does the object hold the VRF and the address, is the ACE in the permitted sequence block, is it ahead of the deny) and the operational data (does the interface report the address and VRF, `ipv4`/`vrf` fields). Configuration answers "what was written", operational data answers "what the device is doing"; the oper-status alone answers neither. Compare each read with the intent, print what differs and exit non-zero.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-25 |
| CML | 2.10.0 |
| Node types | cat8000v (IOS XE 17.16.1a), external_connector, iol-xe (IOS XE 17.16.1a), ubuntu (Ubuntu 24.04), unmanaged_switch |
