# LAB-029 — Solution

## Summary

An implementation/integration lab with the first AI-change review. The Veridian edge (EDGE E1, solved in LAB-025) gets failover that survives a silent provider failure: IP SLA probes to each provider's loopback (pinned), tracked static defaults (so OSPF's conditional default origination, which has no `always`, withdraws with them), a tracked HSRP priority on the DMZ gateway and an EEM evidence applet. The student then reviews an AI-written evidence applet that looks correct against LAB-028's checklist and has two designed flaws found by different halves of the test cycle: AI-1, a trigger bound to the eBGP session instead of the probe (perfect on a cable pull, 130-180 s late on a silent failure), and AI-2, a DMZ gateway move by a configured HSRP priority change that is never reverted (found only on the recovery). Blueprint: 4.4:P (tracking/IP SLA-driven failover), 3.3.c:R (FHRP, DMZ HSRP), 6.6:P (EEM). Its solved state is stage EDGE E2.

## Intentional Faults

None in the YAML (integration lab; the start state is E1 with no tracking). The AI proposal in LAB.md is the reviewed artefact. It contains none of LAB-028's pitfalls (`enable` first, every output appended, exact pattern, no self-trigger, no `wait`), so reading it against that checklist decides nothing.

| ID | Where | What | Symptom |
|---|---|---|---|
| AI-1 | proposal, `event syslog pattern "%BGP-5-ADJCHANGE: neighbor 198.51.100.64 Down"` | keyed to the eBGP session, not to the probe. On a cable pull (both ends down) fast external fallover drops the session at once; on a silent failure (or a one-ended provider `shutdown`) the session stays Up until the hold timer expires | silent failure: nothing in `show event manager history events` at +60 s, run at +134 s and +138 s (Down BGP Notification sent), the file records the post-failover state; fails R4's 30 s bound. Cable pull: runs at +1.9 s, before track 10 goes Down |
| AI-2 | proposal, actions 6.0-6.3 | moves the DMZ gateway by rewriting the configured HSRP priority 110 -> 90 and never reverts it | after the heal EDGE1 stays Standby with `Priority 90 (configured 90)`, EDGE2 stays Active; `show running-config interface e0/2` has `standby 60 priority 90`. Fails R2 ("takes it back") |

AI-1 needs 024's silent-failure BGP timing and 026's reason for probing; AI-2 needs 3.3.c's difference between a configured priority and a tracked decrement. A student who tests only the cable pull sees a perfect run for AI-1; a student who tests only the failure sees the gateway move as promised for AI-2.

