# LAB-046 — Solution

## Summary

Foundation lab for the tunnel family (blueprint 2.2.b, GRE configuration and verification). The student builds a GRE overlay across a provider that does not know the site prefixes, then observes: encapsulation as the provider sees it, OSPF over a point-to-point tunnel, keepalive versus OSPF dead-timer failure detection, recursive routing, and overlay MTU/MSS including the PMTUD black hole. Reused by 047 (same topology with IPsec), 048, 049 (recursion as a fault) and 056.

Build notes (all proven in CML): (1) no AD 250 step in R4: with only static defaults as underlay, the OSPF-learned /31 beats the default route by prefix length, so recursion occurs without any AD change; (2) do-not-fragment pings run on R1 because the Alpine busybox `ping` has no DF option; (3) the working values for the 1300-byte path are `ip mtu 1276` with `ip tcp adjust-mss 1236` (1260 stalls: 1260 + 40 + 24 = 1324 > 1300); (4) `no ip unreachables` must be on R2 Ethernet0/0 (where the oversized packet arrives), not Ethernet0/1.

## Intentional Faults

None. R4 and R5 are guided demonstrations, not faults.

## Diagnosis / Methodology

Start state: PC1 pings 10.0.1.1 but not 10.0.100.1 or PC2 (R2 has no route back to 10.0.1.0/24); traceroute dies after hop 1. The provider is the reason, so the overlay is needed.

- **R1.** Capture on the R2-R3 link. Provider sees `10.0.12.0 > 10.0.23.0 proto=47 len=108`, and the reverse; the inner `10.0.1.101 > 10.0.3.101 proto=1` is only visible by decoding the GRE payload. The outer header has no DF bit (IOS does not copy it). Overhead 24 bytes (20 IP + 4 GRE, no key).
- **R2.** OSPF on Tunnel0 is POINT_TO_POINT (GRE default), cost 1000 from the 100 kbit/s default tunnel bandwidth, hello 10 / dead 40; no DR election (`FULL/ -`). Route cost to PC2's LAN is 1000 + 10 = 1010.
- **R3.** Without keepalive the tunnel only tests that its source interface is up and that the destination is routable, so it stays up/up; OSPF alone detects the dead peer (dead timer 40 s). A static route over the tunnel would stay installed and blackhole traffic. With `keepalive 5 3` the line protocol goes down after 3 missed keepalives, which also removes the OSPF neighbour and static routes pointing out of the tunnel.
- **R4.** Advertising the /31s makes R3 learn 10.0.12.0/31 through Tunnel0 (more specific than the static default), so the route to the tunnel destination points into the tunnel itself. Log on R3: `%ADJ-5-PARENT: Midchain parent maintenance ... looped chain attempting to stack`, then about 1-5 s later (1.3-1.4 s and 4.7 s in separate runs; it varies run to run) `%TUN-5-RECURDOWN: Tunnel0 temporarily disabled due to recursive routing` and the OSPF neighbour drops. The tunnel recovers about 60 s later, the /31 is relearned, and the cycle repeats (period 65-75 s). Prevention: never learn the tunnel destination via the tunnel (separate routing protocol or process for the underlay, prefix filter / `distribute-list`, a more specific static route or higher-preference route to the peer, or not advertising the underlay prefixes into the overlay IGP).
- **R5.** Baseline tunnel MTU 1476 (1500 - 24). With R2 Ethernet0/1 at `ip mtu 1300` and no PMTUD, R2 fragments the GRE packets (outer DF not set), so everything works. With `tunnel path-mtu-discovery` the outer DF is set, R2 returns ICMP type 3 code 4 and R1 learns 1300. With R2 Ethernet0/0 `no ip unreachables` that ICMP is never sent: small packets pass, anything whose outer size exceeds 1300 vanishes (black hole). `no ip unreachables` on Ethernet0/1 alone does not help; the ICMP is still sent because the packet was received on Ethernet0/0.

## Solution Configuration

R1 (R3 mirrors with .3, peer addresses swapped, and its LAN):

```
interface Tunnel0
 ip address 10.0.250.1 255.255.255.0
 tunnel source Ethernet0/0
 tunnel destination 10.0.23.0
ip route 10.0.3.0 255.255.255.0 10.0.250.3          ! R3: ip route 10.0.1.0 255.255.255.0 10.0.250.1
```
R3: `ip address 10.0.250.3`, `tunnel destination 10.0.12.0`.

OSPF (replacing the statics; R3 uses router-id 10.255.0.3 and network 10.0.3.0):

```
no ip route 10.0.3.0 255.255.255.0 10.0.250.3
router ospf 1
 router-id 10.255.0.1
 passive-interface default
 no passive-interface Tunnel0
 network 10.0.250.0 0.0.0.255 area 0
 network 10.0.1.0 0.0.0.255 area 0
```
Keepalive (both ends): `interface Tunnel0` / `keepalive 5 3`.

R4 demonstration (both R1 and R3 Ethernet0/0): `ip ospf 1 area 0`; removal: `no ip ospf 1 area 0`.

