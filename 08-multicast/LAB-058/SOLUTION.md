# LAB-058 — Solution

## Summary

An operations-shift milestone-style troubleshooting lab on HQ lite H4 (HQ-CORE1, DIST1, DIST2, ACC1, PC1/PC2/PC3/PC5, DC min, WAN lite W2 with BR1, EDGE min E3 with HQ-SRV1; 17 nodes). Five tickets, five faults on four subsystems, plus an AI change proposal that has to be tested rather than believed (v1.2: F1 and F3 replaced, TK5/F5, R4/V1/V7 adapted, V8 and Q6 added).

Blueprint (instructor only): 3.1.c:T (spanning-tree root protection, F1), 2.2.a:T (VRF-aware AAA/NTP routing, F2 + F3), 5.2.b:T (CoPP class order, F4), 3.3.d:T (static RP address, F5), 4.3:R (SPAN capture to HQ-PC5), 1.4:R (WAN QoS, TK4), 3.3.c:R (GLBP red herring on VLAN 10, VRRP on VLAN 20), 5.1.b:R (central AAA); AI review #3. Root causes come from modules 02 (guard placement), 05, 06 and 08; module 07's tunnel and QoS are the setting of TK4 and TK5.

Educational intent: first evidence before fixes; series causes (F2 + F3) where the first fix gives a misleading partial success; two video tickets (TK1's black camera wall and TK5) that look like one failure; plausible wrong fixes that satisfy the user but break the documented design; a proposal that looks fine without load, and the discipline of testing it under the documented job.

## Intentional Faults

| ID | Device | Change | Symptom |
|---|---|---|---|
| F1 | HQ-DIST1 | `spanning-tree guard root` on `interface Port-channel1` (the replacement switch got the template line "root guard on every switch-facing trunk except the core uplink"; the design puts it only on the ports toward the access switch) | DIST2's VLAN 20 BPDUs (root) are superior on Po1: Po1 root-inconsistent for VLAN 20; DIST1 then claims VLAN 20 root itself and ACC1 relays DIST2's better BPDU, so DIST1 e0/2 is root-inconsistent for VLAN 20 too. CORE1's VLAN 20 gateway is reachable only through DIST1 e1/0: the OPS room (PC2) loses its gateway, the Internet and the video (TK1). VLANs 10/50/99 are unaffected; ACC1 and DIST2 name DIST2 as VLAN 20 root, as documented |
| F2 | HQ-DIST2 | `ip route vrf MGMT 0.0.0.0 0.0.0.0 10.10.99.1` removed | MGMT table of DIST2 has only 10.10.99.0/24: RADIUS (10.50.50.52) and NTP (10.50.50.1) unreachable; clock unsynchronised, stratum 16 (TK2) |
| F3 | HQ-DIST2 | in `aaa group server radius RADGRP` (which keeps `ip vrf forwarding MGMT`), `ip radius source-interface Loopback0` replaces `Vlan99` | Loopback0 (10.255.10.12) is a global-table address. The request leaves in MGMT from 10.255.10.12 and DC-AAA1 logs it and answers, but the answer cannot enter DIST2's MGMT table: timeouts, then the local fallback (TK2); in series with F2 |
| F4 | HQ-EDGE1 | `PM-COPP`: `class CM-UNDESIRABLE` (`tcp any any eq 22`, drop) placed before `class CM-MGMT` | SSH from the management sources (CORE1 e0/1.99) matches CM-UNDESIRABLE first and is dropped; pings, BGP, OSPF unaffected (TK3) |
| F5 | BR1-RTR1 | `ip pim rp-address 10.255.10.1` replaces `ip pim rp-address 10.255.10.100` (the clean-up "normalised" the RP to HQ-CORE1's router ID; 10.255.10.100 is the anycast RP on Loopback10) | BR1 records the viewer's group and builds (*,239.10.20.1) with RP 10.255.10.1 and RPF Tunnel21; the join names an RP that HQ-WAN1 and CORE1 do not use, so HQ-WAN1 refuses it: the depot sees no video, all day (TK5). OPS is unaffected |
| - | HQ-WAN1 (TK4) | no device fault: the assistant's proposal is the thing under test | CHG-AI-03 looks fine idle and fails under the sync job |

Fault logic: TK2 needs both F2 and F3 in series. F2 alone (F3 present): `ping vrf MGMT 10.50.50.52` succeeds but `test aaa` still fails (the request carries 10.255.10.12 and the answer cannot return); F3 alone (F2 present): the server is unreachable in MGMT (ping 0 %). Both orders were tested. After a failed `test aaa` IOS marks the server dead for its dead time (1 min): wait for `State: current UP` in `show aaa servers` before repeating the test. F2 also stops DIST2's NTP (clears after F2; measured: `Clock is synchronized` after about 29 to 33 min on DIST2 and 34 min on DIST1/ACC1, so allow about 35 min; not re-measured in v1.2). TK4 has no device fault, but V5 needs the depot video: TK5 first. Cross-ticket red herring: TK1 also darkens the OPS camera wall, so together with TK5 a central video failure looks likely; CORE1's (S,G) counters show the encoder arriving, OPS has no unicast either, and only BR1's tree is wrong.

## Diagnosis / Methodology

**TK1 (OPS room cut off, camera wall black).** PC2 cannot ping its gateway 10.10.20.1 (100 % loss) and `wget` to HQ-SRV1 says `Host is unreachable`: unicast fails first, so not a multicast problem. PC1 and PC3 (encoder) work, so the core and the other VLANs are up. Candidates: gateway/FHRP (CORE1 `show vrrp brief` VLAN 20 MASTER as documented; CORE1 has no ARP entry for 10.10.20.102; not the cause); trunk allowed lists (VLAN 20 is allowed on Po1, e0/2 and e1/0 but not in "forwarding and not pruned" on Po1 and e0/2: points at STP); rogue root (ACC1 and DIST2 `show spanning-tree vlan 20`: root priority 24596 = DIST2, ACC1 at the default 32788; eliminated). DIST1 `show spanning-tree inconsistentports` lists `VLAN0020 Ethernet0/2 Root Inconsistent` and `VLAN0020 Port-channel1 Root Inconsistent`; DIST1 and DIST2 both say `This bridge is the root` for VLAN 20 (28692 and 24596); `show running-config interface Port-channel1 | include guard` shows the line: **F1**. The shift's capture: `monitor session 1 source interface Ethernet0/3` + `destination interface Ethernet1/2` on ACC1 (PC2's port), `sudo tcpdump -i eth0 -n arp` on PC5 shows PC2's ARP requests for 10.10.20.1 unanswered (remove the session afterwards). Fix: `no spanning-tree guard root` under DIST1 Port-channel1; this alone clears the symptom (PC2 3/3, inconsistentports empty, DIST1 `Root ID 24596`, ACC1 root 24596 via Et0/1). Traps (each tried once, each restores OPS and fails V2): `no spanning-tree guard root` on DIST1 e0/2 only (OPS returns, Po1 stays blocked for VLAN 20 and the guard toward the access switch is gone); also removing the Po1 guard (no guard on DIST1 at all, inconsistentports empty: the design keeps root protection toward ACC1); moving VLAN 20's root to DIST1 (`spanning-tree vlan 20 priority 16384`: DIST1 becomes root, PC2 3/3, documented root broken). Removing the `priority` line (instead of resetting it) leaves DIST1 at 32788: restore `spanning-tree vlan 20 priority 28672`.

**TK2 (central login rejected on one DIST).** DIST1 authenticates `netadmin`; DIST2 does not: not the server or the key. The local account gets in after the timeouts: the session reaches AAA, so not the VTY ACL/SSH. `show ip route vrf MGMT` on DIST2: `Gateway of last resort is not set`; `ping vrf MGMT 10.50.50.52` 0 %: **F2** (DIST2 also shows `Clock is unsynchronized, stratum 16`, a consequence). With F2 fixed, ping works but `test aaa group RADGRP netadmin netpass legacy` still gives `No authoritative response from any server`. `debug radius brief` shows `Pick NAS IP ... tableid=0 cfg_addr=10.255.10.12` and `Send Access-Request to 10.50.50.52:1812`, two 5 s timeouts, `%RADIUS-4-RADIUS_DEAD`; DC-AAA1's log shows `Login OK: [netadmin] (from client lab port 0)` for the request and its retransmit: the request leaves, the server answers, the answer does not come back. `show running-config | section aaa group` against DIST1's: `ip radius source-interface Loopback0` where DIST1 has Vlan99: **F3**. Traps (each fails V3): a local `netadmin` user on DIST2 (`test aaa` still no response; the shift rule wants central authentication; `no username` waits on `[confirm]`, abandon the call); a global route to 10.50.50.0/24 via 10.10.255.4 (`ping 10.50.50.52` gives `U.`, nothing behind the next hop); `no ip vrf forwarding MGMT` in the group so that source and table "match" (ping from Loopback0 fails and rule 7 on MGMT use is broken).

**TK3 (SSH to the edge times out from MGMT).** Pings, BGP and OSPF to HQ-EDGE1 work. `show access-lists` VTY counters (`MGMT-HOSTS`) do not move and no AAA attempt is logged: the SYN never reaches the VTY. Edge ACLs: no deny hits for the management sources (the E3 ingress ACLs sit on the ISP side). `show policy-map control-plane`: with each `telnet 10.10.254.5 22 /vrf MGMT /source-interface Ethernet0/1.99` from CORE1, CM-UNDESIRABLE conformed (= dropped) packets rise (4 to 8 per two attempts; `CP-UNDESIRABLE permit tcp any any eq 22` matches rise 20 to 24 per attempt); the class order lists UNDESIRABLE before MGMT: **F4**. Traps: `no service-policy input PM-COPP` makes SSH connect but removes the documented policy (V4 fails); adding a permit to `MGMT-HOSTS` is refused as `% Duplicate entry exists` (the packet never reaches the VTY).

**TK4 (depot video freezes, HQ apps crawl; proposal CHG-AI-03).** Start TK5's repair first: V5 needs a working depot video, which is why the order of the tickets matters (Q6).  The proposal looks fine without the job (idle policer, hellos pass). Reproduce the documented job: `iperf -c 10.21.10.101 -u -p 5002 -b 3M -l 1316 -t 300` (HQ-PC3) towards `iperf -s -u -p 5002` (BR1-PC1), a viewer on BR1-PC1, and `wget -T 5 -O /dev/null http://10.10.60.150/stock.dat` (2 to 3 s without the job). Results are in Failure / Recovery below. Key findings: the circuit has 2 Mb/s, so a 3 Mb/s job tail-drops everything with no policy (video 66 to 93 % loss, fetches fail 23/43, OSPF flaps). With CHG-AI-03 as written OSPF and PIM stay up for more than 8 minutes (IOS does not drop its own hellos in the class-default policer: the class-default conformed counter rose by only 2 packets in 40 s with the job off) and video loses 0 to 1.2 %, but `/stock.dat` fails 3/3 in the v1.1 runs (`wget -T 5`) and, re-run for v1.2 under LAB.md's own check `wget -T 20 -O /dev/null http://10.10.60.150/stock.dat` in a loop with 2 s pauses (B-08-7), none of 30 fetches finished while the job ran: each ended as a failure 21 to 25 s after it started (`-T 20` is an idle timeout: a stalled fetch ends at about 21 to 22 s). The depot's TCP session shares the 300 kb/s policer with a 3 Mb/s job that is itself dropped 91 %. The arithmetic agrees: 300 KB is 2.4 Mb, which the whole 300 kb/s policer would need 8 s to carry, and the job offers ten times the policer rate into it. With the depot video present (TK5 fixed) the video is protected by the priority queue (0.21 % loss) while the application half of V5 still fails. Verdict: **flawed on the application half of V5**. You might predict OSPF/PIM loss within one dead interval; that does not hold on this IOS. Replay: `show crypto ipsec sa detail` `pkts replay failed (rcv)` rose by 14 to 21 in 8 minutes with LLQ and window 64, sporadic `%CRYPTO-4-PKT_REPLAY_ERR`.

Why the obvious corrections fail: raising the policer only moves the cliff; removing all QoS freezes the video again; a class-default `fair-queue` behind a 2 Mb/s shaper fails because ESP hides the inner flows from a policy on HQ-WAN1 e0/0: TCP and the UDP job are one flow (flowdrops 43774), small pages pass and `/stock.dat` still fails (3 runs, even with `-T 30`). `qos pre-classify` is rejected on Tunnel21 (`% Invalid input`) and a policy on Tunnel21 does not shape on IOL. A separate BULK class behind the shaper gives back-pressure with no drops but delays bulk ESP past the replay window: video 66 to 73 % loss and 36538 replay failures in about 7 minutes with window 64.

Working amendment: act on the job where its inner headers are visible (HQ-WAN1 e0/2 input, before encryption): police the job's source to 1 Mb/s there; on e0/0 shape to 90 % of the circuit (1.8 Mb/s, so the queue forms on HQ-WAN1 where the policy acts), with a CONTROL class (`dscp cs6` + IKE ACL, `bandwidth percent 5`), video `priority 800` (the 512 kb/s stream plus headers), class-default `fair-queue` and no policer. `replay window-size 1024` on both routers is kept as defence in depth (the amended design shows no replay failures with the default window either; it mattered for the LLQ-only variants). IKE/DPD and the OSPF/PIM hellos already carry CS6, copied to the ESP header (12 ESP packets per 30 s in `match dscp cs6` at idle; IKE 105 packets during a rekey), so the ACL in the CONTROL class is belt and braces against re-marking. The job cannot exceed the circuit anyway, so policing it at the inner headers only decides where its excess is dropped (in front of the shaper, where the policy can see the flow, instead of behind it).

**TK5 (depot video black all day).** Background: the policy on HQ-WAN1 e0/0 has no drops in the start state, so the circuit is not the cause (black all day, not only during the job). Start a viewer on BR1-PC1 (`iperf -s -u -B 239.10.20.1 -i 5`): no interval lines. Eliminate in order: source (CORE1 `show ip mroute 239.10.20.1 count`: `Packets received` rising, the encoder arrives; (S,G) with OIL Null); tunnel (SAs `UP-ACTIVE`, OSPF FULL on Tunnel21, PIM neighbour HQ-WAN1, HQ apps work); viewer and IGMP (BR1 `show ip igmp groups` lists 239.10.20.1 on Et0/2.10); RPF (`show ip rpf 10.255.10.100` and `10.10.50.103`: Tunnel21, `unicast (ospf 1)`, no static mroute). Then the RP: BR1 `show ip pim rp mapping` says `RP: 10.255.10.1` and `show ip mroute 239.10.20.1` shows `(*, 239.10.20.1) ... RP 10.255.10.1, flags: SJC, Incoming interface: Tunnel21`, while HQ-WAN1 and CORE1 map 10.255.10.100: **F5**. HQ-WAN1 `show ip mroute 239.10.20.1` says `Group 239.10.20.1 not found`, and `show logging` carries `%PIM-6-INVALID_RP_JOIN: Received (*, 239.10.20.1) Join from 10.250.21.21 for invalid RP 10.255.10.1`. That message is rate-limited: within about 1 to 2 minutes of the viewer's join the first line appears, and each group (also 224.0.1.40) then repeats about every 2 to 3 minutes, not once per join. The per-join evidence is `debug ip pim`: `Join-list: (*, 239.10.20.1),ignored, invalid RP 10.255.10.1`. Fix: on BR1-RTR1 `no ip pim rp-address 10.255.10.1` and `ip pim rp-address 10.255.10.100`. Traps (none restores V5/V8 within the design): `ip mroute 10.255.10.1/32 Tunnel21` and `ip mroute 10.10.50.103/32 Tunnel21` plus `ip igmp static-group 239.10.20.1` on Et0/2.10 (RPF becomes `multicast (static)` on Tunnel21, it was Tunnel21 already, and the join still names the wrong RP: still no video after 55 s); pointing HQ-WAN1 and CORE1 at 10.255.10.1 as well (video returns after 23 s but the anycast RP design is no longer used: V8 fails).

## Solution Configuration

HQ-DIST1 (F1):
```
interface Port-channel1
 no spanning-tree guard root
```
HQ-DIST2 (F2 + F3; the group keeps `ip vrf forwarding MGMT`):
```
ip route vrf MGMT 0.0.0.0 0.0.0.0 10.10.99.1
aaa group server radius RADGRP
 ip radius source-interface Vlan99
```
HQ-EDGE1 (F4: MGMT before UNDESIRABLE; re-adding the two classes puts them after CM-MGMT):
```
policy-map PM-COPP
 no class CM-UNDESIRABLE
 no class CM-ICMP
 class CM-UNDESIRABLE
  police cir 8000 conform-action drop exceed-action drop
 class CM-ICMP
  police cir 8000 bc 1500 conform-action transmit exceed-action drop
```
BR1-RTR1 (F5):
```
no ip pim rp-address 10.255.10.1
ip pim rp-address 10.255.10.100
```
HQ-WAN1 (TK4 amendment, tested). If the proposal CHG-AI-03 is still attached, first remove its policy on the interface (`no service-policy output <proposal policy>`, first line below under `interface Ethernet0/0`): otherwise the new attach is refused (`Policy map ... is already attached`).
```
ip access-list extended ACL-SYNC
 permit udp host 10.10.50.103 10.21.10.0 0.0.0.255
ip access-list extended ACL-IKE
 permit udp host 203.0.113.129 any eq 500
 permit udp host 203.0.113.129 any eq 4500
class-map match-all CM-BULK-IN
 match access-group name ACL-SYNC
class-map match-any CM-CONTROL
 match dscp cs6
 match access-group name ACL-IKE
class-map match-all CM-VIDEO
 match dscp af41
policy-map PM-WAN-IN
 class CM-BULK-IN
  police 1000000 conform-action transmit exceed-action drop
policy-map PM-WAN-OUT
 class CM-CONTROL
  bandwidth percent 5
 class CM-VIDEO
  priority 800
 class class-default
  fair-queue
policy-map PM-WAN-SHAPE
 class class-default
  shape average 1800000
  service-policy PM-WAN-OUT
interface Ethernet0/2
 service-policy input PM-WAN-IN
interface Ethernet0/0
 no service-policy output <the proposal's policy name, as you attached it>
 service-policy output PM-WAN-SHAPE
crypto ipsec security-association replay window-size 1024
```
BR1-RTR1: `crypto ipsec security-association replay window-size 1024`. New SAs pick the window up after `shutdown`/`no shutdown` on Tunnel21 (module 07: restore 4-26 s); `clear crypto session` also works: on this bench it gives no confirm prompt and flaps Tunnel21 (OSPF/PIM) for only about 1 s (3 runs, v1.2 validation); the older 45-80 s figure (module 07) did not reproduce.

## Verification

Captured on the v1.2 build, each fault fixed on its own and the symptom checked; the amendment as in v1.1 (v1.1 lines marked). Trimmed.

```
HQ-DIST1# show spanning-tree inconsistentports            (after the F1 fix: empty, Number ... 0)
HQ-DIST1# show spanning-tree vlan 20 | include Root ID|This bridge
  Root ID    Priority    24596                (not "This bridge is the root")
HQ-ACC1# show spanning-tree vlan 20 | include Root ID
  Root ID    Priority    24596
HQ-PC2# ping -c 3 10.10.20.1                  3 packets transmitted, 3 packets received
HQ-DIST2# ping vrf MGMT 10.50.50.52           Success rate is 100 percent (3/3)
HQ-DIST2# test aaa group RADGRP netadmin netpass legacy
User was successfully authenticated.
HQ-DIST2# show ntp status | include Clock
Clock is synchronized, stratum 4, reference is 10.50.50.1     (some minutes after the F2 fix)
HQ-CORE1# telnet 10.10.254.5 22 /vrf MGMT /source-interface Ethernet0/1.99
Trying 10.10.254.5, 22 ... Open
SSH-2.0-Cisco-1.25
HQ-EDGE1# show policy-map control-plane | include Class-map
    Class-map: CM-ROUTING ... CM-MONITOR ... CM-MGMT ... CM-UNDESIRABLE ... CM-ICMP ... class-default
BR1-RTR1# show ip mroute 239.10.20.1 | include \(\*|Incoming
(*, 239.10.20.1), ..., RP 10.255.10.100, flags: SJC
  Incoming interface: Tunnel21, RPF nbr 10.250.21.1
```
End state: PC1 and PC2 gateway 3/3, HQ-SRV1 wget ok, 192.0.2.200 2/2; PC2 viewer 65 intervals lost 0 of 3161 (0.00 %); BR1 viewer lost 11 of 2918 over 60 s after the F5 fix (0.38 %, the conditioned circuit has 0.2 % loss; the viewer's first interval line reads `134134/134183 (1e+02%)` because its sequence counter starts mid-stream, ignore it); DIST1 and DIST2 `test aaa` authenticated and `Clock is synchronized, stratum 4, reference is 10.50.50.1`; inconsistentports empty; BR1, CORE1 and HQ-WAN1 `RP: 10.255.10.100`.

TK4 amendment under the sync job (F5 fixed, replay window 1024 on both routers, Tunnel21 bounced on BR1, SAs `replay window size: 1024`; job 245 s, fetch loop 235 s): run 1 17 of 17 fetches ok in 11 to 13 s, video lost 30 of 12985 (0.23 %); run 2 17 of 17 ok in 10 to 13 s, 24 of 12885 (0.19 %); run 3 17 of 17 ok in 11 to 13 s, 28 of 12790 (0.22 %); OSPF FULL, `replay failed (rcv): 0`; the job is policed to about 900 to 930 kb/s (70 to 71 % drop at its 1 Mb/s police). v1.1 runs: window 1024 video 0.15 % and 0.26 %, 64 fetches ok; window 64 video 0.39 %. Proposal CHG-AI-03 with F5 fixed (job 130 s): fetches 21 s fail, 23 s fail, 21 s fail, 21 s fail, 22 s fail, then 27 s ok (started in the last seconds of the job); depot video lost 20 of 9678 (0.21 %); job 91 % drop; policer `conformed 102000 bps, exceeded 962000 bps`; VIDEO `b/w exceed drops: 0`; OSPF FULL throughout.

## Failure / Recovery Behaviour

| Scenario (trigger, end condition) | Runs (raw values) | Documented range | Basis |
|---|---|---|---|
| R4 cable pull: `shutdown` on HQ-DIST2 e0/2 and HQ-ACC1 e0/1, PC2 ping 1/s to 10.10.20.1 (after the F1 fix); end = replies resume (sequence gap) | 1, 1, 1 lost pings | 0 to 3 pings | rapid-PVST: ACC1 e0/1 (VLAN 20 root port) fails, VLAN 20 moves to e0/0 toward DIST1 and Po1, the path F1 had blocked; both ends down, so link-down is detected at once |
| Failback: both ports `no shutdown` | 0, 0, 0 lost pings | 0 to 1 | the returning port is the root port again; proposal/agreement handshake (runs 2 and 3 polled on the same ping file) |
| TK5 fix: `ip pim rp-address` corrected on BR1-RTR1, end = first viewer interval line at BR1-PC1 (config block + `--until`) | 3 s, 4 s, 3 s; 4, 20, 4, 6, 25 s (second set: runs 2 and 3 issued concurrently) | 2 to 30 s | triggered join at once gives 3 to 6 s; the 20 s and 25 s outliers are consistent with a lost or late triggered join that waits for a later join/refresh (concurrent runs add load; derived, not isolated), so allow up to about 30 s before suspecting the fix (before each run `clear ip mroute *` on BR1-RTR1 and HQ-WAN1: HQ-WAN1 keeps an (S,G) SPT after an RP revert) |
| TK5 evidence: first `%PIM-6-INVALID_RP_JOIN` for (*, 239.10.20.1) on HQ-WAN1 after the viewer joins | first line within about 1 to 2 min of the join; each group repeats at 118 s (224.0.1.40) and 60 to 180 s (239.10.20.1) | the line appears within a few minutes and repeats every 2 to 3 min; the debug shows every join | the log is rate-limited, not one line per join |
| TK4 proposal CHG-AI-03: fetch start to failure, `wget -T 20` loop under the job | 21, 22, 22, 21, 22, 21, 25, 23, 21, 21, 21 s (run 1); 22, 21, 21, 21 s (run 3); 21 s (with the video present) | 20 to 27 s | `-T 20` idle timeout plus up to 7 s; 0 of 30 fetches complete while the job runs (one fetch started at 78 s finished in 39 s after the job ended) |
| TK4 proposal: OSPF/PIM on Tunnel21 under the job | stayed up in an 8-minute run, no ADJCHG | up for the whole run | IOS does not police its own hellos; the verdict rests on the application half |
| TK4 amendment: video loss and fetches under the job, 4 min | 0.23, 0.19, 0.22 %; 17 of 17 fetches ok each run, 10 to 13 s | video at most 1 %, each fetch at most 20 s | circuit headroom (1.8 Mb/s shape) and the job policed to 1 Mb/s at the inner headers |
| TK2 server state after a failed `test aaa` | DEAD until the dead time (1 min) ends | wait for `State: current UP` | RADIUS dead timer |

A one-ended `shutdown` is a different test (the peer port stays up and times out). `clear crypto session` flaps the tunnel only about 1 s here (no confirm prompt; 3 runs); the module 07 figure of 45 to 80 s did not reproduce.

## Answers to Analysis Questions

Q1. TK1: PC2 failing to reach its gateway while PC1 and PC3 work, and the unanswered ARP in the capture, ruled out the video and the FHRP before STP; TK2: DIST1 authenticating the same account and the local account working ruled out the server and the VTY; TK3: the unmoved VTY ACL counter ruled out the VTY and the edge ACLs (the packet never reached the VTY), then the rising CoPP drop counter; TK4: the idle behaviour and the conformed/exceeded counters showed the proposal looks fine until the job runs; TK5: the encoder counted on CORE1, the tunnel and OSPF up, the correct RPF and the IGMP group present ruled out the source, the circuit, RPF and the viewer.
Q2. TK1: PC2's gateway ping, then a viewer on PC2 (loss over 60 s) and the documented roots on ACC1/DIST2; TK2: `test aaa` after waiting for the server to be UP, then the clock; TK3: an SSH session opens and the policy keeps its documented class order; TK5: viewer data at BR1-PC1 and loss below 1 %, the RP on all routers 10.255.10.100.
Q3. For example TK3: `show policy-map control-plane` drops rise with every SSH attempt while the VTY ACL counters do not; the class order shows UNDESIRABLE before MGMT. Adding a permit to the VTY ACL fails (duplicate entry, the packet never reaches the VTY); removing the policy lets SSH in but breaks the documented design. Or TK2: fixing the route restores pings in MGMT but `test aaa` still fails because the request carries a global-table source address (`debug radius brief`, `tableid=0`; the server logs the request and its answer cannot return).
Q4. Verdict: flawed. Under the 3 Mb/s job the policer leaves the depot's TCP session no path: none of 30 `wget -T 20` fetches completed while the job ran (each failed 21 to 25 s after it started) although the video (priority queue, 0.21 % loss) and OSPF/PIM look healthy. Corrected change: police the job where the inner headers are visible (HQ-WAN1 e0/2 input), shape e0/0 to 1.8 Mb/s with a CONTROL class, video `priority 800` and a fair-queue class-default, plus `replay window-size 1024` on both routers. The reason to police the sync job at all is arithmetic: a 3 Mb/s job can never fit the 2 Mb/s circuit, so policing it at the inner headers only decides where its excess is dropped, in front of the shaper rather than behind it. The encryption hides the inner flows from a policy on the physical interface: after ESP, TCP and the UDP job are one flow (class-default fair-queue cannot separate them); only the outer DSCP copy is visible.
Q5. Test under the documented load, not idle, and with the documented application check (a timeout of 5 s and one of 20 s tell different stories); check that control traffic (routing hellos, IKE/DPD) has its own class and is never in a policed class; state what the policy can see on an encrypted path (outer header only); verify the replay window before adding a priority queue on an IPsec path; require counters (conformed/exceeded, replay failures) as evidence and a rollback plan.
Q6. Yes, in two ways. TK5 before TK4: V5 and the proposal's verdict need the depot video, and with the depot viewer black the video half of the test shows nothing; a student who tests CHG-AI-03 first sees an empty viewer and may blame the policy. TK1 and TK5 together look like one video failure (the OPS camera wall and the depot are both black), but PC2 cannot ping its gateway (unicast is dead too) and CORE1 counts the encoder arriving, so TK1 is not multicast, and only BR1's tree is wrong for TK5. TK2's clock also depends on the order: it clears some time after the route fix, so TK2 is worked first and checked last (V3).

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-16 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), iol-xe (IOS XE 17.16.1a), ioll2-xe (IOS XE 17.16.1a), radius |
