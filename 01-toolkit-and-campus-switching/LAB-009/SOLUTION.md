# LAB-009 — Solution

## Summary

Expansion lab (X · G2 · 90 min) for blueprint **3.1.a, 3.1.b, 3.1.c** (reinforcing everything from 002-007) plus **1.1.a** (two-tier/collapsed-core design). On a fresh 6-node HQ topology (HQ-DIST1/2, HQ-ACC1/2, HQ-PC1/2) with only a hostname and baseline day-0, the student turns six behaviour-based requirements into a working collapsed-core campus: VLANs 10/20/99/999 with no VTP learning (R1), statically-negotiated 802.1q trunks (R2), a standards-based (LACP) EtherChannel between the distribution switches that survives a member loss (R3), HQ-DIST1 as the sole L3 gateway and management-reachable mesh (R4), Rapid PVST+ with HQ-DIST1 root / HQ-DIST2 secondary and PortFast+BPDU guard on host ports (R5), and full host-to-host/host-to-management reachability (R6).

This build also produces the reusable **HQ H0 stage baseline** (`environments/HQ/H0/`), used by LAB-010 and later HQ labs/milestones.

Toolkit recurrence (4.1): V4/V6 (sourced pings from the hosts, `show etherchannel summary`/`show spanning-tree summary` evidence).

No intentional faults (X lab).

## Solution Configuration

Tested in CML. Commands in configuration mode unless noted. Each distribution block lists `interface Port-channel1` before its member interfaces, the order that works.

**HQ-DIST1** (root, sole L3 gateway):
```
vlan 10
 name USERS
vlan 20
 name OPS
vlan 99
 name MGMT
vlan 999
 name NATIVE
ip routing
spanning-tree mode rapid-pvst
spanning-tree vlan 10,20,99 priority 24576
interface Port-channel1
 switchport trunk encapsulation dot1q
 switchport trunk native vlan 999
 switchport trunk allowed vlan 10,20,99
 switchport mode trunk
 switchport nonegotiate
interface Ethernet0/0
 switchport trunk encapsulation dot1q
 switchport trunk native vlan 999
 switchport trunk allowed vlan 10,20,99
 switchport mode trunk
 switchport nonegotiate
 channel-group 1 mode active
interface Ethernet0/1
 switchport trunk encapsulation dot1q
 switchport trunk native vlan 999
 switchport trunk allowed vlan 10,20,99
 switchport mode trunk
 switchport nonegotiate
 channel-group 1 mode active
interface Ethernet0/2
 switchport trunk encapsulation dot1q
 switchport trunk native vlan 999
 switchport trunk allowed vlan 10,20,99
 switchport mode trunk
 switchport nonegotiate
interface Ethernet0/3
 switchport trunk encapsulation dot1q
 switchport trunk native vlan 999
 switchport trunk allowed vlan 10,20,99
 switchport mode trunk
 switchport nonegotiate
interface Vlan10
 ip address 10.10.10.1 255.255.255.0
 no shutdown
interface Vlan20
 ip address 10.10.20.1 255.255.255.0
 no shutdown
interface Vlan99
 ip address 10.10.99.11 255.255.255.0
 no shutdown
```

**HQ-DIST2** (secondary root, no routing — uses a static default route):
```
vlan 10
 name USERS
vlan 20
 name OPS
vlan 99
 name MGMT
vlan 999
 name NATIVE
spanning-tree mode rapid-pvst
spanning-tree vlan 10,20,99 priority 28672
interface Port-channel1
 switchport trunk encapsulation dot1q
 switchport trunk native vlan 999
 switchport trunk allowed vlan 10,20,99
 switchport mode trunk
 switchport nonegotiate
interface Ethernet0/0
 switchport trunk encapsulation dot1q
 switchport trunk native vlan 999
 switchport trunk allowed vlan 10,20,99
 switchport mode trunk
 switchport nonegotiate
 channel-group 1 mode active
interface Ethernet0/1
 switchport trunk encapsulation dot1q
 switchport trunk native vlan 999
 switchport trunk allowed vlan 10,20,99
 switchport mode trunk
 switchport nonegotiate
 channel-group 1 mode active
interface Ethernet0/2
 switchport trunk encapsulation dot1q
 switchport trunk native vlan 999
 switchport trunk allowed vlan 10,20,99
 switchport mode trunk
 switchport nonegotiate
interface Ethernet0/3
 switchport trunk encapsulation dot1q
 switchport trunk native vlan 999
 switchport trunk allowed vlan 10,20,99
 switchport mode trunk
 switchport nonegotiate
interface Vlan99
 ip address 10.10.99.12 255.255.255.0
 no shutdown
ip route 0.0.0.0 0.0.0.0 10.10.99.11
```

