# EDGE E4 stage baseline (protected edge + WAN backup path)
Built and proven in CML by LAB-053. The stage is the **solved** state (the end state of LAB-053); LAB-053's YAML is the pre-staged start state (E3 + WAN Internet path, no backup tunnel). Cold-boot tested (17 nodes BOOTED in 94 s): OSPF FULL on Tunnel22 and Tunnel122 at HQ-WAN1 and BR2, both IKEv2 SAs READY (Tunnel22 `500/500` no NAT-T, Tunnel122 `4500/4500` `NAT-T is detected  outside`), BR2-PC1 to HQ-PC1 over Tunnel22, EDGE1/EDGE2 EDGE-IN-V4 with 251/252 and the static NAT.

**Profile (17):** HQ-EDGE1, HQ-EDGE2, PROV-ISP1, PROV-ISP2, HQ-CORE1 (stub), HQ-PC1, HQ-SRV1, DMZ switch + DC-RTR1, DC-SYSLOG1, DC-AAA1, DC-NMS1, DC-SW + HQ-WAN1, PROV-INET1, BR2-RTR1, BR2-PC1. Runs alone (17 of 20 licensed nodes). IX switch and PROV-SRV1 left out (PROV-ISP1 Loopback200 192.0.2.200/32 and 2001:DB8:F001:200::200/128 is the Internet host, announced to ISP2 by a `network` statement in each address family).

## New cabling and addressing (on top of E3)
| Link | A | B | Addressing |
|---|---|---|---|
| Core-WAN | HQ-CORE1 e1/0 | HQ-WAN1 e0/2 | 10.10.255.96/31 (CORE1 .96, WAN1 .97), OSPF 1 area 0, p2p, cost 10, hello 1 / dead 4 |
| WAN1 DMZ | HQ-WAN1 e0/3 | DMZ port3 | 10.10.60.41/24 (HSRP 60 VIP 10.10.60.1), not in OSPF |
| WAN1 Internet | HQ-WAN1 e0/0 | PROV-INET1 e0/0 | 203.0.113.128/31 (INET1 .128, WAN1 .129), `WAN1-INET-IN` inbound |
| BR2 Internet | BR2-RTR1 e0/0 | PROV-INET1 e0/2 | 203.0.113.132/31 (INET1 .132, BR2 .133) |
| BR2 LAN | BR2-RTR1 e0/1 | BR2-PC1 | 10.22.10.0/24, PC .101 |
| INET1-ISP1 | PROV-INET1 e1/0 | PROV-ISP1 e0/3 | 198.51.100.128/31 (ISP1 .128, INET1 .129) |
| INET1-ISP2 | PROV-INET1 e1/1 | PROV-ISP2 e0/3 | 198.51.100.130/31 (ISP2 .130, INET1 .131) |

Provider routing (background, read-only): INET1 `192.0.2.0/24` to ISP1 (AD 1) and to ISP2 (AD 5), `198.51.100.0/25` to ISP1, `203.0.113.0/25` to ISP2, W2 statics for the three /29s; ISP1 and ISP2 `203.0.113.128/25` static to INET1, announced to each other over the existing ISP1-ISP2 BGP session. HQ-CORE1 is the E3 stub plus e1/0. BR1, PE1 and Tunnel21 are not in the profile: HQ-WAN1 has e0/1 shut, no provider statics or redistribution, and `WAN1-INET-IN` without the BR1 (.131) lines. HQ-WAN1 and BR2-RTR1 keep the W2 standalone baseline (local AAA, `ntp master 3` on HQ-WAN1, BR2 `ntp server 203.0.113.129`); the edges and the DC keep E3's H3 standard. HQ-WAN1 is not in VRF MGMT: the DC cannot reach it (documented limitation).

## Stage content (the solved state; start state = E3 files + the HQ-WAN1/BR2/INET1/ISP/stub changes above, without the lines below)
- **Both edges:** `ip nat inside source static 10.10.60.41 192.0.2.140` (no port translation, identical on EDGE1 and EDGE2); `EDGE-IN-V4` seq `251 permit udp host 203.0.113.163 eq isakmp host 192.0.2.140 eq isakmp` and `252 permit udp host 203.0.113.163 eq non500-isakmp host 192.0.2.140 eq non500-isakmp` between `250` and `260 deny ip any any log` (26 entries became 28); `EDGE-IN-V6`, PM-COPP, FM-EDGE/FR-EDGE/FE-NMS unchanged. No ESP line.
- **HQ-WAN1:** `ip route 203.0.113.163 255.255.255.255 10.10.60.1`; Tunnel122 (source Ethernet0/3, destination 203.0.113.163, 10.250.122.1/24, `ip mtu 1400`, `ip tcp adjust-mss 1360`, OSPF p2p 5/20, cost 500, area 22, `tunnel protection ipsec profile VPN-PROF-NAT`).
- **BR2-RTR1:** Tunnel122 (source Loopback203 203.0.113.163, destination 192.0.2.140, 10.250.122.22/24, same settings).
- **Both routers:** `crypto ipsec transform-set TS-AES-TRANSPORT esp-aes 256 esp-sha256-hmac` with `mode transport`, `crypto ipsec profile VPN-PROF-NAT` (same IKEv2 profile). **Transport mode, forced by the NAT:** with the tunnel-mode profile `VPN-PROF` the IKE_AUTH fails after the NAT-T float (`There was no IPSEC policy found for received TS`, `TS_UNACCEPTABLE`, Tunnel122 line protocol down): the two ends name different GRE endpoints (10.10.60.41 to 203.0.113.163, 203.0.113.163 to 192.0.2.140). Tunnel22 keeps `VPN-PROF` (tunnel mode, no NAT).

