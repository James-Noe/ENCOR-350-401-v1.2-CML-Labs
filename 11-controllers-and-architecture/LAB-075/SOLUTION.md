# LAB-075 — Solution

## Summary
Saturday shift 4 of Veridian Logistics: three tickets, five faults, one AI proposal to test. Blueprint mapping: 3.3.c (GLBP/first-hop redundancy, T), 2.2.b (GRE/IPsec tunnel, T), 5.1.b (device AAA, T), 3.2.b (OSPF adjacency and area, T), 5.2.a (ACL/circuit policy, T), 4.1 (syslog collector and conditional debug, N). The lab teaches: (1) a healthy-looking first-hop protocol with a broken router behind it (the fault is in routing, not GLBP); (2) an AI fix that is correct but incomplete (TK2: amend); (3) one-way ESP evidence (encaps rise, decaps 0); (4) "server never received" versus "server rejected" for RADIUS. Environment: Shift 4 = HQ lite H3 (modified STP roots, see D1), EDGE E3, W3 lite (`environments/WAN/W3/lite/`), DC lite with DC-SYSLOG1.

**Build notes.**
- **D1:** VLAN 10's STP root is HQ-DIST2 (24576; DIST1 28672). ioll2-xe routes any frame addressed to either GLBP forwarder MAC (also the other switch's: measured, a CML platform behaviour), so the STP root bridge routes all of VLAN 10, and F1 on a non-root DIST is invisible to hosts. With DIST2 as root, F1 breaks **all** of VLAN 10's IPv4 at boot. TK1 therefore reads "the main floor reaches nothing"; a fault that follows DIST2's forwarder ("some PCs, restart sometimes helps") is not reproducible here.
- BR1 does not log `%OSPF-4-ERRRCV`; the TK2 area evidence is the `Area Mismatch` counter on BR1 (`show ip ospf traffic Tunnel21`). The ESP evidence is clear: the hub logs `%SEC-6-IPACCESSLOGNP` for the denied ESP (also in DC-SYSLOG1).
- No shared-secret or accounting line appears on DC-AAA1 (accounting is not sent while the server is DEAD). Only the `Login incorrect` lines are evidence.
- Only the TK1 conditional debug prints anything (`debug ip ospf adj` on HQ-DIST2). Debugs on TK2/TK3 print nothing on iol-xe, so R3 asks for "at least one ticket".
- V1's DC target is 10.255.50.1 (DC services segment is VRF MGMT).
- NTP on the WAN routers: an earlier export had no NTP server on HQ-WAN1 and BR1-RTR1 (IOS drops a `ntp server vrf MGMT` line placed before the VRF definition). Fixed: the NTP block now follows `vrf definition MGMT`; both routers reach `sys.peer` about 15-20 min (16 and 18 min measured) and `Clock is synchronized` about 33 min after a cold start (measured). No effect on TK1-TK3.

## Intentional Faults
| ID | Device | Change | Symptom |
|---|---|---|---|
| F1 | HQ-DIST2 | `ip mtu 1400` on Vlan902 (link to CORE1; "MTU preparation") | OSPFv2 DIST2-CORE1 stuck in EXSTART/EXCHANGE (DBD MTU mismatch); OSPFv3 FULL; DIST2 has only connected routes. DIST2 is the VLAN 10 STP root, so it routes every VLAN 10 frame: TK1 (all VLAN 10 IPv4 broken, IPv6 and VLAN 20 fine) |
| F2 | HQ-WAN1 | `permit esp host 203.0.113.131 host 203.0.113.129` removed from `WAN1-INET-IN` (BR2's `.133` lines left) | ESP from BR1's Internet address is denied at the hub: Tunnel21 carries nothing toward HQ (WAN1 decaps 0 for peer .131); Tunnel91/Tunnel41 ride the /29 loopbacks and stay up (TK2 part 2) |
| F3 | BR1-RTR1 | Tunnel21 `ip ospf 1 area 0` (hub: area 21) | area mismatch: BR1 `Area Mismatch` counter rises, no adjacency (TK2 part 1) |
| F4 | HQ-WAN1 | `aaa group server radius RADGRP` without `ip vrf forwarding MGMT` | RADIUS requests leave in the global table and die; WAN1 times out, falls back to local (`admin`); DC-AAA1 logs nothing from WAN1 (TK3) |
| F5 | BR1-RTR1 | RADIUS key `RADKEY12` on DC-AAA1's entry (server's is `RADKEY123`) | DC-AAA1 logs `Login incorrect` with a garbled password for BR1; BR1 discards the replies, marks the server DEAD (`%RADIUS-4-RADIUS_DEAD`), falls back to local (TK3) |

