# LAB-068 — Solution

## Summary
Educational intent: VXLAN as the Layer 2 data plane of an overlay, built with the simplest control plane (flood-and-learn with static head-end replication) so the mechanics are visible: VTEP (`interface nve1`, source Loopback0), VNI 5040, Ethernet service instance + bridge-domain, MAC learning through `nve1`, a BDI as the stretched subnet's gateway, the 50-byte encapsulation overhead and the underlay MTU, and why `show nve peers` and the VNI state cannot prove the data path. Blueprint 2.3.b (describe VXLAN, control and data plane; I-level). The same encapsulation idea as LISP in LAB-067 (L3 payload, 36 bytes) and GRE in LAB-046 (24 bytes), here carrying L2 frames (50 bytes). Platform: licensed Catalyst 8000V (VXLAN does not work on IOL).

## Intentional Faults
None (foundation lab). The only designed "trap" is R4: with the underlay at 1500 a 1472-byte-payload ping between the servers is dropped by the VTEP.

## Diagnosis / Methodology
Not a troubleshooting lab. Method: (1) check the underlay first (OSPF FULL, Loopback0 reachable both ways, `ping 10.255.90.12 source Loopback0`); (2) build the overlay from the edge inward (service instance on the host port, bridge-domain, VNI member, `nve1`); (3) read `show nve interface nve1`, `show nve vni 5040 detail` (VNI Up, BD 40), `show bridge-domain 40` (remote MAC on `nve1.VNI5040`); (4) size: 1400 passes, 1472 does not, `show ip traffic` `couldn't fragment` counts the drops on the sender of the DF=1 outer packet.

