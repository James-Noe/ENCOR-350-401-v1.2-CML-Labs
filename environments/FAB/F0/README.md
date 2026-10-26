# FAB F0 stage (fabric control plane: underlay + LISP, VN CORP only)
Proven by LAB-067.
Proven in CML by LAB-067 (its solved state). Profile: 6 nodes, FAB-MSMR1, FAB-SPINE1, FAB-XTR1, FAB-XTR2 (iol-xe), FAB-PC1, FAB-PC2 (alpine). No BDR1, no DC-FUS1.

## Cabling and addressing
| Link | A | B | Addressing |
|---|---|---|---|
| Underlay | SPINE1 e0/0 | MSMR1 e0/0 | 10.60.255.0/31 (MSMR1 .0, SPINE1 .1) |
| Underlay | SPINE1 e0/1 | XTR1 e0/0 | 10.60.255.2/31 (SPINE1 .2, XTR1 .3) |
| Underlay | SPINE1 e0/2 | XTR2 e0/0 | 10.60.255.4/31 (SPINE1 .4, XTR2 .5) |
| LAN | XTR1 e0/1 (VRF CORP) | FAB-PC1 | 10.60.10.0/24, gw .1, PC .101 |
| LAN | XTR2 e0/1 (VRF CORP) | FAB-PC2 | 10.60.11.0/24, gw .1, PC .102 |

RLOCs Loopback0: MSMR1 10.255.60.1, SPINE1 .2, XTR1 .11, XTR2 .12. OSPF 1 area 0, p2p, hello 1 / dead 4. VRF CORP rd 65060:1 on the XTRs, LISP instance-ID 4097.

## Content
The day-0 start state of LAB-067 plus: MSMR1 `router lisp` map-server/map-resolver with sites AST-XTR1 (10.60.10.0/24) and AST-XTR2 (10.60.11.0/24) in instance 4097, key `ROUTEKEY123`; each XTR a locator-set RLOC (Loopback0), `itr`/`etr` with map-resolver/map-server 10.255.60.1, instance 4097 with `eid-table vrf CORP` and its own `database-mapping`. Files are the LAB-067 start configs with the proven `router lisp` blocks appended (the commands were applied live, not booted as day-0). Settling: registration within about 10 s of boot of all nodes (OSPF first).

## Proven (LAB-067 build)
Both sites `yes`, PC1 <-> PC2 ping (first ping loses 2 packets with both caches empty), map-cache `10.60.11.0/24 ... 23:59:xx` via map-reply, RIB of VRF CORP unchanged. Evidence and timings: LAB-067 SOLUTION.md.
## Files
`FAB-MSMR1.cfg`, `FAB-SPINE1.cfg`, `FAB-XTR1.cfg`, `FAB-XTR2.cfg`, `FAB-PC1.cfg`, `FAB-PC2.cfg`.