**HQ-ACC1 / HQ-ACC2** (access, no routing, host port guarded):
```
vlan 10
 name USERS
vlan 20
 name OPS
vlan 99
 name MGMT
vlan 999
 name NATIVE
no ip routing
spanning-tree mode rapid-pvst
interface Ethernet0/0
 switchport trunk encapsulation dot1q
 switchport trunk native vlan 999
 switchport trunk allowed vlan 10,20,99
 switchport mode trunk
 switchport nonegotiate
interface Ethernet0/1
 switchport trunk encapsulation dot1q
 switchport trunk native vlan 999
 switchport trunk allowed vlan 10,20,99
 switchport mode trunk
 switchport nonegotiate
interface Ethernet1/0
 switchport access vlan 10   ! (vlan 20 on HQ-ACC2)
 switchport mode access
 spanning-tree portfast
 spanning-tree bpduguard enable
interface Vlan99
 ip address 10.10.99.21 255.255.255.0   ! (.22 on HQ-ACC2)
 no shutdown
ip default-gateway 10.10.99.11
```

**Build-order finding — `ip default-gateway` needs `no ip routing` first.** ioll2-xe has a hidden default of `ip routing` **on**, even with no other L3 configuration. With `ip routing` on, `ip default-gateway` is silently accepted but never used — the switch cannot originate traffic off its own subnet. HQ-ACC1/ACC2 need `no ip routing` before `ip default-gateway` for R4 to actually work. HQ-DIST2 does not need this: it uses a *static default route*, which works with `ip routing` left at its hidden-default "on" (nothing else on HQ-DIST2 needs disabling).

**Build-order finding — configure Port-channel1 before its members.** After configuring both distribution switches (trunk + `nonegotiate` + `channel-group ... mode active` on the members, then the same trunk config on `Port-channel1`), `show etherchannel summary` on both switches showed `Po1(SD) LACP Et0/0(s) Et0/1(s)` (suspended): `%ETC-5-CANNOT_BUNDLE2: ... dtp nonegotiate of Et0/0 is 1, Po1 id 0` then `%ETC-5-L3DONTBNDL2: ... LACP currently not enabled on the remote port`. The cause is order: the members were bundled into a Port-channel1 that did not yet have `switchport nonegotiate`. The same happens on a cold boot when a startup config lists Port-channel1 after its members; with Port-channel1 first, the bundle comes up on every cold boot (CML cold-boot test), which is why the `environments/HQ/H0/` configs use that order. Configuring `interface Port-channel1` before adding `channel-group` to the members avoids it live as well: applying the solution in that order gives `Po1(SU) LACP Et0/0(P) Et0/1(P)` immediately on both switches. Fix once it has happened: after both switches have the full config, bounce the two members on **both** switches — `interface range Ethernet0/0-1` / `shutdown` / `no shutdown`. `show etherchannel summary` then settles to `Po1(SU) LACP Et0/0(P) Et0/1(P)` on both ends within a few seconds.

## Verification

**R1 (VLANs, no VTP learning)** — HQ-DIST1 `show vlan brief`:
```
VLAN Name                             Status    Ports
---- -------------------------------- --------- -------------------------------
1    default                          active
10   USERS                            active
20   OPS                              active
99   MGMT                             active
999  NATIVE                           active
```
All four switches were configured with `vtp mode transparent` from day-0 and never changed, so no switch could have learned VLANs from another (design property, not runtime evidence).

**R2 (static, non-negotiating trunks)** — HQ-DIST1 `show interfaces Ethernet0/0 switchport` (representative of all 6 inter-switch links):
```
Administrative Mode: trunk
Administrative Trunking Encapsulation: dot1q
Trunking Native Mode VLAN: 999 (NATIVE)
Trunking VLANs Enabled: 10,20,99
```
`Negotiation of Trunking: Off` confirmed on `Port-channel1` (`switchport nonegotiate` applied).

**R3 (LACP bundle, survives a member loss)** — `show etherchannel summary` (both HQ-DIST1 and HQ-DIST2, after the bounce above):
```
Group  Port-channel  Protocol    Ports
------+-------------+-----------+-----------------------------------------------
1      Po1(SU)         LACP        Et0/0(P)        Et0/1(P)
```
Member-loss test in "Failure / Recovery Behaviour" below.

**R4 (gateway, management mesh)** — HQ-DIST1 `show ip route connected`:
```
C        10.10.10.0/24 is directly connected, Vlan10
C        10.10.20.0/24 is directly connected, Vlan20
C        10.10.99.0/24 is directly connected, Vlan99
```
HQ-DIST1 pinged HQ-DIST2 (10.10.99.12), HQ-ACC1 (10.10.99.21) and HQ-ACC2 (10.10.99.22): all 5/5.

**R5 (root placement, rapid convergence, PortFast/BPDU guard)** — HQ-DIST1 `show spanning-tree summary`:
```
Switch is in rapid-pvst mode
Root bridge for: VLAN0010, VLAN0020, VLAN0099
```
HQ-DIST2 `show spanning-tree summary`: `Root bridge for: none` (priority 28672, secondary as designed). HQ-ACC1/ACC2 `Ethernet1/0` accepted `spanning-tree portfast` + `spanning-tree bpduguard enable` (IOS prints its standard portfast caution banner, not an error).

