# LAB-055 — Solution

## Summary

Foundation lab for module 08: RP discovery by Auto-RP and BSR, their failover times, SSM with IGMPv3, and the observation of bidirectional PIM and anycast RP with MSDP. Blueprint 3.3.d (PIM-SM, RP discovery, SSM, bidir, MSDP). Environment FND T-MC (4 iol-xe routers, 2 alpine hosts); builds on LAB-054's end state plus two pre-built ranges (bidir 239.2.0.0/16, RP R2 Loopback2 10.255.0.22; anycast 239.3.0.0/16, RP 10.255.0.100 on R3/R4 Loopback100, MSDP R3-R4 Loopback0 with `originator-id Loopback0`).

Platform notes (iol-xe 17.16, alpine iperf 2.2.0):
- ACL names `BIDIR`/`ANYCAST` break `ip pim rp-address ... <name> bidir` ("% Ambiguous command", line dropped from day-0): the lab uses `RPBD` and `RPAC`.
- `ip pim bsr-candidate Loopback0 0 100`: the priority is positional (`priority N` is rejected); hash mask length 0.
- `ip pim ssm default` is not on by default (student step). `ip pim autorp listener` works in pure sparse mode.
- MSDP carries every group for which the member is RP: R4's SA cache also lists `(10.0.1.10, 239.1.1.1)` while R3 is the Auto-RP RP of 239.1.0.0/16.
- Node stop is a silent failure for neighbours (no resign); IOL UTC clock equals host UTC.
- Stream and RP: R3 is on the data path R1-R3-R4, R2 is not. Stopping R3 stops the stream for 30-35 s because the path reroutes (OSPF dead 40 s window / PIM), not because the RP is gone. Stopping R2 (BSR run) loses nothing: the source tree is already built and does not need the RP.

## Intentional Faults

None (F lab).

## Diagnosis / Methodology

Not applicable. Method: `show ip pim rp mapping` on R4 (all methods) and R1 (Auto-RP lists both candidates), poll it after each node stop; `show ip mroute`, `show ip igmp groups ... detail`, `show ip pim interface df`, `show ip msdp sa-cache` for the observed ranges; viewer at `-i 1` for gaps; `tcpdump` on PC2 for the SSM proof.

## Solution Configuration

Save (`write memory`) on every router before any node stop. Static RP removal, all routers: `no ip pim rp-address 10.255.0.2 MC`.

Auto-RP (R1 mapping agent, R2 and R3 candidates, `autorp listener` on all):
```
! all routers
ip pim autorp listener
no ip pim rp-address 10.255.0.2 MC
! R1
ip pim send-rp-discovery Loopback0 scope 16
! R2 and R3
ip pim send-rp-announce Loopback0 scope 16 group-list MC
```
Without `group-list MC` a candidate announces 224.0.0.0/4 and would override the static 239.2/239.3 ranges. R3 is elected (highest RP address; Auto-RP has no priority).

Tuned timers (R2, R3 and R1): `ip pim send-rp-announce Loopback0 scope 16 group-list MC interval 10`; `ip pim send-rp-discovery Loopback0 scope 16 interval 10` (RP holdtime becomes 30 s).

BSR (remove the Auto-RP lines and the listener first: on R1 `no ip pim send-rp-discovery Loopback0 scope 16`, on R2 and R3 `no ip pim send-rp-announce Loopback0 scope 16 group-list MC`; the bare `no ip pim send-rp-announce` / `no ip pim send-rp-discovery` return `% Incomplete command`):
```
! R1
ip pim bsr-candidate Loopback0 0 100
! R3
ip pim bsr-candidate Loopback0 0 200
! R2
ip pim rp-candidate Loopback0 group-list MC priority 10
! R3
ip pim rp-candidate Loopback0 group-list MC priority 20
```
BSR = R3 (higher priority wins), RP = R2 (lower priority value wins). Converged about 25 s after configuring; a stale Auto-RP entry (RP 10.255.0.3, "elected via Auto-RP") stays on R4 for about 25 s.

SSM (all four routers): `ip pim ssm default`. PC2: `iperf -s -u -B 232.1.1.1 -H 10.0.1.10 -i 5`. PC1: `sudo ip addr add 10.0.1.11/24 dev eth0`; `iperf -c 232.1.1.1 -u -T 16 -b 256k -l 1316 -t 0` (10.0.1.10) and the same with `-B 10.0.1.11`.

## Verification

