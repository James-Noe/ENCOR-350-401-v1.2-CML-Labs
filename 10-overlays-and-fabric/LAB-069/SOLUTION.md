# LAB-069 — Solution

## Summary
Educational intent: read a two-VN LISP fabric as SD-Access planes and roles, then add the one piece the fabric lacked, a border that connects it to a traditional network, and see that the fusion router did not care what sits behind the border (1.3.b). Blueprint mapping: 1.3.a:I (planes, roles, SD-Access vs analog), 1.3.b:P (traditional/fabric interworking, fusion), 2.3.a:P (LISP proxy-ETR/ITR, `use-petr`, negative map-reply), 2.2.a:R (VRF leaking at the fusion, isolation), 2.3.b:R (LISP vs VXLAN encapsulation). Platform: iol-xe 17.16.1a for all routers; LISP is the analog's data plane (SD-Access uses VXLAN-GPO). Stages: start F1, end F3 (`environments/FAB/F1/`, `F3/`; F2 = F3 without the DC block). Platform notes: the proxy roles are accepted, and the return path uses a Null0 /23 + BGP `network` + `map-cache <VN /23> map-request`.

## Intentional Faults
None (analysis/extension lab).

## Diagnosis / Methodology
R1 map, from output (captured in Verification): MSMR1 `show lisp site` = control plane node (map server/resolver, 4 registrations: AST-XTR1 and AST-XTR2, each 4097 and 4098); XTR1/XTR2 = fabric edges (ITR+ETR, `database-mapping` in each instance, gateway per edge); SPINE1 = intermediate node (OSPF only, no LISP: its configuration has no `router lisp`); BDR1 = border (VRFs, eBGP per VRF, and after R2 proxy roles); DC-FUS1 = fusion (VRFs CORP/IOT/SHARED with route-target leaking). Underlay = OSPF over the point-to-point links and the Loopback0 RLOCs; overlay = LISP instance 4097/4098 between RLOCs. Instance-ID to VN proof: `show lisp instance-id 4097 ipv4 map-cache` lists only CORP prefixes, `eid-table vrf CORP`. CORP cannot reach IOT because no mapping exists for the other VN's prefixes in the instance (negative map-reply) and the fusion imports only SHARED. SGT/ISE/Catalyst Center: derived references (Cisco SD-Access design guide): ISE authorises an endpoint (802.1X/MAB), returns VN and SGT; Catalyst Center pushes the VN/VRF, LISP instance and anycast gateway configuration; the SGT rides in the VXLAN-GPO header (the 16-bit Group Policy ID).

Before R2 (start state): PC1 ping 10.50.51.53 0/3, traceroute stops at 10.60.10.1 with `!H`; XTR1 map-cache 4097 holds `10.48.0.0/13 ... via map-reply, forward-native` (negative reply from the MS: nobody registered this space, so the entry lasts about 15 min), no use-petr. After `use-petr`: the same entry reads `Encapsulating to proxy ETR`. After R2 alone the ping still fails: the packet reaches the data centre, but DC-RTR1 has no route back (`Sent 34 unreachable` counter rising on RTR1) because the fusion accepted nothing from Aster. R3 closes that.

Plausible wrong ideas ruled out: a default route in the VN table on the edges would work for the first hop but suppresses LISP (a route covering the destination makes the ITR forward natively; rule 3) and would send IOT/CORP traffic unencapsulated into the underlay; advertising the /23 into the OSPF underlay would put endpoint routes into the underlay, the opposite of a fabric; making BDR1 an ordinary xTR registering a default would work (rule 5 fallback) but needs the MS to accept a default registration and a second site; static routes for the /23 on the fusion (option (3)) work only with an inbound prefix-list on BDR1 or the traffic loops back to FUS1 (not needed here).

