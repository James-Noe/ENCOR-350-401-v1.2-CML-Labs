# LAB-049 — Solution

## Summary

First troubleshooting lab of the tunnel family (v1.1). Three independent faults sit behind two tickets: a headend access list that names the wrong BR2 address (key exchange, NTP and ESP never arrive), a per-branch pre-shared key that BR2 was not given (IKE_SA_INIT completes, IKE_AUTH fails authentication) and two totally stubby branch areas whose injected default loses to the branch's static default (the specifics are gone, so branch traffic leaves by the Internet or the provider line). The faults are in series for T1 (F2 gates F1, then F3 keeps T1 open although Tunnel22 is up) and F3 alone causes T2. One cause (F3) gives two symptoms: BR1 falls back to the provider line, BR2 has no backup and sends HQ traffic to the Internet.

Blueprint mapping (instructor only): 2.2.b tunnel verification (T), 5.2.a access control lists (R), 3.2.b OSPF (R). Earlier-module candidates: edge-style ingress ACL (F2), OSPF area types and default injection (F3), branch PAT and NAT order (red herring), NTP (red herring).

## Intentional Faults

| ID | Device | Change | Symptom |
|---|---|---|---|
| F1 | HQ-WAN1, BR1-RTR1 (hardening applied), BR2-RTR1 (not applied) | HQ-WAN1 keyring `KR`: `peer BR1` (address 203.0.113.131, `VERIDIAN-BR1-KEY`) and `peer BR2` (address 203.0.113.133, `VERIDIAN-BR2-KEY`), wildcard removed; BR1 keyring `peer HQ` (203.0.113.129, `VERIDIAN-BR1-KEY`); BR2 keyring still `peer ANY` with `VERIDIAN-VPN-KEY` | with F2 fixed: IKE_SA_INIT completes, IKE_AUTH fails authentication. No IKE SA and no IPsec SA for Tunnel22; BR1 unaffected |
| F2 | HQ-WAN1 | `WAN1-INET-IN` lines 20/40/60/80 (IKE, NAT-T, ESP, NTP) name 203.0.113.132 (INET1's side of BR2's /31) instead of .133 | BR2's IKE and NTP are denied and logged; no IKE exchange at all; pings pass (the ICMP lines name .133) |
| F3 | HQ-WAN1, BR1-RTR1, BR2-RTR1 | `area 21 stub no-summary` and `area 22 stub no-summary` on HQ-WAN1; `area 21 stub` on BR1; `area 22 stub` on BR2 (flags agree, adjacencies form) | each branch area receives only a type-3 default; the O*IA default (AD 110) loses to the static default (AD 1). BR1: HQ traffic uses the provider /16 static (T2; HQ to BR1 stays on Tunnel21, asymmetric); BR1 to BR2 leaves by the Internet default. BR2 (once Tunnel22 is up): HQ and BR1 traffic leaves by the Internet default, PAT'd and dropped at INET1 (`!H`) |

Tickets: T1 = F2, then F1, then F3. T2 = F3 (BR1). Red herrings: BR2's PAT (at boot no UDP 500 translations; after F1, HQ-bound translations are a routing consequence of F3), BR2 NTP unsynchronised (follows F2; PSK authentication does not use time), the provider (INET1 and HQ-WAN1's public address answer pings), BR1's tunnel for T2 (IKE READY, OSPF FULL, no flaps; only the decaps counter grows with user traffic), and the `IKEv2 profile not found` debug line (see Diagnosis step 4).

## Diagnosis / Methodology

