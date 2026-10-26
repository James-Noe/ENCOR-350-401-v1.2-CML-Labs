# LAB-030 — Solution

## Summary

A troubleshooting lab on the dual-ISP edge (environment EDGE stage E2 plus three faults from an "edge clean-up"), v1.2. Two tickets, three faults. T1 (supplier portals) needs F1 and F2 together. T2 (an ISP-B failure takes the office offline) is F3 alone. The change ticket's instructor reading: the clean-up touched EDGE2's edge-link interfaces (F1), EDGE2's static routes (F2) and "made the failover probes consistent on both edges" (F3). Blueprint mapping: 3.2.c (BGP announcement needs an exact RIB match, F2), 3.3.b (NAT inside/outside roles, F1), 4.4 (IP SLA and tracking, F3), 3.3.c (reinforced: HSRP follows the track, policy per exit). Earlier-module causes the evidence must clear: OSPF default origination and the OSPFv2 process (module 03), and the DMZ HSRP (module 02).

## Intentional Faults

| ID | Device | Change | Symptom |
|---|---|---|---|
| F1 | HQ-EDGE2 e0/3 | `ip nat inside` removed | Traffic relayed by EDGE1 to EDGE2 (ISP-B's networks, supplier 198.51.100.8/29) leaves untranslated with private sources: no NAT entry, ISP-B has no return route. Core-to-EDGE2 traffic (failover) still translates, so T2 never shows F1 |
| F2 | HQ-EDGE2 | pool B anchor is `ip route 192.0.2.64 255.255.255.224 Null0` (/27) while `network 192.0.2.64 mask 255.255.255.192` stays | No exact RIB match: 192.0.2.64/26 is not announced to ISP-B, translated traffic from pool B gets no replies. Hits everything leaving via ISP-B (T1, and any ISP-A failover) |
| F3 | HQ-EDGE1 | `ip sla 10` target 203.0.113.1 (ISP-B's loopback) instead of 198.51.100.1, copied from EDGE2's SLA 20 block; `source-interface Ethernet0/0`, frequency 5, track 10, the tracked default, HSRP decrement and the EEM applet unchanged; the two 198.51.100.1 /32 pins stay | EDGE1's best route to 203.0.113.1 is the iBGP 203.0.113.0/25 via EDGE2, so the probe leaves over e0/3, EDGE2 and ISP-B (untranslated) and the reply comes back ISP-B, ISP-A, EDGE1 e0/0. It succeeds in steady state and fails on an ISP-A failure, so every ISP-A test passes; but an ISP-B failure brings track 10 Down too: both edges withdraw their defaults, HSRP moves the DMZ gateway to EDGE2 (towards the dead provider), ISPA-EVIDENCE runs |

Causality (measured, F1-F3 at start):
- T1: fixing F1 only leaves both portals at 100% loss (EDGE2 NAT inside Et0/1-0/3 now, ISP-B still has no 192.0.2.64). Fixing F2 only: ISP-B shows 192.0.2.64/26 within 20 s but F1 still leaves relayed traffic untranslated: with F2 fixed, re-breaking F1 gives 100% loss again, and with both fixed HQ-PC1 reaches both portals.
- T2: with F3 present an ISP-A silent failure behaves exactly like E2-with-F2 (F3 is latent). With F3 fixed alone (F1, F2 still present) the ISP-B drill leaves track 10 Up, EDGE1 Active (110), CORE1 default via EDGE1 metric 10, HQ-PC1 to 192.0.2.200 and PROV-SRV1 to 192.0.2.130 OK: F3 alone closes T2. Its test is independent of F1/F2 (the probe is untranslated and its reply bypasses EDGE2).

## Diagnosis / Methodology

**T1 (supplier portals), at boot.**
1. HQ-PC1: 192.0.2.200 works, 198.51.100.10 and 203.0.113.10 fail (100% loss); IPv6 works. Traceroute to either portal shows HQ-CORE1, EDGE1 (10.10.255.65), EDGE2 (10.10.255.69), then nothing: the path is the designed one (ISP-B exit via EDGE2), so outbound BGP policy is correct; CORE1's default points to EDGE1 and most of the Internet works, which clears module 03.
2. Suppliers and providers are not the cause: EDGE2 itself pings both portals (router-originated traffic uses its ISP-B address, which ISP-B knows), and the looking glasses show the prefixes.
3. EDGE2 `show ip nat statistics` lists inside interfaces Et0/1 and Et0/2 only (no Et0/3); `show ip nat translations | include 10.10.10.101` is empty while HQ-PC1 pings a portal; the ISP-B looking glass shows no flow from Veridian's pool: F1. **Deviation: no packet capture and no `debug ip packet`.** ACL-limited `debug ip packet 150 detail` on EDGE2 (ACL 150 icmp host 10.10.10.101, logging buffered debugging) printed nothing on iol-xe (CEF-switched), so the evidence is the NAT statistics, the absent translations and the provider-side view.
4. After F1: translations to 192.0.2.65 appear (`icmp 192.0.2.65:1024 10.10.10.101:33 <portal>`) but replies never come. PROV-ISP2 `show ip route 192.0.2.64` is "not in table"; EDGE2 `show ip bgp 192.0.2.64/26` is "not in table" while `show ip route 192.0.2.64` is 192.0.2.64/27 static Null0: F2. A BGP `network` statement needs an exact RIB match.
5. Red herrings: the DMZ web server keeps working (its /26 is announced, static NAT unaffected); ISP-A's looking glass shows ISP-B's networks via transit (normal).

**T2 (ISP-B silent failure drill: `link stop` HQ-EDGE2 e0/0 - PROV-ISP2 e0/0).**
1. HQ-CORE1: `show ip route 0.0.0.0` is empty, `show ipv6 route ::/0` is present (OSPFv3 from EDGE1). This looks like an OSPFv2 or default-origination problem. Clear it: OSPFv2 and OSPFv3 neighbours FULL to both edges, `show ip ospf database external` has no 0.0.0.0 LSA (both ASBRs withdrew it; flushed at the withdrawal, no MaxAge wait), and both edges' `default-information originate` has no `always`, as designed. Origination is conditional and both conditions are gone, so ask why EDGE1's static default left.
2. The DMZ gateway moved to EDGE2, towards the failed provider: look at HSRP. Priorities 110/100, preempt and decrement 20 match the design; EDGE1 `show standby` shows `Priority 90 (configured 110)` and `Track object 10 state Down decrement 20`. HSRP reacts correctly to a wrong input: cleared.
3. EDGE1's ISP-A link is healthy: `ping 198.51.100.64` works, eBGP to ISP-A Established. Yet `show track 10` is Down. The evidence file (`more unix:ispa-evidence.txt`) was written for an "ISP-A failure" with ISP-A Established in it.
4. `show ip sla configuration 10`: target 203.0.113.1, an ISP-B address (provider letter or looking glass). `show ip route 203.0.113.1` is the iBGP 203.0.113.0/25 via 10.255.10.32 (EDGE2) and `traceroute 203.0.113.1 source Ethernet0/0` leaves via EDGE2 then ISP-B (steady state: hop 1 10.10.255.69, hop 2 203.0.113.64). The probe depends on the other provider: F3. Steady state SLA 10 RTT 3 ms, as healthy as SLA 20 (3 ms), which is why it misleads.
5. T1's red herrings mix in here: the old 198.51.100.1 pins on EDGE1 are correct E2 lines, now unused (a clue when compared with the probe). Boot-time `%BGP-5-ADJCHANGE` and `%HSRP-5-STATECHANGE` lines on both edges are normal.

**Wrong fixes, each tried once.**
- Announce the /27 (`network 192.0.2.64 mask 255.255.255.224`): closes T1 but ISP-B then holds a /27, not the documented /26 pool (V3); the POOL-B-OUT prefix-list must also change. Not re-run in v1.2 (run in v1.1).
- Steer suppliers out of ISP-A with statics (v1.1): wrong exit (pool A 192.0.2.1), violates V3.
- Pin the probe target via ISP-A's link (`ip route 203.0.113.1 255.255.255.255 Ethernet0/0 198.51.100.64` plus a Null0 AD 250 backup, target unchanged; v1.2 measured): traceroute 198.51.100.64, 198.51.100.67 (ISP-A, interconnect), then ISP-B. ISP-A silent failure: track 10 Down 19.8 s (pass); ISP-B silent failure 45 s in: track 10 Up, EDGE1 Active, users on pool A OK (pass). Both silent drills pass, but `node stop PROV-ISP2` (a silent failure of the provider *node*) took track 10 Up->Down in 12 s (18:51:35.953, stop 18:51:23.8), HSRP Active->Speak and EDGE1 lost its default. The probe still depends on the other provider and violates the measurement rule (V3).
- `default-information originate always` on EDGE1 keeps a core default pointing at a router with no Internet; removing `track 10` from the static fails the ISP-A drill; removing HSRP's `track 10 decrement 20` breaks "gateway follows the healthy provider"; lowering BGP timers needs the provider (rule R3). None of these were run; reasoned from the design.

## Solution Configuration

HQ-EDGE2 (F1 and F2):
```
interface Ethernet0/3
 ip nat inside
no ip route 192.0.2.64 255.255.255.224 Null0
ip route 192.0.2.64 255.255.255.192 Null0
```
(no prompts; `clear ip nat translation *` is optional).

HQ-EDGE1 (F3). A running SLA cannot be edited (`icmp-echo 198.51.100.1 ...` under the running `ip sla 10` returns "Entry already running and cannot be modified"), so remove and re-create:
```
no ip sla 10
ip sla 10
 icmp-echo 198.51.100.1 source-interface Ethernet0/0
  frequency 5
ip sla schedule 10 life forever start-time now
```
`no ip sla 10` does not prompt. During the edit track 10 stayed Up (delay down 5 s was not reached): no new TRACK or ISPA-EVIDENCE line, the default is untouched, and SLA 10's success counter restarts at 0. Order: run the five lines in one config block. Save both edges with `copy running-config startup-config`.

## Verification

All three fixes together restore E2. Captured:
- Start state, re-checked on a fresh import of the YAML: EDGE1 track 10 `Reachability is Up`, `Target address/Source interface: 203.0.113.1/Ethernet0/0`, `show ip route 203.0.113.1` = `203.0.113.0/25 ... type internal ... 10.255.10.32` (BGP, distance 200), HSRP `Et0/2 60 110 P Active local 10.10.60.3`, static default; EDGE2 `Inside interfaces: Ethernet0/1, Ethernet0/2`, `192.0.2.64/27 static ... Null0`, `show ip bgp 192.0.2.64/26` = `% Network not in table`; CORE1 default `ospf 1 ... metric 10` via 10.10.255.65 and `::/0` via ospf; HQ-PC1 to 192.0.2.200 3/3, to 198.51.100.10 and 203.0.113.10 100% loss, IPv6 to 2001:db8:f001:ffff::64 3/3; PROV-ISP2 `show ip route 192.0.2.64` = `% Subnet not in table`.
- T1 closed by F1+F2: HQ-PC1 reaches both portals; ISP-B shows 192.0.2.64/26 within 20 s of the F2 fix.
- T2 closed by F3: ISP-B drill (`link stop` HQ-EDGE2 e0/0 - PROV-ISP2 e0/0 at 18:31:31.9) with F3 fixed: track 10 Up, EDGE1 Active (110), CORE1 default via EDGE1 metric 10, HQ-PC1 to 192.0.2.200 and PROV-SRV1 to 192.0.2.130 OK.
- ISP-B drill with F3 present (stop 18:24:11.6): track 10 Up->Down 18:24:30.412 (18.8 s), `ISPA-EVIDENCE` 18:24:31.078, HSRP 60 EDGE1 Active->Speak 18:24:32, Standby 18:24:43; CORE1 `show ip route 0.0.0.0` not in table, `::/0` via ospf metric 10, OSPFv2/OSPFv3 FULL to both edges; EDGE1 `Priority 90 (configured 110)`, `Track object 10 state Down decrement 20`; both type-5 0.0.0.0 LSAs gone. After EDGE1's iBGP route to 203.0.113.1 expired (172 s after the stop, run 1; <=138 s in another run): HQ-PC1 to 192.0.2.200 and 198.51.100.10 100% loss, PROV-SRV1 to 192.0.2.130 100% loss, IPv6 from HQ-PC1/HQ-SRV1 to ISP-A OK.
- ISP-A drill with F3 present (`link stop` HQ-EDGE1 e0/0 - PROV-ISP1 e0/0): track 10 Down 17.9, 19.9, 20.6 s; EDGE1 default replaced by OSPF E2 metric 30 via EDGE2 14 s after the Down; users fail over but HQ-PC1 to 192.0.2.200 is 100% loss (EDGE2 NAT `icmp 192.0.2.65:1024 10.10.10.101:33 192.0.2.200`, translated to pool B, no return: F2); PROV-SRV1 to 192.0.2.130 lost; IPv6 lost (ISP-A is the IPv6 source); ISPA-EVIDENCE fired.
- ISP-A drill with the solution (EDGE1 SLA 198.51.100.1, F1-F3 fixed): see timings below; HQ-PC1 to 192.0.2.200 recovers on pool B with no residual loss.
- After F3 fix, with ISP-B down and F1/F2 still present, the portals pass through ISP-A's default once ISP-B's BGP routes expire (the T1 faults sit only on the ISP-B exit).
- Reload of both edges after `write memory` was **not run** in v1.2: the solved state was verified by the drills above, and the stored day-0 configs were checked on the re-imported lab. A node stop/start returns to the stored startup configuration, so unsaved fixes are lost (the reason R5 asks for a save).

## Failure / Recovery Behaviour

Method: silent failure (`link stop`/`link start`). Interface `shutdown`, cable pulls and the "reload both edges" test were not run for this lab. Clock: host `date -u` at the trigger against the EDGE1 syslog (router and host clocks agree). The probe grid is :00/:05, so the Down time is a fixed 5 s phase plus freq 5, timeout 5 and `delay down 5`.

| Scenario (trigger -> end condition) | Runs (raw values) | Documented range | Basis |
|---|---|---|---|
| ISP-A silent failure, F3 present: link stop -> track 10 Down | 17.9, 19.9, 20.6 s | 14-21 s | measured; derived 15 s + probe phase |
| ISP-A silent failure, solved: link stop -> track 10 Down | 14.6, 15.2 s (run 1 not clocked; earlier 19.8 s in the wrong-fix lab) | 14-21 s | measured, same mechanism |
| ISP-A silent failure, solved: link stop -> HQ-PC1 pings to 192.0.2.200 recover (pool B, no residual loss) | 13, 12, 13 lost pings (`ping -i 1`) | 12-14 lost pings | measured |
| ISP-A restored: link start -> track 10 Up (delay up 30) | 28-34 s (23-34 s polled); 35-37 s (2 more runs) | 28-40 s | measured; derived 30 s + probe phase + link-up settling |
| ISP-A restored: failback loss | 0 lost pings in 3 runs | 0 | measured |
| ISP-B silent failure, F3 present: link stop -> track 10 Down | 18.8 s | 14-21 s | measured once for this lab (a second drill gave the same signature) |
| ISP-B silent failure: link stop -> EDGE1 route to 203.0.113.1 (iBGP via EDGE2) gone | 172 s; <=138 s (poll) | 120-180 s | BGP hold 180 s counted from the last keepalive (derived bound 180 s) |
| ISP-B restored: link start -> track 20 Up (delay up 30), eBGP up | 30 s delay, eBGP in seconds | about 30-60 s | measured once, qualitative |
| Wrong fix (pinned target), PROV-ISP2 node stop -> track 10 Down | 12 s | 10-15 s | measured once |

Observations: OSPF type-5 default LSAs are flushed at the withdrawal (no MaxAge wait). With `link stop` the BGP-routed destinations behind the failed provider die only after the hold time, so ISP-B's networks (the supplier portals) recover through ISP-A after 120-180 s in the solved lab. IPv6 follows ISP-A's BGP `::/0` (untracked) and OSPFv3 from EDGE1, so it survives an ISP-B failure. Restore: link start returned every check to the steady state (re-run the start checks). Estimate: build 35+28+15 min, two drills about 7 min each, recovery and re-checks about 23 min, rounded to 120 min.

## Answers to Analysis Questions

**Q1.** T1: the traceroute follows the designed path and EDGE2 pings both portals, so policy and providers are not the cause; the first real evidence is EDGE2's NAT statistics and the empty translation table for HQ-PC1. T2: CORE1's missing IPv4 default with ::/0 present points at OSPFv2, but both adjacencies are FULL and the type-5 LSAs are absent because both ASBRs withdrew them; HSRP priorities match the design and show the track decrement; ISP-A is healthy but track 10 is Down, and the SLA target is ISP-B's loopback.
**Q2.** T1: after F1 alone the translation table fills but replies never arrive; ISP-B's looking glass has no 192.0.2.64/26 (F2). After F2 alone the /26 is announced but relayed traffic is still untranslated. T2: fixing F3 changes the drill (track 10 stays Up, EDGE1 stays Active, pool A, the default stays); the proof is the repeated drill plus unchanged HSRP and OSPF configuration.
**Q3.** The providers' looking glasses (`show ip bgp 192.0.2.64/26` on PROV-ISP2, the neighbour's routes), PROV-SRV1 reaching 192.0.2.130, and the ISP-B view of untranslated flows. They show what the provider receives and sends, which the edge's own tables cannot confirm.
**Q4.** EDGE2's own pings to the portals (source 203.0.113.65 is known to ISP-B), the healthy IP SLA 10 statistics in steady state (the probe works and measures the wrong path), the DMZ web server, HSRP 110 and every ISP-A drill all succeeded while users failed or the design was wrong. A router-sourced or single-provider test exercises neither NAT, the pool announcement, nor the other provider's failure.
**Q5.** Checklist: ping a portal from a user host and from EDGE2 with a pool source; `show ip nat statistics` roles on every inside-facing interface (including the inter-edge link); looking glass shows every announced prefix with the documented length (and `show ip route` has an exact match); `show ip sla configuration` target per edge and `traceroute <target> source <link interface>` leaves via its own provider; a silent-failure drill of each provider (track Down within 20 s only for ISP-A, evidence only for ISP-A, HSRP follows, ISP-B drill leaves users on ISP-A); save the config.
**Q6.** Track 10 depends on the SLA 10 path: the probe leaves EDGE1 over whichever route wins for the target, so an iBGP route via EDGE2 puts ISP-B in its path. HSRP depends on track 10. The core default depends on the tracked static plus the conditional OSPF origination. Proof: `show ip sla configuration`, `show ip route <target>`, `traceroute <target> source Ethernet0/0`, and a drill of the other provider's failure.

**Instructor debrief.**
- T2 never showed F1: the failover path (core to EDGE2 over e0/1) is still `ip nat inside`; only the EDGE1-to-EDGE2 relay on e0/3 is untranslated.
- No ISP-A test reveals F3: the probe's reply path dies with ISP-A, so it fails correctly; the evidence capture blames ISP-A because the same applet fires on any track 10 Down.
- IPv6 survived because `::/0` comes from ISP-A by BGP (untracked) and OSPFv3 originates from EDGE1.
- The core lost its default although OSPF was healthy because default origination is conditional on the (withdrawn) static.
- Announcing the /27 is a wrong fix (needs a POOL-B-OUT change and ISP-B then holds a /27); pinning ISP-B's loopback via ISP-A passes both silent drills but fails when PROV-ISP2 itself stops.
- Proving from outside that a prefix is (not) announced: `show ip bgp 192.0.2.64/26` on PROV-ISP2.
- EDGE2 reaches the portals when users cannot for two reasons: router-originated traffic uses 203.0.113.65, known to ISP-B, and it never crosses the e0/3 relay NAT gap.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-15 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), iol-xe (IOS XE 17.16.1a), unmanaged_switch |
