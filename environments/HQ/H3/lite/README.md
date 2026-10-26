# HQ lite H3 + DC min (derived by LAB-045)
Proven by LAB-045.
Derived from HQ H3 by LAB-045. Reused by MS-3 and MS-5. Cold-boot tested together with EDGE min E3 (11 nodes BOOTED in 82 s; OSPF/OSPFv3/OSPF 99 FULL, VRRPv3 20/50/99 MASTER on CORE1, Po1 (SU) with both members, eBGP both AFs, PC1/PC2 reach the Internet host in IPv4 and IPv6 and the DMZ).

**Profile (7 licensed + DC min 2 = 9, with EDGE min 11):** HQ-CORE1, HQ-DIST1, HQ-DIST2, HQ-ACC1, HQ-PC1 (VLAN 10), HQ-PC2 (VLAN 20, ACC1 e0/3), DC-RTR1, DC-AAA1 (on DC-RTR1 e0/1, no DC switch).

**Changes from H3:** CORE2, ACC2/3, PC3 and their links gone; the cross trunks (DIST e1/1 with VLAN 903/904 and their SVIs) and DIST e0/3 / e1/2 removed; CORE1 e0/0 and e0/0.99 (CORE2 links) removed. CORE1 e0/3 = standard EDGE1 link (10.10.255.64/31, 2001:DB8:10:FFFF::64/127, OSPF/OSPFv3 area 0, p2p, cost 10, hello 1 / dead 4); CORE1 e0/3.99 = MGMT 10.10.254.4/31 (OSPF 99); CORE1 e1/1 = DC link 10.10.255.130/31 (OSPF 1 area 50) and e1/1.99 = MGMT 10.10.254.6/31; VRRPv3 groups 20/50/99 keep their configuration with CORE1 the only member; STP priorities as H3 (VLAN 20 root DIST2: VLAN 20 crosses Po1). DC-RTR1 = `environments/EDGE/E3/DC-RTR1.cfg` (uplink HQ-CORE1 e1/1); DC-AAA1 files as H3. Area 10 is a normal OSPF area here: LAB-045's NSSA, summary and filter are its own changes.

**Cabling:** CORE1 e0/1-DIST1 e1/0 (vlan 901, 20, 50, 99), CORE1 e0/2-DIST2 e1/0 (vlan 902), DIST1/DIST2 e0/0+e0/1 (Po1), DIST1 e0/2-ACC1 e0/0, DIST2 e0/2-ACC1 e0/1, ACC1 e1/0-PC1, ACC1 e0/3-PC2, CORE1 e0/3-EDGE1 e0/1, CORE1 e1/1-DC-RTR1 e0/0, DC-RTR1 e0/1-DC-AAA1 eth0.

**Measured (LAB-045):** (a) area 10 `nssa` accepted in both AFs on the ioll2-xe DISTs (`ipv6 route ::/0` = `NSSA extern 2`); (b) iol-xe `area 10 nssa default-information-originate` works in OSPFv2 and in the OSPFv3 AF; (c) `area 10 range 10.10.0.0/16` installs `Null0` discard that beats the default; (d) ioll2-xe `%ETC-5-CANNOT_BUNDLE2: Et0/1 is not compatible with Po1 and will be suspended (vlan mask is different)`. SSH to a device needs a MGMT-HOSTS source address (10.10.99.0/24, 10.50.50.0/24): from CORE1 or a VLAN 99 SVI. No NMS or syslog host in lite: `logging host 10.50.50.51` and flow lines stay but have no collector.

**Files:** `HQ-CORE1/DIST1/DIST2/ACC1.cfg`, `HQ-PC1/PC2.cfg`, `DC-RTR1.cfg`, `DC-AAA1.boot.sh|radiusd.conf|users`. Restart rule as H3 (no ioll2-xe restart in labs relying on RA lifetime; `sys.peer` on the switches about 25 min).
