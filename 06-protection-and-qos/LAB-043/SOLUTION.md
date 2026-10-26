# LAB-043 — Solution

## Summary

Troubleshooting lab on environment EDGE E3 (15 nodes: the full edge, a stub HQ core, a lite data centre with DC-NMS1, DC-SW, IX and DMZ switches). Three independent faults, two tickets. T1 (drops every few minutes) is caused by a control-plane policing ACL with swapped source and destination (F1), made much worse and kept latent by an ordering error in HQ-EDGE2's edge ACL (F3). T2 (no flows from one edge) is a flow exporter in the right VRF that sends to the wrong UDP port (F2, v1.2: 9996 instead of the collector's 2055), so only receiver-side evidence closes it. Red herrings: BGP to ISP-A (uptime continuous), HSRP logs (consequence), OSPF (stable), the periodic ICMP bursts (a provider monitor at a modest rate).

Blueprint mapping (instructor only): 5.2.b CoPP (F1, T), 5.2.a edge ACL (F3, T), 4.2 Flexible NetFlow (F2, T), 4.4 object tracking and 3.2.c BGP (R). Domains in LAB.md: 3, 4, 5. Earlier modules revisited: tracking and HSRP (02/04), NAT (04), management VRF (05), LAB-042 (the build of this edge).

## Intentional Faults

| ID | Device | Change | Symptom |
|---|---|---|---|
| F1 | HQ-EDGE1 | ACL `CP-MONITOR` (CoPP class CM-MONITOR) holds `permit icmp host 198.51.100.65 host 198.51.100.1 echo-reply` (source and destination swapped) instead of `permit icmp host 198.51.100.1 host 198.51.100.65 echo-reply` | Probe replies from 198.51.100.1 do not match CM-MONITOR and fall into CM-ICMP (cir 8 kb/s, bc 1500). PROV-SRV1's background bursts (three parallel `ping -q -i 0.01 -s 0 -w 25` to 198.51.100.65, first 120 s after its boot, then every 145 s) exceed CM-ICMP, replies are dropped, track 10 goes Down after the SLA timeout and `delay down 5`, the default and the HSRP active role move to EDGE2 (new PAT pool: sessions break); 50 s after each burst track 10 is Up again (30 s delay up). T1 |
| F2 | HQ-EDGE2 | `flow exporter FE-NMS` keeps `destination 10.50.50.60 vrf MGMT`, `source Ethernet0/1.99` and the 60 s template timeout but has `transport udp 9996` instead of `transport udp 2055` (EDGE1's exporter is unchanged on 2055) | The records leave in VRF MGMT from 10.10.254.9 and reach DC-NMS1 (`Successfully sent` grows, CEF in VRF MGMT correct, CoPP counters 0), but on UDP 9996, where nothing consumes them: the collector on 2055 sees only EDGE1. T2 |
| F3 | HQ-EDGE2 | in `EDGE-IN-V4`, `130 deny icmp any host 203.0.113.65 echo-reply log` sits before `140 permit icmp host 203.0.113.1 host 203.0.113.65 echo-reply` | EDGE2's probe replies are denied: track 20 Down since boot, EDGE2 originates no default (no backup default in OSPF), BGP unaffected. Latent in steady state; with F1 present it turns every flap into a total Internet outage (EDGE1's default withdrawn, none from EDGE2) and fails V2 on the ISP-A pull |

Fault logic: F1 is the cause of the flapping; F3 adds severity (with it a flap means no default at all) and is latent for redundancy: fixing only F1 stops the flaps (T1 closes) but the ISP-A cable pull then loses everything. Fixing only F3 leaves the flaps but shortens them (users shift to ISP-B). F2 is independent of both.

## Diagnosis / Methodology

