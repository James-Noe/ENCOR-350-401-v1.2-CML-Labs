# LAB-052 — Solution

## Summary

Educational intent: operate a WAN that is already running, from three business requests: protect voice and guarantee OT on a congested 2 Mb/s Internet circuit (shaping to the contracted rate with a child LLQ/CBWFQ policy, marking trusted or set at the branch edge, DSCP surviving GRE and ESP), steer one traffic class between two transports from tracked end-to-end reachability (IP SLA + track + PBR with `verify-availability`, at both ends), and capture evidence when a tunnel drops (EEM on the line-protocol syslog message). Blueprint mapping: 1.4 (QoS), 3.2.d (PBR), 4.4 (IP SLA / tracking), 6.6 (EEM). The lab is N type with no intentional faults; it writes stage WAN W4 (`environments/WAN/W4/`).

Build notes:
- The CML link conditioning on BR1-INET1 carries a **bandwidth limit of 2000 kb/s** in addition to latency 30 ms and loss 0.2 %. Bandwidth conditioning works on an IOL link and is exported with the YAML. Without it the router shaper would not meet real congestion. It is the real bottleneck; the router's shaper makes the router the place where queuing decisions happen.
- BR-1's EF proof needs the **provider path down** (track Down): with the provider path healthy, EF to HQ is steered to the provider line by BR-2 and never meets the shaper. EF to BR2 (not matched by the voice PBR) always meets it.
- EEM writes **one file per tunnel** (`unix:TunnelN-down.txt`), not one file `unix:tunnel-down.txt`: three applet runs fire concurrently and a shared file interleaves them, and a second pipe after `include ... | append` is unsupported on IOL.
- `crypto ipsec security-association replay window-size 1024` is part of the solution (finding below).

## Intentional Faults

None (N lab).

**Designed discovery (not a student error): ESP anti-replay under LLQ.** Every correct solution hits it; the LAB.md concept note names anti-replay without the fix. Evidence chain: with the shaper and LLQ applied, EF and AF31 are clean but best effort falls to about 1 % (28 kb/s) of what is left, although BR1's class-default drops explain only the offered excess. `show logging` on HQ-WAN1 shows `%CRYPTO-4-PKT_REPLAY_ERR: decrypt: replay check failed`: the LLQ transmits EF ESP packets ahead of earlier-sequenced best effort packets, so the flow's ESP sequence numbers arrive more than the default 64-packet window behind the highest and are discarded. Fix on both ends: `crypto ipsec security-association replay window-size 1024`, then new SAs (bounce the tunnels).

Expected student errors, for the debrief:

| Error | Symptom | Where it shows |
|---|---|---|
| IP SLA `threshold` larger than `timeout` | `ip sla schedule` is refused with a message; the SLA never starts, the track stays Down, "Pending trigger" | `show ip sla summary`, config-time message |
| SLA to the far provider /31 without a route | Probe goes to the default (INET1) and fails; track never Up | `show ip route 100.64.10.1`; needs a /31 static on each router toward PE1 |
| PBR with `set ip next-hop` without `verify-availability` + track | Voice keeps going to a dead provider path on a silent failure (interface stays up/up) | `show route-map` counters keep rising, `show track` n/a |
| PBR only at BR1 | Return voice from HQ takes the tunnel | `traceroute -t 184` from HQ-PC1 |
| Applet alert text contains the trigger pattern, or a shared file | Applet re-triggers itself; three concurrent runs interleave in one file | `show logging`, `more unix:...` |
| Marking trusted but only tested with ping | ping does not set EF; policy counters stay 0 | `show policy-map interface` |

## Diagnosis / Methodology

No faults. For a student whose first measurement is wrong:

