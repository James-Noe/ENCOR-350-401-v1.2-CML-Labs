# LAB-039 — Solution

## Summary
Foundation/analysis lab for 1.4:I. One 1 Mb/s shaped circuit and four traffic classes show congestion with no QoS, then classification, ingress marking with a trust boundary, a parent shaper with a child LLQ/CBWFQ/WRED/fair-queue policy, and how to read `show policy-map interface`. R5 overloads the priority class (the designed failure). No troubleshooting faults. Design note: the starting state carries a flat parent shaper (`WAN-SHAPE`, class-default `shape average 1000000`) on R1 e0/0, because without it the circuit is not congested and R1's baseline cannot be measured (IOL Ethernet has no real rate limit: unshaped TCP ran at 30 Mb/s). R3 extends that policy with the child.

## Intentional Faults
None (F/A lab).

## Diagnosis / Methodology
Read order: (1) iperf receiver lines on PC2 (loss, jitter, rate per stream); (2) `show policy-map interface Ethernet0/1 input` for what R1 classified; (3) the same command for e0/0 output: parent line (`shape (average) cir 1000000`, `queue limit 64 packets`, total drops) then each child class (`Priority ... b/w exceed drops`, `(queue depth/total drops/no-buffer drops)`, WRED table, `flowdrops`); (4) R2 e0/0 input counters prove the marks that left R1. Counters are reset by detaching and re-attaching a policy (`clear policy-map` is rejected, `clear counters` prompts).

## Solution Configuration
R1:
```
ip access-list extended ACL-VOICE
 permit udp any any eq 5004
ip access-list extended ACL-VIDEO
 permit udp any any eq 5005
ip access-list extended ACL-DATA
 permit tcp any any eq 5006
class-map match-any CM-VOICE-IN
 match access-group name ACL-VOICE
class-map match-any CM-VIDEO-IN
 match access-group name ACL-VIDEO
class-map match-any CM-DATA-IN
 match access-group name ACL-DATA
policy-map MARK-IN
 class CM-VOICE-IN
  set dscp ef
 class CM-VIDEO-IN
  set dscp af41
 class CM-DATA-IN
  set dscp af21
 class class-default
  set dscp default
interface Ethernet0/1
 service-policy input MARK-IN
class-map match-all CM-EF
 match dscp ef
class-map match-all CM-AF41
 match dscp af41
class-map match-all CM-AF21
 match dscp af21
policy-map WAN-CHILD
 class CM-EF
  priority percent 30
 class CM-AF41
  bandwidth percent 30
 class CM-AF21
  bandwidth percent 20
  random-detect dscp-based
 class class-default
  fair-queue
policy-map WAN-SHAPE
 class class-default
  service-policy WAN-CHILD
```
R2:
```
class-map match-all CK-EF
 match dscp ef
class-map match-all CK-AF41
 match dscp af41
class-map match-all CK-AF21
 match dscp af21
policy-map CHECK-IN
 class CK-EF
 class CK-AF41
 class CK-AF21
interface Ethernet0/0
 service-policy input CHECK-IN
```

## Verification
Receiver (PC2) first line per stream, 20 s run, iperf v2 (a second and a recovery run agreed within the margins below).

| Stream | Baseline A / B / C (shaper only) | With policy, run 1 / run 2 |
|---|---|---|
| Voice EF 250k | 61.2k, 2.65 ms, 74 % / 65.9k, 2.41 ms, 73 % / 67.0k, 2.14 ms, 72 % | 251k, 0.153 ms, 0 % / 251k, 0.093 ms, 0 % |
| Video AF41 400k | 89.4k, 1.92 ms, 77 % / 88.8k, 77 % / 98.2k, 75 % | 310k, 13.4 ms, 12 % / 311k, 13.3 ms, 12 % |
| Data TCP | 30.7k / 27.8k / 30.7k | 206k / 205k |
| Bulk 3M | 823k, 1.9 ms, 72 % / 820k, 72 % / 803k, 73 % | 208k, 12.2 ms, 93 % / 209k, 15.0 ms, 93 % |

