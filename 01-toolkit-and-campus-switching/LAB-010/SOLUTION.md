# LAB-010 — Solution

## Summary

Troubleshooting lab (T · G2 · 75 min). Blueprint mapping: **3.1.a:T, 3.1.b:T, 3.1.c:T** (trunk port-type/native mismatch, VLAN database and "allowed and active" state, EtherChannel member missing from the bundle, rogue spanning-tree root), **4.1:P** (toolkit evidence). LAB.md lists domains only (3, 4).

The start state is the HQ H0 baseline (LAB-009) plus four faults from a weekend contractor visit. T1 (HQ-PC2/VLAN 20 unreachable) needs **two** faults fixed, F1 and F2, because they independently break each of HQ-ACC2's two parallel uplinks: fixing either one restores PC2 but leaves the other path silently broken (a latent defect that V2 catches). F2 (v1.4) is VLAN 20 missing from HQ-DIST2's VLAN database: every trunk allowed list is still `10,20,99` on both ends, so the LAB-003 check (compare allowed lists) passes on every link. Only the "allowed and active in management domain" section of `show interfaces trunk` on HQ-DIST2 and its `show vlan brief` show it. T2's recurring warning is F1's `%CDP-4-NATIVE_VLAN_MISMATCH` (HQ-DIST1 only). F3 (bundle member left out of its channel-group, one `%ETC-5-L3DONTBNDL2` at boot) and F4 (rogue spanning-tree root, no log) are found by T2's design-conformance check (V4) and fixed independently.

