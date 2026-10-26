# MS-4 — Solution

## Summary

The milestone closes module 09 and the first nine modules on one network: HQ lite H4 with HQ-CORE2 (the dual-core lite), the E3 edge pair (HQ-EDGE2 is a Catalyst 8000V), the DC block with its services, and the automation host. Five change requests build the "H5 services" stage (tracked VRRPv3 with an evidence applet, the second anycast RP, core-edge MQC, an ACL change through RESTCONF, and a reviewed AI proposal) and three tickets with seven faults test the habit of using a working peer as the reference. Blueprint (instructor only): 4.6, 6.1, 6.2, 6.5, 6.6, 4.4, 5.2.b, 4.2, 4.1, 5.1.b, 3.3.d, 1.4, 3.3.c (domains 1, 3, 4, 5, 6).

Design decisions (all in favour of teaching ENCOR):
- **CR1 uses `track N shutdown`, not `track N decrement` with the 30 s `preempt delay`.** With decrement the backup waits the full preempt delay before taking over from a master that is still advertising (measured: VLAN 50 master moved 31 s after the track went Down), which cannot meet "within 10 s". `shutdown` makes the group leave (INIT, priority-0 advertisement); the peer is master under 1 s later. On return the group re-enters BACKUP and preempts after the 30 s delay.
- **CR3 is a child policy with `bandwidth percent 30` / `10` plus `set dscp`, with no shaper in the end state.** A CML link never congests, so the proof wraps it in a test-only parent (`shape average 24000`, child `PM-CORE-EDGE`), removed afterwards; the shaper also starves the CR1 SLA probe under load (with 64000 and a ping flood CORE1 track 11 went Down and VRRP 50 left). Debrief on R5: `bandwidth` is a minimum that a class may exceed when the others are idle, not a cap; in V9 bulk still carried about 20 % of the packets (3064 of 15053, OPS 73 %) against its 10 % floor. `police cir percent 10` on the bulk class is an accepted alternative that also passes R5: it caps bulk unconditionally, not only under congestion. Debrief: that is why a control-plane policy such as CR5's CoPP must protect the probe traffic that CR1's failover depends on.
- **CR5: reject and amend, the end state keeps the original CoPP.** The amended policy restores `CM-MONITOR` ahead of `CM-ICMP`, so the final configuration of both edges equals the start.
- F6 is the template's explicit `no ip http secure-server` (the cat8000v enables HTTPS by default); F7 therefore gives HTTP 403 (not refused) once F6 is fixed. `CP-MGMT` on HQ-EDGE2 permits TCP 443 from MGMT1 so that CoPP `CM-UNDESIRABLE` (TCP 443, drop) does not silently kill RESTCONF.

## Intentional Faults

