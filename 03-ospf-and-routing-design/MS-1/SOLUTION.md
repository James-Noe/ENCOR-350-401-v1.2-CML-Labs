# MS-1 — Solution

## Summary

Educational intent: close modules 01–03 on the H2 three-tier dual-stack campus (`environments/HQ/H2/`). The student works a mixed queue (three multi-cause tickets, four change requests) under constraints, proves each fix with before/after evidence, and proves resilience with drills. Latent second causes (parallel pairs F1/F2 and F3/F4, series pair F5/F6) are exposed only by a different test, and CR3 rebuilds the very ports that carry F1/F2.

Blueprint mapping (instructor only): 3.1.a:N, 3.1.b:N, 3.1.c:N, 3.3.c:N, 3.2.b:N, 1.1.b:N, IPv6:N, X-StubNSSA:N, X-L2guards:T (F2, root guard replacing loop guard on ACC3). Tickets: TK1 from modules 01/02, CR3 from 004/005, TK2/CR1/CR2 from this module.

**Build notes:**
1. F2 as built is a replacement: `spanning-tree guard root` replaces `guard loop` on ACC3 e0/1 (the two guards are mutually exclusive on IOS); e0/0 keeps loop guard. With F1 fixed alone, e0/1 stays root-inconsistent for VLANs 50 and 99 as the alternate port, so F2 stays latent until e0/0 is pulled.
2. F5-only partial fix: the black hole is per flow and per boot (CEF hash), so LAB.md does not name which flows die.
3. CR2 uses key-chain/hmac-sha-256 on ioll2-xe SVIs (works; no MD5 fallback needed). A link whose second end follows inside the 4 s dead interval does not reset, so the "one reset per link" bound is met either way.
4. RA lifetime: no distribution switch is restarted anywhere in the lab or its drills (only the cores are stopped; they re-apply `lifetime 12` through the EEM applet RA-LIFETIME, verified after restart). LAB.md says switches are not restarted without naming the cause (platform limitation: RA lifetime lost after `write memory` and restart; ioll2-xe has no EEM).
5. `write memory` before a core stop saves the student's CR changes (V3 asks to save first).

## Intentional Faults

| ID | Device | Change | Symptom |
|---|---|---|---|
| F1 | HQ-DIST1 e1/2 | trunk allowed list `10,20,99` (VLAN 50 missing) | VLAN 50 cannot use ACC3's DIST1 uplink |
| F2 | HQ-ACC3 e0/1 | `spanning-tree guard root` (instead of loop guard) | e0/1 root-inconsistent whenever it would be the root port; `%SPANTREE-2-ROOTGUARD_BLOCK` |
| F3 | HQ-DIST2 Vlan902 | OSPFv3 hello/dead at defaults 10/40 (design 1/4) | no OSPFv3 adjacency on 902; IPv4 unaffected |
| F4 | HQ-DIST2 Vlan904 | `ospfv3 1 ipv6 area 10` missing | no OSPFv3 adjacency on 904; with F3 DIST2 has no IPv6 routes beyond its own subnets |
| F5 | HQ-CORE2 e0/2.50 | `shutdown` | CORE2 not a VLAN 50 backup; no symptom while CORE1 is up |
| F6 | HQ-DIST2 e1/1 | trunk allowed `904,20` (VLAN 50 missing) | CORE2 has no L2 path to VLAN 50 even with F5 fixed |

