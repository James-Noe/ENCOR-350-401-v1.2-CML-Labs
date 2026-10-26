# LAB-056 — Solution

## Summary

Educational intent: build a complete campus-plus-WAN multicast service on a design the student already knows (H3 campus, W2 tunnel) and measure what its failures cost. The student places PIM-SM on the four routers of the video path only (switches never route multicast on this platform), uses an anycast RP on both cores with MSDP, aligns the PIM DR with the VRRP master and shortens the PIM hello to 1 s on the video subinterfaces, carries the stream over the GRE-over-IPsec Tunnel21 and proves from the underlay that only ESP, IKE and NTP cross the Internet link. Blueprint mapping: 3.3.d:R (PIM-SM, RP, IGMP, MSDP), X-IGMPSnoop:I (IGMP snooping tables and mrouter ports on HQ-ACC1), 3.1.a:R (802.1Q trunks carrying the video VLANs), 2.2.b:R (GRE and IPsec tunnels). Prerequisites 055, 048, 037. Output stage: `environments/HQ/H4/`.

Platform deviations (see "Deviations" below): ioll2-xe IGMP snooping learns groups and mrouter ports but does not forward multicast that arrives on a trunk, so VLANs 20 and 50 run with snooping disabled on HQ-DIST1, HQ-DIST2, HQ-ACC2 and HQ-ACC3 (already in the student start state); HQ-ACC1 keeps the default so students can observe the learning. LAB.md carries only a neutral platform note.

## Intentional Faults

None (X lab).

## Diagnosis / Methodology

Not a troubleshooting lab. Suggested method: (1) build the control plane router by router (multicast-routing, PIM on the interfaces on the path, RP, MSDP), checking `show ip pim neighbor` after each hop; (2) start a viewer on HQ-PC2 and follow `show ip mroute 239.10.20.1` from the source side to the receiver side; (3) repeat on BR1-PC1 over Tunnel21; (4) read the underlay counters; (5) run the failure tests with the viewer's interval output and a `tcpdump` gap monitor as the clock.

Wrong turns a student can take (derived from the design rules; only the snooping one was observed): PIM on the DIST/ACC SVIs (hosts then receive every packet twice and VLAN 10 would receive video: R6); a plain `ip pim rp-address` on the cores without Loopback10 in OSPF (the RP address is not reachable from BR1 (derived)); turning on snooping in VLANs 20/50 (the stream stops at the first trunk: see the deviation; the tables show the group and the router port, yet nothing is delivered).

## Solution Configuration

Start state: H3 plus the WAN attachment, snooping already off in VLANs 20/50 on DIST1, DIST2, ACC2, ACC3 (day-0 lines `no ip igmp snooping vlan 20|50`). The delta below is what the student adds (as tested, applied in config mode on each device); the complete solved configs are the H4 stage (`environments/HQ/H4/README.md`).

**HQ-CORE1**
```
ip access-list standard OPS-VIDEO
 permit 239.10.20.0 0.0.0.255
ip multicast-routing
ip pim rp-address 10.255.10.100
interface Loopback10
 ip address 10.255.10.100 255.255.255.255
 ip ospf 1 area 0
 ip pim sparse-mode
interface Loopback0
 ip pim sparse-mode
interface Ethernet0/0
 ip pim sparse-mode
interface Ethernet1/0
 ip pim sparse-mode
interface Ethernet0/1.20
 ip pim sparse-mode
 ip pim query-interval 1
 ip igmp access-group OPS-VIDEO
interface Ethernet0/1.50
 ip pim sparse-mode
 ip pim query-interval 1
 ip pim dr-priority 200
ip msdp peer 10.255.10.2 connect-source Loopback0
ip msdp originator-id Loopback0
```

**HQ-CORE2**
```
ip access-list standard OPS-VIDEO
 permit 239.10.20.0 0.0.0.255
ip multicast-routing
ip pim rp-address 10.255.10.100
interface Loopback10
 ip address 10.255.10.100 255.255.255.255
 ip ospf 1 area 0
 ip pim sparse-mode
interface Loopback0
 ip pim sparse-mode
interface Ethernet0/0
 ip pim sparse-mode
interface Ethernet0/2.20
 ip pim sparse-mode
 ip pim query-interval 1
 ip pim dr-priority 200
 ip igmp access-group OPS-VIDEO
interface Ethernet0/2.50
 ip pim sparse-mode
 ip pim query-interval 1
ip msdp peer 10.255.10.1 connect-source Loopback0
ip msdp originator-id Loopback0
```

