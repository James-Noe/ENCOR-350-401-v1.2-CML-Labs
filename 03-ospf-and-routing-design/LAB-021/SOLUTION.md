# LAB-021 — Solution

## Summary

Educational intent: take the collapsed-core HQ to three tiers. The student integrates two iol-xe core routers with the ioll2-xe distribution switches over 802.1Q transit VLANs, builds multi-area OSPFv2 and OSPFv3 (cores as ABRs, point-to-point 1/4 s timers, ECMP), moves the VLAN 20 gateway to VRRPv3 on the cores without touching hosts, adds the VLAN 50 gateway, makes the campus dual-stack with RA-based IPv6 gateways, and reasons about three-tier versus collapsed-core behaviour from failure evidence (R5 (c)). Blueprint: 3.2.b:R (multi-area OSPF, reinforced from 016/019), 3.3.c:R (VRRPv3), 3.1.a:R (three-tier trunks and failure domains), 1.1.a:P (three-tier design argued from failure evidence), IPv6:P. The end state equals `environments/HQ/H2/`.

**Build notes (platform behaviour and design choices):**
1. Root-inconsistent SVI: HQ-DIST2's `Vlan10` is **not** withdrawn by autostate when all its VLAN 10 ports are root inconsistent (it stays up/up with its connected route). The VLAN 10 black hole is the stale DIST2 SVI plus ECMP. Q3's key follows the measurement.
2. PC1/PC2 start configs carry their static IPv6 address (the H1 PC files had none), as H2 documents them.
3. Transit VLANs 901-904 are not defined on the DIST switches in the start state; the student creates them (IDs are part of the design stated in LAB.md, names are free). The H2 configs use TRANSIT-C1D1, TRANSIT-C1D2, TRANSIT-C2D1, TRANSIT-C2D2.
4. LAB.md allows up to 2 minutes of VLAN 20 outage for the cut-over; the measured value is about 18 s (scripted single pass).
5. Measured failover times are recorded under Failure / Recovery Behaviour: VRRP/IPv4 about 3 s, IPv6 about 11 s with a CORE2 stop (RA lifetime 12 s held across the restart; another run measured about 9-9.5 s).
6. RA-lifetime replay: IOS saves `ipv6 nd ra lifetime` before `ipv6 nd ra interval` and rejects it at boot while the interval is still 200 s, so after `write memory` + restart the lifetime reverts to 1800 s and IPv6 failover grows to 17-34 s. No order-safe form exists on either platform. The cores carry the EEM applet in Step 3; ioll2-xe has no EEM, so the DIST SVIs revert to 1800 s after their own restart (not used by the R5 tests; re-apply `ipv6 nd ra lifetime 12` by hand).

## Intentional Faults

None (X lab, no faults). The start state is the staged state described in LAB.md; PC3 has no gateway because VLAN 50 has no gateway yet.

## Diagnosis / Methodology

Not a troubleshooting lab. Suggested work order: (1) create VLANs 901-904, trunks, SVIs and the DIST loopbacks, the core subinterfaces for 901-904 and VLAN 50; (2) OSPF/OSPFv3 per the design (passive default, p2p, cost 10, 1/4 s on both ends: ioll2-xe SVIs would derive cost 1, iol-xe subinterfaces 10); (3) VLAN 50 VRRPv3 + STP root on DIST1 (with `show spanning-tree vlan 50`, the root must sit next to CORE1); (4) VLAN 20 cut-over: remove the DIST Vlan20 SVIs (or shut them) **before** adding the .20 subinterfaces, because .2/.3 would be duplicated; (5) IPv6 RA values and preferences. Check each step with `show ip ospf neighbor`, `show ip route ospf | include via`, `show vrrp brief`, `show ipv6 routers`, host traceroutes.

## Solution Configuration

Applied with no configuration errors. Order per step: DISTs first, then cores.

### Step 1: everything except the VLAN 20 cut-over (VLAN 50 first)

