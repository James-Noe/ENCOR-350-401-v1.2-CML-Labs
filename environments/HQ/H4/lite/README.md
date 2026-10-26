# HQ lite H4 + HQ-PC3, HQ-PC5 (derived by LAB-058)
Proven by LAB-058.
Derived from HQ lite H3 and HQ H4 by LAB-058. The solved stage: none of LAB-058's faults, no link conditioning, no amended WAN policy. Boot-checked together with the H4 WAN lite W2 nodes and EDGE min E3 (17 nodes BOOTED in 129 s).

**Profile (HQ 8 + DC min 2 = 10; with W2 lite 4 and EDGE min 3 = 17):** HQ-CORE1, HQ-DIST1, HQ-DIST2, HQ-ACC1, HQ-PC1 (VLAN 10, ACC1 e1/0), HQ-PC2 (VLAN 20, ACC1 e0/3), **HQ-PC3** (VLAN 50, the encoder, ACC1 e1/1), **HQ-PC5** (capture host, no IP address, ACC1 e1/2 access VLAN 10, SPAN destination), DC-RTR1, DC-AAA1.

**Delta from HQ lite H3:** VLAN 50 on the ACC1 uplinks and on DIST1 e0/2 / DIST2 e0/2; `no ip igmp snooping vlan 20` and `vlan 50` on DIST1, DIST2 and ACC1 (platform rule: no lite switch snoops the video VLANs); HQ-CORE1: OPS-VIDEO ACL (239.10.20.0/24) as `ip igmp access-group` on e0/1.20, `ip multicast-routing`, static RP 10.255.10.100 on Loopback10 (the full design's anycast address; no MSDP peer, no `dr-priority`), PIM sparse mode on Lo0, Lo10, e0/1.20, e0/1.50 (`ip pim query-interval 1`) and e1/0 (HQ-WAN1 link 10.10.255.96/31, OSPF area 0); ACC1: VLAN 50, PC3 on e1/1, PC5 on e1/2.

**Attachments (files not repeated here):** WAN lite W2 = `environments/HQ/H4/` HQ-WAN1, PROV-INET1, BR1-RTR1, BR1-PC1 (HQ-WAN1 e0/2 to CORE1 e1/0); EDGE min E3 = `environments/EDGE/E3/min/` (HQ-EDGE1 on CORE1 e0/3, PROV-ISP1, HQ-SRV1).

**Cabling:** as `environments/HQ/H3/lite/` plus ACC1 e1/1-PC3, ACC1 e1/2-PC5, CORE1 e1/0-HQ-WAN1 e0/2.

**Boot-check outcomes:** OSPF FULL with EDGE1, HQ-WAN1, DIST1, DIST2, DC-RTR1 (area 50 and MGMT); VRRP 20/50/99 MASTER on CORE1; WAN1 `UP-ACTIVE`, OSPF and PIM over Tunnel21; the encoder's `(10.10.50.103, 239.10.20.1)` appears on CORE1 with an empty OIL until a viewer joins; a viewer on PC2 sees 0 % loss, BR1-PC1 about 0.2 % (the conditioned circuit when conditioning is on). Without MSDP, CORE1 is the only RP and DR. MS-4 adds HQ-CORE2 as the second anycast member.

**Files:** `HQ-CORE1/DIST1/DIST2/ACC1.cfg`, `HQ-PC1/PC2/PC3/PC5.cfg`, `DC-RTR1.cfg`, `DC-AAA1.boot.sh|radiusd.conf|users`. Restart rule as H3 lite.