## Solution Configuration
FAB-XTR1 and FAB-XTR2 (the global `service ipv4` under `router lisp`; no VN table route is added):
```
router lisp
 service ipv4
  use-petr 10.255.60.21
```
FAB-BDR1 (in the F1 start it has no `router lisp`; this is the whole block as tested):
```
ip route vrf CORP 10.60.10.0 255.255.254.0 Null0
ip route vrf IOT 10.60.20.0 255.255.254.0 Null0
router bgp 65060
 address-family ipv4 vrf CORP
  network 10.60.10.0 mask 255.255.254.0
 address-family ipv4 vrf IOT
  network 10.60.20.0 mask 255.255.254.0
router lisp
 locator-set RLOC
  IPv4-interface Loopback0 priority 1 weight 100
 exit
 service ipv4
  itr map-resolver 10.255.60.1
  proxy-etr
  proxy-itr 10.255.60.21
 exit
 instance-id 4097
  service ipv4
   eid-table vrf CORP
   map-cache 10.60.10.0/23 map-request
 exit
 exit
 instance-id 4098
  service ipv4
   eid-table vrf IOT
   map-cache 10.60.20.0/23 map-request
```
(Note: if `itr` is already enabled, `proxy-itr` is refused with `% Disable ITR functionality first.`: enter `no itr` first. The `exit` lines are needed to leave `service ipv4` before the next `instance-id`.)

DC-FUS1 (replace the /24 entries; the replace needs the full `no ... seq 10 permit <old>` form, `no ... seq 10` alone silently does nothing and the new `seq 10` is then refused with `Insertion failed`):
```
no ip prefix-list CORP-USERS seq 10 permit 10.60.10.0/24
ip prefix-list CORP-USERS seq 10 permit 10.60.10.0/23 le 24
no ip prefix-list IOT-USERS seq 10 permit 10.60.20.0/24
ip prefix-list IOT-USERS seq 10 permit 10.60.20.0/23 le 24
clear ip bgp * soft out
```
(`le 24` is headroom: it would also accept per-edge /24s inside the block. BDR1 sends only the /23 in this build, so the measured result does not depend on it.)
**Accepted alternatives (R3 return path).** Only the Null0 /23 plus `map-cache <VN /23> map-request` in each instance was proven on this bench. `redistribute lisp` with an aggregate was never tested. Fusion-side static routes were never tested either, and R3 excludes them because they make the fusion know the fabric and need an inbound filter on BDR1 to avoid a loop. If a student tries another mechanism, accept it only on evidence: `show ip cef vrf <VN> <fabric host>` on BDR1 must show a LISP encapsulation entry (not Null0 or a route back to the fusion), and a capture on the SPINE1-BDR1 link must show return traffic encapsulated for both VNs. A Null0 /23 without the `map-request` line leaves return traffic discarded. If you test from DC-RTR1, use `ping 10.60.10.<host> source 10.50.51.1`: the default source (10.50.255.0) fails even in the solved state, because the fusion leaks only the shared-services /24 (10.50.51.0/24) back into the fabric, so only 10.50.51.1 is routable from the fabric.

Why Null0 works: the BGP `network` statement needs a matching route in the VRF; the Null0 /23 provides it, and LISP's map-cache entry for the /23 (`map-request`) makes the border's CEF resolve a specific /24 per mapping, which beats the /23 discard, so a fabric host address is LISP-encapsulated, not dropped.

## Verification
All captured on a fresh import of the YAML, trimmed.

R2/V4, edge XTR1 (negative reply from the MS for 10.50.51.53, packets sent to the PETR):
```
show lisp instance-id 4097 ipv4 map-cache
10.48.0.0/13, uptime: 00:02:37, expires: 00:12:22, via map-reply, forward-native
  Encapsulating to proxy ETR
10.60.11.0/24, ... via map-reply, complete
  Locator 10.255.60.12 ... up 1/100
show ip route vrf CORP     -> only C 10.60.10.0/24 and L 10.60.10.1/32 (no covering route)
```
(In a test run, `show ip cef vrf CORP 10.50.51.53 detail` on XTR1: `LISP remote EID: 46 packets fwd action encap, nexthop 10.255.60.21 LISP0.4097`.) BDR1 `show lisp service ipv4`: ITR/ETR disabled, `Proxy-ITR Router (PITR): enabled RLOCs: 10.255.60.21`, `Proxy-ETR Router (PETR): enabled`.

