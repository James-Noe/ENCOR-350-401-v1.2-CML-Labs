# LAB-047 — Solution

## Summary

Second lab of the tunnel family (blueprint 2.2.b, 3.3.b reinforced). On LAB-046's bench the student builds an IKEv1 crypto map, meets the PAT/crypto-map interaction (NAT is applied before the crypto match on egress), sees why OSPF cannot run over a crypto map, replaces it with an IKEv2-negotiated IPsec-protected tunnel interface, and compares mismatch behaviour in IKEv1 and IKEv2 and failure detection (OSPF dead timer versus IKEv2 DPD).

**Platform note (not a student fault):** on iol-xe 17.16.1a the pure IPsec VTI (`tunnel mode ipsec ipv4`) comes up (IKEv2 SA READY, Tunnel0 up, OSPF FULL, router-originated pings pass) but drops all transit traffic: CEF counts "Unsupported" drops and Tunnel0 output drops rise; PC1 to PC2 is 0%. It works only router-originated or with `no ip cef` on the router. The lab therefore builds the routed tunnel as GRE with `tunnel protection ipsec profile` (`tunnel mode gre ip`), which uses the same IKEv2 and IPsec profile objects, carries multicast, and forwards transit traffic. The pure IPsec mode is taught as a concept (smaller overhead, no GRE header, IP-only) and shown as an observation in R4. Students are told the limit in LAB.md.

Build notes (proven in CML): (1) R4 uses GRE over IPsec as above; (2) R3 shows OSPF over the crypto map with broadcast hellos only: no adjacency. The NBMA/unicast variant (`ip ospf network non-broadcast`, `neighbor`, ACE for OSPF between the peers) gave no neighbour in testing and is inconclusive, so it is not claimed; (3) R5 is shown on both IKEv1 and IKEv2; (4) failure test shows OSPF dead first, DPD line-down later.

## Intentional Faults

None. R1's NAT/crypto interaction, R3's missing adjacency and R5's mismatch are guided demonstrations, not faults.

## Diagnosis / Methodology

- **R1 (PAT before crypto).** The IKEv1 crypto map is correct on both ends but PC1 to PC2 is lost 5/5. `show ip nat translations` shows `icmp 10.0.12.0:1025 10.0.1.101:2 10.0.3.101:2 10.0.3.101:1025`: PAT rewrote the source to 10.0.12.0 first (NAT is applied before the crypto match on egress), so the crypto ACL (10.0.1.0/24 to 10.0.3.0/24) never matches. `show crypto isakmp sa` is empty, `show crypto session` is `DOWN`, `#pkts encaps: 0`. Fix: NAT exemption through an extended ACL that denies 10.0.1.0/24 to 10.0.3.0/24 ahead of the permit. The old standard ACL 10 cannot match a destination. Migration gotcha: `no ip nat inside source list 10 ...` is refused (`%Dynamic mapping in use, cannot remove`) while translations exist, and a second `ip nat inside source` statement coexists with the old one and the old list still wins. Working order: `clear ip nat translation *` (no confirm prompt), remove the old statement, add the new one.
- **R2.** Phase 1 `QM_IDLE ACTIVE`, phase 2 encaps/decaps counters, ESP in the capture.
- **R3.** With `ip ospf 1 area 0` on e0/0 and e0/1 of R1 and R3 and the crypto map active, no neighbour forms: R2 does not run OSPF, and the hellos to 224.0.0.5 are never sent into the crypto ACL's match (the ACL permits only the LAN pair), so `#pkts encaps` stays at 4 after three hello intervals. A crypto map is not an interface; routing protocols have no interface to run on, no multicast and no neighbour addressing. Unicast/NBMA variant: inconclusive (not claimed).
- **R4.** Routed tunnel: traffic is routed into Tunnel0 and the packet leaves the router with source 10.0.12.0 from the tunnel, not through the NAT outside interface, so no exemption is needed: proven by deleting the `deny` ACE with the tunnel up, PC1 to PC2 still works with no translation entry, while PC1 to Lo100 is still PAT'd. A VTI-style tunnel's line protocol stays down until IKE has succeeded: with a wrong PSK the result is `Tunnel0 is up, line protocol is down`.
- **R4 pure IPsec observation.** `tunnel mode ipsec ipv4` (after `shutdown`/`no shutdown`): IKEv2 SA READY, `show crypto session brief` Tu0 UA, OSPF FULL, `ping 10.0.3.1` from R1 passes; PC1 to PC2 0%, ESP capture shows only OSPF hellos, Tunnel0 `Total output drops` rises and `show cef drop` Unsupported rises (89, 98, 135 in three reads). Not NAT, MSS or MTU (all removed in the test). With `no ip cef` on R3, PC2 to R1 works (2/3), i.e. process switching forwards it.
- **R5.** IKEv1: phase 1 stays up, no phase 2. IKEv2: the child SA is created inside IKE_AUTH, so `NO_PROPOSAL_CHOSEN` deletes the whole IKE SA (see Verification).

