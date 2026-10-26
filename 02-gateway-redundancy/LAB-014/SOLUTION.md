# LAB-014 — Solution

## Summary

Troubleshooting lab (T · G2 · 75 min) for blueprint domains 3 (Infrastructure) and 4 (Network Assurance); blueprint mapping (instructor-only): 3.3.c:T, 3.1.c:T, 3.1.b:R. Built on the HQ H1 baseline (LAB-012) with three faults injected into the day-0 configs of HQ-ACC2 and HQ-DIST2. Two tickets: T1 (OPS floor isolated) and T2 (quarterly failover test). T1 is one user-visible fault (F1) plus a gateway misconfiguration (F2) found by verification (the direct VIP ping in V1): F1 alone accounts for essentially all of T1's reported symptom, and F2 is caught because V1 tests the documented gateway address. F3 (a stale default gateway on ACC2) is **not** exposed by the failover test on this platform: T2 passes with F3 present, so F3 is found only by the design audit (V2: compare the running configuration against the documented design), not from a symptom.

## Intentional Faults

| ID | Device | Change | Symptom |
|---|---|---|---|
| F1 | HQ-ACC2 | `spanning-tree vlan 20 priority 4096` added after `spanning-tree mode rapid-pvst` | ACC2's BPDUs for VLAN 20 are superior to both distribution switches (4116 < 24596). Root guard on HQ-DIST1 e0/3 and HQ-DIST2 e0/3 puts both ports root-inconsistent for VLAN 20 (`%SPANTREE-2-ROOTGUARD_BLOCK` at every cold boot). ACC2's VLAN 20 uplinks are blocking on both distribution switches; VLANs 10/99 unaffected |
| F2 | HQ-DIST2 | `standby 20 ip 10.10.20.10` instead of `.1` | The VIP mismatch makes each switch reject the other's HSRP hellos (`%HSRP-4-DIFFVIP1` on both, not just one), so group 20 splits into two independent single-member groups: HQ-DIST1 self-elects Active for `10.10.20.1`, HQ-DIST2 self-elects Active for `10.10.20.10` — both "Standby router unknown". Both program the **identical** HSRPv2 virtual MAC (derived from the group number, not the VIP), so a direct ping to the documented VIP `10.10.20.1` resolves ARP but gets 100% ICMP loss (the access-layer MAC table for that shared vMAC points at HQ-DIST2's port, which does not own `.1`); a ping to `10.10.20.10` succeeds (0% loss, answered by HQ-DIST2) |
| F3 | HQ-ACC2 | `ip default-gateway 10.10.99.11` (left over from before the redundancy project; ACC1 was correctly migrated to `.1`) | Latent: no effect while HQ-DIST1 is up. Fails the documented-design audit (V2) at any time; on this platform the failover test passes with F3 present (the expected symptom, ACC2 unreachable when HQ-DIST1 is down, does not appear) — see Diagnosis. Found by the design audit (V2) |

