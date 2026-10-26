# HQ H2 stage baseline (three-tier)
Built and proven in CML by LAB-021. The stage is the **solved** state: LAB-021's YAML is the pre-staged start state (cores installed, cut-over not done), never H2.

**Profile:** full 10 nodes: HQ-CORE1, HQ-CORE2 (iol-xe); HQ-DIST1, HQ-DIST2, HQ-ACC1, HQ-ACC2, HQ-ACC3 (ioll2-xe); HQ-PC1, HQ-PC2, HQ-PC3 (alpine). Lite H2 is not built here.

## Topology (cabling; H0/H1 links unchanged)
| Link | A | B | Carries |
|---|---|---|---|
| Core interconnect | CORE1 e0/0 | CORE2 e0/0 | routed 10.10.255.0/31, 2001:db8:10:ffff::/127 |
| CORE1-DIST1 (straight) | CORE1 e0/1 | DIST1 e1/0 | trunk 901, 20, 50 |
| CORE1-DIST2 (cross) | CORE1 e0/2 | DIST2 e1/0 | trunk 902 |
| CORE2-DIST1 (cross) | CORE2 e0/1 | DIST1 e1/1 | trunk 903 |
| CORE2-DIST2 (straight) | CORE2 e0/2 | DIST2 e1/1 | trunk 904, 20, 50 |
| ACC3 uplinks | DIST1 e1/2, DIST2 e1/2 | ACC3 e0/0, e0/1 | trunk 50, 99 |
| PC3 | ACC3 e1/0 (VLAN 50) | PC3 eth0 | |
| Po1 | DIST1/DIST2 e0/0-e0/1 | | trunk 10, 20, 50, 99 |
All trunks dot1q, native 999, `nonegotiate`, explicit allowed lists; DIST e1/0-e1/1 `spanning-tree portfast trunk`, no root guard; DIST e1/2 root guard, ACC3 e0/0-e0/1 loop guard. Reserved: CORE1 e0/3 EDGE1 (.64/31), CORE2 e0/3 EDGE2 (.66/31), CORE1 e1/0 WAN1 (.96/31), CORE2 e1/0 DC-RTR1 (.128/31), CORE1 e1/1 (lite DC .130/31), CORE1 e1/2 (EDGE2 in HQ lite and in the module 04 EDGE stub, which give CORE1 every inter-environment uplink; unused in full H2).

## Addressing and areas
Loopbacks 10.255.10.1/.2 (CORE), .11/.12 (DIST), IPv6 2001:db8:ffff:10::<id>/128. Transit /31 (IPv6 /127 mirrors the last octet): VLAN 901 10.10.255.2/.3 (CORE1/DIST1), 902 .4/.5 (CORE1/DIST2), 903 .6/.7 (CORE2/DIST1), 904 .8/.9 (CORE2/DIST2), core interconnect .0/.1. Areas: CORE e0/0, Lo0 and the VLAN 20/50 subinterfaces area 0 (the user subinterfaces passive); transit links and DIST Lo0/Vlan10/Vlan99 area 10 (user SVIs passive). VLAN 20 .2/.3 on CORE1/CORE2 (VRRP VIP .1), VLAN 50 .2/.3 (VIP .1); VLAN 10 DIST .2/.3 (GLBP .1); VLAN 99 .11/.12 (HSRPv2 VIP .1). IPv6 user VLANs 2001:db8:10:<vlan>::/64 with ::<2|3> on the gateway devices; hosts static ::101/::102/::103.

