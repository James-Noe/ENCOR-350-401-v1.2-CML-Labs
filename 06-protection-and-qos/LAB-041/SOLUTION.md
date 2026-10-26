# LAB-041 — Solution

## Summary

Feature lab on three filter types, from the port outward: PACL (ACL on an access port, inbound only here), VACL (VLAN map, filters traffic inside the VLAN and routed traffic entering it) and RACL (ACL on an SVI). Students learn that only a VLAN map can filter host-to-host traffic on one switch in one VLAN, that the kiosk rule must follow the port (not the IP), the VLAN map end behaviour, and the as-built processing order. Blueprint 5.2.a (practical), 3.1.a (reinforced). No intentional faults.

## Intentional Faults

None (feature lab).

## Diagnosis / Methodology

Not a troubleshooting lab. Design rationale:
- PC3 and PC4 hang off SW2, so a map or ACL on SW1 never sees guest-to-guest frames. The VLAN map goes on SW2 (a pure Layer 2 switch with no SVI in VLAN 30: enforced there, no fallback needed).
- The gateway 10.0.30.1 sits inside the guest subnet, so the drop clause must exempt it (ACL G2G denies = excludes it; in a VLAN map a `permit` ACL line = match = drop).
- Hosts need `sudo -n` for `ip neigh flush all` / `ip addr add`.
- Side effect of stateless GUEST-IN: guests cannot answer pings from VLAN 10 (deny guest to 10.0.0.0/8). Not a requirement.

## Solution Configuration

**SW2**
```
ip access-list extended G2G
 deny ip any host 10.0.30.1
 deny ip host 10.0.30.1 any
 permit ip 10.0.30.0 0.0.0.255 10.0.30.0 0.0.0.255
vlan access-map GUEST 10
 match ip address G2G
 action drop
vlan access-map GUEST 20
 action forward
vlan filter GUEST vlan-list 30
ip access-list extended KIOSK
 permit tcp any host 10.0.50.50 eq 80
 deny ip any any
interface Ethernet0/2
 ip access-group KIOSK in
```
**SW1**
```
ip access-list extended USERS-IN
 permit tcp 10.0.10.0 0.0.0.255 10.0.50.0 0.0.0.255 eq 80
 permit icmp 10.0.10.0 0.0.0.255 10.0.50.0 0.0.0.255
 deny ip 10.0.10.0 0.0.0.255 10.0.50.0 0.0.0.255
 permit ip any any
ip access-list extended GUEST-IN
 permit ip any host 10.0.30.1
 deny ip 10.0.30.0 0.0.0.255 10.0.0.0 0.255.255.255
 permit ip any any
interface Vlan10
 ip access-group USERS-IN in
interface Vlan30
 ip access-group GUEST-IN in
```
The KIOSK ACL ends with an explicit `deny ip any any` so the drops are countable. ARP is not IP, so a port IP ACL does not stop it.

## Verification

Captured after `clear ip access-list counters` (exec mode; `clear` is invalid in a config block). Output trimmed.

- R1: PC3 to PC4 ping: 100% loss. `show ip access-lists G2G`: `30 permit ip 10.0.30.0/24 10.0.30.0/24 (2 matches)`. PC3 to 10.0.30.1 and 198.51.100.1 work (lines 10/20 count those).
- R2: PC2 ping SRV1 and 198.51.100.1: 100% loss; `wget http://10.0.50.50/` prints `web-ok`. `show ip access-lists KIOSK`: `10 permit tcp ... eq www (5 matches)`, `20 deny ip any any (6 matches)`. With `sudo -n ip addr add 10.0.10.77/24 dev eth0` and `nc -s 10.0.10.77`: port 80 rc=0, port 22 rc=1, ping to PC1 100% loss; counters 10 -> 11, 20 -> 16.
- R3: PC1 ping SRV1 works, `nc -z -w2 10.0.50.50 80` rc=0, port 22 rc=1. USERS-IN: `10 (9 matches)`, `20 icmp (2)`, `30 deny (1 match)`. PC3 to SRV1: 100% loss, GUEST-IN `20 deny (2 matches)`, `30 permit (16)`.
- R4: after `sudo -n ip neigh flush all` on the hosts, pings and wget work again (ARP re-resolves: `10.0.30.1 lladdr aa:bb:cc:80:02:00 REACHABLE`).
- R5: one blocked flow per type: PACL = PC2 ping SRV1, KIOSK deny counter; VACL = PC3 to PC4, G2G counter; RACL = PC1 nc 22 (USERS-IN deny) and PC3 to SRV1 (GUEST-IN deny).

