# LAB-026 — Solution

## Summary

Educational intent: measure a path (IP SLA `icmp-echo`, `udp-jitter` with `ip sla responder`), turn the result into object tracks (`reachability` vs `state`, `delay up`), and make a static default and the HSRP active role follow them, with the probe pinned so it tests only the path under test. Blueprint: 4.4:I (IP SLA, tracking) and 3.3.c:R (HSRP). Not a troubleshooting lab: no intentional faults.

Build notes: (1) On iol-xe a `udp-jitter` SLA with `threshold` does not flip a `state` track when RTT exceeds the threshold (observed `Number Of RTT Over Threshold: 10 (100%)`, return code OK, track 2 stays Up). SLA 3 (`icmp-echo` with `threshold 100`, track 3 `state`) was added and flips Down on RTT over threshold; track 2 (udp-jitter, `state`) flips only on failure (proven with an ACL on R3 dropping UDP 1967: track 2 Up -> Down, track 1 stays Up); track 4 (`list boolean or` of 1 and 2) was added. (2) The lab runs 9 licensed nodes (the two unmanaged switches count). Also: HSRP timers are default (3/10 s); the SLA `threshold` must be <= `timeout` (`timeout 2000` with the default threshold 5000 is rejected at `ip sla schedule`).

## Intentional Faults

None (foundation lab). Starting state: R1 HSRP active 110 with preempt, untracked; R1 default via R3 plus floating default via R4 (AD 5); R2 default via R4; no SLA or track on R1/R2; R3/R4 providers with responders and tracked return routes.

## Diagnosis / Methodology

Not applicable; the working method is: (1) measure (SLA 1, target pinned), (2) track, (3) attach the track to the static default and to `standby 10 track`, (4) test with each failure method and read `show track`, `show ip sla statistics`, `show standby brief` and the log lines in sequence.

Why the pins: the Internet LAN lets R1 reach 10.0.100.3 through R4 as well, so an unpinned probe would keep succeeding after R1–R3 fails. The Null0 /32 (AD 250) is insurance for the cable pull, when the pinned route disappears. On this bench the probe leaked via R4 (traceroute hop 10.0.14.4) when the Null0 route was removed, yet track 1 still went Down because R3 then had no route back to 10.0.14.1; so Null0 is insurance here, not the sole guard.

## Solution Configuration

R1 (all as tested):

```
ip route 10.0.100.3 255.255.255.255 Ethernet0/0 10.0.13.3
ip route 10.0.100.3 255.255.255.255 Null0 250
ip sla 1
 icmp-echo 10.0.100.3
 frequency 5
 timeout 2000
 threshold 1000
ip sla schedule 1 life forever start-time now
track 1 ip sla 1 reachability
 delay up 30
no ip route 0.0.0.0 0.0.0.0 10.0.13.3
ip route 0.0.0.0 0.0.0.0 10.0.13.3 track 1
interface Ethernet0/2
 standby 10 track 1 decrement 20
! requirement 4 and 5
ip sla 2
 udp-jitter 10.0.100.3 5000 num-packets 10 interval 20
 frequency 10
 timeout 2000
 threshold 100
ip sla schedule 2 life forever start-time now
track 2 ip sla 2 state
ip sla 3
 icmp-echo 10.0.100.3
 frequency 5
 timeout 1000
 threshold 100
ip sla schedule 3 life forever start-time now
track 3 ip sla 3 state
track 4 list boolean or
 object 1
 object 2
```

R2, R3, R4, PC1, PC2, SRV1: no change (R3 and R4 already have `ip sla responder`). The floating default via R4 (AD 5) is already present on R1. The HSRP decrement of 20 takes R1 from 110 to 90, below R2's 100, and preempt returns the role. Link conditioning: CML GUI, link R1 e0/0 – R3 e0/0, latency 100 ms (per direction).

Requirement 6 (pitfall): on R1 `ip route 10.0.100.200 255.255.255.255 10.0.13.3`, SLA target SRV1, and `no standby 10 track 1`; silent failure; then restore.

## Verification

Observed on the bench (values from the build session; lines below are paraphrased from build observations, not captured output, and are marked `(derived from build observations)`):

