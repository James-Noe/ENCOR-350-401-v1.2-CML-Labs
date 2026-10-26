# HQ H3 stage baseline (hardened, management VRF)
Built and proven in CML by LAB-037. The stage is the **solved** state; LAB-037's YAML is the pre-staged start state (H2 cores/DISTs, H3 access switches, DC-RTR1 without VTY ACL), never H3.

**Profile:** full 15 nodes: HQ full (10, as H2) + DC lite: DC-RTR1 (iol-xe), DC-SYSLOG1 (syslog), DC-AAA1 (radius), DC-NMS1 (net-tools), DC-SW (unmanaged_switch, no file). HQ lite H3 is derived by LAB-045 (module 06).

## New cabling and addressing (H2 links unchanged)
| Link | A | B | Addressing |
|---|---|---|---|
| Core-DC (global) | CORE2 e1/0 | DC-RTR1 e0/0 | 10.10.255.128/31 (.128/.129), OSPF 1 area 50, p2p, cost 10, hello 1 / dead 4 |
| Core-DC (MGMT) | CORE2 e1/0.99 | DC-RTR1 e0/0.99 | 10.10.254.0/31 (.0/.1), OSPF 99 vrf MGMT area 0, same timers |
| Core interconnect (MGMT) | CORE1 e0/0.99 | CORE2 e0/0.99 | 10.10.254.2/31 (.2/.3), OSPF 99 |
| VLAN 99 on the straight trunks | CORE1 e0/1.99, CORE2 e0/2.99 | DIST1 e1/0, DIST2 e1/1 (allowed lists add 99) | 10.10.99.2 / .3, VRRPv3 group 99 VIP .1 (CORE1 110, preempt delay 30), passive in OSPF 99 |
| DC services | DC-RTR1 e0/1 (VRF MGMT) | DC-SW: SYSLOG1 .51, AAA1 .52, NMS1 .60 | 10.50.50.0/24, gw .1, passive in OSPF 99 |
Reserved MGMT /31s (10.10.254.4/.6/.8/.10) unused here.

## Content
VRF MGMT on CORE1/CORE2/DC-RTR1 and DIST1/DIST2 Vlan99 (HSRP removed, out of OSPF 1, `ip route vrf MGMT 0.0.0.0 0.0.0.0 10.10.99.1`); OSPF 99 router IDs CORE1 10.10.254.2, CORE2 10.10.254.3, DC-RTR1 10.50.50.1. ACCs global with `ip default-gateway 10.10.99.1`. Every IOS device: AAA (RADGRP to 10.50.50.52, VTY list group-then-local, console `none`, enable `none`), accounting, `radius-server dead-criteria time 5 tries 2`, `deadtime 1`, logging to 10.50.50.51, SNMPv3 only (`priv` routers, `auth` switches, `access MGMT-HOSTS`), NTP key 1 from DC-RTR1 (`ntp master 3`), VTY `access-class MGMT-HOSTS in vrf-also`, `ipv6 access-class NO-VTY6 in`.

## Measured behaviour
1. (a) PASS: main interface with global OSPF plus dot1q-99 subinterface with `ospf 99` coexist on CORE1 e0/0, CORE2 e1/0, DC-RTR1 e0/0; no fallback.
2. (b) PASS: VRRPv3 group 99 on VRF subinterfaces forwards for ACC1; no fallback. CORE1 stop: master moves to CORE2, 3 s gap.
3. (c) PASS: Vlan99 in VRF on ioll2-xe with `ip vrf forwarding` in the RADIUS group, `logging host/source-interface vrf MGMT`, `ntp server vrf MGMT`, SSH with `vrf-also`.
4. (d) PASS: `access-class` without `vrf-also` refuses VRF sessions (`Connection refused`, ACL counters do not move).
5. (e) PASS: DC-RTR1 master selected as `*` sys.peer on all 7 HQ devices, in MGMT.
6. (f) PASS: SNMPv3 answered over the VRF with no extra command (authPriv routers, authNoPriv switches).
7. (g) PASS: DIST cut-over measured from ACC1 about 13 s.
8. (h) DEVIATION: `line vty 0 15` is rejected on iol-xe and ioll2-xe; only `line vty 0 4` exists (all configs use 0 4). The proposal's line 30 (`permit host 10.50.50.60`) is refused when typed after line 20 (redundant, "higher sequence num as it is part of the existing rule"): the ACL has lines 10, 20, 40.

## Restart rule
H2's rule still applies: ioll2-xe switches are not restarted in labs relying on the 12 s RA lifetime. Time needs about 25 minutes from boot to `sys.peer`. Service nodes carry day-0 files only (`DC-*.boot.sh`, `DC-AAA1.radiusd.conf`, `DC-AAA1.users`).

## Files
`HQ-CORE1/2.cfg`, `HQ-DIST1/2.cfg`, `HQ-ACC1/2/3.cfg`, `HQ-PC1/2/3.cfg`, `DC-RTR1.cfg`, `DC-SYSLOG1.boot.sh`, `DC-AAA1.boot.sh|radiusd.conf|users`, `DC-NMS1.boot.sh`.