Platform findings (build-time tests):
- VLAN map on SW2 (`no ip routing`, no SVI in VLAN 30): enforced.
- RACL on an ioll2-xe SVI enforced in (Vlan10, Vlan30) and out (Vlan50 out: `permit icmp host 10.0.10.11 ... (2 matches)`, `permit tcp any any eq www (5)` incremented).
- VACL on routed traffic: ingress VLAN enforced (vlan filter on VLAN 10 on SW1 dropped PC1 to SRV1 ping while the USERS-IN icmp counter stayed unchanged: VACL is evaluated before RACL in). Egress VLAN not enforced (a map on VLAN 50 dropping icmp: ping passed, ACL 0 matches).
- PACL `out` on a L2 port: `% Invalid input` (inbound only).
- MAC ACL in a VLAN map works; ethertype `arp`/0x806 is not accepted (`permit any any` only).
- `action drop log` is accepted: `%VLMAPLOG-6-ICMP: vlan 10 (port Et0/0) denied icmp 10.0.10.11 -> 10.0.50.50 (8/0), 1 packet`.
- There are no per-map counters, only per-ACL counters.

## Failure / Recovery Behaviour

No timing involved (static behaviour, no link failure; the method is a configuration change).

| Scenario | Result |
|---|---|
| Remove `GUEST 20` (no final forward; trigger: `no vlan access-map GUEST 20`, end: pings from PC3) | PC3 to 10.0.30.1 and to 198.51.100.1: 100% loss (all IP in VLAN 30 hits the implicit drop). ARP still resolves (`REACHABLE` after flush): the map holds only IP ACLs, so non-IP traffic is not subject to the drop. |
| Restore `GUEST 20 forward` | PC3 pings OK at once (3/3, 2/2). |
| Add seq 5 `match mac address` (ACL `permit any any`) with drop, forward 20 kept | ARP fails (`FAILED`; MAC ACL `permit any any (3 matches)`); removing seq 5 recovers. |
| MAC ACL that is empty, referenced in a drop clause | ARP also broke (anomaly; not used in the lab). |

Platform note: the common premise "no final forward kills ARP" is false on this platform; ARP is only dropped when the map contains a MAC clause that matches it.

## Answers to Analysis Questions

Q1: A router ACL on the SVI only sees packets that are routed through the SVI. PC3 to PC4 is switched inside VLAN 30 on SW2 and never reaches the router interface (SW1 never sees it, and SW2 has no SVI in VLAN 30). A VLAN map (or port ACLs) acts on the L2 forwarding path.
Q2: Without the final forward every IP packet in VLAN 30 not matched by a drop clause hits the implicit drop: 100% loss to gateway and loopback. ARP survived (observed), because a VLAN map with only IP ACLs does not apply its implicit drop to non-IP frames. ARP is dropped when the map has a MAC ACL clause (e.g. `permit any any` drop) because that clause matches non-IP frames: then an explicit forward for ARP is needed (the ethertype `arp` match is not available here, so ARP can only be allowed by ordering a MAC forward before the MAC drop).
Q3: PACL on SW2 Et0/1 (none for PC1 here), VACL on VLAN 10 at SW2 (none), trunk, VACL VLAN 10 on SW1 (ingress VLAN, if any; proven evaluated before the RACL), RACL USERS-IN on Vlan10 in, routing, then RACL out on Vlan50 (if any; proven enforced), then the egress VLAN's VACL, which is not enforced on this platform for routed traffic. Standard order (Catalyst hardware enforces all of it): PACL, VACL on the ingress VLAN, RACL in, routing, RACL out, VACL on the egress VLAN. Platform note: on this image (ioll2-xe) the egress VLAN's map was measured as not filtering routed traffic; do not take that as the rule.
Q4: A VLAN map matches IP/MAC addresses, but the kiosk may be given any IP, and the rule is tied to a physical port. A PACL on that port filters regardless of source address and without touching other users in VLAN 10, which a VLAN-wide map would also affect.
Q5: When the isolation is "no host-to-host, all via gateway" with many hosts and ports: private VLANs (isolated ports) enforce it by port type without per-address ACLs and also stop non-IP frames. Analysis only: PVLAN forwarding is unproven on this server.
Q6: No, not on this platform: `ip access-group ... out` on a switchport is rejected here (`% Invalid input`); outbound PACL support varies by platform, so plan egress filtering with a RACL out or a VLAN map.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-17 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), ioll2-xe (IOS XE 17.16.1a) |
