# LAB-051 — Solution

## Summary

Aster Warehousing's two virtual networks (CORP, IOT) arrive on one link from FAB-BDR1 as dot1q subinterfaces, each in its own VRF with its own eBGP session. DC-FUS1 is the fusion router: three VRFs (CORP, IOT, SHARED) and local route-target leaking between them, controlled by export maps built on prefix-lists. SHARED is the VRF that speaks OSPF area 50 to DC-RTR1 (the data centre sees the fusion router as one more neighbour), so DC-RTR1 needs no VRF knowledge. Only 10.50.51.0/24 crosses from SHARED to CORP and IOT; only the two Aster user subnets cross from CORP and IOT to SHARED, then to OSPF as E2 routes (the return path). A second shared service is one `ip prefix-list SHARED-SERVICES` line.

Blueprint: 1.3.b (handoff part; fusion router role), 2.2.a (VRF-lite, route targets), 3.2.c (eBGP, route-maps). Proven platform behaviour: (a) local route-target leaking with `export map` on iol-xe with no VPNv4 neighbour, (b) per-VRF eBGP on dot1q subinterfaces, (c) dnsmasq `address=` answers alpine `nslookup`.

Platform notes: iol-xe 17.16.1a (CML 2.10.0); settling time after boot or config about 60 to 90 s (eBGP update timer 30 s); consoles open privileged; the extra `** server can't find ...: NXDOMAIN` line from `nslookup` is the AAAA (IPv6) query, harmless; show commands are `show ip bgp vpnv4 vrf X [summary]` (`show bgp vrf X` is invalid on this image); `clear bgp vrf IOT ipv4 unicast *` is accepted and confirm-free, but `clear ip bgp vpnv4 vrf IOT *` is invalid. BGP is unauthenticated. The stage `environments/FAB/F-H/` holds the solved configs of all nodes.

Design notes: (1) DC-RTR1 has a Loopback52 10.50.52.1/24 (OSPF area 50), reserved as the "second shared service", so R4 can be demonstrated on DC-FUS1 only; (2) all five route-maps match prefix-lists, so R4 is one prefix-list line; (3) DC-FUS1's start state keeps Ethernet0/1 up and unaddressed and 10.200.60.0/31 is left free for F2; (4) no BGP authentication.

## Intentional Faults

None. This is an Implementation lab; the start state is incomplete (DC-FUS1 has addressing only), not faulty.

## Diagnosis / Methodology

Concepts the LAB.md primer gives (RD makes identical prefixes distinct in BGP and does not control sharing; the RT decides which VRFs import what; an export map restricts what a VRF exports; OSPF-only DC-RTR1 needs redistribution at the fusion router). Compare after solving: the two layers in step 3 below are the RTs (who imports) and the export maps (what is exported with it).

Design reasoning the student should follow (R5):

1. Two routing domains on one link must be separated before anything else: dot1q 3001 and 3002 with their own VRF and eBGP session each. Check `show ip interface brief`, `show ip bgp vpnv4 vrf CORP summary`.
2. The shared segment is global/OSPF on the Veridian side, but must be visible in both customer tables and the customers in it: that is the fusion function. A third VRF (SHARED) takes the DC-RTR1 link and acts as the meeting point; the customer VRFs import only SHARED's tag and SHARED imports both customer tags, so CORP and IOT never import each other's tag (R3, Q2).
3. Leaks are controlled twice: tags (who imports what) and export maps (what is allowed to be exported with it). Without the maps SHARED would export Loopback 10.255.50.1 and 10.50.52.0/24 as well.
4. The return path: Aster prefixes in SHARED (BGP) are redistributed into OSPF (E2 via BGP-TO-OSPF, prefix-list limited); the shared segment prefix goes back into BGP with OSPF-TO-BGP so it can be exported into the VRFs.
5. Plausible wrong paths ruled out: (a) default route on BDR1 towards FUS1 - not needed and would leak other prefixes; (b) a single VRF for both Aster networks - the two networks would meet (Q2); (c) a global handoff on 10.200.60.0/31 - reserved for the fabric stage.

Start-state evidence: `show ip bgp summary` returns `% BGP not active`; BDR1 neighbours `never Active`; PCs reach only their gateway.

## Solution Configuration