**HQ-DIST1**
```
vlan 901
 name TRANSIT-C1D1
vlan 902
 name TRANSIT-C1D2
vlan 903
 name TRANSIT-C2D1
vlan 904
 name TRANSIT-C2D2
ipv6 unicast-routing
spanning-tree vlan 50 priority 24576
interface Ethernet1/0
 switchport trunk encapsulation dot1q
 switchport trunk native vlan 999
 switchport trunk allowed vlan 901,20,50
 switchport mode trunk
 switchport nonegotiate
 spanning-tree portfast trunk
 no shutdown
interface Ethernet1/1
 switchport trunk encapsulation dot1q
 switchport trunk native vlan 999
 switchport trunk allowed vlan 903
 switchport mode trunk
 switchport nonegotiate
 spanning-tree portfast trunk
 no shutdown
interface Loopback0
 ip address 10.255.10.11 255.255.255.255
 ipv6 address 2001:DB8:FFFF:10::11/128
 ip ospf 1 area 10
 ospfv3 1 ipv6 area 10
interface Vlan901
 ip address 10.10.255.3 255.255.255.254
 ipv6 address 2001:DB8:10:FFFF::3/127
 ip ospf 1 area 10
 ip ospf network point-to-point
 ip ospf cost 10
 ip ospf hello-interval 1
 ip ospf dead-interval 4
 ospfv3 1 ipv6 area 10
 ospfv3 network point-to-point
 ospfv3 cost 10
 ospfv3 hello-interval 1
 ospfv3 dead-interval 4
 no shutdown
interface Vlan903
 ip address 10.10.255.7 255.255.255.254
 ipv6 address 2001:DB8:10:FFFF::7/127
 ip ospf 1 area 10
 ip ospf network point-to-point
 ip ospf cost 10
 ip ospf hello-interval 1
 ip ospf dead-interval 4
 ospfv3 1 ipv6 area 10
 ospfv3 network point-to-point
 ospfv3 cost 10
 ospfv3 hello-interval 1
 ospfv3 dead-interval 4
 no shutdown
interface Vlan10
 ip address 10.10.10.2 255.255.255.0
 ipv6 address 2001:DB8:10:10::2/64
 ip ospf 1 area 10
 ospfv3 1 ipv6 area 10
 ipv6 nd router-preference high
 ipv6 nd ra interval 4
 ipv6 nd ra lifetime 12
 glbp 10 ip 10.10.10.1
 glbp 10 priority 110
 glbp 10 preempt delay minimum 30
 glbp 10 timers 1 3
 no shutdown
interface Vlan99
 ip address 10.10.99.11 255.255.255.0
 ip ospf 1 area 10
 standby version 2
 standby 99 ip 10.10.99.1
 standby 99 priority 110
 standby 99 preempt delay minimum 30
 standby 99 timers 1 3
 no shutdown
router ospf 1
 router-id 10.255.10.11
 passive-interface default
 no passive-interface Vlan901
 no passive-interface Vlan903
router ospfv3 1
 router-id 10.255.10.11
 address-family ipv6 unicast
  passive-interface default
  no passive-interface Vlan901
  no passive-interface Vlan903
  exit-address-family
```