**R6 (host reachability)** — HQ-PC1:
```
$ ping -c 5 10.10.10.1        # gateway            -> 5/5, avg ~4-6 ms
$ ping -c 5 10.10.20.102      # HQ-PC2             -> 5/5 (after ARP), avg ~7-9 ms
$ ping -c 5 10.10.99.11/.12/.21/.22   # all 4 switch mgmt IPs -> 4/5 or 5/5 (first packet lost to ARP only)
```
HQ-PC2 reciprocal to 10.10.20.1, 10.10.10.101 and all four mgmt IPs: same result.

## Failure / Recovery Behaviour

1. **Po1 member shut** (HQ-DIST1 `interface Ethernet0/0` / `shutdown`): HQ-PC1 -> HQ-PC2 continuous ping, 10/10 received, **0% loss** — the bundle absorbed the loss with no visible outage (only one member was ever needed for this traffic level). `no shutdown` restored `Po1(SU) ... Et0/0(P) Et0/1(P)` without needing another bounce; only the initial bring-up needs the bounce workaround.
2. **HQ-ACC1's HQ-DIST1 uplink shut** (HQ-DIST1 `interface Ethernet0/2` / `shutdown`): HQ-ACC1's VLAN 10 root port moved from Et0/0 to Et0/1 (via HQ-DIST2/Po1) — `show spanning-tree vlan 10` showed Et0/0 go from `Root FWD` to `Desg`/transitional and Et0/1 become `Root FWD`. HQ-PC1 kept reaching both the gateway and HQ-PC2 with **0% loss** in a 5-ping sample taken immediately after the shutdown (rapid-pvst point-to-point reconvergence, well under the 20 s max-age). Restored cleanly (`no shutdown`), traffic unaffected.
3. **HQ-DIST1 node stop** (simulated power failure): total outage confirmed — HQ-PC1 could reach neither its gateway nor HQ-PC2 (100% loss on both), because HQ-DIST1 is the only L3 gateway and STP root in H0. This is the **expected** result (sets up module 02's single-point-of-failure discussion, see Q2). V9 tells the student to save first, so the result a student sees is the saved case: HQ-DIST1 restarts from its startup-config with the full configuration, Po1 comes up when its members are configured Port-channel-first, and service returns without reconfiguration (measured: Po1(SU) with both members (P) and pings restored with no reconfiguration). Measured unsaved case, as a note: on restart HQ-DIST1 reloaded its **startup-config**, not its last running-config; the VLAN database (in `vlan.dat`) survived, but the trunk/channel/SVI configuration did not (no `write memory`) and had to be reapplied, including the Po1 member bounce, before R1-R6 were restored.

## Answers to Analysis Questions

**Q1.** It is "two-tier" because there is no separate core layer: HQ-DIST1/HQ-DIST2 are the distribution pair *and* they do everything a core would otherwise do at this scale — inter-VLAN routing, the demarcation between the routed and switched domains, and the spanning-tree root. The access switches (HQ-ACC1/2) only switch. A three-tier design would add a dedicated core layer above the distribution pair purely for aggregation/scale, with distribution switches no longer directly hosting end-user default gateways at the top of the hierarchy.

**Q2.** Single points of failure: (1) HQ-DIST1, the design's one true single point of failure: it is the **only** L3 gateway (all three off-subnet paths of both hosts), the STP root for every VLAN, and the next hop of HQ-DIST2's default route (10.10.99.11); (2) each access switch for the hosts behind it (HQ-ACC1 for HQ-PC1, HQ-ACC2 for HQ-PC2); (3) each host's single access link. Redundant by design: the two Po1 members between the distribution switches and the dual uplinks of each access switch (one to each distribution switch). If HQ-DIST1 fails, HQ-DIST2 becomes L2 root and the switched fabric keeps working internally, but there is no default gateway anywhere in the topology, so HQ-PC2 (and HQ-PC1) lose all off-subnet reachability, confirmed by the node-stop test above (100% loss). This is deliberate at H0: module 02 removes it by adding a first-hop redundancy protocol (HSRP/GLBP) so HQ-DIST2 can also serve as gateway.

**Q3.** A third tier (a core layer) would add aggregation capacity for more than two distribution switches, a place to summarize routes before they reach WAN/Internet edges, and would let the distribution layer stay purely L2/L3-boundary without also being the single routing choke point. Veridian would need it once there is more than one distribution block to interconnect (e.g. a second building or floor pair) or once the current collapsed-core's single routing point becomes a growth/redundancy problem — which is exactly what H1/H2 in this curriculum add.

**Q4.** Putting the STP root on the same switch as the default gateway keeps the Layer 2 forwarding topology's shortest path aligned with the Layer 3 forwarding path: traffic already has to reach that switch to leave the VLAN, so making it the root as well means no VLAN's frames take a longer L2 detour to reach their gateway. If the root and the gateway were on different switches, some traffic would cross an extra hop to reach the root-ward path before reversing back to the gateway.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-16 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), ioll2-xe (IOS XE 17.16.1a) |
