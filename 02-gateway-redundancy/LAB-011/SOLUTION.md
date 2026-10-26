# LAB-011 — Solution

## Summary

This is a Foundation (F), guided (G3) lab teaching HSRP (v1 and v2), VRRPv3, priority/preemption, interface tracking, and FHRP failure/recovery behaviour on a 3-router/1-switch/2-host bench (blueprint 3.3.c:I, 1.1.b:I). There are no intentional faults: every requirement is additive configuration on top of a working OSPF/Layer-2 starting state. The teaching payload is in the *behaviour* students observe at each step (election, timers, virtual MAC changes, preemption, tracking, and — in R6 — what tracking can and cannot see).

## Diagnosis / Methodology

Not applicable in the troubleshooting sense (no fault to diagnose). The build/verification order used, and expected for students, is strictly sequential: R1 (HSRPv1 election) → R2 (priority + preempt) → R3 (HSRPv2 migration) → R4 (VRRPv3) → R5 (tracking on both groups) → R6 (failure tests on the fully-configured bench). Each step's `show` output and log lines were captured before moving to the next, and PC1/PC2 pings were used to confirm the *host-visible* effect of every router-side change, not just the router's own state.

## Solution Configuration

**R1** (final, after R1–R5; day-0 has none of this):
```
track 1 interface Ethernet0/1 line-protocol
!
fhrp version vrrp v3
!
interface Ethernet0/0
 standby version 2
 standby 10 ip 10.0.10.1
 standby 10 timers 1 3
 standby 10 priority 110
 standby 10 preempt delay minimum 30
 standby 10 track 1 decrement 20
!
interface Ethernet0/2
 vrrp 20 address-family ipv4
  address 10.0.20.1 primary
  exit-vrrp
```

**R2** (final, after R1–R5):
```
track 1 interface Ethernet0/1 line-protocol
!
fhrp version vrrp v3
!
interface Ethernet0/0
 standby version 2
 standby 10 ip 10.0.10.1
 standby 10 timers 1 3
 standby 10 preempt delay minimum 30
!
interface Ethernet0/2
 vrrp 20 address-family ipv4
  priority 120
  track 1 decrement 20
  address 10.0.20.1 primary
  exit-vrrp
```

**Platform finding:** the VRRPv3 tracking syntax that works is `track <n> decrement <x>` directly inside `vrrp <grp> address-family ipv4` (confirmed via context help: `track 1 ?` → `decrement | shutdown`); a `tracked-object <n> decrement <x>` keyword is rejected. VRRPv3 tracking works exactly like HSRP tracking once configured.

R2's priority for HSRP group 10 was left at the IOS default (100); only R1 has an explicit `standby 10 priority 110`.

## Verification

**R1 — HSRPv1 election (no priority):**
```
R2# show standby brief
Interface   Grp  Pri P State   Active          Standby         Virtual IP
Et0/0       10   100   Active  local           10.0.10.2       10.0.10.1
```
R2 (10.0.10.3, the higher IP) won the tie over R1 (10.0.10.2); both had the default priority 100. This outcome depends on configuration order, not just IP: with equal priority, whichever router reaches Active first (typically whichever is configured first) keeps the role, and the higher-IP tie-break only decides the election when both routers negotiate together (e.g. both come up in Speak state at the same time). A student who configures R1 noticeably earlier than R2 will correctly see R1 remain active. The same holds after the election: an Active router is not displaced by a peer with equal priority, even with `preempt` and a higher IP (measured, see Q3).
`R1# show standby Ethernet0/0` → vMAC `0000.0c07.ac0a (v1 default)`, hello 3 s / hold 10 s, preemption disabled.
Packet capture on the R2–SW1 link confirmed HSRPv1 hellos to multicast `224.0.0.2`, UDP 1985.
Log (R1): `%HSRP-5-STATECHANGE: Ethernet0/0 Grp 10 state Speak -> Standby`.

**R2 — priority 110 + preempt:**
Without `preempt`: `show standby brief` on R1 showed priority 110 but state **Standby** — R2 remained Active despite having the lower priority, proving preemption is required for a priority change alone to take effect.
After `standby 10 preempt delay minimum 30` on both: R1 preempted about 6 s later (next hello cycle). Log (R1): `%HSRP-5-STATECHANGE: Ethernet0/0 Grp 10 state Standby -> Active`; `show standby brief` then showed R1 Active/local with the `P` (preempt) flag set.

**R3 — HSRPv2 migration:**
`R1# show standby Ethernet0/0` → "Group 10 (version 2)", vMAC `0000.0c9f.f00a (v2 default)`, hello 1 s / hold 3 s, still Active (priority 110, preempt delay retained).
`PC1# ip neigh show 10.0.10.1` → `lladdr 00:00:0c:9f:f0:0a` — the host's ARP cache follows the new virtual MAC without any host-side action. Ping to `.1` and to `10.0.100.1` (R3's Lo1) both succeed.