**T1 (BR2).**
1. BR2-PC1 to HQ-PC1 100% loss; BR2-PC1 to 203.0.113.128 and 198.51.100.200 (INET1, "the Internet") reply; traceroute 10.22.10.1, 203.0.113.132, then `!H`. LAN, gateway, PAT and the Internet underlay are ruled out as reachability causes.
2. BR2: Tunnel22 DN, `show crypto ikev2 sa` empty, `show crypto session` `DOWN`, no OSPF neighbour, pings to 203.0.113.129 and .132 100%.
3. HQ-WAN1: `show access-lists WAN1-INET-IN`: the deny entry counts; the log shows `%SEC-6-IPACCESSLOGP: list WAN1-INET-IN denied udp 203.0.113.133(500) -> 203.0.113.129(500)` and later `(123)->(123)` (NTP). The IKE/NAT-T/ESP/NTP lines name .132 (**F2**). Fixing F2 alone: the permit counters for .133 rise (line 20 isakmp, line 80 ntp, esp none), NTP will sync, but still no IKE SA on BR2 and on HQ-WAN1 only .131 is READY. Fixing F1 alone (F2 present): no visible change (11 deny matches still rising after 45 s); this proves the series.
4. With F2 fixed the exchange now arrives. `show crypto ikev2 stats` shows no authentication counter moving, and there is no syslog line without debug. `debug crypto ikev2 error` on HQ-WAN1 (set `logging buffered 64000 debugging`; BR2 bounces Tunnel22):
```
IKEv2-ERROR:(SESSION ID = 7,SA ID = 2):% IKEv2 profile not found
IKEv2-ERROR:(SESSION ID = 7,SA ID = 2):: Failed to authenticate the IKE SA
IKEv2-ERROR:(SESSION ID = 7,SA ID = 2):: Auth exchange failed
```
BR2 (initiator) logs `Auth exchange failed`. The `IKEv2 profile not found` line is a red herring: it also appears when the profile is later chosen (BR1 uses the same profile and is READY), and the narrow `internal` debug shows `Choosing IKE profile IKEV2-PROF`, `Using IKEv2 profile 'IKEV2-PROF'`, `EV_GET_PRESHR_KEY`, `Computing AUTH data to authenticate peer`, `Failed to authenticate the IKE SA`, `Construct Notify Payload: AUTHENTICATION_FAILED`. So IKE_SA_INIT completes and IKE_AUTH fails the key check: authentication, not negotiation. (The `internal` debug is very noisy; students should use `error` only and filter `show logging`.) Compare `show running-config | section keyring` on both ends: HQ-WAN1 holds a per-branch key for .133, BR2 still sends the old wildcard key (**F1**).
5. After F1 is fixed (BR2 `peer HQ` with `VERIDIAN-BR2-KEY`, Tunnel22 bounce): IKE READY, session `UA`, OSPF FULL, but BR2's `show ip route ospf` is empty, `show ip route 10.10.10.101` says `% Subnet not in table` (only the default via 203.0.113.132) and BR2-PC1 still fails; NAT shows `icmp 203.0.113.133:1024 10.22.10.101 -> 10.10.10.101` (HQ-bound traffic is PAT'd to the Internet: a consequence). `show ip ospf database` holds one summary (0.0.0.0, not installed: AD 110 against the static default), `show ip ospf` says "stub area" and HQ-WAN1's says "stub area, no summary LSA in this area" (**F3**).

**T2 (BR1).** BR1-PC1 traceroute to HQ-PC1: 10.21.10.1, 100.64.21.0, 100.64.10.1, 10.10.255.96, 10.10.10.101 (provider path), while HQ-PC1 to BR1-PC1 goes 10.10.10.1, 10.10.255.97, 10.250.21.21 (tunnel): asymmetric. BR1: IKE READY, OSPF FULL, no flap. `show ip route 10.10.10.101` is static 10.10.0.0/16 via 100.64.21.0 (AD 1); `show ip route ospf` shows only the gateway of last resort 203.0.113.130 (no O IA, no O*IA); area 21's LSDB has one summary, 0.0.0.0 from 10.255.10.41. Tunnel21 decaps rose +21 per 20-ping run in each direction while encaps stayed at the OSPF rate (33 -> 35): the return path uses the tunnel, the outbound path does not. HQ-WAN1: `area 21 stub no-summary` (**F3**).