R3/V4, border and fusion:
```
FAB-BDR1# show ip cef vrf CORP 10.60.10.101 detail
10.60.10.0/24, ... SC owned,sourced: LISP remote EID - locator status bits 0x00000001
  LISP remote EID: 2 packets 168 bytes fwd action encap
  nexthop 10.255.60.11 LISP0.4097
FAB-BDR1# show lisp instance-id 4097 ipv4 map-cache
10.60.10.0/23, ... via static-send-map-request   Negative cache entry, action: send-map-request
10.60.10.0/24, ... via map-reply, complete   Locator 10.255.60.11 up 1/100
FAB-BDR1# show ip route vrf IOT | include 10.50|10.60
B  10.50.51.0/24 [20/0] via 10.200.60.4
S  10.60.20.0/23 is directly connected, Null0
DC-FUS1# show ip route vrf SHARED bgp | include 10.60
B  10.60.10.0/23 [20/0] via 10.200.60.3 (CORP)
B  10.60.20.0/23 [20/0] via 10.200.60.5 (IOT)
DC-FUS1# show ip route vrf CORP bgp | include 10.60|10.50
B  10.50.51.0/24 [20/20] via 10.50.255.0 (SHARED), Ethernet0/0
B  10.60.10.0/23 [20/0] via 10.200.60.3
DC-FUS1# show ip route vrf IOT bgp | include 10.60|10.50
B  10.50.51.0/24 [20/20] via 10.50.255.0 (SHARED), Ethernet0/0
B  10.60.20.0/23 [20/0] via 10.200.60.5
DC-RTR1# show ip route ospf | include 10.60|10.50
O E2  10.60.10.0/23 [110/1] via 10.50.255.1, Ethernet0/2
O E2  10.60.20.0/23 [110/1] via 10.50.255.1, Ethernet0/2
```
(CORP never holds 10.60.20.0/23 and IOT never holds 10.60.10.0/23: isolation.) Until the fusion accepted the /23, FUS1's SHARED table held the /23 from BGP but the redistribution map matched only the /24, so DC-RTR1 had `% Subnet not in table`.

