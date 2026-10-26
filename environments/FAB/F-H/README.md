# FAB F-H stage (fusion handoff, Aster VNs to Veridian DC)
Built and proven in CML by LAB-051. The stage is the **solved** state: LAB-051's YAML ships DC-FUS1 with addressing on `Ethernet0/0`/`Ethernet0/1` only.

**Profile:** 6 nodes: FAB-BDR1, DC-FUS1, DC-RTR1 (iol-xe), FAB-PC1, FAB-PC2 (alpine), DC-DNS1 (dnsmasq). No unmanaged switches.

## Cabling and addressing
| Link | A | B | Addressing |
|---|---|---|---|
| Handoff | DC-FUS1 e0/1 | FAB-BDR1 e0/0 | dot1q 3001 CORP 10.200.60.2/.3, dot1q 3002 IOT 10.200.60.4/.5 (/31); main interfaces unaddressed; 10.200.60.0/31 reserved for F2 |
| Fusion-DC | DC-FUS1 e0/0 (VRF SHARED) | DC-RTR1 e0/2 (global) | 10.50.255.0/31 (RTR1 .0, FUS1 .1), OSPF area 50 (FUS1 process 50 in VRF SHARED, RTR1 process 1), p2p, hello 1 / dead 4 |
| Shared services | DC-RTR1 e0/3 | DC-DNS1 eth0 | 10.50.51.0/24 (RTR1 .1, DNS1 .53) |
| Aster CORP / IOT LANs | FAB-BDR1 e0/1 / e0/2 | FAB-PC1 / FAB-PC2 | 10.60.10.0/24 (PC .101), 10.60.20.0/24 (PC .102), gw .1 |

DC-RTR1 also holds Loopback52 10.50.52.1/24 (OSPF 1 area 50): a reserved second shared service, not leaked until a student adds it to prefix-list SHARED-SERVICES on DC-FUS1 (LAB-051 R4). Loopbacks: BDR1 10.255.60.21, FUS1 10.255.50.5 (global, unadvertised), RTR1 10.255.50.1.

## Content
`DC-RTR1.cfg` is `environments/HQ/H3/DC-RTR1.cfg` with e0/0 and e0/0.99 shut and unaddressed (OSPF 99 and its passive exception removed), e0/2, e0/3, Loopback52 added, OSPF 1 `no passive-interface Ethernet0/2`. Its RADIUS/syslog/NTP lines stay (DC-AAA1/SYSLOG1 absent: VTY falls back to local, console unaffected). FAB-BDR1: AS 65060, VRFs CORP (65060:1) and IOT (65060:2), per-VRF eBGP to FUS1, `network` for each VN subnet. DC-FUS1: AS 65010, RDs 65010:1 CORP, :2 IOT, :50 SHARED; each VRF exports its own RT through an export map (prefix-lists CORP-USERS, IOT-USERS, SHARED-SERVICES); CORP/IOT import :50, SHARED imports :1 and :2 (local leaking, no VPNv4 neighbour); OSPF 50 vrf SHARED and BGP vrf SHARED redistribute into each other through route-maps OSPF-TO-BGP / BGP-TO-OSPF. PCs: resolver 10.50.51.53. DNS1: `erp.veridian.example` by `address=`, `dns1.veridian.example` by hosts file.

## Proven (LAB-051 build)
Leak matrix, traceroute BDR1 -> FUS1 -> RTR1, R4 (one prefix-list line on FUS1) and failure timings: in LAB-051 SOLUTION.md. Settling time after boot: about 60-90 s for the BGP leak.
## Files
`FAB-BDR1.cfg`, `DC-FUS1.cfg`, `DC-RTR1.cfg`, `FAB-PC1.cfg`, `FAB-PC2.cfg`, `DC-DNS1.dnsmasq.conf`, `DC-DNS1.hosts`, `DC-DNS1.boot.sh`.
