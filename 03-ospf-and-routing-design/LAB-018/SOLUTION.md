# LAB-018 — Solution

## Summary

Educational intent: show which LSA types each area type admits (stub, totally stubby, NSSA, totally NSSA), how an ASBR inside an area changes the choice, how type-7 LSAs are translated to type 5 at the ABR, and where the default route comes from in each case. Blueprint: 3.2.a:P, X-StubNSSA:I (3.2.a names "area types" among the EIGRP/OSPF routing concepts, so the area-type work is the 3.2.a practice; Q5 adds the EIGRP comparison). No intentional faults (type F lab). Platform: all routers iol-xe 17.16.1a, SW1 ioll2-xe 17.16.1a, PC1/PC2 alpine.

Start-state note: R1 and R4 hold their own external routes as static/connected, so "O E2 on every router" means every router except the originating ASBR.

## Intentional Faults

None. The two ASBRs (R1: static 198.51.100.0/24 to Null0; R4: connected Lo5 172.16.4.0/24 through route-map DEPOT-ONLY) are pre-built redistribution, not a learning objective.

## Diagnosis / Methodology

1. Baseline: `show ip route ospf` on R4 and R5 shows both externals as O E2 and no default.
2. R2: setting `area 1 stub` on R4 makes it log `%OSPF-4-ASBR_WITHOUT_VALID_AREA` because R4 is an ASBR with only a stub area. The adjacency resets and reforms once R3 is also stub. R3's type-5 database then loses 172.16.4.0: the depot is no longer originated. Hence a stub area is wrong for R4's area. NSSA (type 7) lets R4 keep originating it.
3. R3 (default into the NSSA): plain `area 1 nssa` gives R4 no default and no 198.51.100.0 route. `default-information-originate` adds a type-7 default (O*N2). `no-summary` gives a type-3 default (O*IA) and removes the inter-area routes. The chosen design is totally NSSA.
4. R1: R5's area is first set to stub (R5 keeps O IA routes and a default, loses externals) and then to totally stubby (`no-summary` on the ABR R2), leaving only the default.

## Solution Configuration

```
R3: router ospf 1
     area 1 nssa no-summary
R4: router ospf 1
     area 1 nssa
R2: router ospf 1
     area 2 stub no-summary
R5: router ospf 1
     area 2 stub
```

Intermediate steps recorded: R4 then R3 `area 1 stub` (R2 evidence); R3 `area 1 nssa default-information-originate` (type-7 default); R2 and R5 `area 2 stub` before `no-summary`.

## Verification

Captured in a test run (trimmed):

- Totally NSSA, R4: only `O*IA 0.0.0.0/0` in the OSPF RIB; type-3 0.0.0.0 advertised by R3; `show ip route 198.51.100.1` answers `% Network not in table` (exact-match show), `show ip cef 198.51.100.1` shows 0.0.0.0/0 via 10.0.34.3. PC2 traceroute: hop 3 R3, hop 4 R1 with `!H`.
- Depot: R4 originates a type-7 172.16.4.0 (`Options: Type 7/5 translation`, forwarding address 10.255.0.4). R3 reports `Perform type-7/type-5 LSA translation` and holds a type-5 172.16.4.0 advertised by R3. R1: `O E2 172.16.4.0 via 10.0.123.3`. R3: `O N2 172.16.4.0 via 10.0.34.4`, `O E2 198.51.100.0`.
- Area 2 stub: R5 has `O*IA 0.0.0.0/0` plus all inter-area routes, no O E2, no type-5 in its database. Totally stubby: R5's RIB is `O*IA 0.0.0.0/0` only; Area 2 summary database holds only 0.0.0.0 (advertised by R2). R2 still holds type-5 172.16.4.0 (R3) and 198.51.100.0 (R1).
- Reachability: R5 `ping 172.16.4.1 source Lo0` 2/2, `ping 10.0.1.101 source Lo0` 2/2; R1 and PC1 ping 172.16.4.1 ok; PC2 to PC1 ok.