**Fault logic:**
- T1 needs F1 **and** F2 fixed. They are not in series (F1 does not mask F2's user impact); fixing only F1 leaves the ticket's core check (V1, ping to the default gateway address) failing:
  - F1 alone blocked: the access switch's VLAN 20 uplinks are both blocking, so nothing on that VLAN reaches anything off-floor.
  - F1 fixed, F2 still present: VLAN 20 connectivity is restored at the L2/root level, and — on this platform — most reachability actually returns (see Diagnosis note below: both switches self-elect Active on a split HSRP group and share one virtual MAC), **except** a direct ping to the documented gateway address itself, which fails 100% of the time (ARP resolves, ICMP does not, because the shared vMAC's traffic lands on HQ-DIST2's port and HQ-DIST2 does not own `.1`). A V2 config audit also fails immediately (VIP shown is `.10`, not `.1`).
  - Both fixed: full V1 pass, including the direct gateway ping.
- F3 is latent and independent of F1/F2: it is caught by V2 (config audit) reliably; the T2 live-failover symptom you would expect does not reliably reproduce on this platform (Diagnosis note).
- Two plausible wrong fixes were tested and shown to fail V2 despite appearing to restore user connectivity:
  1. **Remove root guard** instead of fixing F1: HQ-ACC2 becomes the spanning-tree root for VLAN 20, and PC2 reaches the rest of the network through the "long way" (via the now-unprotected uplink). V2 fails: the documented root for VLAN 20 is HQ-DIST2, not HQ-ACC2.
  2. **Raise HQ-DIST1's VLAN 20 priority** instead of fixing F2 — live-tested and found not to be a plausible wrong fix. Raising HQ-DIST1's priority to 120 (above HQ-DIST2's 110) had **no effect on the symptom**: both switches remained independently `State is Active` (`Standby router is unknown`) and `ping 10.10.20.1` from HQ-PC2 stayed at 100% loss, unchanged. This is because F2's VIP mismatch makes the two switches reject each other's HSRP hellos outright (`%HSRP-4-DIFFVIP1`) before priority is ever compared — there is no negotiation for a priority change to influence. Unlike wrong fix 1 (which genuinely restores user-visible service while leaving the design non-compliant), this candidate does not restore anything and would not tempt a student who tests V1 — it is kept here only as a documented dead end, not as a second "appears to work" trap.

## Diagnosis / Methodology

**T1 candidates and eliminating evidence:**

| Candidate | Evidence |
|---|---|
| PC2 host / access port | Address and gateway correct; access port VLAN 20, PortFast, forwarding. Eliminated |
| Access switch's uplink trunks | Both trunks up, native VLAN correct, VLAN 20 allowed on both ends (`show interfaces trunk`). But VLAN 20 is not forwarding on the distribution end: leads to spanning tree |
| Spanning tree, VLAN 20 | `show spanning-tree inconsistentports` on both distribution switches: the access-facing port is root-inconsistent for VLAN 20; `%SPANTREE-2-ROOTGUARD_BLOCK` in the log; the access switch claims to be root for VLAN 20 with priority 4116: **F1** |
| Distribution interconnect (Po1) | `Po1(SU)` with both members `(P)`. Eliminated (reused for V4) |
| Virtual gateway, VLAN 20 | After F1 is fixed: the host still cannot reach `10.10.20.1` directly (100% loss, reproduced 3×), even though it can now reach the rest of the network (see note below); `show standby vlan 20` on HQ-DIST2 shows virtual IP `10.10.20.10` and `State is Active`; `show standby vlan 20` on HQ-DIST1 shows virtual IP `10.10.20.1`, also `State is Active`, `Standby router is unknown` — **both** switches claim Active on a split group; a `%HSRP-4-DIFFVIP1` log appears on **both**: **F2** |
| Inter-VLAN routing on the distribution switches | The first-floor host reaches both VLAN 20 SVIs directly; routing tables hold every VLAN as connected. Eliminated |

**T2 candidates:** load-sharing gateway takeover (VLAN 10), active/standby gateway takeover (VLANs 20, 99), spanning-tree reconvergence with loop guard, access-switch management gateways. Evidence for F3: `show running-config | include default-gateway` on the access switches shows the second-floor switch still pointing at the first distribution switch's physical address rather than the virtual management address (V2). This is the only cause with no accompanying log message.

**Platform-specific note (recorded for the instructor, not the student; the F1/F2 mechanism was measured on CML):** after F1 is fixed but F2 is not, the second-floor host actually regains reachability to the first-floor host and every switch's management address — the "reaches nothing off-floor" symptom from T1 substantially clears. Only a **direct** ping to the documented gateway address (`10.10.20.1`) reliably fails. The real mechanism: the VIP mismatch makes HQ-DIST1 and HQ-DIST2 reject each other's HSRP hellos (`%HSRP-4-DIFFVIP1` logged on **both**, not just the standby), so group 20 splits into two unsynchronized single-member groups — HQ-DIST1 self-elects Active for `.1` (priority 100, `Standby router is unknown`), HQ-DIST2 self-elects Active for `.10` (priority 110, `Standby router is unknown`). Because HSRPv2's virtual MAC is derived from the **group number**, not the VIP, both switches program the identical vMAC (`0000.0c9f.f014`) at the same time. A ping to `10.10.20.1` resolves ARP to that shared vMAC (confirmed: PC2's `ip neigh` shows a resolved entry, `REACHABLE` or `STALE` depending on timing; observed `REACHABLE` right after the pings) but gets 100% ICMP loss, because the access-layer switches' MAC forwarding table for that one shared address ends up pointing at HQ-DIST2's port — and HQ-DIST2 does not own `.1`, so it silently drops the frame. A ping to `10.10.20.10` succeeds at 0% loss, answered by HQ-DIST2. This is an ARP-resolves-but-no-ICMP-reply failure, not a missing-ARP failure — and it is not simply "the standby doesn't answer for its peer's VIP": with F2 present, there is no true standby at all, only two simultaneous, unsynchronized Actives sharing one MAC. This is why V1 explicitly tests the gateway address directly rather than only "reaches PC1" — testing reachability alone would make the ticket look closed after F1 alone. Similarly, F3's "ACC2 unreachable when HQ-DIST1 is down" symptom did not reproduce live: even after removing the stale ARP entry outright (`no arp 10.10.99.11`) and forcing a fresh resolution attempt, no new ARP entry was created and traffic still passed. Why it does not reproduce is **measured on CML and is a CML image (ioll2-xe) artefact**: the ioll2-xe access switch never uses `ip default-gateway` to choose an ARP next hop. For an off-subnet destination it ARPs for the *destination itself* (HQ-ACC2's ARP table holds the remote host mapped to the Vlan99 HSRP vMAC), and whichever HQ-DIST is Active for group 99 proxy-ARPs for it. With HQ-DIST1 stopped, HQ-DIST2 becomes Active and answers the same ARP, so the wrong `.11` is never needed. Control: with `no ip proxy-arp` on both Vlan99 SVIs, every off-subnet management path fails with HQ-DIST1 up, HQ-ACC1 (correct gateway) included, so proxy ARP cannot be turned off to expose F3. **Hardware expectation:** a real switch sources its management traffic via its default gateway, so with F3 (`ip default-gateway 10.10.99.11`) a failover to HQ-DIST2 would cut HQ-ACC2's off-subnet management. Treat F3 as a real fault that CML cannot show. V2's static config audit remains fully reliable regardless of this data-plane behavior, which is why the lab's verification criteria rely on it for F3.