**HQ-DIST2**
```
vlan 901
 name TRANSIT-C1D1
vlan 902
 name TRANSIT-C1D2
vlan 903
 name TRANSIT-C2D1
vlan 904
 name TRANSIT-C2D2
ipv6 unicast-routing
interface Ethernet1/0
 switchport trunk encapsulation dot1q
 switchport trunk native vlan 999
 switchport trunk allowed vlan 902
 switchport mode trunk
 switchport nonegotiate
 spanning-tree portfast trunk
 no shutdown
interface Ethernet1/1
 switchport trunk encapsulation dot1q
 switchport trunk native vlan 999
 switchport trunk allowed vlan 904,20,50
 switchport mode trunk
 switchport nonegotiate
 spanning-tree portfast trunk
 no shutdown
interface Loopback0
 ip address 10.255.10.12 255.255.255.255
 ipv6 address 2001:DB8:FFFF:10::12/128
 ip ospf 1 area 10
 ospfv3 1 ipv6 area 10
interface Vlan902
 ip address 10.10.255.5 255.255.255.254
 ipv6 address 2001:DB8:10:FFFF::5/127
 ip ospf 1 area 10
 ip ospf network point-to-point
 ip ospf cost 10
 ip ospf hello-interval 1
 ip ospf dead-interval 4
 ospfv3 1 ipv6 area 10
 ospfv3 network point-to-point
 ospfv3 cost 10
 ospfv3 hello-interval 1
 ospfv3 dead-interval 4
 no shutdown
interface Vlan904
 ip address 10.10.255.9 255.255.255.254
 ipv6 address 2001:DB8:10:FFFF::9/127
 ip ospf 1 area 10
 ip ospf network point-to-point
 ip ospf cost 10
 ip ospf hello-interval 1
 ip ospf dead-interval 4
 ospfv3 1 ipv6 area 10
 ospfv3 network point-to-point
 ospfv3 cost 10
 ospfv3 hello-interval 1
 ospfv3 dead-interval 4
 no shutdown
interface Vlan10
 ip address 10.10.10.3 255.255.255.0
 ipv6 address 2001:DB8:10:10::3/64
 ip ospf 1 area 10
 ospfv3 1 ipv6 area 10
 ipv6 nd ra interval 4
 ipv6 nd ra lifetime 12
 glbp 10 ip 10.10.10.1
 glbp 10 priority 100
 glbp 10 preempt delay minimum 30
 glbp 10 timers 1 3
 no shutdown
interface Vlan99
 ip address 10.10.99.12 255.255.255.0
 ip ospf 1 area 10
 standby version 2
 standby 99 ip 10.10.99.1
 standby 99 priority 100
 standby 99 preempt delay minimum 30
 standby 99 timers 1 3
 no shutdown
router ospf 1
 router-id 10.255.10.12
 passive-interface default
 no passive-interface Vlan902
 no passive-interface Vlan904
router ospfv3 1
 router-id 10.255.10.12
 address-family ipv6 unicast
  passive-interface default
  no passive-interface Vlan902
  no passive-interface Vlan904
  exit-address-family
```

**HQ-CORE1**
```
interface Ethernet0/1.901
 description transit VLAN 901 to HQ-DIST1
 encapsulation dot1q 901
 ip address 10.10.255.2 255.255.255.254
 ipv6 address 2001:DB8:10:FFFF::2/127
 ip ospf 1 area 10
 ip ospf network point-to-point
 ip ospf cost 10
 ip ospf hello-interval 1
 ip ospf dead-interval 4
 ospfv3 1 ipv6 area 10
 ospfv3 network point-to-point
 ospfv3 cost 10
 ospfv3 hello-interval 1
 ospfv3 dead-interval 4
interface Ethernet0/1.50
 description VLAN 50 gateway
 encapsulation dot1q 50
 ip address 10.10.50.2 255.255.255.0
 ipv6 address 2001:DB8:10:50::2/64
 ip ospf 1 area 0
 ospfv3 1 ipv6 area 0
 ipv6 nd router-preference high
 ipv6 nd ra interval 4
 ipv6 nd ra lifetime 12
 vrrp 50 address-family ipv4
  address 10.10.50.1 primary
  priority 110
  preempt delay minimum 30
  exit-vrrp
interface Ethernet0/2.902
 description transit VLAN 902 to HQ-DIST2
 encapsulation dot1q 902
 ip address 10.10.255.4 255.255.255.254
 ipv6 address 2001:DB8:10:FFFF::4/127
 ip ospf 1 area 10
 ip ospf network point-to-point
 ip ospf cost 10
 ip ospf hello-interval 1
 ip ospf dead-interval 4
 ospfv3 1 ipv6 area 10
 ospfv3 network point-to-point
 ospfv3 cost 10
 ospfv3 hello-interval 1
 ospfv3 dead-interval 4
router ospf 1
 router-id 10.255.10.1
 passive-interface default
 no passive-interface Ethernet0/0
 no passive-interface Ethernet0/1.901
 no passive-interface Ethernet0/2.902
router ospfv3 1
 router-id 10.255.10.1
 address-family ipv6 unicast
  passive-interface default
  no passive-interface Ethernet0/0
  no passive-interface Ethernet0/1.901
  no passive-interface Ethernet0/2.902
  exit-address-family
```

