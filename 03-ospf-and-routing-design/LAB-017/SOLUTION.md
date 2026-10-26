# LAB-017 — Solution

## Summary

Educational intent: put EIGRP and OSPF side by side on one diamond so the student sees, with real numbers, the differences the blueprint names: advanced distance vector versus link state, feasibility condition and feasible successors, unequal-cost load sharing with `variance`, administrative distance between protocols, and failover behaviour. The vendor's claims are tested, not assumed. Blueprint: 3.2.a:I (compare EIGRP and OSPF; stub at compare depth). This is an A/F lab: nothing is broken; the only "build" is adding EIGRP.

Design values: `delay 750` (7500 us) on R1 e0/1 and R4 e0/1. With EIGRP metric = 256 × (10^7/10000 + sum of delays/10) the R2 path costs 332800 and the R3 path 499200 (1.5×) in both directions, and R3's reported distance (307200) is below the successor's FD (332800).

## Intentional Faults

None (analysis lab).

## Diagnosis / Methodology

Not a troubleshooting lab. Method the student follows:
1. Compare `show ip route 10.0.4.0` before and after EIGRP: AD 90 (EIGRP internal) beats 110 (OSPF), so EIGRP installs, OSPF stays in its own database.
2. Read `show ip eigrp topology 10.0.4.0/24`: successor, FD, RD per neighbour; feasibility condition RD(R3) < FD(successor).
3. Read `show ip ospf rib 10.0.4.0` and `show ip ospf database`: equal total cost, so ECMP.
4. Measure the four failures with `ping -i 0.2` to 10.0.4.1 and the msec log timestamps.

## Solution Configuration

All routers (R1 shown; R2/R3/R4 use their own Loopback0 as router ID, and only R1 and R4 mark the LAN port passive):

```
router eigrp 100
 eigrp router-id 10.255.0.1
 network 10.0.0.0 0.255.255.255
 passive-interface Ethernet0/2
```

R4 uses `eigrp router-id 10.255.0.4` and `passive-interface Ethernet0/2`; R2 and R3 have no passive interface. (Named mode is equally valid; classic was used and tested.)

R4 task (R1 only), removed before R5:

```
router eigrp 100
 variance 2
```

R5 (the EIGRP-out cases, R1): `router eigrp 100` then `shutdown`; restore with `no shutdown`.

R6 (R4): `router eigrp 100` / `eigrp stub connected`; remove with `no eigrp stub`.

Build-time aid for simultaneous cable pull (R1 and R2, same minute, optional for students): `event manager applet PULL` / `event timer cron cron-entry "MM HH * * *"` / `action 1.0 cli command "enable"` / `action 2.0 cli command "configure terminal"` / `action 3.0 cli command "interface Ethernet0/0"` / `action 4.0 cli command "shutdown"`. (`event timer absolute time` was rejected.)

## Verification

R1, after EIGRP is enabled on all four routers (captured):

```
R1# show ip eigrp topology 10.0.4.0/24 | include via|Composite|State
  State is Passive, Query origin flag is 1, 1 Successor(s), FD is 332800
      Composite metric is (332800/307200), route is Internal      <- via 10.0.12.2 (R2), successor
      Composite metric is (499200/307200), route is Internal      <- via 10.0.13.3 (R3), feasible successor
R1# show ip route 10.0.4.0
  Known via "eigrp 100", distance 90, metric 332800 ... 
  * 10.0.12.2, from 10.0.12.2, via Ethernet0/0, Route metric is 332800, traffic share count is 1
```

Total delay: 3000 us via R2, 9500 us via R3. Feasibility: RD via R3 = 307200 < FD 332800, so R3 is a feasible successor; 499200 < 2 × 332800 = 665600, so `variance 2` admits it.

R4 for 10.0.1.0/24 (captured, symmetric): via 10.0.24.2 (332800/307200) successor, via 10.0.34.3 (499200/307200) feasible successor.