Start state (identical on a fresh import): every router `Acl: MC, Static / RP: 10.255.0.2`, `Acl: RPBD, Static, Bidir Mode / RP: 10.255.0.22`, `Acl: RPAC, Static / RP: 10.255.0.100`; R3 and R4 `show ip msdp peer`: `State: Up`; R1 route to 10.255.0.100 via 10.0.13.2 metric 11, R2 via 10.0.24.2 metric 31, R3/R4 connected; R4 e0/2 `Current IGMP router version is 3`.

V1/V2 Auto-RP, R4: `Group(s) 239.1.0.0/16 RP 10.255.0.3, v2v1, elected via Auto-RP, info source 10.255.0.1`; R1 lists R3 (elected) and R2; RPBD and RPAC static entries still listed. Removing `send-rp-announce` on R3 is withdrawn at R4 within the first poll (1-5 s).

V4 BSR, R4: RP 10.255.0.2 priority 10 and RP 10.255.0.3 priority 20 via bootstrap; `BSR address: 10.255.0.3, BSR Priority: 200`; `show ip pim rp-hash 239.1.1.1` selects 10.255.0.2.

V7 SSM, R4: `(10.0.1.10, 232.1.1.1)` flags `sTI`, iif Ethernet0/1, oif Ethernet0/2; no 10.0.1.11 entry on R4 or R1; `show ip igmp groups 232.1.1.1 detail`: Group mode INCLUDE. PC2 `tcpdump -ni eth0 -c 400 dst 232.1.1.1`: 400 packets from 10.0.1.10, 0 from 10.0.1.11. Viewer 255 kb/s, 0 % loss. Without `ip pim ssm default` SSM is off.

V8 bidir 239.2.2.2 (PC1 sends, PC2 joins): R2 `(*,G)` flags `B`, `Bidir-Upstream: Null`, oif Ethernet0/1; R4 `(*,G)` flags `BC`, Bidir-Upstream Ethernet0/0, oif Ethernet0/2; no `(S,G)` anywhere; R1 and R3 hold no entry. `show ip pim interface df` winners: R1 e0/0 R2 (10.0.12.2); R3 e0/0 R1; R3 e0/1 R4 (10.0.34.2); R4 e0/0 R2 (10.0.24.1); R4 e0/1 and e0/2 R4. Viewer 0 % loss.

V9 anycast 239.3.3.3: R3 `(*,G)` flags `SP`, `(S,G)` `TA` (R1 registered to R3); R4 `(S,G)` `MT`; R4 `show ip msdp sa-cache`: `(10.0.1.10, 239.3.3.3), RP 10.255.0.3, Peer 10.255.0.3`; R3's cache is empty (it originates). R1 and R3 use R3, R2 and R4 use R4 for 10.255.0.100. After R3 stops: R1's route moves to R4 (metric 61, via Ethernet0/0), R1 `(S,G)` gains oif Ethernet0/0, R4 `(S,G)` iif Ethernet0/0; the stale SA entry stays in R4's cache (holdtime 5:58).

## Failure / Recovery Behaviour

Method: node stop (silent failure) after `write memory`; trigger = the stop call at the host (the REST call takes 4-5 s), end = R4's mapping lists only the other RP (anycast: viewer back at `-i 1`). Clock: host UTC wall clock to R4 `show clock`; scripted CLI poll values exclude about 12 s of connect time and are not used.

| Scenario (trigger -> end condition) | Runs (raw) | Documented range | Basis |
|---|---|---|---|
| Auto-RP default (announce 60 s, discovery 60 s, holdtime 180): stop R3 -> R4 lists only RP .2 | 178 s, 179 s, 175 s; 126 s, 175 s, 175 s | 120-240 s | measured; bounds derived: holdtime 180 minus announce age (0-60 s) gives about 120 s, holdtime 180 + next discovery 60 gives 240 s |
| Auto-RP tuned (announce 10 s, discovery 10 s, holdtime 30): stop R3 -> same | 38 s, 45 s, 42 s | 30-50 s | measured; holdtime 30 s confirmed on R1 and R4 (`expires` falls to 30 s) |
| BSR default (C-RP adv 60 s, holdtime 150, bootstrap 60 s): stop R2 -> R4 lists only RP .3 | 119 s, 134 s, 129 s; 97-100 s, 136-139 s, 135-138 s | 90-210 s | measured; bounds derived: holdtime 150 minus C-RP advertisement age (0-60 s) gives about 90 s, holdtime 150 + 60 gives 210 s |
| Anycast: stop R3 with 239.3.3.3 running -> viewer receives again (R1 uses R4) | 30 s, 33 s, 36 s gap | 30-60 s | measured; OSPF dead 40 s window, register and tree rebuild (the 1a test saw up to 60 s) |
| Recovery: node start -> RP back in R4's mapping | R3 within 0-40 s, R2 about 45 s (boot 11-13 s) | 15-60 s | measured, single runs |