**HQ-CORE2**
```
interface Ethernet0/1.903
 description transit VLAN 903 to HQ-DIST1
 encapsulation dot1q 903
 ip address 10.10.255.6 255.255.255.254
 ipv6 address 2001:DB8:10:FFFF::6/127
 ip ospf 1 area 10
 ip ospf network point-to-point
 ip ospf cost 10
 ip ospf hello-interval 1
 ip ospf dead-interval 4
 ospfv3 1 ipv6 area 10
 ospfv3 network point-to-point
 ospfv3 cost 10
 ospfv3 hello-interval 1
 ospfv3 dead-interval 4
interface Ethernet0/2.904
 description transit VLAN 904 to HQ-DIST2
 encapsulation dot1q 904
 ip address 10.10.255.8 255.255.255.254
 ipv6 address 2001:DB8:10:FFFF::8/127
 ip ospf 1 area 10
 ip ospf network point-to-point
 ip ospf cost 10
 ip ospf hello-interval 1
 ip ospf dead-interval 4
 ospfv3 1 ipv6 area 10
 ospfv3 network point-to-point
 ospfv3 cost 10
 ospfv3 hello-interval 1
 ospfv3 dead-interval 4
interface Ethernet0/2.50
 description VLAN 50 gateway
 encapsulation dot1q 50
 ip address 10.10.50.3 255.255.255.0
 ipv6 address 2001:DB8:10:50::3/64
 ip ospf 1 area 0
 ospfv3 1 ipv6 area 0
 ipv6 nd ra interval 4
 ipv6 nd ra lifetime 12
 vrrp 50 address-family ipv4
  address 10.10.50.1 primary
  preempt delay minimum 30
  exit-vrrp
router ospf 1
 router-id 10.255.10.2
 passive-interface default
 no passive-interface Ethernet0/0
 no passive-interface Ethernet0/1.903
 no passive-interface Ethernet0/2.904
router ospfv3 1
 router-id 10.255.10.2
 address-family ipv6 unicast
  passive-interface default
  no passive-interface Ethernet0/0
  no passive-interface Ethernet0/1.903
  no passive-interface Ethernet0/2.904
  exit-address-family
```

### Step 2: VLAN 20 cut-over (DIST SVIs removed first, then core subinterfaces and VRRP; one pass per device, outage about 18 s)

**HQ-DIST1**
```
no interface Vlan20
```

**HQ-DIST2**
```
no interface Vlan20
```

**HQ-CORE1**
```
interface Ethernet0/1.20
 description VLAN 20 gateway
 encapsulation dot1q 20
 ip address 10.10.20.2 255.255.255.0
 ipv6 address 2001:DB8:10:20::2/64
 ip ospf 1 area 0
 ospfv3 1 ipv6 area 0
 ipv6 nd ra interval 4
 ipv6 nd ra lifetime 12
 vrrp 20 address-family ipv4
  address 10.10.20.1 primary
  preempt delay minimum 30
  exit-vrrp
```

**HQ-CORE2**
```
interface Ethernet0/2.20
 description VLAN 20 gateway
 encapsulation dot1q 20
 ip address 10.10.20.3 255.255.255.0
 ipv6 address 2001:DB8:10:20::3/64
 ip ospf 1 area 0
 ospfv3 1 ipv6 area 0
 ipv6 nd router-preference high
 ipv6 nd ra interval 4
 ipv6 nd ra lifetime 12
 vrrp 20 address-family ipv4
  address 10.10.20.1 primary
  priority 110
  preempt delay minimum 30
  exit-vrrp
```

CORE1 is the VRRP 50 master (priority 110) and the RA-preferred (High) router on VLAN 50, CORE2 the same for VLAN 20; the other core keeps the default priority 100 and Medium preference. After the solution, a line-set diff of running configs against `environments/HQ/H2/*.cfg` for CORE1/2 and DIST1/2 shows only display-form differences (`encapsulation dot1Q`, normalised allowed lists, hidden defaults).