**R4 — VRRPv3 on LAN B:**
```
R2# show vrrp Ethernet0/2
Ethernet0/2 - Group 20 - Address-Family IPv4
  State is MASTER
  Virtual IP address is 10.0.20.1
  Virtual MAC address is 0000.5E00.0114
  Advertisement interval is 1000 msec
  Preemption enabled
  Priority is 120
```
`R1# show vrrp brief` → BACKUP, priority 100 (default). PC2 reaches `10.0.20.1` (one ping lost to ARP resolution, expected) and `10.0.100.1` (0% loss).

**R5 — tracking:**
```
R1# show standby Ethernet0/0
  ...
  Track object 1 state Up decrement 20

R2# show vrrp Ethernet0/2
  ...
  Track object 1 state UP decrement 20
R2# show track brief
Track Type        Instance                   Parameter        State Last Change
1     interface   Ethernet0/1                line-protocol    Up    00:24:35
```
Both HSRP and VRRPv3 tracking are confirmed live on this platform (VRRPv3 once the correct `track` keyword is used — see the platform finding above).

**Restored / re-verified start state (after removing all FHRP config):**
```
PC1$ ping 10.0.10.2   → 0% loss (physical R1)
PC1$ ping 10.0.10.1   → 100% loss (no VIP)
PC1$ ping 10.0.100.1  → 100% loss (no usable default route)
PC2$ ping 10.0.20.3   → 0% loss (physical R2)
PC2$ ping 10.0.20.1   → 100% loss
PC2$ ping 10.0.100.1  → 100% loss
```
Identical on a restored lab and on a fresh import of `LAB-011.yaml`.

## Failure / Recovery Behaviour