Fault logic: TK1 = F1 and F2 parallel (either fix restores service; the other is exposed by pulling the working uplink). TK2 = F3 and F4 parallel (either fix restores DIST2's IPv6; the other is exposed by pulling the working transit link / stopping the core). TK3 = F5 and F6 in series. Red herrings: ACC3 answers management pings (VLAN 99 uses e0/0); ACC1/ACC2 uplinks to DIST2 are blocking by design; VLAN 20's master is CORE2; the "IPv6 go-live" entry points at the RAs, which are correct; boot-time adjacency logs.

## Diagnosis / Methodology

**TK1 (plausible subsystems: PC3/access port, ACC3 uplink trunks, spanning tree, VLAN 50 gateway on the core, core–DIST trunks).** PC3 reaches nothing off-floor; ACC3 is reachable on VLAN 99 (rules out ACC3 down, PC3 port). Evidence: `show spanning-tree vlan 50` on ACC3 shows itself as root (priority 32818) with e0/1 `Desg BKN* *ROOT_Inc`; `show spanning-tree inconsistentports` lists Et0/1 for VLAN 50 and 99 and the log has `ROOTGUARD_BLOCK`; DIST1 `show interfaces trunk` shows Et1/2 allowed `10,20,99`. VLAN 50 gateway and core trunks are healthy (CORE1 VRRP 50 MASTER, CORE1 trunks carry 50). Fix one, confirm service; then the pull test of the working uplink exposes the other.

**TK2 (IPv6 addressing on DIST2, RAs, OSPFv3 adjacencies, OSPFv2).** OSPFv2 FULL everywhere (IPv4 green) eliminates L1/L2 and OSPFv2. DIST2 `show ospfv3 neighbor` is empty and `show ipv6 ospf interface brief` shows Vl902 `Nbrs 0/0` and no Vl904 line. Vl902 is enabled but with default timers: `debug condition interface Vlan902` + `debug ospfv3 hello` prints `Mismatched hello parameters ... Dead R 4 C 40, Hello R 1 C 10` (without the debug there is no mismatch log line). Vl904 has no `ospfv3 1 ipv6 area` line. RAs are correct (`show ipv6 interface Vlan10`: every 4 s, live 12 s), so the go-live entry is a red herring.

**TK3 (VRRP configuration and priorities, core subinterfaces, core–DIST trunk contents, STP for VLAN 50, OSPF).** Drill: stop CORE1; VLAN 50 stays dark. CORE2 `show interfaces Ethernet0/2.50` says `administratively down` (`show vrrp brief` may list it MASTER at first boot; trust the interface line); DIST2 e1/1 allowed `904,20` has no VLAN 50. Fixing only F5 creates a second VRRP master on an isolated VLAN and ECMP black holes (below), so the series pair needs both. Instructor debrief: ACC3 stayed manageable because VLAN 99 rides e0/0 (not root-guarded for 99 as the active uplink), and the partial TK3 fix is worse than none because CORE2 advertises 10.10.50.0/24 into OSPF without a working path.

## Solution Configuration

Tickets (each fix alone was tested, see Verification):

```
HQ-DIST1:  interface Ethernet1/2 / switchport trunk allowed vlan add 50
HQ-ACC3:   interface Ethernet0/1 / no spanning-tree guard root / spanning-tree guard loop
HQ-DIST2:  interface Vlan902 / ospfv3 hello-interval 1 / ospfv3 dead-interval 4
HQ-DIST2:  interface Vlan904 / ospfv3 1 ipv6 area 10
HQ-CORE2:  interface Ethernet0/2.50 / no shutdown
HQ-DIST2:  interface Ethernet1/1 / switchport trunk allowed vlan add 50
```

CR1 (order CORE1, DIST1, DIST2, CORE2, about 8 s apart; cores use `no-summary`):

```
cores:  router ospf 1 / area 10 stub no-summary ;  router ospfv3 1 / address-family ipv6 unicast / area 10 stub no-summary
DISTs:  router ospf 1 / area 10 stub ;             router ospfv3 1 / address-family ipv6 unicast / area 10 stub
```

CR2 (key chain on all four routers/switches, then `ip ospf authentication key-chain OSPF-KEY` on both ends of each link, each pair within about 3 s):

```
key chain OSPF-KEY / key 1 / key-string ROUTEKEY123 / cryptographic-algorithm hmac-sha-256
interface <core interconnect, Vlan901-904 and the matching core subinterfaces / e0/0> / ip ospf authentication key-chain OSPF-KEY
```

CR3 (Po3 first, then Po2; spares `no shutdown` at both ends):

```
DIST1/DIST2: interface Port-channel<N> / switchport trunk encapsulation dot1q / switchport trunk native vlan 999 / switchport trunk allowed vlan 50,99 / switchport mode trunk / switchport nonegotiate / spanning-tree guard root
             interface range Ethernet1/2 - 3 / same trunk lines, no member-level guard / channel-group <N> mode active / no shutdown
ACC3:        interface Port-channel<N> (same trunk lines + spanning-tree guard loop); members Ethernet0/0, 0/2 (Po2) and 0/1, 0/3 (Po3) / channel-group <N> mode active / no shutdown
```

(Po2 = ACC3–DIST1, Po3 = ACC3–DIST2; the DIST side guard is `guard root`, the ACC3 side `guard loop`.)

CR4:

```
CORE2: interface Ethernet0/2.50 / vrrp 50 address-family ipv4 / priority 120 / exit-vrrp ;  ipv6 nd router-preference high
CORE1: interface Ethernet0/1.50 / ipv6 nd router-preference medium
Give back: CORE2 no priority 120, no ipv6 nd router-preference ;  CORE1 ipv6 nd router-preference high
```

Finally `write memory` on every device.

## Verification

All outputs observed in CML (5 flows in parallel at 4 pings/s).

- Start state: OSPFv2 FULL on all 8 adjacencies; OSPFv3 CORE1 FULL to CORE2 and DIST1 only, DIST2 none; DIST1 `ping 2001:db8:ffff:10::12` `% No valid route for destination`, `ping 10.255.10.12` 100%. ACC3 VLAN 50 root 32818 (itself), `Et0/1 Desg BKN* *ROOT_Inc`, inconsistentports VLAN0050 and VLAN0099 Et0/1. CORE2 `Ethernet0/2.50 is administratively down`. PC3 to 10.10.50.1, .2, 10.10.10.101: 0%; PC1/PC2 to PC3 (v4, v6) 0%; PC1<->PC2 works.
- **TK1 causality.** F1 alone fixed: PC1<->PC3 v4 3/3, v6 3/3, ACC3 root port e0/0 but `Et0/1 Desg BKN* *ROOT_Inc` still (VLANs 50 and 99 root-inconsistent on the alternate port). Cable pull (ACC3 e0/0 + DIST1 e1/2): PC1->PC3 4/4 lost, e0/1 stays BKN. F2 alone fixed (F1 present): after ~30 s ACC3 root port e0/1, e0/0 `Root BKN* *LOOP_Inc`, PC1->PC3 4/4 OK; cable pull (ACC3 e0/1 + DIST2 e1/2): 4/4 lost. Both fixed: root e0/0, e0/1 `Altn BLK`, PC3 reachable.
- **TK2 causality.** F4 alone fixed: DIST2 FULL to CORE2 on Vl904 only, DIST1<->DIST2 loopback v6 ping 3/3; cable pull of 904 (CORE2 e0/2 + DIST2 e1/1): no OSPFv3 neighbour, `% No valid route`. F3 alone fixed: FULL to CORE1 on Vl902, 3/3; pull of 902: no route. Both fixed: two OSPFv3 neighbours.
- **TK3 causality.** F5 alone fixed (F6 present): CORE2 VRRP 50 MASTER (own priority 100) beside CORE1 MASTER 110; DIST1 and DIST2 hold two O IA paths to 10.10.50.0/24. PC1->PC3 0/3, PC2->PC3 0/3, DIST1 `ping 10.10.50.103 source Vlan10` 0/3 and `source Vlan99` 0/3 (source Loopback0 3/3), CORE2 own ping 0/3, CORE1 3/3. `show ip cef exact-route 10.10.10.2 10.10.50.103` goes out Vlan901 (CORE1) but `10.255.10.11 -> 10.10.50.103` out Vlan903 (CORE2): which flows die varies per boot. F6 alone fixed: no change (subinterface still down). Both fixed: CORE1 MASTER 110, CORE2 BACKUP; every source reaches PC3; DIST routes ECMP via both cores.
- **CR1.** Intended answer: totally stubby area 10 (stub on the DISTs, `no-summary` on the cores). The requirement says the DISTs hold only their own area's routes plus a default; VLAN 20 and 50 are in area 0, so they are reached through the default. A plain stub would still leave the area 0 inter-area routes on the DISTs and fails the requirement. Loss 0–2 pings per flow (at most 0.5 s at 4 pings/s), well inside the LAB R3 bound of the 4 s dead interval. Totally NSSA (`area 10 nssa no-summary`) also meets R3 (accept it): the DISTs get the same table (O*IA default plus area 10 routes, both stacks). Debrief: area 10 has no ASBR, so NSSA's type-7 machinery has no purpose here, and totally stubby is the fitting design. DIST1 `show ip route ospf`: `O*IA 0.0.0.0/0` via both cores plus area 10 intra routes only; `show ipv6 route ospf`: `OI ::/0` plus intra. CORE1 `show ip ospf`: `Area 10 ... It is a stub area, no summary LSA in this area`. Hosts still reach 10.10.50.103 and 10.255.10.1. `show ip route 10.10.50.0` is empty on the DISTs afterwards (default only). Converting a DIST first or the cores out of order isolates that device for the re-formation time (unsafe-order consequence: adjacencies sit in LOADING for 25–60 s in this bench, far beyond the 4 s bound; ECMP via the other core carried traffic; not separately measured; CR1 order rationale derived).
- **CR2.** `show ip ospf interface Vlan901`: `Cryptographic authentication enabled / Sending SA: Key 1, Algorithm HMAC-SHA-256 - key chain OSPF-KEY`. 0 lost pings on every flow, no ADJCHG event (the second end follows inside the 4 s dead interval); a slower second end resets that adjacency, which re-forms in 25–60 s with ECMP carrying traffic.
- **CR3.** `show etherchannel summary`: Po2(SU) Et0/0(P) Et0/2(P), Po3(SU) Et0/1(P) Et0/3(P); ACC3 `show spanning-tree vlan 50`: root port Po2 FWD, Po3 `Altn BLK` (one blocked logical link as before, no inconsistent ports). 0 lost pings during both conversions.
- **CR4.** CORE2 MASTER after the 30 s preempt delay (CORE1 `BACKUP 110`); give-back returns CORE1 MASTER; 0 lost pings on all flows (v4 and v6) both directions. Alpine `ip -6 route show default` lists both RA routers at the same metric (no preference visible host-side). IPv6 proof for the role move (measured on MS-1): during the window `traceroute6` from PC3 to PC1 has first hop 2001:db8:10:50::3 (CORE2), and `show ipv6 routers` on CORE1 lists CORE2's RA on the VLAN 50 subinterface with Preference=High; after give-back the first hop is 2001:db8:10:50::2 (CORE1) again.
- **V1 end state:** all host pairs, switch loopbacks and routed loopbacks reply over v4/v6; VLAN 99 addresses answer after the first ARP; the re-check saw 1–2 of 4 lost, so repeat at least 5 (as LAB.md V1 says).
- **V4 evidence types:** `%SPANTREE-2-ROOTGUARD_BLOCK` or `show spanning-tree inconsistentports` (TK1), the interface-conditioned `debug ospfv3 hello` mismatch line or a ping sourced from a DIST loopback (TK2), `%OSPF-5-ADJCHG` / VRRP state lines or a sourced ping during the stop-CORE1 drill (TK3).

## Failure / Recovery Behaviour

Method: node stop = silent failure (cores saved with `write memory` first); cable pull = `shutdown` on both ends; a one-ended member shutdown is not valid.
- Core stop (solved state, then again with CR1–CR4): CORE1 stop: IPv4 loss 11–13 pkts (about 3 s), IPv6 38–42 pkts (about 9.5–10.5 s); CORE2 became VLAN 50 master; DIST1 routes 10.10.50.0 via CORE2 only. CORE2 stop: IPv4 12–17 pkts (3–4 s), IPv6 42 pkts (about 10.5 s); VLAN 20 hosts unaffected when CORE1 stops. Restart (BOOTED in about 31 s): roles return after the 30 s preempt delay with about 1 lost ping (meets V3's "at most one lost ping"); OSPF FULL, auth and stub kept; CORE1 RA `live for 12 seconds` after boot (EEM applet re-applied). V3 targets with margin: IPv4 5 s, IPv6 15 s. IPv6 host failover is slower than IPv4 by design (RA timers), not a defect.
- Access uplink pulls (ACC1 e0/0 + DIST1 e0/2; ACC3 alternate Po3 member e0/1 + DIST2 e1/2): 0 lost. Active bundle member (ACC3 Po2 member e0/0 + DIST1 e1/2): 18–19 pkts on PC3 flows (about 4.5 s, includes about 3 s between the two `shutdown` blocks); target 10 s.
- Po1 member (V3 "one member of each bundle" includes the DIST interconnect; measured in the solved tickets state, 160 pings at 4/s, PC1 to DIST2 Vlan10 10.10.10.3 across Po1 and PC2 to DIST2 Vlan99 10.10.99.12): `shutdown` of Ethernet0/0 on both DISTs lost 4 of 160 (PC1, about 1 s) and 3 of 160 (PC2); `show etherchannel summary` `Po1(SU) Et0/0(D) Et0/1(P)`. The same pull on Ethernet0/1 lost 0 of 160 on both flows. Restored with `no shutdown` at both ends: `Et0/0(P) Et0/1(P)` after about 20 s. Well inside V3's 10 s.
- No DIST restart is performed anywhere in this lab.

## Answers to Analysis Questions

Q1. Suggested order: TK3 first (CR4 depends on it and the drill needs it), TK1 (CR3 rebuilds the same ports, so a student who bundles first carries F1/F2 into the port-channels), TK2, then the windowed CR1 and CR2, then CR3, CR4 and the V3 drills. CR4 cannot pass until TK3 is fully fixed; CR3 depends on TK1.
Q2. TK1: after fixing either F1 or F2 service returns; the cable pull of the working ACC3 uplink exposes the other. TK2: after either fix DIST2 has IPv6 through one core; pulling that transit link (or stopping that core) exposes the other. TK3: fixing the subinterface alone makes a second VRRP master and ECMP black holes to the server floor; the stop-CORE1 drill shows the trunk is still missing VLAN 50.
Q3. CR1: 0–2 pings per flow, kept inside the limit by converting the cores/DISTs one at a time in the safe order with ECMP carrying traffic. CR2: 0 lost, the second end of each link was configured within the 4 s dead interval, so no adjacency reset (otherwise one reset per link). CR3: 0 lost (alternate bundle first). CR4: at most one lost ping (30 s preempt delay and high preference).
Q4. Survives: loss of either core (IPv4 about 3–4 s, IPv6 about 10.5 s), loss of any one access uplink or bundle member (0–4.5 s), loss of one transit link (ECMP via the other core), a single DIST-side uplink loss to the server floor. Does not survive: loss of the whole DIST interconnect (the core-routed VLANs split, known H2 limitation, 021 Q3), simultaneous loss of both cores, loss of PC3's single access port.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-18 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), iol-xe (IOS XE 17.16.1a), ioll2-xe (IOS XE 17.16.1a) |
