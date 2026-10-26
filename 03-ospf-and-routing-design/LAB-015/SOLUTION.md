# LAB-015 — Solution (instructor)

## Summary

Foundation lab for OSPFv2 adjacency control (blueprint 3.2.b:I): neighbour states, DR/BDR election and its non-preemption, network types (broadcast, point-to-point, loopback), passive interfaces, key-chain authentication, hello/dead timers, and detection time for a silent failure versus a cable pull. Every output below was captured in CML (IOS XE iol-xe, 17.16.1a).

## Intentional Faults

None. The one-sided network type (R3), key mismatch (R6) and timer mismatch are student-made and reverted.

## Diagnosis / Methodology

Evidence path for the two student-made problems:
- **One-sided point-to-point (R3):** `show ip ospf neighbor` is FULL on both routers (R3 `FULL/  -`, R4 `FULL/BDR`), so look at the interface (`show ip ospf interface Ethernet0/1`: R3 POINT_TO_POINT, R4 BROADCAST and DR), at the routing tables (R3 and R4 have no routes across the link; R1 lost all R4 routes) and at the LSDB (R4's router LSA lists a Transit Network link to DR 10.0.34.4, R3's lists a point-to-point link). Hello/dead (10/40) are equal for both types, so they exchange hellos and databases, but SPF cannot use a link described as transit on one side and point-to-point on the other.
- **Key mismatch (R6):** on the router with the wrong key the neighbours disappear after the dead timer (`show ip ospf neighbor` empty) and the default log shows only `%OSPF-5-ADJCHG ... FULL to DOWN, Neighbor Down: Dead timer expired`. The cause appears with `debug condition interface Ethernet0/0` plus `debug ip ospf adj`, read with `show logging` (a remote CLI session may show the debug lines only in the buffer): `Mismatched Authentication key - ID 1`. The other two routers keep their adjacency with each other.
- **Timer mismatch:** `debug ip ospf hello` (interface-conditioned) prints `Mismatched hello parameters from 10.0.34.3` each second.

## Solution Configuration

```
! R1
router ospf 1
 router-id 10.255.0.1
 passive-interface Ethernet0/1
interface Loopback0
 ip ospf 1 area 0
interface Ethernet0/0
 ip ospf 1 area 0
 ip ospf priority 50
 ip ospf authentication key-chain OSPFKEY
interface Ethernet0/1
 ip ospf 1 area 0
key chain OSPFKEY
 key 1
  key-string ROUTEKEY123
  cryptographic-algorithm hmac-sha-256

! R2
router ospf 1
 router-id 10.255.0.2
interface Loopback0
 ip ospf 1 area 0
interface Ethernet0/0
 ip ospf 1 area 0
 ip ospf priority 0
 ip ospf authentication key-chain OSPFKEY
key chain OSPFKEY
 key 1
  key-string ROUTEKEY123
  cryptographic-algorithm hmac-sha-256

! R3
router ospf 1
 router-id 10.255.0.3
interface Loopback0
 ip ospf 1 area 0
interface Ethernet0/0
 ip ospf 1 area 0
 ip ospf priority 100
 ip ospf authentication key-chain OSPFKEY
interface Ethernet0/1
 ip ospf 1 area 0
 ip ospf network point-to-point
 ip ospf authentication key-chain OSPFKEY
 ip ospf hello-interval 1      ! after the R7(a) default-timer test
 ip ospf dead-interval 4
key chain OSPFKEY
 key 1
  key-string ROUTEKEY123
  cryptographic-algorithm hmac-sha-256

! R4
router ospf 1
 router-id 10.255.0.4
 passive-interface Ethernet0/1
interface Loopback0
 ip ospf 1 area 0
interface Loopback1          ! repeat for Loopback2-4
 ip ospf 1 area 0
 ip ospf network point-to-point
interface Ethernet0/0
 ip ospf 1 area 0
 ip ospf network point-to-point
 ip ospf authentication key-chain OSPFKEY
 ip ospf hello-interval 1
 ip ospf dead-interval 4
interface Ethernet0/1
 ip ospf 1 area 0
key chain OSPFKEY
 key 1
  key-string ROUTEKEY123
  cryptographic-algorithm hmac-sha-256
```
Roles are set by priority (R3 100, R1 50, R2 0) and then applied by the election: configure all three routers within the first seconds, or bounce LAN123 interfaces (see R2 below).

## Verification

**R1 / V2 (first adjacencies).** R2 right after enabling OSPF: `10.255.0.1 1 2WAY/DROTHER`, `10.255.0.3 1 2WAY/DROTHER`, interface `Et0/0 ... WAIT 0/2`. About 45 s later: R3 `FULL/DR`, R1 `FULL/DROTHER`, R2 itself BDR (highest router IDs win with equal priority, R3 first). PC1 pings PC2 5/5 after ~45 s. With default types R2 sees R4's loopbacks as `O 10.0.40.1/32 [110/21]`.

