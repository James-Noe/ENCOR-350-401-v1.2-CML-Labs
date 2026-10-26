# LAB-012 — Solution

## Summary

Implementation lab (I · G2 · 105 min) for blueprint **3.3.c** (first-hop redundancy), **3.1.c** (spanning-tree security/guards), **1.1.b** (high-availability techniques: FHRP/redundancy practised), plus the module-02-added **X-GLBP** (load-sharing FHRP) and **X-L2guards** . Starting from the LAB-009 solved state (H0: HQ-DIST1 is the sole gateway and sole spanning-tree root), the student turns HQ-DIST2 into an active, redundant distribution switch: both switches route VLANs 10/20/99 (R1); VLAN 20 and VLAN 99 each get a single active/standby virtual gateway, HQ-DIST2 active for VLAN 20 and HQ-DIST1 active for VLAN 99 (R2); VLAN 10 gets a load-sharing gateway forwarded by both switches at once (R3); per-VLAN spanning-tree roots are realigned to match each VLAN's active gateway (R4); the access switches' management traffic follows the virtual management gateway (R5); root guard on the distribution downlinks and loop guard on the access uplinks protect the design (R6); and the whole block is proven to survive losing either distribution switch, one interconnect member, or one access uplink (R7).

This build also produces the reusable **HQ H1 stage baseline** (`environments/HQ/H1/`), used by LAB-013, LAB-014 and later HQ stages.

No intentional faults (I lab).

## Solution Configuration

Tested in CML. Full day-0-equivalent configs (the lab has no faults, so the "solution" is simply the H1 target state applied from H0) are in `environments/HQ/H1/*.cfg`; the delta from H0 per device is:

**HQ-DIST1** — add SSH/RSA day-0, split STP priorities, add GLBP 10 / HSRP 20 / HSRP 99, add root guard on the ACC-facing ports:
```
crypto key generate rsa modulus 2048
ip ssh version 2
spanning-tree vlan 10,99 priority 24576
spanning-tree vlan 20 priority 28672
interface Ethernet0/2
 spanning-tree guard root
interface Ethernet0/3
 spanning-tree guard root
interface Vlan10
 ip address 10.10.10.2 255.255.255.0
 glbp 10 ip 10.10.10.1
 glbp 10 priority 110
 glbp 10 preempt delay minimum 30
 glbp 10 timers 1 3
interface Vlan20
 ip address 10.10.20.2 255.255.255.0
 standby version 2
 standby 20 ip 10.10.20.1
 standby 20 priority 100
 standby 20 preempt delay minimum 30
 standby 20 timers 1 3
interface Vlan99
 standby version 2
 standby 99 ip 10.10.99.1
 standby 99 priority 110
 standby 99 preempt delay minimum 30
 standby 99 timers 1 3
line vty 0 4
 transport input ssh
```

**HQ-DIST2** — add explicit `ip routing`, remove the old default route, add SSH/RSA day-0, split STP priorities, add GLBP 10 / HSRP 20 / HSRP 99, add root guard:
```
ip routing
no ip route 0.0.0.0 0.0.0.0 10.10.99.11
crypto key generate rsa modulus 2048
ip ssh version 2
spanning-tree vlan 20 priority 24576
spanning-tree vlan 10,99 priority 28672
interface Ethernet0/2
 spanning-tree guard root
interface Ethernet0/3
 spanning-tree guard root
interface Vlan10
 ip address 10.10.10.3 255.255.255.0
 no shutdown
 glbp 10 ip 10.10.10.1
 glbp 10 priority 100
 glbp 10 preempt delay minimum 30
 glbp 10 timers 1 3
interface Vlan20
 ip address 10.10.20.3 255.255.255.0
 no shutdown
 standby version 2
 standby 20 ip 10.10.20.1
 standby 20 priority 110
 standby 20 preempt delay minimum 30
 standby 20 timers 1 3
interface Vlan99
 standby version 2
 standby 99 ip 10.10.99.1
 standby 99 priority 100
 standby 99 preempt delay minimum 30
 standby 99 timers 1 3
line vty 0 4
 transport input ssh
```

