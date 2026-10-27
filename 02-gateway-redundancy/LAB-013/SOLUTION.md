# LAB-013 — Solution

## Summary

Analysis lab (A · G2 · 90 min) for blueprint **1.1.b** (analyse: SSO/NSF/FHRP high-availability techniques) and **1.1.a** (partial: two-tier vs three-tier triggers, what a third tier would take over). The student does not change any configuration; HQ H1 (`environments/HQ/H1/`, built in LAB-012) is used exactly as-is. The lab has the student build a per-layer redundancy inventory (R1), measure the real outage caused by six failure scenarios from both end hosts (R2), fully explain the compound failure of losing the whole distribution interconnect (R3), use vendor reference material to reason about chassis/stack redundancy this CML platform cannot demonstrate (R4), and make an evidence-based recommendation for the upcoming three-tier project (R5).

No intentional faults (A lab; starting state is the unmodified H1 baseline).

## Solution Configuration

No configuration changes: this is an A-type analysis lab and HQ H1 is used unmodified throughout (see "No intentional faults" above). What follows is the measurement method used for R2, in place of a solution config.

All six R2 scenarios were reproduced against the unmodified H1 baseline, then fully restored (wipe + reload from the H1 stage configs) and re-verified. Outage was measured as ICMP loss from HQ-PC1 / HQ-PC2 (Alpine `ping`), issued immediately after the fault was injected so early losses are captured.