### Step 3: keep the RA lifetime across a restart (iol-xe cores only; environment convenience, not expected student work)

IOS saves `ra lifetime` ahead of `ra interval`; at boot the lifetime is rejected (`% Cannot set RA lifetime below RA interval`) and stays 1800 s. An EEM applet re-applies it after every boot (tested with `write memory` + node stop/start: 12 s on both RA interfaces).

**What the student is expected to do instead.** The applet is not part of the lab (EEM is taught in module 04). After the R5 node restart the student checks `show ipv6 interface <subinterface>`: `ND router advertisements live for 1800 seconds` instead of 12 shows the lifetime was lost, and the boot log holds `% Cannot set RA lifetime below RA interval`. The fix by hand is `ipv6 nd ra lifetime 12` on each RA interface after the restart. The cause is the save order: the lifetime is saved before the interval, so it is rejected while the interval is still 200 s at boot. Without the re-applied lifetime the IPv6 failover grows from about 9-11 s to 17-34 s (Failure / Recovery Behaviour).

**HQ-CORE1**
```
event manager applet RA-LIFETIME
 event syslog pattern "SYS-5-RESTART"
 action 010 cli command "enable"
 action 020 cli command "configure terminal"
 action 030 cli command "interface Ethernet0/1.20"
 action 040 cli command "ipv6 nd ra lifetime 12"
 action 050 cli command "interface Ethernet0/1.50"
 action 060 cli command "ipv6 nd ra lifetime 12"
```

**HQ-CORE2** (same applet with `Ethernet0/2.20` and `Ethernet0/2.50`)

## Verification

Captured in CML, trimmed.

- Step 1 result: CORE1 OSPFv2 and OSPFv3 FULL/- with CORE2 (Et0/0), DIST1 (Et0/1.901) and DIST2 (Et0/2.902), dead time 00:00:03 (hello 1 / dead 4). DIST1 FULL with CORE1 (Vlan901) and CORE2 (Vlan903) in both protocols. No flaps seen.
- `show ip ospf interface Ethernet0/1.901`: `Network Type POINT_TO_POINT, Cost: 10`, `Hello 1, Dead 4` (same for ospfv3 and for Vlan902 on DIST2). `show ip ospf interface brief` on DIST1: Vl10 and Vl99 DR 0/0 (passive, no adjacency).
- VRRP: CORE1 `Et0/1.50 50 IPv4 110 ... MASTER 10.10.50.2(local) 10.10.50.1`, CORE2 `Et0/2.50 ... 100 BACKUP`; after the cut-over CORE2 `Et0/2.20 20 IPv4 110 MASTER 10.10.20.3(local) 10.10.20.1`, CORE1 `Et0/1.20 100 BACKUP`.
- STP VLAN 50: DIST1 `priority 24576 ... This bridge is the root`; DIST2 28672, Root port Po1 (this boot; the secondary rises to 28672 by design).
- ECMP (`show ip route ospf | include via`): DIST1 reaches 10.10.20.0/24 and 10.10.50.0/24 as O IA metric 20 via 10.10.255.6 (Vlan903) and 10.10.255.2 (Vlan901); DIST2 likewise via Vlan904 and Vlan902; DIST1 to 10.255.10.12/32 [110/21] via both; CORE1 to 10.10.10.0/24 [110/11] via 10.10.255.5 and .3. `show ip cef 10.10.50.103 detail` on DIST1: `per-destination sharing`, next hops 10.10.255.2 Vlan901 and 10.10.255.6 Vlan903.
- IPv6: CORE1 e0/1.50 `RA every 4 seconds / live for 12 seconds / preference High`; CORE2 e0/2.20 the same; `show ipv6 routers` on CORE1 sees CORE2's RA on .20 as Preference=High and on .50 as Medium. PC2 traceroute6 to PC3: first hop 2001:db8:10:20::3 (CORE2); PC3 traceroute6 to PC1: first hop 2001:db8:10:50::2 (CORE1). Both hosts hold two default routes (`ip -6 route show default`).
- After `write memory` and a node stop/start of CORE2 (applet from Step 3): `show ipv6 interface Ethernet0/2.20` and `.50` `ND router advertisements live for 12 seconds`; without the applet 1800 seconds.
- Pings in both stacks, PC1/PC2/PC3 all pairs: 0% loss (the first IPv6 ping to a new destination loses 1: ND). PC1 to PC3 traceroute: 10.10.10.2 (DIST1 SVI), 10.10.255.6 (CORE2 transit), PC3; PC2 to PC3: 10.10.20.3 (CORE2), PC3.
- VLAN 50 first: PC3 reaches 10.10.50.1 (VRRPv3 on dot1q subinterfaces forwards through DIST1/ACC3).
- VLAN 20 cut-over (DIST Vlan20 removed then core subinterfaces added, one script, PC2 ping to PC1 at 1 s): sequence gaps 34 to 51 (16 lost) and 51 to 54 (2 lost): about 18 s outage.
- Day-0 RSA on iol-xe, VTY SSH-only works. `2001:DB8:10:FFFF::0/127` is accepted on CORE1 e0/0, OSPFv3 FULL over it.