1. Baseline without policy: EF 43 %, AF31 43 %, BE 33 % loss at the 2 Mb/s circuit (the circuit drops FIFO).
2. Policy on e0/0 not matching: `show policy-map interface Ethernet0/0` shows 0 packets in VOICE: the traffic is encrypted, so only the ESP outer header's ToS can match. The capture on the BR1-INET1 link shows outer ToS 0xb8 (EF), 0x68 (AF31), 0xc0 (control): the DSCP is copied inner -> GRE -> ESP, so a classifier on the physical interface sees it and `qos pre-classify` is not needed.
3. EF and AF31 clean, best effort collapses beyond the offered excess: look beyond the policy counters at `show logging`. Counters in `class-default` show drops only for what the shaper dropped, but the best effort traffic that was delivered is being discarded at HQ-WAN1 by the anti-replay check.
4. BR-2: `show track 30`, `show ip sla summary`, `show route-map VOICE-PBR` counters, `traceroute -n -t 184` (hop addresses 100.64.x versus 10.250.21.x). Plausible wrong causes ruled out: interface-state tracking (stays up on a silent failure), a PBR with no track (keeps sending to the dead path), missing /31 route to the probe target.
5. BR-3: `more unix:Tunnel21-down.txt` and `show logging | include HA_EM`.

## Solution Configuration

Applied in this order (also re-applied on a fresh import). No reload.

### BR1-RTR1

```
class-map match-all VOICE
 match dscp ef
class-map match-all OT-DATA
 match dscp af31
policy-map WAN-CHILD
 class VOICE
  priority percent 25
 class OT-DATA
  bandwidth percent 25
 class class-default
  fair-queue
policy-map WAN-SHAPE
 class class-default
  shape average 2000000
  service-policy WAN-CHILD
policy-map MARK-OT
 class class-default
  set dscp af31
interface Ethernet0/0
 service-policy output WAN-SHAPE
interface Ethernet0/2.40
 service-policy input MARK-OT
ip route 100.64.10.0 255.255.255.254 100.64.21.0
ip sla 30
 icmp-echo 100.64.10.1 source-interface Ethernet0/1
 threshold 1000
 timeout 1000
 frequency 5
ip sla schedule 30 life forever start-time now
track 30 ip sla 30 reachability
 delay down 5 up 30
ip access-list extended VOICE-OUT
 permit ip 10.21.10.0 0.0.0.255 10.10.0.0 0.0.255.255 dscp ef
route-map VOICE-PBR permit 10
 match ip address VOICE-OUT
 set ip next-hop verify-availability 100.64.21.0 1 track 30
interface Ethernet0/2.10
 ip policy route-map VOICE-PBR
crypto ipsec security-association replay window-size 1024
event manager applet TUNNEL-DOWN
 event syslog pattern "Line protocol on Interface Tunnel[0-9]+, changed state to down"
 action 1.0 cli command "enable"
 action 2.0 regexp "Tunnel[0-9]+" "$_syslog_msg" tun
 action 3.0 cli command "show clock | append unix:$tun-down.txt"
 action 4.0 cli command "show interfaces $tun | append unix:$tun-down.txt"
 action 5.0 cli command "show ip route | append unix:$tun-down.txt"
 action 6.0 cli command "show crypto session brief | append unix:$tun-down.txt"
 action 7.0 cli command "show ip ospf neighbor | append unix:$tun-down.txt"
 action 8.0 syslog priority alerts msg "WAN tunnel failure at BR1: evidence for $tun in unix:$tun-down.txt"
```

VLAN 10 marking is trusted (no policy on e0/2.10 input). Existing SAs keep the old window: after adding the replay line on both routers, bounce the tunnels (`interface Tunnel21`, `Tunnel41` and `Tunnel91` each with `shutdown`, `no shutdown`, or `clear crypto sa` on both routers) to negotiate new SAs. The reference run bounced only Tunnel21, the tunnel carrying the load; Tunnel41 (OT) and Tunnel91 (management) kept the 64-packet window until their next rekey, which does not affect the tests because they carry no reordered QoS load, but a production change should bounce all three in the change window.

### HQ-WAN1

