# LAB-004 — Solution

## Summary

Foundation lab (F · G3 · 60 min) for blueprint **3.1.b** (Layer 2/Layer 3 EtherChannel with LACP, PAgP and static), reinforcing **3.1.a** (802.1Q trunks, native VLAN, allowed lists). On the FND bundle pair topology the student builds:

- Po1, an LACP (active/passive) L2 trunk between SW1 and SW2;
- Po2, a PAgP (desirable/auto) L2 trunk between SW1 and SW2, plus a one-sided `on` experiment;
- Po3, a routed LACP bundle SW2–SW3 carrying the pre-built static routes, so PC1 (VLAN 10) reaches PC2 (VLAN 30).

The lab shows that spanning tree treats a bundle as one port, that the port-channel interface's settings drive the members, how the load-balancing hash works, what the EtherChannel misconfiguration guard does with a one-sided `on` bundle, and that losing a member lowers the bundle's bandwidth and therefore changes its STP cost. Toolkit recurrence (4.1): V5 (sourced ping), V7/V8 (log messages), V8 (continuous ping).

No intentional faults (F lab).

## Solution Configuration

Tested in CML. The order matters on ioll2-xe: `switchport trunk encapsulation dot1q` before `switchport mode trunk`; members first, then the port-channel's trunk settings (which the members inherit).

**SW1**
```
interface range Ethernet0/0 - 1
 switchport trunk encapsulation dot1q
 switchport mode trunk
 channel-group 1 mode active
interface Port-channel1
 switchport trunk encapsulation dot1q
 switchport mode trunk
 switchport trunk native vlan 999
 switchport trunk allowed vlan 10,99
interface range Ethernet0/2 - 3
 switchport trunk encapsulation dot1q
 switchport mode trunk
 channel-group 2 mode desirable
interface Port-channel2
 switchport trunk encapsulation dot1q
 switchport mode trunk
 switchport trunk native vlan 999
 switchport trunk allowed vlan 10,99
port-channel load-balance src-dst-ip
```

**SW2**
```
interface range Ethernet0/0 - 1
 switchport trunk encapsulation dot1q
 switchport mode trunk
 channel-group 1 mode passive
interface Port-channel1
 switchport trunk encapsulation dot1q
 switchport mode trunk
 switchport trunk native vlan 999
 switchport trunk allowed vlan 10,99
interface range Ethernet0/2 - 3
 switchport trunk encapsulation dot1q
 switchport mode trunk
 channel-group 2 mode auto
interface Port-channel2
 switchport trunk encapsulation dot1q
 switchport mode trunk
 switchport trunk native vlan 999
 switchport trunk allowed vlan 10,99
interface range Ethernet1/0 - 1
 no switchport
 no ip address
 channel-group 3 mode active
interface Port-channel3
 no switchport
 ip address 10.0.23.0 255.255.255.254
port-channel load-balance src-dst-ip
```
The /31 gives `% Warning: use /31 mask on non point-to-point interface cautiously`; it works.

**SW3**
```
interface range Ethernet1/0 - 1
 no switchport
 no ip address
 channel-group 3 mode active
interface Port-channel3
 no switchport
 ip address 10.0.23.1 255.255.255.254
port-channel load-balance src-dst-ip
```

**R5 note:** `src-dst-ip` is already the ioll2-xe default (`show etherchannel load-balance` shows it on the unconfigured switches and the command does not appear in the running-config). The command is accepted and changes nothing; the expected student answer is "already compliant, nothing to change" (entering it anyway is fine).

**R3 experiment (SW1 only) and restore**
```
! experiment
interface range Ethernet0/2 - 3
 no channel-group
 channel-group 2 mode on
! restore (after the guard has err-disabled the bundle)
interface range Ethernet0/2 - 3
 no channel-group
 channel-group 2 mode desirable
interface Port-channel2
 shutdown
 no shutdown
interface range Ethernet0/2 - 3
 shutdown
 no shutdown
```
`channel-group 2 mode on` directly on a PAgP member is rejected: `Command rejected: is already part of a channel with a different type of protocol enabled` / `% Range command terminated because it failed on Ethernet0/2`.

