# LAB-066 — Solution

## Summary

Intent: a source router copies the traffic of one port into GRE packets (IP protocol 47, type 0x88BE) and routes them to an analyser anywhere in the IP network. The student builds the session, decodes the headers by hand, controls what is copied (direction, ACL), meets the MTU limit of mirroring and tests what happens when the analyser vanishes. Blueprint: 4.3 (SPAN, RSPAN and ERSPAN) at Perform level; 2.2.b (GRE overhead, MTU) reinforced. Platform: ERSPAN source on cat8000v RTR4 (17.16.1a), analyser tcpdump/tshark on AUTO-MGMT1; the copy crosses one routed hop (RTR4 to RTR3) and then the L2 API segment.

## Intentional Faults

None (F lab).

## Diagnosis / Methodology

Not a troubleshooting lab. Common student problems: (1) session shows Admin Enabled but nothing arrives: check `origin ip address` is routed back (RTR3 has a route to 10.255.90.12 via OSPF) and the capture is on ens2, protocol 47; (2) changing `source interface Gi2 rx` while `both` exists adds nothing, the old line stays: `no source interface GigabitEthernet2` first; (3) a filter cannot be removed by shutting the session: `no monitor session 66` and rebuild; (4) `mtu 1500` makes large copies disappear instead of fixing them (see R4).

## Solution Configuration

AUTO-RTR4 (R1):
```
monitor session 66 type erspan-source
 source interface GigabitEthernet2 both
 destination
  erspan-id 66
  ip address 10.90.50.31
  origin ip address 10.255.90.12
  exit
 no shutdown
```
R3 receive-only (replace the source line): under `monitor session 66 type erspan-source` enter `no source interface GigabitEthernet2`, then `source interface GigabitEthernet2 rx`. R3 filter (SYNs to PC2 leave the router on Gi2 (tx), so the session needs `both` or `tx`):
```
ip access-list extended ERSPAN-SSH
 permit tcp any host 10.90.40.102 eq 22
monitor session 66 type erspan-source
 filter access-group ERSPAN-SSH
```
Removing: `no monitor session 66`, `no ip access-list extended ERSPAN-SSH`. R4: `monitor session 66 type erspan-source / destination / mtu 1500`; undo with `monitor session 66 type erspan-source / destination / mtu 1464` (the default; `show monitor session 66 detail` shows `MTU : 1464` again; `no mtu` alone is an incomplete command). Analyser (MGMT1): `sudo tcpdump -n -i ens2 -XX proto 47`; optional `sudo apt-get install -y tshark` (4.2.2, about 1 min via NAT; run `tshark -i ens2 -Y erspan`). R6: `sudo ip link set ens2 down`, wait 10 s, `sudo ip link set ens2 up`, then start `sudo tcpdump -tt -n -i ens2 proto 47` (tcpdump cannot attach to a down interface).

## Verification

Captured on a fresh import of the YAML unless marked.

`show monitor session 66 detail` on RTR4 (trimmed): `Type : ERSPAN Source Session`, `Status : Admin Enabled`, `Both : Gi2`, `Destination IP Address : 10.90.50.31`, `MTU : 1464`, `Destination ERSPAN ID : 66`, `Origin IP Address : 10.255.90.12`, `IP TTL : 255`. There are no packet counters in this output; on RTR4 the evidence that copies are sent is `show interfaces GigabitEthernet1 | include output` rising (it lags a few seconds), or the capture (V1).