Fault logic: TK1 = F1. TK2 = F3 then F2 in series (fixing F3 alone, the assistant's change, leaves BR1 INIT: its ESP never passes the hub). TK3 = F4 and F5 in parallel, one per device. TK2 and TK3 do not interact: BR1's RADIUS rides Tunnel91 (VRF MGMT).

## Diagnosis / Methodology
**TK1.** HQ-PC1 has its address, gateway ARP answers (flush: gateway MAC alternates 0007.b400.0a01/0a02 round-robin, 0/2 Internet each time): host and access layer eliminated. IPv6 works (OSPFv3 FULL) and VLAN 20 works: not cabling or VLANs. `show glbp brief` on both DISTs is healthy (AVG DIST1, forwarder 1 Active DIST1, forwarder 2 Active DIST2): red herring, and the MAC the host holds does not matter on this platform. `traceroute` from HQ-PC1: hop 1 10.10.10.3 (DIST2, the STP root), then `!H`. DIST2: `show ip route` has only connected/local routes; `show ip ospf neighbor` CORE1 EXSTART (CORE1 side EXCHANGE/INIT); `show ip interface Vlan902` MTU 1400 against CORE1's Ethernet0/2.902 1500; `debug ip ospf adj` on DIST2 shows `Rcv DBD ... mtu 1500 state EXSTART` / `Nbr 10.255.10.1 has larger interface MTU` (in `show logging`). DC-SYSLOG1 holds `%OSPF-5-ADJCHG ... Vlan902 from EXSTART to DOWN, Neighbor Down: Too many retransmissions` from 10.10.99.12.
Wrong fixes tried once (each reverted): `ip ospf mtu-ignore` on Vlan902 (adjacency FULL, PC1 3/3, but `ping 10.10.255.4 size 1450 df-bit` from DIST2 0/3 with `ip mtu 1400` still set: fails V2); `no glbp 10 ip` on DIST2 (DIST1 takes both forwarders, masks TK1, DIST2 stays route-less: fails V2); `glbp 10 load-balancing host-dependent` on the AVG (no effect, hop 1 still 10.10.10.3 then `!H`); static default on DIST2 (PC1 3/3 with asymmetric return, OSPF still EXSTART: fails V2).

**TK2.** BR1-PC1 reaches the Internet host, not HQ/DC: depot LAN and breakout eliminated. IKEv2 SA READY, Tunnel21 up/up on both ends (red herring). BR1: `show ip ospf interface Tunnel21` Area 0, hub Area 21; `show ip ospf traffic Tunnel21` `Area Mismatch` rising, RX Hello 0 (no `%OSPF-4-ERRRCV` on BR1). The assistant's fix (`ip ospf 1 area 21`): BR1 INIT/no FULL (Area 21, neighbor count 1, adjacent 0), WAN1 Tunnel21 neighbor count 0. So the proposal is correct but incomplete: **verdict amend**. `show crypto ipsec sa peer 203.0.113.129` on BR1: encaps 221 rising, decaps rising (hub to BR1 works); on WAN1 `peer 203.0.113.131`: decaps 0. `show ip access-lists WAN1-INET-IN`: ESP lines only for `.133` (BR2, decommissioned) and the /29s; WAN1 log and DC-SYSLOG1 show `%SEC-6-IPACCESSLOGNP: list WAN1-INET-IN denied 50 203.0.113.131 -> 203.0.113.129, N packets` every 5 minutes, and the final `370 deny ip any any log` match counter rises. The management tunnel (Tunnel91, /29 loopbacks) works because those lines exist: why the NOC can still log in. F2 alone (area left at 0): BR1-PC1 still cannot reach HQ; WAN1 now receives BR1's hellos and logs `%OSPF-4-ERRRCV ... mismatched area ID from backbone area from 10.250.21.21, Tunnel21`. `debug ip packet` (ACL) on WAN1 prints nothing (CEF); use the ACL log and counters.
Wrong fixes (V3): `permit esp any any` / `permit ip any any` on the hub, or a static route on BR1 toward HQ (derived, not run: obvious breaches of the standards).

**TK3.** Path eliminated: both routers are in VRF MGMT with a route to 10.50.50.52, `admin` logs in. Server side: DC-AAA1 console log has nothing from WAN1 (HQ devices show as client `lab port 0`), only BR1's requests (also `lab port 0`; the client port does not tell the devices apart, use the source address). WAN1: `test aaa group RADGRP netadmin netpass legacy` gives `No authoritative response from any server`, `show aaa servers` DEAD, no request at the server: `show running-config | section aaa group` has no `ip vrf forwarding MGMT` (**F4**). BR1: same `test aaa` text, but `show aaa servers` shows `Authen: request 2, timeouts 2`, DC-AAA1 logs `Login incorrect (pap: Cleartext password does not match "known good" password): [netadmin/<garbled>] (from client lab port 0)` for the real user, and `(No Auth-Type found: rejecting the user via Post-Auth-Type = Reject): [admin/<garbled>]` for the unknown user `admin`; a garbled password means a key mismatch (**F5**). Collector: `%RADIUS-4-RADIUS_DEAD` from 10.10.254.11 (WAN1) and 10.21.99.1 (BR1). Fallback takes about 10 s per login (2 tries x 5 s) while the server is not yet marked DEAD, 0-1 s after (deadtime 1 minute).
Wrong fixes (V4, derived): local NOC accounts, or `aaa authentication login ... local` first.

## Solution Configuration
```
! HQ-DIST2                              ! BR1-RTR1
interface Vlan902                       interface Tunnel21
 no ip mtu                               ip ospf 1 area 21
                                        radius server DC-AAA1
! HQ-WAN1                                key RADKEY123
ip access-list extended WAN1-INET-IN
 45 permit esp host 203.0.113.131 host 203.0.113.129
aaa group server radius RADGRP
 ip vrf forwarding MGMT
```
Each fix clears only its part: F1 alone clears TK1 (OSPF FULL within 6 s, MTU 1500; TK2/TK3 unchanged); F5 alone: BR1 `test aaa` for netadmin and netops successful, WAN1 still no response; F4: WAN1 successful; F3 alone leaves BR1 INIT; F3 + F2 gives FULL on both ends 6 s after the second change. After a key or VRF fix, `test aaa` still fails until the server leaves DEAD (`radius-server deadtime 1` = 60 s): wait about a minute (or `clear aaa`/re-test) before judging V4, and before the V1 run on the hosts.
Re-entering `ip mtu 1400` on a FULL adjacency keeps it FULL (MTU is checked in DBD only); `shutdown`/`no shutdown` brings back EXSTART.

## Verification
(Captured in CML; trimmed.)
- V1 (build-time script, not shipped; method: 10 neighbour-cache flushes per host, tests: gateway, 10.255.50.1, 192.0.2.200, other site): HQ-PC1 10/10 (gateway MAC alternates 01/02), HQ-PC2 10/10, BR1-PC1 10/10; HQ-PC1 IPv6 2/2; BR1-PC1 traceroute to HQ: 10.21.10.1, 10.250.21.1, 10.10.255.96, 10.10.255.131.
- V2: DIST2 OSPF FULL 1, `Vlan902` MTU 1500, no `ip mtu`/`mtu-ignore`; CORE1 OSPF 8 FULL; `show glbp brief`: AVG DIST1 Active / DIST2 Standby, forwarder 1 Active DIST1, forwarder 2 Active DIST2.
- V3: WAN1 OSPF 5 FULL, BR1 3 FULL; BR1 learns `O IA 10.10.10.0/24` via Tunnel21; `WAN1-INET-IN` has `45 permit esp host 203.0.113.131 host 203.0.113.129`; EDGE1 eBGP to ISP1 up.
- V4: `test aaa group RADGRP netadmin netpass legacy` and `netops opspass`: `User was successfully authenticated` on both routers; SSH `netadmin` privilege 15, `netops` privilege 1 on BR1 (10.21.10.1) and WAN1 (10.250.21.1); DC-AAA1 `Login OK` for both. (SSH from BR1-PC1 needs a temporary `permit 10.21.10.0/24` in the routers' `WAN-MGMT`; use the console instead, or wipe to restore.)
- V5: before/after-F3 evidence as in the TK2 diagnosis. V6: DC-SYSLOG1 lines (`IPACCESSLOGNP`, `RADIUS_DEAD`, `ADJCHG ... Too many retransmissions`) and DIST2 `debug ip ospf adj` output (`Nbr 10.255.10.1 has larger interface MTU`).

## Failure / Recovery Behaviour
Method: silent total loss of a DIST = CML link stop of e1/0, e0/0, e0/1, e0/2 (build-time script, not shipped), restored with link start; never a node stop (RA lifetime rule: wiping a DIST loses `ipv6 nd ra lifetime 12`). Load: HQ-PC1 to 192.0.2.200, IPv4 ping -i 1 on the `seq` clock; IPv6 a 1 s loop of single pings (+-1 s). Every run was restored to steady state first (CORE1 8 FULL, AVG DIST1 Active, RA 4/12 s on both DISTs). Timers: GLBP hello 1 s / hold 3 s; OSPF dead 4 s at CORE1; RA interval 4 s / lifetime 12 s; RSTP.

| Scenario (trigger, end condition) | Runs (raw lost seconds) | Documented range | Basis |
|---|---|---|---|
| Stop all links of DIST1; end: HQ-PC1 IPv4 pings answered again | 4, 0, 4 | 0-5 s | 0 when the return flow already hashes via DIST2; else CORE1 OSPF dead 4 s |
| Same; end: HQ-PC1 IPv6 pings answered again | 12, 12, 10 | 8-14 s | RA lifetime 12 s (default router expires, DIST2 takes over) |
| Restore DIST1 links; end: IPv4 steady | 0, 0, 0 | 0-3 s | preempt delay does not interrupt the path; ECMP re-add |
| Restore DIST1 links; end: IPv6 steady | 24, 22, 0 | 0-25 s | router lifetime/RA timing and DIST1 re-learn; the 0 after 16 s away is not explained further |
| Stop all links of DIST2 (STP root); end: IPv4 answered again | 16, 15, 15 (a pre-run 14) | 14-20 s | ACC1 re-converges (loop guard/RSTP root change on VLAN 10) + GLBP 3 s + OSPF 4 s |
| Same; end: IPv6 answered again | about 19, 14, 19 (+-1 s) | 14-22 s | as above + RA 12 s |
| Restore DIST2 links; end: IPv4 steady | 3, 1, 3 | 0-5 s | STP root returns |
| Restore DIST2 links; end: IPv6 steady | none | 0-3 s | RA of the returning router; the other router keeps serving |
| NOC login with the RADIUS server not answering (`test aaa` and SSH `admin`), end: prompt | BR1 10, 10, 10; WAN1 10, 10, 11 (SSH); `test aaa` 10.35 s each | 10-11 s; 0-1 s while the server is marked DEAD | 2 tries x 5 s (derived); `radius-server deadtime 1` = 60 s |
| F1 fix, end: OSPF FULL | 6 s (poll) | 5-10 s | OSPF 1/4 s timers + DBD exchange |
| F3 + F2 fixes, end: Tunnel21 FULL on both | 6 s | 5-25 s | hello 5 s/dead 20 s on the tunnel |

Cold boot: 16 nodes BOOTED 105 s; protocols converge about 3 min; `Clock is synchronized` on the HQ/DC devices and on HQ-WAN1/BR1-RTR1 25-35 min (33 min measured; `sys.peer` on the WAN routers about 15-20 min). A one-sided `shutdown` would leave the peer port up/up and is not used. RA lifetime recheck after all runs: both DISTs `ND router advertisements are sent every 4 seconds / live for 12 seconds`.

## Answers to Analysis Questions
**Q1** Only VLAN 10 failed: show that the host, gateway ARP, GLBP and IPv6 are fine, then `traceroute` from HQ-PC1 (hop 1 = DIST2, then `!H`) and compare the routing tables of DIST1 and DIST2: DIST2 had no OSPF routes. DIST2 is the STP root of VLAN 10, so it routes all frames whichever forwarder MAC a host holds. **This is a CML artefact (D1), not GLBP behaviour:** on hardware each forwarder routes only for its own virtual MAC, so the same fault on DIST2 would break only the hosts that hold forwarder 2's MAC (about half the PCs, with the affected set changing after an ARP flush, because the AVG hands out the two MACs in turn).
**Q2** Apply the proposal on a copy of the situation (or on the live router, reverting if it fails): BR1 moves to INIT/no FULL, WAN1 still sees no neighbour: the proposal is right (area 21) but incomplete. Evidence for the second fault: encaps rising on BR1 with decaps 0 on WAN1, the ACL without an ESP line for .131, and the `IPACCESSLOGNP` deny line. Verdict: amend.
**Q3** `show crypto ipsec sa peer` on both ends (encaps on BR1 rising, decaps 0 on WAN1), plus the ACL log line `denied 50 203.0.113.131 -> 203.0.113.129` on the hub.
**Q4** Server log: WAN1 produced nothing at DC-AAA1 (never received; requests left in the wrong routing table); BR1 produced `Login incorrect` with a garbled password (received and rejected: wrong shared secret). `show aaa servers` counters complement it.
**Q5** F1: compare MTU/OSPF state before and after (`show ip ospf neighbor`, `show ip interface | include MTU`); F2: a post-change ACL review against the live peer list, and ESP counters (`decaps`); F3: OSPF interface area audit against the design; F4/F5: a `test aaa group RADGRP` run from every device after any AAA change.

**Debrief.** Why IPv6 kept working on the main floor (OSPFv3 carries no MTU mismatch problem here: IPv6 MTU unchanged and the adjacency is FULL). Why the clean-up removed the wrong line (BR2's `.133` lines left, BR1's `.131` ESP removed: removed by pattern, not by owner). Why Tunnel91/Tunnel41 kept working while Tunnel21 failed (the /29 loopback permit lines match the MGMT/OT tunnels but not BR1's Internet address). Would the fault follow one GLBP forwarder? Not on this platform (see the build notes). Debrief question: how would TK1 read on hardware? ("About half the PCs on the main floor cannot leave the VLAN; which half changes after an ARP flush.") What evidence would then separate a per-forwarder fault from a host fault? (The gateway MAC the failing hosts hold: `arp -n` on the host against `show glbp` on the switches.)

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-25 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), iol-xe (IOS XE 17.16.1a), ioll2-xe (IOS XE 17.16.1a), radius, syslog, unmanaged_switch |