## Solution Configuration

R1 IKEv1 crypto map (R3 mirrors: key address 10.0.12.0, ACL source/destination swapped, `set peer 10.0.12.0`, route `ip route 10.0.1.0 255.255.255.0 10.0.23.1`):

```
crypto isakmp policy 10
 encryption aes 256
 hash sha256
 authentication pre-share
 group 14
crypto isakmp key VERIDIAN-VPN-KEY address 10.0.23.0
ip access-list extended VPN-TRAFFIC
 permit ip 10.0.1.0 0.0.0.255 10.0.3.0 0.0.0.255
crypto ipsec transform-set TS-AES esp-aes 256 esp-sha256-hmac
 mode tunnel
crypto map CMAP 10 ipsec-isakmp
 set peer 10.0.23.0
 set transform-set TS-AES
 match address VPN-TRAFFIC
interface Ethernet0/0
 crypto map CMAP
ip route 10.0.3.0 255.255.255.0 10.0.12.1
```

R1 NAT exemption (tested order):

```
clear ip nat translation *
ip access-list extended NAT-PAT
 deny ip 10.0.1.0 0.0.0.255 10.0.3.0 0.0.0.255
 permit ip 10.0.1.0 0.0.0.255 any
ip nat inside source list NAT-PAT interface Ethernet0/0 overload
no ip nat inside source list 10 interface Ethernet0/0 overload
```

