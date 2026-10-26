# HQ H4 stage (campus multicast, WAN lite W2)
Proven by LAB-056.
Built and proven in CML by LAB-056. The stage is the **solved** state: H3 plus the WAN attachment and the multicast delta. LAB-056's YAML is the start state (the same configs without the multicast delta), never H4. LAB-057 starts from it.

**Profile:** 16 nodes: HQ full 10 (HQ-CORE1/2 iol-xe; HQ-DIST1/2, HQ-ACC1-3 ioll2-xe; HQ-PC1-3 alpine) + DC min 2 (DC-RTR1 iol-xe, DC-AAA1 radius on DC-RTR1 e0/1, no DC switch, no syslog/NMS) + WAN lite W2 4 (HQ-WAN1, PROV-INET1, BR1-RTR1 iol-xe; BR1-PC1 alpine). 18 files: `HQ-*.cfg` x10 (incl. HQ-WAN1), `DC-RTR1.cfg`, `DC-AAA1.boot.sh|radiusd.conf|users`, `PROV-INET1.cfg`, `BR1-RTR1.cfg`, `BR1-PC1.cfg`.

## Cabling (additions to H3)
| Link | A | B | Addressing |
|---|---|---|---|
| Core - WAN hub | HQ-CORE1 e1/0 | HQ-WAN1 e0/2 | 10.10.255.96/31 (.96/.97), OSPF 1 area 0 p2p cost 10 hello 1 / dead 4, PIM |
| WAN1 Internet | HQ-WAN1 e0/0 | PROV-INET1 e0/0 | 203.0.113.128/31 |
| BR1 Internet | BR1-RTR1 e0/0 | PROV-INET1 e0/1 | 203.0.113.130/31 |
| BR1 LAN | BR1-RTR1 e0/2 | BR1-PC1 | e0/2.10 `dot1Q 10 native` 10.21.10.1/24, PC .101; management on Loopback99 10.21.99.1/24 |
| DC services (min) | DC-RTR1 e0/1 (VRF MGMT) | DC-AAA1 | 10.50.50.0/24 (.1/.52); `logging host 10.50.50.51` stays with no collector |
Tunnel21 (GRE over IPsec, `tunnel protection`, OSPF area 21, `ip mtu 1400`) HQ-WAN1 10.250.21.1 - BR1-RTR1 10.250.21.21. Unused ports shut: HQ-WAN1 e0/1, e0/3; BR1-RTR1 e0/1; PROV-INET1 e0/2, e0/3.

## Multicast content (the H4 delta)
CORE1/CORE2: `ip multicast-routing`, PIM sparse mode on Lo0, Lo10 (10.255.10.100/32, OSPF area 0), core link, the video subinterfaces (CORE1 e0/1.20/.50 and e1/0; CORE2 e0/2.20/.50), `ip pim rp-address 10.255.10.100`, MSDP between the Lo0 addresses with `originator-id Loopback0`, `ip pim dr-priority 200` on CORE1 e0/1.50 and CORE2 e0/2.20, `ip pim query-interval 1` on the four video subinterfaces, `ip igmp access-group OPS-VIDEO` (239.10.20.0/24) on both VLAN 20 subinterfaces. HQ-WAN1: PIM on e0/2 and Tunnel21; BR1-RTR1: PIM on Tunnel21 and e0/2.10; same static RP. HQ-PC3: the encoder at boot (239.10.20.1, 512 kb/s, TTL 16, AF41).
**IGMP snooping:** `no ip igmp snooping vlan 20` (and 50 where the VLAN exists) on HQ-DIST1, HQ-DIST2, HQ-ACC2 (20), HQ-ACC3 (50); HQ-ACC1 at its default. See the snooping note below.

## BV outcomes (LAB-056)
- Works: PIM-SM over Tunnel21 with `tunnel protection` (neighbour, (S,G) across, only ESP/IKE/NTP in the underlay).
- Works: encoder started from HQ-PC3's day-0 file (loop around `iperf -t 0`).
- Snooping: ioll2-xe snooping learns groups and mrouter ports but does not forward multicast arriving on a trunk (static mrouter or group entries do not help), so VLANs 20/50 run with snooping off on the four switches above. `query-interval 1` and `dr-priority` accepted; DR failover 2.1-2.8 s, no restore gap. Anycast RP + MSDP works; stopping CORE1 gives the OPS viewer no gap.
- MTU: 1344-byte packets cross Tunnel21 unfragmented; a 1498-byte DF packet is dropped (498 "couldn't fragment").

## Restart rule
Save before a node stop (`write memory`); avoid `clear ip mroute *` with a running source; alpine keeps IGMPv2 for about 4 min after a router IGMP version change; ioll2-xe switches are not restarted where the RA lifetime matters (H2 rule). Service nodes carry day-0 files only.