Transient messages while building (normal, members configured one step at a time): `%ETC-5-CANNOT_BUNDLE2: Et0/2 is not compatible with Et0/3 and will be suspended (native vlan of Et0/2 is 999, Et0/3 id 1)`, `(vlan mask is different)`, then `%ETC-5-COMPATIBLE`; on SW2 `%ETC-5-L3DONTBNDL2: Et1/1 suspended: LACP currently not enabled on the remote port.` until SW3 was configured.

## Verification

Captured in CML. In that boot SW2 was the root bridge for every VLAN (lowest MAC); in another import SW1 may be root, and then the blocking bundle is on SW2 instead.

**V1** — SW2 `show etherchannel summary`
```
Group  Port-channel  Protocol    Ports
------+-------------+-----------+-----------------------------------------------
1      Po1(SU)         LACP        Et0/0(P)        Et0/1(P)
2      Po2(SU)         PAgP        Et0/2(P)        Et0/3(P)
3      Po3(RU)         LACP        Et1/0(P)        Et1/1(P)
```
SW1 shows Po1(SU) LACP and Po2(SU) PAgP with all members (P); SW3 shows `3 Po3(RU) LACP Et1/0(P) Et1/1(P)`. SW2 `show lacp neighbor`: group 1 Et0/0–0/1 flags `SA` (partner SW1 active), group 3 Et1/0–1/1 `SA`. SW1 `show etherchannel 2 port-channel`: `Protocol = PAgP`, members `Desirable-Sl`.

**V2** — SW2 `show interfaces trunk`
```
Port           Mode             Encapsulation  Status        Native vlan
Po1            on               802.1q         trunking      999
Po2            on               802.1q         trunking      999
Port           Vlans allowed on trunk
Po1            10,99
Po2            10,99
```

**V3** — SW1 `show spanning-tree vlan 10` (SW2 root)
```
Interface           Role Sts Cost      Prio.Nbr Type
Et1/0               Desg FWD 100       128.5    P2p Edge
Po1                 Root FWD 56        128.65   P2p
Po2                 Altn BLK 56        128.66   P2p
```
SW2: `Po1 Desg FWD 56 128.65`, `Po2 Desg FWD 56 128.66`. No member interfaces appear. A two-member bundle has `BW 20000 Kbit/sec` and cost 56; a single 10 Mb/s port costs 100. Po1 wins over Po2 on the port ID (128.65 < 128.66), so in either root outcome Po2 is the blocked bundle.

**V4** — PC1
```
PING 10.0.30.102: 4 of 5 received (first lost to ARP)
traceroute to 10.0.30.102
 1  10.0.10.1
 2  10.0.23.1
 3  10.0.30.102
```

**V5** — SW3 `ping 10.0.10.101 source Vlan30 repeat 5`
```
Packet sent with a source address of 10.0.30.1
!!!!!
Success rate is 100 percent (5/5), round-trip min/avg/max = 4/4/5 ms
```
SW2 `show ip route static`: `S 10.0.30.0/24 [1/0] via 10.0.23.1`; SW3: `S 10.0.10.0/24 [1/0] via 10.0.23.0`, `S 10.0.99.0/24 [1/0] via 10.0.23.0`.

**V6** — every switch `show etherchannel load-balance`
```
EtherChannel Load-Balancing Configuration:
        src-dst-ip
EtherChannel Load-Balancing Addresses Used Per-Protocol:
Non-IP: Source XOR Destination MAC address
  IPv4: Source XOR Destination IP address
```