DC-FUS1 only (the other five nodes unchanged). Order matters only for the VRF definitions before interfaces; apply as one block (it equals the FAB F-H stage's DC-FUS1 config):

```
ip prefix-list SHARED-SERVICES seq 10 permit 10.50.51.0/24
ip prefix-list CORP-USERS seq 10 permit 10.60.10.0/24
ip prefix-list IOT-USERS seq 10 permit 10.60.20.0/24
route-map SHARED-EXP permit 10
 match ip address prefix-list SHARED-SERVICES
route-map CORP-EXP permit 10
 match ip address prefix-list CORP-USERS
route-map IOT-EXP permit 10
 match ip address prefix-list IOT-USERS
route-map OSPF-TO-BGP permit 10
 match ip address prefix-list SHARED-SERVICES
route-map BGP-TO-OSPF permit 10
 match ip address prefix-list CORP-USERS
route-map BGP-TO-OSPF permit 20
 match ip address prefix-list IOT-USERS
vrf definition CORP
 rd 65010:1
 address-family ipv4
  export map CORP-EXP
  route-target export 65010:1
  route-target import 65010:50
 exit-address-family
vrf definition IOT
 rd 65010:2
 address-family ipv4
  export map IOT-EXP
  route-target export 65010:2
  route-target import 65010:50
 exit-address-family
vrf definition SHARED
 rd 65010:50
 address-family ipv4
  export map SHARED-EXP
  route-target export 65010:50
  route-target import 65010:1
  route-target import 65010:2
 exit-address-family
interface Ethernet0/0
 vrf forwarding SHARED
 ip address 10.50.255.1 255.255.255.254
 ip ospf network point-to-point
 ip ospf hello-interval 1
 ip ospf dead-interval 4
 ip ospf 50 area 50
interface Ethernet0/1.3001
 encapsulation dot1q 3001
 vrf forwarding CORP
 ip address 10.200.60.2 255.255.255.254
interface Ethernet0/1.3002
 encapsulation dot1q 3002
 vrf forwarding IOT
 ip address 10.200.60.4 255.255.255.254
router ospf 50 vrf SHARED
 router-id 10.255.50.5
 passive-interface default
 no passive-interface Ethernet0/0
 redistribute bgp 65010 subnets route-map BGP-TO-OSPF
router bgp 65010
 bgp router-id 10.255.50.5
 bgp log-neighbor-changes
 address-family ipv4 vrf CORP
  neighbor 10.200.60.3 remote-as 65060
  neighbor 10.200.60.3 activate
 exit-address-family
 address-family ipv4 vrf IOT
  neighbor 10.200.60.5 remote-as 65060
  neighbor 10.200.60.5 activate
 exit-address-family
 address-family ipv4 vrf SHARED
  redistribute ospf 50 route-map OSPF-TO-BGP
 exit-address-family
```

Notes: the `vrf forwarding` on Ethernet0/0 removes the existing address, so it is re-entered in the same block. R4 (test prefix), then removal:

```
ip prefix-list SHARED-SERVICES seq 20 permit 10.50.52.0/24
no ip prefix-list SHARED-SERVICES seq 20 permit 10.50.52.0/24
```

One line serves SHARED-EXP (export to CORP/IOT) and OSPF-TO-BGP (OSPF into BGP). The BGP-to-OSPF direction needs nothing for a new service.

## Verification

Captured on a fresh import, about 2 minutes after applying the block.

DC-FUS1:

```
show ip ospf neighbor
10.255.50.1       0   FULL/  -        00:00:03    10.50.255.0     Ethernet0/0
show ip bgp vpnv4 all summary | begin Neighbor
10.200.60.3     4        65060       5       6        8    0    0 00:02:02        1
10.200.60.5     4        65060       5       6        8    0    0 00:01:57        1
show ip route vrf SHARED
O        10.50.51.0/24 [110/20] via 10.50.255.0, Ethernet0/0
O        10.50.52.0/24 [110/11] via 10.50.255.0, Ethernet0/0
C        10.50.255.0/31 is directly connected, Ethernet0/0
B        10.60.10.0/24 [20/0] via 10.200.60.3 (CORP)
B        10.60.20.0/24 [20/0] via 10.200.60.5 (IOT)
O        10.255.50.1/32 [110/11] via 10.50.255.0, Ethernet0/0
show ip route vrf CORP | include ^B|^O
B        10.50.51.0/24 [20/20] via 10.50.255.0 (SHARED), Ethernet0/0
B        10.60.10.0/24 [20/0] via 10.200.60.3
show ip route vrf IOT | include ^B|^O
B        10.50.51.0/24 [20/20] via 10.50.255.0 (SHARED), Ethernet0/0
B        10.60.20.0/24 [20/0] via 10.200.60.5
```

FAB-BDR1 and DC-RTR1:

```
FAB-BDR1# show ip route vrf CORP bgp | include ^B
B        10.50.51.0/24 [20/0] via 10.200.60.2
FAB-BDR1# show ip route vrf IOT bgp | include ^B
B        10.50.51.0/24 [20/0] via 10.200.60.4
DC-RTR1# show ip route ospf | include ^O
O E2     10.60.10.0/24 [110/1] via 10.50.255.1, Ethernet0/2
O E2     10.60.20.0/24 [110/1] via 10.50.255.1, Ethernet0/2
```

Hosts (identical result from FAB-PC1 and FAB-PC2 unless noted):

```
nslookup erp.veridian.example 10.50.51.53
Name:	erp.veridian.example
Address: 10.50.51.53
** server can't find erp.veridian.example: NXDOMAIN        <- the AAAA query
nslookup dns1.veridian.example           (PC1; resolver preset)  -> Address: 10.50.51.53
ping 10.50.51.53 / 10.50.51.1            0% packet loss
ping other PC / 10.255.50.1 / 10.50.50.1 / 10.50.52.1   100% packet loss (both PCs)
PC1: traceroute -n 10.50.51.53:  10.60.10.1, 10.200.60.2, 10.50.255.0, 10.50.51.53
PC2: traceroute -n 10.50.51.53:  10.60.20.1, 10.200.60.4, 10.50.255.0, 10.50.51.53
```

R4 (test run): after the seq 20 line, BDR1 vrf IOT gained `B 10.50.52.0/24 via 10.200.60.4` within 3 s; PC2 pinged 10.50.52.1 (64 bytes, ttl 42); PC1's first ping was lost during propagation and it reached the address a few seconds later. Nothing else in any table changed. The leaked Loopback0 10.255.50.1 is in SHARED (OSPF) but is never in CORP or IOT (blocked by SHARED-EXP).

Observed side effect: the traceroute shows DC-FUS1's CORP-side address (10.200.60.2) as hop 2 and DC-RTR1's fusion-link address as hop 3; the fusion router appears with the Aster-facing address.

## Failure / Recovery Behaviour

| Scenario (trigger -> end condition) | Runs (raw) | Documented range | Basis |
|---|---|---|---|
| `clear bgp vrf IOT ipv4 unicast *` on DC-FUS1 -> BDR1 IOT session Established with 2 prefixes, uptime under 1 min (a scripted CLI poll, excludes the ~8 s connect) | 1, 4, 4 s | 1-10 s | session re-open plus initial update; BGP connect/hold timers not involved |
| Cable pull (`shutdown` on DC-FUS1 e0/1 and FAB-BDR1 e0/0, then `no shutdown` on both) -> first successful FAB-PC1 ping to 10.50.51.53 | 12, 16, 19, 9, 12, 7 s | 7-35 s, varies run to run | session setup plus eBGP advertisement interval 30 s |

Observations: during the cable pull both PCs lose 10.50.51.53 (100% loss) but their gateway still answers; DC-FUS1's sessions go Idle, SHARED holds no B routes, DC-RTR1 has no E2 routes. After the clear, the CORP session uptime kept running (7:30, 7:44, 7:58 across the runs): unaffected. PC2 recovered at the same moment as PC1. A node stop was not tested. The cable pull is two-ended `shutdown` (a one-ended shutdown leaves the peer port up and relies on BGP hold timers, 180 s, not tested).

## Answers to Analysis Questions

**Q1.** The two Aster networks are separately routed tables; the data centre has one table. Something must hold both customer tables and the data centre table at once and decide, prefix by prefix, what crosses between them. Connecting each network to DC-RTR1 directly would put Aster prefixes into the global table, where nothing keeps CORP and IOT apart and no filter exists on Veridian's side. The fusion router is also the single place to filter, to add services and to insert policy.

**Q2.** CORP and IOT import only the tag 65010:50, which only SHARED exports; neither imports the other's tag, and SHARED exports only 10.50.51.0/24. It would break if any VRF imported 65010:1 or :2 besides SHARED, if the export maps were removed (SHARED would export every OSPF route and BGP-learnt prefix) or if a VRF were to export a prefix that the other network's import accepted. Note that the OSPF E2 routes make DC-RTR1 aware of both Aster subnets, but the customer VRFs never import them.
**Q3.** 65010:1 is exported by CORP (its user subnet through CORP-EXP) and imported by SHARED; 65010:2 is the same for IOT; 65010:50 is exported by SHARED (only 10.50.51.0/24 through SHARED-EXP) and imported by CORP and IOT. The prefix-lists hold back everything else (loopback 10.255.50.1, 10.50.52.0/24, any Aster /31).

**Q4.** With statics, each shared prefix needs one static route per customer VRF (`ip route vrf CORP ...`, `ip route vrf IOT ...`, pointing out of the SHARED table) plus the return statics and redistributions, and every new service repeats it for all VRFs, with no tracking of reachability. With tags and a prefix-list, R4 is the one line in SHARED-SERVICES and the routing protocol withdraws the leak if the service goes away. The cost grows as services times VRFs with statics; it is constant with tags.
**Q5.** In SD-Access the border node hands each virtual network to an external device, one VRF-lite subinterface and BGP session per VN, exactly the handoff built here; the external router (the fusion router) performs the leaking between VRFs and the shared services; labs 068/069 re-frame F-H this way (Aster's BDR1 is the border).

**Q6.** DC-RTR1 has no VRFs and no BGP with Aster; its only way to know a return path to 10.60.10.0/24 and 10.60.20.0/24 is OSPF from DC-FUS1. Without the redistribution the replies from DC-DNS1 would have no route and would be dropped. The loopbacks are in SHARED (OSPF) but never exported to CORP or IOT by SHARED-EXP, so Aster never learns them (and Aster's own routes to them do not exist).

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-17 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), dnsmasq, iol-xe (IOS XE 17.16.1a) |