**HQ-WAN1**
```
ip multicast-routing
ip pim rp-address 10.255.10.100
interface Ethernet0/2
 ip pim sparse-mode
interface Tunnel21
 ip pim sparse-mode
```

**BR1-RTR1**
```
ip multicast-routing
ip pim rp-address 10.255.10.100
interface Tunnel21
 ip pim sparse-mode
interface Ethernet0/2.10
 ip pim sparse-mode
```

**HQ-DIST1**
```
no ip igmp snooping vlan 20
no ip igmp snooping vlan 50
```

**HQ-DIST2**
```
no ip igmp snooping vlan 20
no ip igmp snooping vlan 50
```

**HQ-ACC2**
```
no ip igmp snooping vlan 20
```

**HQ-ACC3**
```
no ip igmp snooping vlan 50
```

The four switch lines `no ip igmp snooping vlan 20|50` are in the student start state; they are the delta's snooping part (see Deviations).

## Verification

Captured on the re-imported lab with the solution applied and a viewer on HQ-PC2 (PC2 viewer 60-80 s intervals `0/244 (0%)`, `0/243 (0%)`; encoder 512 kb/s). Part 1b measured a 60 s window on both viewers: PC2 0/972 and 0/973 in two successive 20 s intervals (0 %), BR1-PC1 likewise 0 %.