```
crypto ipsec security-association replay window-size 1024
ip route 100.64.21.0 255.255.255.254 100.64.10.0
ip sla 31
 icmp-echo 100.64.21.1 source-interface Ethernet0/1
 threshold 1000
 timeout 1000
 frequency 5
ip sla schedule 31 life forever start-time now
track 31 ip sla 31 reachability
 delay down 5 up 30
ip access-list extended VOICE-RET
 permit ip any 10.21.10.0 0.0.0.255 dscp ef
route-map VOICE-PBR permit 10
 match ip address VOICE-RET
 set ip next-hop verify-availability 100.64.10.0 1 track 31
interface Ethernet0/2
 ip policy route-map VOICE-PBR
```

## Verification

Captured on a fresh import after applying the solution.

End state:

```
BR1-RTR1# show track brief
30    ip sla      30                         reachability     Up    00:01:12
BR1-RTR1# show ip sla summary
*30          icmp-echo   100.64.10.1       RTT=4       OK          2 seconds ago
HQ-WAN1# show track brief
31    ip sla      31                         reachability     Up    00:01:46
BR1-RTR1# show event manager policy registered
1    applet    user    syslog              Off   Sat Oct 10 05:09:45 2026  TUNNEL-DOWN
BR1-RTR1# show policy-map interface Ethernet0/0 | include Service-policy|shape
  Service-policy output: WAN-SHAPE
      shape (average) cir 2000000, bc 8000, be 8000
          Priority: 25% (500 kbps), burst bytes 12500, b/w exceed drops: 0
          bandwidth 25% (500 kbps)
BR1-RTR1# show policy-map interface Ethernet0/2.40
  Service-policy input: MARK-OT
BR1-PC1:~$ traceroute -n -w 2 -m 5 -t 184 10.10.10.101
 1  10.21.10.1
 2  100.64.21.0
 3  100.64.10.1
 4  10.10.255.96
 5  10.10.10.101
BR1-PC1:~$ traceroute -n -w 2 -m 5 10.10.10.101
 1  10.21.10.1
 2  10.250.21.1    (tunnel)
 3  10.10.255.96
 4  10.10.10.101
```

BR-1 load (EF 300k -l 200 + AF31 400k -l 1200 + BE 3M -l 1200, 30 s) with the provider path down (`link stop` BR1-RTR1 e0/1 to PROV-PE1, track 30 Down after 6 s). Receiver side (HQ-PC1):

```
EF   [1] 0.00-30.48 sec  1.07 MBytes   294 Kbits/sec  2.373 ms   18/5628 (0.32%)
AF31 [1] 0.00-30.50 sec  1.43 MBytes   394 Kbits/sec  5.007 ms    1/1253 (0.08%)
BE   [1] 0.00-30.67 sec  3.45 MBytes   943 Kbits/sec  4.767 ms 6822/9835 (69%)
```