## Failure / Recovery Behaviour

Pings at 4/s (`-i 0.25`), lost pings counted from sequence gaps; one lost ping = 0.25 s.

**R5 (a), stop CORE2** (silent failure; `write memory` first; PC2 to PC3 in both stacks; CORE2 was the VLAN 20 master): IPv4 one gap of 12 lost pings (about 3 s). IPv6 one gap of 44 lost pings (about 11 s, bounded by the RA lifetime of 12 s; re-measured with 480 pings per stack at 4/s: IPv4 13 lost, IPv6 44 lost; other runs measured IPv6 36 and 38 lost, about 9-9.5 s: expect 9-11 s, the spread is the RA phase). Without the Step 3 applet the lifetime reverts to 1800 s after the restart and the gap was 17-34 s. Afterwards CORE1 holds `Et0/1.20 20 IPv4 100 MASTER 10.10.20.2(local)` and master for 50; CORE1 OSPFv2/v3 neighbours are DIST1 (Et0/1.901) and DIST2 (Et0/2.902), dead time 00:00:03, CORE2 gone; DIST1 `show ip route 10.10.50.0` shows a single path via Vlan901. V6 log evidence (240 pings per stack at 4/s: IPv4 14 lost, IPv6 39 lost): `node stop` issued at about 05:10:01 UTC; CORE1 `%VRRP-6-STATE: Ethernet0/1.20 IPv4 group 20 state BACKUP -> MASTER` at 05:10:04.985, with `%OSPF-5-ADJCHG: Process 1, Nbr 10.255.10.2 on Ethernet0/0 from FULL to DOWN, Neighbor Down: Dead timer expired` at 05:10:04.588; DIST1 logs `%OSPF-5-ADJCHG: Process 1, Nbr 10.255.10.2 on Vlan903 from FULL to DOWN, Neighbor Down: Dead timer expired` at 05:10:04.869 (OSPFv3 line 05:10:05.163), DIST2 the same on Vlan904 at 05:10:04.755 (OSPFv3 05:10:05.125). All fire about 4 s after the stop, matching the IPv4 gap of about 3.5 s. Recovery: after `node start` no lost pings (zero gaps in 800 pings over 200 s in both stacks); within 70 s CORE2 is `Et0/2.20 ... 110 MASTER` and `Et0/2.50 100 BACKUP`, CORE1 `Et0/1.20 100 BACKUP` (preempt delay 30 s).