| ID | Device | Change | Symptom |
|---|---|---|---|
| F1 | HQ-EDGE2 | IP SLA 20 `icmp-echo 203.0.113.11` (typo for ISP-B's probe address 203.0.113.1) | track 20 Down from boot (0 successes, Timeout); EDGE2's static default never installs and it originates no default; with ISP-A down nobody originates a default: CORE1/CORE2 `% Network not in table`, PC1/PC2 100 % loss, traceroute stops at 10.10.10.2 (TK1) |
| F2 | HQ-EDGE2 | Gi2 (to CORE2) and Gi3 (to EDGE1) lack `ip nat inside` (only Gi4 has it) | latent until F1 is fixed: with ISP-A down, inside traffic leaves Gi1 untranslated (10.x), ISP-B has no path back; PC1 traceroute reaches 10.10.255.67 then `* * *`; `show ip nat statistics` Hits 0 Misses 0 (series with F1) |
| F3 | HQ-EDGE2 | no `ip flow monitor FM-EDGE input` on any interface | empty cache, exporter sent 0; DC-NMS1 sees only EDGE1 (parallel) |
| F4 | HQ-CORE2 | `logging host 10.50.50.15 vrf MGMT` (the collector is .51) | nothing from 10.10.99.3 on DC-SYSLOG1; DC-RTR1 ARP for .15 Incomplete (TK2, parallel) |
| F5 | HQ-CORE2 | `radius server DC-AAA1 ... auth-port 1645 acct-port 1646` | DC-AAA1 (1812/1813 only) logs nothing for CORE2; CORE2 marks the server dead (`%RADIUS-4-RADIUS_DEAD`), falls back to local: `netadmin` refused, `admin` works (TK2, parallel) |
| F6 | HQ-EDGE2 | `restconf` present, `no ip http secure-server` (hardening template) | TCP 443 refused; nginx Not Running, confd Running (TK3, first) |
| F7 | HQ-EDGE2 | `ip http access-class ipv4 API-HOSTS` where `API-HOSTS` permits 10.90.50.31 (MGMT1's old pod address) | after F6, HTTP 403 from 10.50.50.31 (series) |

Not faults (red herrings): cat8000v interface names; the transient DMI `lock-denied` 409 after CLI changes on EDGE2 (not reproducible on demand; read the `error-tag`, retry a bounded number of times); DIST2 as VLAN 20 STP root with CORE2 as VLAN 20 master (aligned); IGMP snooping off in VLANs 20/50; BGP to ISP-B up with prefixes received; video from PC3 from boot.

## Diagnosis / Methodology

**TK1 (failover and flows).** Reproduce the drill first (cable pull of EDGE1 e0/0 and PROV-ISP1 e0/0): CORE1 `show ip route 0.0.0.0` is `% Network not in table` within 2 s, CORE2 and EDGE2 also; PC1/PC2 100 % loss, PC1 traceroute ends at 10.10.10.2 `!H`. Candidates: (a) BGP to ISP-B: `show bgp ipv4 unicast summary` on EDGE2 is established with prefixes, eliminated (the default is static, not BGP). (b) OSPF default origination: EDGE2 `show ip route static` has no default; `show track 20` Down; `show ip sla statistics 20` Timeout, 0 successes; `show ip sla configuration 20` target 203.0.113.11 against ISP-B's 203.0.113.1 (compare EDGE1's SLA 10 target 198.51.100.1, the ISP's loopback): F1. (c) F2 appears only after F1: with the default restored (CORE1 gets it 34 s after the SLA is recreated: `delay up 30` on the track), PC1 ping is still 100 % lost, traceroute reaches EDGE2 Gi2 (10.10.255.67) then `* * *`; `show ip nat statistics` Hits 0 Misses 0 and lists only Gi4 as inside; comparing with EDGE1 (inside e0/1-3) points at F2. Fixing F2 alone changes nothing (no default), so the series is proven in both orders. (d) Edge ACL/CoPP: return traffic never arrives (ISP-B has no route to 10.x), eliminated. (e) Flows: DC-NMS1 receives EDGE1's exports (tshark: only 10.10.254.5); `ping vrf MGMT 10.50.50.60` from EDGE2 works and the exporter has `vrf MGMT`, so path and collector are eliminated; `show flow interface` is empty (EDGE1 lists e0/0-2) and the cache is empty: F3. Note the exporter sends no template without a monitor on an interface.
**TK2.** `ping vrf MGMT 10.50.50.51` from CORE2 works and OSPF 99 is FULL (path eliminated). `show logging` on CORE2: host 10.50.50.15 against CORE1's .51; DC-RTR1 `show ip arp vrf MGMT 10.50.50.15` Incomplete: F4. Logins: CORE1 netadmin works; DC-AAA1's log shows nothing from CORE2; `show aaa servers` on CORE2 shows auth-port 1645, requests timing out and `RADIUS_DEAD`; break-glass `admin` works from the same host, so SSH and the VTY ACL are eliminated: F5. The DC servers may not be changed (constraint), so making DC-AAA1 listen on 1645 is not a fix.
**TK3.** MGMT1 pings 10.10.254.9 and SSH works (reachability eliminated); `show ip http server status`: HTTP and HTTPS Disabled; `show platform software yang-management process`: confd Running, nginx Not Running (so the RESTCONF/DMI process itself is eliminated): F6. After `ip http secure-server`, TCP 443 answers at once and `curl` returns HTTP 403; `show ip access-lists API-HOSTS` lists only 10.90.50.31 with no match for 10.50.50.31: F7.
**Wrong-fix traps (tried once, recorded):** `default-information originate always` on EDGE2 (with both ISPs down CORE1/CORE2 keep a default of metric 30, EDGE2 has `% Network not in table`, PC1 traceroute dies at 10.10.255.67: violates V3); a second `logging host 10.50.50.51` without `vrf MGMT` is accepted and nothing from 10.10.99.3 reaches DC-SYSLOG1 (V6); removing the access class or `ip http server` breaks V7; a CLI change of EDGE-IN-V4 on EDGE2 breaks the constraint; POST of an existing ACE sequence returns 409 `data-exists`. An SLA entry running on cat8000v cannot be edited ("already running and cannot be modified"): `no ip sla 20` and recreate.

**CR notes.** CR1: each core probes its own edge's core-facing address (CORE1 10.10.255.65, CORE2 10.10.255.67) every 2 s; `threshold` must not exceed `timeout` (a config block hid `Scheduling a probe with threshold 5000 ms greater than timeout 1000 ms is not allowed` and the track stayed Down). Interface tracking would never fire for a silent failure (CORE2 e0/3 stayed `up, line protocol up` after the EDGE2 node stop). The HQ-EDGE2 silent failure in the replay is `link stop` of CORE2-EDGE2 (measured, Failure / Recovery table); a node stop of EDGE2 is not used, because the router then runs its stored day-0 again and the student's fixes and API trust are lost. Gateway tracking, two valid answers: (1) `track N shutdown` on the VRRP group, as in the reference, gave a gateway move within the V1 limit; (2) the owned-skill alternative, tracking with decrement, only lowers the master's priority and the earlier decrement variant moved VLAN 50 31 s after the track went Down (derived: the backup takes over only after its preempt delay of 30 s), which fails V1's 10 s. Alternative (2) can be accepted only as a documented deviation if the student shortens the backup's preempt delay and keeps 30 s on the master so the gateway still returns after 30 s (derived, not measured); grade a decrement-only design with a 31 s move as failing V1. The applet pattern is `VRRP-6-STATE:` (the message is %VRRP-6-STATE) and the evidence file is read with `more unix:/gw-evidence.txt`. CR2: DR = VRRP master per VLAN (`dr-priority 200` on CORE2 e0/2.20 and CORE1 e0/1.50). CR4: the GET of the whole ACL returns `Cisco-IOS-XE-acl:extended` as a list. CR5: test on one edge with the 3x `ping -q -i 0.01 -s 0 -w 25 198.51.100.65` burst from PC1.

## Solution Configuration

Each block is a config block (no `configure terminal`), proven on the original lab and again on the re-imported lab.

### HQ-EDGE2 (TK1, TK3)

```
interface GigabitEthernet2
 ip nat inside
interface GigabitEthernet3
 ip nat inside
no ip sla 20
ip sla 20
 icmp-echo 203.0.113.1 source-interface GigabitEthernet1
  frequency 5
ip sla schedule 20 life forever start-time now
interface GigabitEthernet1
 ip flow monitor FM-EDGE input
interface GigabitEthernet2
 ip flow monitor FM-EDGE input
interface GigabitEthernet4
 ip flow monitor FM-EDGE input
ip http secure-server
ip access-list standard API-HOSTS
 no 10
 10 permit 10.50.50.31
```

Order matters for TK1 only in the drill: F1 and F2 are both needed. After F6 the first `curl` can still show 403 for a few seconds (the access-class edit applies late). Then the trust step (TK3 follow-up, V7), run on AUTO-MGMT1 in the background (about 2 minutes, it creates trustpoint `API-TP` with CN and SAN `edge2.hq.veridian.example` over SSH as `netadmin` and stores `/home/cisco/trust/edge2.pem`):

```
nohup sh /home/cisco/trust/fetch-edge2-cert.sh > /tmp/fetch.log 2>&1 &
cd /home/cisco/auto && /home/cisco/venv/bin/python rc_get.py | head -3      # HTTP status: 200
```

### HQ-CORE2 (TK2, CR1, CR2, CR3)

```
ip sla 12
 icmp-echo 10.10.255.67 source-interface Ethernet0/3
  threshold 1000
  timeout 1000
  frequency 2
ip sla schedule 12 life forever start-time now
track 12 ip sla 12 reachability
interface Ethernet0/2.20
 vrrp 20 address-family ipv4
  track 12 shutdown
interface Ethernet0/2.50
 vrrp 50 address-family ipv4
  track 12 shutdown
event manager applet GW-EVIDENCE
 event syslog pattern "VRRP-6-STATE:"
 action 0.1 cli command "enable"
 action 1.0 cli command "show clock | append unix:gw-evidence.txt"
 action 2.0 cli command "show vrrp brief | append unix:gw-evidence.txt"
 action 3.0 cli command "show track 12 | append unix:gw-evidence.txt"
 action 4.0 cli command "show ip route 0.0.0.0 | append unix:gw-evidence.txt"
 action 5.0 syslog msg "Gateway state change evidence captured"
ip access-list standard OPS-VIDEO
 permit 239.10.20.0 0.0.0.255
ip multicast-routing
ip pim rp-address 10.255.10.100
interface Loopback10
 ip address 10.255.10.100 255.255.255.255
 ip ospf 1 area 0
 ip pim sparse-mode
interface Loopback0
 ip pim sparse-mode
interface Ethernet0/0
 ip pim sparse-mode
interface Ethernet0/2.50
 ip pim sparse-mode
 ip pim query-interval 1
interface Ethernet0/2.20
 ip pim sparse-mode
 ip pim query-interval 1
 ip pim dr-priority 200
 ip igmp access-group OPS-VIDEO
ip msdp peer 10.255.10.1 connect-source Loopback0
ip msdp originator-id Loopback0
ip access-list extended CR3-OPS
 permit tcp 10.10.20.0 0.0.0.255 any eq 443
ip access-list extended CR3-BULK
 permit tcp 10.10.50.0 0.0.0.255 any eq 20
 permit tcp 10.10.50.0 0.0.0.255 any eq 21
class-map match-all CM-OPS-APP
 match access-group name CR3-OPS
class-map match-all CM-BULK-XFER
 match access-group name CR3-BULK
policy-map PM-CORE-EDGE
 class CM-OPS-APP
  set dscp af21
  bandwidth percent 30
 class CM-BULK-XFER
  set dscp cs1
  bandwidth percent 10
 class class-default
  fair-queue
interface Ethernet0/3
 service-policy output PM-CORE-EDGE
no logging host 10.50.50.15 vrf MGMT
logging host 10.50.50.51 vrf MGMT
radius server DC-AAA1
 address ipv4 10.50.50.52 auth-port 1812 acct-port 1813
```

### HQ-CORE1 (CR1, CR2, CR3)

```
ip sla 11
 icmp-echo 10.10.255.65 source-interface Ethernet0/3
  threshold 1000
  timeout 1000
  frequency 2
ip sla schedule 11 life forever start-time now
track 11 ip sla 11 reachability
interface Ethernet0/1.20
 vrrp 20 address-family ipv4
  track 11 shutdown
interface Ethernet0/1.50
 vrrp 50 address-family ipv4
  track 11 shutdown
event manager applet GW-EVIDENCE
 event syslog pattern "VRRP-6-STATE:"
 action 0.1 cli command "enable"
 action 1.0 cli command "show clock | append unix:gw-evidence.txt"
 action 2.0 cli command "show vrrp brief | append unix:gw-evidence.txt"
 action 3.0 cli command "show track 11 | append unix:gw-evidence.txt"
 action 4.0 cli command "show ip route 0.0.0.0 | append unix:gw-evidence.txt"
 action 5.0 syslog msg "Gateway state change evidence captured"
interface Ethernet0/0
 ip pim sparse-mode
interface Ethernet0/1.50
 ip pim dr-priority 200
ip msdp peer 10.255.10.2 connect-source Loopback0
ip msdp originator-id Loopback0
ip access-list extended CR3-OPS
 permit tcp 10.10.20.0 0.0.0.255 any eq 443
ip access-list extended CR3-BULK
 permit tcp 10.10.50.0 0.0.0.255 any eq 20
 permit tcp 10.10.50.0 0.0.0.255 any eq 21
class-map match-all CM-OPS-APP
 match access-group name CR3-OPS
class-map match-all CM-BULK-XFER
 match access-group name CR3-BULK
policy-map PM-CORE-EDGE
 class CM-OPS-APP
  set dscp af21
  bandwidth percent 30
 class CM-BULK-XFER
  set dscp cs1
  bandwidth percent 10
 class class-default
  fair-queue
interface Ethernet0/3
 service-policy output PM-CORE-EDGE
```

Save both cores (`write memory`). HQ-EDGE1 needs no change; HQ-DIST/ACC need none.

### CR2 viewer and gap clock (HQ-PC2)

```
iperf -s -u -B 239.10.20.1 -i 1
sudo tcpdump -tt -n -l -i eth0 dst 239.10.20.1      # gaps > 0.25 s listed with awk
```

### CR3 test-only parent shaper (remove afterwards)

```
policy-map PM-CORE-EDGE-SHAPE
 class class-default
  shape average 24000
  service-policy PM-CORE-EDGE
interface Ethernet0/3
 no service-policy output PM-CORE-EDGE
 service-policy output PM-CORE-EDGE-SHAPE
! ... run the load, read `show policy-map interface Ethernet0/3 output`, then:
interface Ethernet0/3
 no service-policy output PM-CORE-EDGE-SHAPE
 service-policy output PM-CORE-EDGE
no policy-map PM-CORE-EDGE-SHAPE
```

Load: `while true; do nc -w 1 192.0.2.200 443 </dev/null; done` x4 on HQ-PC2 and the same to port 21 x8 on HQ-PC3 (stop with `pkill -f "while true; do nc"`).

### CR4 script (AUTO-MGMT1, `/home/cisco/auto/cr4_add_ace.py`)

If the first run fails with HTTP 502 (seen for several minutes right after boot and the trust step), RESTCONF on HQ-EDGE2 is not ready yet: wait a few minutes and re-run. The script reads before it writes, so a failed run changed nothing and re-running is safe.

```
#!/usr/bin/env python3
"""CR4 reference: insert the partner-server echo-reply permit into EDGE-IN-V4 on HQ-EDGE2 by RESTCONF
(sequence 135, between the pinned-target permit 130 and the deny 140), then check both edges."""
import sys
import requests
from netmiko import ConnectHandler

HOST = "edge2.hq.veridian.example"
CERT = "/home/cisco/trust/edge2.pem"
AUTH = ("apiuser", "Api#Pass2026")
BASE = f"https://{HOST}/restconf/data/Cisco-IOS-XE-native:native/ip/access-list/extended=EDGE-IN-V4"
HDR = {"Accept": "application/yang-data+json", "Content-Type": "application/yang-data+json"}
ACE = {"Cisco-IOS-XE-acl:access-list-seq-rule": [{
    "sequence": "135",
    "ace-rule": {"action": "permit", "protocol": "icmp",
                 "host-address": "203.0.113.50", "host": "203.0.113.50",
                 "dst-host-address": "203.0.113.65", "dst-host": "203.0.113.65",
                 "named-msg-type": "echo-reply"}}]}


def edge2_sequences():
    r = requests.get(BASE, auth=AUTH, headers=HDR, verify=CERT, timeout=15)
    r.raise_for_status()
    acl = r.json()["Cisco-IOS-XE-acl:extended"]
    acl = acl[0] if isinstance(acl, list) else acl
    return [x["sequence"] for x in acl["access-list-seq-rule"]]


def main():
    if "135" in edge2_sequences():
        print("ACE 135 already present (sequence only, body not compared), no write sent")
    else:
        r = requests.post(BASE, json=ACE, auth=AUTH, headers=HDR, verify=CERT, timeout=15)
        print("POST", r.status_code, r.text.strip()[:200])
        if r.status_code not in (201, 204):
            sys.exit(2)
    seqs = edge2_sequences()
    ok2 = "135" in seqs and seqs.index("130") + 1 == seqs.index("135") == seqs.index("140") - 1
    print("EDGE2 sequences around the change:", seqs[seqs.index("130"):seqs.index("140") + 1], "->", "OK" if ok2 else "FAIL")
    dev = ConnectHandler(device_type="cisco_ios", host="10.10.254.5", username="netadmin", password="netpass")
    out = dev.send_command("show ip access-lists EDGE-IN-V4 | include 203.0.113.50")
    dev.disconnect()
    ok1 = out.strip() == ""
    print("EDGE1 lines mentioning 203.0.113.50:", repr(out.strip()), "->", "OK (unchanged)" if ok1 else "FAIL")
    sys.exit(0 if ok1 and ok2 else 1)


if __name__ == "__main__":
    main()
```

Run `/home/cisco/venv/bin/python cr4_add_ace.py` after the trust step. Result of the first run: POST 201. The script reads first and sends nothing when sequence 135 already exists, so a second run must exit 0 and add no `%DMI-5-CONFIG_I` log line (a design the course teaches in LAB-065: POST cannot "ensure" an object exists; the earlier unconditional-POST version exited 2 on a 409 `data-exists`; the read-first guard was added later and has not been re-run on the bench); `DELETE .../access-list-seq-rule=135` returns 204 (a first DELETE right after a CLI change returned 409, the DMI lock).

### CR5 (HQ-EDGE1 or HQ-EDGE2; end state = original CoPP)

The proposal moves `CM-ICMP` (8000 bps) to the top of `PM-COPP`, ahead of `CM-MONITOR`, which carries the IP SLA 10 echo replies from 198.51.100.1. Test on HQ-EDGE1 (the proposal is rebuilt in order because IOS has no insert-before):

```
policy-map PM-COPP
 no class CM-ICMP
 no class CM-ROUTING
 no class CM-MONITOR
 no class CM-MGMT
 no class CM-UNDESIRABLE
 no class class-default
 class CM-ICMP
  police cir 8000 bc 1500 conform-action transmit exceed-action drop
 class CM-ROUTING
  police cir 64000 bc 8000 conform-action transmit exceed-action transmit
 class CM-MONITOR
  police cir 8000 bc 1500 conform-action transmit exceed-action transmit
 class CM-MGMT
  police cir 64000 bc 8000 conform-action transmit exceed-action drop
 class CM-UNDESIRABLE
  police cir 8000 conform-action drop exceed-action drop
 class class-default
  police cir 16000 bc 4000 conform-action transmit exceed-action drop
```

Verdict: reject (evidence in Verification). Amendment (also the clean-up of the test): restore the original order; with the remaining classes in place only `CM-ICMP` and `class-default` need to move:

```
policy-map PM-COPP
 no class CM-ICMP
 no class class-default
 class CM-ICMP
  police cir 8000 bc 1500 conform-action transmit exceed-action drop
 class class-default
  police cir 16000 bc 4000 conform-action transmit exceed-action drop
```

The class order of `show policy-map control-plane` is then ROUTING, MONITOR, MGMT, UNDESIRABLE, ICMP, class-default (as at the start). The end state keeps both edges' CoPP unchanged.

## Verification

Captured on a fresh import after the solution, and with the H5 files cold-booted on CORE1, CORE2 and EDGE2 (same results). Earlier per-fault evidence is from the original lab.

```
HQ-EDGE2# show track brief           20 ip sla 20 reachability  Up
HQ-EDGE2# show ip nat statistics     Outside: GigabitEthernet1  Inside: GigabitEthernet2, GigabitEthernet3, GigabitEthernet4
HQ-EDGE2# show flow interface        Interface GigabitEthernet1 / GigabitEthernet2 / GigabitEthernet4 (FM-EDGE input)
HQ-EDGE2# show ip http server status HTTP server status: Disabled / HTTP secure server status: Enabled
HQ-EDGE2# show ip access-lists EDGE-IN-V4 | include echo-reply
    130 permit icmp host 203.0.113.1 host 203.0.113.65 echo-reply (118 matches)
    135 permit icmp host 203.0.113.50 host 203.0.113.65 echo-reply
    140 deny icmp any host 203.0.113.65 echo-reply log
HQ-EDGE2# ping 203.0.113.50 source GigabitEthernet1       Success rate is 100 percent (5/5)
HQ-CORE1# show track brief           11 ip sla 11 reachability  Up      HQ-CORE2: 12 ... Up
HQ-CORE1# show vrrp brief            Et0/1.20 BACKUP (10.10.20.3) / Et0/1.50 MASTER / Et0/1.99 MASTER
HQ-CORE2# show vrrp brief            Et0/2.20 MASTER / Et0/2.50 BACKUP / Et0/2.99 BACKUP
both cores# show ip msdp peer        State: Up
HQ-CORE2# show ip pim interface      Et0/2.20 DR priority 200 (DR 10.10.20.3), Et0/2.50, Et0/0 (query interval 1/30)
HQ-CORE2# show aaa servers           auth-port 1812, acct-port 1813, State: current UP
HQ-CORE2# show logging | include Logging to 10      Logging to 10.50.50.51 (MGMT)
both cores# show policy-map interface Ethernet0/3 output    Class-map: CM-OPS-APP / CM-BULK-XFER / class-default
AUTO-MGMT1$ cr4_add_ace.py           POST 201; EDGE2 sequences ['130','135','140'] -> OK; EDGE1 lines mentioning 203.0.113.50: '' -> OK (unchanged)
AUTO-MGMT1$ curl -sk https://10.10.254.9/restconf/    HTTP 401 without credentials; rc_get.py with edge2.pem: HTTP status: 200
```

Per-requirement evidence (original build):
- **V2/TK1.** F2 alone: drill still fails (no default anywhere, `% Network not in table`, PC1/PC2 100 % loss, traceroute `!H` at 10.10.10.2). F1 alone: default on CORE1 34 s after the SLA is recreated (metric 30, via CORE2 and EDGE1 at equal cost); PC1 ping 100 % lost, traceroute reaches 10.10.255.67 then `* * *`, NAT Hits 0 Misses 0. F1 and F2 fixed: PC1/PC2 `ping 192.0.2.200` 3/3 via EDGE2, traceroute hop 5 203.0.113.64, translations `192.0.2.65 <- 10.10.10.101 / 10.10.20.102`. Re-run after CR5 amendment: 3/3.
- **V3.** ISP-A and ISP-B both disconnected (EDGE2 Gi1 and PROV-ISP2 e0/0 shut): `% Network not in table` on CORE1, CORE2 and EDGE2 within 2 s. ISP-B back: default on CORE1 after 45 s; ISP-A back: default via EDGE1 metric 10 after 45 s.
- **F3.** After `ip flow monitor FM-EDGE input` on Gi1/Gi2/Gi4: cache Flows added 5; exporter Successfully sent 4, Records added 2; DC-NMS1 tshark 80 s: 2 packets from 10.10.254.5 and 3 from 10.10.254.9. Before: sent 0, Records added 0, no template either.
- **V6/V5 (F4, F5).** Wrong fix `logging host 10.50.50.51` (no vrf): accepted, nothing arrives. Right fix: DC-SYSLOG1 receives from 10.10.99.3 within 1 s. After F5: `show aaa servers` UP; `netadmin` SSH to CORE2 privilege 15; DC-AAA1 log `Login OK: [netadmin]` and accounting start from nas 10.10.99.3.
- **V7 (F6, F7).** After `ip http secure-server`: TCP 443 answers at once and `curl /restconf/` gives HTTP 403; `nginx Running`, `confd Running`. After the `API-HOSTS` edit: the first curl a few seconds later still 403, the next 200 (`/restconf/data/Cisco-IOS-XE-native:native/hostname` with `apiuser`); bad password 401; `netadmin` (a RADIUS user) 401 (RESTCONF uses the local list). RESTCONF in VRF MGMT on 443 works (10.10.254.9 is Gi2.99 in VRF MGMT). Trust: `edge2.pem` stored about 2 minutes after the fix, `rc_get.py` HTTP 200 with `verify=edge2.pem`.
- **V8.** Before: `ping 203.0.113.50 source GigabitEthernet1` 0/5, `deny 140` +5 matches. After: 5/5, 135 between 130 and 140, `%DMI-5-CONFIG_I: Configured from NETCONF/RESTCONF by apiuser` in the log; repeat POST 409 `data-exists`.
- **V4.** Viewer `iperf -s -u -B 239.10.20.1 -i 1` on HQ-PC2, last 60 s: 0 lost of 2918 datagrams. CORE2 `show ip msdp sa-cache` holds (10.10.50.103, 239.10.20.1) from 10.255.10.1; (S,G) incoming e0/2.50 to e0/2.20 Forward.
- **V9.** Load: 4 loops to 192.0.2.200:443 from HQ-PC2 and 8 loops to :21 from HQ-PC3, test parent shaper 24000, about 85 s: CM-OPS-APP 10972 packets marked af21, 3 drops; CM-BULK-XFER 3064 packets marked cs1, queue depth 44, 20 drops; class-default 1017, 0 drops. With a 64000 shaper there are no drops (7463 AF21, 1940 CS1 in 50 s). The plain policy marks and counts but never congests.
- **V10.** Baseline PM-COPP with 3x `ping -q -i 0.01 -s 0 -w 25 198.51.100.65` from HQ-PC1: track 10 stays Up (2 changes), CM-ICMP exceeded 7487. Proposal (CM-ICMP first), same flood: track 10 Up to Down 16 s after the flood starts, CORE1 default moves to EDGE2 (metric 30), Down to Up 60 s later; CM-ICMP exceeded 41042. Amended (original order): no track change in the same flood, CM-ICMP exceeded 88602.
- **V11.** `more unix:/gw-evidence.txt` on each core holds, per VRRP state change, the clock, `show vrrp brief`, the track and the default route; one `%HA_EM-6-LOG: GW-EVIDENCE: Gateway state change evidence captured` per change appears on DC-SYSLOG1 (from 10.10.99.2 and 10.10.99.3).

## Failure / Recovery Behaviour

Gateway failover is by `track N shutdown` on an IP SLA probe (frequency 2 s, timeout 1000 ms) to the core's own edge router. Failure methods are named in each row. T0 is the host clock before the call, T1 after it returned (3.6-4.7 s), events are read from the router log (UTC; router clocks agree with the host within about 0.4 s).

| Scenario (trigger, end condition) | Runs (raw, s) | Documented range | Basis |
|---|---|---|---|
| Cable pull (shutdown both ends) CORE1-EDGE1: shutdown to gateway 50 MASTER on CORE2 | 4, 3, 6 | 3-7 | SLA frequency 2 s + timeout 1 s + priority-0 advert; derived bound 4 s plus poll granularity. PC3 lost 0 pings, PC2 at most 1 per run |
| Same, return (no shutdown both ends) to CORE1 MASTER again | 40, 38, 40 | 35-50 | track Up after link up + preempt delay 30 s |
| Cable pull CORE2-EDGE2: gateway 20 to CORE1 | 3, 6, 5 | 3-7 | as above |
| Same, return to CORE2 MASTER | 48, 47, 48 | 40-55 | cat8000v carrier-up is slower |
| Silent failure (`link stop` CORE1-EDGE1): track Down/INIT after T1 | 4.4-4.8, 4.8, 7.0 (9.1, 8.5, 10.6 after T0); peer MASTER 0.6 s after the Down in each run | 4-7 after the call returns; under 11 after the call starts | SLA schedule + timeout; measured from T0 the V1 limit of 10 s is hit once at 10.6, so the allowance is stated from the end of the call |
| Same, return (`link start`) track Up after S1; then MASTER | 0.9, 3.2, 3.3; then 30.8, 30.6, 31.1 (other runs: 6.3, 1.1, 4.2) | track 1-7, MASTER 30-32 s after Track Up | preempt delay minimum 30 |
| Silent failure `link stop` CORE2-EDGE2: Down after T1 | 6.2, 6.4 (9.7, 9.9 after T0); CORE1 MASTER 0.6 s after | 6-7 after the call returns | as above |
| Same, return: Track Up after S1; MASTER after Track Up | 4.9, 5.1; 30.6 | 5 s; 30-31 s | cat8000v slow to carrier-up |
| EDGE1 node stop (silent): CORE2 gateway MASTER (VLAN 50 moves to CORE2) | 10.3 s after the call started (6.3 s after it returned) | under 11 after the call starts; 6-7 after it returned | the V1 10 s is counted from the call returning; 1 run. Node stop returns slowly, so T0 includes the call |
| EDGE2 node stop (silent; reference measurement only, not a method for students or for the replay, use the `link stop` row above): CORE2 track 12 Down; CORE1 VLAN 20 MASTER | Down 3.6 after T1 (7.9 after T0), MASTER 0.6 s later; CORE2 e0/3 stayed up/up | under 9 after the stop starts | one run (cat8000v stop is slow to return); interface tracking would never fire |
| EDGE2 node start: CORE2 track Up; VLAN 20 MASTER again | 222 s; then 31.2 s | about 4 minutes + 30 s | cat8000v boot and CVAC |
| ISP-A cable pull: default moves to EDGE2 (metric 30) | 2 | 2-3 | interface down removes the static at once |
| ISP-B path back (SLA up + `delay up 30`) / ISP-A back | 34-45 / 45 | 30-50 | SLA frequency 5 s + `delay up 30` |
| CORE2 node stop (VLAN 20 DR + master): video gap | 2.39, 2.42, 2.49 (+0.47 once) | 2-3 | PIM hello 1 s, holdtime 3.5 s for the DR change |
| CORE2 node start: video gap above 0.25 s | none in 3 runs (CORE2 MASTER again 11-17 s after the start) | none | |
| CORE1 node stop (VLAN 50 DR): video gap above 0.25 s | none in 3 runs | none | CORE1 keeps the (S,G) via flooded VLAN 50 (LAB-057) |
| DC-AAA1 node stop | netadmin refused on CORE1; `admin` / `Cisco123!` privilege 15 on CORE1, CORE2, EDGE1, EDGE2 (10-11 s first login while RADIUS is dead, 1 s once marked dead); after node start (33 s to BOOTED) netadmin works again and `admin` is rejected by RADIUS | | reject is final |

Cable-pull rows are measured from the call start (scripted CLI latency adds about 1 s to event-to-event values, so event-to-event times can read 1-5 s against the documented 3-7).

TK device-level evidence (moved from the LAB.md monitoring excerpt): the NMS shows one flow exporter (F3: no flow monitor is applied on EDGE2, so its exporter sends nothing), DC-SYSLOG1 has no HQ-CORE2 messages (F4), and EDGE2 `track 20` has been Down since boot (F1). Find these with the device commands in the TK1/TK2 solutions above.

Notes. The earlier decrement variant (kept as a teaching contrast) moved VLAN 50 31 s after the track went Down. A node stop of HQ-EDGE1 was recovered by OSPF reroute (4 s dead) before the gateway moved: PC3 lost 3-4 pings. Whole-lab cold boot: all 19 nodes BOOTED in about 4 minutes on an idle server; HQ-EDGE2's day-0 is effective about 4-5 minutes after start (`cml-rest.sh wait` reports BOOTED when the console shows `%CVAC-4-CONFIG_DONE`; after a cat8000v `node stop`/`start` the log says `FILE_IGNORED ... checksum unchanged` and `wait` keeps reporting not-ready, although the stored day-0 runs). A wiped DC node gets a new MAC, DC-RTR1 keeps a stale ARP entry for four hours (`clear arp-cache` takes no VRF): wipe DC-AAA1/DC-SYSLOG1 together with DC-RTR1. Opening EDGE2's console while the day-0 is being applied can leave a stale session that makes a scripted console login fail with "Bad Password" for HQ-EDGE2: from MGMT1 `ssh netadmin@10.10.254.9`, `clear line 0`, Enter.

## Answers to Analysis Questions

**Q1.** TK1: BGP to ISP-B was established with prefixes, so the "ISP-B is broken" path is out; the default is static, tracked, and the track was Down with 0 SLA successes. Flows: the collector receives EDGE1 and `ping vrf MGMT` works, so the path is out; `show flow interface` was empty. TK2: `ping vrf MGMT` and OSPF 99 prove the path; the break-glass login from the same host rules out SSH and the VTY ACL. TK3: ping and SSH to the management address prove reachability; `confd` Running rules out the RESTCONF process.
**Q2.** EDGE1 is the reference for EDGE2 (SLA target, NAT inside list, `show flow interface`), CORE1 for CORE2 (logging host, RADIUS ports). The comparison misleads where the two differ by design: EDGE2's interfaces are named Gi1-Gi4 and its default has metric 30, CORE1's VLAN priorities mirror CORE2's, and EDGE1's NAT inside list is e0/1-3 while EDGE2's correct list is Gi2-Gi4 (DMZ included). Copying a peer's SLA target would also have been wrong (203.0.113.1 against 198.51.100.1).
**Q3.** Fixes that restored service: F1 and F2 together (the default and the translation), F3 flows, F4 syslog, F5 central logins, F6 and F7 the API. CR1, CR2 and CR3 restore redundancy or quality, not service: proved by the drills (cable pull and silent failure of each edge, node stop of each core, ISP-A and ISP-B disconnects) with measured timings, and by V1/V2 re-run after CR5.
**Q4.** The API validates the body against the model before it touches the configuration (a wrong leaf or a duplicate sequence is a 400/409 with an `error-tag`, not a half-applied line), leaves an audit trail (`%DMI-5-CONFIG_I ... by apiuser`), is repeatable and checkable by a script (the script verifies both edges), and keeps the edge ACL change off the CLI as the constraint requires.
**Q5.** The proposal was tried on one edge only, with the flood of the right size and a stop condition (-w 25), with the evidence listed first (`show track 10` history, `%TRACK-6-STATE`, CoPP drops), and the original order was restored afterwards; the baseline run with the original policy was done first so that the difference is attributable.
**Q6.** After a platform migration: compare every per-interface feature (NAT inside/outside, flow monitors, ACLs, service policies) with the old router or its twin; probe targets of every IP SLA (a track Down since the migration is a symptom, not a status); the management plane (syslog host and VRF, AAA ports, API enablement and access control, certificate); and a failover drill, because redundancy faults are latent.
**Instructor debrief.** The NAT fault shows only in the drill because EDGE1 originates the default at metric 10 in normal operation, so EDGE2 never forwards user traffic. The server log is empty for one login cause because the requests never reach DC-AAA1's listening port: a RADIUS server that is not asked has nothing to log, so the evidence for F5 is on the client (`show aaa servers`). CR5's test needs TK1 fixed first: with F1 and F2 present a false failover of the proposal is a total outage instead of a measurable moving default (the student must not leave that in place).

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-18 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), cat8000v (IOS XE 17.16.1a), external_connector, iol-xe (IOS XE 17.16.1a), ioll2-xe (IOS XE 17.16.1a), net-tools, radius, syslog, ubuntu (Ubuntu 24.04), unmanaged_switch |