(Part 1 run: EF 10/5628, 0.18 %; AF31 3/1253; BE 938 kb/s. The loss is the conditioning's 0.2 %.) Policy counters after the run on BR1 e0/0: VOICE 5682 packets, drop rate 0; OT-DATA 1305 packets, drop rate 0; class-default 10121 packets, 6817 drops (223 kb/s). No-policy baseline of the same test: EF 43 %, AF31 43 %, BE 33 % loss.

Capture on the BR1-INET1 link (CML packet capture, summarised by protocol and ToS): outer ESP header ToS 0xb8 for 1205 EF packets, 0x68 for 609 AF31, 0xc0 for 15 control, 12 at 0x0; the OT tunnel (Lo202 to Lo202) 12 packets at 0x68 (MARK-OT survives GRE and ESP); Tunnel91 only 0xc0. No GRE (protocol 47) in the capture.

BR-3 cable pull (shutdown BR1 e0/0 and INET1 e0/1), `show logging` on BR1 and the file:

```
*Oct 10 05:13:28.349: %LINK-5-CHANGED: Interface Ethernet0/0, changed state to administratively down
*Oct 10 05:13:32.220: %LINEPROTO-5-UPDOWN: Line protocol on Interface Tunnel21, changed state to down
*Oct 10 05:13:32.915: %HA_EM-1-LOG: TUNNEL-DOWN: WAN tunnel failure at BR1: evidence for Tunnel21 in unix:Tunnel21-down.txt
*Oct 10 05:13:42.472: %LINEPROTO-5-UPDOWN: Line protocol on Interface Tunnel91, changed state to down
*Oct 10 05:13:42.478: %LINEPROTO-5-UPDOWN: Line protocol on Interface Tunnel41, changed state to down
*Oct 10 05:13:43.151: %HA_EM-1-LOG: TUNNEL-DOWN: WAN tunnel failure at BR1: evidence for Tunnel91 in unix:Tunnel91-down.txt
*Oct 10 05:13:43.152: %HA_EM-1-LOG: TUNNEL-DOWN: WAN tunnel failure at BR1: evidence for Tunnel41 in unix:Tunnel41-down.txt
BR1-RTR1# dir unix: | include down
1465470  -rw-  4034  Oct 10 2026 05:13:43 +00:00  Tunnel91-down.txt
1465471  -rw-  4030  Oct 10 2026 05:13:43 +00:00  Tunnel41-down.txt
1465466  -rw-  4267  Oct 10 2026 05:13:32 +00:00  Tunnel21-down.txt
BR1-RTR1# more unix:Tunnel21-down.txt   (head)
*05:13:32.380 UTC Sat Oct 10 2026
Tunnel21 is up, line protocol is down
  Tunnel linestate evaluation down - no output interface
  Tunnel protection via IPSec (profile "VPN-PROF")
```
(then the routing table, crypto sessions and OSPF neighbours at that moment.)

Matrix sample: unchanged from W3: BR1-PC1 reaches HQ-PC1 only (not 10.21.99.1, 10.10.99.2, 10.10.40.1); BR1-PC2 reaches 10.10.40.1, not 10.10.10.101; BR2-PC1 reaches HQ-PC1 and BR1-PC1; HQ-CORE1 `telnet 10.21.99.1 22 /vrf MGMT /source-interface Loopback99` returns SSH-2.0-Cisco-1.25.

## Failure / Recovery Behaviour

Clocks: router clock = CML host clock (NTP-free, same host). BR-2 and BR-3 failure methods differ and are not mixed: BR-2 = silent failure (CML `link stop` of BR1-RTR1 e0/1 to PROV-PE1, interfaces stay up/up); BR-3 = cable pull (shutdown both ends BR1 e0/0 and PROV-INET1 e0/1) and, separately, silent failure of the same link.

| Scenario (trigger, end condition) | Runs (raw) | Documented range | Basis |
|---|---|---|---|
| BR-2 silent failure of BR1-PE1, trigger = `link stop`, end = voice datagrams flowing again on the Internet path (gap = lost datagrams / 100 pps), BR1 to HQ | 9.6, 6.8, 6.9, 10.7, 13.5, 10.2 s | 6.8-14 s (limit in R3/V5: 20 s) | SLA every 5 s, timeout 1 s, `delay down 5`: arithmetic gives 6-11 s per router, but measured track-down reached 11.1 s (BR1) and 14.7 s (HQ-WAN1) after the stop, so budget up to ~15 s plus the path switch; the 20 s limit leaves margin |
| same, HQ to BR1 | 11.9, 9.1, 9.2, 14.2, 12.1, 13.8 s | 9-15 s (limit 20 s) | same; HQ-WAN1's probe runs 2.3 s after BR1's, and its detection is the later of the two |
| BR-2 restore, trigger = `link start`, end = track Up (voice back on provider) | BR1 33-35 s, 31.7-34.7 s, 35.9-39.4 s; WAN1 35-37 s, 34-37 s, 33.2-36.7 s (REST call start-end windows) | 30-40 s | `delay up 30` + probe period; no loss on restore |
| BR-3 cable pull, trigger = shutdown of BR1 e0/0 (pulled side), end = line protocol down, Tunnel21 | 4.99 s, 3.86 s, 7.19 s | 3-8 s | HA_EM message +0.7 s after each line-down |
| same, Tunnel41 / Tunnel91 | 14.28/14.26, 13.13/13.15, 16.46/16.48 s | 12-18 s | DPD/IKE on the protected tunnels without keepalive |
| BR-3 silent failure (`link stop` of e0/0 to INET1), end = line down (any of the three) | 24.6-28.4 s, 23.2-26.6 s, 21.0-27.6 s | 20-30 s | DPD/IKE; applet +0.7 s |
| BR-3 restore after cable pull (run 2), end = tunnels up | Tunnel91/41 +9.6 s, Tunnel21 +16.1 s | 8-20 s | IKE re-establish and OSPF |
| BR-3 restore after silent failure, end = tunnels up | 1.7-5.6 s, 4.5-9.6 s, 1.4-5.5 s | 1-10 s | IKE already retrying |

BR-2 detail: no loss before the track goes down (the PBR sends voice to the dead path until then); after failover the EF streams on the Internet circuit lose 0-2 datagrams per second (conditioning's 0.2 % plus queue jitter, <= 2 %). The evidence file and `%HA_EM-1-LOG` message follow each line-down by about 0.7 s, so BR-3's requirement "evidence within 30 s" holds for both failure kinds. The files are in RAM (`unix:`); a reload loses them.

## Answers to Analysis Questions

Q1. The router interface is faster than the circuit, so the router never sees congestion: the circuit (here the CML conditioned link, in production the provider's policer or the access device) drops FIFO and voice is lost with the rest (baseline 43 %). Shaping to 2 Mb/s moves the bottleneck into the router, where LLQ and CBWFQ can prioritise. In CML the link's bandwidth limit is the circuit; the shaper rate must equal it.

Q2. Yes. The inner DSCP is copied into the GRE outer IP header and from there into the ESP outer header (capture: EF 0xb8, AF31 0x68, control 0xc0; the OT tunnel shows AF31 set by MARK-OT). So the policy on the physical interface classifies protected-tunnel traffic. If not, classification would move to the tunnel interface, or `qos pre-classify` on the tunnel would be needed.

Q3. A silent provider failure leaves the interface up/up, so an interface-state route or PBR keeps sending voice into the failure for as long as it lasts (the whole call). A track on an IP SLA probe through the provider path to the far end (not merely the next hop) reflects delivery: voice moved after 6.8-14.2 s in the tests (10 runs; limit 20 s). A student can shorten this (e.g. `delay down 3` or SLA frequency 3) at the price of more probes and more sensitivity to a single lost probe; the 20 s limit does not require it.

Q4. PBR is a per-router, per-direction decision on ingress; the return path from HQ is chosen by HQ-WAN1's own routing (tunnel). The mirrored policy and probe at HQ-WAN1 move the return EF to the provider path.

Q5. On a cable pull the interface state, routing table and crypto sessions are captured at the moment of the tunnel's line-protocol down: for the pulled side the line is down 4-7 s (Tunnel21) / 13-17 s (41, 91) after the pull; on a silent failure all three go down 21-28 s after the stop (DPD) and the physical interface is still up. The applet only sees BR1's view after the event: not the HQ side, not the route flush or crypto SA lifetimes that happened before the message, and a reload erases the RAM file.

Q6. `show logging` on HQ-WAN1: `%CRYPTO-4-PKT_REPLAY_ERR: decrypt: replay check failed`, while the class-default drop counters on BR1 explain only the offered excess. The LLQ transmits EF ESP packets ahead of earlier-sequenced best effort packets, so a flow's ESP sequence numbers arrive more than 64 behind the highest, and the receiver discards them as replays (best effort fell to about 1 %). A larger anti-replay window (`crypto ipsec security-association replay window-size 1024`, both ends, new SAs) fixes it (BE 943 kb/s).

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-14 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), iol-xe (IOS XE 17.16.1a), ioll2-xe (IOS XE 17.16.1a) |
