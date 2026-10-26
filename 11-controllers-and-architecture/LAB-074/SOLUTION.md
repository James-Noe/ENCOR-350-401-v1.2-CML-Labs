# LAB-074 — Solution

## Summary

Type A, G1. Blueprint: 1.2.b (SD-WAN control and data plane: OMP, TLOCs, BFD, AAR; analysed from the derived pack), 1.2.a (controller-based vs traditional design, analysed and compared), 3.2.d (policy-based routing with `verify-availability` and object tracking, built and measured), 4.4 (IP SLA, tracking and the limits of sampled probes). Students read vendor reference outputs, measure today's dual-transport WAN under CML link conditioning, extend the probes to track round-trip time on both routers, time the move and the return, and write a recommendation.

Platform caveats for the documents:
- SD-WAN edges do not onboard on this CML server, so every SD-WAN edge output in LAB.md is a `(derived)` fixture. Format and fields follow the Cisco Catalyst SD-WAN command reference entries for `show sdwan omp routes`, `show sdwan omp tlocs`, `show sdwan bfd sessions`, `show sdwan app-route stats` and `show sdwan policy from-vsmart`, and the Application-Aware Routing section of the Cisco Catalyst SD-WAN Policies configuration guide (SLA class, preferred-color, no strict). Values (addresses, latency, uptime) are invented for the exercise. Outputs from the IOS routers below are captured live.
- CML link conditioning applies per direction: 200 ms set on the link gave an SLA round trip of 403-404 ms. LAB.md says so where it describes the delay.
- The conditioned link is `BR1-RTR1-Ethernet0/1<->PROV-PE1-Ethernet0/1` (UI Conditioning, or REST `PATCH /labs/{lab}/links/{link}/condition` with `{"latency":200,"enabled":true}` and `DELETE` to remove).
- Hosts: non-EF ping rides the tunnel (about 69 ms) whatever is on the provider line. EF traceroute shows the path; its RTTs jump at hop 3 because the reply of 100.64.10.1 is sourced from the provider link and is not EF, so it returns through the tunnel (35 ms with no conditioning at all). Students use end-to-end RTT, not per-hop RTT.
- Failure method: conditioning is neither a link stop nor a shutdown. There is no interface failure in this lab. The "dead probe target" of Q4 is analysed, not measured (derived).

## Intentional Faults

None (Type A analysis lab). The one trap built into the start state is a design property, not a fault: SLA 30 on BR1-RTR1 and SLA 31 on HQ-WAN1 have `threshold 1000 timeout 1000`, and tracks 30/31 are `reachability`, which treats an over-threshold echo as success. Lowering the threshold alone changes nothing.

## Diagnosis / Methodology

R1 (derived pack). TLOCs of DEP21: three sites, two colours each, IPsec. Routes to 10.10.0.0/16: two OMP routes (C,I,R) with next-hop TLOCs 10.255.10.1 mpls and biz-internet. BFD: four sessions up (HQ and DEP22, each on both colours), transitions 0. Normal statistics: mpls 0 % / 22 ms / 2 ms, biz-internet 0 % / 48 ms / 6 ms; both meet VOICE-SLA (loss 2 %, latency 150 ms, jitter 30 ms), so voice uses the preferred colour mpls. After the capture mpls shows 6 % loss, 310 ms, 45 ms jitter: it fails all three limits, and voice moves to biz-internet, which still meets the class. Without `strict`, traffic for which no tunnel meets the SLA class is not dropped: it is forwarded over the available tunnels by normal routing (load-shared), and `backup-sla-preferred-color` (in newer releases `fallback-to-best-path`) chooses the path in that case; with `strict` that traffic is dropped (derived: Cisco Catalyst SD-WAN Policies Configuration Guide, Application-Aware Routing, SLA class action). The answer to R1 does not depend on it: biz-internet still meets VOICE-SLA.