## Solution Configuration

Tested in CML.

**Fix F1** (HQ-ACC2):
```
no spanning-tree vlan 20 priority 4096
```

**Fix F2** (HQ-DIST2):
```
interface Vlan20
 standby 20 ip 10.10.20.1
```

**Fix F3** (HQ-ACC2):
```
no ip default-gateway 10.10.99.11
ip default-gateway 10.10.99.1
```

## Verification

```
HQ-DIST1# show spanning-tree inconsistentports
Number of inconsistent ports (segments) in the system : 0

HQ-DIST1# show standby brief
Vl20   20  100 P Standby 10.10.20.3   local          10.10.20.1
Vl99   99  110 P Active  local        10.10.99.12    10.10.99.1

HQ-PC2$ ping -c 6 10.10.20.1
6 packets transmitted, 6 packets received, 0% packet loss
```
Matches the H1 baseline exactly (LAB-012 SOLUTION.md verification block). V1/V2 PASS.

**Fault reproduction (boot-time logs, identical on a fresh import):**
```
%SPANTREE-2-ROOTGUARD_BLOCK: Received a superior STP BPDU from bridge <ACC2-bridge-id>. Root guard blocking port Ethernet0/3 on VLAN0020.  (both HQ-DIST1 and HQ-DIST2)
%HSRP-4-DIFFVIP1: Vlan20 Grp 20 active routers virtual IP address 10.10.20.10 is different to the locally configured address 10.10.20.1
```

**Wrong fix 1 tried and shown to fail V2:** removed `spanning-tree guard root` from both distribution switches' e0/3 (F1 left in place) → `show spanning-tree vlan 20` on HQ-ACC2: "This bridge is the root", priority 4116; HQ-PC2 reached `.1`/.2/.3 through the now-unprotected path. Reverted (root guard restored, F1 properly fixed instead).

## Failure / Recovery Behaviour

**T2, stop the first distribution switch** (configs saved first): second-floor host → first-floor host 0% loss (20 pings @ 0.5 s); → second distribution switch's management address 16% (ARP-timing, not FHRP-timing) — both well under the 10 s target. Restarting it: roles returned after ~50 s (within the 30 s stability window plus settling).