HQ-CORE1 `show ip pim neighbor` and `show ip pim interface` (CORE2 is DR on VLAN 20 with priority 200, CORE1 on VLAN 50):
```
PIM Neighbor Table
Mode: B - Bidir Capable, DR - Designated Router, N - Default DR Priority,
      P - Proxy Capable, S - State Refresh Capable, G - GenID Capable,
      L - DR Load-balancing Capable
Neighbor          Interface                Uptime/Expires    Ver   DR
Address                                                            Prio/Mode
10.10.255.1                             Ethernet0/0              00:01:36/00:01:36 v2    1 / DR S P G
10.10.255.97                            Ethernet1/0              00:01:34/00:01:39 v2    1 / DR S P G
10.10.20.3                              Ethernet0/1.20           00:01:36/00:00:02 v2    200/ DR S P G
10.10.50.3                              Ethernet0/1.50           00:01:35/00:00:02 v2    1 / S P G
10.255.10.100    Loopback10               v2/S   0      30     1          10.255.10.100
10.255.10.1      Loopback0                v2/S   0      30     1          10.255.10.1
10.10.255.0      Ethernet0/0              v2/S   1      30     1          10.10.255.1
10.10.255.96     Ethernet1/0              v2/S   1      30     1          10.10.255.97
10.10.20.2       Ethernet0/1.20           v2/S   1      1      1          10.10.20.3
10.10.50.2       Ethernet0/1.50           v2/S   1      1      200        10.10.50.2
```
HQ-CORE1 `show ip mroute 239.10.20.1` (RP and source router: register flag F, the OIL is the WAN link; VLAN 20 is served by CORE2, the DR):
```
(*, 239.10.20.1), 00:01:38/00:03:13, RP 10.255.10.100, flags: SF
  Incoming interface: Null, RPF nbr 0.0.0.0
  Outgoing interface list:
    Ethernet1/0, Forward/Sparse, 00:01:15/00:03:13, flags: 
(10.10.50.103, 239.10.20.1), 00:01:38/00:02:54, flags: FTA
  Incoming interface: Ethernet0/1.50, RPF nbr 0.0.0.0
  Outgoing interface list:
    Ethernet1/0, Forward/Sparse, 00:01:15/00:03:13, flags:
```
HQ-CORE2 (MSDP-created source state, OIL VLAN 20) and MSDP:
```
(*, 239.10.20.1), 00:01:37/stopped, RP 10.255.10.100, flags: SJC
  Incoming interface: Null, RPF nbr 0.0.0.0
  Outgoing interface list:
    Ethernet0/2.20, Forward/Sparse, 00:01:17/00:02:23, flags: 
(10.10.50.103, 239.10.20.1), 00:01:37/00:01:22, flags: T
  Incoming interface: Ethernet0/2.50, RPF nbr 0.0.0.0
  Outgoing interface list:
    Ethernet0/2.20, Forward/Sparse, 00:01:17/00:02:23, flags:
MSDP Source-Active Cache - 1 entries
(10.10.50.103, 239.10.20.1), RP 10.255.10.1, AS ?,00:00:38/00:05:21, Peer 10.255.10.1
Connection status:
    State: Up, Resets: 0, Connection source: Loopback0 (10.255.10.1)
    Connection and counters cleared 00:01:38 ago
```
HQ-WAN1 and BR1-RTR1 (PIM neighbours over Tunnel21, (S,G) across the tunnel, incoming Tunnel21 on BR1):
```
PIM Neighbor Table
Mode: B - Bidir Capable, DR - Designated Router, N - Default DR Priority,
      P - Proxy Capable, S - State Refresh Capable, G - GenID Capable,
      L - DR Load-balancing Capable
Neighbor          Interface                Uptime/Expires    Ver   DR
Address                                                            Prio/Mode
10.10.255.96                            Ethernet0/2              00:01:36/00:01:36 v2    1 / S P G
10.250.21.21                            Tunnel21                 00:01:35/00:01:37 v2    1 / S P G
(*, 239.10.20.1), 00:01:17/00:03:11, RP 10.255.10.100, flags: S
  Incoming interface: Ethernet0/2, RPF nbr 10.10.255.96
  Outgoing interface list:
    Tunnel21, Forward/Sparse, 00:01:17/00:03:11, flags: 
(10.10.50.103, 239.10.20.1), 00:01:17/00:01:42, flags: T
  Incoming interface: Ethernet0/2, RPF nbr 10.10.255.96
  Outgoing interface list:
    Tunnel21, Forward/Sparse, 00:01:17/00:03:11, flags:
PIM Neighbor Table
Mode: B - Bidir Capable, DR - Designated Router, N - Default DR Priority,
      P - Proxy Capable, S - State Refresh Capable, G - GenID Capable,
      L - DR Load-balancing Capable
Neighbor          Interface                Uptime/Expires    Ver   DR
Address                                                            Prio/Mode
10.250.21.1                             Tunnel21                 00:01:36/00:01:35 v2    1 / S P G
(*, 239.10.20.1), 00:01:18/stopped, RP 10.255.10.100, flags: SJC
  Incoming interface: Tunnel21, RPF nbr 10.250.21.1
  Outgoing interface list:
    Ethernet0/2.10, Forward/Sparse, 00:01:18/00:02:31, flags: 
(10.10.50.103, 239.10.20.1), 00:01:18/00:01:41, flags: JT
  Incoming interface: Tunnel21, RPF nbr 10.250.21.1
  Outgoing interface list:
    Ethernet0/2.10, Forward/Sparse, 00:01:18/00:02:31, flags:
```
RPF decisions (Q2):
```
BR1-RTR1: RPF interface: Tunnel21 / RPF neighbor: ? (10.250.21.1)
HQ-WAN1:  RPF interface: Ethernet0/2 / RPF neighbor: ? (10.10.255.96)
HQ-CORE2: RPF interface: Ethernet0/2.50 / RPF neighbor: 10.10.50.103 - directly connected (RPF type: multicast (connected))
BR1-RTR1 RP 10.255.10.100: RPF interface: Tunnel21, neighbor 10.250.21.1
```
IGMP and join policy (VLAN 20: reporter 10.10.20.102 on both cores; `Inbound IGMP access group is OPS-VIDEO`; querier CORE1 10.10.20.2 by lowest address):
```
IGMP Connected Group Membership
Group Address    Interface                Uptime    Expires   Last Reporter   Group Accounted
239.10.20.1      Ethernet0/1.20           00:01:16  00:02:24  10.10.20.102
```
IGMP snooping (R5, V7). HQ-ACC1 (default snooping; VLAN 20 uplink Et0/1, group learned from reports flooded by the non-snooping switches above):
```
Vlan      Group/source             Type        Version     Port List
-----------------------------------------------------------------------
20        239.10.20.1              I           v2          Et0/1
Vlan    ports
----    -----
  20    Et0/1(dynamic)
```
HQ-ACC2, HQ-DIST1/2 and HQ-ACC3 show `IGMP snooping Admin State : Disabled` for VLANs 20/50, so their group and mrouter tables are empty.