- (derived from build observations) Healthy: SLA 1 RTT 1–2 ms OK, track 1 Up, R1 default via 10.0.13.3, `show standby brief` R1 Active 90→110 when Up. With 100 ms conditioning, RTT 202–203 ms: SLA 1 (threshold 1000) and track 1 stay Up; SLA 3 returns "Over threshold" and track 3 goes Down; both clear after conditioning is removed. Track 1 after config starts Down for the `delay up 30` interval, then `%TRACK-6-STATE: 1 ip sla 1 reachability Down -> Up`.
- (derived from build observations) SLA 2 under conditioning: `Number Of RTT Over Threshold: 10 (100%)`, return code OK, track 2 stays Up (the platform limit above).
- Captured (trimmed; one run each), healthy after the 30 s `delay up`:

```
R1#show ip sla statistics 1
        Latest RTT: 2 milliseconds
Latest operation return code: OK
R1#show ip sla statistics 3
        Latest RTT: 2 milliseconds
Latest operation return code: OK
R1#show track brief
1     ip sla      1                          reachability     Up    00:03:48
2     ip sla      2                          state            Up    00:03:43
3     ip sla      3                          state            Up    00:03:46
4     list                                   boolean          Up    00:03:45
R1#show standby brief
Et0/2       10   110 P Active  local           10.0.10.3       10.0.10.1
```

  First convergence log (track 1 and 3 initial lines were not captured; track 1 comes Up about 30 s after the config because of `delay up 30`): `%TRACK-6-STATE: 2 ip sla 2 state Down -> Up`, then `%TRACK-6-STATE: 4 list boolean or Down -> Up`.

- Under 100 ms latency on R1 e0/0 - R3 e0/0 (read about 100 s after setting). Tracks 2 and 4 stay Up (SLA 2 reports over-threshold but its return code stays OK, see the platform limit above):

```
R1#show ip sla statistics 1
        Latest RTT: 203 milliseconds
Latest operation return code: OK
R1#show ip sla statistics 3
        Latest RTT: 205 milliseconds
Latest operation return code: Over threshold
R1#show track brief
1     ip sla      1                          reachability     Up    00:05:48
2     ip sla      2                          state            Up    00:05:43
3     ip sla      3                          state            Down  00:01:43
4     list                                   boolean          Up    00:05:45
R1#show standby brief
Et0/2       10   110 P Active  local           10.0.10.3       10.0.10.1
```

  Log: `%TRACK-6-STATE: 3 ip sla 3 state Up -> Down`. Only track 3 flips: its threshold (100 ms) is below the RTT and `state` follows "Over threshold"; track 1 is `reachability` with threshold 1000 ms, track 2 never reacts to a threshold on this platform, and track 4 (`or`) needs tracks 1 and 2 both Down, so HSRP stays at 110 Active. After the conditioning is removed track 3 returns to Up at the next good probe (no `delay up` on track 3).
- (derived from build observations) Track 4 (boolean or) goes Down only when tracks 1 and 2 are both Down.
- (derived from build observations) Providers during a silent failure: R3's track 1 Down and its route to 10.0.10.0/24 AD 250 via R4; R4's tracks stay Up.

## Failure / Recovery Behaviour

- **Silent failure R1–R3** (link stop 03:14:32): track 1 Down 03:14:42 (+10 s), HSRP R1 Active -> Speak +11-13 s (R2 Active, R1 Standby 90), R1 default via R4 (AD 5). Re-check run (link stop about 16:07:00; timings vary by run with the probe phase, this is one measured run): track 3 +3 s, track 1 +8 s, tracks 2 and 4 +23 s:

```
16:07:00.585 %TRACK-6-STATE: 3 ip sla 3 state Up -> Down
16:07:05.587 %TRACK-6-STATE: 1 ip sla 1 reachability Up -> Down
16:07:20.587 %TRACK-6-STATE: 2 ip sla 2 state Up -> Down
16:07:20.682 %TRACK-6-STATE: 4 list boolean or Up -> Down
R1#show track brief   (+28 s)
1     ip sla      1                          reachability     Down  00:00:28
2     ip sla      2                          state            Down  00:00:13
3     ip sla      3                          state            Down  00:00:33
4     list                                   boolean          Down  00:00:13
R1#show standby brief
Et0/2       10   90  P Standby 10.0.10.3       local           10.0.10.1
```

  Predicting the order: SLA 3 and SLA 1 both probe every 5 s, so the first lost probe is 0-5 s after the failure; SLA 3 fails after its 1 s timeout, SLA 1 after its 2 s timeout, hence track 3 first (a shorter timeout, no delay) and track 1 a few seconds later (it was +10 s in the build run). SLA 2 runs every 10 s with a 2 s timeout, so the udp-jitter round needs a whole cycle or more to report failure: tracks 2 and 4 follow at +20-25 s, and track 4 (`or`) changes only when track 2 joins track 1 in Down (the 0.1 s after track 2). PC1 -> SRV1 lost 7-10 replies (7 and 10 in two runs); SRV1 -> PC1 lost about the same. Tracks 2 and 4 also Down at +20-25 s (their probes use the pinned route). **Recovery** (link start 03:18:51): SLA Up 03:18:57, track 1 Down -> Up 03:19:27 (`delay up` 30 s; in the re-check run tracks 2, 3 and 4 came Up immediately at 16:07:50 on the first good probe, track 1 only at 16:08:15 because only track 1 has `delay up 30`), HSRP R1 Active +3 s, default via R3, R3 return via R1 again.