1. **T1: where do the drops happen?** From HQ-PC1, `ping -c 200 -i 1 192.0.2.200` shows loss in blocks of about 50 s every 145 s. On HQ-CORE1 `show ip route 0.0.0.0` changes in step (EDGE1 metric 10 gone, EDGE2 metric 30 or nothing).
2. **Rule out BGP/ISP-A.** `show bgp ipv4 unicast summary` on EDGE1: uptime continuous (00:20:51 at 20:10 in the build, across seven flaps), prefix counts constant. OSPF neighbours stable.
3. **Tracking.** `show logging | include TRACK` on EDGE1: `Up->Down` at 19:52:46, 19:55:11, 19:57:36, 20:00:01, 20:02:26, 20:04:51 (every 145 s), each `Down->Up` 50 s later; `show track 10` change count grows; HSRP goes Active->Speak->Standby with each Down (consequence, not cause). A manual `ping 198.51.100.1 source Ethernet0/0` between bursts works, so something drops the replies during bursts.
4. **Who drops the replies?** `show policy-map control-plane` on EDGE1: CM-MONITOR `exceeded 0` and frozen counters, CM-ICMP `exceeded 2502` after the first burst and rising with each burst. The probe replies are not in CM-MONITOR: `show ip access-lists CP-MONITOR` shows the entry with source and destination swapped (and `10 permit ... (10 matches)` counting the wrong direction after the fix). Flow cache on e0/0 (or a capture) shows the bursts from 192.0.2.200.
5. **Ruled out as the cause.** The edge ACL on EDGE1: the probe-reply line counts and nothing is denied for 198.51.100.1. The bursts (three pings at about 100 pps each, 28-byte packets (no payload), for 25 s) are policed by CM-ICMP with or without the fault: its exceeded counter keeps rising after the fix. The fault puts the probe replies into the same class, so they are dropped with the burst.
6. **EDGE2 (found while checking the backup path, or by V2):** `show track 20` Down since boot (SLA Timeout, 0 successes); `show ip access-lists EDGE-IN-V4`: `130 deny icmp any host 203.0.113.65 echo-reply log` has matches, `140 permit ... 203.0.113.1 ...` has none. `show ip route 0.0.0.0` on EDGE2 shows no static default; the core's default comes from EDGE1 only.
7. **T2.** On DC-NMS1 the sample with `-f "udp port 2055"` shows source 10.10.254.5 only. Eliminate the collector (EDGE1's flows arrive) and the management path (`ping vrf MGMT 10.50.50.60 source Ethernet0/1.99` and SNMP from NMS1 work). Then the 038 recall check, which passes: `show flow exporter FE-NMS` on EDGE2 shows `VRF label: MGMT`, `Source IP address: 10.10.254.9`, `Successfully sent` growing (4 at 1.5 min after boot, 14 at 4 min; 24 at 6 min in the 1a run), `show ip cef vrf MGMT 10.50.50.60` = `10.50.50.0/24 nexthop 10.10.254.8 Ethernet0/1.99`: the sender is correct, so re-entering `destination ... vrf MGMT` changes nothing. Receiver side: on DC-NMS1 a capture not limited to the collector port, `tshark -i eth0 -a duration:70 -f "host 10.10.254.9 or host 10.10.254.5"`, shows 10.10.254.9 -> UDP 9996 (CFLOW, 4 packets per 70 s) next to 10.10.254.5 -> 2055 (3 per 70 s). NMS1 answers ICMP port unreachable for both edges (nothing listens on 2055 either), so that is not a discriminator, and EDGE2's CoPP `exceeded` stays 0 in every class (the export is transit via Ethernet0/1.99, not punted). `Destination Port: 9996` on EDGE2 against 2055 on EDGE1 and the documented collector port: **F2**. Note: without the `-f` filter, `tshark` decodes 9996 as CFLOW by default and lists 10.10.254.9 too, which is why LAB.md's sample command carries `-f "udp port 2055"`.

**Wrong fixes tried once each (all shown to fail a V item, CML run; times UTC). (a)-(c) are from the v1.0 build (unchanged F1/F3 configs); (d) from the v1.2 build.**

| Wrong fix | Result | Fails |
|---|---|---|
| (a) raise CM-ICMP to `cir 128000 bc 16000` on EDGE1 (F1 present) | no track change over three bursts (20:49 to 20:56), CM-ICMP exceeded frozen at 119905; but `hostile.sh flood` answers 628 of 3813 pings (34 of 3816 with the right fix) and ten parallel small-packet pings take track 10 Down within 12 s | V3 (the `swarm` part) and V5 |
| (b) remove CoPP (`no service-policy input PM-COPP`) | flaps stop; flood 2164 of 3819 answered (34 of 3816 with CoPP), `show policy-map control-plane` empty | V3, V5 (042 R3 violated) |
| (c) `delay down 30` on track 10 | silent failure of ISP-A: TRACK Down +34.3 s (documented 15-25 s); no track change in a window that contained a 25 s burst (flaps hidden) | V2 timing |
| (d) `no transport udp 9996` on EDGE2 | the exporter falls back to the IOS XE default port: `show flow exporter FE-NMS` `Destination Port: 9995` (running-config shows no transport line; the iol-xe 17.16.1a default is 9995, not 2055). DC-NMS1 `-f "host 10.10.254.9 and udp"`, 70 s: 3 packets 10.10.254.9 -> 9995; the `-f "udp port 2055"` sample still lists only 10.10.254.5 | V4 |

**Accepted alternative (not a wrong fix):** deleting `130 deny icmp any host 203.0.113.65 echo-reply log` on EDGE2 instead of re-ordering. Line 130 only logs and counts echo-replies; with it removed, unsolicited echo-replies to the router are still denied by `deny ip any host 203.0.113.65 log` and the probe replies match the permit, so track 20 recovers exactly as with re-ordering; V5 does not fail. The difference is the lost deny logging for that traffic (derived from the ACL; not separately run, the re-ordering fix was run). Grade both as correct; ask the student to say what the line was for.

## Solution Configuration

As applied (v1.2):

```
HQ-EDGE1 (F1)
ip access-list extended CP-MONITOR
 no permit icmp host 198.51.100.65 host 198.51.100.1 echo-reply
 permit icmp host 198.51.100.1 host 198.51.100.65 echo-reply

HQ-EDGE2 (F3)
ip access-list extended EDGE-IN-V4
 no 130
 145 deny icmp any host 203.0.113.65 echo-reply log

HQ-EDGE2 (F2)
flow exporter FE-NMS
 transport udp 2055
```

The exporter change is accepted live (no need to remove the exporter from the monitor). Not saved to NVRAM in the lab: the exported YAML holds the start state.

## Verification

Causality. The F1-only / F3-only drill and the wrong fixes (a)-(c) are carried over from v1.0 evidence (F1 and F3 configs unchanged in v1.2); the v1.2 rebuild re-proved the F3 -> F1 -> F2 order and F2:

- v1.0, F3 only (20:02:44): track 20 Up at 20:03:25 (+41 s); flaps continue on the same 145 s cycle; HQ-PC1 200 s ping 12% loss (2 flaps) against 44% in the start state. F1 fixed in addition (20:06:45): no track change afterwards (CM-ICMP exceeded 52164, CM-MONITOR exceeded 0), 0% loss. F1 fixed with F3 latent (V2 fails): ISP-A cable pull, TRACK Down +7.8 s, **HQ-PC1 1 of 90 pings answered**; with F3 fixed, 0 of 90 lost.
- v1.2, F3 fix alone (00:45:55 UTC): track 20 Down -> Up after 44 s; track 10 flaps continue on the 145 s cycle (Down 00:44:16, next 00:46:41). F1 fix at 00:46:56: no track 10 change afterwards (14 changes in total, last change 6-8 min old at 00:53 and 00:55) over two bursts; HQ-PC1 -> 192.0.2.200: 371 sent, 0 lost over 00:47-00:53.
- F2: `transport udp 2055` accepted live; `show flow exporter FE-NMS` `Destination Port: 2055`; the 70 s `-f "udp port 2055"` sample lists 10.10.254.9 (at 0, 21, 36, 46 s) and 10.10.254.5 (six packets): both sources within 1 s of the change (data records every few seconds; templates at the 60 s timeout). `show track 20` still Down and CoPP exceeded 0 at that point: F2 is independent of F1 and F3. EDGE2 `Successfully sent` 102 at the end of the run.

End state (v1.2, all three fixes): `hostile.sh all`: probes `rc=1` x5, spoof 100% loss, web request ok, flood 3809 sent / 39 answered (98% loss), swarm done; EDGE1 track 10 14 changes before and after, EDGE2 track 20 2 changes before and after; BGP uptimes continuing (EDGE1 00:22:24 -> 00:24:19 for ISP-A, EDGE2 ISP-B 00:22:18 -> 00:24:13); HSRP Et0/2 Active unchanged; CM-MONITOR exceeded 0, CM-ICMP exceeded 52169 -> 91612; `CP-MONITOR 10 permit icmp host 198.51.100.1 host 198.51.100.65 echo-reply (111 matches)`; EDGE2 `140 permit ... (260 matches)`, `145 deny ... echo-reply log`.

Start-state evidence (fresh import of the YAML, 15 nodes BOOTED in 82 s; boot +5 min): EDGE2 exporter `VRF label: MGMT`, source 10.10.254.9, `Destination Port: 9996`, CEF in VRF MGMT via 10.10.254.8 Ethernet0/1.99, `Successfully sent` 14; track 20 Down, `130 deny` 26 matches before `140 permit`; EDGE1 track 10 4 changes, exporter port 2055; HQ-PC1 30% loss over 60 pings; DC-NMS1 `-f "udp port 2055"` sample only 10.10.254.5.

## Failure / Recovery Behaviour

All drills with all three faults fixed; times from the device log (UTC, one clock). HQ-PC1 pings 192.0.2.200 at 1/s.

| Scenario (trigger -> end condition) | Runs (raw) | Documented range | Basis |
|---|---|---|---|
| ISP-A cable pull (`shutdown` both ends): `%LINK-5-CHANGED` on EDGE1 e0/0 -> `TRACK 10 Up->Down` | 10.0, 11.7, 10.6 s | 7-15 s | link-down event drives the tracked static route and the SLA/`delay down 5` |
| same: HQ-PC1 pings lost (1/s, across three pulls and restores) | 0 of 369 | 0-2 | tracked default leaves with the interface at once; the core uses EDGE2's OSPF default; ping has no NAT state to break |
| ISP-A `no shutdown` on both ends -> HSRP Standby->Active on EDGE1 | 56, 51, 51 s (track 10 Down->Up 60 s after the Down) | 30-60 s | track delay up 30 s plus SLA period, counted from the link coming back |
| ISP-B cable pull: `%LINK-5-CHANGED` on EDGE2 e0/0 -> `TRACK 20 Up->Down` | 9.4, 11.3, 10.2, 11.6 s | 7-15 s | as above; user traffic unaffected (0 lost, 659 pings) |
| ISP-B `no shutdown` on both ends -> `show track 20` Up | 41, 50, 50 s | 20-60 s | delay up 30 s plus SLA period (log Down->Up 50-60 s after the Down) |
| ISP-A silent failure (`link stop`, host clock) -> `TRACK 10 Up->Down` | 19.5, 20.2, 16.7 s | 15-25 s | 5 s SLA period x timeout + `delay down 5`; eBGP stays Up (hold time 180 s); host clock vs NTP-synced device clock, skew about 1 s |
| same: HQ-PC1 pings lost (1/s, until the gap closes) | 19, 19, 16 | 12-25 | detection time plus convergence |
| ISP-A `link start` -> HSRP Standby->Active on EDGE1 | 37.1, 38.0, 45.0 s (track Down->Up 36.1, 37.0, 44.0 s after the start) | 30-60 s | track delay up 30 s plus SLA period |
| F3 fix on EDGE2 (ACL re-order) -> `show track 20` Down->Up | 44 s (one run) | 30-60 s | delay up 30 s plus SLA period |
| Start-state T1 cycle: first Down about 3 min after boot, then every 145 s, Down 50 s | v1.0: six flaps 19:52:46 to 20:04:51; v1.2: Down 00:44:16, 00:46:41 | 140-150 s cycle | burst 25 s + sleep 120 s; Down = burst + SLA timeout + 5 s + 30 s up |

The v1.2 rebuild re-measured the drills with the F2 change in place: the values lie in the v1.0 documented ranges, so F2 does not alter any timing (the ranges are unchanged; the v1.0 runs were 11.1-12.6 s pull, 16.3-19.9 s silent, 15-19 lost).

Stopping the CML link does not take the IOL port down; the silent-failure drills use it on purpose, the cable pulls use `shutdown` on both ends.

## Answers to Analysis Questions

**Q1.** T1: BGP to ISP-A was the obvious suspect; its uptime spans many flaps and the prefix counts are constant, so it is eliminated. The next suspects (OSPF, HSRP) are consequences: OSPF is stable and HSRP moves only because track 10 decrements priority. T2: the collector, the management path and the exporter's VRF (the pattern from LAB-038) are the obvious suspects; flows from EDGE1 arrive, `ping vrf MGMT` / SNMP from NMS1 work, and `show flow exporter` shows `VRF label: MGMT`, source 10.10.254.9 and a growing `Successfully sent`, with CEF in VRF MGMT correct.
**Q2.** T1: `show policy-map control-plane` on the edge nearest the provider: CM-MONITOR frozen at 0, CM-ICMP exceeded rising in step with each burst; `show ip access-lists CP-MONITOR` shows the entry matches the wrong direction. T2 (nothing is dropped; the records are delivered but not consumed): the sender's statistics and `show ip cef vrf MGMT` prove correct sending; the receiver-side capture on DC-NMS1 without the collector-port filter shows the packets arriving from 10.10.254.9 on UDP 9996; `show flow exporter FE-NMS` `Destination Port: 9996` against the documented 2055 and EDGE1's exporter locates the defect in the exporter's transport port. Lesson: compare sender and receiver evidence; a filter on the expected port hides traffic on the wrong one.
**Q3.** F1 changed the user experience (the flaps). F3 changed no steady-state user experience at all but shortened the outage per flap and, mainly, restored the backup path: it is found by checking EDGE2's track (Down since boot) or by the ISP-A cable-pull drill (98% loss with only F1 fixed). F2 (the exporter port) restored visibility only. The drill, not the steady state, shows that redundancy is real.
**Q4.** Alarm on track state changes (SNMP trap/syslog `TRACK-6-STATE`) and on their rate; alert on a track that has been Down since boot; CoPP exceed-counter trend per class (SNMP CISCO-CLASS-BASED-QOS-MIB); an expected-sources check on the flow collector (one edge silent for 10 minutes); an ACL deny-log baseline for the probe addresses.
**Q5.** After any change to the edge protection policy: (1) both tracks Up, change counts static for 10 minutes; (2) `hostile.sh all` with no track/BGP/OSPF change and the flood/swarm answered at a small fraction; (3) probe replies counted in the monitoring class, ICMP class counters rise only for hostile traffic; (4) both edges' ACLs: probe replies permitted before any deny, spoof and probe tests as in LAB-042; (5) flows from both edges at the collector; (6) cable pull and silent failure of each provider, PC1 ping loss against the documented table; (7) NAT, HSRP and BGP sessions (both AFs) unchanged; (8) diff of the running configuration against the approved change.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-25 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), iol-xe (IOS XE 17.16.1a), net-tools, radius, syslog, unmanaged_switch |