**R2 (non-preemption).** R1 `ip ospf priority 200`:
```
Transmit Delay is 1 sec, State DROTHER, Priority 200
Designated Router (ID) 10.255.0.3, Interface address 10.0.123.3
Backup Designated router (ID) 10.255.0.2, Interface address 10.0.123.2
```
After R1 50 / R3 100 / R2 0, R1's neighbours: `10.255.0.2 0 FULL/DROTHER`, `10.255.0.3 100 FULL/DR` (R1 is BDR). What moves the DR: `shutdown`/`no shutdown` on R3 Et0/0 gives R1 `State DR` and R3 `FULL/BDR`; the same bounce on R1 gives R3 `State DR`, R1 `FULL/BDR` (R3: `10.255.0.1 50 FULL/BDR`). After re-import with the solution applied to R1-R3 within a few seconds of each other: R3 `Et0/0 ... DR 2/2`, R1 `FULL/BDR`, R2 `FULL/DROTHER`.

**R3 (one-sided point-to-point).** R3 Et0/1 point-to-point, R4 Et0/0 default broadcast:
```
R3: 10.255.0.4  0  FULL/  -   10.0.34.4  Ethernet0/1      Network Type POINT_TO_POINT
R4: 10.255.0.3  1  FULL/BDR   10.0.34.3  Ethernet0/0      Network Type BROADCAST, State DR
R3 ping 10.255.0.4 source 10.255.0.3 -> Success rate is 0 percent (0/2)
R4 show ip route ospf -> (no OSPF routes)
R1 show ip route ospf -> only 10.0.34.0/24, 10.255.0.2/32, 10.255.0.3/32 (no R4 routes)
```
Both ends point-to-point: R1 gains `10.0.4.0/24`, `10.0.34.0/24`, `10.255.0.4/32` and R4's loopbacks (~30 s).

**R4 (loopback type).** Default `show ip ospf interface Loopback0` shows `Network Type LOOPBACK` and the route is a /32; with `ip ospf network point-to-point` on Lo1-4, R1 shows `O 10.0.40.0/24 [110/21] ... 10.0.43.0/24`.

**R5.** R1 `show ip ospf interface Ethernet0/1`: `No Hellos (Passive interface)`, `State DR, 0/0`; 10.0.1.0/24 stays in the other routers' tables (`O 10.0.1.0/24 [110/20]` on R2).

**R6 (authentication).** Mismatch on R2 (`ROUTEKEY124`): R2 `show ip ospf neighbor` empty, R1 loses R2 (`FULL to DOWN, Neighbor Down: Dead timer expired`, 16:49:31) while R1-R3 stay FULL. Debug on R2:
```
OSPF-1 ADJ   Et0/0: Send with youngest Key 1
OSPF-1 ADJ   Et0/0: Rcv pkt from 10.0.123.3 : Mismatched Authentication key - ID 1
OSPF-1 ADJ   Et0/0: Rcv pkt from 10.0.123.1 : Mismatched Authentication key - ID 1
```
Fix: `key-string ROUTEKEY123` on R2: `FULL/DROTHER` again within ~30 s. R3 Et0/1 reports `Cryptographic authentication enabled`.

**R7 (silent failure, link stopped in CML; host, PC1 and router clocks agree within ~1-2 s).** PC1 ran ping and `traceroute -n -m2` once a second; "unreachable" is the traceroute line `10.0.1.1 !H`.

| Run | Link stop | R3 `ADJCHG ... Dead timer expired` | PC1 pings fail | PC1 `!H` (unreachable) |
|---|---|---|---|---|
| default 10/40 | 16:54:17.4 | 16:54:50.5 (+33 s) | from the stop | not captured (loop used `-m1`) |
| default 10/40 | 16:56:56.9 | 16:57:32.6 (+35.7 s) | from the stop | not captured |
| default 10/40 | 16:59:06.2 | 16:59:37.6 (+31.4 s) | from the stop | 16:59:36 (+30 s) |
| hello 1 / dead 4 | 17:01:59.1 | 17:02:02.8 (+3.6 s) | from the stop | 17:02:03 (+4 s) |

The interfaces stay up/up throughout; detection time = dead interval minus the time since the last hello (so 31-37 s of 40 s, and 3.6 s of 4 s; another run measured 37 s).