Underlay (PROV-INET1 counters-only ACL `CAP-IN` inbound on e0/0 and e0/1 after 25 min of stream): `permit esp (81169 matches)`, `permit gre` 0, `permit ip any 224.0.0.0/4` 0, `permit udp eq isakmp (4)`, `eq non500` 0, `eq ntp (42)`, `permit ip any any` 0. Only ESP, IKE and NTP cross the Internet links. (Students can add the same ACL, or a CML capture on the BR1-PROV link.)

HQ-PC1 viewer: no data lines at all (VLAN 10 never receives).

MTU (Q8): the 1344-byte packets cross Tunnel21 (`ip mtu 1400`) with 0 fragmented and 0 "couldn't fragment" on HQ-WAN1 and BR1-RTR1 in 15 s of stream. A 1498-byte packet (`iperf -l 1470`, group 239.10.20.7) is dropped, not fragmented: HQ-WAN1 `0 fragmented, 0 fragments, 498 couldn't fragment`; BR1-PC1 receives nothing (the Linux sender sets DF). Payloads over 1372 bytes with DF are dropped at the tunnel.

## Failure / Recovery Behaviour

Method: node stop of the router after `write memory` (silent failure for neighbours; the REST stop returns 4-8 s after the command, the media stop is at its completion). Clock: `tcpdump -tt` gap monitor on the viewer host (threshold 0.15 s; the stream is about 48 packets/s, so each gap line is a media gap); BR1 return timed with host `date +%s` from the start call.

