# LAB-019 — Solution (instructor)

## Summary

Foundation/implementation lab for IPv6 on a campus-shaped bench: IPv6 addressing and link-local next hops, OSPFv3 in address-family form with the OSPFv2 design carried over (areas 0/10, passive default, point-to-point, cost 10, hello 1 / dead 4 s), gateway redundancy by RAs from two layer-3 switches (router preference, interval, lifetime), and an observation of OSPFv3's IPv4 address family. Blueprint: 3.2.b:P (OSPFv3, IPv6 addressing), IPv6:I. Veridian framing: the dual-stack mandate before the HQ cut-over (021 reuses these RA values: preference high on the preferred device, `ra interval 4`, `ra lifetime 12`).

## Intentional Faults

None (implementation lab).

## Diagnosis / Methodology

Not a troubleshooting lab. Checks if a student's IPv6 does not work:
- No adjacency: `show ospfv3 interface` on both ends for timers/network type (a mismatch of hello/dead stops the adjacency; the v3 commands are `ospfv3 hello-interval` / `ospfv3 dead-interval`, not `ip ospf`), and `ipv6 unicast-routing` on all four devices.
- An interface missing from OSPFv3 stays out of the table: `show ospfv3 interface brief`.
- PC1 without a default route: `show ipv6 interface Vlan10` on the switches (RA interval/lifetime/preference) and `ipv6 unicast-routing` (RAs are only sent when routing is enabled).

## Solution Configuration

Applied one device at a time. Platform notes: ioll2-xe accepted `ipv6 nd router-preference high`, `ipv6 nd ra interval` and `ipv6 nd ra lifetime`.

R1:
```
ipv6 unicast-routing
interface Loopback0
 ipv6 address 2001:DB8:FFFF::1/128
 ospfv3 1 ipv6 area 0
interface Ethernet0/0
 ipv6 address 2001:DB8:0:12::1/64
 ospfv3 1 ipv6 area 0
 ospfv3 network point-to-point
 ospfv3 cost 10
 ospfv3 hello-interval 1
 ospfv3 dead-interval 4
interface Ethernet0/1.901
 ipv6 address 2001:DB8:0:FFFF::2/127
 ospfv3 1 ipv6 area 10
 ospfv3 network point-to-point
 ospfv3 cost 10
 ospfv3 hello-interval 1
 ospfv3 dead-interval 4
interface Ethernet0/2.902
 ipv6 address 2001:DB8:0:FFFF::4/127
 ospfv3 1 ipv6 area 10
 (same four ospfv3 lines as 901)
router ospfv3 1
 router-id 10.255.0.1
 address-family ipv6 unicast
  passive-interface default
  no passive-interface Ethernet0/0
  no passive-interface Ethernet0/1.901
  no passive-interface Ethernet0/2.902
```
R2: same pattern: Lo0 `2001:DB8:FFFF::2/128` area 0; Et0/0 `2001:DB8:0:12::2/64` area 0 with the four point-to-point/cost/timer lines; Et0/1 `2001:DB8:0:2::1/64` `ospfv3 1 ipv6 area 0`; `router ospfv3 1` / `router-id 10.255.0.2` / `address-family ipv6 unicast` / `passive-interface default` / `no passive-interface Ethernet0/0`.

SW1:
```
ipv6 unicast-routing
interface Loopback0
 ipv6 address 2001:DB8:FFFF::11/128
 ospfv3 1 ipv6 area 10
interface Vlan901
 ipv6 address 2001:DB8:0:FFFF::3/127
 ospfv3 1 ipv6 area 10
 ospfv3 network point-to-point
 ospfv3 cost 10
 ospfv3 hello-interval 1
 ospfv3 dead-interval 4
interface Vlan10
 ipv6 address 2001:DB8:0:10::2/64
 ospfv3 1 ipv6 area 10
 ipv6 nd router-preference high
 ipv6 nd ra interval 4
 ipv6 nd ra lifetime 12
router ospfv3 1
 router-id 10.255.0.11
 address-family ipv6 unicast
  passive-interface default
  no passive-interface Vlan901
```
SW2: same with Lo0 `::12`, Vlan902 `2001:DB8:0:FFFF::5/127`, Vlan10 `2001:DB8:0:10::3/64`, router-id 10.255.0.12, **no** `router-preference` line (default Medium), same `ra interval 4` / `ra lifetime 12`.

