# HQ H5 single-core lite (built by MS-5)

**Proven by:** MS-5.

Derived from HQ H5 by MS-5. Only consumer: MS-5 (no later stage).

**Nodes:** HQ-CORE1 (iol-xe), HQ-DIST1, HQ-DIST2, HQ-ACC1 (ioll2-xe), HQ-PC1 (VLAN 10), HQ-PC2 (VLAN 20; MS-5 runs without it for the node budget, VLAN 20 stays configured with CORE1 as its only VRRP master). No HQ-PC3 (ACC1 keeps the configured, uncabled e1/1 port).

**Delta from `environments/HQ/H5/`**
- HQ-CORE1: e0/0 and e0/0.99 (core link to CORE2) removed; MSDP peer, `ip pim` on e0/0 and the `dr-priority 200` removed (Loopback10 10.255.10.100 stays as the lone RP, as H4 lite); `no passive-interface` exceptions for e0/0 and e0/0.99 replaced by e1/0 and e1/0.99.
- HQ-CORE1: e1/0 (10.10.255.96/31 to HQ-WAN1 e0/2, PIM sparse) and e1/0.99 (MGMT 10.10.254.10/31) as the W3 lite files; `ip ssh source-interface Ethernet0/1.99`; e1/1 and e1/1.99 to DC-RTR1 and e0/3 (PM-CORE-EDGE) as H5.
- HQ-CORE1: VRRPv3 20/50/99 with CORE1 the only member and **no `track` lines** (a tracked shutdown of the lone master would remove the gateway). SLA 11 / track 11 (icmp-echo 10.10.255.65 from e0/3, frequency 2) kept as H5; applet `GW-EVIDENCE` now `event track 11 state any` and appends the clock, `show ip route 0.0.0.0` and `show track 11` to `unix:gw-evidence.txt`, then logs `Gateway state change evidence captured` (tracking as tracked routes and evidence only). SLA 12 / track 12 (CORE2's old edge address) is **not** in the stage.
- HQ-DIST1, HQ-DIST2, HQ-ACC1, HQ-PC1, HQ-PC2 = H5 files (DIST1/ACC1 = H4 lite forms; DIST2 keeps H5's VLAN 904 lines and the Ethernet1/1 trunk, both unused).

**Cabling (as H3/H4 lite):** CORE1 e0/1 - DIST1 e1/0 (VLAN 901), e0/2 - DIST2 e1/0 (VLAN 902), e0/3 - HQ-EDGE1 e0/1 (10.10.255.64/31), e1/0 - HQ-WAN1 e0/2, e1/1 - DC-RTR1 e0/0 (10.10.255.130/31); DIST1/DIST2 e0/0 and e0/1 = Po1; DIST1 e0/2 - ACC1 e0/0, DIST2 e0/2 - ACC1 e0/1; ACC1 e1/0 - HQ-PC1, e0/3 - HQ-PC2.

**Boot proof (clean 19-node boot with EDGE min E3, W3 lite, DC lite, the F-H FAB subset and AUTO-MGMT1; no faults anywhere):** 19 nodes BOOTED in 115 s. About 5 minutes after start: VRRP 20/50/99 MASTER on CORE1 alone, track 11 Up, no root-inconsistent port on either DIST, no native-VLAN mismatch, HQ-PC1 reaches its gateway, BR1-PC1 (10.21.10.101), the Internet host 192.0.2.200, DC-RTR1 loopback and 10.50.51.1. The applet wrote `gw-evidence.txt` at boot (track 11 Down to Up), on a CORE1 e0/3 plus EDGE1 e0/1 `shutdown` (track Down, 6 s after the second `shutdown`, entry without a default route) and on `no shutdown` (Up, default route back via 10.10.255.65). See MS-5's SOLUTION.md for the end-to-end proofs.
