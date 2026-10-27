# LAB-057 — Solution

## Summary

Two tickets, three faults, one environment (H4 profile of LAB-056 plus the capture host HQ-PC5, 17 nodes). T1 (OPS camera wall black) is two faults in series: a port ACL on the viewer's access port drops IGMP (F2), and a typo in the join-policy ACL on the VLAN 20 DR ignores the reports that get past it (F1). T2 (depot screen black) is a static multicast route that moves the RPF interface for the RP away from the tunnel (F3). Blueprint: 3.3.d:T (multicast: IGMP, PIM, RPF, join policy), X-IGMPSnoop:R (read on HQ-ACC1, ruled out as a cause), 4.3:R (SPAN). Earlier-module candidates ruled out by evidence: VLAN 20 trunking/STP (module 01), VRRP gateway (03), tunnel/IPsec and MTU (07). Wrong-fix traps teach that "video plays" is not the exit criterion: V3 to V6 must still hold.

## Intentional Faults

| ID | Device | Change | Symptom |
|---|---|---|---|
| F1 | HQ-CORE2 | `ip access-list standard OPS-VIDEO` permits `239.10.2.0 0.0.0.255` (CORE1's copy: `239.10.20.0 0.0.0.255`); applied by `ip igmp access-group OPS-VIDEO` on Ethernet0/2.20 | CORE2, the VLAN 20 DR, ignores PC2's reports for 239.10.20.1 (`debug ip igmp`: "Group 239.10.20.1 access denied on Ethernet0/2.20"); no (*,G) OIL. CORE1 (querier, not DR) holds the group without forwarding |
| F2 | HQ-ACC2 | Ethernet1/0 (PC2) carries `ip access-group KIOSK-IN in`; `KIOSK-IN` = `10 deny igmp any any`, `20 permit ip any any` (the kiosk template; e0/3 has it legitimately) | the port drops PC2's reports; no router or snooping switch sees the group; unicast fine. `show access-lists KIOSK-IN`: deny counter rises at each query |
| F3 | BR1-RTR1 | `ip mroute 10.255.10.100 255.255.255.255 10.21.10.254` (RP /32 via a next hop on BR1's own LAN) | RPF for the RP is `Ethernet0/2.10`, `RPF type: multicast (static)`; BR1's (*,G) has incoming e0/2.10 and an empty OIL; no join leaves on Tunnel21, HQ-WAN1 has no Tunnel21 in any OIL |

Series logic (T1): with F2 no router sees a report; fixing F2 alone puts the group on ACC1's uplink (`20 239.10.20.1 I v2 Et0/1`) and on CORE1 (reporter 10.10.20.102), CORE1 (*,G) OIL Null (not DR), CORE2 empty, still black; fixing F1 alone changes nothing (100 s after the change both cores' groups still empty). T2 is independent of T1.

## Diagnosis / Methodology

Start a viewer on HQ-PC2 and BR1-PC1: header only, no interval lines (the viewer prints nothing, not even a loss line). Then walk the path.

1. **Encoder.** CORE1 and CORE2 `show ip mroute 239.10.20.1`: (S,G) 10.10.50.103 with incoming Ethernet0/1.50 / 0/2.50 and packets counted. Eliminated.
2. **L2 and gateway (T1).** PC2 pings 10.10.20.1 and 10.10.50.103; VLAN 20 is on the trunks. Eliminated (module 01/03).
3. **Snooping.** ACC2 `show ip igmp snooping vlan 20`: Admin State Disabled, as documented, so snooping cannot hide the stream. ACC1 (snooping on) `show ip igmp snooping groups vlan 20` has no entry: the reports never leave the OPS switch. Points at ACC2's port.
4. **Host.** SPAN `monitor session 1 source interface Ethernet1/0 rx` / `destination interface Ethernet0/2` on ACC2, then on HQ-PC5 `sudo tcpdump -n -e -i eth0 igmp`: `10.10.20.102 > 239.10.20.1: igmp v2 report 239.10.20.1`. The host joins (Q2). Remove the session afterwards.
5. **F2.** `show running-config interface Ethernet1/0` names `ip access-group KIOSK-IN in`; `show access-lists KIOSK-IN` deny counter rises about once per query. Port ACL drops IGMP although the SPAN (ingress, before the ACL) sees it. The OPS port template (HQ-PC5's e0/2) has no ACL. Purpose of `KIOSK-IN` (not stated in LAB.md): the kiosk template blocks guest kiosks from joining multicast, which is why it must not sit on an OPS port.
6. **F1 (after F2).** CORE1 has the group, CORE2 not. `show ip pim interface`: CORE2 is DR on Ethernet0/2.20. The primary evidence is the cross-core comparison: `show ip igmp interface Ethernet0/2.20 | include access group` names OPS-VIDEO on both cores, and `show access-lists OPS-VIDEO` shows 239.10.2.0/24 on CORE2 against 239.10.20.0/24 on CORE1. Confirmation only if wanted: `debug ip igmp 239.10.20.1` (limited to the group, per the handed-over no-unconditioned-debug habit) on CORE2 prints the access-denied line.
7. **RP.** `show ip pim rp mapping`, `show ip msdp summary`: fine. Eliminated.
8. **T2.** Tunnel up, `Session status: UP-ACTIVE`, OSPF FULL, PIM neighbour on Tunnel21: eliminated. BR1 `show ip igmp groups` lists 239.10.20.1 on Ethernet0/2.10 (viewer fine). BR1 `show ip mroute 239.10.20.1`: (*,G) incoming Ethernet0/2.10, "Mroute", OIL Null. `show ip rpf 10.255.10.100`: interface Ethernet0/2.10, `RPF type: multicast (static)`. `show ip mfib count` (not `show ip mroute count`, which does not count RPF-failed packets for a group with no entry) on HQ-WAN1 shows nothing sent into Tunnel21. Source RPF alone is not the fault: `show ip rpf 10.10.50.103` stays Tunnel21 (unicast, ospf 1).
9. **Red herrings:** querier (CORE1) is not DR (CORE2): normal (Q1 of LAB-056); snooping disabled in VLAN 20 on ACC2 is the documented design; MTU: 1344-byte packets fit `ip mtu 1400`; TTL 16.

Plausible-subsystem table (ticket, candidate, evidence): T1 encoder / VLAN 20 L2 path / viewer host / snooping (X-IGMPSnoop) / RP / access port (F2) / router join policy (F1); T2 tunnel and IPsec / MTU and TTL / viewer and IGMP on BR1 / RPF (F3). Evidence above.

## Solution Configuration

```
HQ-ACC2
interface Ethernet1/0
 no ip access-group KIOSK-IN in

HQ-CORE2
ip access-list standard OPS-VIDEO
 no 10
 10 permit 239.10.20.0 0.0.0.255

BR1-RTR1
no ip mroute 10.255.10.100 255.255.255.255 10.21.10.254
```

`KIOSK-IN` stays on e0/3 (the kiosk template). After the fix, `write memory` is not required for the lab (end state = H4 of LAB-056 with HQ-PC5).

## Verification

Captured on a fresh import after applying the solution above:

```
HQ-CORE2# show access-lists OPS-VIDEO
Standard IP access list OPS-VIDEO
    10 permit 239.10.20.0, wildcard bits 0.0.0.255
HQ-CORE2# show ip igmp groups 239.10.20.1
239.10.20.1      Ethernet0/2.20           00:00:08  00:02:51  10.10.20.102
HQ-CORE2# show ip mroute 239.10.20.1
(*, 239.10.20.1), RP 10.255.10.100, flags: SJC
  Outgoing interface list: Ethernet0/2.20, Forward/Sparse
(10.10.50.103, 239.10.20.1), flags: T
  Incoming interface: Ethernet0/2.50
  Outgoing interface list: Ethernet0/2.20, Forward/Sparse
HQ-WAN1# show ip mroute 239.10.20.1
(10.10.50.103, 239.10.20.1), flags: T
  Incoming interface: Ethernet0/2, RPF nbr 10.10.255.96
  Outgoing interface list: Tunnel21, Forward/Sparse
BR1-RTR1# show ip rpf 10.255.10.100
  RPF interface: Tunnel21
  RPF neighbor: ? (10.250.21.1)
  RPF type: unicast (ospf 1)
BR1-RTR1# show ip mroute 239.10.20.1
(*, 239.10.20.1), RP 10.255.10.100, flags: SJC
  Incoming interface: Tunnel21, RPF nbr 10.250.21.1
  Outgoing interface list: Ethernet0/2.10, Forward/Sparse
HQ-ACC1# show ip igmp snooping groups vlan 20
20        239.10.20.1              I           v2          Et0/1
HQ-PC2 viewer:  0.00-5.00 sec   314 KBytes   514 Kbits/sec   0.252 ms 11459/11703 (98%)   <- first interval, bogus
                5.00-10.00 sec  312 KBytes   512 Kbits/sec   0.373 ms 0/243 (0%)
BR1-PC1 viewer: 0/243 (0%) in every interval from 20 s on
```

Start state at boot (fresh import, both tickets): PC2 and BR1-PC1 viewers print only the header; CORE1/CORE2 `show ip igmp groups 239.10.20.1` empty; CORE2 (*,G) `SP` OIL Null, (S,G) incoming Ethernet0/2.50; `KIOSK-IN` `10 deny igmp any any (2 matches)` rising; ACC2 `show ip igmp snooping vlan 20`: Admin State Disabled; BR1 `show ip rpf 10.255.10.100`: Ethernet0/2.10, `multicast (static)`; BR1 (*,G) `SJPC`, incoming Ethernet0/2.10 "Mroute", OIL Null.

Build-time observations (hostnames as above; times are from the first fixed run):
- F2 alone: ACC1 snooping `20 239.10.20.1 I v2 Et0/1` after 21 s; CORE1 lists the group (reporter 10.10.20.102), CORE1 (*,G) OIL Null; CORE2 empty; PC2 black. F1 alone: no change after 100 s. Both fixed: CORE2 group and (*,G) `SJC` OIL Ethernet0/2.20; PC2 19 consecutive intervals `0/243 (0%)`.
- F3 alone: BR1 (*,G) and (S,G) incoming Tunnel21 nbr 10.250.21.1, HQ-WAN1 OIL Tunnel21; BR1-PC1 `0/243 (0%)` within 21 s; PC2 still black.
- V2 (judged on the viewer's new session after the source change, from its second interval; the first interval of the new session shows the restart): second encoder address 10.10.50.113 on PC3 (`sudo ip addr add`), BR1 mroute lists both (10.10.50.113,G) and (10.10.50.103,G) (1949 packets for .113), viewer 0 %.
- V3: PC2 viewer for 239.10.30.1 and 239.10.2.9: no entry on either core (only 224.0.1.40 on CORE1 e1/0); ACC1's snooping table does list both on Et0/1 (snooping learns them; the routers ignore). 239.10.2.9 is inside the F1 typo range, a good probe of the policy.
- V4: ACC2 e1/0 and e0/2 identical OPS template, e0/3 kiosk template with `KIOSK-IN`, ACC2 snooping disabled for VLAN 20, PC1 (VLAN 10) viewer silent.
- V5: DR VLAN 20 = 10.10.20.3 (CORE2, priority 200) = VRRP master; VLAN 50 DR CORE1 (10.10.50.2) = master; querier on both is CORE1.
- V7 / R4: `monitor session 1 source interface Ethernet1/0 rx`, `destination interface Ethernet0/2` on ACC2; HQ-PC5 `sudo tcpdump -n -e -i eth0 igmp` (needs `sudo`): `10.10.20.102 > 239.10.20.1: igmp v2 report 239.10.20.1` while `KIOSK-IN` still drops it (ingress mirrored before the ACL).

## Failure / Recovery Behaviour

Method: node stop of HQ-CORE2 after `write memory` (silent failure for neighbours; the REST stop returns about 4.7 s after the command, so the media clock is the viewer host). Clock: `tcpdump -tt` on HQ-PC2 for dst 239.10.20.1, gap = last packet before to first after.

| Scenario (trigger -> end condition) | Runs (raw) | Documented range | Basis |
|---|---|---|---|
| Stop HQ-CORE2 (VLAN 20 DR and VRRP master) -> OPS viewer receives again | 2.39 s, 2.69 s, 2.24 s | 2-4 s | measured; derived bound PIM hello holdtime 3.5 s (hello 1 s); CORE1 holds the (S,G) |
| Start HQ-CORE2 (becomes DR at its first PIM hello) -> longest gap | runs 1 and 2: no gap above 0.5 s; run 3: no gap above 0.2 s | 0-0.5 s | measured; CORE2 keeps the (S,G) from flooded VLAN 50 frames |

Platform note: stopping a CML router sends no VRRP/PIM goodbye, so the DR is replaced at the hold time.

**Wrong-fix traps** (each tried once on the start state or a partially fixed lab; result against the V item):

| Trap | Result | Fails |
|---|---|---|
| A: CORE1 `ip pim dr-priority 210` on Ethernet0/1.20 (F2 fixed, F1 present) | video plays; DR VLAN 20 = CORE1 (10.10.20.2) while VRRP master is CORE2; on CORE1 stop CORE2 becomes DR (priority 200) but drops the reports: `show ip igmp groups` empty, PC2 black 100 s+ | V5, V6 |
| B: `no ip igmp access-group` on CORE2 e0/2.20 (F1 present, F2 fixed) | video returns within one query (~60 s); a PC2 viewer for 239.10.30.1 shows `239.10.30.1 Ethernet0/2.20` on CORE2 | V3 |
| C: F2 present, F1 fixed, `no 10` in `KIOSK-IN` | video plays about 90 s later; `KIOSK-IN` now only `20 permit ip any any`; e1/0 and e0/3 still carry the kiosk ACL | V4 |
| D: `ip igmp snooping vlan 20` on ACC2 with F2 present, groups cleared | black for 151 s (deny counter rising), snooping Admin Enabled | V4 (no fix) |
| E: `ip igmp join-group 239.10.20.1` on CORE2 e0/2.20, nothing else fixed | video plays (the router joins without a report; F2 still present); CORE1 also learns the group (reporter 10.10.20.3). CORE2 stop: video returns after 2.16 s via CORE1, then stops again when CORE1's membership expires 2.5-3 min after CORE2 died | V4 at once (port ACL still on); V6 only after about 3 min |
| F: BR1 `ip mroute 10.10.50.0 255.255.255.0 10.250.21.1` (tried from the start state) | `show ip rpf 10.255.10.100` still Ethernet0/2.10 `multicast (static)`, (*,G) OIL Null, BR1-PC1 black. (On a live (S,G) tree it keeps playing, so BR1 traps must be tried from the start state.) | V2 |

Methods: node stop (CORE2 saved first, CORE1 stop for trap A); no `clear ip mroute *` (stalls streams 60 s+); `clear ip igmp group 239.10.20.1` only.

## Answers to Analysis Questions

- **Q1** T1: the viewer prints nothing and CORE1/CORE2 have no group, while the encoder (S,G) arrives on VLAN 50: the failure is between the host and the routers (switch layer first, then router policy). T2: BR1 lists the group but its (*,G) has incoming Ethernet0/2.10 and an empty OIL while WAN1 sends nothing into Tunnel21: router path (RPF), not host or tunnel.
- **Q2** SPAN of PC2's port to HQ-PC5: IGMPv2 reports for 239.10.20.1 leave the host at each query; the same traffic is missing on ACC1's snooping table and on the cores, so the host did its part.
- **Q3** Fixing F2 alone (or F1 alone, which changes nothing): after F2, ACC1's snooping table and CORE1 show the group but CORE2 (the DR) does not, still no video. It tells the engineer the report reaches the segment and that only the DR can forward: a second fault is on the DR.
- **Q4** The router looks up the source (or for (*,G) the RP) in the unicast table unless a static mroute overrides it (LAB-054 primer: `ip mroute`, distance 0); the answer is the incoming interface, and a packet arriving elsewhere is dropped. Prove it with `show ip rpf <source or RP>`: the interface, the neighbour and the type field ("unicast" or "multicast (static)" tells which table decided), and `show ip mfib count` (RPF-failed counters). Detail for the debrief: among the static mroutes and unicast routes the longest match is taken in each and the lower administrative distance wins (static 0, OSPF 110); only `ip multicast longest-match` makes prefix length decide first; a static mroute is used only if its next hop resolves to a PIM interface.
- **Q5** T1: `show ip igmp groups` on the cores (empty with F2; CORE1 only after F2 fixed) and `show ip pim interface` (CORE2 is DR) show the stream stops at the VLAN 20 DR, HQ-CORE2, which should have forwarded it into VLAN 20. T2: `show ip mroute` on BR1 (incoming Ethernet0/2.10, OIL Null) and HQ-WAN1 (no Tunnel21 in OIL): BR1-RTR1 should have joined on Tunnel21 toward HQ-WAN1.

## Build notes

1. **F3 form:** `ip mroute 10.0.0.0 255.0.0.0 100.64.21.0` is ignored (next hop unresolvable), a mroute via 203.0.113.130 is ignored too (RPF stays `unicast (ospf 1)`; a static mroute is skipped when its interface has no PIM), and a mroute via the tunnel is accepted but harmless. Chosen: the RP /32 via a next hop on BR1's LAN (10.21.10.254, PIM-enabled interface); the RPF interface for the RP becomes Ethernet0/2.10. The evidence row still reads `multicast (static)`.
2. The static-join trap fails V4 at once (port ACL still on) and V6 only after about 3 min (membership expiry on CORE1), not at the failover.
3. V1 is read from the second viewer interval (the first shows bogus loss).
4. 203.0.113.131 is BR1's own address; the Internet next hop is .130.
5. The F1 evidence is the ACL comparison between the cores; `debug ip igmp` (limited to the group) only confirms it, since a standard ACL shows no hit counters.
6. ACC2 additions: e0/2 = HQ-PC5 on the OPS template, e0/3 = kiosk template port (shut), `KIOSK-IN` on e0/3 and e1/0.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-14 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), iol-xe (IOS XE 17.16.1a), ioll2-xe (IOS XE 17.16.1a), radius |