## Content
- OSPFv2 process 1 and OSPFv3 process 1 (address-family ipv6 unicast), router ID = Lo0 IPv4, `passive-interface default`, non-passive on CORE e0/0 and transit links; network type point-to-point, cost 10, hello 1 / dead 4 s in both protocols on CORE e0/0 and every transit interface (both ends). No default route, no authentication.
- VLAN 20: VRRPv3 group 20 on CORE subinterfaces (CORE2 priority 110 master, CORE1 100), `preempt delay minimum 30`; VLAN 50: group 50 (CORE1 110 master). DIST Vlan20 SVIs and HSRP 20 removed. STP: VLAN 10/99 DIST1 24576 / DIST2 28672, VLAN 20 DIST2 24576 / DIST1 28672, VLAN 50 DIST1 24576 / DIST2 28672.
- RAs: `ipv6 nd ra interval 4`, `ra lifetime 12` on every user-facing interface; `router-preference high` on DIST1 Vlan10, CORE2 VLAN 20, CORE1 VLAN 50 (LAB-019 values). IOS saves `ra lifetime` before `ra interval` and rejects it at boot while the interval is still 200 s, so after `write memory` + restart the lifetime reverts to 1800 s. The iol-xe cores carry the EEM applet `RA-LIFETIME` (syslog `SYS-5-RESTART`) that re-applies `lifetime 12`; ioll2-xe has no EEM, so the DIST SVIs keep 12 s only until their first restart (re-apply by hand).
- Restart rule for labs on H2: the iol-xe cores may be stopped and started (the applet restores the RA lifetime); the ioll2-xe switches should not be restarted in a lab that depends on the 12 s lifetime, or the lab must tell the student to re-apply it (MS-1 does the former).
- Management: day-0 `crypto key generate rsa modulus 2048`, `transport input ssh` on every IOS node, including the iol-xe cores.

## Build notes (LAB-021)
1. **Works:** VRRPv3 on iol-xe dot1q subinterfaces forwards for hosts behind ioll2-xe (PC3 and PC2 reach `.1` and other VLANs). Syntax: `vrrp 20 address-family ipv4` / `address 10.10.20.1 primary` / `priority 110` / `preempt delay minimum 30` / `exit-vrrp`, with `fhrp version vrrp v3` globally.
2. **Works:** `ip ospf network point-to-point`, `ospfv3 network point-to-point`, hello 1 / dead 4 s on ioll2-xe transit SVIs and iol-xe subinterfaces: all neighbours FULL/- with dead time 3 s; `spanning-tree portfast trunk` on e1/0-e1/1: the transit VLANs forward at once. No flaps seen; default costs (no explicit cost): iol-xe Ethernet subinterface 10, ioll2-xe SVI 1 (observed on user interfaces `show ip ospf interface brief`).
3. **Works:** day-0 RSA on iol-xe: `show ip ssh` `SSH Enabled - version 2.0` on CORE1 after boot.
4. **Works:** `2001:DB8:10:FFFF::0/127` accepted on CORE1 e0/0; OSPFv3 FULL over it.
5. **ECMP:** DIST1/DIST2 have two equal-cost paths (metric 20, O IA) to 10.10.20.0/24 and 10.10.50.0/24 and to each other's loopback (21); each core has two to the DIST subnets. Filter ECMP output with `| include via` (continuation lines).
6. Dead-core failover (silent, node stop of CORE2, 4 pings/s): IPv4 about 3 s, IPv6 about 9-11 s (bounded by the 12 s RA lifetime); core back with no loss, roles return after the 30 s preempt delay. Cable pull of a straight trunk: IPv4 about 0.5 s, IPv6 none seen; cross trunk: none. Details and Po1-loss mechanism in LAB-021 SOLUTION.md.
7. **Po1 total loss:** each core is VRRP master of both groups; ECMP flows hashed to the cut-off core or to DIST2 (whose Vlan10 stays up/up with its connected route) are black-holed; some host pairs still work. Autostate does not withdraw DIST2 Vlan10.
8. Link-local gateway addresses are MAC-derived (iol-xe subinterfaces of one parent share the MAC) and differ per boot: never documented. Hosts also get SLAAC addresses (not documented).
9. VLAN 20 cut-over with both DIST SVIs removed and both core subinterfaces added from one script: about 18 s outage (1 s pings).
## Files
`HQ-CORE1.cfg`, `HQ-CORE2.cfg`, `HQ-DIST1.cfg`, `HQ-DIST2.cfg`, `HQ-ACC1.cfg`, `HQ-ACC2.cfg`, `HQ-ACC3.cfg`, `HQ-PC1.cfg`, `HQ-PC2.cfg`, `HQ-PC3.cfg`: the solved H2 state of each node (a lab that starts from H2 loads these as day-0).
