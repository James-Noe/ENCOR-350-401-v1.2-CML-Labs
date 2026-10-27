# LAB-020 — Solution

## Summary

Two faults behind two tickets, each with "routing looks fine" evidence in the obvious place. F1: an adjacency that is listed but never reaches FULL (interface MTU mismatch). F2: an over-wide prefix-list in R2's inter-area (type-3) filter that removes the partner summary together with the two intended /24s, so the LSA is absent from areas 0 and 1. The fault sits upstream of every router the engineer looks at first; R1's own filter is a red herring. Teaches neighbour-state reading, LSDB-versus-RIB comparison ("LSA absent: look upstream"), conditional debug, and why symptom fixes (`ip ospf mtu-ignore`, deleting or loosening the filter) fail the full design test. Blueprint: 3.2.b:T, 4.1:P, SK-RM:T (domains 3, 4). Topology and design: LAB-016 plus R5 Lo6 10.0.48.1/24.

## Intentional Faults

| ID | Device | Change | Symptom |
|---|---|---|---|
| F1 | R4 Et0/0 | `ip mtu 1400` | R3-R4 stalls: R3 shows INIT/EXCHANGE, R4 EXSTART, cycling (DBD MTU check). R3 lists R4 as a neighbour but holds no area 1 routes; R4 learns no routes; PC2 reaches only R4. T1. Shows only when the adjacency forms (boot or interface bounce) |
| F2 | R2 | `ip prefix-list PARTNER-LAB seq 5 deny 10.0.48.0/20 le 32` (meant `deny 10.0.48.0/24` and `deny 10.0.59.0/24`), `seq 10 permit 0.0.0.0/0 le 32`, used by `area 2 filter-list prefix PARTNER-LAB out` | R2 originates no type-3 for 10.0.48.0/24, 10.0.59.0/24 and the summary 10.0.52.0/22 (all inside the /20). No router outside area 2 holds the LSA or the route. R2's range for the /22 shows Passive and no Null0 route exists. T2 (and the second half of T1 once F1 is fixed) |

Red herrings: R1's `distribute-list prefix HQ-IN in` (denies exactly 10.0.48.0/24, correct interim rule; a RIB filter cannot remove an LSA); R5's default-source ping to PC1 succeeds (10.0.25.0/24 is outside the /20); R2 DROTHER with priority 0 (by design); boot-time ADJCHG lines.

## Diagnosis / Methodology

T1. PC2 pings R4 Et0/1 and Et0/0 (PC2, addressing eliminated); R3 pings 10.0.34.4 with small packets (L1-L3 eliminated). `show ip ospf neighbor`: R3 INIT/EXCHANGE, R4 EXSTART. Past INIT means hellos match (area, timers, authentication, network type), so the database exchange fails. Conditional debug on R4 (`debug condition interface Ethernet0/0`, `debug ip ospf adj`) shows the MTU complaint; `show ip interface e0/0` on R4: `MTU is 1400 bytes`: F1. R3's missing summary for area 1 is a consequence (no components).