**Verdict (model): amend.** Keep actions 0.1-5.0 and 7.0, replace the trigger with `event track 10 state down`, delete actions 6.0-6.3 (R2 belongs to `standby 60 track 10 decrement 20`, which reverts by itself), and restore `standby 60 priority 110` after the test. Reject (with the student's own applet) is graded equally when the evidence shows both defects. Approve fails V3 and V6. A verdict citing only one flaw is half credit.

## Diagnosis / Methodology

1. Baseline (R6/V1): `show track`, `show ip route 0.0.0.0`, `show standby brief`, PC1 traceroutes; with no tracking, a silent ISP-A failure leaves EDGE1's static default (AD 1) in place and HQ-PC1 loses everything default-routed.
2. Probe design (R3): the probe target is the provider loopback, pinned with `/32` via the interface and next hop plus a Null0 `/32` at AD 250. After a cable pull the pinned route disappears and `show ip route 198.51.100.1` shows only the Null0 route, so the probe cannot leak through EDGE2 and keep the track Up. Check this explicitly in the cable pull.
3. Timing (R1): detection = SLA frequency 5 s, timeout 5 s, track `delay down 5`; `delay up 30` gives the 30 s hold-down. Measure rather than assume.
4. DMZ gateway (R2): `standby 60 track 10 decrement 20` drops EDGE1 to 90 below EDGE2's 100 (preempt on both), and the priority stays 90 while track 10 is Down, so no black hole on restart.
5. Applet review (R5). Evidence table (all measured, UTC log stamps, one clock):

   | Student test | Proposal as written | What it decides |
   |---|---|---|
   | Read against the 028 checklist | all present or not applicable | nothing |
   | Cable pull ISP-A (`shutdown` both ends) | `%BGP-5-ADJCHANGE: neighbor 198.51.100.64 Down Interface flap` and the applet run +1.9 s after the shutdown, file complete, one `%HA_EM-6-LOG`, history success; the file shows `Reachability is Up, last change 00:00:16` (track Down only at +10.5 s) and the default already via OSPF | looks correct; first hint that the capture precedes the probe |
   | One-ended `shutdown` (PROV-ISP1 e0/0 only; EDGE1 e0/0 stays up/up) | track 10 Down +8.7 s; no run; the ADJCHANGE line and the run come at +129 s (`Down BGP Notification sent`, hold expiry) | a student-side "cable pull" with only the provider side down is a silent failure for the session: the proposal is late here too |
   | Silent failure (`link stop`), checked at +60 s | `show event manager history events` empty, no log line, while track 10 has been Down since +14 s and the default is via EDGE2 | 028-recall trap "the pattern never matches". Ruled out: `show ip bgp summary` shows 198.51.100.64 Established (Up/Down 00:02:58) and `show logging \| include ADJCHANGE` has no Down line yet. The event has not happened; the pattern is fine |
   | Same silent failure to hold expiry | `%BGP-5-ADJCHANGE: neighbor 198.51.100.64 Down BGP Notification sent` at +133.9 s (run 2: +137.5 s); applet start +1.0 s later; history `success`, exactly one `%HA_EM-6-LOG`; file entry stamped 20:59:02.713 with `Known via "ospf 1", distance 110`, `Reachability is Down ... last change 00:02:00`, SLA failures 13, BGP 198.51.100.64 Idle | **AI-1**: the file is written two minutes late and shows the post-failover state; fails R4's 30 s bound |
   | Heal ISP-A after either failure, wait for track Up + 30 s (S1 checked +153 s after track Up) | EDGE1 `State Standby, Preemption enabled, Priority 90 (configured 90)`, `Track object 10 state Up decrement 20`; `standby 60 priority 90` in the running config; EDGE2 Active | **AI-2**: fails R2. Wrong conclusion "EDGE1 lacks preempt" ruled out by `Preemption enabled`: the configured priority changed |
   | Companion lines that do not match | `%BGP_SESSION-5-ADJCHANGE ... topology base removed`, `%BGP-5-NBR_RESET`, the IPv6 neighbour 2001:DB8:F001:FFFF::64 ADJCHANGE | the pattern matches exactly one line per failure and the applet ran once each time |
   | Amended applet (`event track 10 state down`, no 6.x) | silent: track Down +12.4 / +15.3 s, log line +13.1 / +16.0 s, file stamped at track Down, BGP still Established; cable pull (both ends): track Down +11 s, log +11.6 s, one line. Heal: HSRP back on EDGE1 at +42 / +35 / +38 s, `Priority 110 (configured 110)` | meets R2 and R4 |

   Actions 6.0-6.3 do run inside the default `maxrun` of 20 s with the five `show` actions (history `success`, `%SYS-5-CONFIG_I ... (EEM:ISPA-EVIDENCE)`), so the gateway move is real. With the student's `standby 60 track 10 decrement 20` also configured (110-20=90 < 100), EDGE2 already becomes Active when the track goes Down, before the applet runs; the proposal's damage then shows only after the heal (`Priority 90 (configured 90)`; `70`, configured 90, while the track is Down). Without the tracked decrement the gateway moves only through actions 6.x. The evidence file persists across runs (appended), so a second test shows older entries; delete it between tests (`delete /force unix:ispa-evidence.txt` is non-interactive) or compare the `show clock` stamps. Restore after the test: `standby 60 priority 110` (preempt returns the gateway within 5 s).
6. BGP-learned destinations (Q6): `show ip bgp summary` shows ISP-A Up until the hold timer expires, so ISP-A's own networks and inbound DMZ traffic follow BGP, not the track.

## Solution Configuration

**HQ-EDGE1** (config mode)

```
ip route 198.51.100.1 255.255.255.255 Ethernet0/0 198.51.100.64
ip route 198.51.100.1 255.255.255.255 Null0 250
ip sla 10
 icmp-echo 198.51.100.1 source-interface Ethernet0/0
 frequency 5
ip sla schedule 10 life forever start-time now
track 10 ip sla 10 reachability
 delay down 5 up 30
no ip route 0.0.0.0 0.0.0.0 198.51.100.64
ip route 0.0.0.0 0.0.0.0 198.51.100.64 track 10
interface Ethernet0/2
 standby 60 track 10 decrement 20
event manager applet ISPA-EVIDENCE
 event track 10 state down
 action 0.1 cli command "enable"
 action 1.0 cli command "show clock | append unix:ispa-evidence.txt"
 action 2.0 cli command "show ip route 0.0.0.0 | append unix:ispa-evidence.txt"
 action 3.0 cli command "show track 10 | append unix:ispa-evidence.txt"
 action 4.0 cli command "show ip sla statistics 10 | append unix:ispa-evidence.txt"
 action 5.0 cli command "show ip bgp summary | append unix:ispa-evidence.txt"
 action 7.0 syslog msg "ISP-A evidence captured, DMZ gateway moved to HQ-EDGE2"
```

(`show track` and `show ip sla statistics` without an object number also work, as in the proposal.) If the proposal was tested, first `delete /force unix:ispa-evidence.txt`, then `no event manager applet ISPA-EVIDENCE`, re-enter the applet as above, and on the interface `standby 60 priority 110`. No actions 6.0-6.3: the gateway move belongs to `standby 60 track 10 decrement 20`.

**HQ-EDGE2** (config mode)

```
ip route 203.0.113.1 255.255.255.255 Ethernet0/0 203.0.113.64
ip route 203.0.113.1 255.255.255.255 Null0 250
ip sla 20
 icmp-echo 203.0.113.1 source-interface Ethernet0/0
 frequency 5
ip sla schedule 20 life forever start-time now
track 20 ip sla 20 reachability
 delay down 5 up 30
no ip route 0.0.0.0 0.0.0.0 203.0.113.64
ip route 0.0.0.0 0.0.0.0 203.0.113.64 track 20
```

The corrected applet replaces the proposal (`no event manager applet ISPA-EVIDENCE` first); `event track 10 state down` replaces the BGP syslog trigger. `flash:` does not exist on iol-xe; the file is on `unix:`.

## Verification

Captured on a fresh import after applying the solution (steady state):

```
HQ-EDGE1# show track | include Reach           Reachability is Up
HQ-EDGE1# show standby brief                    Et0/2  60  110 P Active  local  10.10.60.3  10.10.60.1
HQ-EDGE1# show ip route 0.0.0.0 | include Known Known via "static", distance 1, metric 0, candidate default path
HQ-EDGE1# show event manager policy registered  1  applet  user  track  Off  ...  ISPA-EVIDENCE
HQ-EDGE2# show track | include Reach            Reachability is Up
HQ-PC1$ traceroute -n 192.0.2.200   10.10.10.1, 10.10.255.65, 198.51.100.64, 192.0.2.200
HQ-PC1$ traceroute -n 203.0.113.10  10.10.10.1, 10.10.255.65, 10.10.255.69, 203.0.113.64
```

Silent failure ISP-A (`link stop`), 30 s later:

```
HQ-EDGE1# show track | include Reach            Reachability is Down
HQ-EDGE1# show standby brief | include Et0      Et0/2  60  90  P Standby 10.10.60.3 local 10.10.60.1
HQ-EDGE1# show ip route 0.0.0.0                 Known via "ospf 1", distance 110, metric 30 ... * 10.10.255.69, from 10.255.10.32
HQ-EDGE1# show log | include TRACK|evidence
 %TRACK-6-STATE: 10 ip sla 10 reachability Up -> Down
 %HA_EM-6-LOG: ISPA-EVIDENCE: ISP-A evidence captured, DMZ gateway moved to HQ-EDGE2   (about 1 s later)
HQ-CORE1# show ip route 0.0.0.0                 ospf 1, metric 30, via 10.10.255.67 (HQ-EDGE2)
HQ-PC1$ traceroute -n 192.0.2.200               10.10.10.1, 10.10.255.67, 203.0.113.64, 192.0.2.200
```

Evidence file: `more unix:ispa-evidence.txt` shows the clock, the default route, `Reachability is Down`, SLA statistics (successes/failures) and the BGP summary. R6: the traceroutes above (steady state) match LAB-025.

## Failure / Recovery Behaviour

Times in seconds from the failure; hosts ping once per second.

| Scenario (trigger, end condition) | Runs (raw values) | Documented range | Basis |
|---|---|---|---|
| Silent failure ISP-A (`link stop`) | track Down +15 (second run +16), evidence +16, HSRP leaves Active +1 after track Down, Standby +12; PC1 -> PROV-SRV1 lost 15 (14) pings, then via ISP-B. ISP-A eBGP stays Up until hold expiry, about +130-180 s (IPv6 +130-180, IPv4 +160-170 in other runs). Inbound HQ-SRV1 <-> PROV-SRV1 (DMZ static NAT 192.0.2.130) lost roughly 130-175 pings, back when the hold expires. IPv6 default: PC1 v6 pings lost about 140 until the IPv6 BGP hold expired, then via ISP-B | track Down 11-17 s; HSRP leaves Active +1 s after track Down; PC1 loses 11-17 pings; ISP-A eBGP Down +130-180 s | 6 runs (+15, +16, +11, +13, +14, +12) |
| Recovery (`link start`) | IPv6 BGP Up at once only if the session survived (after a hold expiry IPv4 came up about +10-25 s and IPv6 about +20-25 s after link start), track Up about +35 (first probe + delay up 30), HSRP Active +37, 0 pings lost | track Up +32-41 s; HSRP Active +35-42 s; 0 pings lost | measured runs |
| Cable pull ISP-A (`shutdown` both ends) | BGP down at once, static default gone at once (0 of 120 pings lost for IPv4; IPv6 loses 8-9 pings before OSPFv3 moves the default to EDGE2), track Down +10-12 on EDGE1 only (+11 s with the amended applet; earlier runs +6) (EDGE2's track 20 stays Up), `show ip route 198.51.100.1` = Null0 AD 250 (no leak), HSRP 90, evidence written | BGP down at once; track 10 Down 6-12 s; IPv4 0 lost; IPv6 8-9 lost | runs +10-12, +6 earlier, +11, +8 to +9 |
| Silent failure ISP-B | track 20 Down +16; default traffic unaffected (EDGE1 primary, 0 lost); traffic to ISP-B's networks lost 147 pings until BGP hold expiry (+148), then via ISP-A and the interconnect | track 20 Down +16 s; ISP-B-network traffic lost until BGP hold expiry (about +148 s) | 1 run |
| Cable pull ISP-B | 0 lost for both targets, track 20 Down, `show ip route 203.0.113.1` = Null0 AD 250 | 0 lost; track 20 Down | 1 run |
| Node stop HQ-EDGE1 (saved) | PC1 -> PROV-SRV1 lost 3 pings (OSPF dead 4 s), EDGE2 HSRP Active at once; HQ-SRV1's Internet traffic lost roughly 100-150 s (replies return through ISP-A, whose session to the dead EDGE1 stays Up until hold expiry +177). On restart: track Up +30 after boot, HSRP preempts back | 3 pings lost; HQ-SRV1 Internet loss 100-150 s; track Up +30 s after boot | 1 run |
| AI proposal, cable pull (both ends) | runs +1.9 s after the shutdown, complete file, one log line; file shows track 10 Up and the default already moved | applet runs about +2 s | 1 run |
| AI proposal, one-ended provider `shutdown` | track Down +8.7 s; session stays Up; applet runs at BGP hold expiry, +129 s | track Down +8.7 s; applet at +129 s (hold expiry) | 2 runs (second: +13 s track Down) |
| AI proposal, silent failure | nothing at +60 s; runs at +133.9 s and +137.5 s (BGP hold expiry), file shows post-failover state (range +130-180 s) | applet runs +130-180 s (hold expiry) | 2 runs (+133.9, +137.5 s) |
| AI proposal, heal | HSRP stays on EDGE2 indefinitely: EDGE1 `Priority 90 (configured 90)` (track Up +32 s after link start; still Standby +153 s after track Up) | HSRP stays on EDGE2 indefinitely (checked to +153 s after track Up) | 1 run |
| Amended applet | silent: log +13.1 / +16.0 s, file at track Down; cable pull: +11 s; BGP stays Established on a silent failure; heal: track Up +33-41 s, HSRP back on EDGE1 +35-42 s with no manual action | silent: log +11-16 s; cable pull +11 s; heal: track Up +33-41 s, HSRP back +35-42 s | 2 runs per case; further silent runs +11 to +14 s |

The measured R1 detection (track Down after a silent failure) is 11-17 s across all runs (cable pull 6-12 s) and meets the 20 s target; the 30 s hold-down shows as 35 s from heal to restore.

## Answers to Analysis Questions

**Q1.** Silent failure at t=0; probe Down +11 to +17 s (11-16 s across runs); the tracked static leaves and OSPF withdraws the E2 default at the same moment (EDGE2's metric-30 default takes over, CORE1 reroutes within about a second); HQ-PC1's traffic is back right after the track change, so 11-17 pings are lost (one per second) before the probe goes Down at +11-17 s; resumption cannot precede detection. The detection time dominates: SLA frequency 5 s + timeout 5 s + `delay down 5`; the OSPF and HSRP steps take 1 s. Shorten it with a shorter probe interval (a smaller `frequency` value means more probes per minute), a shorter timeout and a lower `delay down`, at the cost of false positives from a single lost probe.
**Q2.** Inbound traffic arrives via ISP-A's BGP-learned route to Veridian's DMZ block; ISP-A keeps sending it to EDGE1 over the dead link until its BGP session to EDGE1 times out (hold 180 s; measured roughly 130-170 s from the failure), and only then does ISP-B's path win. That decision is the provider's (its hold timer or BFD), not Veridian's.
**Q3.** The IPv6 default comes from the ISP-A ::/0 learned by BGP (preferred by local preference 150), not from a tracked static, so a silent failure leaves it in place until the BGP hold time expires (about 130-180 s). The DMZ host HQ-SRV1 is different again: its IPv6 default is RA-based (HQ-EDGE1's DMZ interface advertises router preference High, EDGE2 default Medium), so it prefers EDGE1 and follows neither HSRP 60 nor track 10; it recovers only when the IPv6 BGP/OSPFv3 default moves, not with the track. Fixes, noting that an IPv6 cable pull loses only 8-9 pings before OSPFv3 moves the default: track-driven action for IPv6 (an IP SLA on IPv6 with a tracked IPv6 static default and conditional origination), BFD or shorter BGP timers agreed with the provider.
**Q4.** The tracked static default leaving the table is what must withdraw the OSPF default. With `always`, EDGE1 would keep advertising the default into OSPF after its provider fails, so the campus would keep preferring it (metric 10 against EDGE2's 30) and send traffic into the black hole. Without `always`, the tracked static default leaving the table withdraws the OSPF default and EDGE2's takes over.
**Q5.** Amend (reject with the student's own applet is graded equally when both defects are shown; approve is wrong). The proposal is well formed (privilege, exact pattern, appended output, no self-trigger) and works on a cable pull, which hides its two defects. (1) Its trigger is the eBGP session, not the probe. On a silent failure the session stays Established until the hold timer expires: at +60 s history is empty and `show ip bgp summary` still shows 198.51.100.64 Up, so the pattern is fine, the event has not happened; the applet then runs at +134 / +138 s and the file shows the post-failover state (default via EDGE2, track Down for two minutes): R4's 30 s bound fails. The same holds for a one-ended provider `shutdown` (+129 s). (2) Actions 6.0-6.3 rewrite the configured HSRP priority to 90 and nothing reverts it: after the heal EDGE1 shows `Priority 90 (configured 90)` while preemption is enabled, and EDGE2 stays Active; R2 fails. Amended: `event track 10 state down` (file at +13 to +17 s on a silent failure, about +11 s on a cable pull), delete 6.0-6.3 and rely on `standby 60 track 10 decrement 20`, restore `standby 60 priority 110`.
**Debrief.** The proposal looks perfect on the cable pull because both ends going down drops the session in about 2 s, so a trigger on the session is early there. A probe-driven event is the right trigger for evidence about a silent failure because the probe is what detects it: the track goes Down at +12-17 s while the session still looks healthy, so the evidence matches the moment of failover on both failure methods. A tracked decrement reverts by itself because the effective priority is the configured one minus the decrement while the object is Down; a priority change is a configuration edit that persists, and a later `write memory` would make it permanent.
**Q6.** The ISP-A routes (its /25, supplier /29) come from BGP and the session stays Up until hold expiry (about 130-180 s), so they point at the dead link while the default (a static plus OSPF) has already moved. Options on Veridian's side: lower BGP keepalive/hold timers (provider must accept the negotiated lower hold), BFD for the neighbor if supported, or an EEM/tracked action that shuts or reroutes the neighbor when the track goes Down. Provider-side options (their own BFD or timers) are outside Veridian's control.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-15 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), iol-xe (IOS XE 17.16.1a), unmanaged_switch |