**HQ-ACC1 / HQ-ACC2** — add SSH/RSA day-0, loop guard on both uplinks, move the default gateway to the virtual address:
```
crypto key generate rsa modulus 2048
ip ssh version 2
interface Ethernet0/0
 spanning-tree guard loop
interface Ethernet0/1
 spanning-tree guard loop
no ip default-gateway 10.10.99.11
ip default-gateway 10.10.99.1
line vty 0 4
 transport input ssh
```

HQ-PC1/HQ-PC2 configuration is unchanged from H0 (R1: hosts never need to change their gateway address).

## Verification

Captured ≥ 60 s after boot (preempt-delay settling window):

```
HQ-DIST1# show standby brief
Interface   Grp  Pri P State   Active          Standby         Virtual IP
Vl20        20   100 P Standby 10.10.20.3      local           10.10.20.1
Vl99        99   110 P Active  local           10.10.99.12     10.10.99.1
HQ-DIST1# show glbp brief
Interface   Grp  Fwd Pri State    Address         Active router   Standby router
Vl10        10   -   110 Active   10.10.10.1      local           10.10.10.3
Vl10        10   1   -   Active   0007.b400.0a01  local           -
Vl10        10   2   -   Listen   0007.b400.0a02  10.10.10.3      -
HQ-DIST1# show spanning-tree root
VLAN0010         24586 aabb.cc00.cf00         0    2   20  15
VLAN0020         24596 aabb.cc00.d000        56    2   20  15  Po1
VLAN0099         24675 aabb.cc00.cf00         0    2   20  15
HQ-DIST1# show etherchannel summary
1      Po1(SU)         LACP        Et0/0(P)        Et0/1(P)
```
(HQ-DIST2 shows the complementary roles: Active for Vl20, Standby for Vl99, GLBP Standby/pri100, root for VLAN0020 only.) V1/V2 PASS (`show spanning-tree inconsistentports` returns 0 entries on both).

`show interfaces trunk` on HQ-ACC1: `Et0/0` (to HQ-DIST1) forwards VLANs 10,99; `Et0/1` (to HQ-DIST2) forwards VLAN 20 — confirms R4's per-VLAN root alignment reaches the access layer. V5: `show running-config | include default-gateway` on both ACCs → `ip default-gateway 10.10.99.1`.

From HQ-PC1: `ping` reaches its own gateway, HQ-PC2, and all four switch management addresses at 0% loss (after the first, ARP-resolution packet). V3 PASS.

**How the GLBP part of R3 works.** The AVG is elected by priority (HQ-DIST1, 110; preempt with the 30 s delay returns the role after a failure). The AVG answers ARP for the single virtual IP and hands out the virtual MACs of the AVFs (`0007.b400.0a01` for HQ-DIST1, `0a02` for HQ-DIST2) in round-robin order by default, which is why V4 sees alternating addresses. Each AVF forwards for its own MAC; when a peer fails, the surviving member takes over the dead AVF's MAC (seen in the stop-switch tests below), and the AVG role moves as in those tests. Weighting (lowered by a tracked object) is the lever that moves forwarding away from a member with a failed uplink; it is not usable here because the image has no tracking.

**V4 (GLBP load sharing, P3FU T3 method):** on HQ-PC1, `sudo ip neigh flush dev eth0` (the console user `cisco` is non-root; plain `ip neigh flush` returns "Operation not permitted") then `ping -c1 10.10.10.1` then `ip neigh show dev eth0`, repeated four times: the resolved gateway hardware address alternated `0007.b400.0a02` / `0007.b400.0a01` / `0a02` / `0a01` — confirms both switches forward VLAN 10. PASS.

## Failure / Recovery Behaviour

**Stop HQ-DIST1** (configs saved on all four switches first): from HQ-PC1, `ping -c30 -i0.5` to HQ-PC2 and `ping -c10 -i0.5` to HQ-ACC2's management address both returned **0% loss** (failover completes before the first probe; well under the 10 s target). HQ-DIST2 becomes Active for Vl99 (`Standby: unknown`) and AVG for Vl10 (owns both GLBP forwarders); becomes root for all three VLANs. Restarting HQ-DIST1: after ~45 s it reclaimed Vl99 Active and the Vl10 AVG role, and STP roots returned to the table above. **R2/R7 PASS** for this direction.