**T2, stop the second distribution switch:** first-floor host → second-floor host 10% loss (20 pings @ 0.5 s); → first distribution switch's management address 33% (ARP-timing) — both well under 10 s. Roles returned about 28 s after the node finished booting on restart (the boot itself took 12-53 s).

**V4, one interconnect member (both ends, per the LAB-012 platform finding — a one-sided `shutdown` is not a valid single-link test on this platform):** 1/20 pings lost (5%). Restored; `Po1(SU)` both members `(P)`.

## Answers to Analysis Questions

**Q1.** Candidates were ruled out from the outside in: the host and its access port first (both correct), then the access switch's trunks (up, correct VLANs, so not a trunk-negotiation problem), which pointed at spanning tree once "VLAN 20 not forwarding on the distribution end" appeared in `show interfaces trunk`. `show spanning-tree inconsistentports` was the single piece of evidence that both identified the mechanism (root guard) and the culprit (the access switch's priority) in one command. The same root-inconsistent signature appeared on the same ports after losing the interconnect in LAB-013(e), so the discriminating step between "rogue access-switch priority" and "interconnect loss" is the interconnect check (`Po1(SU)` with both members `(P)`) together with the access switch claiming to be root with priority 4116. From there, fixing that alone still left the gateway address itself unreachable, which is what led to checking the gateway's own state (`show standby brief`) and finding the VIP mismatch.

**Q2.** `%SPANTREE-2-ROOTGUARD_BLOCK` mapped directly to F1 (both distribution switches log it, naming the interface and the superior bridge). `%HSRP-4-DIFFVIP1` mapped directly to F2 (logged periodically on both distribution switches). F3 left no log message at all — it was found only by comparing the access switch's running configuration against the documented design (V2), since the misconfigured address is a valid, working address while HQ-DIST1 is up and produces no error and no log. On this platform it does not even produce a symptom when HQ-DIST1 is stopped (the failover test passes with F3 present), so it is an audit find, not a symptom-driven one. Evidence for each cause: F1 by `show spanning-tree inconsistentports` and the root-guard log, F2 by `show standby` and the DIFFVIP log, F3 by the configuration comparison alone. A student who found the first two from the ticket and the third only from the audit used the right method for each.

**Q3.** The most reliable method is a fixed-interval, fixed-count ping (e.g. one probe every 0.5 s for 10-20 s) from a host, started immediately after taking a distribution switch out of service, and counting lost replies rather than trusting a single ping's round-trip time. On this platform the result can differ from physical hardware for two reasons: a stopped node's link to a still-running neighbor does not go link-down, so failover is driven purely by protocol hold timers rather than any faster link-down-triggered convergence a real chassis might also benefit from; and the software's per-flow forwarding and ARP behaviour can shorten or mask outages in ways a real forwarding ASIC might not (not separately measured here).

**Q4 (post-fix).** A change-review checklist for weekend maintenance work should have required: (1) a spanning-tree priority audit on every switch touched, comparing against the documented root/secondary table, which would have caught F1 immediately; (2) a virtual-gateway address audit (`show standby brief` / `show glbp brief` compared against the documented VIP table) on every FHRP-capable device touched, which would have caught F2; and (3) a full `default-gateway`/static-route audit on every access switch against the current (not historical) documented design, which would have caught F3 even though it produces no immediate symptom — the checklist item exists precisely to catch changes that "work" today but fail only when a specific redundant path is later needed.

**Instructor debrief (not shown to students).** Removing root guard "fixed" the symptom because a superior BPDU is, by definition, one that spanning tree would otherwise accept as a legitimate new root — root guard's entire purpose is to override that normal, "correct" STP behavior when the source is known to be untrustworthy (an access switch). The NOC's ping of the access switch's own management address proved nothing about VLAN 20 because that address lives on VLAN 99, a completely separate broadcast domain and gateway from VLAN 20 — the switch answering on its own management network says nothing about whether it can forward traffic for a different VLAN whose uplinks are blocked.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-17 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), ioll2-xe (IOS XE 17.16.1a) |