Stream during a failover: Auto-RP, R3 stopped: the viewer shows 0/0 intervals for 30-35 s (one run 6 intervals plus 93 % loss in the next) because R3 is the transit router of the cheap path, while OSPF and PIM reroute via R2; the RP loss itself costs nothing. BSR, R2 stopped: no lost interval in 3 runs, the RP is off the path and the source tree and `(S,G)` keep forwarding. Removing the candidate command (instead of a node stop) withdraws the mapping at once.

## Answers to Analysis Questions

Q1: 224.0.1.39 (announce) and 224.0.1.40 (discovery) are multicast groups with no RP; in sparse mode they cannot be forwarded unless dense mode or `ip pim autorp listener` (dense fallback for just those two groups) is used. BSR messages are PIM messages sent hop by hop to 224.0.0.13 (all PIM routers), which every PIM router processes and re-floods without needing a tree.

Q2: Auto-RP depends on the announcement interval (60 s), the mapping agent's discovery interval (60 s) and the RP holdtime (180 s, 3 x announce): measured 126-179 s by default, 38-45 s with 10 s intervals. BSR depends on the C-RP advertisement interval (60 s), its holdtime (150 s) and the bootstrap interval (60 s): measured 97-139 s. Auto-RP has no priority: the mapping agent picks the highest RP address, R3 (10.255.0.3 over .2). BSR compares the C-RP priority first (lower wins, R2 = 10, R3 = 20) and then the hash. The Auto-RP run lost 30-35 s of stream, but that is path loss: R3 forwards the stream (R1-R3-R4), so stopping it forces a reroute over R2. The BSR run (R2 off the path) lost nothing. An already-built source tree does not need the RP at all; the RP is needed only for new sources (registers) and new receivers (joins), so the loss is the router, not the RP.

Q3: In SSM the receiver names the source in an IGMPv3 INCLUDE report, so the last-hop router sends an (S,G) join straight towards the source along the RPF path: there is no shared tree to build, no register, no RP. The receiver must know the source address and use IGMPv3 (the viewer's `-H`). An unwanted source, 10.0.1.11, is never joined, so no router creates state (the packets are dropped by the first-hop router for lack of any join; R4's LAN carries only 10.0.1.10).

Q4: Bidir suits many-to-many with many sources (conferencing, sensor groups): state stays at one (*,G) per group regardless of the number of sources. Traffic flows up to the RP and down by the shared tree, over the DF (designated forwarder) of each link, which is elected by the best metric to the RP address; because sources are not registered and no source trees are built, there are no (S,G) entries and no registers.

Q5: MSDP lets the RPs of one PIM-SM domain tell each other about active sources. R1 registers to R3 (nearest member of 10.255.0.100); R3 originates a Source-Active message to R4 over the MSDP peering; R4 stores it in the SA cache and joins towards the source for receivers of 239.3.3.3 that joined R4's side. Without MSDP R4 would never learn of the source, since R2 and R4 use R4 as their RP and the register went elsewhere. Between two PIM domains it exchanges SA messages between the domains' RPs so that receivers in one domain can join sources in another without sharing the RP or the shared tree. R4's cache also lists 239.1.x because MSDP carries every group R3 is RP for, not only the anycast range.

Q6: Anycast RP with MSDP (what LAB-056 builds): both members are active, the RP load is shared by proximity, failover needs no RP-specific timer: the measured 30-36 s is the path reroute around the stopped R3 (the transit router, as in Q2); the RP change itself costs an existing stream nothing, and new sources and joins reach the surviving member as soon as the IGP has removed the stopped member's route to the anycast address (much less with tuned IGP timers). There are no additional timers like Auto-RP or BSR holdtimes. Auto-RP is Cisco-proprietary and slow; BSR is standard but has the same slow default failover (97-139 s measured). For IPv6 and mixed vendors BSR is the one to tune; at Veridian, anycast RP on the HQ cores.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-17 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), iol-xe (IOS XE 17.16.1a) |
