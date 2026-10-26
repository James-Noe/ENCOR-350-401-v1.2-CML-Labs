# LAB-040 — Solution

## Summary
Foundation lab: CoPP with the MQC grammar of LAB-039. The student measures control-plane load, builds a five-class policy, proves with counters which class drops an ICMP flood, a scan and Telnet, and learns two things that surprise people: a class ACL `deny` means "not in this class" (the packet falls through to a later class), and a routing protocol policed with a flood is starved even when the flood is small. Blueprint: 5.2.b:I, 1.4:P. No intentional faults (foundation lab).

## Intentional Faults
None.

## Diagnosis / Methodology
Not a troubleshooting lab. Method: (1) put a policy with a measuring `police ... transmit/transmit` action in every class (a class without an action shows no counters on iol-xe), generate normal load, read counter deltas; (2) design rates from the table; (3) attack from PC2 and read exceeded counters per class; (4) change one class and watch the effect on OSPF/BGP.

## Solution Configuration
R1 (ACLs and classes, then policy):
```
ip access-list extended ACL-ROUTING
 permit ospf host 10.0.12.1 any
 permit tcp host 10.0.12.1 eq bgp any
 permit tcp host 10.0.12.1 any eq bgp
ip access-list extended ACL-MGMT
 permit tcp 10.0.10.0 0.0.0.255 any eq 22
 permit udp 10.0.10.0 0.0.0.255 any eq 161
ip access-list extended ACL-ICMP
 permit icmp any any
ip access-list extended ACL-UNDESIRABLE
 permit tcp any any eq telnet
 permit udp any any eq tftp
 permit tcp any any eq 514
class-map match-all CM-ROUTING
 match access-group name ACL-ROUTING
class-map match-all CM-MGMT
 match access-group name ACL-MGMT
class-map match-all CM-ICMP
 match access-group name ACL-ICMP
class-map match-all CM-UNDESIRABLE
 match access-group name ACL-UNDESIRABLE
policy-map PM-COPP
 class CM-ROUTING
  police cir 64000 conform-action transmit exceed-action transmit
 class CM-MGMT
  police cir 64000 bc 8000 conform-action transmit exceed-action drop
 class CM-UNDESIRABLE
  police cir 8000 conform-action drop exceed-action drop
 class CM-ICMP
  police cir 8000 conform-action transmit exceed-action drop
 class class-default
  police cir 8000 conform-action transmit exceed-action drop
control-plane
 service-policy input PM-COPP
```
If the measuring policy from step (1) is still attached (called `PM-MEAS` in the build), remove it first: under `control-plane` enter `no service-policy input PM-MEAS`, then `service-policy input PM-COPP`. Only one input policy can be attached, and attaching on top gives `Policy map PM-MEAS is already attached`.

Class order is the match order (routing, management, undesirable, ICMP, default). Notes: `drop` is not accepted as a class action on iol-xe (`% Invalid input`); `police ... conform-action drop exceed-action drop` is the form. The routing class transmits both ways so it has counters but is never dropped. SSH needs burst: `cir 32000` with the default bc (1000 B) dropped the RSA key-exchange packets and every login timed out; `bc 8000` fixed it.

Measuring policy used for R1 (same classes, `police cir 1000000 conform-action transmit exceed-action transmit` in each).

## Verification
Rate table (R1, 70 s window: 3 SSH logins with `show ip route`, 60 pings at 1/s from PC1; counter deltas):

| Class | Packets | Bytes | Approx. rate |
|---|---|---|---|
| CM-ROUTING | 66 | 7429 | ~0.85 kb/s (OSPF hello 1/s plus BGP) |
| CM-MGMT | 74 | 10611 | bursty; ~1.2 kb/s average, bursts up to ~5 kB per login |
| CM-ICMP | 60 | 5880 | ~0.8 kb/s (1 ping/s) |
| CM-UNDESIRABLE | 0 | 0 | with the final ACL (the first ACL also matched udp 67: alpine DHCP broadcasts) |
| class-default | 5 | 665 | ~0.1 kb/s |

Rates chosen: routing 64 kb/s (75x headroom, never dropped), management 64 kb/s with bc 8000 (burst for key exchange), ICMP 8 kb/s (10x the normal 0.8), default 8 kb/s, undesirable dropped.

R3, flood `ping -f -s 500 10.0.20.1` from PC2 (about 100 pps) + SSH logins from PC1 + nmap, one pass (output trimmed):
```
BGP uptime before 00:09:57, after 00:10:06 (no reset); OSPF FULL before and after
PC1: 3/3 SSH logins ok (show clock); ping 10.0.12.1 10/10
CM-ICMP exceeded 11533 -> 12337 packets; CM-MGMT unchanged
nmap -p 20-30,80,179,514: 23/tcp filtered telnet, 514/tcp filtered shell; other ports closed (reset)
CM-UNDESIRABLE conformed 6 -> 36 packets (action drop)
```
Fast scan (`nmap -sS -p 1-20000 --min-rate 3000 10.0.20.1`, 72 s): class-default conformed 104 -> 1362 packets, exceeded 0 -> 211453 packets / 12.3 MB.
SSH from PC2 (untrusted LAN) to 10.0.20.1: `Terminated` after 25 s. It is not in CM-MGMT (source not in the admin LAN), so it falls into class-default at 8 kb/s with a 1500-byte burst, which the key exchange cannot pass.