- **Cable pull** (`shutdown` both ends): the pinned /32 falls to Null0 (AD 250), track 1 Down (return code Timeout), default via R4, R1 HSRP 90 Standby, PC1 -> SRV1 works. After restore: Up after the 30 s delay, HSRP back.
- **Node stop R1** (`write memory` first), measured in 3 runs: a CML node stop behaves like a silent failure, not a graceful HSRP resign. PC1 -> SRV1 lost 0–11 replies (3 runs: about 4–11; a fourth run: 0 of 40; the count depends on whether the unmanaged switch floods to R2 during the hold timer); R2 logged `Standby -> Active` directly (no resign-triggered change) roughly 7–15 s after the stop command, consistent with the 10 s hold timer expiring. On R1's restart R2 goes Active -> Speak -> Standby (preempt); R3 track 1 Down, R3 return AD 250 via R4; R4 track 1 Down, track 2 Up, R4 returns via R2 only.
- **Host-route pitfall** (R6): host route 10.0.100.200/32 via R3 on R1, silent failure: R1's own ping to SRV1 0/3. With HSRP tracking in place PC1 -> SRV1 still works (R2 is the gateway). With `no standby 10 track 1`, PC1 -> SRV1 100% loss: R1 stays active and sends into the dead link although its default moved to R4. Pinging R4 (10.0.100.4) from R1 works (default via R4).
- ACL fallback: `deny udp any any eq 1967` on R3 e0/0 inbound makes track 2 Up -> Down (`No connection`) while track 1 stays Up; removed afterwards.
- Restore: R1 wiped and restarted; start checks match the start state.

## Answers to Analysis Questions

Q1. The two tracks in this solution follow different measurements: track 1 (reachability) is on SLA 1 (threshold 1000 ms), track 3 (state) is on SLA 3 (threshold 100 ms), so under conditioning the comparison shows the effect of the threshold together with the track type. `reachability` is Up while the last operation's return code is OK (or an accepted code) and Down on timeout/failure. `state` also goes Down on other bad return codes such as "Over threshold". Observed: under 100 ms conditioning SLA 3 returned "Over threshold": track 3 (state) Down, track 1 (reachability) Up. The default route and the HSRP decrement should follow reachability (switch only when the path is dead, a slow path still carries traffic); the bad-path declaration needs `state` on an icmp-echo with `threshold`. (`udp-jitter` threshold does not flip a state track on iol-xe; track 2 flips only on failure.)
Q2. Without a pin the probe takes whatever route exists: through R4 over the Internet LAN, so it would succeed while R1–R3 is dead and the track stays Up. The Null0 /32 (AD 250) covers the cable pull, when the pinned route disappears: the probe then cannot leak out of another exit. A destination users need must not be pinned, because the host route sends their traffic into the dead link as well (the R6 pitfall: R1's own ping and, without gateway tracking, PC1's traffic lose 100%).
Q3. It prevents flapping: the default and the HSRP role do not return to R3 until the measurement has been good for 30 s, so an intermittent path does not bounce traffic. Cost: after recovery traffic stays on the backup for 30 s plus up to one probe interval (observed +30 s after the first good probe).
Q4. Observed: track Down +10 s after the failure (5 s frequency, 2 s timeout, plus detection), HSRP moves +11-13 s (track update plus the decrement and the 3 s hello with preempt on R2), 7-10 lost replies. Timers: SLA frequency, timeout, track delay (none down), HSRP hello/hold.
Q5. A boolean `or` of tracks 1 and 2 is Down only when both measurements fail, so one measurement's glitch does not trigger the reaction; with `and` it would be Up only when both work. Observed: track 4 went Down only when both tracks 1 and 2 were Down.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-25 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), iol-xe (IOS XE 17.16.1a), unmanaged_switch |
