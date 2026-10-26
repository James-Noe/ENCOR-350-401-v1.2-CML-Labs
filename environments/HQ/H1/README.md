# HQ H1 stage baseline

Built and proven in CML by LAB-012.

**Profile:** same 6 nodes as H0 ("full without CORE1/2"): HQ-DIST1, HQ-DIST2, HQ-ACC1, HQ-ACC2, HQ-PC1, HQ-PC2. ACC3/PC3 still absent (added in a later stage).

## Topology

Unchanged from H0 (`environments/HQ/H0/README.md` "Topology"): same cabling, same Po1 (e0/0+e0/1 LACP, nonegotiate trunk).

## Content

- Both HQ-DIST1 and HQ-DIST2 route (`ip routing` explicit on both); VLAN10/20/99 SVIs on both switches: DIST1 `.2`/DIST2 `.3` for VLANs 10 and 20, `.11`/`.12` for VLAN 99 (unchanged from H0). No IGP: every HQ subnet is connected on both DISTs. H0's DIST2 static default route to `.11` is removed.
- First-hop redundancy (untracked — no `track` on ioll2-xe):
  - VLAN 10 USERS: GLBP group 10, VIP `10.10.10.1`, DIST1 AVG (priority 110), DIST2 AVF (priority 100), round-robin load sharing between both switches' forwarders.
  - VLAN 20 OPS: HSRPv2 group 20, VIP `10.10.20.1`, DIST2 active (priority 110), DIST1 standby (priority 100).
  - VLAN 99 MGMT: HSRPv2 group 99, VIP `10.10.99.1`, DIST1 active (priority 110), DIST2 standby (priority 100). HQ-ACC1/ACC2 `ip default-gateway` moved from DIST1's physical `.11` (H0) to the virtual `.1`.
  - All groups: hello 1 s / hold 3 s, `preempt delay minimum 30` on both switches.
  - Hosts keep their H0 gateway addresses (`10.10.10.1`, `10.10.20.1`) unchanged — only the owner became virtual.
- Per-VLAN spanning-tree roots aligned with the active gateway (priority **24576** root / **28672** secondary, never 4096): DIST1 root for VLANs 10 and 99, DIST2 root for VLAN 20 (H0 had DIST1 root for all three).
- Guards (new at H1): `spanning-tree guard root` on HQ-DIST1/DIST2 e0/2 and e0/3 (the ACC-facing downlinks); `spanning-tree guard loop` on HQ-ACC1/ACC2 e0/0 and e0/1 (the DIST-facing uplinks). PortFast + BPDU guard on host ports unchanged from H0. No UDLD, no errdisable recovery.
- Management plane: `crypto key generate rsa modulus 2048` + `ip ssh version 2` in day-0 on all four switches; VTY `login local` + `transport input ssh` (SSH-only, no Telnet), from H1 onward.

## Build notes (from LAB-012)

1. All H0 build notes still apply (Port-channel-before-members day-0 order; `no ip routing` before `ip default-gateway` on the ACCs; a node stop/start reloads only the startup-config).
2. **Day-0 `crypto key generate rsa modulus 2048` works on ioll2-xe.** Unlike a plain exec-only command, IOS accepts it directly in the startup-config file: a freshly booted or freshly re-imported switch has RSA keys and SSH v2 enabled with no manual step. `show ip ssh` confirms "SSH Enabled - version 2.0" immediately after boot. `transport input ssh` (no telnet) works from day-0 with no fallback needed.
3. **Preempt-delay settling time.** With `preempt delay minimum 30` on both switches, the FHRP roles in the table above are only guaranteed **after about 60 seconds from a cold boot** (two GLBP/HSRP negotiation rounds plus the 30 s preempt delay itself). Read gateway/root roles only after that settling window; reading them immediately after BOOTED can show a switch still in Speak/Listen state or an interim owner before preemption completes.
4. **GLBP load sharing confirmed** (P3FU T3 method): flushing a host's ARP entry (`sudo ip neigh flush dev eth0` — the CML console user is non-root `cisco`; plain `ip neigh flush` fails with "Operation not permitted") and re-pinging the gateway repeatedly returns alternating forwarder vMACs (`0007.b400.0a01` / `0007.b400.0a02`), confirming both DISTs forward VLAN 10 traffic.
5. **Distribution switch failover (LAB-012 R2/R7).** Stopping either DIST costs a measured 0–6% (0–2 packets, well under the 10 s target) at LAB-012's ping rate, and about 2–5 s at LAB-013's per-second rate, to the surviving hosts and switch management addresses; the survivor becomes root and active/AVG for every VLAN the stopped switch owned. Restarting the stopped switch reclaims its roles 45–85 s after the switch is back at the CLI (30 s preempt delay plus negotiation). A stopped switch's link to a still-running peer stays up/up (IOL does not signal carrier loss); failover is by protocol timers, not link-down.
6. **Po1-member-loss test must shut down BOTH ends.** `shutdown` on only one switch's Po1 member interface is **not** a valid single-link-failure test on this platform: the peer keeps that member bundled (LACP long timeout, ~70–90 s) and IOS's per-flow port-channel hash can pin a whole conversation onto the now-dead member, producing 100% loss for that flow until the timeout — not "a few lost pings". Shutting down the **same member on both switches** (simulating a real cable pull) reconverges immediately with only a few lost pings, as the design intends. Any lab or SOLUTION.md testing "lose one Po1 member" on H1 must shut both ends.
7. **ACC uplink silent failure** (`stop_cml_link`, both ends — a link stop does not bring the IOL interface down, so it is the right tool for this *silent* failure, distinct from a real cable pull which is `shutdown` on both ends, note 6): the access switch's spanning tree reconverges onto its surviving uplink (loop-guard BPDU-absence detection, measured about 4-6 s) with **no gateway address change** — traffic reaches the far distribution switch via the interconnect. Confirms guard placement does not block legitimate reconvergence. A `shutdown`-both-ends cable pull on the same link reconverges immediately via RSTP's alternate-to-root transition instead (no loop-guard event, near-0 loss) — pick the test method deliberately and don't call the two the same thing.
8. **Total Po1 loss + root guard (LAB-013, confirmed).** Shutting down both Po1 members on both ends isolates each DIST's downlinks for the VLANs it does not root: root guard puts them root-inconsistent (the non-root DIST *does* receive the real root's superior BPDU, relayed by the access switch over its now-designated uplink — root guard blocks because that BPDU arrives, not because the DIST can no longer hear the root). Each host keeps a working virtual gateway (whichever DIST already owns that VLAN locally), but PC1↔PC2 cross-VLAN traffic and HQ-DIST2's management address both fail completely: the interconnect is a single point of failure for inter-VLAN traffic and for HQ-DIST2's management reachability, because H1 has no IGP between the DISTs (fixed at H2 with OSPF area 10).

## Files

`HQ-DIST1.cfg`, `HQ-DIST2.cfg`, `HQ-ACC1.cfg`, `HQ-ACC2.cfg`, `HQ-PC1.cfg`, `HQ-PC2.cfg` — one startup config per device, the full H1 solved state (identical to LAB-012's day-0, since LAB-012 has no intentional faults: the lab's starting state is H0 and its expected end state is this H1 baseline). A lab that starts from H1 loads these as day-0 and applies its own changes/faults on top.