**R5 (b), cable pull** (`shutdown` on both ends, back to back): straight trunk CORE1 e0/1 + DIST1 e1/0 (VLANs 901/20/50, PC3 pinging PC1): IPv4 one gap of 2 pings (about 0.5 s), IPv6 no gap. Afterwards CORE1 VRRP groups INIT, CORE2 master for 20 and 50, CORE1 neighbours DIST2 and CORE2 only, DIST1 route to 10.10.50.0/24 via Vlan903 only. Cross trunk CORE1 e0/2 + DIST2 e1/0: 0 lost pings in both stacks; DIST2 route to 10.10.50.0/24 via Vlan904 only. Restored with `no shutdown` on both ends; CORE1 regained `Et0/1.50 MASTER` (110) and `Et0/1.20 BACKUP` after the preempt delay.

**R5 (c), Po1 total loss** (`shutdown` Et0/0 and Et0/1 on both DISTs, 45 s settle): `show spanning-tree inconsistentports` DIST1: VLAN0020 Et0/2 and Et0/3 Root Inconsistent; DIST2: VLAN0010 Et0/2, Et0/3, VLAN0050 Et1/2, VLAN0099 Et0/2, Et0/3, Et1/2 Root Inconsistent. VRRP: both cores MASTER for both groups (each on its own fragment). Pings (4 each), one boot (the ECMP hash is per boot, so which host pairs fail varies between boots; key on the mechanism): PC1 to PC2 and to PC3, IPv4 and IPv6: 100% loss. PC2 to PC1 IPv4 100%, PC2 to PC3 IPv4 and IPv6 100%, PC2 to 10.10.20.1 0%, PC2 to PC1 IPv6 0% (that pair worked on this boot; another boot had PC1 to PC2 working and PC2 to PC1 IPv6 failing). PC3 to PC1 IPv4 100%, PC3 to PC2 IPv4 and IPv6 100%, PC3 to 10.10.50.1 0%, PC3 to PC1 IPv6 0%. Mechanism (`show ip cef exact-route`): CORE1's PC3-to-PC1 return flow hashed to Ethernet0/2.902 (DIST2), and CORE2's PC2-to-PC1 flow to Ethernet0/2.904 (DIST2); DIST2's `Vlan10 is up, line protocol is up , Autostate Enabled` although all its VLAN 10 ports are root inconsistent, so its connected route stays and black-holes the flow. DIST1 exact-route PC1 to PC2 and PC1 to PC3 both hashed to Vlan901 (CORE1), whose VLAN 20 segment is cut off from the hosts (DIST1 downlinks root-inconsistent for VLAN 20). Management (this boot): CORE1 to 10.255.10.12 (DIST2 Lo0) 3/3, to 10.10.10.3 (DIST2 Vlan10) 3/3, to 10.10.99.12 (DIST2 Vlan99) 0/3 (3/3 on another boot **(derived from the per-boot flow hash, not a stored output)**, so say "may fail" for Vlan99, which depends on the flow hash). Restored with `no shutdown` on both ends.

Restore check (step 7): after wiping and restarting CORE1/2, DIST1/2 the start-state checks returned the documented start state; a fresh import of the YAML passed the same checks (cores FULL with each other only, DIST e1/0-1/1 disabled, HSRP 20 DIST2 active, PC3 isolated, PC1 to PC2 passing from the second ping).

## Answers to Analysis Questions

Q1. (derived from the platform rule, not tested by configuring the second subinterface) An iol-xe router has no IRB: it can hold a VLAN's subnet on only one interface, so VLAN 20 and VLAN 50 ride one trunk per core. The transit VLANs are four different /31 subnets, one per link, so all four trunks can route. If a core carried VLAN 20 on both trunks it would need 10.10.20.0/24 on two interfaces, which it cannot do; the router would not bridge the two trunks either, so the VLAN 20 segments on the two trunks would be separate layer-2 domains.

Q2. Measured (see the H2 stage README): iol-xe Ethernet subinterfaces derive cost 10 (10 Mb/s against the 100 Mb/s reference bandwidth); ioll2-xe SVIs derive cost 1 (seen on the user SVIs in `show ip ospf interface brief`; the SVI bandwidth is above the reference). Without explicit values the two ends of a transit link would have different costs per direction (asymmetric paths) and the ECMP sets towards the cores could be unequal. Setting 10 on both ends of every link makes metrics equal and symmetric, so each DIST has two equal-cost paths (metric 20 to the core subnets) and does not depend on a platform default.