Unshaped (before the circuit shaper existed): all UDP 0 % loss, TCP 30.1 Mb/s. The four streams together stay at about 975 kb/s (the shaper).

R1 e0/1 inbound (run 2): `CM-VOICE-IN 429 packets`, `CM-VIDEO-IN 859`, `CM-DATA-IN 585`, `class-default 5192`. R2 e0/0 inbound: `CK-EF 429`, `CK-AF41 615`, `CK-AF21 411`, `class-default 395`. The bulk stream was marked EF by PC1 and never appears in `CK-EF`: R1 re-marked it. R2's AF41 count equals R1's output (859 - 244 drops = 615).

R1 e0/0 outbound (run 2, after counter reset):
```
  Service-policy output: WAN-SHAPE
    Class-map: class-default (match-any)   7062 packets ... queue limit 64 packets
      (queue depth/total drops/no-buffer drops) 0/5156/0
      shape (average) cir 1000000, bc 4000, be 4000
      Service-policy : WAN-CHILD
        Class-map: CM-EF   429 packets   Priority: 30% (300 kbps), burst bytes 7500, b/w exceed drops: 0
        Class-map: CM-AF41 859 packets   0/244/0   bandwidth 30% (300 kbps)
        Class-map: CM-AF21 585 packets   0/174/0   bandwidth 20% (200 kbps)
            Exp-weight-constant: 9 (1/512)
            af21   414/618204   4/6056   167/252838   32   40   1/10
        Class-map: class-default 5189 packets   0/4788/0/4787   Fair-queue: per-flow queue limit 16 packets
```
Voice counter 429 against 430 datagrams sent (iperf: `Sent 430`; V4). WRED af21: transmitted 414, random 4, tail 167 (recovery run 1091 / 10 / 270): random drops are present but tail drops dominate on a 64-packet queue at lab rates.

R1 baseline: flat shaper class-default `queue limit 64 packets`, drops 9559 after the first runs.

## Failure / Recovery Behaviour
No timing measurement applies (no convergence or timer scenario); the lab's designed failure is a load change. Each result below was observed, runs raw.

| Scenario (trigger, end condition) | Runs | Result | Basis |
|---|---|---|---|
| R5: voice offered 500 kb/s, 20 s run; end: iperf receivers and R1 counters | 2 | voice 299k, 0.24 ms, 343/852 lost (40 %); 299k, 0.18 ms, 342/851 (40 %). `b/w exceed drops` 346 / 343 (= receiver loss). Video 294k / 292k (17 %), TCP 193k, bulk 198k / 93 % | LLQ policer caps EF at 300 kb/s, equal to its priority rate; other classes keep their guarantees (documented range: voice 295-305k, exceed drops within ±5 of loss) |
| Recovery: voice back to 250 kb/s | 1 | voice 251k, 0.276 ms, 0 %; exceed drops 0; video 311k, TCP 206k, bulk 209k | same as R4 |
| Trust boundary removed (`no service-policy input MARK-IN`), standard load | 1 | PC1's EF-marked bulk (3 Mb/s) lands in the priority class: `exceed drops: 5028`; voice 25.3k, 382/425 lost (about 90-92 %, run-to-run spread); video 400k, 0 % loss (the shaped bulk no longer competes in default); TCP 275k; bulk 277k, 91 % | Q4 |
| Parent shaper removed (child `WAN-CHILD` alone on e0/0; interface bandwidth 10 Mb/s) | 1 | no policy drops in any class (all `0/0/0`), `Priority: 30% (3000 kbps)`, TCP 28.4 Mb/s, bulk 2.97 Mb/s, voice and video about 1-2 % loss (host/virtual link, not the policy) | no queueing without congestion |
| NBAR | 1 | `match protocol http` accepted in a class-map (`show class-map`: Match protocol http; `show ip nbar protocol-id` lists it); not attached | Q6 |