R4/V2/V5 (end checks, fresh import):
```
FAB-PC1# ping -c 3 -W 2 10.50.51.53     3 packets transmitted, 3 packets received
FAB-PC1# nslookup erp.veridian.example 10.50.51.53
Name:   erp.veridian.example
Address: 10.50.51.53
** server can't find erp.veridian.example: NXDOMAIN        (busybox second query, AAAA; harmless)
FAB-PC2: same, 3/3 and the same answer
FAB-PC1 -> 10.60.21.102 and 10.50.52.1: 0/2.  FAB-PC2 -> 10.60.11.1 and 10.60.10.101: 0/2
```
The first ping of a fresh flow can lose one packet (the border's map-request for the destination /24): observed 2/3 on the first run, 3/3 afterwards.

R2/R3 capture (V3). A capture of 13 packets (link SPINE1 e0/3 - BDR1 e0/3, filter `udp port 4341 or udp port 4342`); this describes what the capture shows. The CML UI dissects both ports as LISP.
```
#1  10.60.255.3 -> 10.255.60.21  UDP 15454 -> 4341  LISP flags 0x48 instance-ID 4097  inner 10.60.10.101 -> 10.50.51.53 ICMP  (frame 134 = 14+20+8+8+84)
#2  10.60.255.7 -> 10.255.60.11  UDP 15454 -> 4341  LISP flags 0x08 instance-ID 4097  inner 10.50.51.53 -> 10.60.10.101
IOT: 10.60.255.5 -> 10.255.60.21 UDP 10077 -> 4341  instance-ID 4098; return 10.60.255.7 -> 10.255.60.12
#8 Map-Request BDR1 -> MSMR1 (UDP 4342), #9 Map-Request XTR2 -> BDR1 (UDP 4342)
```
The outer source is the egress interface address, not the RLOC (as in LAB-067). The outbound packet has flags 0x48 (L and I bits: locator-status-bits present, instance-ID present); the return packet leaves the proxy ITR with 0x08 (I bit only, no locator-status-bits, because the PITR is not an ETR with a locator set it must report). Overhead = 20 + 8 + 8 = 36 bytes.

R5 comparison (three captures: LAB-067 R3 LISP data in its SOLUTION, this pcap, LAB-068 `lab068-rtr3-rtr4-vxlan.pcap`):
| | LISP (067, 069) | VXLAN (068) |
|---|---|---|
| Outer | IP + UDP dst 4341, src varies | IP (DF=1) + UDP dst 4789, src varies (53242, 51407, 58949) |
| Shim header | 8 bytes: flags (0x48 or 0x08), nonce/map-version, 24-bit instance-ID (4097, 4098), LSBs | 8 bytes: flags 0x08 (VNI valid), reserved, 24-bit VNI (5040), reserved |
| VN identifier | instance-ID | VNI |
| Payload | inner IP packet (L3) | inner Ethernet frame (L2) |
| Overhead against the inner IP packet | 36 bytes | 50 bytes (36 + 14 inner Ethernet); 148-byte frame for a ping (98-byte inner frame) |
| Control plane | LISP map server (pull) | none here (static ingress replication, flood and learn); BGP EVPN in real fabrics |

## Failure / Recovery Behaviour
Method: cable pull = `shutdown` on SPINE1 e0/3 **and** BDR1 e0/3 (named, both ends; stopping the link would leave both interfaces up). While down: PC1 and PC2 to 10.50.51.53 0/2 (the border is the only exit); XTR1 `ping vrf CORP 10.60.11.1` still works (intra-VN fabric traffic is unaffected: the border is off its path), eBGP sessions between BDR1 and FUS1 on e0/0 stay Established (they are not on the failed link), the mapping system keeps both edges registered. Restore: `no shutdown` on both ends; trigger = the `no shutdown` config block, end condition = first `Name:` line of an FAB-PC1 `nslookup erp.veridian.example 10.50.51.53` loop (a scripted CLI poll for `Name:` every 3 s, so up to one lookup cycle of granularity).

| Scenario (trigger -> end condition) | Runs (raw) | Documented range | Basis |
|---|---|---|---|
| `no shutdown` on both SPINE1-BDR1 ends -> first PC1 DNS answer | 10 s, 11 s, 13 s | 8-20 s | OSPF hello 1 / dead 4 on the p2p link brings the adjacency up in a few seconds; BGP never dropped; the edges' map-cache keeps the PETR entry; upper bound includes the 5 s nslookup retry and a first-packet map-request at the border |
| Cold start of BDR1, XTR1, XTR2 and DC-FUS1 together (F3 day-0, others running) -> first PC1 DNS answer | 94 s (7 polls, 10 s) | 90-130 s | registrations plus the BGP leak (60-90 s as in F-H); 122 s wall clock from the first `node start` |
| Full lab cold start (F1, 10 nodes) -> BOOTED | 88 s, 94 s | 85-100 s | CML boot; registrations within about 90 s afterwards |

Q7 answer is below.

## Answers to Analysis Questions
1. **Q1.** IS-IS runs directly over Layer 2 (not IP), so it has no dependency on addressing or an IP routing protocol bring-up; it carries the loopback (RLOC) routes with fast convergence and is what Catalyst Center automates for the underlay. The underlay must give every RLOC a reachable loopback (a routed access design) and enough MTU for the overlay header: 36 bytes for LISP, 50 for VXLAN with the inner Ethernet (VXLAN-GPO carries the SGT in the same 8-byte header, so SD-Access overhead is also 50 bytes, +4 with an inner 802.1Q tag; Cisco still recommends a 9100 jumbo underlay MTU). OSPF does that equally here: point-to-point links, loopbacks in area 0, same job in a lab.
2. **Q2.** SD-Access: the endpoint authenticates through 802.1X or MAB at the edge, ISE authorises it and returns a VN (VRF/instance) and an SGT (derived: Cisco SD-Access design guide); the edge assigns the port to the VN dynamically. Here the VN is static: the interface is in a VRF (`vrf forwarding CORP`), no SGT exists, and a host moved to another port or edge keeps no identity.
3. **Q3.** In SD-Access every edge answers for the same gateway IP and MAC (anycast gateway), so a host that moves keeps its address and gateway and only its EID registration moves (a new map-register with the new RLOC). Here each edge has its own gateway (.1 in its own /24), so a moved host would have the wrong subnet and gateway; moving a host also needs the subnet to be registered at the new edge, so the move would not work without a change (LAB-067 Q5).
4. **Q4.** An ITR encapsulates only when it has a mapping for the destination. The MS holds no mapping for 10.50.51.53, so it answered with a negative map-reply (`forward-native`): with no PETR configured the ITR forwards natively, finds no route in the VN table and drops (`!H` at the edge). With `use-petr` the negative entry means "send to the PETR": the packet goes encapsulated to the border, which as proxy-ETR decapsulates it into VRF CORP/IOT and routes it to the fusion. The DC's reply returns to the border (via the /23 it learned); the border has no registered EID for it, so it is a proxy-ITR: it resolves the destination /24 through a map-request and encapsulates to the right edge, using `map-cache <VN /23> map-request` so the /23 Null0 does not discard it. In the registered-default fallback the border would register `0.0.0.0/0` (or 10.50.51.0/24) per VN as an ordinary xTR, so the edges would get a positive mapping toward the border instead of a negative reply and `use-petr` would be unnecessary.
5. **Q5.** The fusion sits outside so that the fabric needs no knowledge of the shared services and the rest of Veridian's network (policy and route leaking happen in one place, the same on traditional and fabric sides), and a change on one side does not touch the other. If the shared services lived in a VN, the VN would have to be extended to them (a LISP-registered subnet or a second fabric site), and every consumer VN would need inter-VN leaking inside the fabric, which a LISP fabric does not do natively (it needs a border route-leak or extranet), losing the single point of policy.
6. **Q6.** The requirement is the inner IP MTU plus the overlay header at every IP hop of the path: 1500 + 36 = 1536 bytes for LISP here (1550 for VXLAN with the inner Ethernet), on SPINE1's links, the edges' uplinks and the border link. Raise the interface MTU on every underlay link (fabric side; on the handoff only if the data centre sees encapsulated frames, which it does not: the border decapsulates, so the handoff stays at 1500). Raising the underlay is cheaper than lowering every host's MTU/MSS.
7. **Q7.** With a second border (a second PETR/PITR, both advertised to the fusion with the same /23 and a preference), the edges would use whichever border is reachable: the map-cache `use-petr` can list two PETRs, and the cable pull would not cut the VNs off from the shared services. This lab has one border, so the pull removes the only exit while the intra-fabric traffic keeps working (measured); the cost of the second border is the return-path symmetry (two borders advertising the same /23 may split flows, and stateful devices on the fusion side would drop asymmetric traffic).

R1 answers beyond Q: LISP instance 4097 is CORP and 4098 is IOT (proved by `eid-table vrf` in each instance, the MS site table and the capture's instance-ID); the policy plane (SGT, SGACL) is ISE/TrustSec, not present in this lab (LAB-070 covers TrustSec by hand) and the management plane is Catalyst Center. R6: between 051 and this lab only the fusion's accepted prefixes changed (CORP-USERS and IOT-USERS from the /24 of 051's VN LANs to the /23 `le 24`); BGP sessions, VRFs, route-targets, DNS and the SHARED table are unchanged (diff of FUS1 between `environments/FAB/F-H/` and F3 = the two prefix-list lines). That is the point of a fusion router: the traditional side's contract (which prefixes it accepts, which it leaks to whom) is independent of whether a VRF-lite block or a fabric sits behind the border. If fusion static routes for the fabric aggregates had been needed, the fusion would have needed to know about the fabric; origination at the border keeps the fabric's reachability its own business.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-17 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), dnsmasq, iol-xe (IOS XE 17.16.1a) |