**V7** — R3 (`on` on SW1, PAgP auto on SW2), observed over about 95 s:
- Right after the change, SW1: `2 Po2(SU) - Et0/2(P) Et0/3(P)` (no protocol). SW2: `2 Po2(SD) PAgP Et0/2(I) Et0/3(I)`; `show etherchannel 2 detail` `Port state = Up Sngl-port-Bndl Mstr Not-in-Bndl`; logs `%LINK-3-UPDOWN: Interface Port-channel2, changed state to down`.
- SW2 now runs Et0/2 and Et0/3 as two separate trunks (`Et0/2 Desg FWD 100 128.3`, `Et0/3 Desg FWD 100 128.4`). SW1 hears their BPDUs on its single Po2 and, because sender port ID 128.3 beats Po1's 128.65, moves its root port: `Po1 Altn BLK 56`, `Po2 Root FWD 56`.
- PC1 still pinged its gateway (10/10) and PC2 (5/5) in that window. After an ARP flush a ping to the gateway lost 4 of 5 (the guard acted at that moment).
- About 93 s after the change, SW1's EtherChannel misconfiguration guard fired:
```
%PM-4-ERR_DISABLE: channel-misconfig error detected on Po2, putting Et0/2 in err-disable state
%PM-4-ERR_DISABLE: channel-misconfig error detected on Po2, putting Et0/3 in err-disable state
%PM-4-ERR_DISABLE: channel-misconfig error detected on Po2, putting Po2 in err-disable state
```
  SW1 `show etherchannel summary`: `2 Po2(SD) - Et0/2(D) Et0/3(D)`; `show interfaces status err-disabled`: Et0/2, Et0/3, Po2 `err-disabled channel-misconfig`; STP back to `Po1 Root FWD 56` only.
- SW2 kept `Po2(SD) PAgP Et0/2(I) Et0/3(I)` with both ports FWD, because in CML an err-disabled port does not take the peer's link down.
- After the restore: SW1 `Po2(SU) PAgP Et0/2(P) Et0/3(P)`, `Po1 Root FWD 56`, `Po2 Altn BLK 56`.

**Load-balancing evidence (Q2)** — SW2 packets output before and after PC1 `ping -c 100 -i 0.2 10.0.30.102` (0% loss): Et1/0 222 → 224, Et1/1 350 → 453. The PC1→PC2 flow uses Et1/1 only. `show etherchannel 3 port-channel` shows `Load 00` for both members on IOL, so hash buckets cannot be read from the device.

## Failure / Recovery Behaviour

Test: PC1 `ping -c 120 -i 0.5 10.0.30.102` in the background; SW1 `interface Ethernet0/0` / `shutdown` (17:09:35).

- PC1: `120 packets transmitted, 120 packets received, 0% packet loss`.
- SW1 log: `%LINK-5-CHANGED: Interface Ethernet0/0, changed state to administratively down`, `%LINEPROTO-5-UPDOWN: Line protocol on Interface Ethernet0/0, changed state to down` (no ETC message).
- SW1: `1 Po1(SU) LACP Et0/0(D) Et0/1(P)`; `Port-channel1 is up, line protocol is up`, `BW 10000 Kbit/sec`, `Members in this channel: Et0/1`.
- Po1's STP cost rose from 56 to 100, so SW1 (non-root) moved its VLAN 10/99 root port to Po2: `Po2 Root FWD 56`; Po1 went `Desg BLK 100` → `Desg LRN 100` → settled `Altn BLK 100` at 17:10:57.
- CML platform behaviour: SW2's Et0/0 stayed `up, line protocol is up`, and SW2 kept Et0/0 as `(P)` until the LACP neighbour entry aged out (`show lacp neighbor` Et0/0 age 66 s, slow LACP), then showed `Et0/0(w)` at 17:10:46 (~70 s). In another run the same timeout instead produced `%LINEPROTO-5-UPDOWN ... Ethernet0/0, changed state to down` and `%ETC-5-L3DONTBNDL2: Et0/0 suspended: LACP currently not enabled on the remote port.` on SW2, with `Et0/0(s)` and a zero partner in `show lacp neighbor`. Accept either `(w)` or `(s)` (with or without those logs) as the student's observation. Before the timeout SW2 showed `Po1 Desg BLK 56 128.65 P2p Dispute`: SW2's BPDUs hashed onto the dead member, SW1 claimed designated on Po1, and the RSTP dispute mechanism kept Po1 blocked on SW2, so no loop formed.
- Recovery: `no shutdown` at 17:11:11 → `%LINK-3-UPDOWN: Interface Ethernet0/0, changed state to up`, line protocol up 17:11:15; 17:11:21 SW1 `Po1(SU) LACP Et0/0(P) Et0/1(P)`, `BW 20000`, `Po1 Root FWD 56`, `Po2 Altn BLK 56`.