R2 (today's WAN, measured). Start state: EF `traceroute -n -t 184` BR1-PC1 to HQ-PC1 via 10.21.10.1, 100.64.21.0, 100.64.10.1, 10.10.255.96; reverse via 10.10.10.1, 10.10.255.97, 100.64.10.0, 100.64.21.1; route-map counters count the EF packets (BR1 15, HQ-WAN1 12 after the test traceroutes). Delay: the SLA saw 403-404 ms round trip (200 ms per direction), track stayed Up because `reachability` ignores the 1000 ms threshold, voice stayed on the line; the non-EF ping is unchanged. Loss at 5 %: the track outcome is probabilistic (see timings): sometimes no transition, sometimes a Down/Up cycle; voice lost 4.6-5.1 %. The probe is one echo every 5 s with a 1 s timeout; at 5 % loss in each direction about 10 % of echoes fail (7 of 92 and 13 of 89 in the hourly statistics), so a single failed echo is usually followed by a successful one before `delay down 5` expires and the track stays Up, but two consecutive failures (about 1 % per period) are enough for a Down/Up cycle.

R3. The solution recreates the probe with a threshold and makes the track follow the operation's state rather than its reachability. Order matters on each router: remove the schedule, remove the operation (a running IP SLA cannot be modified), re-create it with `threshold 150`, schedule it, then set `track N ip sla N state`. IOS accepts the new track type over the existing track in place, and the PBR reference to the track is kept. Both routers must be changed: if only BR1 is, the return direction (HQ-WAN1 to BR1) stays on the degraded line.

Plausible but wrong: lowering only the threshold (track stays `reachability`, never Down on a slow echo, shown in the 200 ms run); a lower `timeout` instead of a threshold (that turns slow echoes into timeouts, but needs `reachability` semantics plus a timeout below the delay; not tested, it would also make loss flap the track); tuning `delay down` (at 5 % loss with a single echo per period it would only make the track flap randomly, not tracking RTT).

Limits still left, for the R3 list: one sampled ICMP echo per 5 s per router, one path (provider line) measured, no loss/jitter measurement for voice, decision per router and per direction (no coordination: each side decides separately), no automatic selection among more than two paths, no per-application SLA other than the single EF match, nothing for the Internet tunnel's quality.

## Solution Configuration

BR1-RTR1:
```
no ip sla schedule 30
no ip sla 30
ip sla 30
 icmp-echo 100.64.10.1 source-interface Ethernet0/1
 threshold 150
 timeout 1000
 frequency 5
ip sla schedule 30 life forever start-time now
track 30 ip sla 30 state
 delay down 5 up 30
```
HQ-WAN1:
```
no ip sla schedule 31
no ip sla 31
ip sla 31
 icmp-echo 100.64.21.1 source-interface Ethernet0/1
 threshold 150
 timeout 1000
 frequency 5
ip sla schedule 31 life forever start-time now
track 31 ip sla 31 state
 delay down 5 up 30
```
Result seen on both routers: `show track` reports "IP SLA N state ... Delay up 30 secs, down 5 secs".

## Verification

Start state (captured on a fresh import of the YAML):
```
BR1-RTR1: Reachability is Up (track 30); OSPF FULL on Tunnel21/41/91
          Policy routing matches: 15 packets, 900 bytes (after the EF traceroute)
HQ-WAN1:  Reachability is Up (track 31); FULL: Ethernet0/2, Ethernet0/2.99, Tunnel21/41/91
          Policy routing matches: 12 packets, 720 bytes
BR1-PC1:  traceroute -n -t 184 10.10.10.101: 10.21.10.1, 100.64.21.0, 100.64.10.1, 10.10.255.96, 10.10.10.101
HQ-PC1:   traceroute -n -t 184 10.21.10.101: 10.10.10.1, 10.10.255.97, 100.64.10.0, 100.64.21.1, 10.21.10.101
BR1-PC1:  ping 10.10.10.101: 0 % loss, 69-74 ms (via Tunnel21)
```
With the solution and 200 ms applied: both tracks Down; EF traceroute BR1-PC1 to HQ-PC1 via 10.250.21.1 (Tunnel21) and HQ-PC1 to BR1-PC1 via 10.250.21.21; ping RTT unchanged (about 69 ms). With the original probe and 200 ms: SLA RTT 403-404 ms, track Up. Voice, solution config, 200 ms set at 0 s, 120 s of EF 64 kb/s: 10 of 6003 lost (0.17 %, equal to the 0.2 % of the Internet link) and 8 datagrams out of order at the move; no burst loss.

## Failure / Recovery Behaviour

Conditioning is applied and removed through the CML REST API; clock: the automation host (UTC), router `show clock` agreed within 1 s. T0 is just before the PATCH or DELETE, the end condition is the TRACK state-change syslog time on the router.

| Scenario (trigger, end condition) | Runs (raw) | Documented range | Basis |
|---|---|---|---|
| Move, solution config: 200 ms set on BR1-PE1 link until track Down, BR1 | 15.4, 12.5, 11.6 s | 5-16 s | next echo within 0-5 s, `delay down 5`, up to one more echo period (derived from timers) |
| Move, HQ-WAN1 track 31 Down | 14.6, 11.8, 15.8 s | 5-16 s | same |
| Return: conditioning removed until track Up, BR1 | 32.1, 34.0, 33.1 s | 30-36 s | `delay up 30` plus next echo 0-5 s |
| Return, HQ-WAN1 | 31.3, 33.2, 32.3 s | 30-36 s | same |
| Voice loss in a 300 s window, original probe, 5 % loss on the provider link (3 runs) | 754, 730, 770 of 15003 (5.0, 4.9, 5.1 %) | 4.9-5.1 % | the link's own loss; build: 0 track transitions in 3 of 3 runs (changes 12 to 12); validation: 0/0, 0/0 and 2/0 (BR1/HQ-WAN1; run 3 track 30 Down then Up 35 s later), voice loss 4.6-5.1 % |
| Same with the solution probe (1 run) | 746 of 15003 (5.0 %), build: transitions 0 (20 to 20); validation: BR1 0, HQ-WAN1 one Down/Up cycle (5.1 %) | about 5 % | loss and delay need different probes |

Restore: BR1-RTR1 and HQ-WAN1 were wiped and restarted, conditioning removed; start checks identical to the start state.

## Answers to Analysis Questions

**Q1.** Under delay the probe measured 403-404 ms round trip (200 ms per direction) but the track stayed Up: the operation has `threshold 1000` and the track is `reachability`, which does not look at the threshold, so the voice stayed on the slow line. Under 5 % loss the probe lost 7 of 92 (BR1) and 13 of 89 (HQ-WAN1) echoes in the hourly statistics, yet the transitions varied: 0 in 3 of 3 build runs, 0/0/2 (BR1) and 0 (HQ-WAN1) in the validation runs, plus one HQ-WAN1 cycle with the solution probe. A reachability probe sends one echo per 5 s, so it is a sample of one; steady random loss sits right at its limits: usually a failure is followed by a success before `delay down 5` elapses (no transition), but two consecutive failures (about 1 % per period) take the track Down and `delay up 30` brings it back, a flap. The signal is unreliable either way: a student's run may show none or a cycle, and both are correct observations. Design lesson: an SLA probe with a reachability track suits dead or alive, not quality; thresholds on single echoes cannot judge loss, which is why SD-WAN application-aware routing measures loss, latency and jitter continuously per tunnel (BFD) against an SLA class and steers per application. The voice stayed on the degraded line (when the track did not flap) and lost 4.6-5.1 % of its packets, the whole 5 %. The probe also measures a different thing from the voice (ICMP, one packet).

**Q2.** BFD runs on every tunnel (each colour pair), at one-second intervals (multiplier 7), and reports loss, latency and jitter per path, continuously, whether or not user traffic uses the path, and in the same form for all sites. The ICMP probe measures one path of a router, one packet per 5 s, a single round-trip value with no jitter or loss statistics.

**Q3.** Today: in every router, from its own probe and its own route-map; each depot and the hub decide separately and per direction, 50 depots mean 50 configurations of probes, tracks and route-maps (and 50 hub counterparts), changed by hand. SD-WAN: one central policy (VOICE-AAR, SLA class) written once on the controller and sent to the edges, which measure with BFD and execute it in their data plane. Fifty depots mean one policy and a site list.

**Q4.** Today: a dead SLA target makes the track Down after `delay down 5`; `verify-availability` then drops the policy next hop and forwarding falls back to the routing table (the tunnel), voice continues on the Internet path but loses the provider line even though the line may be fine (a false Down); a dead probe responder is therefore a path failure for voice. SD-WAN: with the controllers down, the edges keep the last policy and the OMP routes for the graceful-restart period and keep forwarding and measuring with BFD (derived from the Cisco documentation; the controller-stop observations are those of LAB-073): existing traffic and AAR continue, but there are no new policy changes, onboarding or route updates until the controllers return.

**Q5.**

| | PBR with tracked probe | AAR with BFD |
|---|---|---|
| Measures | one ICMP echo (RTT and success) | loss, latency, jitter from BFD packets |
| Frequency | every 5 s (our config) | every second, aggregated per poll interval |
| Per | one router, one target, one path | every tunnel (colour pair) between every pair of sites |
| Where decided | each router, own route-map | central policy, executed by each edge |
| Reaction | track Down after `delay down` (5-16 s), back after 30-36 s | SLA class evaluated per tunnel and application |
| Cost | many hand configurations, one SLA per path and direction | controllers, licences, skills, migration effort |

Our threshold probe measures round-trip time of a single echo against 150 ms and acts only on that; BFD per tunnel measures all three SLA metrics.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-17 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), iol-xe (IOS XE 17.16.1a) |