**R6, both-ended cable pull (R1 Et0/1 + R3 Et0/0 shut together):**
Continuous ping PC1 → 10.0.100.1 across the whole test: **130/130 received, 0% loss** (one 100 ms outlier, no drops). Timeline (R1 log): `TRACK-6-STATE Et0/1 line-protocol Up->Down` → 31 s later `HSRP Active->Speak` → `HSRP Speak->Standby` (R2 becomes Active; R1's priority dropped to 90 = 110 − 20). On restore (`no shutdown` both ends): track recovers, R1's priority returns to 110, but R1 stays Standby for **~31 s** — matching `preempt delay minimum 30` — before reclaiming Active. The 31 s between the track going Down and the hand-over is R2's `preempt delay minimum 30`: the delay holds back the *taking-over* router, so it applies to every tracked failover, not only to a router that has just reloaded. (`preempt delay reload`, or a shorter `minimum`, is the usual remedy when the delay should apply only after a reload.) Zero packet loss because R1 stayed in the forwarding path for that whole time: R1's uplink was down, but R1 was still Active and forwarded PC1's packets to R2 over the LAN-A OSPF adjacency, and R2 delivered them to R3. When R2 took over, the virtual MAC moved to R2 and SW1 relearned it; PC1 did not need to re-ARP because the virtual MAC and IP stay the same.

**R6, one-ended shutdown (only R3's end of the R1–R3 link):**
Continuous ping PC1 → 10.0.100.1: **150/150 received, 0% loss.** R1's own interface (`Ethernet0/1`) and its tracked object stayed **Up** throughout — this failure is invisible to interface tracking, as expected, and R1's HSRP state (Active, priority 110) never changed.
**Not the local dead timer:** you might expect R1 to keep forwarding into the dead link until its own OSPF dead timer (40 s) expired, causing a blackhole until then. The measured mechanism was faster and lossless: R3's OSPF process withdraws the R1–R3 link from **R3's own** router-LSA the instant R3's interface goes administratively down (`show ip ospf database router 10.255.0.3` showed only 3 links — both stub networks and the R2 transit network — with the R1 link entry gone, LSA age 126 s). Since OSPF SPF requires a link to be listed by **both** endpoints before using it, R1's SPF stopped using the R1–R3 edge and switched to the path via R2 as soon as it processed R3's updated LSA — well before R1's own local dead timer for that neighbor actually expired (`%OSPF-5-ADJCHG ... Dead timer expired`, logged only *after* the reroute had already happened). The real recovery mechanism is **LSA reflooding from the failing side, not the local dead timer** — faster and lossless, and the basis for the Q4 answer below.

**R2 (standby for LAN A / VRRP master for LAN B) reload, saved first:**
`copy running-config startup-config` on R2, then power-cycled (equivalent to `reload`, but avoids the IOS reload confirmation prompt hanging the console session). PC1 → 10.0.100.1 (LAN A, R1 untouched throughout): **180/180 received, 0% loss** — confirms the active router is unaffected by the standby's reload. PC2 → 10.0.100.1 (LAN B, VRRP): **176/180 received (4 lost, ~2.2%)**, both drops inside the first ~35 s while R1 (VRRP priority 100, preempt enabled) detected R2's master-down and took over (`%VRRP-6-STATE ... BACKUP -> MASTER` on R1), then handed back 16 s after R2 rebooted and preempted (`MASTER -> BACKUP`). The small real loss here — unlike the zero-loss HSRP tests — is because R2's whole node was down, not just an interface: nothing answered as the VRRP virtual MAC until R1's master-down timer (~3.6 s, advertisement-interval based) expired.

## Answers to Analysis Questions

**Q1.** Observed differences: (1) virtual MAC — v1 used `0000.0c07.ac0a`, v2 used `0000.0c9f.f00a` for the same group number; (2) group numbering — v1 supports groups 0–255, v2 extends this to 0–4095 (not directly exercised here since group 10 is valid under both — **(derived)**); (3) multicast hello destination — only v1's (`224.0.0.2`/UDP 1985) was captured in this build; v2 uses `224.0.0.102` — **(derived)**. The timers are **not** a difference: both versions default to hello 3 s / hold 10 s and both can be configured (the 1 s/3 s on R1 and R2 was this lab's own configuration); v2 advertises and learns millisecond timer values (v1 also accepts msec timers, with its own `msec` keyword for the hold time: `standby 10 timers msec 200 msec 750`, but v2 is the version designed for them), but it does not converge faster by default. Veridian should standardise on v2 for the larger group range, IPv6 support and a virtual MAC range (`0000.0c9f.fXXX`) that cannot be confused with v1's (`0000.0c07.acXX`) when both versions run in the same network.

**Q2.** The defaults are a fact of each protocol: HSRP preempt is off by default on Cisco IOS, VRRP preempt is on by default (RFC 5798). Preemption is a trade-off, not a right or wrong: on gives deterministic placement (the highest-priority router is always the gateway), but costs a second disruption when a failed router comes back; off avoids that second disruption but can leave the gateway on the less preferred router indefinitely. `preempt delay` (proven in R6's both-ended test: R1 waited ~31 s after its priority was restored before reclaiming Active, matching the configured `minimum 30`) softens that cost: a switch or router that has just reloaded does not declare itself active again until its interfaces, adjacencies and routing table have had time to reconverge, which avoids a black hole. The same delay also holds back the router that must *take over* after a tracked failure (R6 shows R2 waiting ~31 s after R1's track went Down), so a long `minimum` slows tracked failover too.

**Q3.** With R2 left at the default priority 100, R1 needs its priority to drop to 99 or below for R2 to preempt, so the smallest decrement that forces a failover is **11** (110 - 11 = 99 < 100); the lab used 20 for clear margin. If the decrement leaves R1 exactly equal to R2 (a decrement of 10, giving 100 = 100), **there is no failover**: measured on this platform (HSRPv2 group 10, `preempt delay minimum 30` on both, R1 `track 1 decrement 10`), after R1 Et0/1 was shut the tracked object went Down and R1 showed priority 100, yet 75 s later (well past the 30 s delay) `show standby brief` still had R1 Active / R2 Standby (both `P`, both priority 100), and R2's log held no Standby -> Active transition. So R2, despite having `preempt` and the higher IP (10.0.10.3 vs 10.0.10.2), does not take over at equal priority: an already-Active router keeps the role on a tie. The higher-IP tie-break only decides an election when both routers negotiate together (see the R1 key), not a hand-over from a working Active router. R1 therefore stays active with its uplink down, which is why the decrement must exceed the priority gap (here at least 11).

**Q4.** In the one-ended test, **OSPF restored traffic — specifically via LSA reflooding from R3, not via R1's own dead timer.** R3's interface going down caused R3 to immediately withdraw that link from its own router-LSA; R1's SPF recomputation (triggered by receiving that updated LSA over the still-good R1–R2–R3 path) dropped the now one-sided R1–R3 edge and rerouted via R2, before R1's local 40-second dead timer for that neighbor even expired. Measured recovery time was effectively instantaneous (0 lost pings in a 150-second continuous test). Interface tracking would never detect this class of failure at all — or any failure that isn't a loss of *local* line-protocol state, such as a failure on the far router's other interfaces, a failure of the far router's application/control-plane, or anything beyond the directly-tracked link.

**Q5.** A VRRP "address owner" (priority 255) is a router whose interface's real IP address **is** the virtual IP itself; an owner always wins election (nothing can preempt priority 255), does not need `preempt` configured, and answers directly to the VIP for protocols like ping/traceroute in a way a non-owner virtual router does not — **(derived)**, not directly tested in this lab, where both R1 and R2 use a separate "address ... primary" VIP rather than owning it. VRRP is the right choice when the paired gateways are not both Cisco because it is an open IETF standard (RFC 5798) implemented by essentially every vendor, whereas HSRP is Cisco-proprietary and generally will not interoperate with a non-Cisco peer.

**Q6.** A first-hop redundancy protocol protects hosts only against the failure of **the specific router (or, with tracking, its specific tracked uplink) acting as their gateway** — exactly what R1–R6 demonstrated: losing R1's uplink, or R2 itself, did not disrupt PC1/PC2's traffic. It does **not** protect against: the host's own NIC or cable failing (nothing on the network side can fix that); the access switch between the host and both routers failing — in this exact bench, SW1 is a single point of failure that HSRP/VRRP cannot route around, since both routers reach the host only through it; or any failure beyond the gateway, on the far side of the network (R6's one-ended test showed this directly: the failure was beyond what tracking could see, and only OSPF's independent convergence — not the FHRP pair — restored the path).

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-17 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), iol-xe (IOS XE 17.16.1a), ioll2-xe (IOS XE 17.16.1a) |