**LSA table for R4 (final state, requirement R4; routers' own LSAs per area, measured outputs above, type-4 reasoning derived).**

| Area | Types present | Originated by / note |
|---|---|---|
| 0 (LAN123: R1, R2, R3) | 1 (R1, R2, R3), 2 (LAN123 DR, R3), 3 (R3 and R2 for areas 1 and 2 and their summaries), 5 (198.51.100.0 by R1; 172.16.4.0 by R3 after translation) | no type 4: R1 and R3 are ASBRs in area 0 itself, and an ASBR-summary is only needed by routers in another area |
| 1 (R3-R4, NSSA) | 1, 3 (default only, with `no-summary`), 7 (172.16.4.0 by R4) | no type 5 or 4 in the area; R3, the ABR, translates type 7 to type 5 |
| 2 (R2-R5, stub/totally stubby) | 1, 3 (default only in the totally stubby case) | no type 5 or 4: they are blocked at the ABR R2 |

No type-4 LSA exists anywhere in the final state. The only ASBR outside area 0 is R4, whose externals leave area 1 as type 5 originated by R3 (so the advertising router is an area 0 router and no ASBR-summary is needed), and R1's externals never enter areas 1 and 2 because those areas block type 5 and the type 4 that would describe R1.

## Failure / Recovery Behaviour

- R6 (a) one-ended mismatch (on R4: `no area 1 nssa`, then `area 1 stub`, while R3 stays NSSA; `area 1 stub` alone is rejected with `% Area is configured as NSSA already`): R3 debug shows `Hello from 10.0.34.4 with mismatched NSSA option bit` every 10 s; the neighbour is dead on R4 after about 40 s (`Dead timer expired`, adjacency reset first). Restoring R4 (`no area 1 stub`, `area 1 nssa`) brings FULL in about 45 s.
- R6 (b) R3 node stop (silent failure for R4 and the LAN123 routers, `write memory` first): at +15 s R4 is still FULL with its default; at +55 s the neighbour is gone, no gateway of last resort, `Neighbor Down: Dead timer expired`. PC2 to PC1 100% loss; R1 loses 172.16.4.0 (translator gone). After R3 starts, about 100 s later R4 is FULL with `O*IA 0.0.0.0/0`, R1 has `O E2 172.16.4.0 via 10.0.123.3`, and PC1/PC2 reach the depot and each other.

## Answers to Analysis Questions

Q1. (Debrief: why the choice for R4 is not a stub area.) R4 is an ASBR and a stub area cannot carry type-5 externals. R4 logged `%OSPF-4-ASBR_WITHOUT_VALID_AREA: Router is currently an ASBR while having only one area which is a stub area`, reset the adjacency and stopped originating 172.16.4.0 (R3's database lost it, so the depot became unreachable). NSSA carries it as type 7.

Q2. (Debrief: stub versus totally stubby.) Stub: R5 lost all type-5 (and 4) LSAs and kept the inter-area routes plus a default. Totally stubby: type-3 summaries are also blocked, so R5's database holds only the default summary and its RIB only `O*IA 0.0.0.0/0`. R5 can no longer hold external routes or act as an ASBR inside the area (captured: `redistribute connected subnets` on R5 in stub area 2 logs `%OSPF-4-ASBR_WITHOUT_VALID_AREA` and R2's type-5 database gains no R5 external), and the area cannot carry a virtual link transit (derived, RFC 2328).

Q3. (Debrief: plain NSSA does not inject a default route, totally NSSA does.) Totally NSSA (`no-summary` on R3, R4 plain NSSA): it gives R4 a type-3 default and removes the inter-area routes, the smallest table. Plain NSSA gave no default and R4 could not route to 198.51.100.0; `default-information-originate` gave a type-7 default but kept the inter-area routes.

Q4. The ABR (R3) translates type 7 to type 5 (`Perform type-7/type-5 LSA translation`). With two ABRs only one translates; by RFC 3101 the one with the highest router ID is elected (derived, not tested here); the other is a backup if it fails.

Q5. OSPF stub/NSSA areas stop whole LSA types at the ABR and replace them with a default, so the remote router's table shrinks by filtering the flooding. EIGRP stub (017) leaves the hub's advertisements alone but tells the hub not to query the stub router; the stub router's table is shrunk only by summaries or default sent from the hub, so the saving is in query scope and not automatically in table size (derived from 017's observation).

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-14 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), iol-xe (IOS XE 17.16.1a), ioll2-xe (IOS XE 17.16.1a) |