| Scenario (trigger -> end condition) | Runs (raw) | Documented range | Basis |
|---|---|---|---|
| Stop HQ-CORE2 (VLAN 20 DR and VRRP master) -> OPS viewer (PC2) receives again | 2.80 s, 2.59 s, 2.08 s (BR1 unaffected) | 2-4 s | measured; derived bound: PIM hello holdtime 3.5 s (query-interval 1 x 3.5); CORE1 already holds the (S,G) and takes over as DR |
| Start HQ-CORE2 (it becomes DR at its first PIM hello) -> gap above 0.15 s on PC2 | none in 3 runs (only "1 datagrams received out-of-order") | 0-2 s | measured; CORE2 holds the (S,G) from the flooded VLAN 50 frames, so forwarding resumes before CORE1 stops |
| Stop HQ-CORE1 (VLAN 50 DR and VRRP master, RP, BR1's only HQ path) -> PC2 gap | none (< 0.15 s) in 4 runs | none to 4 s | measured; CORE2 is RP at the same anycast address and already holds the state |
| Stop HQ-CORE1 -> BR1-PC1 stream | lost until CORE1 returns; gaps 316.95 s (stopped 5 min), 33.06 s, 29.64 s, 39.13 s | start call + 9-20 s | measured (12-15 s, 9.6-10.2 s); BR1 has one HQ attachment |
| Start HQ-CORE1 -> BR1-PC1 receives again | 15 s, 12 s, 14 s after the start call (call itself 4-6 s of that); 10.2, 9.6, 9.95 s | 9-20 s | measured (boot, OSPF, IPsec, PIM) |

Restore gap: Q7's expectation (a brief stop when the DR returns before it has state) is not reproduced; the returning DR already has the (S,G), so only a duplicate or reordered datagram is seen. CML restarts CORE2 within about 20 s; VRRP 20 returned MASTER 21 s after node start in each run. After the runs CORE1 shows `(10.10.50.103, 239.10.20.1)` FTA again and MSDP is Up on both.

## Answers to Analysis Questions

- **Q1** The IGMP querier is HQ-CORE1 (10.10.20.2): the querier is the lowest IP address on the segment. The DR is HQ-CORE2 (10.10.20.3): the DR is the highest priority (200 set by the lab, equal to the VRRP master), ties by address. Different elections, different tie-breakers: querier != DR is normal (shown by `show ip igmp interface` and `show ip pim interface`).
- **Q2** BR1-RTR1: the source lies in 10.10.50.0/24, learned by OSPF over Tunnel21 from 10.250.21.1, so the RPF interface is Tunnel21 (the RP 10.255.10.100 is also reached over Tunnel21). HQ-WAN1: the route is via CORE1 (10.10.255.96) on Ethernet0/2. HQ-CORE2: the source is on its own Ethernet0/2.50, "directly connected".
- **Q3** (Analysis, from the tunnel design; lab 047 evidence.) The tunnel is a GRE interface: it carries multicast and PIM hellos in GRE, and IPsec (`tunnel protection`) encrypts the whole GRE packet, so the Internet sees only ESP. A crypto map is not an interface and matches an ACL of unicast flows between two peers: multicast destinations (224.0.0.0/4) and PIM hellos are not tunnelled by it, so neighbours do not form across it.
- **Q4** MSDP carries source-active messages (source, group, originating RP) between the RPs so each core learns the sources registered at the other, although both use the same RP address. CORE2's SA cache shows `(10.10.50.103, 239.10.20.1), RP 10.255.10.1`. While one core is stopped the MSDP session is down and the surviving core is the RP at the same address; a new source registers with it (anycast routing reaches it), so no SA is needed.
- **Q5** HQ-ACC1 learns group 239.10.20.1 for VLAN 20 on its uplink Et0/1 and shows Et0/1 as dynamic mrouter port: the uplinks carry the reports (flooded by the non-snooping switches above) and the stream. Its host port Et1/0 is in VLAN 10, so VLAN 20 traffic is never delivered there; PC1 (V5) sees nothing. Debrief on the platform limit: snooping restricting a stream to a host port is not observable on this bench, because HQ-ACC1 has no VLAN 20 host and snooping is off on the other switches. With a VLAN 20 viewer behind a snooping-capable access switch, its tables would add that host's port to the group's port list next to the mrouter uplink (general IOS behaviour, not measured here). HQ-ACC2's tables are empty because snooping is off there.
- **Q6** BR1's video stops when CORE1 stops (its only WAN attachment, HQ-CORE1 e1/0) and returns about 9-20 s after CORE1 starts (measured 9.6-15 s). A second WAN attachment (HQ-WAN1 to CORE2, or a second hub with its own Internet link) removes the dependency.
- **Q7** The DR role returns first (CORE2 becomes DR at its first PIM hello after the restart; the VRRP master returned 21 s after node start, see the table), so the DR precedes the gateway. The video did not stop in the three runs (no gap above 0.15 s): CORE2 had the (S,G) from the source frames, so it forwarded before CORE1 stopped. A stop would show where the returning DR has no (S,G) state yet.
- **Q8** A 1498-byte packet exceeds the tunnel `ip mtu 1400`, carries DF and is dropped (HQ-WAN1: 498 "couldn't fragment"); the encoder's 1344-byte packets fit.

## Build notes

1. IGMP snooping disabled for VLANs 20/50 on HQ-DIST1, HQ-DIST2, HQ-ACC2, HQ-ACC3. On ioll2-xe, with snooping on, routed multicast frames arriving on a trunk are not forwarded: VLAN 20 group learned (`20 239.10.20.1 I v2 Et1/0`), mrouter Et0/1 dynamic, no delivery to PC2; a static group entry also no; a VLAN 50 source to a static mrouter port (`ip igmp snooping vlan 50 mrouter interface Et0/0`), no delivery; explicit tracking removal and report suppression made no difference; `no ip igmp snooping vlan N` on every hop restores delivery. This is a CML platform limitation, so R5/Q5 and the snooping check use the HQ-ACC1 tables.
2. Q7 / restore gap: 0 (see table).
3. Underlay proof is counters (ACL `CAP-IN` on PROV-INET1), not a CML capture.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-14 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), iol-xe (IOS XE 17.16.1a), ioll2-xe (IOS XE 17.16.1a), radius |