R1/V1, MGMT1 (`tcpdump -n -i ens2 -e proto 47`, three pings PC1 to PC2):
```
10.255.90.12 > 10.90.50.31: GREv0, seq 8, proto unknown (0x88be), length 114   (frame length 148)
10.255.90.12 > 10.90.50.31: GREv0, seq 9, proto unknown (0x88be), length 114
10.255.90.12 > 10.90.50.31: GREv0, seq 10, ...
```
R2/V2 hex of one copy (`-XX`, frame 148 bytes; the outer frame is RTR3's L2 wire):
```
0x0000: 5254 00d7 5e62 5254 00d5 d603 0800 4500   outer Ethernet, then IP 4500
0x0010: 0086 0000 4000 fe2f dac4 0aff 5a0c 0a5a   len 134, DF (4000), TTL 254, proto 0x2f=47, src 10.255.90.12, dst 10.90.50.31
0x0020: 321f 1000 88be 0000 0014 1001 0042 0000   GRE 1000 (S bit) 88be seq 0x14; ERSPAN 1001 0042 = ver 1 (type II), VLAN 1, session 0x42 = 66
0x0030: 0000 5254 0045 aef9 5254 008c 3f5b 0800   index 0; inner Ethernet dst 5254.0045.aef9 (PC2), src 5254.008c.3f5b (RTR4 Gi2)
0x0040: 4500 0054 6b9d 4000 3d01 8a8d 0a5a 0a65   inner IP, ICMP, 10.90.10.101 > 10.90.40.102, TTL 61
```
Overhead = IP 20 + GRE 8 (flags, type, sequence) + ERSPAN II 8 = 36 bytes, plus the outer Ethernet 14 on the wire: a 98-byte inner frame (84-byte IP echo) becomes 134 bytes of IP and a 148-byte frame (matches). tshark 4.2.2 (build lab) shows `ERSPAN Type II`, Vlan 1, SpanID 66, Truncated 0. ERSPAN type III is not configurable on this platform.

R3/V3 (build lab, 3 pings): both directions give 6 ICMP copies (3 requests, 3 replies); `rx` gives 3, all type 0 echo replies, because the port faces PC2 and what the router receives on it is what PC2 sends (replies, DHCP, its own SYN-ACK). Requests to PC2 leave Gi2, so they are `tx`. V4: with `permit tcp any host 10.90.40.102 eq 22` on `both`, one `nc 10.90.40.102 22` from PC1 gave 5 copies, all TCP 22, none for ping or port 80.

R4/V5 (build lab; ping payloads 1372 / 1422 / 1472 = IP 1400 / 1450 / 1500):

| IP size | Copy wire size | State |
|---|---|---|
| 1400 | 1464 | whole |
| 1450 | 1514 | whole (inner frame 1464 fits) |
| 1500 | 1514 | truncated: ERSPAN T bit 1, inner frame cut to 1464 B though the IP header still says 1500 |
| 1500, `mtu 1500` | none | the copy would need 1536 B, the outer DF is set and the 1500-byte path drops it; only small copies arrive |

Nothing is fragmented. V6 (CML packet capture on the RTR3-RTR4 link), measured through the CML REST API (`PUT /api/v0/labs/<lab>/links/<link>/capture/start` with `{"maxtime":30}`, ping from PC1, `GET .../capture/key`, `GET /api/v0/pcap/<key>` with the Bearer token from `/authenticate`; the GUI capture on the link works too): with 4 pings the capture showed 12 GRE packets (10.255.90.12 > 10.90.50.31, protocol 47), 4+4 original ICMP (10.90.10.101 <> 10.90.40.102) and OSPF hellos to 224.0.0.5. The GRE copies sit next to the original ICMP on the link between 10.90.255.6/.7.

## Failure / Recovery Behaviour

Method: a one-ended failure at the analyser (`ip link set ens2 down` on MGMT1); the switch port stays up.

| Scenario (trigger, end condition) | Runs (raw) | Documented range | Basis |
|---|---|---|---|
| MGMT1 `ip link set ens2 up` -> first GRE copy in `tcpdump -tt` on MGMT1 (same host clock) | 3.9, 2.5, 5.5 s (server busy); 0.9, 1.8, 1.5 s (quieter); 0.94, 0.57, 0.08 s | 0.1-6 s | link settle plus up to about 1 s until the next PC1-PC2 packet (ping interval 1 s); measured on a loaded server, so the upper bound is generous |
| Loss of PC1 to PC2 pings during the analyser outage (3 runs, ping at 1 s) | 0, 0, 0 lost | 0 | mirroring is stateless: the source keeps sending, the data path is separate |

During the outage RTR4's session stays Admin Enabled, its Gi1 output counter keeps rising and nothing is reported to the source (GRE has no feedback). RTR3's ARP entry for 10.90.50.31 stayed cached (27 min age), so copies keep being forwarded into the void; an incomplete ARP appears only after the entry is cleared (`clear ip arp` on RTR3 coincided with a console hang in the build: avoid). One observation from the build lab, not reproduced: a 10-minute PC1-PC2 outage with OSPF loss on RTR3 and 94 % QFP load while LAB-065 was running on the same server (host contention, not a lab behaviour). Q4 (CPU) was measured separately: see the answer.

## Answers to Analysis Questions

- **Q1** The copy is an ordinary IP/GRE packet addressed to the analyser, so any routed path works; RSPAN puts the copy in a special VLAN that must exist and be carried on every switch between source and destination (layer 2 end to end).
- **Q2** Same: GRE over IP protocol 47, a flags field (here only the sequence-number bit), a protocol type (0x88BE instead of 0x0800) and a 4-byte sequence number. Different: no tunnel interface or tunnel IP, no keepalive, no state at the destination and no return traffic belonging to the session: ERSPAN is one-way and the destination need not decapsulate or even understand GRE. A link capture showed AUTO-MGMT1 answering every GRE copy (12 of 12) with ICMP type 3 code 2 (protocol unreachable) to 10.255.90.12, because Linux has no handler bound to protocol 47. RTR4 ignores these replies, so they are harmless to the session, but they add load and noise; in production drop them on the collector (an nftables/iptables rule for protocol 47 that is not delivered locally, or a dedicated capture interface) so the collector does not answer; the payload is a whole Ethernet frame plus an 8-byte ERSPAN header, not a routed IP packet.
- **Q3** A copy is bigger than the original by 36 bytes, so a full-size frame no longer fits a 1500 MTU path: the platform truncates the copy at its session MTU (1464 of the inner frame, T bit set) or, with `mtu 1500`, loses it. Fix by raising the transport MTU (jumbo frames toward the analyser), by lowering the frame size at the source (truncate on purpose when only headers matter), by filtering to the traffic that matters, or by using a platform with fragmentation of the outer packet.
- **Q4** The source spends forwarding capacity (replication in the data plane) and, per copied packet, one extra packet of up to 36 bytes more; both directions of a busy port double the load on the egress toward the analyser. The links on the path carry the copy in addition to production traffic and can congest it; a GRE copy has no priority marking unless set (IP precedence 0 by default). The copy is made in the QFP (the forwarding plane), not on the route processor. Measured (`ping -s 1400` at about 195 pps through RTR4): session on, QFP output 387 pps for 197 pps in (every packet sent twice), QFP load 8 % (5 s), RP CPU 3 % (one 14 % sample); session off, QFP output 194 pps, load 5 %, RP CPU 0 %. QFP work scales with the mirrored rate while RP CPU stays nearly flat (`show platform hardware qfp active datapath utilization summary`, `show processes cpu sorted | include CPU utilization`).
- **Q5** The copy contains user traffic in clear (full frames, credentials, MACs) and a host that can reach the analyser address, or spoof the source, can read or inject mirrored data; the analyser address must be restricted by ACL/firewall, and ERSPAN is not encrypted (protect with IPsec or restrict the path).
- **Q6** Nothing: it keeps sending (the session stays enabled, counters on Gi1 rise), there is no feedback from the session itself (ERSPAN is one-way: no keepalive, no state at the destination; the only traffic coming back while the analyser is up is the kernel's ICMP protocol-unreachable per copy, which RTR4 ignores, and with the link down even that stops); the next hop drops or black-holes the copies (RTR3 keeps the cached ARP entry and sends them into the void). Production traffic is not affected.
- **Q7** The port faces PC2: `rx` is what the router receives from PC2 (replies); a SYN to PC2 leaves the router on that port, which is `tx`. Use `both` (or `tx`) with the ACL.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-25 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), cat8000v (IOS XE 17.16.1a), external_connector, iol-xe (IOS XE 17.16.1a), ubuntu (Ubuntu 24.04), unmanaged_switch |