**Stop HQ-DIST2**: from HQ-PC2, `ping -c30 -i0.5` to HQ-PC1 lost 2/30 (6%, ARP-timing, not FHRP-timing) and `ping -c10 -i0.5` to HQ-ACC1's management address lost 2/10 — both well inside 10 s. HQ-DIST1 becomes Active for Vl20 and Vl99, AVG for Vl10, and root for all three VLANs. Restarting HQ-DIST2: after ~50 s it reclaimed Vl20 Active and Vl10 GLBP standby, Po1 fully re-bundled. **R2/R7 PASS**.

**One interconnect member lost — platform-specific test method.** `shutdown` on only **one** switch's Po1 member (e.g. only HQ-DIST1 Et0/0) is **not** a valid test on this platform: the peer (HQ-DIST2) keeps that member in the bundle until the LACP long timeout (~70–90 s), and IOS's per-flow port-channel hash pinned the whole PC1→PC2 ICMP flow onto the dead member for the entire test window, producing **100% loss**, not "a few pings". Shutting down the **same member on both switches** (`interface Ethernet0/0` / `shutdown` on HQ-DIST1 **and** HQ-DIST2, simulating an actual cable pull) reconverges immediately: 1/20 pings lost (5%). **R7 PASS with this corrected method**; `no shutdown` on both restores `Po1(SU)` with both members `(P)`. SOLUTION note for future labs testing this on H1: always shut both ends of the same member.

**One access uplink lost** ("Stop link" in the CML UI on the HQ-DIST1↔HQ-ACC1 link, both ends — a link stop is the right tool here since it does not bring the IOL interface administratively down, matching a silent/dead-timer failure): HQ-PC1's ping to its gateway stayed at 0% loss throughout; the resolved gateway hardware address did not change. `show interfaces trunk` on HQ-ACC1 showed `Et0/0` no longer forwarding anything and `Et0/1` forwarding all three VLANs — spanning tree reconverged onto the surviving uplink via BPDU aging, with **no gateway change**, confirming R6. Restoring the link reconverged back to the baseline (Et0/0 10,99 / Et0/1 20) within one polling interval. **R7 PASS**.

## Answers to Analysis Questions

**Q1.** HQ-ACC2's uplink to HQ-DIST2 is the one forwarding VLAN 20 (HQ-DIST2 is root for VLAN 20), so every VLAN 20 frame from HQ-PC2 reaches HQ-DIST2 first, whichever switch is the active gateway.

- *PC2 to PC1:* one Po1 crossing in **both** designs. In the actual design HQ-DIST2 (root and active gateway for VLAN 20) routes the frame onto VLAN 10, but HQ-ACC1's only forwarding uplink for VLAN 10 is the one to HQ-DIST1 (VLAN 10's root), so HQ-DIST2 hands the routed frame to HQ-DIST1 across Po1. In the hypothetical design HQ-DIST2 bridges the frame across Po1 to HQ-DIST1 (which now holds the virtual MAC), and HQ-DIST1 routes it and forwards straight to HQ-ACC1. This pair therefore cannot show the cost of misalignment (measured by trace of the root/forwarding state above).
- *PC2 to its own gateway 10.10.20.1:* **(derived)** zero Po1 crossings in the actual design (the root and the active gateway are the same switch), one in the hypothetical design (HQ-DIST2 must bridge every gateway-bound frame across Po1 to HQ-DIST1). That is the penalty of misalignment: every frame the VLAN's hosts send to their gateway takes an extra interconnect hop.

On real hardware this matters more because the interconnect is typically the block's narrowest and most contended link, and every misaligned flow adds load to it and a hop of latency; in this simulator all links behave alike, so a wasted hop shows only as a design smell (**(derived)**).