**R7 (b), cable pull (R3 Et0/1 then R4 Et0/0 `shutdown`, 1/4 timers; LAB.md asks for this order).** R3: `%OSPF-5-ADJCHG ... FULL to DOWN, Neighbor Down: Interface down or detached` at 17:03:19.3, immediately after the command (the `%LINK-5-CHANGED` line is logged ~2 s later). On a cable pull R3 drops the adjacency the instant the interface goes down (`Interface down or detached`) and R1 has withdrawn the route about 0.1 s later (measured 0.11, 0.11, 0.12 s); PC1's pings are lost from that moment, and a once-per-second `traceroute` shows `!H` on its next probe, so a student's loop records about 1 s at most, set by the loop cadence, not the network. (Re-measured with a 0.2 s ping loop and R1 `debug ip icmp`, three runs; the earlier 17:03:08-:20 gap in the first capture was that capture's loop, not the network.) Reversed order: with R4 Et0/0 shut first, R3's interface stays up and R3 logs `Dead timer expired` about 4 s later instead of `Interface down or detached`, because R3 only loses R4's hellos until its own end is shut. A student who shuts the far end first and is slow on the second console sees the dead-timer message; both are correct for the order used.

**End state (V1, V4).** R3:
```
10.255.0.4   0  FULL/  -     00:00:03  10.0.34.4   Ethernet0/1
10.255.0.1  50  FULL/BDR     00:00:36  10.0.123.1  Ethernet0/0
10.255.0.2   0  FULL/DROTHER 00:00:35  10.0.123.2  Ethernet0/0
Et0/1 P2P 1/1     Et0/0 DR 2/2     Hello 1, Dead 4     Cryptographic authentication enabled
```
PC1 to PC2 3/3; traceroute `10.0.1.1, 10.0.123.3, 10.0.34.4, 10.0.4.102`; PC1 to 10.0.40.1 2/2.

## Failure / Recovery Behaviour

- R7 (a) silent failure and (b) cable pull: see the table and the paragraph above; the link was restored (Start in CML, or `no shutdown` on both ends) and the adjacency returned in about 30 s (10/40 timers) or a few seconds (1/4).
- R8 node stop (R3, DR, `write memory` first): after the dead timer R1 shows only R2 as a neighbour and `Et0/0 ... DR 1/1`. R1 is the DR and there is no BDR, because R2's priority is 0 (R1 log `Nbr 10.255.0.3 ... Dead timer expired` 17:04:49). R3 restarts as `BDR 2/2` with R1 still `FULL/DR`: it does not reclaim DR although its startup-config priority is 100.
- V7 records these roles.
- LAN123 priority 0 on R2 means that with R3 down no router is BDR until R3 returns.

## Answers to Analysis Questions

**Q1.** DOWN (no hello seen), INIT (hello seen without our router ID in it), 2WAY (bidirectional: our ID is in their hello; DROTHER-DROTHER pairs stay here), then EXSTART/EXCHANGE/LOADING and FULL. The hello must match before 2WAY: area, hello/dead intervals, network mask on broadcast segments, authentication, stub flag (and MTU is checked at EXSTART/EXCHANGE, so it blocks FULL, not 2WAY). Seen: `2WAY/DROTHER` on LAN123 until the 40 s election wait ended, then FULL with the DR and BDR; `Mismatched hello parameters` when timers differ and `Mismatched Authentication key` when keys differ.

**Q2.** The election is not preemptive: a sitting DR keeps the role until it loses it (R1 with priority 200 stayed DROTHER). The role moved only when the DR's interface or OSPF process restarted (shut/no shut on R3 Et0/0). In production that restart drops all adjacencies on the segment and re-floods the LSDB, so it is done in a maintenance window, and the priority plan is set before the routers first come up.

**Q3.** One end point-to-point and the other broadcast: both stay FULL (hello/dead are the same 10/40), but R3 describes the link as point-to-point and R4 as a transit network with itself as DR. SPF finds no consistent two-way link, so R3 and R4 install no routes across it (R3 could not even ping R4's loopback, R1 lost every R4 route). FULL only proves the databases synchronised, not that the topology they describe is usable; check network types on both ends and routes.

**Q4.** A loopback is a host interface, so OSPF advertises its address as a /32 stub regardless of the configured mask (network type LOOPBACK). It matters when the mask is meaningful: R4's branch subnets would otherwise appear as /32s; fixing it needs `ip ospf network point-to-point` (or summarisation at an ABR). For router IDs and management loopbacks (HQ DIST loopbacks in 021) the /32 is what you want.

**Q5.** Silent failure: the interfaces stay up, so only the dead timer (40 s default, about 31-37 s observed because the last hello arrived earlier, 3.6 s with 4 s dead) detected it; PC1's pings timed out from the stop and turned to unreachable when R1's route disappeared (~4 s with tuned timers). Cable pull: the shut interface goes down, OSPF reacts to the interface event at once (`Interface down or detached`) and withdraws the link from the router LSA, so no timer is involved (R1 withdraws the route about 0.1 s after the shutdown, measured 0.11-0.12 s; a once-per-second loop records about 1 s at most).

**Q6.** `passive-interface default` stops hellos (and so adjacencies) on every interface, and only the interfaces you re-enable with `no passive-interface` form neighbours; user subnets are still advertised. It prevents rogue routers on user ports and saves CPU, but forgetting `no passive-interface` on a transit link leaves the router with no neighbour there, with no error: the link's subnet is still advertised but routing across it does not work.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-17 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), iol-xe (IOS XE 17.16.1a), ioll2-xe (IOS XE 17.16.1a) |