## Answers to Analysis Questions

**Q1.** A port-channel is one logical interface: STP runs on the Po, sends and receives one set of BPDUs per VLAN on it, and gives it one role and state (`Po1 Root FWD`, `Po2 Altn BLK`; members never appear in `show spanning-tree`). Blocking a single member would still leave the others forwarding the same logical link, so the Po is the unit. Without bundling (the starting state), STP sees four parallel links and blocks three of them (Et0/1–0/3 `Altn BLK` in VLAN 1), so only one 10 Mb/s link carries traffic.

**Q2.** The method is `src-dst-ip`: for IPv4 the switch XORs the source and destination addresses and uses the low-order bits to pick a member. PC1→PC2 is 10.0.10.101 XOR 10.0.30.102; in the last octet 101 (0110 0101) XOR 102 (0110 0110) = 0000 0011, so the low bit is 1 and, with two members, the flow maps to the second member. The counter test agrees: the 100-ping flow left SW2 on Et1/1 only. Every packet of the flow has the same address pair, so it always hashes to the same member. That keeps packets in order, and it means one flow never goes faster than one member; only many flows (different address pairs) spread across both links. (The exact bucket-to-member mapping is platform-internal and IOL does not display it, so the answer is reasoned, then confirmed by counters.)

**Q3.** `on` bundles without negotiation, so the switch cannot tell that the far end does not agree. In R3 SW1 treated Et0/2–0/3 as one logical port while SW2 ran them as two independent trunks. That creates a loop and MAC-flapping risk: a broadcast sent up one link can return on the other into the same logical port. It also disturbed STP: SW1's root port moved to Po2. Traffic kept working for about 90 s, until the misconfiguration guard err-disabled the whole bundle on SW1 (`channel-misconfig`). The capacity was lost, and it came back only after manual recovery. With negotiation on both ends (PAgP or LACP), the mismatched ports would simply not bundle (stand-alone or suspended) and STP would handle them as individual links.

**Q4.** LACP (IEEE 802.3ad/802.1AX) is a standard, supported by every vendor. PAgP is Cisco-proprietary, so a bundle to a non-Cisco switch, server NIC team or firewall must use LACP (or `on`, with the risks from Q3). LACP also offers standby links (more than eight members, the `H` flag), system and port priorities, and fast timers. Choose PAgP only in an all-Cisco legacy environment that already uses it.

**Q5.** (The dead member shows `(w)` or `(s)` on SW2 once the ~70 s LACP timeout expires; both are correct observations.) Po1's bandwidth fell from 20000 to 10000 Kbit/s, and its STP cost, derived from bandwidth, rose from 56 to 100. Po2 still cost 56, so the non-root switch's best path to the root moved to Po2, even though Po1 never went down. Traffic did not stop (0 of 120 pings lost) because the change was a quick RSTP role swap. In CML, SW2 did not see its Et0/0 go down: it only noticed when the LACP neighbour information for Et0/0 expired (slow LACP, about 70–90 s; member shown `(w)`). Until then it kept sending on the dead member, and the RSTP dispute check kept Po1 blocked. On real hardware SW2 would see the link go down at once.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-14 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), ioll2-xe (IOS XE 17.16.1a) |