Q3. The core removed the dependency of VLAN 10 (and management by loopback) on Po1: with the Po1 pair gone in the collapsed design, VLAN 10 survived only on one DIST and flows that needed the other DIST failed, and DIST2's Vlan99 and everything on it were unreachable. Now the DISTs reach each other and the cores over the transit links, so DIST2's loopback 10.255.10.12 stays reachable from CORE1 (3/3) while its Vlan99 address may not be (0/3 on one boot, 3/3 on another **(derived from the per-boot flow hash)**: it depends on the flow hash): a routed loopback is reachable over any surviving path, a VLAN address is only as reachable as the layer-2 segment it lives on. The dependency that remains is for the core-routed VLANs that span both DISTs: with Po1 down, root guard makes each DIST's downlinks root inconsistent for the VLAN whose root sits on the other DIST, so VLAN 20 and VLAN 50 are split into fragments, each core becomes VRRP master on its own fragment and keeps advertising the connected /24, and the DISTs' ECMP then sends flows to a core whose fragment cannot reach the destination host. Measured: CORE-DIST traffic for the flows above was black-holed, 100% loss for most pairs, and some pairs worked (PC2 and PC3 reaching their own gateway; PC2 to PC1 and PC3 to PC1 over IPv6) depending on which equal-cost path the flow hashed to. For VLAN 10 the black hole is not caused by autostate: DIST2's Vlan10 stays up/up even though every VLAN 10 port is root inconsistent, so its connected route stays in the table and ECMP sends flows to it that it cannot deliver (measured with `show ip cef exact-route` and `show interfaces Vlan10`). What would remove the dependency: a design with a layer-2 path between the DISTs that does not rely on one link bundle (for example a second interconnect, or no VLAN spanning both DISTs, such as routed access); or tracking: VRRP priority tracking of the uplink/the DIST reachability (or a tracked interface that makes the stale SVI go down) so a fragmented core steps down. Tracking is added in H5 (derived, not tested here; ioll2-xe has no object tracking).

Q4. In a separate area the DISTs keep their LSDB limited to area 10 plus summary LSAs from the ABRs: a topology change in the campus floods only inside area 10 and in area 0 the cores see inter-area routes; SPF runs are smaller and failures stay local. With 20 switches in area 10 I would make area 10 totally stubby (the cores send a default route and stop injecting inter-area detail, so the DISTs hold only area 10 routes plus a default, as MS-1 CR1 requires) and summarise at the ABRs, and use `area range` for the user subnets so that a flapping subnet does not cause SPF in area 0 (MS-1 CR1). (Derived: only the two-DIST area was built.)

Q5. DIST2 no longer routes VLAN 20; it is a layer-2 switch for VLAN 20 whose Vlan20 SVI is gone, and it carries the VLAN 20 flows between the hosts (via Po1 or ACC) and the CORE2 straight trunk (e1/1). It stays the STP root because CORE2, the VLAN 20 VRRP master, attaches to DIST2 (its straight trunk), so hosts reach the active gateway with the shortest layer-2 path (the root's ports forward; a root on DIST1 would send the VLAN 20 gateway traffic across Po1). The root alignment is the STP-gateway rule from 012, with the gateway moved from a switch to the core.

Q6. VRRPv3 gives the host one gateway address and MAC (10.10.20.1) that moves between cores, so the host config never changes and failover is the master-down time: measured about 3 s (12 lost pings at 4/s). RAs give each host several default routers with preferences; the host picks the High one and the failover time depends on how fast the host drops the dead router, bounded by the RA lifetime (12 s): measured about 9-11 s (36-44 lost pings at 4/s over three runs) with the Linux kernel on the Alpine hosts, so IPv6 failover is slower than IPv4 here, and it is tuned with the RA interval and lifetime, not with FHRP timers.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-17 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), iol-xe (IOS XE 17.16.1a), ioll2-xe (IOS XE 17.16.1a) |
