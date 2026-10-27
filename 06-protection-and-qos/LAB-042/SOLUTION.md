# LAB-042 — Solution

## Summary

An X (integration) lab with one planted audit deviation (F1). The student closes the edge project's three findings on a live dual-ISP edge: a 10-minute acceptance audit of HQ-EDGE2 against the management standard that finds and fixes one deviation (5.1.b, 5.2.a), a stateless ingress ACL pair in IPv4 and IPv6 (5.2.a, IPv6 ACLs), a control-plane policy sized from measurement (5.2.b), and flow export into VRF MGMT with two monitor placements (4.2); then proves each control from counters, logs and flow records without breaking BGP, OSPF, HSRP, SLA tracking or NAT. The only designed "trap" is Q1: an anti-spoofing entry of 192.0.2.0/24 also denies the IX block 192.0.2.192/26 where PROV-SRV1 lives. Blueprint: 5.2.a:R, 5.2.b:P, 4.2:P, 5.1.b:R, IPv6:R. Platform notes: the edge design is stateless (no ZBFW in this lab: ZBFW and CBAC are not supported on iol-xe 17.16.1a, measured in a CML feature test, so the stateless design is confirmed), flow monitoring is IPv4 only here (fixed 15 s / 1800 s cache timeouts, so exports arrive within about a minute with `template data timeout 60`), unmanaged switches count against the licence (15 running nodes, lab runs alone).

