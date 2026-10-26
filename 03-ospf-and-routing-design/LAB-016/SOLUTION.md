# LAB-016 — Solution

## Summary

Educational intent: take a working flat OSPF network to the Veridian area design (area 0 core, one area per site), then compare the three ways of controlling what a router learns: summarising at the ABR, an inter-area LSA filter (`filter-list`) and a local RIB filter (`distribute-list`). This is the first exposure to prefix-lists with `ge`/`le` (SK-RM:I). Blueprint: 3.2.b:P, SK-RM:I. No intentional faults. Platform notes: all routers iol-xe 17.16.1a, SW1 ioll2-xe.

## Intentional Faults

None (implementation lab).

## Diagnosis / Methodology

Not a troubleshooting lab. Work order for a student: (1) move R4's and R5's interfaces first, then the ABR-side interfaces, and read `show ip ospf border-routers`; (2) add ranges; (3) filter-list on R2; (4) distribute-list on R1; (5) verify with the host pings. Expect old area-0 LSAs from R4 and R5 to linger after the migration (see Verification, stale LSAs) and a harmless `Router Link States (Area 0)` entry for R4 and R5. Look at advertising routers and the routing table, not only at the database.

## Solution Configuration

```
R4: (each of) interface Loopback0-4, Ethernet0/0, Ethernet0/1:  ip ospf 1 area 1
R5: (each of) interface Loopback0-5, Ethernet0/0:               ip ospf 1 area 2
R3: interface Ethernet0/1
     ip ospf 1 area 1
    router ospf 1
     area 1 range 10.0.40.0 255.255.252.0
R2: interface Ethernet0/1
     ip ospf 1 area 2
    ip prefix-list NO-PARTNER-LAB seq 5 deny 10.0.59.0/24
    ip prefix-list NO-PARTNER-LAB seq 10 permit 0.0.0.0/0 le 32
    router ospf 1
     area 2 range 10.0.52.0 255.255.252.0
     area 2 filter-list prefix NO-PARTNER-LAB out
R1: ip prefix-list NO-PARTNER-SUMMARY seq 5 deny 10.0.52.0/22
    ip prefix-list NO-PARTNER-SUMMARY seq 10 permit 0.0.0.0/0 le 32
    router ospf 1
     distribute-list prefix NO-PARTNER-SUMMARY in
```

R1's Lo0, LAN123 and the R2/R3 Lo0 and LAN123 interfaces stay in area 0, and R1 keeps the PC1 LAN in area 0.

## Verification

R1 after areas and ranges (captured):
```
O IA  10.0.4.0/24, 10.0.25.0/24, 10.0.34.0/24 via R3/R2
O IA  10.0.40.0/22 [110/21] via 10.0.123.3
O IA  10.0.52.0/22 [110/21] via 10.0.123.2
O IA  10.0.59.0/24 [110/21] via 10.0.123.2
O IA  10.255.0.4/32 via R3, 10.255.0.5/32 via R2     (loopback /32s stay)
R1# show ip ospf border-routers
i 10.255.0.2 [10] via 10.0.123.2, Ethernet0/0, ABR, Area 0
i 10.255.0.3 [10] via 10.0.123.3, Ethernet0/0, ABR, Area 0
```
Null0 discard routes: R3 `O 10.0.40.0/22 is a summary, 00:01:42, Null0`; R2 `O 10.0.52.0/22 is a summary, 00:01:08, Null0`. R3 holds the four /24s as intra-area `O` routes via 10.0.34.4; R2 holds 10.0.52-55.0/24 and 10.0.59.0/24 via 10.0.25.5.

Database per area (R3): Area 0 router LSAs (R1, R2, R3, plus stale R4/R5), net LSA 10.0.123.3 (R3, the DR); area 1 router LSAs R3 and R4, type-3 from R3 for everything outside area 1. R2: area 2 router LSAs R2 and R5, net LSA 10.0.25.5 originated by R5 (R5 is DR on the broadcast R2-R5 segment), type-3 from R2. No LSA type 4 or 5 exists.

Stale LSAs (captured, R1/R3/R2): after the flat to multi-area migration, area 0 still lists router LSAs `10.255.0.4` and `10.255.0.5` (ages grow, not refreshed) and type-3 LSAs advertised by 10.255.0.4/10.255.0.5 (e.g. 10.0.41.0 adv 10.255.0.4). They are not connected to the area 0 topology, so no route comes from them. They disappear at MaxAge or on a restart. `clear ip ospf process` asks for a confirmation; the bench was not cleared this way, so the stale LSAs were left to age out.

Inter-area filter (captured):
- R2 `area 2 filter-list prefix NO-PARTNER-LAB out`: on R1, `show ip route 10.0.59.0` gives `% Subnet not in table`. What R1's database shows depends on the order of work: added after R2 had already advertised 10.0.59.0, the filter leaves R2's type-3 LSA 10.0.59.0 at `LS age: MAXAGE(3609)` until it is flushed; configured together with the range, it means R2 never originates it and the only 10.0.59.0 LSA in area 0 is R5's stale pre-migration one (advertising router 10.255.0.5, unreachable, no route). Either way no usable LSA from R2 exists outside area 2. R2 keeps `O 10.0.59.0/24 [110/11] via 10.0.25.5`, and `ping 10.0.59.1` on R2 and R5 succeeds. The working form is `out` on area 2 (towards the other areas).
- R1 `distribute-list prefix NO-PARTNER-SUMMARY in`: `show ip route 10.0.52.0 255.255.252.0` gives `% Subnet not in table`, but `show ip ospf database summary 10.0.52.0` still lists the LSA advertised by 10.255.0.2 (`LS age: 101`). R3 and R4 keep the route (`O IA 10.0.52.0/22`).