Log behaviour: the CDP message logs 1/s for about 5 s at boot, then about every 57-60 s; `L3DONTBNDL2` logs once at boot; F2 and F4 log nothing (DIST2's log shows only boot lines).

## Intentional Faults

| ID | Device | What was changed | Symptom |
|---|---|---|---|
| F1 | HQ-ACC2 Ethernet0/0 (uplink to HQ-DIST1) | `switchport mode access` + `switchport access vlan 99` instead of the documented trunk, while HQ-DIST1 Ethernet0/3 stays a trunk | Port-type/native mismatch: HQ-DIST1 logs a repeating `%CDP-4-NATIVE_VLAN_MISMATCH: Native VLAN mismatch discovered on Ethernet0/3 (999), with HQ-ACC2...Ethernet0/0 (99)`. This uplink carries **nothing usable**: ACC2 sends untagged frames, which HQ-DIST1's trunk port places in *its own* native VLAN 999 (no SVI, a dead end) — VLAN 10, 20 **and** 99 are all lost on this specific link. HQ-ACC2's management address stays reachable throughout only because its *second* uplink (to HQ-DIST2, still a normal trunk carrying VLAN 99) and Po1 provide an alternate path to HQ-DIST1's Vlan99 SVI — confirmed live by shutting HQ-ACC2 Ethernet0/1 alone, which drops HQ-DIST1→HQ-ACC2 management pings from 100% to 0% — **part of T1; also T2's recurring warning** |
| F2 | HQ-DIST2 (VLAN database) | `vlan 20` / `name OPS` absent from the configuration (VTP transparent; deleted as "unused": DIST2 has no VLAN 20 SVI or access port). Trunk allowed lists stay `10,20,99` everywhere; `spanning-tree vlan 10,20,99 priority 28672` is kept in the running-config | HQ-DIST2 carries VLAN 20 on no trunk (Et0/3 or Po1), so VLAN 20 cannot use the alternate path ACC2 -> DIST2 -> Po1 -> DIST1. `show interfaces trunk` "allowed and active": `10,99` on Et0/1-3 and Po1; `show spanning-tree vlan 20` on DIST2: "does not exist". VLANs 10 and 99 are unaffected. No log line. **Part of T1**, latent once F1 alone is fixed |
| F3 | HQ-DIST2 Ethernet0/1 (Po1 member 2) | `channel-group 1 mode active` is missing (left as a standalone trunk port after the contractor's re-cabling) | HQ-DIST1's `show etherchannel summary`: `Po1(SU) LACP Et0/0(P) Et0/1(s)` — one member **permanently** suspended (persistent state, confirmed unchanged 14+ min after boot). HQ-DIST1 logs `%ETC-5-L3DONTBNDL2: Et0/1 suspended: LACP currently not enabled on the remote port.` **once**, at boot; it does not repeat on its own — the suspended member itself, not a repeating log, is the durable evidence — found by T2's design-conformance check (V4), with the one-off log line as supporting evidence |
| F4 | HQ-ACC1 | `spanning-tree vlan 10 priority 4096` added (H0's documented root/secondary priorities are 24576/28672, so this reliably wins) | HQ-ACC1 becomes the spanning-tree root for VLAN 10 instead of HQ-DIST1: both distribution switches' `show spanning-tree vlan 10` report Root ID priority 4106 (HQ-ACC1's bridge ID), not HQ-DIST1's. VLAN 10 traffic takes a longer path to its gateway than designed — found by T2's design-conformance check (V4) |

**Platform note:** F1's logged mechanism is `%CDP-4-NATIVE_VLAN_MISMATCH`, not `RECV_1Q_NON_TRUNK` (same platform behaviour as in LAB-002). A `switchport trunk native vlan 1` fault on the member would not persist on this platform — once the member (re)joins the LACP bundle, ioll2-xe silently rewrites its native VLAN to match the Port-channel's, self-healing the fault within about 70 seconds (confirmed with `show running-config interface` before/after). F3 (member left out of the channel-group entirely) produces the same educational point — a Po1 member misconfigured after cabling work — with a stable, persistently-suspended symptom (the log line itself fires once, not repeatedly; see above).

## Diagnosis / Methodology

**T1 — HQ-PC2 (second floor, VLAN 20) unreachable**

1. From HQ-PC2: `ping 10.10.20.1` (its own gateway) fails — this is not a routing problem elsewhere, the local segment itself cannot reach its gateway.
2. The NOC's claim that "the closet switch answers" is confirmed but is a red herring: `ping 10.10.99.22` from HQ-DIST1 succeeds (60-80%, ARP-limited) — HQ-ACC2 is alive and its management VLAN works, telling you nothing about whether its **user** VLAN (20) is passing traffic.
3. Compare HQ-ACC2's two uplinks. Uplink 1 (to HQ-DIST1, Ethernet0/0): `show interfaces switchport` shows **access mode**, VLAN 99 — not the documented trunk. HQ-DIST1's `show logging | include NATIVE_VLAN` confirms the mismatch repeating → **F1**.
4. Uplink 2 (to HQ-DIST2, Ethernet0/1) looks correct: `show interfaces trunk` on HQ-ACC2 shows it trunking, native 999, allowed 10,20,99, and the allowed list at HQ-DIST2 Et0/3 is identical (the LAB-003 check passes). The second section on **HQ-DIST2** ("allowed and active in management domain") lists only `10,99` on Et0/1-3 and Po1, and `show vlan brief` there has no VLAN 20 (`show spanning-tree vlan 20`: "Spanning tree instance(s) for vlan 20 does not exist.") -> **F2**: a transit switch in transparent mode needs the VLAN in its own database. With F1 fixed, STP corroborates it: ACC2's VLAN 20 tree has Et0/1 designated forwarding (no VLAN 20 BPDUs come from DIST2), while VLANs 10 and 99 show Et0/1 `Altn BLK`; check after about 30 s.
5. Ruled out: HQ-PC2 addressing (correct, matches the documented plan); HQ-DIST1's Vlan20 SVI (up, and reachable from HQ-PC1's side of the network); HQ-ACC2 itself (management plane fully functional, only trunk-carried VLANs affected).

**T2 — recurring warning on the distribution layer, plus a design check**

1. The recurring warning is `%CDP-4-NATIVE_VLAN_MISMATCH` on HQ-DIST1 (every 45-60 s): it names HQ-DIST1 Ethernet0/3 and HQ-ACC2 Ethernet0/0, the same evidence as T1 step 3 → **F1**. T1 and T2's first request therefore share a cause, and fixing F1 clears the recurring warning (R4: F1 clears the warning and part of T1's problem; F2 clears the rest of T1; F3 and F4 clear no user-visible symptom).

2. Checking the rest of the campus against the documented design (V4): HQ-DIST1's log buffer (not HQ-DIST2's) also holds `%ETC-5-L3DONTBNDL2: Et0/1 suspended: LACP currently not enabled on the remote port.` once, near boot; it does not recur, but `show etherchannel summary` keeps showing the member suspended indefinitely. This points at the Po1 member on the far end (HQ-DIST2 Ethernet0/1): `show running-config interface Ethernet0/1` there has no `channel-group` line at all → **F3**.
3. Separately, both distribution switches' `show spanning-tree vlan 10` report a Root ID that is neither of their own bridge IDs (priority 4106, not 24586/28682). Checking HQ-ACC1: `show running-config | section spanning-tree` has an explicit `spanning-tree vlan 10 priority 4096` → **F4**.
4. Ruled out: a genuine cabling/link failure (no interface reports down/down anywhere); the EtherChannel misconfig guard err-disabling a port (nothing is err-disabled — the member is merely suspended, waiting for a partner that will never appear until fixed); a VLAN database problem behind the root election (VLAN 10 exists correctly everywhere, only the root election is wrong).

## Solution Configuration

Tested fault-by-fault to prove causality.

**Fix F1** (HQ-ACC2):
```
interface Ethernet0/0
 no switchport access vlan 99
 switchport trunk encapsulation dot1q
 switchport trunk native vlan 999
 switchport trunk allowed vlan 10,20,99
 switchport mode trunk
 switchport nonegotiate
```
Result: HQ-PC2 reaches its gateway again (3/3), via HQ-ACC2 -> HQ-DIST1 directly. At this point F2 is still present but **latent**: shutting HQ-ACC2's uplink 1 (to HQ-DIST1) again reproduces 100% loss, proving the second uplink alone cannot yet carry VLAN 20.

**Fix F2** (HQ-DIST2):
```
vlan 20
 name OPS
```
Result: "allowed and active" on HQ-DIST2 becomes `10,20,99` on Et0/1-3 and Po1; HQ-PC2 reaches its gateway over ACC2 -> DIST2 -> Po1 -> DIST1. Tested alone with F1 re-broken: PC2 0/3 before, then 3/3.

**Wrong fixes** (recorded, no effect): `switchport trunk allowed vlan add 20` on DIST2 Et0/3 and Po1 leaves the config unchanged (`10,20,99`), "allowed and active" still `10,99`, PC2 0/3. Creating `interface Vlan20` (10.10.20.3/24, `no shutdown`) on DIST2 does not create the VLAN: `show vlan brief` still lacks it, `Vlan20 down/down`, no STP instance, PC2 0/3 to .1 and .3; it also adds an SVI the design does not have.

**Fix F3** (HQ-DIST2):
```
interface Ethernet0/1
 channel-group 1 mode active
```
Result: HQ-DIST1 `show etherchannel summary` -> `Po1(SU) LACP Et0/0(P) Et0/1(P)`; the member no longer shows suspended and no further `L3DONTBNDL2` fires.

**Fix F4** (HQ-ACC1):
```
no spanning-tree vlan 10 priority 4096
```
Result: HQ-DIST1 `show spanning-tree summary` -> `Root bridge for: VLAN0010, VLAN0020, VLAN0099` again.

## Verification

**V1/V4** — after all four fixes, HQ-PC2:
```
$ ping -c 3 10.10.20.1        -> 3/3
$ ping -c 3 10.10.10.101      -> 3/3 (HQ-PC1)
```
HQ-DIST1 `show spanning-tree summary`: `Root bridge for: VLAN0010, VLAN0020, VLAN0099`.

**V2** - redundancy proven both ways (table below): PC2 keeps 0 lost pings with either HQ-ACC2 uplink pulled on its own. Before F2 is fixed, `shutdown` of ACC2 e0/0 with only F1 fixed gave 5/5 lost (latent F2).

**V3** — after the fixes, HQ-DIST1's `show logging` shows a clean multi-minute window with no further `%CDP-4-NATIVE_VLAN_MISMATCH` (the message that had genuinely been repeating every 45-60s before the F1 fix). `%ETC-5-L3DONTBNDL2` does not return either, but since it only ever logged once (not a repeat), the real confirmation for F3 is `show etherchannel summary` no longer showing the member suspended (captured under "Fix F3" above) — checking only for log silence would not have proven F3 was fixed.

**V5** — HQ-PC1 and management reachability were re-checked at every stage of the fix sequence (shown inline above) and were never lost: 3/3 throughout.

**V6 (toolkit)** — the diagnosis used sourced pings from both hosts, `show interfaces switchport`/`show interfaces trunk` from both ends of each link, and log timestamps — which showed the CDP message genuinely repeating (45-60s apart) but the L3DONTBNDL2 message firing only once, a distinction that matters for what each message can and cannot prove.

## Failure / Recovery Behaviour

Probe: HQ-PC2 -> 10.10.20.1, busybox `ping -i 0.2`, loss counted from `seq=` gaps; 3 runs each, all four fixes in place. Cable pull = `shutdown` on both ends of the link; one-ended = `shutdown` on one end only; no link stop used.

| Scenario (trigger -> end condition) | Runs (lost pings) | Documented range | Basis |
|---|---|---|---|
| Cable pull ACC2 e0/0 (shut ACC2 e0/0 and DIST1 e0/3) -> replies continue | 0, 0, 0 | 0-1 pings (< 1 s) | RSTP alternate port (Et0/1) takes over |
| Failback: `no shutdown` both ends -> replies continue | 0, 0, 0 | 0-1 pings | RSTP proposal/agreement |
| Cable pull ACC2 e0/1 (shut ACC2 e0/1 and DIST2 e0/3), e0/0 active -> replies continue | 0, 0, 0 | 0 pings | standby path, no topology change on the active path |
| One-ended `shutdown` DIST1 e0/3 only (ACC2 e0/0 stays up/up) -> gap closes | 26, 22, 28 (4.4-5.6 s) | 4-7 s | measured 4.4-5.6 s; for comparison, 3 x 2 s RSTP hellos = 6 s is a calculated upper bound, not measured, plus polling |
| Po1 member loss (earlier build: shut DIST1 e0/0, PC1 -> PC2 ping 10) | 0 of 10 lost | 0-1 pings | LACP member leaves the bundle; the other member carries traffic; `Po1(SU) Et0/0(P) Et0/1(P)` returns on `no shutdown` |

## Answers to Analysis Questions

**Q1.** A successful ping to a switch's own management address only proves that switch's control-plane/management VLAN is alive — it says nothing about whether the specific VLAN and trunk paths that carry user traffic are working. Here, HQ-ACC2 answered on VLAN 99 the whole time not because the broken uplink was passing anything, but because the **second, independent** uplink to HQ-DIST2 (which still carries VLAN 99) and Po1 carried its management traffic instead; the broken uplink carried nothing at all (untagged frames from it land in the far end's own native VLAN, a dead end with no SVI). Monitoring should probe end-to-end, in the actual VLAN/subnet that matters, over the actual path a user's traffic takes, not just "is the box alive" over whatever path happens to still work.

**Q2.** Both reported problems start from the same log line: the `%CDP-4-NATIVE_VLAN_MISMATCH` message (on HQ-DIST1, the distribution switch nearest the affected closet, repeating every 45-60 s) points straight at the mismatched trunk/access configuration, which is F1, the first cause of T1 and the recurring warning in T2. T1's second cause (F2) has no log at all: it comes from comparing both ends of HQ-ACC2's second uplink. The `%ETC-5-L3DONTBNDL2` message (also on HQ-DIST1, logged only once, near boot) points at the other distribution switch's un-bundled port (F3); its persistence has to be confirmed with `show etherchannel summary`, not by waiting for the log to repeat. The rogue root (F4) has no log of its own: it is found by comparing `show spanning-tree` output against the documented design, which is why R3 asks for `show` command output as evidence too, not only log lines.

**Q3.** Root guard — configured on the distribution switches' downlinks toward the access layer in the bench labs — would have blocked the access switch from ever becoming root: as soon as it started advertising a superior (lower-priority) BPDU, the distribution switch's downlink would have moved to a root-inconsistent, blocking state instead of ceding the root role, and would have logged the change immediately rather than leaving VLAN 10 quietly running through a suboptimal path. This same protection is the reason the H1 stage (012) adds root guard to the production design.

**Q4.** F1: the ping to ACC2's management address (and "the trunk is up") looked fine; the repeating `%CDP-4-NATIVE_VLAN_MISMATCH` and `show interfaces switchport` on e0/0 showed the access-mode port. F2: the LAB-003 check, comparing trunk allowed lists on both ends of each link, passes on every link; the "allowed and active in management domain" section of `show interfaces trunk` on HQ-DIST2 and `show vlan brief` there show VLAN 20 missing. A switch that only passes a VLAN through still needs it in its database in transparent mode. F3: Po1 is up and the Port-channel works, so a ping across it looks fine; `show etherchannel summary` shows `Et0/1(s)` and DIST2's member config has no `channel-group`. F4: everything forwards, no log; `show spanning-tree root` shows ACC1 (bridge 4106) as VLAN 10 root.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-15 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), ioll2-xe (IOS XE 17.16.1a) |