R5 lab steps: R2 `interface Ethernet0/1` / `ip mtu 1300`; R1 and R3 Tunnel0 `tunnel path-mtu-discovery`; R2 `interface Ethernet0/0` / `no ip unreachables`; reset learned PMTU with `no tunnel path-mtu-discovery` then `tunnel path-mtu-discovery` on both (tested: the black hole reappears), and `sudo ip route flush cache` on PC1.

Fix for the 1300-byte path (both tunnel ends): `ip mtu 1276` and `ip tcp adjust-mss 1236`.

Cleanup / end state: R2 `no ip mtu` on Ethernet0/1 and `ip unreachables` on Ethernet0/0; `no tunnel path-mtu-discovery`; Tunnel0 `ip mtu 1400`, `ip tcp adjust-mss 1360`, `keepalive 5 3`.

## Verification

Captured on a fresh import (statics stage, then OSPF stage):

```
R1# show interfaces tunnel0 | include Tunnel0 is|Tunnel protocol|transport MTU|Tunnel source
Tunnel0 is up, line protocol is up
  Tunnel source 10.0.12.0 (Ethernet0/0), destination 10.0.23.0
  Tunnel protocol/transport GRE/IP
  Tunnel transport MTU 1476 bytes
PC1# traceroute -n -w 2 -m 4 10.0.3.101
 1  10.0.1.1 ...   2  10.0.250.3 ...   3  10.0.3.101 ...
R1# show ip ospf neighbor
10.255.0.3        0   FULL/  -        00:00:38    10.0.250.3      Tunnel0
R1# show ip ospf interface tunnel0 | include Network Type
  Process ID 1, Router ID 10.255.0.1, Network Type POINT_TO_POINT, Cost: 1000
R1# show ip route ospf | include 10.0.3
O        10.0.3.0/24 [110/1010] via 10.0.250.3, 00:00:12, Tunnel0
R1# show interfaces tunnel0 | include Tunnel0 is|Keepalive
Tunnel0 is up, line protocol is up
  Keepalive set (5 sec), retries 3
```
Capture on R3 Ethernet0/0 (decoded): `10.0.12.0 > 10.0.23.0 proto=47 len=108 off=0 GRE[inner 10.0.1.101 > 10.0.3.101 proto=1 len=84 DF]`; reply `10.0.23.0 > 10.0.12.0 proto=47 len=108`.

MTU (R5), from a test run:
- Baseline: R1 DF ping from Ethernet0/1 size 1476 works, 1477 fails; 1500 non-DF works (fragmented).
- R2 `ip mtu 1300`, no PMTUD: capture shows R2 fragmenting the GRE packets (`len=172 MF off=0` then `len=1300 off=152`), PC1 `-s 1400` 3/3.
- With PMTUD: outer header has DF; R2 sends `ICMP type=3 code=4`; R1 DF ping 1276 works, 1277 fails; TCP 100 kB works.
- Black hole (`no ip unreachables` on R2 Ethernet0/0, PMTU reset, PC1 cache flushed): PC1 `ping -s 56` 3/3, `-s 1200` 3/3, `-s 1250` 0/3, `-s 1400` 0/3; 100000-byte nc transfer: `0 /tmp/rx1` at the receiver after 20 s (reproduced on a fresh import: 3/3, 0/3, 0 bytes). Boundary: inner IP 1276 passes, 1277 does not.
- Fixes on a 1300 path: `ip mtu 1400` + MSS 1360: TCP stalls; MSS 1260: TCP stalls; `ip mtu 1400` + MSS 1236: TCP works but `-s 1250` 0/3; `ip mtu 1276` + MSS 1236: TCP 100000 bytes OK, `-s 1250` 2/3 (first lost) and `-s 1400` 3/3 (R1 fragments before encapsulation), R1 DF 1276 OK, 1277 fails.
- Final state (R2 restored, PMTUD removed, 1400/1360): PC1 `-s 1400` 2/3 (first lost), `-s 1472` 3/3; R1 DF ping 1400 3/3, 1401 0/3.

Recursion (R4), R3 log: `%ADJ-5-PARENT: Midchain parent maintenance for IP midchain out of Tunnel0 - looped chain attempting to stack`; about 1-5 s later (1.3-1.4 s and 4.7 s in separate runs; it varies run to run) `%TUN-5-RECURDOWN: Tunnel0 temporarily disabled due to recursive routing` and `%OSPF-5-ADJCHG ... FULL to DOWN, Neighbor Down: Interface down or detached`. Observed cycle: 19:54:39 RECURDOWN, 19:55:44 FULL, 19:56:53 FULL, 19:56:54 RECURDOWN.

## Failure / Recovery Behaviour

Method: cable pull of R3's provider link is `shutdown` on R3 Ethernet0/0 AND R2 Ethernet0/1 (both ends). A one-ended `shutdown` of R3 Tunnel0 is a separate test (R3 step); stopping the CML link would be a silent failure and does not drop an IOL interface.

