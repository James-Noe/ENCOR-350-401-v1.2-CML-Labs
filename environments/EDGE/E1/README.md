# EDGE E1 stage baseline (dual ISP, dual stack)
Built and proven in CML by LAB-025. Start point for LAB-029 (E2). The stage is the **solved** state of LAB-025: its YAML is the start state (no EDGE2-ISP-B session, no IPv6 BGP, no policy), never E1.

**Configs.** The five routers (HQ-EDGE1, HQ-EDGE2, HQ-CORE1, PROV-ISP1, PROV-ISP2) carry their running configuration after LAB-025's solution, cold-boot tested (every BGP session, the policy and the end-state outputs match the solved lab). The hosts are unchanged from LAB-025. Running-config captures show IPv6 addresses in upper case and omit default `no shutdown` and `standby 60 priority 100`.

**Profile:** 8 nodes licensed, 10 running by the budget tool: HQ-EDGE1, HQ-EDGE2, PROV-ISP1, PROV-ISP2, HQ-CORE1 stub (iol-xe); PROV-SRV1, HQ-SRV1, HQ-PC1 (alpine); unmanaged switches `IX` and `DMZ` (count as running nodes).

## Topology
| Link | A | B | Addressing (IPv4 / IPv6) |
|---|---|---|---|
| EDGE1-ISP1 | HQ-EDGE1 e0/0 | PROV-ISP1 e0/0 | 198.51.100.64/31 (ISP1 .64, EDGE1 .65) / 2001:db8:f001:ffff::64/127 (ISP1 ::64, EDGE1 ::65) |
| EDGE1-core | HQ-EDGE1 e0/1 | HQ-CORE1 e0/3 | 10.10.255.64/31 (CORE1 .64, EDGE1 .65) / 2001:db8:10:ffff::64/127 |
| EDGE1-DMZ | HQ-EDGE1 e0/2 | DMZ switch | 10.10.60.2/24 / 2001:db8:10:60::2/64 |
| EDGE1-EDGE2 | HQ-EDGE1 e0/3 | HQ-EDGE2 e0/3 | 10.10.255.68/31 (EDGE1 .68, EDGE2 .69) / 2001:db8:10:ffff::68/127 |
| EDGE2-ISP2 | HQ-EDGE2 e0/0 | PROV-ISP2 e0/0 | 203.0.113.64/31 (ISP2 .64, EDGE2 .65) / 2001:db8:f002:ffff::64/127 |
| EDGE2-core | HQ-EDGE2 e0/1 | HQ-CORE1 stub e1/2 | 10.10.255.66/31 (core .66, EDGE2 .67) / 2001:db8:10:ffff::66/127 |
| EDGE2-DMZ | HQ-EDGE2 e0/2 | DMZ switch | 10.10.60.3/24 / 2001:db8:10:60::3/64 |
| ISP1-ISP2 | PROV-ISP1 e0/1 | PROV-ISP2 e0/1 | 198.51.100.66/31 (ISP1 .66, ISP2 .67) / 2001:db8:f001:ffff::66/127 (ISP1 ::66, ISP2 ::67) |
| ISP1-IX | PROV-ISP1 e0/2 | IX switch | 192.0.2.193/26 / 2001:db8:f001:200::1/64 |
| ISP2-IX | PROV-ISP2 e0/2 | IX switch | 192.0.2.194/26 / 2001:db8:f001:200::2/64 |
| Stub user LAN | HQ-CORE1 e1/3 | HQ-PC1 eth0 | 10.10.10.1/24 / 2001:db8:10:10::1/64; PC1 .101 |

Hosts: PROV-SRV1 192.0.2.200/26 gw .193, 2001:db8:f001:200::200/64 (static IPv6 default via ::1); HQ-SRV1 10.10.60.150/24 gw .1 (HSRP VIP), 2001:db8:10:60::150/64; HQ-PC1 10.10.10.101/24 gw .1, 2001:db8:10:10::101/64. IPv6 host defaults come from RAs (IOS default timers; present after a cold boot, RC2 closed: no static fallback needed). Not cabled: EDGE1-ISP2 203.0.113.66/31 (D2).