Host results: PC1 to PC2 OK; PC1 to 10.0.52.1 100% loss, traceroute `1 10.0.1.1 ... !H`; PC2 to 10.0.52.1 and 10.0.55.1 OK; PC2 to 10.0.59.1 100% loss (no route at R3/R4); R4 to 10.0.52.1 OK, to 10.0.59.1 fails; R5 and R2 to 10.0.59.1 OK. Every interface is up (only the unused Et0/2-Et0/3 are down).

## Failure / Recovery Behaviour

Method: `shutdown` on interfaces (cable pull for the link).
- R4 Lo1 shut: R3 keeps `O 10.0.40.0/22 is a summary ... Null0`, loses 10.0.40.0/24; R1 keeps 10.0.40.0/22. V6's sourced ping from R1 Lo0 to 10.0.40.1 therefore fails: R1 forwards it on the summary to R3, whose longest match is now the Null0 discard route (captured: before the shutdown `ping 10.0.40.1 source Loopback0 repeat 3` gives `!!!`, 3/3; with Lo1 shut it gives `U.U`, `Success rate is 0 percent (0/3)`; the `U` replies are R3's host-unreachable from its Null0 discard route, the `.` is ICMP unreachable rate limiting; R3 `show ip route 10.0.40.0 255.255.255.0` gives `% Subnet not in table`, and the /22 is `directly connected, via Null0`).
- R4 Lo2-Lo4 also shut: R3 and R1 have no 10.0.40.0/22 or branch /24 (R3's own type-3 LSA withdrawn). `no shutdown` on all four: `O IA 10.0.40.0/22` back at R1.
- R2-R5 cable pull (shutdown on both ends): R3 and R1 lose 10.0.52.0/22 and 10.255.0.5/32; after `no shutdown` on both ends the route returned within about 45 s (DR election on the segment), all neighbours FULL.

## Answers to Analysis Questions

**Q1.** Area 0: type 1 from R1, R2, R3; type 2 for LAN123 from R3 (DR); type 3 from R3 (branch, area 1 prefixes and R4 Lo0) and from R2 (area 2 prefixes). Area 1: type 1 from R3 and R4, no type 2 (R3-R4 is point-to-point), type 3 from R3 for all other areas. Area 2: type 1 from R2 and R5, type 2 for 10.0.25.0/24 from R5 (the DR, higher router ID), type 3 from R2. No type 4 or 5. Ignore the stale area-0 LSAs of R4 and R5 left over from the migration.

**Q2.** All branch subnets down: the summary is withdrawn, because an ABR advertises a range only while at least one more specific route exists in the area (observed). One subnet down: the summary stays and its cost does not change here (the summary takes one representative component cost: the highest under RFC 2328, the lowest under the older RFC 1583 rule; all four branch subnets cost the same, so the bench cannot show the difference; derived), and the dead /24 is not visible outside area 1 (the failure is hidden, so SPF elsewhere does not run). The Null0 route prevents loops: traffic to an address inside the range with no specific route would otherwise follow a less specific or default route and could bounce back to the ABR.

**Q3.** R2's `filter-list` removed the type-3 LSA (R2's 10.0.59.0 LSA is absent from R1's area-0 database, or at MAXAGE if the filter was added after it was advertised; no route anywhere outside area 2; a stale 10.0.59.0 LSA from R5 left over from the migration is unreachable and gives no route). R1's `distribute-list` removed only the route: the LSA 10.0.52.0 stays in R1's database (age 101) but is absent from the routing table. A RIB filter does not change what R1 floods to its neighbours, so a transit router that filters a prefix still forwards LSAs while having no route: traffic from routers behind it that follows its path is dropped.

**Q4.** Exactly 10.0.52.0/22: `ip prefix-list X permit 10.0.52.0/22`. Any subnet inside it: `permit 10.0.52.0/22 ge 23` (equivalently `le 32` with `ge 23`). Mask /24 or longer in 10.0.0.0/16: `permit 10.0.0.0/16 ge 24`. The R1 distribute-list (requirement R4) needed the first one: `deny 10.0.52.0/22` followed by a `permit 0.0.0.0/0 le 32`, because the summary is exactly that prefix, and the final permit is required (an implicit deny ends every prefix-list). The R2 filter-list prefix-list (requirement R3) needed `deny 10.0.59.0/24` plus the permit-all entry. (Requirement numbers R3/R4 are not router names: the filters sit on routers R2 and R1.)

**Q5.** Summarise at each branch ABR: area 21-23 prefixes into one /22 or /24 per area towards area 0, and at the HQ ABR for the campus into the branches. The cost: the failure of one subnet inside the summary is invisible outside the area, so a ping or traceroute fails at the ABR or the Null0 route, and the engineer needs the database of the right area to locate the fault. Metrics are also less precise (one representative component cost) and a stale summary hides a withdrawn prefix.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-14 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), iol-xe (IOS XE 17.16.1a), ioll2-xe (IOS XE 17.16.1a) |
