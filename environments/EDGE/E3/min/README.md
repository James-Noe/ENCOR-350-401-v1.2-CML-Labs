# EDGE min E3 (derived by LAB-045)
Proven by LAB-045.
Derived from EDGE E3 by LAB-045. Together with HQ lite H3, 11 nodes cold-booted clean in 82 s (see that README).

**Nodes:** HQ-EDGE1 (iol-xe), PROV-ISP1 (iol-xe), HQ-SRV1 (alpine, DMZ 10.10.60.150, httpd on 80, directly on EDGE1 e0/2, HSRP 60 alone). **Changes from E3:** EDGE2/ISP2, the EDGE1-EDGE2 link, iBGP (v4 and v6 neighbours and CP-ROUTING iBGP lines) and ISP1's ISP2 peering/e0/1 removed; ISP1 e0/2 (IX) shut and unaddressed; ISP1 `Loopback200` 192.0.2.200/32 and 2001:DB8:F001:200::200/128 as the Internet host. EDGE1 keeps E3's ACLs, PM-COPP, FNF (no collector in 045), AAA/logging/SNMPv3/NTP lines, tracks, NAT and static default. EDGE1 e0/1 meets HQ-CORE1 e0/3 (10.10.255.65/31; MGMT e0/1.99 10.10.254.5/31 meets CORE1 e0/3.99 .4, which is in the lite files, not here).

**Behaviour:** PC to 192.0.2.200 goes through PAT pool 192.0.2.1 and EDGE-IN-V4 `permit icmp any 192.0.2.0 0.0.0.63 echo-reply`. The only service published from the Internet is TCP 80 to 192.0.2.130 / 2001:DB8:10:60::150 (ICMP to them is denied by EDGE-IN: `U.U` / `AAA` from ISP1); test with `telnet 192.0.2.130 80 /source-interface Loopback200` from ISP1 (`Open`, `HTTP/1.1 400 Bad Request`). Cable pull on EDGE1-ISP1 e0/0 (both ends): track 10 Down +14-16 s, HQ internal traffic (incl. DMZ) unaffected when CORE1 holds the specific DMZ route; default back +43-50 s after `no shutdown` (`delay up 30`).

**Files:** `HQ-EDGE1.cfg`, `PROV-ISP1.cfg`, `HQ-SRV1.cfg`.