## Solution Configuration
Tested on a fresh import, after a clean cold boot. Applied in this order: RTR4, then RTR3. Note: leave the service-instance submode with `exit` before `bridge-domain 40` (otherwise the line is read as the service instance's own `bridge-domain` subcommand and the global bridge domain is never created).

**AUTO-RTR4** (the routed interface Gi2 becomes the access port; the gateway moves to BDI40):
```
interface GigabitEthernet1
 mtu 1600
interface GigabitEthernet2
 no ip address
 no ip ospf 1 area 0
 service instance 40 ethernet
  encapsulation untagged
  exit
 exit
bridge-domain 40
 member vni 5040
 member GigabitEthernet2 service-instance 40
 exit
interface BDI40
 ip address 10.90.40.1 255.255.255.0
 ip ospf 1 area 0
 no shutdown
interface nve1
 no shutdown
 source-interface Loopback0
 member vni 5040
  ingress-replication 10.255.90.11
```
**AUTO-RTR3**:
```
interface GigabitEthernet4
 mtu 1600
interface GigabitEthernet3
 no shutdown
 service instance 40 ethernet
  encapsulation untagged
  exit
 exit
bridge-domain 40
 member vni 5040
 member GigabitEthernet3 service-instance 40
 exit
interface nve1
 no shutdown
 source-interface Loopback0
 member vni 5040
  ingress-replication 10.255.90.12
```
The `mtu 1600` on RTR3 Gi4 and RTR4 Gi1 is the R4 answer (both ends, so OSPF's MTU check stays satisfied). Pings straight after the change fail until OSPF is FULL again (about 30 s). Alternative (not built, derived): hosts `ip link set eth0 mtu 1450` and BDI40 `ip mtu 1450` plus `ip tcp adjust-mss 1410`; rejected as the design answer because every host would need touching.

## Verification
Captured on a fresh import of the YAML, trimmed.

R1/R2 (RTR3, solved state):
```
show nve interface nve1
Interface: nve1, State: Admin Up, Oper Up
source-interface: Loopback0 (primary: 10.255.90.11 vrf: 0)
show nve vni 5040 detail
nve1       5040       N/A              Up         L2DP  40    CLI N/A
show nve peers
nve1     5040     L2DP 10.255.90.12         ----       -          --   -/-
show bridge-domain 40
    GigabitEthernet3 service instance 40
    vni 5040
   0   5254.0002.1C9E forward dynamic   290  GigabitEthernet3.EFP40
   0   5254.0092.4F88 forward dynamic   298  nve1.VNI5040, VxLAN
                                             src: 10.255.90.11 dst: 10.255.90.12
```
RTR4:
```
show bridge-domain 40
    BDI40  (up)
    GigabitEthernet2 service instance 40
    vni 5040
   -   001E.7A57.69BF to_bdi  static    0    BDI40
   0   5254.0002.1C9E forward dynamic   289  nve1.VNI5040, VxLAN
                                             src: 10.255.90.12 dst: 10.255.90.11
   0   5254.0092.4F88 forward dynamic   299  GigabitEthernet2.EFP40
show ip route 10.90.40.0
  * directly connected, via BDI40
```
AUTO-PC1: ping 10.90.40.102 3/3, ping 10.90.40.1 3/3, ping 10.90.50.31 2/3 (first packet lost to ARP); `ip neigh` shows both neighbours REACHABLE. AUTO-MGMT1 -> AUTO-PC1 2/2. `show nve peers` shows only `----` and `--`/`-/-` for a static peer: no state is learned.

R3 capture (link RTR3 Gi4 - RTR4 Gi1, `udp port 4789`, saved as `lab068-rtr3-rtr4-vxlan.pcap`, decoded with a small Python script; 34 packets: 10 of them are inner DHCP broadcasts from the hosts, 0.0.0.0 -> 255.255.255.255, 392-byte frames, which are BUM traffic the VTEP replicates to the peer; the rest are ARP, the pings and MGMT1 traffic):
```
frame=148 outer 10.255.90.11->10.255.90.12 DF=1 UDP 53242->4789 VXLAN flags=0x08 VNI=5040 inner 5254.0079.ba31->5254.0047.b45e innerframe=98 10.90.40.101->10.90.40.102 (ICMP)
frame=148 outer 10.255.90.12->10.255.90.11 DF=1 UDP 51407->4789 ... (reply)
frame=148 ... UDP 58949->4789 ... 10.90.40.101->10.90.50.31 (via BDI40 MAC 001e.bd23.6abf)
frame=92  ... UDP 54958->4789 ... inner ARP op=1 (92 = 42 + 50)
```
Overhead: 148 - 98 = 50 bytes on the wire = outer Ethernet 14 + outer IP 20 + UDP 8 + VXLAN 8; the outer IP packet is 134 bytes = inner frame 98 (inner Ethernet 14 included) + 36. Flags 0x08 = VNI-valid bit, VNI 5040 = 0x0013B0. Against the underlay's IP MTU the cost is therefore 14 + 36 = 50 bytes per inner IP packet. LISP (LAB-067): 20 + 8 + 8 = 36 bytes on an L3 payload; VXLAN carries the full inner Ethernet frame (L2), so the overhead against the inner IP packet is 50 (36 + the 14-byte inner Ethernet header). The UDP source port differs per flow (53242, 51407, 58949 ...: hash of the inner headers), the destination is always 4789.

R4 (measured before the `mtu 1600` change; re-proved with 1600 on a fresh import):
| Payload | Underlay 1500 | Underlay 1600 |
|---|---|---|
| 1400 | 3/3 (outer frame 1492) | 3/3 |
| 1472 | 0/3; RTR3 `show ip traffic` `couldn't fragment` rises 0 -> 3 (outer IP 1550, DF=1); the counter lags the pings by a few seconds (one run showed 0 right after the first three pings, 1 after the next three, 3 later), so re-read `show ip traffic` after a short wait | 3/3 (outer frame 1564) |
Underlay check on RTR3 with `mtu 1600`: `ping 10.255.90.12 source Loopback0 size 1596 df-bit` 3/3; `size 1700 df-bit` 0/3. Rule: underlay MTU >= inner IP MTU (1500) + 14 (inner Ethernet) + 36 (outer IP/UDP/VXLAN) = 1550 minimum; 1600 leaves headroom (also for a VLAN tag).

R5 note: the stock `show_cmds.py` covers RTR1 and RTR3 only (10.90.50.x, apiuser). For the VTEPs, copy it and set the device list to RTR3 10.255.90.11 and RTR4 10.255.90.12 (user admin), commands `show nve vni 5040 detail` and `show bridge-domain 40`, or loop over both hosts with netmiko `ConnectHandler(device_type='cisco_xe', host=h, username='admin', password=...)` and print each output.

R5 (netmiko `cisco_xe` from MGMT1 to 10.255.90.11 and .12, both devices in 3.8 s, 4 commands each): both VNIs Up; counters RTR3 In 79 / Out 88, RTR4 In 57 / Out 80. (The netmiko venv needs the NAT node for its install.)

## Failure / Recovery Behaviour
Trigger: on RTR4 `interface Loopback0` / `no ip ospf 1 area 0` (named underlay change, not a link stop). Onset end condition: RTR3 `show ip route 10.255.90.12` -> `Subnet not in table`. Restore trigger: `ip ospf 1 area 0` back on Loopback0; end condition: first reply of an AUTO-PC1 `ping -c 1 -W 1 10.90.40.102` loop (poll granularity 1 s, a scripted CLI poll every 1 s).

| Scenario (trigger -> end condition) | Runs (raw) | Documented range | Basis |
|---|---|---|---|
| RTR4 Lo0 out of OSPF -> route gone on RTR3 | 1 s, 1 s, 1 s, 1 s | 1-3 s | SPF delay + 1 s poll |
| Lo0 back in OSPF -> first PC1 reply | 1 s, 1 s, 1 s, 1 s | 1-3 s | SPF delay + 1 s poll; wall clock per command under 20 s incl. CLI session setup |
| Cold boot of the cat8000v pair (day-0 CVAC applied) | 3:43/3:41, 3:33/3:45, 3:22/3:30, 3:19/3:29, 3:23/3:23 (RTR3/RTR4) | 3.3-3.8 min on a quiet server | 5 cold boots; A4 saw 33 min on a busy server, once none |

During the failure: PC1 -> PC2 0 of 2; the VNI stays `Up`, `show nve interface nve1` stays Oper Up, `show nve peers` is unchanged (it never held state), RTR3's `Pkts Out` keeps rising and `Pkts In` stops: the data path is dead while every control-plane indicator is green. Monitor instead: reachability of the peer VTEP address (IP SLA / routing table entry for the peer Loopback), VNI packet counters in both directions, and an end-to-end probe across the overlay.

## Answers to Analysis Questions
1. **Q1.** By flood-and-learn: a frame from a remote host arrives encapsulated, the VTEP learns the inner source MAC against the outer source VTEP (`nve1.VNI5040 src ... dst ...` in `show bridge-domain`). Unknown destinations are flooded to every statically configured peer. A control plane (BGP EVPN type-2 routes; in SD-Access the LISP map-server) distributes MAC/IP bindings so no flooding is needed to learn, and ARP can be answered locally.
2. **Q2.** Broadcasts and unknown unicast are head-end replicated: the ingress VTEP sends one unicast VXLAN copy per peer listed under `ingress-replication` (here one). With N VTEPs each BUM frame costs N-1 copies at the ingress and every peer needs every other peer configured, so it scales poorly (O(N^2) config, O(N) replication). The two problems have different fixes: a multicast underlay sends one copy per link instead of N-1 at the ingress; BGP EVPN discovers peers automatically (no N^2 config), but replication stays head-end unless multicast is used.
3. **Q3.** With static ingress replication there is no peer discovery: `show nve peers` lists the configured address with `----`, `--`, `-/-` whatever the underlay does, and the VNI stays Up while the peer is unreachable (measured). Monitor the peer's loopback in the routing table / an IP SLA probe, the VNI in/out counters (Out rising, In flat = broken), and an end-to-end overlay ping.
4. **Q4.** A VLAN ID has 12 bits (4094 usable); a VNI has 24 bits (about 16 million) in the 8-byte VXLAN header, so segments are not limited per fabric. SD-Access maps a virtual network (VRF/instance) to a VNI (VXLAN-GPO) so tenant separation travels in the header across the fabric rather than relying on VLANs per link; LISP uses the instance-ID (LAB-067: 4097) for the same job in the control plane.
5. **Q5.** Underlay MTU >= inner IP MTU + 50 bytes (14 inner Ethernet + 36 outer IP/UDP/VXLAN): 1550, here 1600. Raising the underlay MTU (a few links, set once, carries any host) is cheaper and safer than lowering every host's MTU/MSS (many endpoints, easy to miss, unmanaged devices). The same overhead appeared in LAB-046 (GRE: 24 bytes), LAB-066 (ERSPAN) and LAB-067 (LISP: 36 bytes).
6. **Q6.** The sender hashes the inner flow into the UDP source port so a transit router's ECMP/LAG hash (5-tuple) spreads different overlay flows over different paths while one flow stays in order; the destination port stays 4789. Observed: 53242, 51407 and 58949 for different flows.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-25 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), cat8000v (IOS XE 17.16.1a), external_connector, iol-xe (IOS XE 17.16.1a), ubuntu (Ubuntu 24.04), unmanaged_switch |