**Wrong-fix traps, each tried once:**
- A (F1 present, F2 fixed): re-add the wildcard `peer ANY` (`VERIDIAN-VPN-KEY`) on HQ-WAN1 and keep `peer BR2`: Tunnel22 still fails (the more specific address entry wins). Delete `peer BR2` as well: Tunnel22 READY and OSPF FULL within the call, but one key is now shared by both branches (V4 fails).
- B (BR1 `ip route 0.0.0.0 0.0.0.0 203.0.113.130 250`, F1/F2 fixed): the OSPF default `O*IA` wins, the tunnel destination resolves into the tunnel: `%ADJ-5-PARENT ... looped chain`, `%TUN-5-RECURDOWN: Tunnel21 temporarily disabled due to recursive routing`, a fixed 70 s cycle (60.0 s down, 10.0 s up). BR1's Internet breakout is disturbed only in the 10 s up window (the default is then OSPF via Tunnel21; Internet ping 2/3), and in the 60 s down window the provider /16 and the static default carry traffic. Fails V3 (flap) and V5 (tunnel destination resolved via the tunnel, default via the overlay).
- C (BR1 `ip route 10.10.10.0 255.255.255.0 10.250.21.1`): BR1-PC1 traceroute to HQ-PC1 now uses 10.250.21.1 (hides F3 for that prefix only); V2 unchanged (18-20 lost pings with or without it); fails V5 (the route is not learned from OSPF); BR1 to BR2 unchanged.
- D (`1 permit ip any any` on HQ-WAN1): Tunnel22 UA and OSPF FULL within 7 s, but PROV-INET1 pings 203.0.113.129 3/3 (V4 fails). After re-breaking F2, HQ-WAN1 keeps a stale IKE SA for .133 until DPD, so `show crypto ikev2 sa` still lists it for a while.
- Time sinks (no V item): changing BR2's proposal or transform set, or adding NAT exemption on BR2 (the routed tunnel needs none).

## Solution Configuration

Order: F2 first, then F1, F3 any time (fixing F3 alone clears T2). As tested.

HQ-WAN1:
```
ip access-list extended WAN1-INET-IN
 no 20
 no 40
 no 60
 no 80
 20 permit udp host 203.0.113.133 host 203.0.113.129 eq isakmp
 40 permit udp host 203.0.113.133 host 203.0.113.129 eq non500-isakmp
 60 permit esp host 203.0.113.133 host 203.0.113.129
 80 permit udp host 203.0.113.133 host 203.0.113.129 eq ntp
router ospf 1
 no area 21 stub no-summary
 no area 22 stub no-summary
```
BR2-RTR1:
```
crypto ikev2 keyring KR
 no peer ANY
 peer HQ
  address 203.0.113.129
  pre-shared-key VERIDIAN-BR2-KEY
interface Tunnel22
 shutdown
 no shutdown
```
Accepted alternatives. F3 (b): remove `stub` on both ends of each area (HQ-WAN1 and the branch); the adjacency drops until both ends agree. F1: change BR2's wildcard key to `VERIDIAN-BR2-KEY` instead of adding `peer HQ`.

## Verification

Captured in CML (CML 2.10.0, iol-xe 17.16.1a).

**Start state (boot):** HQ-WAN1: `show crypto ikev2 sa` only 203.0.113.131 READY; session `Tu21 UA`, `Tu22 DN`; OSPF FULL with the core and Tunnel21 only; areas 21 and 22 "It is a stub area, no summary LSA in this area"; `220 deny ip any any log (9 matches)` rising, lines 20/40/60/80 name .132. BR1: IKE READY, OSPF FULL, `Gateway of last resort 203.0.113.130`, static /16 via 100.64.21.0, only 0.0.0.0 in the summary LSDB, NTP unsynchronised for the first ~20 minutes. BR2: no IKE SA, `Tu22 DN`, no OSPF neighbour, default via 203.0.113.132, NTP unsynchronised, no UDP 500 in the NAT table, pings to .129 and .132 3/3. Hosts: HQ-PC1 to BR1-PC1 via 10.250.21.21, BR1-PC1 to HQ-PC1 via 100.64.21.0, BR2-PC1 to HQ-PC1 100% loss with `!H` at 203.0.113.132.