R5 observation (not kept): R1 and R2 Et0/0 `ospfv3 1 ipv4 area 0`; `router ospfv3 1` / `address-family ipv4 unicast` / `passive-interface default` / `no passive-interface Ethernet0/0`; R2 Loopback9 `10.99.2.1/32` with `ospfv3 1 ipv4 area 0` needed `ipv6 enable`.

## Verification

R1 (`show ospfv3 neighbor`, IPv6 AF): FULL/- with 10.255.0.2 on Ethernet0/0, 10.255.0.12 on Ethernet0/2.902, 10.255.0.11 on Ethernet0/1.901, dead time 00:00:03 (hello 1 / dead 4 live).
`show ospfv3 interface Ethernet0/1.901`: `Network Type POINT_TO_POINT, Cost: 10` / `Timer intervals configured, Hello 1, Dead 4, Wait 4, Retransmit 5`. `show ipv6 ospf interface brief`: Lo0 area 0 cost 1 LOOP; Et0/0 area 0 cost 10 P2P; Et0/2.902 and Et0/1.901 area 10 cost 10 P2P.
R1 `show ipv6 route ospf`:
```
O   2001:DB8:0:2::/64 [110/20]  via FE80::A8BB:CCFF:FE00:5000, Ethernet0/0
O   2001:DB8:0:10::/64 [110/11] via FE80::A8BB:CCFF:FE80:5200, Ethernet0/1.901
                                via FE80::A8BB:CCFF:FE80:5100, Ethernet0/2.902
O   2001:DB8:FFFF::2/128 [110/10] via ... Ethernet0/0   (::11, ::12 [110/10] via the SVI neighbours)
```
(link-local values are MAC-derived and differ per boot: LAB.md documents none.) SW2 reaches the remote LAN as `OI 2001:DB8:0:2::/64 [110/30] via R1 Vlan902` and `OI 2001:DB8:0:12::/64 [110/20]`.
PC1 `ip -6 route`: `default via fe80::...5200 dev eth0 metric 1024` and `default via fe80::...5100 dev eth0 metric 1024` (SW1 and SW2 link-locals), the connected `2001:db8:0:10::/64`; address list: static `::101` plus one SLAAC address (`2001:db8:0:10:5054:ff:fe..`).
`traceroute6 -n 2001:db8:0:2::102` from PC1: 1 `2001:db8:0:10::2` (SW1) 2 `2001:db8:0:ffff::2` 3 `2001:db8:0:12::2` 4 `2001:db8:0:2::102`. Three repeated `traceroute6 -m 1`: always `2001:db8:0:10::2`. IPv4 traceroute: 10.0.10.2, 10.0.255.2, 10.0.12.2, 10.0.2.102. Ping both stacks to PC2: replies (the first echo of a fresh host pair is lost to ARP/ND, so a 3-packet ping often shows 2/3).
SW1 `show ipv6 interface Vlan10`: `ND router advertisements are sent every 4 seconds` / `live for 12 seconds` / `advertised default router preference is High`. SW2 `show ipv6 routers`: SW1 `Preference=High` on Vlan10.
PC2: `default via fe80::...5010 dev eth0` (R2's RA) and 2 global addresses (static plus SLAAC).
OSPFv3 database on R1 lists per area and per address family: Router, Inter Area Prefix (ABR), Link (Type-8) and Intra Area Prefix LSAs (the area-0 section has no Inter Area Prefix in the IPv4 AF as no area 10 was enabled there).

R5, R1: IPv4 AF adjacency separate from the IPv6 one (`show ospfv3 neighbor` lists `address-family ipv4` FULL and `address-family ipv6` FULL on Et0/0). `show ip route ospfv3`: `O 10.99.2.1/32 [110/10] via 10.0.12.2, Ethernet0/0`, `Known via "ospfv3 1"`. Needs: `ipv6 enable` (or an IPv6 address) on the interface (`% OSPFv3: IPV6 is not enabled on this interface` otherwise), and its own AF block; only interfaces enabled with `ospfv3 1 ipv4 area N` are carried.

## Failure / Recovery Behaviour

Measurement (method: node stop of SW1 after `write memory`, 0.25 s ping loops on PC1 to PC2 for IPv4 and IPv6, 1 s timestamp resolution):

| RA timers | IPv6 outage | IPv4 (HSRP) outage |
|---|---|---|
| default (interval 200 s, lifetime 1800 s) | about 30 s | about 10 s |
| interval 4 s, lifetime 12 s | about 9 s | about 11 s |

With default timers PC1 does not wait for the 1800 s lifetime: Linux marks the unreachable router through neighbour discovery (reachable time 30 s) and switches to the second default route. A 12 s lifetime removes the route within 12 s of SW1's last RA, which brings IPv6 to HSRP's 10 s hold time. Target in LAB.md (15 s) is the measured value plus margin (a second run measured about 14 s including console lag). R1's return path was not limiting (OSPFv3 1/4 s timers on every transit link): the pings recover as soon as PC1 uses SW2.
Recovery: after SW1 is started again (node start), PC1's first hop is back on SW1 for IPv6 about 5 s later (its first RA with preference High); one earlier run with default timers showed about 4 s of loss and PC1 back on SW1 within about 20 s of the start command. HSRP preempt is delayed 30 s.
RA values after a restart (a known platform limitation): IOS saves `ra lifetime` before `ra interval` and rejects the lifetime at boot, so a switch restarted from a saved 4/12 configuration comes back with interval 4 s but lifetime 1800 s (running-config shows only the interval; ioll2-xe has no EEM to re-apply it). Only SW1 is ever restarted here; its own lifetime matters again only if the student stops it a second time, which then shows the ~30 s NUD-bound outage until `ipv6 nd ra lifetime 12` is re-applied (LAB.md says to re-check the values). Order notes: to return to default timers, remove the lifetime before the interval (`no ipv6 nd ra interval` first is rejected: `% Cannot set RA interval above RA lifetime (12 secs)`); measuring the default timers first avoids this, and after reverting, PC1's 12 s route for that switch can expire before the next RA (default interval 200 s) refreshes it, so send an RS (flap PC1's link) or wait before a default-timer run.
Cable pull R1–R2 (`shutdown` on both Et0/0): PC1 to PC2 100% loss on IPv4 and IPv6 (single path); `no shutdown` on both ends and about 12 s later both stacks 3/3.