**(a) ACC1 uplink cable pull** — `shutdown` on **both ends** of the HQ-ACC1–HQ-DIST1 link (the module convention, LAB.md's told method: a real cable pull is `shutdown` on both ends, per LAB-011 LAB.md:47).
**(a2) ACC1 uplink silent failure** — "Stop link" in the CML UI on the same HQ-ACC1–HQ-DIST1 link (the correct tool for a *silent* failure per H1 README note 7 — a CML link stop does not bring the IOL interface down, unlike a real cable pull). (a) and (a2) are two different failure modes with two different detection paths.
**(b) / (c) Stopped distribution switch** — `copy running-config startup-config` on the target switch first (a stopped node reloads from its saved config, not its running config), then stop the node, then ping immediately.
**(d) One interconnect member lost** — `shutdown` on Ethernet0/0 on **both** HQ-DIST1 and HQ-DIST2 (H1 README note 6: shutting only one end is not a valid single-link-failure test on this platform — the peer keeps the member bundled for the LACP long timeout and can pin a whole flow onto the dead member).
**(e) Both interconnect members lost** — `shutdown` on Ethernet0/0 **and** Ethernet0/1 on both switches.

Each scenario was reversed (`no shutdown` / "Start link" in the CML UI / start the node in the CML UI) and the H1 baseline role settling window (~60 s, per H1 README note 3) was allowed to elapse before moving to the next scenario.

## Verification

**Baseline (both switches, before any test), confirming the exact H1 target roles:**
```
HQ-DIST1# show standby brief
Vl20   20  100 P Standby 10.10.20.3   local          10.10.20.1
Vl99   99  110 P Active  local        10.10.99.12    10.10.99.1
HQ-DIST1# show glbp brief
Vl10   10  -   110 Active   10.10.10.1  local  10.10.10.3
HQ-DIST1# show spanning-tree root
VLAN0010  24586 ...   0   ...   (no root port — DIST1 is root)
VLAN0020  24596 ...  56   ...  Po1
VLAN0099  24675 ...   0   ...   (no root port — DIST1 is root)
HQ-DIST1# show etherchannel summary | include Po1
1  Po1(SU)  LACP  Et0/0(P)  Et0/1(P)
```
(HQ-DIST2 shows the mirror image: active/root for VLAN20, standby elsewhere.) PC1 reached 10.10.10.1 / 10.10.99.11 / 10.10.99.12 at 0% loss; PC2 reached 10.10.20.1 at 0% loss.

**(a) ACC1 uplink cable pull (`shutdown` both ends, measured):**
- Baseline: HQ-ACC1 Et0/0 (to HQ-DIST1) `Root FWD`; Et0/1 (to HQ-DIST2) `Altn BLK`.
- HQ-ACC1 Et0/0 and HQ-DIST1 e0/2 shut (both ends): Et0/1 transitioned directly `Altn BLK` → `Root FWD` — an immediate RSTP alternate-to-root port move, **no loop-guard event** (the port never lost BPDUs while physically up; it went link-down instead).
- PC1 → 10.10.99.12, `ping -c 30`: **1 packet lost (~3%, ~1 s)** — a single ping interval, not a multi-second outage; the already-alternate port's transition to forwarding is close to instantaneous under Rapid PVST+.
- Restored (`no shutdown` both ends): HQ-ACC1 back to Et0/0 `Root FWD` / Et0/1 `Altn BLK` exactly.

**(a2) ACC1 uplink silent failure ("Stop link" in the CML UI, measured earlier build):**
- HQ-ACC1: Et0/0 (to HQ-DIST1) went `Root BKN *LOOP_Inc` (loop guard fired on loss of BPDUs while the port stayed physically up); Et0/1 (to HQ-DIST2) became `Root FWD`.
- PC1 → 10.10.99.12 continuous ping: **about 3-6 s outage (measured range: 4 to 6 pings lost with loop guard, 3 to 4 without it)**, then 44 more with 0% loss.
- Why the port shows `*LOOP_Inc`: loop guard keeps a port that stopped receiving BPDUs blocked (loop-inconsistent) instead of letting it age out into designated/forwarding. It is not what moved the traffic to the other uplink (see the explanation below).
- Restored ("Start link" in the CML UI): Et0/0 back to `Root FWD`, Et0/1 back to `Altn BLK` within 10 s. Gateway addresses never changed (H1 README note 7).
- **(a) vs (a2), why the difference:** a real link-down (a) gives RSTP an immediate trigger to move the already-standing alternate port straight to forwarding — sub-second. A silent failure (a2) leaves the port physically up with no link-down event at all. The failover comes from **BPDU aging**: the root port's stored BPDU information expires after 3 × hello (up to about 6 s at the default 2 s hello; 3–6 s measured, with and without loop guard, depending on where in the BPDU interval the failure lands), after which RSTP promotes the alternate port to root and forwarding. Loop guard does not speed this up and the outage would be the same without it; its job is to stop the old root port from becoming designated and forwarding (it shows `*LOOP_Inc`), which is what prevents a loop if the failure were unidirectional. A student who tests only one of these and calls it "the" cable-pull result will draw the wrong general conclusion about how fast this design fails over.

**(b) Stopped HQ-DIST1** (saved config first): HQ-DIST2 became GLBP AVG for both forwarders (local/Active) and HSRP active for Vlan99 (was Standby).
- PC1→PC2 and PC2→PC1 continuous ping: **5 packets lost each direction (~5 s)** — well under the 10 s target.
- Restored (start the node in the CML UI): Po1 rebundled on first boot; HQ-DIST1 reclaimed GLBP AVG (Vlan10) and HSRP active (Vlan99) after ~85 s total (24 s after the `Speak→Standby` log line, consistent with the 30 s preempt delay plus negotiation).

**(c) Stopped HQ-DIST2** (saved config first): HQ-DIST1 took over HSRP active for Vlan20 (was Standby) and both GLBP forwarders went local/Active on HQ-DIST1; VLAN20's spanning-tree root also moved to HQ-DIST1 (secondary priority 28692).
- PC2 → 10.10.20.1: **13% loss over 15 pings (2 packets, ~2 s outage)**, then 0% loss.
- PC1 → PC2 (10.10.20.102), run concurrently: **0% loss** — VLAN10 and the inter-VLAN routing path from HQ-DIST1 were never affected, since HQ-DIST1 was already the GLBP AVG's peer and had its own connected VLAN20 SVI throughout.
- Restored (start the node in the CML UI): HQ-DIST2 reclaimed its roles within the preempt-delay window; full baseline confirmed afterward.

**(d) One interconnect member lost** (Et0/0 shut on both switches — the same member, both ends):
- `show etherchannel summary` on both switches: `Po1(SU) LACP Et0/0(D) Et0/1(P)` — bundle stayed up on the remaining member.
- PC1 → PC2 (10.10.20.102): **0% loss over 15 pings.** The surviving Po1 member carried the flow (PC1↔PC2 does cross Po1, see LAB-012 Q1); with the same member shut on both ends, LACP removed it immediately and rehashed the flow onto the other member.
- Restored (`no shutdown` both ends): Po1 back to `Et0/0(P) Et0/1(P)`.

**(e) Both interconnect members lost** (Et0/0 **and** Et0/1 shut on both switches):
- `show spanning-tree inconsistentports`: HQ-DIST1 — `Ethernet0/2` and `Ethernet0/3` **Root Inconsistent for VLAN0020** (2 ports); HQ-DIST2 — `Ethernet0/2` and `Ethernet0/3` **Root Inconsistent for VLAN0010 and VLAN0099** (4 ports). Root guard fired on exactly the downlinks whose VLAN root is the *other* switch — matching the design: HQ-DIST1 is root for VLAN10/99 so HQ-DIST2's downlinks for those VLANs are blocked, and HQ-DIST2 is root for VLAN20 so HQ-DIST1's downlinks for that VLAN are blocked. **Mechanism (measured):** each blocked distribution switch does *not* lose contact with the real root — with Po1 down, the access switch on that downlink still reaches the real root through its other uplink, becomes designated toward the cut-off distribution switch, and relays the real root's superior BPDU to it; root guard blocks the port because that superior BPDU arrives, not because the switch can no longer hear the root. Confirmed: HQ-ACC2's uplink to HQ-DIST1 flipped alternate→designated and reported the designated root as HQ-DIST2's own bridge ID (24596; the bridge MAC differs on every import, e.g. aabb.cc01.1900 on one import and aabb.cc00.1600 on another, so compare against your own `show spanning-tree` output); HQ-DIST1's e0/2/e0/3 showed `broken (Root Inconsistent)` with root guard enabled on receipt of it. The mirror direction (HQ-ACC1 relaying HQ-DIST1's root ID to HQ-DIST2) confirmed the same for VLANs 10/99.
- Both switches then show themselves **Active/local** for every one of their own groups (`show standby brief` / `show glbp brief`) — each lost its only path to the peer and to the access layer for the VLANs it does not root, so each began claiming ownership of groups it can no longer verify against the other switch. Neither switch can reach any host through a VLAN it is isolated from (its SVI stays up but has no forwarding path to any access port for that VLAN).
- Measured host impact:
  - PC1 → PC2 (10.10.20.102): **100% loss (5/5)** — cross-VLAN traffic fails completely.
  - PC2 → PC1 (10.10.10.101): **100% loss (5/5)** — same failure, opposite direction.
  - PC1 → HQ-DIST2 mgmt (10.10.99.12): **100% loss (5/5)** — HQ-DIST2's management address is unreachable from the rest of the network (its downlinks for VLAN99 are root-inconsistent).
  - PC2 → its own gateway 10.10.20.1: **0% loss (5/5)** — HQ-DIST2 is still root and active for VLAN20 and needs no path across the (dead) interconnect to serve its own directly-connected access switch.
- This confirms the predicted mechanism exactly: each host keeps a working *virtual* gateway address (whichever switch already owns that VLAN's root/active role keeps serving it locally), but PC1↔PC2 traffic and HQ-DIST2's management reachability both depend on the interconnect and fail completely.
- Restored: `no shutdown` on both members, both ends; full re-verification (wipe + reload from `environments/HQ/H1/*.cfg`, fresh boot) confirmed `show spanning-tree inconsistentports` empty on both switches, Po1 `Et0/0(P) Et0/1(P)`, and every role back to the H1 baseline table.

## Expected Answers to Requirements R1–R5

This is an A lab: R1–R5 (not just the Analysis Questions) are the graded deliverable, so a model answer for each is recorded here.

**R1 (redundancy table, model answer using the measured values above):**

| Layer | Redundancy? | Failure detection on this platform | Measured user impact |
|---|---|---|---|
| Host NIC / cable | None | N/A | A host's own NIC or cable failing has no protection anywhere in this design; the host is offline |
| Access switch (HQ-ACC1/2) | None (single access switch per floor) | N/A | An access switch failing takes its whole floor offline; no redundant access switch exists per floor |
| Access uplinks (ACC↔DIST) | Yes — dual uplinks, RSTP | Link-down (real cable pull) → immediate RSTP alternate-to-root move; a silent failure (link stays up) → BPDU aging (3 × hello, ~6 s) promotes the alternate; loop guard keeps the silent port from forwarding | (a) ~1 s / ~3% (real link-down); (a2) ~3-6 s (silent failure) |
| Distribution switches (HQ-DIST1/2) | Yes — active/standby or active/active FHRP per VLAN | FHRP hello/hold timers (1 s/3 s); a stopped node's link stays up, so failover is timer-driven, not link-down-driven | (b) ~5 s; (c) ~2 s — both well under the 10 s target |
| Distribution interconnect (Po1) | Partial — 2-member LACP bundle, but no IGP behind it | A single member loss: LACP still up on the survivor; total loss: root guard root-inconsistents each switch's non-root downlinks | (d) 0% loss (one member, both ends); (e) 100% loss for PC1↔PC2 and HQ-DIST2 mgmt — see R3 |
| Gateway protocols themselves (GLBP/HSRP) | Yes, by design | Peer hello/hold timers | Confirmed working correctly throughout (b)/(c); not a failure point on their own |

**R2:** see "Verification" above for all six measurements (a, a2, b, c, d, e) with method and numbers.

**R3 (expected answer for scenario (e)):** with both Po1 members gone, there is no direct link between the distribution switches, so an IGP between them would have no link to run on; the only remaining Layer 2 path between them runs through the access switches, and root guard blocks exactly that path for the VLANs each switch does not root (the access switch relays the real root's superior BPDU, see the (e) record). Without root guard, **(derived)** the VLAN traffic would detour through an access switch (suboptimal but working); with it, each distribution switch is cut off from the VLANs it does not root, and there is no alternative Layer 3 path (no core uplinks) to take over. PC1↔PC2 (cross-VLAN traffic) fails completely because the routing switch each host's frame reaches (via its own VLAN's root/gateway switch) has no Layer 2 path left to the *other* VLAN's access switch once root guard root-inconsistents the downlinks it doesn't root. HQ-DIST2's management address (10.10.99.12) fails for the same reason: it lives on a VLAN (99) that HQ-DIST1 roots, so HQ-DIST1's downlinks stay up, but reaching HQ-DIST2's own directly-connected address still requires crossing Po1, which is gone. Each host's *own* gateway stays reachable because the switch that already roots that host's VLAN never depended on the interconnect to serve it locally. Yes, the interconnect is a single point of failure — specifically for all cross-VLAN (inter-VLAN-routed) traffic and for HQ-DIST2's management reachability, not for same-VLAN host-to-gateway traffic. The design trade-off: root guard turns an interconnect loss into a partition, and the remedies are a third path (core uplinks with an IGP), a routed interconnect plus a core, or StackWise Virtual.

**R4 (expected answer):** SSO by itself checkpoints Layer 2 forwarding and hardware state (CEF, MAC/ARP tables) across a supervisor switchover, so a switch that has SSO alone keeps forwarding already-established flows through the switchover; it does **not** checkpoint routing-protocol state — an OSPF adjacency (or any control-plane session) still drops and has to rebuild from scratch. Graceful restart / NSF, layered on top of SSO, is what lets a neighbouring router keep forwarding to the restarting router through the switchover, by holding routes for it during a grace period instead of tearing the adjacency down. Neither R2(b) nor R2(c) would have been shortened or eliminated by dual supervisors: both scenarios stopped the **whole node** (stopping the node in the CML UI), which is a chassis-loss event, not a supervisor failure — SSO/NSF protect against losing one of *two* supervisors *inside* a chassis that otherwise keeps running; they do nothing when the entire chassis goes away, which is exactly what R2(b)/(c) modelled. A StackWise Virtual distribution pair would **not** need an FHRP (HSRP/GLBP) between its members: SVL presents one logical switch with one control/management/data plane, so each VLAN has a single SVI and one gateway IP, and there is nothing to coordinate or fail over between two gateways. Redundancy comes from the SVL itself (the surviving chassis keeps forwarding and owns the gateway) and from multichassis EtherChannel (MEC) uplinks that span both members. An FHRP matters again only where two separate (non-SVL) gateways exist, as in this HQ H1 design.

**R5 (expected answer):** acceptable recommendations include adding a core layer, making the distribution interconnect a routed link, or moving to StackWise Virtual — any of these removes the single-point-of-failure evidence gathered above. The strongest evidence from this lab: (1) R3/scenario (e) proved the interconnect is a SPOF for all cross-VLAN traffic and for HQ-DIST2's management address, because root guard blocks the only remaining Layer 2 path through the access layer and there is no alternative Layer 3 path; (2) R4 established that no amount of chassis-level redundancy (dual supervisors, SVL) removes the need for a routed path between the distribution switches once a third tier exists. A concrete trigger for Veridian: the day HQ adds a second building, a WAN/edge attachment point, or any requirement that inter-VLAN traffic keep flowing during a single distribution-switch or interconnect failure (not just single-VLAN gateway failover, which H1 already handles) — at that point a routed core (with OSPF between distribution and core) becomes necessary rather than merely nice to have, because H1 has no second path (Layer 3 or otherwise) between the distribution switches that survives a dead interconnect.

## Failure / Recovery Behaviour

All six scenarios recovered fully and automatically once the fault was reversed and the ~60 s settling window elapsed (30 s preempt delay + negotiation). No scenario required manual intervention beyond reversing the injected condition. Scenario (e) is the only one that produces a *compound* failure the student must reason through rather than a single-mechanism failover; scenarios (a)/(a2)–(d) are each a single redundancy mechanism doing its job within a few seconds.

Outage summary (all times to the nearest measured second):

| Scenario | Outage measured | Target |
|---|---|---|
| (a) ACC uplink cable pull (`shutdown` both ends) | ~1 s (1/30 lost; immediate RSTP alternate→forwarding, no loop-guard event) | n/a — no gateway change, informational |
| (a2) ACC uplink silent failure ("Stop link" in the CML UI) | ~3-6 s (BPDU aging, 3 × hello, then the alternate port is promoted; loop guard only holds the silent port blocked) | n/a — no gateway change, informational |
| (b) Stopped HQ-DIST1 | ~5 s each direction | ≤ 10 s — met |
| (c) Stopped HQ-DIST2 | ~2 s | ≤ 10 s — met |
| (d) One Po1 member lost (both ends) | 0% loss | "a few lost pings" — better than target |
| (e) Both Po1 members lost | 100% loss, PC1↔PC2 and HQ-DIST2 mgmt; PC2's own gateway unaffected | not recoverable by this design — confirms interconnect is a SPOF for cross-VLAN and HQ-DIST2 mgmt traffic |

## Answers to Analysis Questions

**Q1.** The timer-driven outages — (b) and (c) (FHRP hello 1 s / hold 3 s), and (a2) (BPDU aging, 3 × hello) — are set by configured or standard protocol timers, so they would be about the same on real hardware (**(derived)**). A real chassis loss would also bring the neighbours' links down, which can speed up the spanning-tree part; only ARP/forwarding jitter and first-ping ARP loss are specific to the simulator. (a) is a genuine link-down test (`shutdown` both ends): its ~1 s outage is already close to what real hardware achieves, because RSTP's alternate-to-root transition on a link-down event is fast on any platform. The two scenarios (a) and (a2) exist to show that link-down and silent failure on the *same* physical link are detected by different mechanisms at very different speeds, not that this platform's timers are "slow".

**Q2.** About the same: VLAN10 (GLBP) and VLAN20/VLAN99 (HSRP) recovered from a distribution-switch failure in similar measured times (2–6 s), as expected because both use the same hello/hold timers (1 s / 3 s) and neither is tracked. The (b)/(c) measurements mix both protocols in one flow (for example PC1→PC2 crosses VLAN 10 and VLAN 20), so they do not separate GLBP from HSRP; measuring a ping to the VLAN 10 gateway and a ping to the VLAN 20 gateway separately would. The difference between the two lies in how recovery happens (GLBP's survivor takes over both forwarder roles locally; HSRP's standby becomes active), not in how long it takes when the timers match.

**Q3.** Without SSO, a supervisor failure looks to OSPF neighbours like the router disappearing entirely: the dead-interval (default 40 s) has to expire before neighbours declare it down and reconverge, and even after it comes back the adjacency has to be rebuilt from scratch (full LSA exchange). With SSO alone (no NSF/graceful restart), neighbours would still see this — SSO checkpoints Layer 2 forwarding and the supervisor failover itself, but not OSPF's protocol state, so the adjacency still drops and the dead-interval still has to elapse. Only graceful restart, running on top of SSO, lets neighbours keep forwarding to the restarting router through the switchover. This becomes far more important once HQ has a routed core: today's design has no dynamic routing at all between the distribution switches (every subnet is simply connected on both), so there is no protocol adjacency to lose — a routed core would introduce exactly the OSPF dependency described in the reference material.

**Q4.** Ranked by how many users/how much of the network each affects: (1) the distribution interconnect (Po1) — losing it entirely breaks all cross-VLAN traffic and HQ-DIST2's management reachability, affecting every user who needs to reach the other VLAN or the NOC needing HQ-DIST2; (2) either single distribution switch's software/control-plane failing without triggering a clean stop (e.g., a hung process) — the redundancy protocols assume a clean stop/reload behaviour; (3) an access switch itself — a single point of failure for its own floor only (no redundant access switch per floor in this design); (4) a single Po1 member — not a SPOF, proven by (d); (5) an access uplink — not a SPOF, proven by (a).

**Q5.** The core layer will most likely take over: inter-VLAN routing itself (today done redundantly but statically on the distribution pair with no dynamic routing protocol), the routed uplink to the rest of Veridian's network, and likely the "coordinator" role for anything that needs a single point for policy (ACLs, QoS boundaries) between campus and the core/WAN. The distribution pair will keep: first-hop gateway redundancy for the access-facing VLANs (the mechanisms measured in this lab), spanning-tree root placement for those VLANs, and direct access-switch aggregation — none of that moves to a core layer in a standard three-tier design.

## Reference Material Sources

Sources for LAB.md's "Reference material — chassis and stack redundancy `(derived)`" section (the three illustrative outputs this CML platform cannot produce):

**(a) Catalyst 9400 SSO / `show redundancy states`:** *High Availability Configuration Guide, Cisco IOS XE Amsterdam 17.3.x (Catalyst 9400 Series Switches)* — "Configuring Nonstop Forwarding with Stateful Switchover" — https://www.cisco.com/c/en/us/td/docs/switches/lan/catalyst9400/software/release/17-3/configuration_guide/ha/b_173_ha_9400_cg/nonstop_forwarding_with_stateful_switchover.html . Confirms the `show redundancy states` field layout (`my state`, `peer state`, `Mode`, `Unit`, `Redundancy Mode (Operational)` / `(Configured)`) used in LAB.md's example, and states directly: "If the active device fails, the standby device becomes the active device. This new active device uses existing Layer 2 switching information to continue forwarding traffic. Layer 3 forwarding is delayed until routing tables are repopulated in the newly active device" (~80 s) — i.e. SSO alone does not checkpoint routing-protocol state, exactly LAB.md's claim.

**(b) OSPF NSF / graceful restart:** *IP Routing: OSPF Configuration Guide, Cisco IOS Release 15M&T* — "OSPF RFC 3623 Graceful Restart Helper Mode" — https://www.cisco.com/c/en/us/td/docs/ios-xml/ios/iproute_ospf/configuration/15-mt/iro-15-mt-book/iro-restart.html ; default grace-period value confirmed in *IP Routing: OSPF Command Reference* — `nsf ietf` command — https://www.cisco.com/c/en/us/td/docs/ios-xml/ios/iproute_ospf/command/iro-cr-book/ospf-i1.html ("restart-interval seconds ... The default is 120"). Together these confirm the RFC 3623 Restarting Mode / Helper Mode terminology, the 120 s default grace period, and that a helper neighbour continues forwarding to (and does not tear down its adjacency with) the restarting router while the grace period runs, provided the link-state database hasn't changed. **Caveat:** neither document uses the term "LLS-based" for this mechanism — RFC 3623 graceful restart is Grace-LSA based; Link-Local Signalling (LLS, RFC 5613) is a related but distinct OSPF extension used for out-of-band resynchronization. LAB.md's block (b) reflects this: no ADJCHG message is logged, and IETF graceful restart (`nsf ietf`) is distinguished from Cisco NSF (`nsf cisco`, LLS/OOB resync).

**(c) StackWise Virtual:** *High Availability Configuration Guide, Cisco IOS XE 17.16.x (Catalyst 9400 Series Switches)* — "Configuring Cisco StackWise Virtual" — https://www.cisco.com/c/en/us/td/docs/switches/lan/catalyst9400/software/release/17-16/configuration_guide/ha/b_1716_ha_9400_cg/configuring_cisco_stackwise_virtual.html . Confirms the core claim used in LAB.md: "the control plane, management plane, and data plane are integrated, the system behaves as a single switch" and may "look like a single logical entity to peer switches" — supporting the statement that the pair is "indistinguishable from one switch" to a connected access switch or host. LAB.md block (c) shows only `show stackwise-virtual`, the guide's documented verification command.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-17 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), ioll2-xe (IOS XE 17.16.1a) |