Loopbacks: EDGE1 10.255.10.31 / 2001:db8:ffff:10::31, EDGE2 10.255.10.32 / ::32, CORE1 stub 10.255.10.1 (+ Lo20 10.10.20.2/24, Lo50 10.10.50.2/24), ISP1 198.51.100.1 and 198.51.100.10/29, ISP2 203.0.113.1 and 203.0.113.10/29.

**Stub role:** HQ-CORE1 stands in for the campus core; its user LAN 10.10.10.0/24 plays the DIST role.

## Stage content (E1 on top of E0)
- EDGE2: eBGP AS 65010 to ISP-B AS 64602 (203.0.113.64, MD5 `ISPB-64602`; IPv6 neighbour 2001:db8:f002:ffff::64, same key); PAT pool POOL-B 192.0.2.65 (overload) and static NAT 10.10.60.150 <-> 192.0.2.130; HSRP 60 priority 100, preempt, untracked; static default to ISP2 and OSPF `default-information originate metric 30`.
- iBGP EDGE1 <-> EDGE2: IPv4 (loopbacks) and IPv6 (2001:db8:ffff:10::31/::32) as separate neighbours; `no neighbor ... activate` for IPv6 neighbours in the IPv4 AF; next-hop-self in the IPv6 AF.
- Per-ISP announcements: pool A 192.0.2.0/26 to ISP-A only, pool B 192.0.2.64/26 to ISP-B only, DMZ 192.0.2.128/26 to both with two prepends towards ISP-B, IPv6 2001:db8:10::/48 on both (Null0 anchor on both edges), two prepends towards ISP-B. No-transit outbound route-maps on both edges in both AFs (the filter is the outbound prefix-list route-map); local preference 200 on EDGE2 for 198.51.100.8/29 from ISP2 (route-map ISPB-IN); EDGE1 sets local preference 150 on ISP-A's IPv6 routes (ISPA-IN-V6).
- OSPFv3 (AF ipv6, new-style `ospfv3 1 ipv6 area 0`) on all edge links with `default-information originate` on both edges (metrics 10 and 30). EDGE2's origination is dormant while EDGE1 has ISP-A's ::/0.

## Measured behaviour (LAB-025)
- Steady state: PC1 to PROV-SRV1 via ISP-A (IPv4 and IPv6); to 203.0.113.10 and 198.51.100.10 via EDGE2 and ISP-B; ISP-B's best path for 192.0.2.128/26 and the /48 is 64601 65010 (two prepends; one prepend ties on length).
- Cable pull EDGE1-ISP1 (`shutdown` both ends): IPv4 and IPv6 default move to EDGE2 (metric 30) within about 1 min (first check), ISP-B's best DMZ path becomes direct 65010 x3; recovery BGP Up in 1-2 min (IPv6 too).
- Silent failure (`link stop`): sessions stay Up until the hold timer (about 170 s); IPv4 black-holed for good (static default stays), IPv6 recovers after the hold time.
- IPv6 eBGP, `default-originate` (ISPs), OSPFv3 default from a BGP ::/0 (EDGE2 BGP ::/0 shows RIB-failure while OSPFv3 E2 wins) and RA host defaults all PASS on iol-xe. Transit-leak evidence needs `received-routes` on the provider (soft reconfiguration).
- Unmanaged switches count in the node budget (10 running). A first-pass IPv6 convergence after a restart takes 1-2 min. `clear ip bgp * soft` is safe.

**The lab YAML of 025/029 is a pre-staged start state, not the stage.** LAB-029 (E2) adds SLA/track, tracked defaults, HSRP tracking and the EEM evidence applet on top of these files.
- HQ-EDGE1's DMZ interface advertises `ipv6 nd router-preference High` (EDGE2 default Medium): HQ-SRV1's IPv6 default prefers EDGE1 and does not follow HSRP (added in E2) or tracking.