Failure method: these are load changes, no link or interface failure. Restored by re-applying `MARK-IN` / `WAN-SHAPE`.

## Answers to Analysis Questions
Q1. The parent class-default line: `shape (average) cir 1000000`, `queue limit 64 packets` and non-zero `total drops`, with the four receivers adding up to about 975 kb/s. The interface hardware never overruns (interface bandwidth 10 Mb/s, well above the 1 Mb/s shaper), but shaper queue drops are counted in the interface's `Total output drops` and equal the policy-map drops, so that counter rises during a shaped run. The child policy schedules packets from the queue the parent builds: with no congestion at the parent nothing waits, so no class is distinguished (shown in the shaper-removed test: all child classes `0/0/0`).
Q2. Strict priority could starve every other class if it were unlimited, so IOS polices the LLQ at its configured rate, and only under congestion (when the interface is not congested the class may exceed it). R5: voice offered 500 kb/s is held to 299 kb/s (priority 30 % of 1 Mb/s = 300 kb/s), `b/w exceed drops` 343-346 equals the 40 % receiver loss, jitter stays 0.2 ms, and video, data and bulk keep their shares.
Q3. TCP reacts to loss by slowing down, so early random drops before the queue fills spread the loss across flows and avoid tail-drop bursts and global synchronisation (random 4-10, tail 167-270 in the table: WRED does help but the 64-packet queue still overflows with lab-scale traffic). UDP ignores loss: iperf keeps sending, so dropping early only discards packets without slowing the sender, and WRED therefore adds nothing for it.
Q4. If R1 trusts PC1's DSCP, the bulk stream (marked EF) enters the priority class and, without the ingress policy, took the whole EF class (`exceed drops: 5028`) and destroyed voice (about 90-92 % loss). Re-marking by port/ACL makes the network, not the host, decide the class. At HQ the trust boundary sits at the access port (or at the first routed hop for hosts that cannot be trusted): trust phones' EF through a conditional trust (CDP/LLDP phone detection) and re-mark everything else.
Q5. (derived; Cisco wireless QoS design / RFC 8325 mapping) EF (46) maps to UP 6 = AC_VO; AF41 (34) to UP 4 = AC_VI; AF21 (18) to UP 3 = AC_BE; default (0) to UP 0 = AC_BE. The legacy rule "UP = DSCP >> 3" gives EF 5 (AC_VI), AF41 4 (AC_VI), AF21 2 (AC_BK) and default 0, which is why the mapping must be configured explicitly. A WLC or AP that is not set to trust the client's DSCP (platinum/gold/silver/bronze profile caps) rewrites or caps the marking to the WLAN's QoS profile, so an EF-marked client in a Silver (best-effort) WLAN does not get voice treatment. No wireless node exists on this server, so this answer is analysis only.
Q6. NBAR (`match protocol`) classifies by application signature instead of ports, so the R2 classification would follow the application when it moves ports and could classify encrypted/port-hopping traffic by protocol. Cost: NBAR needs the protocol pack, DPI CPU per flow and memory, first packets of a flow are classified late, and results depend on pack version. On iol-xe `match protocol http` is accepted (`show class-map`); it was not attached here.
Q7. iperf v2's UDP client sends a final datagram with a negative sequence number and repeats it until the server's report arrives. When the shaper delays the report (video waits in the AF41 queue), the client resends the FIN (full 1470 B, counted by the AF41 class): tcpdump on PC1 shows 34 packets/s of data followed by a burst of about 180 packets with ids `0xfffffea7`, `0xfffffea6`, ... (negative, decreasing). Voice (priority) gets its report back at once, so its counter matches. It appears only when the receiver reports late, e.g. 859 counted against 685 sent.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-17 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), iol-xe (IOS XE 17.16.1a) |