**Isolated fixes (causality):** F2 only: ACL permit counters rise for .133, `show crypto ikev2 sa` empty on BR2, HQ-WAN1 only .131; `debug crypto ikev2 error` shows the authentication lines of step 4. F1 only (F2 present): no change. F2+F1 (F3 present): Tunnel22 UA 7 s after the keyring change, HQ-WAN1 IKE SA .133 READY, OSPF FULL on Tunnel22, BR2-PC1 still 100% loss. F3 area 21 only (start state otherwise): `UNTIL met after 1 s`, BR1 learns `O IA` routes, traceroute 10.21.10.1, 10.250.21.1, 10.10.255.96, 10.10.10.101: T2 cleared, T1 unchanged. F3 area 22 as well: BR2-PC1 to HQ-PC1 3/3 via 10.250.22.1, T1 cleared.

**End state (solution applied; within 22 s):** HQ-WAN1 IKE SA .131 and .133 READY, Tu21 and Tu22 UA, OSPF FULL on both tunnels, areas still "stub area". V1: BR1-PC1 to HQ-PC1 via 10.21.10.1, 10.250.21.1, 10.10.255.96, 10.10.10.101; to BR2-PC1 via 10.250.21.1, 10.250.22.22; BR2-PC1 to HQ-PC1 via 10.250.22.1, 10.10.255.96; to BR1-PC1 via 10.250.22.1, 10.250.21.21; HQ-PC1 to both branch hosts 3/3 (note: the first ping to each branch host can be lost to ARP warm-up after the tunnel comes up; use `ping -c 4` or repeat, 2/3 on the first run is normal). BR1 and BR2 `show ip route 10.10.10.101`: `ospf 1, distance 110, type inter area` via the tunnel; each branch has 10 O IA routes and the default stays the static one (203.0.113.130 and .132). V4: keyrings HQ-WAN1 `peer BR1` (VERIDIAN-BR1-KEY) and `peer BR2` (VERIDIAN-BR2-KEY), BR1 `peer HQ` (BR1 key), BR2 `peer HQ` (BR2 key): one key per branch; PROV-INET1 ping 203.0.113.129 `U.U` 0/3. V3: solution applied at 15:34:52, checked 15:39:57 (5 min 5 s): only the intended Tunnel22 shutdown/no shutdown, no further ADJCHG/UPDOWN/TUN lines, Tunnel21 and Tunnel22 FULL (one `IKEv2-ERROR ... Maximum number of retransmissions reached` on BR2, a stale pre-fix SA while the error debug was still on, no effect on the tunnel). V6: about 28 minutes after boot BR1 and BR2 `*~203.0.113.129` (sys.peer, stratum 3); HQ-WAN1 `*~127.127.1.1`. BR2-PC1 to 198.51.100.200 3/3.

**Fix (b) for F3 (area 21, one end at a time):** HQ-WAN1 `no area 21 stub` first: Tunnel21 neighbour DOWN after 1 s (stub flag mismatch on the Hello); BR1 second: neighbour FULL after 6 s. BR1 then has O IA specifics, `O E2 10.21.0.0/16` from the PROV-ROUTES redistribution and no default from OSPF. Restoring stub on both ends: FULL after 7 s (single runs).

## Failure / Recovery Behaviour

Method: cable pull = `shutdown` on both ends (BR1 e0/0 + PROV-INET1 e0/1; BR2 e0/0 + PROV-INET1 e0/2), pings 1/s from the branch host to HQ-PC1, timings from a scripted CLI poll (3 s poll unless noted; each run ends at the end condition, with a clean baseline before).