## Measured behaviour (LAB-053)
- (a) NAT-T through IOS static NAT with GRE over IPsec: **tunnel mode FAIL, fallback 1 (transport-mode profile on Tunnel122 only) PASS.** NAT detection itself works (`Host is located NAT inside` on HQ-WAN1, `NAT-T is detected  outside` on BR2); IKE_SA_INIT on UDP 500 then everything on 4500; `in use settings ={Transport UDP-Encaps, }`; `Tunnel transport MTU 1418`, DF 1400 passes and 1401 fails through Tunnel122, so no 40-byte adjustment (rule 3 values hold). Before the edge permits, BR2's first attempt is logged `%SEC-6-IPACCESSLOGP: list EDGE-IN-V4 denied udp 203.0.113.163(500) -> 192.0.2.140(500)` (the discovery evidence).
- (b) CoPP: **PASS, no change needed.** Permitted NAT-T IKE/ESP-in-UDP is transit and moves no class beyond idle drift (re-negotiation window: class-default +15 vs +19 idle); 100 denied UDP 4500 probes from 203.0.113.161 move class-default by about +100 (the logged copies). Counter deltas, `clear policy-map interface` is rejected.
- (c) Tunnel22 and Tunnel122 to the same BR2 coexist (different source/destination pairs): both FULL, primary cost 100 preferred (BR2 `10.10.10.0 via Tunnel22` metric 120; during a circuit loss via Tunnel122 metric 520).
- (d) Provider failover EDGE1-ISP1 (cable pull) while on the backup path: **the IKE and IPsec SAs are kept** (same SPIs, Active Time continuous); 1 ping lost in 3 runs; track 10 Down 5.9-9.0 s after the BGP session drops; HSRP Active again 43-47 s after the restore.

## Measured behaviour (BR2-PC1 to HQ-PC1 ping 1/s unless stated; raw values in the LAB-053 SOLUTION.md)
| Case | Result |
|---|---|
| Cable pull HQ-WAN1 e0/0 + INET1 e0/0 (primary circuit) | 2-10 s of lost pings (9, 3, 2, 10, 9; BR2 learns HQ-WAN1's new LSA over Tunnel122, no wait for the 20 s dead timer); restore: BR2 back on Tunnel22 6-40 s (6, 40, 11, 11, 14), no packet lost |
| Silent failure (link stop) of HQ-WAN1-INET1 | 16-18 lost pings (18, 18, 16): OSPF dead 20 s on Tunnel22; failback 2-35 s, no loss |
| Cable pull EDGE1 e0/0 + ISP1 e0/0 on the backup path | 1 lost ping x 3; SAs kept |
| Cable pull EDGE2 e0/0 + ISP2 e0/0 on the backup path (EDGE1 active) | no ping lost |
| Node stop of HQ-WAN1 | BR2 OSPF dead 16.7-20.2 s, Tunnel line down 23.2-23.8 s (DPD), no HQ path until the node is back (route back about 11-13 s after `node start`) |

Platform notes: IP SLA `udp-jitter` is no UDP generator without a responder; `traceroute <ip> source <lo> numeric probe N timeout 1 ttl 30 30 port P` sends N UDP probes (port increments per probe) and the edge answers `!A`. FNF exports a flow when it ends (15 s inactive; 1800 s active): bounce the tunnel to see the UDP 4500 records; `cflow.inputint` 1 = Ethernet0/0, 3 = Ethernet0/2. `logging buffered ... informational` hides `debug crypto ikev2` output: raise the level to `debugging` temporarily.

## Files
17 node files: `HQ-EDGE1.cfg`, `HQ-EDGE2.cfg`, `PROV-ISP1.cfg`, `PROV-ISP2.cfg`, `PROV-INET1.cfg`, `HQ-CORE1.cfg`, `HQ-WAN1.cfg`, `BR2-RTR1.cfg`, `DC-RTR1.cfg`, `HQ-PC1.cfg`, `HQ-SRV1.cfg`, `BR2-PC1.cfg`, `DC-SYSLOG1.boot.sh`, `DC-AAA1.boot.sh|radiusd.conf|users`, `DC-NMS1.boot.sh` (E3 service files unchanged); the DMZ and DC-SW unmanaged switches have no file.