## Answers to Analysis Questions

Q1. Any three of: next hops are link-local (FE80::) addresses, not the neighbour's global address; OSPFv3 runs per link, not per subnet (the adjacency forms with no common global prefix, and on the /127 transit links the global addresses are irrelevant); extra LSAs: Link (Type-8) and Intra Area Prefix (Type-9) carry link-local and prefix data separately from the Router LSA; the router ID is still a 32-bit IPv4 value, set explicitly because the process needs one; interface commands are `ospfv3 1 ipv6 area N` and `ospfv3 hello-interval`, and the address family is chosen per process.
Q2. ioll2-xe does not forward on IPv6 FHRP virtual addresses (VRRP and HSRPv2 IPv6 reach MASTER/ACTIVE but the VIP does not forward), and IPv6 does not need a virtual address: hosts take several default routers from RAs and use preference. A real network would weigh the host's behaviour (some stacks wait for the lifetime or NUD), failover speed (VRRPv3 with 1 s advertisements gives a deterministic 3-4 s on platforms that support it), consistency with the IPv4 FHRP, and tooling.
Q3. The host's detection of a dead router: default RA timers leave it to neighbour discovery (about 30 s here), while a 12 s lifetime (interval 4 s so the lifetime is refreshed often) makes the router's route expire within 12 s, about 9 s measured. HSRP IPv4 failed over in about 10-11 s, set by the 10 s hold time. With the 4/12 values both stacks recover in the same order.
Q4. Yes: the address-family form carries IPv4 and IPv6 in one process with one adjacency per AF (R5 output). Gain: one protocol, one set of timers/area/authentication design, and a single place to tune. Risk: OSPFv3 IPv4 AF needs IPv6 enabled on every interface, replaces a working OSPFv2 during migration (route preference between the two on the same prefix), and operations tooling and engineers know OSPFv2; a mistake affects both stacks.
Q5. The SLAAC address is derived from the interface MAC (EUI-64, `5054:ff:fe...`), so it differs on every boot and every rebuild; the documented address is the static `::101`, which is the same every time.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-04 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), iol-xe (IOS XE 17.16.1a), ioll2-xe (IOS XE 17.16.1a) |