| Scenario (trigger, end condition) | Runs (raw) | Documented range | Basis |
|---|---|---|---|
| BR1 cable pull to first BR1-PC1 reply from HQ-PC1 (provider /16) | 20 / 24 / 20 s; lost pings 18 / 20 / 18 | 17-25 s | tunnel falls at about 15 s by recursion (`%ADJ-5-PARENT looped chain`, then Tunnel21 down; the static default is withdrawn and the `O*IA` default resolves the tunnel destination into the tunnel), then the static /16 takes over (not the OSPF dead timer; HQ-WAN1 sees `Dead timer expired`) |
| BR1 restore (`no shutdown` both ends) to Tunnel21 FULL | 19 / 12 / 19 s; no extra loss on failback | 12-20 s | link up, IKE, OSPF hello 5 s |
| BR2 cable pull to HQ-WAN1's Tunnel22 neighbour gone (`--until-gone`, 2 s poll) | 18 / 18 / 21 s | 15-25 s | HQ-WAN1 side: dead timer 20 s (derived); BR2 side drops Tunnel22 by the same recursion at about 15 s |
| BR2 restore to first BR2-PC1 reply | 24 / 31 / 32 s; pings lost over the whole outage 54 / 62 / 62 | 20-40 s | link up, IKE after the peers' stale SA, OSPF adjacency |
| F3 fix (a) on HQ-WAN1 to first `O IA` on the branch | area 21: 1 / 1 / 1 s; area 22: 1 / 1 / 1 s (adjacencies never reset) | under 5 s | SPF delay; poll resolution about 1 s |
| F1 fix (BR2 keyring + Tunnel22 bounce) to Tunnel22 UA, OSPF FULL | 7 s (first run); about 22 s from the solution script's start | 5-25 s | bounce, IKE exchange, hello |
| Trap B recursion cycle on BR1 Tunnel21 | 60 s down, 10 s up, 70 s cycle (RECURDOWN 19:25:00 to 19:26:10 to 19:27:20) | 70 s | RECURDOWN hold-down 60 s plus 10 s up |

V2 limit note: the times exclude about 8 s for the CLI to connect; the longest BR2 restore (32 s) is inside 45 s, so V2's limit stays 45 s. BR1 has the provider /16 as backup; BR2 has no alternate path, so its Internet breakout is lost during the pull too (same cable). The IKE SA on the peer can be stale after a pull, which explains the 24-32 s BR2 recovery.

## Answers to Analysis Questions

**Q1** T1: BR2-PC1 reaches 198.51.100.200 but not HQ-PC1, Tunnel22 is down, `show crypto ikev2 sa` empty and pings to 203.0.113.129 succeed: the underlay works, the tunnel control plane does not. After the tunnel is up the traceroute ends with `!H` at INET1's side: the routing layer. T2: BR1-PC1's traceroute shows 100.64.x hops instead of 10.250.21.x although the tunnel is up and OSPF is FULL: route selection, not the tunnel.

**Q2** Packets not accepted (F2): ACL deny counters and log lines for .133 UDP 500, nothing on the responder's IKE side. Key exchange runs but authentication fails (F1): permit counters rise, `show crypto ikev2 sa` stays empty, `debug crypto ikev2 error` on the responder shows `Failed to authenticate the IKE SA` and `Auth exchange failed` (the `IKEv2 profile not found` line is misleading); IKE_SA_INIT completed, IKE_AUTH failed. Tunnel and adjacency up but no routes (F3): IKE READY, session UA, OSPF FULL, but `show ip route` has no prefix and the LSDB has one summary. The underlay (pings, BR1's working tunnel) was ruled out first.

**Q3** After each fix re-test the user path, the log and the counters. F2: the deny counter stops, permits rise, the symptom persists, the evidence changes (authentication). F1 alone (F2 present) changed nothing: they are in series. F1+F2: Tunnel22 up, OSPF FULL, T1 still open: the next layer (F3). F3 on area 21 clears T2 only; T1 needs area 22 too.

**Q4** Re-test T1 and T2 together after the last fix, repeat after a tunnel bounce and after a cable pull, and read the log over several minutes. One cause (F3) explains both tickets: BR1 falls back to the provider, BR2 has no backup and leaves by the Internet. Trap-style workarounds (static default with AD 250, static HQ routes, `permit ip any any`) fail V3, V5 or V4.

**Q5** After any WAN change: `show crypto session` and IKE SA state on every tunnel, OSPF neighbours, a soak with log review (flaps, RECURDOWN), the route to every tunnel destination (underlay, never the overlay), the routing source of each branch's HQ routes (OSPF, not static), traceroute from each LAN to HQ and the other branch (overlay hop, not provider), headend list counters (deny must not grow; probes from the outside observer), the per-branch keys, a cable-pull test of each branch with the measured switch-over time, time sync last. Each catches a class that another hides: a working provider backup masks a broken tunnel routing choice, ping passes through an ACL that blocks IKE.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-16 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), iol-xe (IOS XE 17.16.1a), ioll2-xe (IOS XE 17.16.1a) |