OSPF view on R1 (captured): `show ip route 10.0.4.0` before EIGRP: `Known via "ospf 1", distance 110, metric 30`, two paths (via 10.0.13.3 and 10.0.12.2), each traffic share count 1. `show ip ospf rib 10.0.4.0`: `10.0.4.0/24, Intra, cost 30, area 0`, two `via` entries, LSA 1/10.255.0.4/10.255.0.4 (R4's router LSA).

With `variance 2` on R1 (captured):

```
R1# show ip route 10.0.4.0 | include via|share
    10.0.13.3, from 10.0.13.3, via Ethernet0/1   Route metric is 499200, traffic share count is 2
  * 10.0.12.2, from 10.0.12.2, via Ethernet0/0   Route metric is 332800, traffic share count is 3
R1# show ip cef 10.0.4.0 detail
10.0.4.0/24, epoch 0, per-destination sharing
  nexthop 10.0.13.3 Ethernet0/1
  nexthop 10.0.12.2 Ethernet0/0
```

(`show ip cef ... internal`: path shares 3/3 via R2 and 2/2 via R3; load is per destination, so one flow stays on one path.)

Distances (`show ip protocols`): EIGRP internal 90, external 170; OSPF 110.

Stub (captured on R2): before, neighbour 10.0.24.4 shows `Prefixes: 5`. After `eigrp stub connected` on R4: `Prefixes: 3`, `Stub Peer Advertising (CONNECTED ) Routes`, `Suppressing queries`. R3 shows the same for 10.0.34.4. R2's topology entries via R4 shrink to 10.0.34.0/24, 10.255.0.4/32 and 10.0.4.0/24; the routes it had learned through R4 (10.0.13.0/24, 10.255.0.3/32) are gone and R2 reaches them via R1 (`D 10.255.0.3/32 [90/601600] via 10.0.12.1`). R4 itself still sees both paths to 10.0.1.0/24 (332800/307200 and 499200/307200). `show ip protocols` on R4 shows `Stub, connected`.

## Failure / Recovery Behaviour

PC1 pinging 10.0.4.1 with `-i 0.2`. Cable pull = `shutdown` on both ends, fired in the same second by EEM (R1 16:58:00.474 vs R2 16:58:00.38 and 16:50:00.565 vs .382 in the two runs). Silent failure = `stop_cml_link` on R1–R2. A first attempt with two shutdown commands issued one after the other had a 6.2 s gap between the two ends and showed 31 lost packets (6.2 s): all of it the gap, so the cable-pull number is a convergence below 0.2 s. Students typing on two consoles will see a similar gap; LAB.md tells them to subtract it using the log timestamps.

| Case | Sent | Received | Lost | Outage | Detection |
|---|---|---|---|---|---|
| 1 EIGRP, cable pull | 400 | 400 | 0 | under 0.2 s | R1 `EIGRP-IPv4 100: Neighbor 10.0.12.2 (Ethernet0/0) is down: interface down` at 16:58:00.474 |
| 2 OSPF only, cable pull | 400 | 399 | 1 | about 0.2 s | R1 `OSPF-5-ADJCHG ... Neighbor Down: Interface down or detached` 16:50:00.565 |
| 3 EIGRP, silent | 500 | 437 | 63 | about 12.6 s | `DUAL-5-NBRCHANGE ... is down: holding time expired` R2 17:00:43.969, R1 17:00:45.118 |
| 4 OSPF only, silent | 500 | 317 | 183 | about 36.6 s | `OSPF-5-ADJCHG ... Neighbor Down: Dead timer expired` R1 17:04:56.732 |

(10.0.4.1 was used because under OSPF its ECMP hash goes through R2; 10.0.4.102 hashes through R3 and would show no loss.) All cases were restored and reconverged before the next. Every EIGRP case also switched to the feasible successor with no query.

EIGRP hold time is 15 s (3 × 5 s hello); OSPF dead interval on these broadcast links is 40 s (4 × 10 s hello). Outage is the hold/dead time minus the time since the last hello, plus negligible SPF/DUAL time, so the silent-failure numbers (12.6 s and 36.6 s) are dominated by those timers, not by the algorithms. The cable-pull numbers are dominated by interface-down detection (both react at once).

Notes: shutting EIGRP down on R1 with `shutdown` under the process removes EIGRP completely from R1 (neighbours down: shutdown) and R1 falls back to OSPF at once; `no shutdown` re-forms the adjacencies in about a minute. After restoring a link, wait about a minute for OSPF to elect a DR before measuring again. Run CLI calls on the routers one at a time: a configuration sent in parallel with others was lost once during the build (R4).

## Answers to Analysis Questions

Q1. EIGRP (distance vector): R1 holds, per neighbour, only a distance: "via R2, 332800 with R2 reporting 307200" and "via R3, 499200 reporting 307200". It does not know the diamond's shape; it trusts what its neighbours report. OSPF (link state): R1 holds the whole area-0 LSDB (a router LSA from each of R1–R4) and runs SPF itself; the 10.0.4.0/24 entry is R4's stub-link LSA reached at cost 30 by two computed paths. EIGRP stores what neighbours advertise, OSPF stores what every router originated.

Q2. When the successor via R2 is lost, R1 checks the topology table: R3's reported distance 307200 is lower than the old FD 332800, so the feasibility condition guarantees the R3 path cannot loop through R1, and R1 installs it at once (passive state, no query). Without a feasible successor (RD of every remaining path not below the FD) the route goes active: R1 sends queries to its neighbours and waits for replies before choosing a path.

Q3. Without variance only the successor (via R2, 332800) is in the RIB. With `variance 2` the R3 path (499200 < 2 × 332800) is installed too, with traffic-share counts 3 (R2) : 2 (R3) in inverse proportion to metric, and CEF lists both next hops (per-destination sharing). OSPF installs only paths of equal total cost: it computes one SPF distance per destination and has no notion of a feasible-but-longer path, because link-state SPF gives a shortest-path tree with no reported distances from neighbours to prove a longer path is loop-free.

Q4. Cable pull: both were under about a second (EIGRP 0 lost, OSPF 1 lost at 0.2 s resolution): the interface-down event triggers the adjacency drop immediately in both, and EIGRP switches to a pre-computed feasible successor while OSPF runs a fast SPF, so no real difference on a small topology. Silent failure: EIGRP about 12.6 s (hold time 15 s since the last hello), OSPF about 36.6 s (dead interval 40 s). The silent-failure difference is entirely timer defaults (15 s hold versus 40 s dead), not protocol design: OSPF hello/dead could be lowered, as could EIGRP's.

Q5. Reasons to keep OSPF: it is an open standard that works with any vendor's routers (EIGRP's basic functionality is published but the ecosystem is Cisco-centred); it has areas, ABR summarisation and area types that scale and bound change, which this curriculum builds on; the IPv6 plan uses OSPFv3 with the same design. The vendor claims hold only partly: unequal-cost sharing worked (3:2), and a feasible successor avoids queries, but the cable-pull results were equal and the silent-failure gap is a timer default. EIGRP would be better in a Cisco-only hub-and-spoke WAN where unequal paths should be used with minimal configuration and manual summarisation (or stub spokes) can be applied per interface without an area design.

Q6. After `eigrp stub connected` R4 advertises only its connected networks (3 prefixes instead of 5) and tells its neighbours it is a stub: R2 and R3 see "Stub Peer Advertising (CONNECTED) Routes" and "Suppressing queries", and no longer learn the routes R4 used to relay (10.0.13.0/24, 10.255.0.3/32 via R4 disappeared from R2's table), so R4 is no longer a transit path. A stub is never queried: neighbours skip it when a route goes active, so queries do not wander beyond it and a failure converges faster and is less likely to get stuck in active (SIA). That is why stubs suit leaf sites and feeds 018 Q5.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-14 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), iol-xe (IOS XE 17.16.1a) |