Time estimate: 185 min (including the 10-minute audit; EDGE2's authenticated NTP syncs from boot, so its wait overlaps R2-R4). Build notes: the audit script has 21 lines (18 commands on three nodes, 5 on HQ-EDGE1, 9 on HQ-EDGE2, 4 on DC-NMS1, plus the 3 node headers) and takes 16 s of machine time; the two SSH password logins (central administrator and operator accounts) are manual (no `sshpass`, about 1 minute each). That the audit fits 10 minutes for a student (5 items x 2 devices, HQ-EDGE1 as the reference) is an estimate, not a timed student run. NTP: both edges reach `*~10.50.50.1` sys.peer about 25 minutes after boot (still `.INIT.` at 12 minutes, because DC-RTR1 itself is unsynchronised for its first minutes), so an audit run earlier judges the NTP item as "server configured with key 1, selection pending".

Build notes: FNF IPv4 only; CM-ROUTING and CM-MONITOR police with `transmit` for both conform and exceed (measure-only, they can never drop routing or probe replies; the rate is still configured so the counters show the load); the start state is generated from E2/H3 files and cold-boot proven rather than captured.

## Intentional Faults

One planted audit deviation (the lab stays X/N). The Q1 /24 mistake is a separate designed experiment (below).

| ID | Device | Change | Symptom |
|---|---|---|---|
| F1 | HQ-EDGE2 | SNMP group `NMSGROUP v3 auth access MGMT-HOSTS` and user `nmsuser ... v3 auth sha AUTHPASS123` with no `priv aes 128` (the access-switch form of the standard on a router) | Nothing is broken: DC-NMS1 polls EDGE2 at authNoPriv and gets `"HQ-EDGE2.veridian.example"`. `snmpget -v3 -l authPriv` against EDGE2 fails with `snmpget: Unsupported security level` while EDGE1 answers; `show snmp user` shows `Privacy Protocol: None`, `show snmp group` shows `security model:v3 auth` (EDGE1: AES128, `v3 priv`) |

Evidence path: the audit's SNMP check at the strongest level (authPriv) from DC-NMS1 fails on EDGE2 only, then `show snmp user nmsuser` and `show snmp group` on both routers. Every other standard item checks clean on EDGE2 (AAA server UP, logging to 10.50.50.51, NTP key 1, `MGMT-HOSTS` 10/20/40 and `transport input ssh` on the VTYs, port 23 refused, 22 open). Wrong fixes: deleting SNMP from EDGE2 (V1 fails), adding a v2c community (violates the standard).

Q1 experiment (designed, not a fault):

| ID | Device | Change | Symptom |
|---|---|---|---|
| (experiment) | HQ-EDGE1 EDGE-IN-V4 | `deny ip 192.0.2.0 0.0.0.255 any log` instead of the /25 + /26 pair | HQ-PC1 to PROV-SRV1 ping 3/3 lost, wget timeout, the /24 ACE counts the replies; restoring the two entries: 3/3 ok |

## Diagnosis / Methodology

Design path (what a good answer does, in order):

1. **Audit first (R1), about 10 minutes (estimate).** One check per standard item on both routers, HQ-EDGE1 as the reference. The scripted part is 21 lines (script below, 16 s machine time); the two SSH logins are typed by hand.
   - Accounts: `show running-config | section aaa|radius` on both (list `VTY group RADGRP local`, console `none`), `show aaa servers | include State` (`current UP`), manual SSH as `netadmin` (privilege 15) and `netops` (privilege 1).
   - Logging: `show logging | include [Ll]ogging to|Trap logging` (`10.50.50.51`, informational).
   - Monitoring access: `show snmp group | include security model`, `show snmp user | include Privacy` and an authPriv `snmpget` from DC-NMS1 to each router. **This is the only item that fails (F1).**
   - Time: `show ntp associations` and `show running-config | include ntp` (key 1; `*~10.50.50.1` only after about 25 min).
   - Management sources: `show running-config | section line vty`, `show ip access-lists MGMT-HOSTS`, `nc -zv -w 3 10.10.254.9 22` (open) and `23` (refused).
   The scripted lines (one `@node:` block per device):
   ```
   @HQ-EDGE1: show running-config | section aaa|radius / show logging | include [Ll]ogging to|Trap logging / show snmp group | include security model / show ntp associations / show running-config | section line vty
   @HQ-EDGE2: the same five, plus show aaa servers | include State / show snmp user | include Privacy / show running-config | include ntp / show ip access-lists MGMT-HOSTS
   @DC-NMS1:  snmpget -v3 -u nmsuser -l authPriv -a SHA -A AUTHPASS123 -x AES -X PRIVPASS123 <10.10.254.5 | 10.10.254.9> 1.3.6.1.2.1.1.5.0 ; nc -zv -w 3 10.10.254.9 22 ; nc -zv -w 3 10.10.254.9 23
   ```
   Then the protection design below. The management standard itself is already in place on both routers.
2. **Inventory what must keep working** before filtering: eBGP (TCP 179 both directions, both AFs), iBGP over loopbacks, OSPF/OSPFv3 and HSRP (all only on internal links, so not in EDGE-IN, but in the CoPP routing class), IP SLA echo replies from the pinned probe target (the tracks), NAT return traffic, ND.
3. **Ingress ACL order.** Bogons and own-space sources first (own space is the /25 + /26 pair, not the /24 [192.0.2.192/26 is the IX]), then the peer's BGP, then the pinned probe replies and `deny icmp any host <own> echo-reply log` (so the only echo-replies reaching the router come from the probe target), echo to the provider-facing address, `deny ip any host <own> log`, return traffic to the pool and the DMZ block, TCP 80 to the DMZ server, final `deny ip any any log`. Provider-side checks: `hostile.sh probe|spoof|web`, ACE counters and log lines.
4. **CoPP from measurement.** Take counter deltas per class over a representative window (a test run measured routing 3.1 kb/s, management bursts of about 14 kB per SSH login, ICMP 0.8 kb/s at one ping per second, probe replies 0.1 kb/s, default 0.3 kb/s), then set cir with headroom and bc above the biggest burst (management needs bc 8000: key exchange). Routing and probe classes never drop. Test with the flood.
5. **FNF.** Record, exporter (`destination 10.50.50.60 vrf MGMT`, `source Ethernet0/1.99`), monitor input on e0/0, e0/1 and e0/2 of both edges. Prove with `show flow exporter FE-NMS statistics` and tshark on DC-NMS1.
6. **Regression pass** over the constraints (V6) after each control, not only at the end.

Plausible-but-wrong approaches: ACE on the VTY only (does nothing for the router CPU, Q4); a /24 anti-spoof entry (Q1); a stateful-looking `permit tcp any any established` inbound everywhere (opens the router's own addresses to scans: restrict it to the pool and DMZ block); dropping probe replies with the general ICMP class (the track fails during bursts); `ip nat inside` thinking applies to e0/1.99 (it does not: the MGMT subinterface is outside NAT).

## Solution Configuration

The protection block was tested as config text on the imported start-state lab (HQ-EDGE1 and HQ-EDGE2 in one pass, no errors). Both routers already carry the management standard, so each needs only the protection block (and EDGE2 the F1 fix above). Values below are for HQ-EDGE1; the same text goes on HQ-EDGE2 with these substitutions: provider peer 198.51.100.64 -> 203.0.113.64, own 198.51.100.65 -> 203.0.113.65, probe 198.51.100.1 -> 203.0.113.1, pool 192.0.2.0 0.0.0.63 -> 192.0.2.64 0.0.0.63, IPv6 peer/own 2001:DB8:F001:FFFF::64/65 -> 2001:DB8:F002:FFFF::64/65, iBGP peer and own loopbacks swapped (10.255.10.32/31 <-> 10.255.10.31/32 and 2001:DB8:FFFF:10::32/31 likewise). Rates are the same on both edges.

### HQ-EDGE2 only: the fix for F1 (R1)

A group-only change is not enough: the user keeps its stored security level and the user line is not shown in running-config, so remove and re-add the user with the group at `priv` (tested on the lab, EDGE1 untouched):

```
no snmp-server user nmsuser NMSGROUP v3 auth sha AUTHPASS123
no snmp-server group NMSGROUP v3 auth access MGMT-HOSTS
snmp-server group NMSGROUP v3 priv access MGMT-HOSTS
snmp-server user nmsuser NMSGROUP v3 auth sha AUTHPASS123 priv aes 128 PRIVPASS123
```

Afterwards `show snmp user` shows `Privacy Protocol: AES128`, `show snmp group` shows `security model:v3 priv`, and `snmpget -v3 -l authPriv` from DC-NMS1 answers `"HQ-EDGE2.veridian.example"` on both routers. (The rest of the management block on EDGE2 is the E3 standard and needs no change.)

### HQ-EDGE1 (and, with the substitutions above, HQ-EDGE2): protection (R2, R3, R4)

```
ip access-list extended EDGE-IN-V4
 deny ip 0.0.0.0 0.255.255.255 any log
 deny ip 10.0.0.0 0.255.255.255 any log
 deny ip 100.64.0.0 0.63.255.255 any log
 deny ip 127.0.0.0 0.255.255.255 any log
 deny ip 169.254.0.0 0.0.255.255 any log
 deny ip 172.16.0.0 0.15.255.255 any log
 deny ip 192.168.0.0 0.0.255.255 any log
 deny ip 224.0.0.0 31.255.255.255 any log
 deny ip 192.0.2.0 0.0.0.127 any log
 deny ip 192.0.2.128 0.0.0.63 any log
 permit tcp host 198.51.100.64 host 198.51.100.65 eq bgp
 permit tcp host 198.51.100.64 eq bgp host 198.51.100.65
 permit icmp host 198.51.100.1 host 198.51.100.65 echo-reply
 deny icmp any host 198.51.100.65 echo-reply log
 permit icmp any host 198.51.100.65 echo
 deny ip any host 198.51.100.65 log
 permit tcp any 192.0.2.0 0.0.0.63 established
 permit icmp any 192.0.2.0 0.0.0.63 echo-reply
 permit icmp any 192.0.2.0 0.0.0.63 time-exceeded
 permit icmp any 192.0.2.0 0.0.0.63 unreachable
 permit tcp any 192.0.2.128 0.0.0.63 established
 permit icmp any 192.0.2.128 0.0.0.63 echo-reply
 permit icmp any 192.0.2.128 0.0.0.63 time-exceeded
 permit icmp any 192.0.2.128 0.0.0.63 unreachable
 permit tcp any host 192.0.2.130 eq www
 deny ip any any log
ipv6 access-list EDGE-IN-V6
 permit icmp any any nd-ns
 permit icmp any any nd-na
 deny ipv6 FC00::/7 any log
 deny ipv6 FF00::/8 any log
 deny ipv6 2001:DB8:10::/48 any log
 permit tcp host 2001:DB8:F001:FFFF::64 host 2001:DB8:F001:FFFF::65 eq bgp
 permit tcp host 2001:DB8:F001:FFFF::64 eq bgp host 2001:DB8:F001:FFFF::65
 permit icmp any host 2001:DB8:F001:FFFF::65 echo-request
 deny ipv6 any host 2001:DB8:F001:FFFF::65 log
 permit tcp any 2001:DB8:10::/48 established
 permit icmp any 2001:DB8:10::/48 echo-reply
 permit icmp any 2001:DB8:10::/48 time-exceeded
 permit icmp any 2001:DB8:10::/48 unreachable
 permit icmp any 2001:DB8:10::/48 packet-too-big
 permit tcp any host 2001:DB8:10:60::150 eq www
 deny ipv6 any any log
ip access-list extended CP-ROUTING
 permit tcp host 198.51.100.64 host 198.51.100.65 eq bgp
 permit tcp host 198.51.100.64 eq bgp host 198.51.100.65
 permit tcp host 10.255.10.32 host 10.255.10.31 eq bgp
 permit tcp host 10.255.10.32 eq bgp host 10.255.10.31
 permit ospf any any
 permit udp any eq 1985 host 224.0.0.2
ipv6 access-list CP-ROUTING-V6
 permit tcp host 2001:DB8:F001:FFFF::64 host 2001:DB8:F001:FFFF::65 eq bgp
 permit tcp host 2001:DB8:F001:FFFF::64 eq bgp host 2001:DB8:F001:FFFF::65
 permit tcp host 2001:DB8:FFFF:10::32 host 2001:DB8:FFFF:10::31 eq bgp
 permit tcp host 2001:DB8:FFFF:10::32 eq bgp host 2001:DB8:FFFF:10::31
 permit 89 any any
 permit icmp any any nd-ns
 permit icmp any any nd-na
ip access-list extended CP-MONITOR
 permit icmp host 198.51.100.1 host 198.51.100.65 echo-reply
ip access-list extended CP-MGMT
 permit tcp 10.50.50.0 0.0.0.255 any eq 22
 permit tcp 10.10.99.0 0.0.0.255 any eq 22
 permit udp 10.50.50.0 0.0.0.255 any eq snmp
 permit udp host 10.50.50.52 eq 1812 any
 permit udp host 10.50.50.52 eq 1813 any
 permit udp host 10.50.50.1 eq ntp any
 permit icmp 10.50.50.0 0.0.0.255 any
ip access-list extended CP-UNDESIRABLE
 permit tcp any any eq telnet
 permit tcp any any eq 22
 permit udp any any eq snmp
 permit udp any any eq tftp
 permit tcp any any eq 514
 permit tcp any any eq 80
 permit tcp any any eq 443
ip access-list extended CP-ICMP
 permit icmp any any
ipv6 access-list CP-ICMP-V6
 permit icmp any any echo-request
 permit icmp any any echo-reply
class-map match-any CM-ROUTING
 match access-group name CP-ROUTING
 match access-group name CP-ROUTING-V6
class-map match-all CM-MONITOR
 match access-group name CP-MONITOR
class-map match-all CM-MGMT
 match access-group name CP-MGMT
class-map match-all CM-UNDESIRABLE
 match access-group name CP-UNDESIRABLE
class-map match-any CM-ICMP
 match access-group name CP-ICMP
 match access-group name CP-ICMP-V6
policy-map PM-COPP
 class CM-ROUTING
  police cir 64000 bc 8000 conform-action transmit exceed-action transmit
 class CM-MONITOR
  police cir 8000 bc 1500 conform-action transmit exceed-action transmit
 class CM-MGMT
  police cir 64000 bc 8000 conform-action transmit exceed-action drop
 class CM-UNDESIRABLE
  police cir 8000 conform-action drop exceed-action drop
 class CM-ICMP
  police cir 8000 bc 1500 conform-action transmit exceed-action drop
 class class-default
  police cir 16000 bc 4000 conform-action transmit exceed-action drop
flow record FR-EDGE
 match ipv4 protocol
 match ipv4 source address
 match ipv4 destination address
 match transport source-port
 match transport destination-port
 match interface input
 collect counter bytes
 collect counter packets
 collect timestamp sys-uptime first
 collect timestamp sys-uptime last
flow exporter FE-NMS
 destination 10.50.50.60 vrf MGMT
 source Ethernet0/1.99
 transport udp 2055
 template data timeout 60
flow monitor FM-EDGE
 record FR-EDGE
 exporter FE-NMS
interface Ethernet0/0
 ip access-group EDGE-IN-V4 in
 ipv6 traffic-filter EDGE-IN-V6 in
 ip flow monitor FM-EDGE input
interface Ethernet0/1
 ip flow monitor FM-EDGE input
interface Ethernet0/2
 ip flow monitor FM-EDGE input
control-plane
 service-policy input PM-COPP
```

## Verification

Captured on a fresh import after applying the solution text to both edges (cold boot, about 7 minutes after BOOTED).

**Constraints (V6), HQ-EDGE1:** both BGP sessions and OSPF up, track Up, HSRP Active:
```
10.255.10.32    4        65010      13      13        9    0    0 00:06:52        5
198.51.100.64   4        64601      11      11        9    0    0 00:06:47        2
10    ip sla      10                         reachability     Up    00:06:05
Et0/2       60   110 P Active  local           10.10.60.3      10.10.60.1
10.10.254.2       0   FULL/  -        00:00:03    10.10.254.4     Ethernet0/1.99
     State: current UP, duration 420s, previous duration 0s
```
HQ-PC1: `ping -c 2 192.0.2.200` 0% loss, `ping6 -c 2 2001:db8:f001:200::200` 0% loss, `traceroute` 4 hops (10.10.10.1, 10.10.255.65, 198.51.100.64, 192.0.2.200).

**Hostile script from PROV-SRV1 (V2, R5):**
```
tcp/22 rc=1   tcp/23 rc=1   tcp/80 rc=1   tcp/179 rc=1   tcp/443 rc=1
spoofed source 192.0.2.10 ... 5 packets transmitted, 0 packets received, 100% packet loss
web-ok / web request ok
ICMP flood to 198.51.100.65 (40 s) ... 3811 packets transmitted, 39 packets received, 98% packet loss
```
EDGE1 afterwards (V3, R5): the flood is policed by the ICMP class, BGP and the track are untouched:
```
 Class-map: CM-ICMP ... conformed 50 packets, 41602 bytes; exceeded 3772 packets, 3930424 bytes; actions: drop
 conformed 3000 bps, exceeded 98000 bps
 198.51.100.64   4        64601      13      13        9    0    0 00:08:44        2
 10    ip sla      10                         reachability     Up    00:08:02
 CM-MONITOR conformed 6 packets (probe replies), exceeded 0   (earlier output, before the flood)
 150 permit icmp any host 198.51.100.65 echo (3850 matches)
  90 deny ip 192.0.2.0 0.0.0.127 any log (5 matches)         <- spoofed pings
 130 permit icmp host 198.51.100.1 host 198.51.100.65 echo-reply (58 matches)   <- probe replies
```
The 3850 matches on the echo ACE show the ingress ACL permits the flood (echo to the provider-facing address is a requirement); CoPP is what stops it (Q4). The scan and spoof are dropped by the ACL's last `deny ip any host <own> log` and the own-space ACE; DC-SYSLOG1 shows:
```
%SEC-6-IPACCESSLOGP: list EDGE-IN-V4 denied tcp 192.0.2.200(36629) -> 198.51.100.65(179), 1 packet
%SEC-6-IPACCESSLOGDP: list EDGE-IN-V4 denied icmp 192.0.2.10 -> 198.51.100.65 (8/0), 1 packet
%IPV6_ACL-6-ACCESSLOGDP: list EDGE-IN-V6/160 denied icmpv6 FE80::A8BB:CCFF:FE00:3500 -> FF02::1 (134/0), 1 packet   (provider RA: expected noise)
```
EDGE2 (E3 management lines; earlier build with the standard applied by the student): `State: current UP`, ACE counters `permit tcp host 203.0.113.64 eq bgp ... (2 matches)`, `permit icmp host 203.0.113.1 host 203.0.113.65 echo-reply (24 matches)`; `show ntp associations` shows `~10.50.50.1 .INIT.` early and `*~10.50.50.1` (sys.peer) after 24 min in the earlier build.

**Management (V1), measured earlier in the same build (scripted SSH from DC-NMS1):** `netadmin` `Current privilege level is 15`, `netops` `Current privilege level is 1` on both edges; `snmpwalk` authPriv returned `HQ-EDGE2.veridian.example`; EDGE2 `show aaa servers` UP and `show ntp associations` `*~10.50.50.1`; `Trap logging informational` to 10.50.50.51.

**Flows (V5, R4):** tshark on DC-NMS1 decodes (`-d udp.port==2055,cflow`); exporter shows VRF label MGMT, source 10.10.254.9. FM-EDGE cache on e0/0 of EDGE1 for return traffic: `192.0.2.200 -> 192.0.2.1` (outside-global, pre-NAT) on Et0/0, `10.10.10.101 -> 192.0.2.200` on Et0/1 (inside); DMZ flow: `192.0.2.200 -> 192.0.2.130` on Et0/0, `10.10.60.150 -> 192.0.2.200` on Et0/2. Denied packets are also recorded (`192.0.2.10 -> 198.51.100.65` icmp, `192.0.2.200:38207 -> :22`) because the monitor sees the packet before the ACL. In the cache after the hostile run: `IPV4 DESTINATION ADDRESS: 198.51.100.65`. IPv4 only.

**F1 (fresh import, EDGE2 as it boots):**
```
EDGE2: Privacy Protocol: None            groupname: NMSGROUP   security model:v3 auth
EDGE1: Privacy Protocol: AES128          groupname: NMSGROUP   security model:v3 priv
DC-NMS1 snmpget -l authNoPriv -> EDGE2 (10.10.254.9): "HQ-EDGE2.veridian.example"
DC-NMS1 snmpget -l authPriv   -> EDGE2: snmpget: Unsupported security level
DC-NMS1 snmpget -l authPriv   -> EDGE1 (10.10.254.5): "HQ-EDGE1.veridian.example"
nc -zv -w 3 10.10.254.9 23: Connection refused      22: succeeded
EDGE2 OSPF 99 FULL, BGP 203.0.113.64 up, track 20 Up, AAA State: current UP, MGMT-HOSTS 10/20/40, transport input ssh
```
After the fix (above) `show snmp user` on EDGE2 reads AES128, `show snmp group` `v3 priv`, and authPriv answers from both routers; EDGE1 was not touched. NTP: both edges `*~10.50.50.1` sys.peer (stratum 3, reach 77) about 25 minutes after import; at about 12 minutes both were still `.INIT.`. Any V item that depends on NTP state (V1's `*` mark) must wait for that. Management logins as `netadmin`/`netops` are manual SSH logins.

**Q1 experiment:** `deny ip 192.0.2.0 0.0.0.255 any log` on EDGE1: PC1 -> PROV-SRV1 ping 3/3 lost, wget timeout, ACE 85 counting; /25 + /26 restored: ping 3/3 ok.

**Production note (R3):** the CoPP rates here are lab-scaled so that the provider-side scripts move the counters. In production, baseline the load per class over days, keep the routing classes generous or transmit-only, start from the platform's CoPP template and review after every change (see LAB-040 Q2).

**Normal control-plane rates (R3 input, ~100 s window with 3 logins, one snmpwalk, 60 pings at 1/s):** routing about 3.1 kb/s (357 packets, 37 kB), management 99 packets 14 kB (burst per login), ICMP 60 packets about 0.8 kb/s, probe replies 1 packet per 5 s about 0.1 kb/s, default about 0.3 kb/s. Chosen (same on both edges): routing 64000 transmit/transmit, probe 8000 bc 1500 transmit/transmit, management 64000 bc 8000 transmit/drop, undesirable 8000 drop/drop, ICMP 8000 bc 1500 transmit/drop, default 16000 bc 4000 transmit/drop. HSRP ACE counts rose 1 per 3 s (655 -> 680), OSPF 5103 -> 5298, OSPFv3 3401 -> 3532 over the same window.

## Failure / Recovery Behaviour

### Start-state drills (HQ-EDGE2 hardened from boot, no ACL, CoPP or FNF yet)

The protected-state tables below were measured with the full solution on both edges; these runs show the same behaviour on the pre-staged start state, so the drills do not depend on the student's protection. Cable pull = `shutdown` on both ends of the HQ-EDGE1 / PROV-ISP1 link; silent failure = CML `link stop` (both interfaces stay up/up); node stop = DC-AAA1.

| Scenario (trigger -> end condition) | Runs (raw, s) | Documented range | Basis |
|---|---|---|---|
| Cable pull: `%LINK-5-CHANGED` administratively down -> track 10 Down | 12.0, 9.9, 8.0 | 5-13 s | link-down detection then probe; BGP both AFs down in the same second; PC1 pings PROV-SRV1 (IPv4 and IPv6) with 0% loss, HSRP EDGE1 Standby |
| Cable pull recovery: link up -> track 10 Up | 43.6, 42.6, 44.4 | 35-48 s | probe recovery; HSRP Active within 50 s of `no shutdown` |
| Silent failure: `link stop` -> track 10 Down (wall clock from the REST call, includes about 10 s of session connect) | 16, 21, 21 | 14-22 s | HSRP Active -> Speak in the same second as the track |
| Silent failure: `link start` -> HSRP Active (wall clock incl. connect) | about 36, 38, 42 | 32-48 s | same as the protected-state table below |
| DC-AAA1 `node stop` -> `%RADIUS-4-RADIUS_DEAD` -> `%RADIUS-3-ALLDEADSERVER` on EDGE2 | RADIUS_DEAD logged at 02:41:59, ALLDEADSERVER 20 s later | about 20 s between the two lines | dead-criteria 5 s x 2 tries, then the fallback to the local list |

AAA evidence for the node stop: use the log lines `%RADIUS-4-RADIUS_DEAD` and `%RADIUS-3-ALLDEADSERVER` (EDGE2 `show logging | include RADIUS`), not `show aaa servers | include State`: with `radius-server deadtime 1` the State line returns to `current UP` after each deadtime, even while DC-AAA1 is down, and goes DEAD again on the next attempt. A `test aaa group RADGRP nobody wrong new-code` times out while the node is stopped and returns `User rejected` about 12 s after `node start` (server answering). The local-fallback login (`admin` / `Cisco123!`) is a manual SSH login and was not scripted (proven in an earlier test run, below).

### Protected-state drills (earlier build)

All with the protection of the solution in place on both edges, PC1 pinging PROV-SRV1 at 1/s (75 pings). Cable pull = `shutdown` on both ends of the HQ-EDGE1 e0/0 link; silent failure = CML `link stop`, which leaves both interfaces up/up. Times are seconds from the trigger.

| Scenario (trigger -> end condition) | Runs (raw) | Documented range | Basis |
|---|---|---|---|
| Silent failure: `link stop` on the EDGE1-ISP1 link -> track 10 Down (evidence-log timestamp) | 14.1, 15.3, 17.2, 16.7, 15.9, 17.3 | 14-20 s | next probe 0-5 s + 5 s timeout + `delay down 5` (10-15 s nominal; measured values run 2-5 s above that on this bench, cause not isolated); LAB-043 re-measured the same drill on this stage (16.3-19.9 s); E2 unprotected track Down was 15-17 s, the same as E3, and the 3-5 more lost pings than E2 (14-15) are in the pings row |
| Same, pings lost out of 75 | 18, 18, 20 | 17-21 | detection time at 1 ping/s |
| Silent failure: HSRP Active -> Speak after track Down | +15.2, +14.9, +16.6 | same second as the track | tracking decrement |
| `link start` -> HSRP Active again (EDGE1 preempt) | 34.4, 35.1, 37.6, 32.3, 42.8, 33.0 | 32-48 s | probe recovery plus preempt delay; 48 s seen on a loaded 15-node bench |
| ISP-A BGP IPv4 during a silent outage of 93 s | stayed Up (uptime continued) | up to the 180 s hold | BGP hold time 180 s |
| Cable pull: `%LINK-5-CHANGED ... administratively down` -> track 10 Down | 6.5, 7.1, 5.6 | 5-13 s | link-down detection then probe; LAB-043 re-measured 11.1-12.6 s; 8.3-11.9 s on a loaded bench |
| Cable pull, pings lost out of 75 | 0, 0, 0 | 0 | forwarding already via EDGE2 (HSRP is not the data path for PC1's Internet traffic here) |
| Cable pull recovery: `%LINK-3-UPDOWN up` -> HSRP Active | 35.5, 40.6, 42.6 | 35-48 s | preempt after tracking returns; 45.7-46.1 s on a loaded bench |
| Flood (40 s, `hostile.sh flood`) | BGP v4 uptime 00:31:58 -> 00:32:41 (unbroken), OSPF FULL x3, track 10 Up (no change), SLA failures 2 -> 2, CM-MONITOR exceeded 0 | no reset in any run | CM-ICMP absorbs it (exceeded 1685 -> 5455 in the first run, 3772 in the captured one) |

Other cases:
- **DC-AAA1 node stop:** both edges `State: current DEAD`; local `admin` / `Cisco123!` logs in at privilege 15 after about 11 s (dead-criteria 5 s x 2); `netadmin` is refused (`Connection closed`); AAA UP again after the node restarts.
- **Stub-DC silent failure (`link stop` CORE1 e1/1 - DC-RTR1 e0/0):** after the OSPF 99 dead time the edge has no route to 10.50.50.60 (`% Subnet not in table`); the exporter's `Successfully sent` counter freezes at 299 while the cache keeps adding flows (unlike LAB-036's directly connected exporter, which keeps counting); 34 s outage; route back about 12 s after `link start`, exports resume +12 s, template resent +23 s (counter 299 -> 302). Records of the outage are lost for good (UDP, no replay); syslog lines of the outage are lost too.
- A one-sided `shutdown` of the ISP-A link would leave the provider side up/up: not used.

## Answers to Analysis Questions

**Q1.** 192.0.2.0/24 contains 192.0.2.192/26, the IX block with PROV-SRV1 (192.0.2.200). With `deny ip 192.0.2.0 0.0.0.255 any` the replies and everything sourced from PROV-SRV1 are dropped: PC1 -> PROV-SRV1 ping 3/3 lost, wget timeout, the ACE counting. Veridian's own space is only 192.0.2.0/26, .64/26 and .128/26 (the /25 plus /26 pair).

**Q2.** `permit tcp any <pool> established` matches any TCP segment with ACK or RST, not only replies to sessions an inside host opened: an outside host can send ACK-flag packets to any pool or DMZ address (which NAT then drops unless a translation exists), and echo-reply / time-exceeded / unreachable are accepted without a matching echo or flow. A stateful firewall tracks the connection and admits only matching return packets, including UDP. This is the gap LAB-044 (evidence) and the firewall labs close.

**Q3.** The same flow shows different addresses: monitors on e0/1 and e0/2 (inside-facing) see inside addresses (10.10.10.101, 10.10.60.150); the monitor on e0/0 sees the outside-global addresses (pre-NAT for return traffic: 192.0.2.200 -> 192.0.2.1 on Et0/0) because the input monitor runs before NAT translates the destination back. It also records packets the ingress ACL denies, since the monitor sits ahead of the ACL on the interface.

**Q4.** Without CoPP the ingress ACL still permits echo to the provider-facing address (3850 matches during the flood), so the flood would reach the CPU: nothing else stops it. The VTY access-class and the AAA/SNMP controls only protect their own services. The spoof and scan controls (own-space ACE, `deny ip any host <own>`) would still drop their traffic, but those are not the flood. The only control that limits the flood is the ICMP class (exceeded 3772 packets); a tighter ACL would also stop it, but at the cost of the provider's troubleshooting pings.

**Q5.** On this edge the SLA echo replies are what tracks 10 and 20 depend on, and they arrive as ICMP echo-replies addressed to the router: with no probe class they fall into CM-ICMP, so any provider burst of ICMP starves them and the track falls, failing over a healthy link. On a bench with no tracked failover a dropped reply costs nothing. The probe class (CM-MONITOR, matching only echo-replies from the pinned target) keeps them out of the ICMP class and out of any drop.

**Q6.** The management traffic leaves through e0/1.99, the dot1q-99 subinterface in VRF MGMT towards HQ-CORE1 and DC-RTR1, never through e0/0. It is outside NAT because `ip nat inside` is on e0/1 and does not apply to e0/1.99 (MGMT addresses are private and never in the NAT table), and EDGE-IN is applied only to e0/0 inbound, so management never meets it. The flow exporter and RADIUS/syslog/NTP use the same path (VRF MGMT, source e0/1.99).

**Q7.** Flow export is UDP: records of flows that ended while the DC link was down are lost for good (the exporter counter froze at 299; flows kept being cached but the NetFlow packets could not be sent, the route to 10.50.50.60 was gone); after the route returns exports resume about 12 s later and the template is resent about 23 s after the link starts. Syslog is also UDP: messages sent during the outage are lost. Neither buffers on this platform beyond the local log buffer.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-25 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), iol-xe (IOS XE 17.16.1a), net-tools, radius, syslog, unmanaged_switch |