**Q2.** HQ-ACC1's uplink to HQ-DIST1 is the one forwarding VLAN 10 (HQ-DIST1 is root for VLAN 10), so every VLAN-10 frame from HQ-PC1 — including one destined for HQ-DIST2's GLBP forwarder — physically reaches HQ-DIST1 first and then crosses the interconnect (Po1) to reach HQ-DIST2 for that specific packet. Load sharing is still worth having even though the topology is already fully redundant and looped: it uses both distribution switches' forwarding and CPU capacity under normal conditions instead of leaving one idle, and it halves the number of hosts whose traffic is disrupted by any single forwarder's momentary hiccup. The path-efficiency point from Q1 (co-locate gateway and root) and the capacity-sharing point here are separate arguments, and GLBP's per-host load split does not by itself fix the extra Po1 hop for whichever forwarder isn't co-located with the root.

**Q3.** Order used: (1) configure HQ-DIST2's VLAN 99 SVI and virtual gateway first (priority 100). Alone in the group it becomes **Active**, while the ACCs still point at HQ-DIST1's physical `.11`, so nothing changes for them. (2) Configure the virtual gateway on HQ-DIST1 (priority 110, `preempt delay minimum 30`). HQ-DIST2 is already Active, and an Active router keeps its role (the LAB-011 lesson), so HQ-DIST1 does **not** become Active immediately: it takes the role only through preempt, after the 30 s delay (configuring HQ-DIST1 first would instead make it Active from the start). (3) Repoint the ACCs' `ip default-gateway` from `.11` to the virtual `.1`. The virtual address answers on whichever switch is Active from step 1 onward, so the ACCs lose their gateway only for one ARP resolution of `.1` (a couple of lost pings at most), and the later HSRP hand-over to HQ-DIST1 is invisible to them because the virtual MAC does not change. The gap could be removed by pre-populating the ACCs' ARP entry for `.1` with a static `arp` entry, which works only because the HSRPv2 virtual MAC is predictable from the group number **(derived, not tested here)**.

**Q4.** Root guard belongs on the distribution switches' downlinks because an access switch should never win a root election, so any superior BPDU arriving there is wrong and the port is blocked. Loop guard belongs on the access switches' uplinks because those are root or alternate ports where the real risk is a unidirectional failure that stops BPDUs without taking the link down: loop guard keeps such a port blocking instead of letting it become designated and forwarding. Swapped, root guard on an uplink would block the legitimate superior BPDU from the real root, and loop guard on a downlink with no upstream neighbour would do nothing useful.

Total interconnect failure (measured on CML, see LAB-013 SOLUTION (e)): the non-root distribution switch's downlinks go root-inconsistent (blocking) for the VLANs it does not root. It still hears the real root, but only indirectly: with Po1 down, each access switch keeps a path to the real root through its other uplink and becomes designated toward the cut-off distribution switch, relaying the root's superior BPDU over that link, and root guard blocks the port precisely because a superior BPDU arrives from an access switch. Measured: with Po1 shut on both ends, HQ-ACC2's uplink to HQ-DIST1 went from alternate to designated/forwarding and its `show spanning-tree vlan 20 detail` named HQ-DIST2's bridge ID (24596) as the designated root, while HQ-DIST1's e0/2 and e0/3 showed `broken (Root Inconsistent)`. The mirror direction held for VLANs 10 and 99. The design consequence: root guard turns an interconnect loss into a partition of the VLANs each switch does not root, rather than letting traffic detour through an access switch.

**Q5.** On ioll2-xe there is no interface/route tracking feature, so the redundancy protocols can only react to their own peer-to-peer hellos, not to the state of another interface. That is a limit of this simulator image: on real Catalyst distribution switches HSRP (`standby ... track`) and GLBP (weighting with a track object) can tie a priority or weight to an uplink or route (**(derived)**, not measurable on this bench). In this curriculum the uplink protection moves to the routed core (HQ-CORE1/2, added in module 03's H2 stage), which runs VRRPv3 on iol-xe, and that image supports tracking. H2 leaves the VRRP group untracked; tracking is added later in MS-4 (CR1).

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-17 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), ioll2-xe (IOS XE 17.16.1a) |