R4 on both routers (N = 1 on R1 / 3 on R3; DEST = peer's Ethernet0/0 address; RID = Loopback0 address). First remove the crypto map stage (`no crypto map CMAP`, `interface Ethernet0/0` / `no crypto map CMAP`, `no ip access-list extended VPN-TRAFFIC`, the remote-LAN static, `no crypto isakmp key VERIDIAN-VPN-KEY address <peer>`). The keyring key is `VERIDIAN-VPN-KEY`.

```
crypto ikev2 proposal PROP
 encryption aes-cbc-256
 integrity sha256
 group 14
crypto ikev2 policy POL
 proposal PROP
crypto ikev2 keyring KR
 peer ANY
  address 0.0.0.0 0.0.0.0
  pre-shared-key VERIDIAN-VPN-KEY
crypto ikev2 profile IKEV2-PROF
 match identity remote address 0.0.0.0
 authentication remote pre-share
 authentication local pre-share
 keyring local KR
 dpd 10 2 on-demand
crypto ipsec profile VPN-PROF
 set transform-set TS-AES
 set ikev2-profile IKEV2-PROF
interface Tunnel0
 ip address 10.0.250.N 255.255.255.0
 ip mtu 1400
 ip tcp adjust-mss 1360
 tunnel source Ethernet0/0
 tunnel mode gre ip
 tunnel destination DEST
 tunnel protection ipsec profile VPN-PROF
 ip ospf network point-to-point
 ip ospf hello-interval 5
 ip ospf dead-interval 20
 ip ospf cost 100
 ip ospf 1 area 0
interface Ethernet0/1
 ip ospf 1 area 0
router ospf 1
 router-id RID
```

(Never put OSPF on Ethernet0/0: it would advertise the underlay and cause LAB-046's recursion.) Pure IPsec observation: `interface Tunnel0` / `tunnel mode ipsec ipv4`, then `shutdown` / `no shutdown` (the mode-change warning demands it); revert with `tunnel mode gre ip` and the same bounce.

R5: `crypto ipsec transform-set TS-AES esp-aes 128 esp-sha256-hmac` on R3, `clear crypto session` on both, then restore `esp-aes 256`. Do not use `clear logging` or `clear ip ospf process` (confirm prompts hang the CLI tool).

## Verification

Captured in CML (trimmed).

R1 symptom (PAT before crypto): `icmp 10.0.12.0:1025 10.0.1.101:2 10.0.3.101:2 10.0.3.101:1025`; ISAKMP SA table empty; `Session status: DOWN ... Active SAs: 0`; `#pkts encaps: 0`; PC1 to PC2 5/5 lost. After the fix: PC1 to PC2 5 sent / 4 received (first lost during IKE), PC1 to Lo100 3/3 (`icmp 10.0.12.0:1024 10.0.1.101:8 10.0.100.1:8`); on R1 and R3 `10.0.23.0 10.0.12.0 QM_IDLE 1001 ACTIVE`; encaps/decaps 4/4 on both.

R2 capture (R1-R2 link, after `clear crypto session` on both, PC1 ping x6 to PC2, 43 packets, ping 5/6):
```
1-6  10.0.12.0 <> 10.0.23.0 UDP 500>500 IKEv1 exch=2 (main mode, 6 messages: len 196,136,464,484,136,120)
7-9  UDP 500>500 IKEv1 exch=32 (quick mode, 3 messages: 216,216,104)
10.. 10.0.12.0 > 10.0.23.0 proto=50 ESP spi=0x6f90384f len=156 ; reverse spi=0xd091e2ca len=156 (inner ICMP 84 bytes -> 156 on the wire)
```

R3 (OSPF over crypto map): `show ip ospf neighbor` empty on both; `#pkts encaps` unchanged (4) after three hello intervals. NBMA attempt: no neighbour, only 3 NBMA polls in 10 minutes (inconclusive, not claimed).

R4 (GRE over IPsec tunnel, IKEv2): IKEv2 SA `Encr: AES-CBC, keysize: 256, PRF: SHA256, Hash: SHA256, DH Grp:14, Auth sign: PSK`, READY; Tu0 up; OSPF FULL on Tunnel0 (cost 100, point-to-point, hello 5 / dead 20); PC1 to PC2 3/3 with no translation entry, PC1 to Lo100 still PAT'd. `Tunnel transport MTU 1414 bytes` (pure IPsec mode: 1438; plain GRE in LAB-046: 1476); `plaintext mtu 1438, path mtu 1500`. DF ping from R1 (source Ethernet0/1) size 1400 to PC2 3/3, 1401 0/2.
Capture (after `clear crypto session`, PC1 ping x4, 4/4): `UDP 500>500 IKEv2 exch=34` (IKE_SA_INIT, 2 messages, 546/546), `exch=35` (IKE_AUTH, 2 messages, 620/300; child SA created inside IKE_AUTH), `exch=37` informational (deletes from the clear), then only `proto=50 ESP` (spi 0x4bacc142 / 0x2c865ce3); PC1 ICMP echo (IP length 84) appears as ESP IP length 172 (frame 186; GRE-in-ESP, as the Q5 formula gives for 84 bytes), and R1 `ping size 100` as ESP IP length 188 (frame 202), measured; OSPF hellos 156-172. Once the SAs were up, no GRE (47) or plaintext ICMP was visible.

Observed caveat (F-1): in one run, with the capture started right after `clear crypto session` on both routers, one plaintext ICMP packet (10.0.1.101 > 10.0.3.101) crossed the R1-R2 link between the IKE_SA_INIT messages, and 3 of 4 pings were answered. It was seen once and its mechanism was not proven; a plausible reading is that while Tunnel0 is down the OSPF route is lost and the static default (with the NAT-PAT deny ACE still present) sends the traffic out unprotected. The lesson: when the protected tunnel is down, a less specific route (here the static default) can carry the traffic unencrypted. Designs that must never send it in the clear add a fail-closed route (for example a Null0 route for the remote LANs with an AD above the overlay's) and validate protection with a capture taken after negotiation. Mechanism not proven on this bench; avoid clearing sessions under load in production.

Cosmetic (F-3): `show crypto session` for this tunnel prints `origin: crypto map` even though no crypto map is configured; on IOS-XE the label is cosmetic for tunnel protection. Use the `Tunnel0` interface name and the IPsec profile to confirm the protection.

R4 pure IPsec observation: see Diagnosis. SAs up, `ping 10.0.3.1` from R1 passes, PC1 to PC2 and PC2 to R1 0%, `show cef drop` Unsupported 89 -> 98 -> 135.

R5 IKEv1: PC1 to PC2 0/3; both ends `10.0.23.0 10.0.12.0 QM_IDLE 1001 ACTIVE` (phase 1 up); `Session status: UP-IDLE ... Active SAs: 0`; `#pkts encaps` 0, `current outbound spi: 0x0(0)`; no %-level syslog message.
R5 IKEv2: `show crypto ikev2 sa` empty on both ends, session DOWN with 0 SAs, `Tunnel0 is up, line protocol is down`, OSPF down. With `debug crypto ikev2 error` and `internal` on R1: in IKE_AUTH `Parse Notify Payload: NO_PROPOSAL_CHOSEN`, `IKEv2-ERROR`.

Final state: Tunnel0 on R1 and R3 as above; PAT retained through NAT-PAT; no crypto map. (The `deny` ACE is optional and harmless once the tunnel carries the traffic; deleting it was the proof for Q4.)

## Failure / Recovery Behaviour

Method: silent failure (CML link stop of R3-Ethernet0/0 to R2-Ethernet0/1) with IKEv2 DPD `10 2 on-demand`, OSPF hello 5 / dead 20. Interfaces stay up/up. One clock: R1 `send log 1 MARKSTOP` just before the REST `link stop` (effective about 1.2 s later; the values include that second); events from R1 `show logging`. (The a scripted CLI poll seconds exclude about 8 s of connect time and were not used.)

| Scenario (trigger, end condition) | Runs (s) | Documented range | Basis |
|---|---|---|---|
| Link stop: to R1 `Dead timer expired` (OSPF neighbour lost) | 17.7 / 17.8 / 17.5 | 15-20 s | measured; dead 20 s, last hello up to 5 s before the stop |
| Link stop: to Tunnel0 line protocol down (DPD tears the session) | 24.6 / 24.6 / 20.1 | 18-30 s | measured; DPD: 10 s without inbound traffic, then retries every 2 s until the peer is declared dead (derived) |
| Link start: to Tunnel0 up and OSPF FULL | 13.8 / 3.4 / 10.4 | 2-15 s | measured; new IKEv2 negotiation after the link returns |

OSPF always detected first; DPD removed the SA 3-7 s later.

## Answers to Analysis Questions

1. **Q1:** A crypto map encrypts only traffic matching its ACL, on the physical interface, one ACL entry pair per site pair; there is no interface, so no routing protocol or multicast and no per-tunnel statistics. A protected tunnel interface encrypts whatever is routed into it, carries multicast and OSPF, supports a routing-based design that scales with a routing protocol, and needs no per-site ACLs. (Pure IPsec VTIs share this but carry IP only; GRE adds multi-protocol support at 24 bytes of overhead; on this platform the pure form does not forward transit traffic.)
2. **Q2:** Phase 1 (IKE SA) authenticates the peers and protects the IKE negotiation (`show crypto isakmp sa` QM_IDLE for IKEv1, `show crypto ikev2 sa` READY). Phase 2 (IPsec/child SA) protects the user traffic with ESP (`show crypto ipsec sa`: encaps/decaps, SPIs).
3. **Q3:** IKEv1: main mode, 6 messages (exch 2), then quick mode, 3 messages (exch 32) to negotiate the IPsec SA: 9 messages. IKEv2: IKE_SA_INIT (exch 34, 2 messages) and IKE_AUTH (exch 35, 2 messages) with the first child SA inside IKE_AUTH: 4 messages.
4. **Q4:** Crypto map: the packet is translated by the NAT outside interface (R1 Ethernet0/0) before the crypto ACL is evaluated, so the source is 10.0.12.0 and the ACL (10.0.1.0/24 to 10.0.3.0/24) does not match; a NAT ACL `deny` for the VPN traffic is needed. Tunnel: routing sends the LAN traffic out of Tunnel0, which is not a NAT outside interface, so no translation occurs. Proof: deleting the `deny` ACE did not change PC1 to PC2.
5. **Q5:** Crypto map ESP: a 84-byte ICMP packet becomes 156 bytes on the wire (72 added: outer IP 20 + ESP header 8 + IV 16 + 10 bytes padding + 2-byte pad-length/next-header trailer + 16-byte ICV; `esp-sha256-hmac` is HMAC-SHA-256-128, RFC 4868, so the ICV is 16 bytes). GRE-in-ESP adds, on top of the same ESP fields, the GRE encapsulation inside the tunnel-mode payload: outer IP 20 + ESP 8 + IV 16 + inner GRE packet (IP 20 + GRE 4 + original packet) + padding to a 16-byte multiple + 2 + ICV 16; for an 84-byte packet that is 172 bytes (88 added). Measured (R1-R2 link): the default PC1 ping (84-byte IP) gives ESP IP length 172 (frame 186), and R1 `ping size 100` (100-byte IP) gives 188 (frame 202); both match the formula. Tunnel transport MTU here is 1414 (versus 1476 for plain GRE); `ip mtu 1400` and MSS 1360 remain correct: DF 1400 passes, 1401 does not, and the MSS is 1400 - 40.
6. **Q6:** The crypto-map SA is created on demand: when it has idled out (or been cleared) the first packet triggers IKE and is lost (or queued only briefly) while negotiation happens; the capture shows the 9 IKEv1 messages before ESP. In the routed tunnel the IKE/IPsec session is set up at tunnel bring-up and kept up by OSPF hellos (DPD is on-demand), so traffic does not trigger it; the first ping after a `clear crypto session` is still lost (the lab observed 1 lost of 4-6), as the session is re-established.
7. **Q7:** OSPF hellos go to multicast 224.0.0.5 and are not matched by the crypto ACL; a crypto map is not an interface, so OSPF has no interface for the neighbour address. A tunnel interface provides an interface that routing protocols can run on, point-to-point, with multicast carried (GRE) and the IPsec profile protecting it all. (Unicast hello over NBMA was not demonstrated.)
8. **Q8:** IKEv1: phase 1 completes first and stays up (`QM_IDLE`), phase 2 (quick mode) fails with no matching proposal; only `Active SAs: 0` and the lack of encaps show it, with no syslog. IKEv2: the child SA is negotiated inside IKE_AUTH, so a proposal mismatch is `NO_PROPOSAL_CHOSEN` in IKE_AUTH and the whole IKE SA is deleted; visible only with the IKEv2 debug.
9. **Q9:** OSPF's dead timer (20 s) fires first (15-20 s measured). DPD (on-demand, `10 2`) detects the dead peer only when traffic needs it, and removes the IKE and IPsec SAs and brings the tunnel line down (18-30 s). DPD matters for crypto maps and tunnels without a routing protocol or keepalive.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-17 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), iol-xe (IOS XE 17.16.1a) |