R4: with `5 deny tcp any any eq 22` in ACL-MGMT, PC1 ping still works (ICMP class) and SSH times out:
```
CM-MGMT conformed 124 packets (unchanged), class-default conformed 1367 -> 1376 (+9), exceeded 211453 -> 211461 (+8)
ACL-MGMT: 5 deny tcp any any eq 22 (14 matches)
```
The packet is not dropped by the ACE: a deny means "not in this class", it continues to the next class that matches (here class-default) and is policed there.

## Failure / Recovery Behaviour
Method: configuration change on R1 (not a link failure). Misclassification: `permit icmp any any` added to ACL-ROUTING and CM-ROUTING policed with `police cir 8000 conform-action transmit exceed-action drop`; flood from PC2 `ping -f -s 8 10.0.20.1` (small packets, about 100 pps) already running. A 500-byte flood does not starve OSPF (the token bucket oscillates between 0 and 528 B, so a ~90-byte hello usually conforms); the small-packet flood keeps the bucket empty so hellos fail.

| Scenario (trigger -> end) | Runs (raw) | Documented range | Basis |
|---|---|---|---|
| Apply the misclassification -> OSPF neighbour absent on R1 (`--until-gone FULL`, poll 1 s) | 5, 5, 6 s | 4-7 s | dead timer 4 s + poll; `%OSPF-5-ADJCHG ... Neighbor Down: Dead timer expired` |
| Restore the policy (flood still running) -> OSPF FULL | 1, 1, 1 s | 1-10 s | hello 1 s, adjacency re-forms; logs show LOADING->FULL within a few seconds, up to ~10 s in repeated flaps |
| Misclassification with flood running -> BGP session lost | 1 run, ~180 s (hold-time expired at 23:00:51, last keepalive passed about 22:57:51) | about the 180 s hold time, if the flood lasts that long | `%BGP-3-NOTIFICATION: sent to neighbor 10.0.12.1 4/0 (hold time expired)`; session back about 25 s after restore |

With a 70 s flood the BGP session stays Established (R1 uptime 00:01:36, no reset): R2 shows TCP retransmissions to R1 (`Sent: 13 (retransmit: 4 ...)` in `show ip bgp neighbors`/TCP statistics), CM-ROUTING exceeded 39800 packets / 5.29 MB (drops in the policed class). BGP stays Established in the failure test only for floods shorter than the hold time (LAB.md says about 60 s), and the session does fail after about 180 s of sustained starvation. OSPF flapped repeatedly while the flood ran (down at 22:55:34, 22:56:39, 22:57:22, 22:58:06).

## Answers to Analysis Questions
Q1. The policy is attached to the control-plane (punt) path, input only for packets addressed to or punted to the router CPU. Transit traffic is forwarded in the data plane and never reaches it; use interface ACLs or QoS for that.
Q2. Measure normal load per class (counter deltas under realistic use, including bursts such as SSH logins) and set the CIR with headroom above peak, plus a burst (bc) large enough for the biggest legitimate burst; here 0.85 kb/s routing -> 64 kb/s; ICMP 0.8 -> 8; management needs bc 8000 for key exchange (cir 32000 with default bc broke every login). In production: baseline over days with a classify-only/monitoring policy, size on peak plus margin (routing classes generous or only transmit), tighten gradually, review after topology or protocol changes. Alternatively quote rate tables from vendor guidance.
Q3. Nothing is dropped by that ACE: the packet is not in this class and goes on to the next class whose ACL permits it (here SSH from the admin LAN would land in class-default and be policed at the default rate; our R4 run shows 9 packets counted in class-default, 0 in CM-MGMT, and the login failed because the default class is too small for the key exchange).
Q4. A VTY access-class is checked when the SYN reaches the VTY: the CPU still receives every SYN and answers it with a RST (`Connection refused`, like a closed port), so it filters but does not bound the CPU load; an interface ACL protects only the interface it is on and only filters (no rate limit), and does not cover addresses reachable on other interfaces unless applied everywhere; CoPP covers every interface in one place and can rate-limit, but its classes are shared, so overall rate matters. Use together: access-class/ACLs to filter, CoPP to bound the rate.
Q5. OSPF: the flood and the hellos share the policed class; the small-packet flood leaves no tokens, hello packets (1/s) are dropped, the dead timer (4 s) expires within 4-7 s and the adjacency flaps for as long as the flood runs. BGP: it runs over TCP with a 60 s keepalive and 180 s hold time, TCP retransmits dropped segments (R2 shows retransmissions), so the session survives a one-minute flood; only after about 180 s of starvation does the hold time expire. The difference is the protocol's timers and its transport. Packet size mattered because the policer is a token bucket: with 500-byte packets the bucket oscillates between 0 and 528 B and refills enough between packets for a ~90-byte hello to conform, so OSPF stays up; with minimum-size packets the flood keeps the bucket empty and the hellos find no tokens.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-17 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), iol-xe (IOS XE 17.16.1a), net-tools |