| Scenario (trigger, end condition) | Runs (s) | Documented range | Basis |
|---|---|---|---|
| Cable pull, no keepalive: from shutdown to R1 OSPF neighbour gone | 39 / 39 / 39 | 35-45 s | measured; dead interval 40 s |
| Cable pull, `keepalive 5 3`: from shutdown to R1 Tunnel0 line protocol down | 18 / 20 / 22 | 15-25 s | measured; 3 x 5 s plus jitter (derived) |
| Cable pull recovery: from `no shutdown` on both ends to tunnel up and OSPF FULL | keepalive: 11 / 14 / 14; none: 6 / 11 / 11 | 5-15 s | measured |
| R3 Tunnel0 shutdown (one end), no keepalive: to R1 OSPF neighbour gone | 32 / 42 / 42 | 30-45 s | measured; dead 40 s, 2 s poll |
| R3 Tunnel0 shutdown, `keepalive 5 3`: to R1 line protocol down | 19 / 21 / 21 | 15-25 s | measured |
| R3 Tunnel0 `no shutdown`: to FULL, no keepalive | 3 / 3 / 3 | 2-10 s | measured |
| R3 Tunnel0 `no shutdown`: to line up and FULL, keepalive | 11 / 8 / 11 | 5-15 s | measured |
| R4: from adding `ip ospf 1 area 0` on both Ethernet0/0 to tunnel line protocol down (RECURDOWN) | 2 / 5 / 5 | 2-35 s | measured (the first, untimed run took about 30 s) |
| R4: from `no ip ospf 1 area 0` on both to tunnel up and FULL | 57 / 57 / 57; a fourth run within 181 s, not re-timed | 55-180 s | measured; the RECURDOWN holddown is about 60 s, and the total varies run to run, so do not rely on one value |

Without keepalive R1's tunnel stays `up, line protocol is up` throughout; with keepalive, the line protocol goes down and the OSPF neighbour goes with it (interface down). Raw readings were taken from a scripted CLI poll polls (1-2 s step).

## Answers to Analysis Questions

1. **Q1:** The provider sees only IP protocol 47 between the two underlay /31 addresses (10.0.12.0 and 10.0.23.0), the packet lengths and timing. It cannot see, without decoding the GRE payload, the site addresses, protocols or ports; GRE has no encryption, so a capture that decodes GRE can read them. The provider cannot route the private prefixes, which is why the overlay is needed.
2. **Q2:** A GRE tunnel is stateless: with no keepalive its line protocol follows only the local source interface and a route to the destination, so it stays up/up when the peer vanishes. A static route over it stays installed and traffic is blackholed. OSPF detects it by the dead timer (40 s) and removes the routes (30-45 s measured). With `keepalive 5 3` the interface itself goes down in 15-25 s, removing both static routes and the neighbour.
3. **Q3:** OSPF advertises the underlay /31 over the tunnel; R3 now learns 10.0.12.0/31 through Tunnel0, a longer prefix than the static default. The route to the tunnel destination points into the tunnel; IOS logs `%ADJ-5-PARENT` (looped chain) and `%TUN-5-RECURDOWN`, the tunnel goes down, the OSPF neighbour drops, the route disappears, and after about 60 s the tunnel comes back and repeats (65-75 s). Prevention: do not advertise the underlay prefixes into the overlay IGP (passive/network statements, distribute-list or prefix filter); run the underlay and overlay in separate routing processes; make the route to the tunnel destination more specific or more preferred via the physical interface.
4. **Q4:** 24 bytes (20-byte outer IP + 4-byte GRE header; no key or checksum), so tunnel MTU 1476 on a 1500 underlay and TCP MSS 1436 (1476 - 40). The lab's final values 1400/1360 leave room for extra encapsulation such as IPsec. For a 1300-byte underlay path: tunnel IP MTU 1300 - 24 = 1276 and MSS 1276 - 40 = 1236. A value of 1260 does not fit: 1260 + 40 + 24 = 1324 > 1300.
5. **Q5:** TCP segments follow the MSS negotiated in the SYN, so clamping to 1236 makes every segment fit inside the 1300-byte path and the black hole disappears. A ping is not TCP: it keeps the size and DF bit the sender chose, MSS does not touch it, and with the ICMP filtered the sender never learns a smaller PMTU. Only a lower tunnel `ip mtu` (so R1 fragments non-DF packets before encapsulation or returns ICMP to the sender) helps non-TCP traffic. Measured: MSS 1236 with `ip mtu 1400`: TCP works, `-s 1250` 0/3; `ip mtu 1276`: the ping works.
6. **Q6:** IPsec adds more overhead (ESP header, IV, padding, trailer; tunnel mode adds a new IP header too), so MTU and MSS values lower; ESP hides the inner addresses and ports from the provider (Q1 changes); with an encrypted payload the outer DF/ICMP handling matters equally, but a PMTUD-based fix interacts with the crypto; and ICMP errors for the outer packet must be mapped back to the inner flow. Lab 047 builds this on the same topology. (Interpretive answer, not measured here.)

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-14 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), iol-xe (IOS XE 17.16.1a) |