T2. Partner announces: R2 holds 10.0.52-55.0/24, 10.0.48.0/24 and 10.0.59.0/24 as intra-area `O` routes via 10.0.25.5, R2-R5 FULL. On R1: `show ip ospf database summary 10.0.52.0` shows no LSA, so this is "removed before the database", not a RIB filter (R1's HQ-IN cannot remove an LSA and denies only 10.0.48.0/24). R1 holds R2's other type-3 LSAs (10.0.25.0/24, 10.255.0.5/32), so flooding and the adjacencies are fine; R3 and (after F1) R4 lack the routes too, so the cause is upstream of all of them: R2. On R2 `show ip ospf` lists the range 10.0.52.0/22 as Passive (not Active) with `Area-filter PARTNER-LAB out`, and `show ip route | include Null` is empty (a suppressed range has no discard route); `show ip ospf database summary self-originate` has no 10.0.52.0; `show ip prefix-list detail PARTNER-LAB` shows `seq 5 deny 10.0.48.0/20 le 32` with hits: F2 (the /20 covers 10.0.48.0-10.0.63.255).

Causality: fix F1 only (`no ip mtu` on R4 e0/0): R4 FULL, PC2 <-> PC1 work, PC1 and PC2 -> 10.0.52.1 fail (T1 half open, T2 open). Fix F2 only: R1 gets `O IA 10.0.52.0/22 [110/21]` 1-2 s later, PC1 -> 10.0.52.1 and 10.0.55.1 work, PC1 -> 10.0.48.1 fails, PC2 still isolated.

Wrong fixes (each tried once):
- `ip ospf mtu-ignore` on R4 e0/0 (F1 left at 1400): FULL at once, small PC2 -> PC1 ping works, but `ping 10.0.34.3 size 1500 df-bit` and `ping 10.0.1.101 size 1500 df-bit` from R4 are 0/3. Fails V3. PC pings carry no DF bit (busybox ping has none; `-s 1472` fragments), so the full-size test must be a router DF ping.
- Thursday's list (only `deny 10.0.59.0/24`): R1 holds the 10.0.48.0/24 type-3 but its HQ-IN keeps it out of the RIB; PC1 -> 10.0.48.1 fails (every HQ test passes), but R3/R4 get `O IA 10.0.48.0/24` and PC2 -> 10.0.48.1 works: fails V1/V3 from the branch.
- Removing `area 2 filter-list prefix PARTNER-LAB out`: /22 appears at once, but R1, R3, R4 also get 10.0.59.0/24 and the 10.0.48.0/24 type-3; PC1 -> 10.0.59.1 and PC2 -> 10.0.48.1/10.0.59.1 work: leaks, fails V1/V2.

Debrief: `mtu-ignore` is wrong because it hides the mismatch the design forbids (every link carries 1500). R1's filter looks guilty because it names 10.0.48; it is innocent because the LSA is absent from R1's LSDB, where a RIB filter has no effect (and R3, which has no such filter, lacks the routes too). Thursday's list passes every HQ test because R1's interim rule still hides 10.0.48.0/24 from HQ; only the branch shows the leak.

## Solution Configuration

```
R4:  interface Ethernet0/0
      no ip mtu
      shutdown
      no shutdown          (the adjacency must re-form)
R2:  no ip prefix-list PARTNER-LAB seq 5 deny 10.0.48.0/20 le 32
     ip prefix-list PARTNER-LAB seq 5 deny 10.0.48.0/24
     ip prefix-list PARTNER-LAB seq 6 deny 10.0.59.0/24
R2, R4: copy running-config startup-config
```

## Verification

Start state (captured on a fresh import of the YAML):
```
R3# show ip ospf neighbor            10.255.0.4  0  INIT/ -  ... Ethernet0/1
R4# show ip interface e0/0 | include MTU     MTU is 1400 bytes
R4# show ip ospf neighbor / show ip route ospf    (empty)
R1# show ip route 10.0.52.0          % Subnet not in table
R1# show ip route ospf | include 10.0.2|10.0.4|10.0.5
O IA     10.0.25.0/24 [110/20] via 10.0.123.2
R2# show ip ospf | include Area-filter|10.0.52.0/22
	   10.0.52.0/22 Passive Advertise
	Area-filter PARTNER-LAB out
R2# show ip route | include Null     (empty)
R2# show ip prefix-list detail PARTNER-LAB
   seq 5 deny 10.0.48.0/20 le 32 (hit count: 12, refcount: 1)
   seq 10 permit 0.0.0.0/0 le 32 (hit count: 7, refcount: 1)
R5# ping 10.0.1.101                  3/3 ; ping 10.0.1.101 source Loopback1: 0/3
PC1 -> 10.0.4.102, 10.0.52.1, 10.0.48.1: fail ; PC2 -> 10.0.34.3, 10.0.1.101, 10.0.52.1: fail
```
End state (captured):
```
R4 e0/0 MTU 1500, R4 neighbour FULL; R4: O IA 10.0.52.0/22 [110/31]
R1: O IA 10.0.52.0/22 [110/21]; no type-3 for 10.0.48.0 or 10.0.59.0; 10.0.48.0 not in the RIB (HQ-IN)
R2 range: 10.0.52.0/22 Active(11) Advertise ; O 10.0.52.0/22 is a summary, Null0 (metric 11)
R2 prefix-list hits: seq 5 1, seq 6 1, seq 10 21
R5: ping 10.0.1.101 3/3 ; sourced Lo1 -> 10.0.1.101 and 10.0.4.102 3/3
PC1: 10.0.4.102, 10.0.52.1, 10.0.55.1 ok ; 10.0.48.1, 10.0.59.1 fail
PC2: 10.0.1.101, 10.0.52.1 ok ; 10.0.48.1, 10.0.59.1 fail
R4: ping size 1500 df-bit to 10.0.34.3, 10.0.1.101, 10.0.52.1: 3/3 each ; R4 -> 10.0.48.1 fails
```

## Failure / Recovery Behaviour

Persistence: after `copy run start` on R2 and R4 and a node stop/start of both (a silent failure for their neighbours), R4 MTU 1500, R3-R4 FULL, R2 FULL x3, list seq 5/6/10, R1 holds 10.0.52.0/22.

Cable pull = `shutdown` on both ends of R3 e0/1 and R4 e0/0; the restore is `no shutdown` on both ends. The CLI poll ran every 5 s, so values are poll-resolution.

| Scenario (trigger, end condition) | Runs (s) | Documented range | Basis |
|---|---|---|---|
| Cable pull: config block start, R1 route to 10.0.4.0/24 gone | 2, 2, 2 | 1-10 s | shutdown on both ends withdraws the link from the router-LSA at once; poll resolution |
| Restore: `no shutdown` both ends, R4 neighbour FULL | 18, 18, 18 | 15-30 s | hello 10 s default on the point-to-point link (first hello plus DBD/LSR exchange); range derived from the timer and the runs; no stuck state |

Estimate (75 min): about 60 min diagnosis and two fixes, plus 2 min boot, plus failure tests (2 x about 20 s) and the persistence reload; no timed full solve was measured.

## Answers to Analysis Questions

Q1. T1: R3's neighbour table listed R4, but INIT/EXCHANGE (never FULL) and R3 had no area 1 routes; R4 showed EXSTART. T2: the type-3 LSA for 10.0.52.0 was missing from R1's LSDB although R2 held the partner routes and R2-R5 was FULL, and R5's default-source ping to PC1 worked (10.0.25.0/24 is outside the filtered /20), while a ping sourced from a partner network failed; R2's range showed Passive.

Q2. INIT (hellos seen one way), 2WAY (normal between DROTHERs), EXSTART (master/slave negotiation not completing: MTU mismatch, duplicate router ID), EXCHANGE (DBD exchange not completing: MTU mismatch, packets dropped above a size), LOADING (LSRequests unanswered: corrupt or filtered LSAs, MTU). Here: MTU mismatch (EXSTART/EXCHANGE).

Q3. Compare `show ip ospf database summary <prefix>` with `show ip route <prefix>`. LSA present and route absent: removed after the database (distribute-list, prefix-list, route-map; `show ip protocols`, `show ip prefix-list`). LSA absent: removed before it, upstream (ABR filter-list, summarisation, withdrawal): find which routers lack it and inspect the advertising ABR (`show ip ospf` area filters, self-originated LSAs, `show ip prefix-list detail`). Here R1 and R3 lacked the LSA, R2 held the routes: R2.

Q4. `debug condition interface Ethernet0/0` then `debug ip ospf adj` on R4 limits output to that interface; show the MTU complaint. Undo with `undebug all` (`undebug condition all` prompts `[yes/no]` and fails through the CLI tool). Unconditioned, it prints events for every interface and neighbour, floods the console and burns CPU on a busy router, possibly worsening the outage.

Q5. Lines: `ip prefix-list PARTNER-LAB seq 5 deny 10.0.48.0/24`, `seq 6 deny 10.0.59.0/24`, `seq 10 permit 0.0.0.0/0 le 32`. Review check: test what an entry matches (`show ip prefix-list PARTNER-LAB 10.0.52.0/22`) and compare the type-3 LSAs the ABR originates before and after (`show ip ospf database summary self-originate`); for the MTU change compare `show ip interface` MTU at both link ends with the per-link standard and confirm FULL plus a DF ping of 1500 bytes in both directions.

Q6. R1 (area 0), R3 (area 0/1 ABR) and R4 lacked 10.0.52.0/22 and the /24s; R2, the area 2 ABR, and R5 held them. A missing route on every router outside one area, with the LSA absent from area 0, places the fault at that area's ABR or in its inter-area policy, not at R1.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-15 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), iol-xe (IOS XE 17.16.1a), ioll2-xe (IOS XE 17.16.1a) |
