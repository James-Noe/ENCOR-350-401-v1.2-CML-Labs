# MS-5 — Solution

## Summary

The final challenge runs the whole Veridian network at once (19 nodes with the NAT connector): HQ single-core H5 lite, the E3 edge, the W3 lite WAN (hub, provider, depot), the DC block with its services, DC-FUS1 and Aster's border, and AUTO-MGMT1. Three tickets (eight faults) and four change requests that interact with them, plus a scripted compliance report. Blueprint mapping (instructor only): IPv6 first-hop security and 3.1.a, 3.1.c (TK1), 3.2.b, 3.2.c, 1.3.b, 2.2.a, 5.4.d (TK2, CR1), 5.1.b, 6.6, 4.1 (TK3), 4.4, 3.3.b, 5.2.a (CR2), 5.2.b (CR3), 1.4, 2.2.b (CR4), 6.1 (compliance script).

Design decisions (all in favour of teaching ENCOR):
- **F7 is an RA-guard host policy, not an IPv6 ACL.** ioll2-xe rejects `ipv6 traffic-filter` on trunk and access ports (`% Invalid input`). It accepts and enforces `ipv6 nd raguard policy HOST-RA-BLOCK` (`device-role host`) with `ipv6 nd raguard attach-policy` on L2 ports, which is IPv6 first-hop security and in the blueprint's reach. F7 is that policy on all five HQ-ACC1 ports including the uplinks e0/0 and e0/1. **There are no drop counters** (`show ipv6 nd raguard policy` lists the targets only), so TK1's evidence path is the host capture, the policy's target list and the port configuration, not an ACL deny count. LAB.md says "RA guard policy HOST-RA-BLOCK".
- **The destination group comes from the ingress VRF's mapping (F8).** DC-FUS1 looks up the source and the destination group in the VRF the packet arrives in. Measured: removing the SHARED copy of 10.50.51.0/24 leaves office 10 to 50 permitted; removing the CORP and IOT copies (SHARED kept) makes the ping pass with no cell counted (destination unknown). So the CORP and IOT copies matter, SHARED's is idle; all three are kept in the start state.
- **Causality of F7-only and F8-only is derived, not run.** F1-only-fixed was run (IPv4 back, no IPv6 default). F7-only-fixed with F1 present was not re-run: root guard still blocks VLAN 10 (derived; the start state shows 100 % IPv4 loss). F8-only-fixed was not run: before F3 and F4 VRF IOT has no route to 10.50.51.1 (derived); F3 and F4 were each shown alone, and F8 with F3 and F4 fixed.
- **F3 is the absence of `no passive-interface Ethernet0/2`** under OSPF 1 (the E3 DC-RTR1 already runs `passive-interface default`); same effect as an added `passive-interface` line and a more natural production mistake.
- **`capability vrf-lite` on `router ospf 50 vrf SHARED` (FUS1) belongs in DC-FUS1's start configuration.** The student is not expected to know this knob: CR1 is about the restricted route-target leak, not about OSPF-in-VRF PE behaviour. The line is in DC-FUS1's start config in `MS-5.yaml` (` capability vrf-lite` under `router ospf 50 vrf SHARED`); the line survives day-0 (confirmed at every boot of the v1.5 build: `capability vrf-lite` in `show running-config` on the cold-booted lab). It was first validated as a manual CR1 step. MS-5's start config therefore deliberately differs from the FAB F-H/F3 stage file `environments/FAB/.../DC-FUS1.cfg` by this one line (the stage file is unchanged). Background (why the line is needed, measured on the original build): With F3 fixed, the VRF OSPF process still ignores Veridian's inter-area prefixes: `show ip ospf 50 database summary 10.10.10.0` still lists the LSA (`Options: (No TOS-capability, DC, Upward)`; `Upward` means the DN bit is clear), but the process does not use it: an OSPF process in a VRF acts as a PE, i.e. as an ABR attached to the MPLS VPN superbackbone, and an ABR does not use type-3 summary LSAs learned in a non-backbone area (FUS1 has only area 50). Intra-area 10.50.51.0/24 is installed, the inter-area Veridian prefixes are not. `capability vrf-lite` turns these PE checks off. LAB.md gives no hint and, with the line in the start config, needs none; the `show ip ospf 50` header lines ("Connected to MPLS VPN Superbackbone", area border router) are the trail. Measured on DC-FUS1 (only F3 fixed):

```
Before capability vrf-lite:
show ip ospf 50 | include Connected|border|Domain
   Domain ID type 0x0005, value 0.0.0.50
 Connected to MPLS VPN Superbackbone, VRF SHARED
 It is an area border and autonomous system boundary router
show ip ospf 50 database summary 10.10.10.0   -> Options: (No TOS-capability, DC, Upward), Advertising Router 10.255.10.1, Metric 11
show ip route vrf SHARED 10.10.10.0           -> % Subnet not in table
show ip route vrf SHARED ospf                 -> only O 10.10.255.130/31, 10.50.51.0/24, 10.50.52.0/24, 10.255.50.1/32 (no IA)

After capability vrf-lite:
show ip ospf 50 | include Connected|border|Domain   -> no lines
show ip ospf 50 database summary 10.10.10.0   -> Options: (No TOS-capability, DC, Upward) (same LSA)
show ip route vrf SHARED ospf                 -> O IA 10.10.10.0/24 [110/31] and 21 more O IA routes, O*E2 0.0.0.0/0
```
- **CR1's outbound ACL must also admit FUS1's own BGP to the CORP neighbour.** On iol-xe an ACL applied `out` on the handoff sub-interface drops FUS1's router-originated BGP keepalives (the IOS rule "outbound ACLs do not filter local traffic" does not hold here): without ACEs 5/6 the CORP session died 3 minutes after the ACL (hold time expired, Aster CORP routes withdrawn). Found while rebuilding the solution on the final lab.
- **FAB-BDR1 listens for SSH** (the F-H file has no RSA key, so TCP 22 was refused): the day-0 adds `crypto key generate rsa modulus 2048`, so V4's SSH test is a real session. Aster's border is otherwise the F-H file, with Loopback10/Loopback20 as the CORP/IOT user prefixes.
- **The depot circuit is conditioned in the start state** (2000 kb/s, 30 ms, 0.2 % loss on BR1 e0/0 to PROV-INET1 e0/1), because LAB.md documents it as provider-shaped. The exported YAML carries it. **BR1 starts with the uplink policy `PM-WAN-SHAPE` on e0/0 (shape 2 Mb/s; CM-VOICE priority 25 %, CM-SCANNER bandwidth 25 %, class-default fair-queue) and HQ-WAN1 starts with `crypto ipsec security-association replay window-size 1024`; BR1 has no replay line.** CR4 is the hub side toward the depot.
- **Compliance scope excludes DC-FUS1 and FAB-BDR1** (listed as `out_of_scope` in the JSON): FUS1 has no management plane in VRF MGMT (console, local login), FAB-BDR1 is Aster's. Making them deviations would stop the "after" report from being clean.
- **NTP**: the W3 lite files carry `ntp server vrf MGMT 10.50.50.1 key 1` after the `vrf definition MGMT` (IOS silently drops VRF-aware global lines placed ahead of the VRF definition at boot). MS-5 adds no NTP lines of its own.
- H5 lite drops CORE1's `dr-priority 200` and PIM on e0/0 (dual-core leftovers); DC-RTR1 has no e0/3 to shut; DC-FUS1/FAB-BDR1 are not on the syslog or RADIUS (F-H files).

## Intentional Faults

| ID | Device | Change | Symptom |
|---|---|---|---|
| F1 | HQ-ACC1 | `spanning-tree vlan 10 priority 4096` (the replacement switch's template) | ACC1's BPDUs for VLAN 10 are superior: root guard on DIST1 e0/2 and DIST2 e0/2 blocks both downlinks for VLAN 10 (`%SPANTREE-2-ROOTGUARD_BLOCK`, `Root Inconsistent`); PC1 has no gateway; VLAN 99 unaffected (TK1) |
| F2 | HQ-ACC1 | e0/1 (uplink to DIST2) `switchport trunk native vlan 1` (DISTs use 999) | `%CDP-4-NATIVE_VLAN_MISMATCH` about every 50 s on both ends; no user impact (latent, fails V2) |
| F3 | DC-RTR1 | OSPF 1 `passive-interface default` with no `no passive-interface Ethernet0/2` | DC-RTR1 has no adjacency with DC-FUS1; VRF SHARED loses every Veridian route and Aster's VN routes vanish from Veridian (TK2 part 1) |
| F4 | DC-FUS1 | `ip prefix-list SHARED-SERVICES seq 10` permits 10.50.52.0/24 instead of 10.50.51.0/24 | after F3: SHARED holds 10.50.51.0/24 but does not export it with RT 65010:50; BDR1 CORP and IOT lack it and gain the unused .52 (TK2 part 2, series) |
| F5 | BR1-RTR1 | `aaa authorization exec VTY if-authenticated` (was `group RADGRP local`) | RADIUS authenticates `netadmin` (Access-Accept, `Login OK` on DC-AAA1) but the server's privilege is not applied: `BR1-RTR1>`, privilege 1, `configure terminal` rejected (TK3 part 1) |
| F7 | HQ-ACC1 | the replacement switch's template attaches `ipv6 nd raguard policy HOST-RA-BLOCK` (`device-role host`) to every port, the uplinks e0/0 and e0/1 included (design: access ports only) | the DISTs' RAs for VLAN 10 are dropped as they enter ACC1: PC1 never learns an IPv6 default router; on-link IPv6 to the DISTs works, every off-link IPv6 destination fails at once (`Network unreachable`); IPv4 unaffected. Masked by F1 until F1 is fixed (TK1, series) |
| F8 | DC-FUS1 | `cts role-based sgt-map vrf CORP 10.60.20.0/24 sgt 20` entered under the office VRF, none under VRF IOT | IOT traffic reaches FUS1 unclassified; the `from unknown to 50` cell (DENY-ALL) refuses it at the routed hop: the scanners never reach 10.50.51.1, the office is unaffected. Masked by F3/F4 (no route to the shared service in VRF IOT) until both are fixed (TK2, series) |
| F6 | HQ-CORE1 | applet `GW-EVIDENCE` triggers on `event track 12 state any`; track 12 = IP SLA 12 to 10.10.255.67 (CORE2's old edge address), Down from boot | no evidence file on an edge-link event (TK3 part 2) |

**Fault logic.** TK1: F1 alone causes the outage; F2 is latent (found by logs or V2); F7 sits in series behind F1 for IPv6 (F1 only fixed: IPv4 back, off-link IPv6 still fails, measured; F7 only fixed: nothing changes, derived). TK2: F3 then F4 in series (F3 fixed restores Veridian's view of Aster but not the shared service for Aster; F4 alone changes nothing, both measured), then F8 behind both for the scanners only (derived for F8 alone). TK3: F5 and F6 parallel. Interactions: CR1 cannot be verified until F3 is fixed (the fusion learns Veridian's prefixes through DC-RTR1), and its export must add a prefix, not replace one (F4's mistake). CR2's failover test (an ISP-side silent failure) does not exercise F6: track 11 does not move for it, only V9's core-edge cable pull does. The real ticket/CR interaction is TK2 before CR1. CR3's flood must not run while CR2's backup is active.

Not faults (red herrings): OSPFv3 FULL and ::/0 on the DISTs, RAs every 4 s on Vlan10 (IPv6 routing and the gateways are fine); the IOT routes to 10.50.51.0/24 after F4 (routing is fine for the scanners); the DC-FUS1 SHARED mapping of 10.50.51.0/24 (idle); the root-guard messages (the guard is doing its job); VRRP Master with no peer (single core by design); FUS1–BDR1 eBGP Established in both VRFs; Access-Accept with privilege 15 on DC-AAA1 for the low-privilege sessions; SLA 12 Down in the monitoring excerpt (a stale object; it is the cause only through the applet); the first ping lost to ARP; hub traceroute to 192.0.2.200 showing `* * *` after INET1 (provider hop).

## Diagnosis / Methodology

**TK1.** PC1: port up, ARP for 10.10.10.1 unanswered; `show glbp` is healthy on both DISTs but neither sees PC1's ARP, so the fault is below the gateways. DIST1/DIST2 `show spanning-tree inconsistentports`: `VLAN0010 Ethernet0/2 Root Inconsistent` and `%SPANTREE-2-ROOTGUARD_BLOCK` on VLAN 10 only. ACC1 `show spanning-tree vlan 10`: `Root ID Priority 4106`, bridge = root: **F1**. `show interfaces trunk` on ACC1: e0/1 native 1 against DIST2 999, with the CDP mismatch logs: **F2**. After F1 (and F2): IPv4 works, IPv6 does not. PC1 `ip -6 route` holds the on-link prefix and fe80::/64 but no default, `ping -6 2001:db8:10:10::2` works, `ping -6 2001:db8:f001:200::200` says `Network unreachable`. The DISTs are eliminated: OSPFv3 FULL, ::/0 present, RAs every 4 s (`show ipv6 interface Vlan10`). `sudo tcpdump -i eth0 icmp6` on PC1 shows no type 134. ACC1 `show ipv6 nd raguard policy` lists Et0/0 and Et0/1 (the uplinks) among the targets and `show running-config interface Ethernet0/0` shows `ipv6 nd raguard attach-policy HOST-RA-BLOCK`: **F7** (no counters exist: the capture and the target list are the evidence).
Wrong fixes: removing root guard or lowering the DIST priorities below 4096 (V2), `bpdufilter` on the uplinks (V2); a static IPv6 default on PC1 (V1, V10); removing the policy from every port or deleting it (V2: the access-port standard); changing RAs on the DISTs (nothing to fix there). **The F7 trap:** detaching the policy only on the forwarding uplink (Et0/0, the VLAN 10 path to DIST1; Et0/1 is the STP alternate) passes V1 and the IPv6 ping at once, because DIST2's RAs also cross DIST1, so PC1 holds both default routers. The error shows only when DIST1 is lost: ACC1 then forwards on Et0/1, which still blocks DIST2's RAs, DIST1's router lifetime (12 s) expires and IPv6 never recovers (measured: IPv4 lost 6 pings and recovered, IPv6 stopped at seq 12 and returned only when the links were restored). So V10 fails only for DIST1.

**TK2.** FUS1 `show bgp vpnv4 unicast all summary`: both sessions Established with 1 prefix, so Aster's side is eliminated. FUS1 `show ip ospf 50 neighbor` is empty; DC-RTR1 `show ip protocols` lists Ethernet0/2 as passive and `show ip ospf neighbor` has only CORE1: **F3**. After F3: `show ip route vrf SHARED` holds 10.50.51.0/24, `show ip route vrf CORP` on FUS1 does not; `show bgp vpnv4 unicast all 10.50.51.0` has no RT 65010:50; the prefix-list names .52: **F4**. After F4 the office reaches 10.50.51.1 and the scanners do not: BDR1 `ping vrf CORP 10.50.51.1 source Loopback10` succeeds, `ping vrf IOT 10.50.51.1 source Loopback20` fails, `traceroute vrf IOT` answers at 10.200.60.4 (FUS1) and stops. FUS1 `show ip route vrf IOT 10.50.51.0` is present (routing eliminated). `show cts role-based counters` shows `0 50` (unknown to 50) SW-Denied rising with each probe and `20 50` at 0; `show cts role-based sgt-map vrf IOT all` lacks 10.60.20.0/24 while `vrf CORP all` holds it: **F8**. Wrong fixes: statics on FUS1 or DC-RTR1 for the shared service, a new RT or an import of .51 on the VN side (V3); removing the `from unknown to 50` cell or `no cts role-based enforcement` (V3); mapping the scanners into the office group (V3: scanners ICMP only); an IP ACL or static route on FUS1 (V3).

**TK3 (1).** `test aaa group RADGRP netadmin netpass legacy` succeeds on BR1 and DC-AAA1 logs `Login OK`: the server and the path are fine. `show privilege` in the NOC session is 1; the same account on HQ-WAN1 lands at 15; `show running-config | include authorization exec` on BR1: `if-authenticated` (a different method list from HQ-WAN1's `group RADGRP local`): **F5**; the "before" compliance report lists BR1 as unreadable. Wrong fixes: `aaa authorization exec VTY none`, `privilege exec level 1 configure terminal`, a local NOC user on BR1 (V8).

**TK3 (2).** `show event manager policy registered`: applet on `track 12`; `show track brief`: track 12 Down since boot, track 11 Up; no `gw-evidence.txt` in `unix:`; a CORE1/EDGE1 cable pull moves track 11 and writes nothing: **F6**. An ISP-side silent failure does not move track 11 either (EDGE1 stays up and the probe is to its core-facing address): see Answers.

**CR notes.** CR1: dedicated RT 65010:10 exported from SHARED for 10.10.10.0/24 only, imported by CORP only; OSPF-TO-BGP admits only the HELPDESK prefix; the outbound ACL on the CORP handoff sub-interface restricts ping and TCP 22 from 10.10.10.0/24 to Aster's CORP prefix (BDR1 Loopback10 10.60.10.1) and admits FUS1's own BGP (see design decisions). The ACL is stateless: BDR1 cannot ping the helpdesk from its own loopback source because the reply direction is outbound to CORP. CR2: the tracked /32 static to the Internet host (via PROV-INET1) is what the route-map matches, so the hub originates a default (metric 200, EDGE1 originates metric 10) only while its own path answers; no `always`. PAT on the hub and four return ACEs in `WAN1-INET-IN` (before the final deny). CR3: the SLA class exempts the hub's own SLA 20 replies (the flood would otherwise flap track 20). CR4: the bottleneck toward the depot is the provider's shaper at INET1, which Veridian does not control, so the queue has to be created upstream of it, at the hub, per depot: a parent class on HQ-WAN1 e0/0 output matching everything the hub sends to the depot's three tunnel endpoints (ESP to 203.0.113.131, .153 and .154: Tunnel21, Tunnel91 and Tunnel41 share the circuit) with `shape average 2000000` and the depot's child policy (EF priority 25 %, AF31 bandwidth 25 %, class-default fair-queue), classified on the outer header (the inner DSCP is copied to ESP). The parent class-default stays unshaped (HQ's CR2 backup, other depots). The shaper reorders ESP toward the depot, so BR1, the receiver, logs `%CRYPTO-4-PKT_REPLAY_ERR` and needs `crypto ipsec security-association replay window-size 1024` (the hub has it from the start; the new SAs need a tunnel `shutdown` / `no shutdown`, `clear crypto session` asks `[confirm]` and blocks scripted calls). **The trap:** copying the depot's policy as an interface-wide shaper on HQ-WAN1 e0/0 (class-default `shape average 2000000` + the child) holds HQ's backup Internet to 2 Mb/s and queues it behind the depot's bulk (V7 (b)): pings keep 0 % loss but the delay is 15.4/35.0/86.6 ms (min/avg/max, 3.7 times the average with the correct policy), so (b) is decided on the counters (HQ's pings must be in the parent class-default, not in CM-DEPOT) and the delay, not on loss alone.

## Solution Configuration

Each block is a config block (no `configure terminal`), proven on the original lab and again on the re-imported lab.

### TK1 / TK2 / TK3 fixes

```
@HQ-ACC1 config
no spanning-tree vlan 10 priority
interface Ethernet0/1
 switchport trunk native vlan 999
 no ipv6 nd raguard attach-policy HOST-RA-BLOCK
interface Ethernet0/0
 no ipv6 nd raguard attach-policy HOST-RA-BLOCK
@DC-FUS1 config
no cts role-based sgt-map vrf CORP 10.60.20.0/24 sgt 20
cts role-based sgt-map vrf IOT 10.60.20.0/24 sgt 20
@DC-RTR1 config
router ospf 1
 no passive-interface Ethernet0/2
@DC-FUS1 config
no ip prefix-list SHARED-SERVICES seq 10 permit 10.50.52.0/24
ip prefix-list SHARED-SERVICES seq 10 permit 10.50.51.0/24
@BR1-RTR1 config
aaa authorization exec VTY group RADGRP local
@HQ-CORE1 config
event manager applet GW-EVIDENCE
 event track 11 state any
```

Notes: F7: the policy stays on Et0/3, Et1/0 and Et1/1 (the host ports). F8: the mapping moves from VRF CORP to VRF IOT. Overwriting the F5 list is enough for the next login. If instead the list is removed with `no ... if-authenticated` and re-added, the line keeps the stale list until `line vty 0 4` / `no authorization exec VTY` / `authorization exec VTY` is re-entered. `no ip prefix-list ... seq 10` alone is "Incomplete command" on this image: give the whole entry. The unused track 12 / SLA 12 may be removed as housekeeping.

### CR1 (DC-FUS1)

`router ospf 50 vrf SHARED` / `capability vrf-lite` is already in DC-FUS1's start configuration (see the design decisions above) and is not part of the student's CR1 work; if the running YAML lacks it, add it first.

```
ip prefix-list HELPDESK seq 10 permit 10.10.10.0/24
route-map SHARED-EXP permit 20
 match ip address prefix-list HELPDESK
 set extcommunity rt 65010:10
route-map OSPF-TO-BGP permit 20
 match ip address prefix-list HELPDESK
vrf definition CORP
 address-family ipv4
  route-target import 65010:10
ip access-list extended CR1-ASTER-OUT
 5 permit tcp host 10.200.60.2 host 10.200.60.3 eq bgp
 6 permit tcp host 10.200.60.2 eq bgp host 10.200.60.3
 10 permit ip 10.50.51.0 0.0.0.255 any
 20 permit icmp 10.10.10.0 0.0.0.255 10.60.10.0 0.0.0.255 echo
 30 permit tcp 10.10.10.0 0.0.0.255 10.60.10.0 0.0.0.255 eq 22
 40 deny ip any any log
interface Ethernet0/1.3001
 ip access-group CR1-ASTER-OUT out
```

(ACEs 5 and 6 are a platform requirement of iol-xe, not IOS behaviour. The IOT handoff and Aster's border are untouched; the new RT is imported by CORP only.)

### CR2 (HQ-WAN1)

```
ip sla 20
 icmp-echo 192.0.2.200 source-interface Ethernet0/0
 frequency 5
ip sla schedule 20 life forever start-time now
track 20 ip sla 20 reachability
 delay down 5 up 10
ip route 192.0.2.200 255.255.255.255 203.0.113.128 track 20
ip prefix-list HUB-INET-PROBE seq 10 permit 192.0.2.200/32
route-map HUB-DEFAULT permit 10
 match ip address prefix-list HUB-INET-PROBE
router ospf 1
 default-information originate metric 200 route-map HUB-DEFAULT
ip access-list standard NAT-INSIDE
 10 permit 10.10.0.0 0.0.255.255
interface Ethernet0/0
 ip nat outside
interface Ethernet0/2
 ip nat inside
ip nat inside source list NAT-INSIDE interface Ethernet0/0 overload
ip access-list extended WAN1-INET-IN
 372 permit icmp host 192.0.2.200 host 203.0.113.129 echo-reply
 374 permit icmp host 192.0.2.200 host 203.0.113.129 unreachable
 376 permit icmp host 192.0.2.200 host 203.0.113.129 time-exceeded
 378 permit tcp host 192.0.2.200 host 203.0.113.129 established
event manager applet HUB-BACKUP-ON
 event track 20 state up
 action 1.0 syslog priority informational msg "HUB-BACKUP-ON: Internet path answers, offering the backup default"
event manager applet HUB-BACKUP-OFF
 event track 20 state down
 action 1.0 syslog priority informational msg "HUB-BACKUP-OFF: Internet path down, backup default withdrawn"
```

### CR3 (HQ-WAN1)

```
ip access-list extended CR3-IKE
 permit udp any any eq isakmp
 permit udp any any eq non500-isakmp
 permit esp any any
ip access-list extended CR3-ROUTING
 permit ospf any any
ip access-list extended CR3-NTP
 permit udp any any eq ntp
ip access-list extended CR3-SSH
 permit tcp 10.50.50.0 0.0.0.255 any eq 22
 permit tcp 10.10.99.0 0.0.0.255 any eq 22
ip access-list extended CR3-SLA
 permit icmp host 192.0.2.200 any echo-reply
ip access-list extended CR3-ICMP
 permit icmp any any echo
class-map match-all CM-IKE
 match access-group name CR3-IKE
class-map match-all CM-ROUTING
 match access-group name CR3-ROUTING
class-map match-all CM-NTP
 match access-group name CR3-NTP
class-map match-all CM-SSH
 match access-group name CR3-SSH
class-map match-all CM-SLA
 match access-group name CR3-SLA
class-map match-all CM-ICMP
 match access-group name CR3-ICMP
policy-map PM-HUB-COPP
 class CM-IKE
  police cir 512000 conform-action transmit exceed-action transmit
 class CM-ROUTING
  police cir 512000 conform-action transmit exceed-action transmit
 class CM-NTP
  police cir 64000 conform-action transmit exceed-action transmit
 class CM-SSH
  police cir 64000 conform-action transmit exceed-action transmit
 class CM-SLA
  police cir 64000 conform-action transmit exceed-action transmit
 class CM-ICMP
  police cir 8000 bc 1500 conform-action transmit exceed-action drop
control-plane
 service-policy input PM-HUB-COPP
```

### CR4 (HQ-WAN1, BR1-RTR1)

BR1-RTR1's uplink policy `PM-WAN-SHAPE` and HQ-WAN1's replay window are in the start state (see the design decisions). The student's work is the hub policy and BR1's replay window.

```
@HQ-WAN1 config
ip access-list extended HUB-TO-DEPOT
 permit esp any host 203.0.113.131
 permit esp any host 203.0.113.153
 permit esp any host 203.0.113.154
class-map match-all CM-DEPOT
 match access-group name HUB-TO-DEPOT
class-map match-any CM-VOICE
 match dscp ef
class-map match-any CM-SCANNER
 match dscp af31
policy-map PM-DEPOT-CHILD
 class CM-VOICE
  priority percent 25
 class CM-SCANNER
  bandwidth percent 25
 class class-default
  fair-queue
policy-map PM-HUB-OUT
 class CM-DEPOT
  shape average 2000000
  service-policy PM-DEPOT-CHILD
interface Ethernet0/0
 service-policy output PM-HUB-OUT
@BR1-RTR1 config
crypto ipsec security-association replay window-size 1024
interface range Tunnel21, Tunnel91, Tunnel41
 shutdown
 no shutdown
```

(Names are ours, not mandated.) Wait for 3 IKEv2 READY and 5 OSPF FULL on HQ-WAN1 (about 90 s); `clear crypto session` is avoided (`[confirm]`). `show policy-map interface Ethernet0/0 output` on HQ-WAN1 shows per-class counters.

### Compliance script (V11, AUTO-MGMT1; `/home/cisco/venv/bin/python compliance.py > before.json`)

```python
#!/usr/bin/env python3
"""Veridian management-standard compliance report (MS-5, 6.1). Run on AUTO-MGMT1:
   /home/cisco/venv/bin/python compliance.py > before.json
Logs in as the NOC RADIUS account netadmin (server-assigned privilege 15, no enable
fallback). A failed login, or privilege below 15, is itself a deviation."""
import json, re, sys
from netmiko import ConnectHandler

USER, PW = "netadmin", "netpass"
DEVICES = {  # name: (management address, options)
    "HQ-CORE1": ("10.10.99.2", {}),
    "HQ-DIST1": ("10.10.99.11", {}),
    "HQ-DIST2": ("10.10.99.12", {}),
    "HQ-ACC1": ("10.10.99.21", {"vrf": False}),
    "HQ-EDGE1": ("10.10.254.5", {}),
    "HQ-WAN1": ("10.10.254.11", {"acl": "WAN-MGMT"}),
    "BR1-RTR1": ("10.21.99.1", {"acl": "WAN-MGMT"}),
    "DC-RTR1": ("10.50.50.1", {"ntp_master": True}),
}
OUT_OF_SCOPE = {
    "DC-FUS1": "no management plane in VRF MGMT (fusion handoff device, local login only)",
    "FAB-BDR1": "Aster's border, not Veridian's device",
}


def check(cfg, o):
    dev, vrf = [], o.get("vrf", True)
    if not re.search(r"^aaa authentication login VTY group RADGRP local\s*$", cfg, re.M):
        dev.append("aaa authentication login VTY is not 'group RADGRP local'")
    if not re.search(r"^aaa authorization exec VTY group RADGRP local\s*$", cfg, re.M):
        dev.append("aaa authorization exec VTY is not 'group RADGRP local'")
    grp = re.search(r"^aaa group server radius RADGRP\n((?: .*\n)+)", cfg, re.M)
    if not grp:
        dev.append("no RADIUS server group RADGRP")
    elif vrf and "ip vrf forwarding MGMT" not in grp.group(1):
        dev.append("RADGRP does not use VRF MGMT")
    lh = r"^logging host 10\.50\.50\.51%s\s*$" % (" vrf MGMT" if vrf else "")
    if not re.search(lh, cfg, re.M):
        dev.append("logging host 10.50.50.51%s missing" % (" vrf MGMT" if vrf else ""))
    if o.get("ntp_master"):
        if not re.search(r"^ntp master", cfg, re.M):
            dev.append("NTP source of the network (ntp master) missing")
    else:
        ns = r"^ntp server %s10\.50\.50\.1 key 1\s*$" % ("vrf MGMT " if vrf else "")
        if not re.search(ns, cfg, re.M):
            dev.append("ntp server 10.50.50.1 key 1 missing")
    vty = re.search(r"^line vty 0 4\n((?: .*\n)+)", cfg, re.M)
    acl = o.get("acl", "MGMT-HOSTS")
    if not vty or ("access-class %s in vrf-also" % acl) not in vty.group(1):
        dev.append("VTY access-class %s in vrf-also missing" % acl)
    if not vty or "transport input ssh" not in vty.group(1):
        dev.append("VTY transport is not ssh only")
    return dev


report = {"account": USER, "devices": {}, "out_of_scope": OUT_OF_SCOPE}
for name, (ip, o) in DEVICES.items():
    r = {"address": ip, "deviations": []}
    try:
        c = ConnectHandler(device_type="cisco_ios", host=ip, username=USER, password=PW,
                           fast_cli=False, conn_timeout=30, auth_timeout=30, banner_timeout=30)
        r["prompt"] = c.find_prompt()
        m = re.search(r"level is (\d+)", c.send_command("show privilege"))
        r["privilege"] = int(m.group(1)) if m else None
        if r["privilege"] != 15:
            r["deviations"].append("login succeeds at privilege %s: running configuration unreadable, "
                                   "exec authorization does not apply the server's privilege" % r["privilege"])
        else:
            r["deviations"] += check(c.send_command("show running-config", read_timeout=60), o)
        c.disconnect()
    except Exception as e:
        r["deviations"].append("login failed: %s" % str(e).splitlines()[0][:100])
    r["compliant"] = not r["deviations"]
    report["devices"][name] = r
report["deviation_count"] = sum(len(d["deviations"]) for d in report["devices"].values())
print(json.dumps(report, indent=1))
```

Run it before the fixes (`deviation_count 1`: BR1-RTR1, login at privilege 1; the other seven in-scope devices compliant) and after the F5 fix (`deviation_count 0`, `out_of_scope` lists DC-FUS1 and FAB-BDR1 with the reason).

## Verification

Captured on the v1.3 build (v1.3 items) and on the v1.4/v1.5 build (F7, F8, CR4, V9, V10, V5 and AAA timings; the same configuration otherwise). Outputs marked (derived) were not run.

**Tickets (V1, V2, V3).**
```
HQ-PC1: ping 10.10.10.1 -> 3 packets transmitted, 3 packets received, 0% packet loss
DIST1/DIST2: Number of inconsistent ports (segments) in the system : 0
HQ-ACC1: Root ID Priority 24586 / Bridge ID Priority 32778; Et0/0 and Et0/1 trunking, native 999
DC-RTR1: 10.255.50.5 FULL Ethernet0/2 (plus CORE1 on Ethernet0/0 and Ethernet0/0.99)
DC-FUS1: show ip ospf 50 neighbor -> 10.255.50.1 FULL/ - Ethernet0/0
FAB-BDR1: show ip route vrf CORP|IOT | include ^B -> B 10.50.51.0/24 [20/0] via 10.200.60.2 (CORP) / 10.200.60.4 (IOT)
HQ-CORE1: show ip route 10.60.10.0 -> Known via "ospf 1" ... type extern 2, Last update from 10.10.255.131 on Ethernet1/1
BR1-PC1: ping 10.50.51.1 -> 0% packet loss (66-70 ms: the conditioned circuit)
```
**F7 and F8 (v1.4/v1.5 build).**
```
Start state: HQ-PC1 ping 10.10.10.1 -> 100% packet loss ; ip -6 route -> 2001:db8:10:10::/64, fe80::/64 only
HQ-ACC1: show ipv6 nd raguard policy -> HOST-RA-BLOCK (device-role host) on Et0/0, Et0/1, Et0/3, Et1/0, Et1/1
F1 only fixed: ping 10.10.10.1 0% loss after 25 s ; ip -6 route: no default ; ping -6 2001:db8:f001:200::200 -> Network unreachable ; ping -6 2001:db8:10:10::2 0% loss
F7 trap (policy off Et0/0 only): two defaults on PC1 (d700 DIST1, d600 DIST2), ping -6 Internet host works ; DIST1 total loss: IPv4 lost 6 pings, IPv6 stops at seq 12 and does not return
F7 fixed (policy off Et0/0 and Et0/1, native 999 on Et0/1): two defaults within 7 s, ping -6 2001:db8:f001:200::200 0% loss, IPv4 0% loss, root = DIST1 (24586)
F4 alone (F3 present): FUS1 no OSPF 50 neighbour, no B routes on BDR1 ; F3 alone: FUS1 neighbour 10.255.50.1 FULL, BDR1 CORP/IOT B 10.50.52.0/24 only ; F4 also fixed: B 10.50.51.0/24 on CORP (via .2) and IOT (via .4) after 14 s
F8 present: BDR1 ping vrf CORP 10.50.51.1 3/3 ; ping vrf IOT 0/3 ; traceroute vrf IOT: 10.200.60.4 then * * * ; show cts role-based counters: 0 50 SW-Denied 6, 10 50 permitted 3, 20 50 0
F8 fixed: ping vrf IOT 3/3 ; telnet 10.50.51.1 22 /vrf IOT /source-interface Loopback20 -> Connection timed out (20->50 denied 4, permitted 3) ; same from CORP -> Connection refused by remote host (reaches DC-RTR1's access class)
```
(ping -6 and tcpdump are the evidence for F7: there is no drop counter. IOT-only checks use Loopback20 as source.)

Each fix cleared its own symptom when applied alone (F1: 0 % loss after 11 s on the v1.3 build, 25 s on the v1.4/v1.5 build; F2: no more CDP mismatch; F3: FUS1 FULL in 8 s and the Veridian route 10.60.10.0/24 back on CORE1; F4: `B 10.50.51.0/24` on BDR1 CORP and IOT after 18 s).

**TK3.**
```
BR1 (F5 fixed, next login): BR1-RTR1#  Current privilege level is 15
compliance report after the fixes: deviation_count 0
HQ-CORE1 (F6 fixed, CORE1 e0/3 + EDGE1 e0/1 shutdown, then no shutdown):
  *05:32:13 / % Network not in table / Track 11 Reachability is Down
  *05:32:33 / Routing entry for 0.0.0.0/0 ... Last update from 10.10.255.65 on Ethernet0/3 / Track 11 Reachability is Up
```

**CR1 (V4).**
```
FAB-BDR1 CORP: B 10.10.10.0/24 [20/0] via 10.200.60.2 ; B 10.50.51.0/24 [20/0] via 10.200.60.2
FAB-BDR1 IOT : B 10.50.51.0/24 [20/0] via 10.200.60.4        (nothing of 10.10.10.0/24)
DC-FUS1: show bgp vpnv4 unicast all 10.10.10.0/24 -> Extended Community: RT:65010:10 (only)
HQ-PC1: ping 10.60.10.1 -> 0% packet loss ; nc -z -w 3 10.60.10.1 22 -> OPEN ; nc 10.60.10.1 23 -> Host is unreachable
v1.4/v1.5 build (group policy present): the same results; BDR1 CORP B 10.10.10.0/24 in 5 s; helpdesk traffic leaves the cells unchanged (0->50 denied stays 6, 10->50 permitted 4): helpdesk is an unknown source for the office group (no cell, default permit) and 10.50.51.1 stays inside SHARED, not crossing FUS1's enforcement. IOT ping to 10.50.51.1 still works
HQ-PC1: ping 10.60.20.1 -> 100% packet loss ; ping 10.50.51.1 -> 0% packet loss
DC-FUS1: CR1-ASTER-OUT  20 permit icmp ... echo (matches)  30 permit tcp ... eq 22 (matches)  40 deny ip any any log (matches)
DC-FUS1: show bgp vpnv4 unicast all summary -> 10.200.60.3 and 10.200.60.5 Established after 11 and 24 minutes (ACEs 5/6 in place)
```
Without ACEs 5/6: `%BGP-3-NOTIFICATION: ... 4/0 (hold time expired)` on FUS1 3 minutes after the ACL, and BDR1 CORP lost every route. ACEs 5 and 6 are a **CML platform requirement, not IOS behaviour**: on IOS hardware an outbound ACL does not filter the router's own traffic, so the two BGP ACEs would not be needed; on this iol-xe image an outbound ACL also filters router-originated traffic. The failure appears only after the BGP hold time, so a student must re-check the session (`show bgp vpnv4 unicast all summary`) more than 3 minutes after applying the ACL before calling V4 done.

**CR2 (V5).**
```
HQ-WAN1: track 20 Reachability is Up ; ip route 192.0.2.200/32 static via 203.0.113.128
OSPF type-5 default: Advertising Router 10.255.10.31 Metric 10 ; Advertising Router 10.255.10.41 Metric 200
HQ-CORE1: 0.0.0.0/0 via 10.10.255.65 (EDGE1) while the edge is healthy
HQ-PC1 traceroute 192.0.2.200: 10.10.10.2, 10.10.255.2, 10.10.255.65, 198.51.100.64 (EDGE1 path)
EDGE1-ISP1 link stop -> HQ-PC1 traceroute: 10.10.10.2, 10.10.255.2, 10.10.255.97, 203.0.113.128 (hub path, PAT'd), 16 s after the call
DC-SYSLOG1 / HQ-WAN1 log: %HA_EM-6-LOG: HUB-BACKUP-ON: ... (one message per change)
```

**CR3 (V6), flood `ping -q -i 0.01 -s 0 -w 40 203.0.113.129` from BR1-PC1 (3810 sent, 985 answered).**
```
CM-ICMP   conformed 572 packets ; exceeded 1575 packets (dropped) ; rate 2000 bps / 2000 bps
CM-ROUTING conformed 100 packets ; CM-IKE conformed 8 ; CM-SLA conformed 7
HQ-WAN1: OSPF FULL 5 ; IKEv2 READY 3 ; NTP *~10.50.50.1 reach 7
```
(An earlier measurement mid-flood: ICMP exceeded 1217-3891 packets; CM-SSH 72-78 packets conformed while a netadmin SSH session from AUTO-MGMT1 to 10.10.254.11 stayed at privilege 15; CM-NTP stays 0 until the second poll; ESP is not counted separately.) The flood saturates the shared 2 Mb/s depot uplink, so a BR1-PC1 to HQ-PC1 ping during it is lost (the pipe, not the hub).

**CR4 (V7 (a)), both directions at once, 60 s (EF `-S 0xb8 -b 300k -l 200`, AF31 `-S 0x68 -b 400k -l 1200`, bulk `-b 3m -l 1200`; receivers `iperf -s -u -p 5001/5002/5003 -i 30`), receiver side, v1.4/v1.5 build:**
```
At HQ-PC1 (from BR1-PC1): EF 17/11253 lost (0.15 %), AF31 4/2503 (0.16 %), bulk 930 kb/s, 68 % loss (the shaper's share)
At BR1-PC1 (from HQ-PC1): EF 20/11253 lost (0.18 %), AF31 4/2503 (0.16 %), bulk 930 kb/s, 68 % loss
HQ-WAN1 CM-DEPOT: shape 2000000; CM-VOICE priority 25 %, exceed drops 0; CM-SCANNER 0 drops; child class-default 12834 drops (the bulk); parent class-default 0 drops
BR1 PM-WAN-SHAPE: class-default 12834 drops (identical), voice and scanner 0 ; #recv errors 0 on all three SAs on both ends, no PKT_REPLAY_ERR
```
Before the hub policy: HQ-PC1 to BR1-PC1 EF 56 % lost, AF31 52 %, bulk 44 % (the provider's shaper drops blindly; EF reaches the hub unchanged). Hub policy without the replay window on BR1: EF 0.13 %, AF31 0.16 %, bulk 100 % lost (9352/9378), `%CRYPTO-4-PKT_REPLAY_ERR` on BR1, `#recv errors 2949` on Tunnel21's SA. With `replay window-size 1024` on BR1 and new SAs: EF 0.21 %, AF31 0.08 %, bulk 932 kb/s, `#recv errors` 0. Packet length matters for EF: the 25 % LLQ counts wire bytes after GRE/ESP overhead, so a smaller `-l` loses more (v1.3 build: `-l 160` lost about 10 %, `-l 200` 0.25 %).

**CR4 (V7 (b)), edge-path failure active, load toward the depot running (HQ-PC1 EF/AF31/bulk for 100 s, EDGE1-ISP1 `link stop`, CORE1 default from 10.255.10.41 within 17 s):**
```
Correct policy: HQ-PC1 ping -s 1400 -i 0.2 -c 150 192.0.2.200 -> 0% loss, rtt 7.7/9.5/13.4 ms
HQ-WAN1: parent class-default 208 packets (the pings, 31 NAT translations); CM-DEPOT 31666 packets (voice 10932, scanner 2530, bulk 18204)
Interface-wide trap (class-default shaper PM-HUB-ALL + child on e0/0): 0% loss, rtt 15.4/35.0/86.6 ms (the pings share the depot's shaped queue with the bulk)
```
The trap is removed and PM-HUB-OUT restored after the test.

**V8.** `compliance` after: 0 deviations on 8 devices (netadmin at privilege 15 everywhere); before: `deviation_count 1` (BR1-RTR1: `login succeeds at privilege 1: running configuration unreadable ...`), 7 devices compliant, DC-FUS1 and FAB-BDR1 out of scope. The count goes from 1 to 0 with the F5 fix. DC-AAA1 stopped: `admin` / `Cisco123!` logs in on BR1, HQ-WAN1 and HQ-CORE1 after the RADIUS dead-criteria (first login 12-13 s, later logins 2-3 s while the server stays marked dead); DC-AAA1 started: `netadmin` works again on CORE1 and BR1 within 9 s of the poll start, HQ-WAN1 one poll later (all three by about 30 s).

**V9 (v1.4/v1.5 build).** CORE1 e0/3 + EDGE1 e0/1 `shutdown`, then `no shutdown`: `more unix:/gw-evidence.txt` holds `Track 11 Reachability is Down` / `Timeout`, then after `no shutdown` `Up` / `OK` (return to Up 7-13 s). Delete the file with `delete /force unix:/gw-evidence.txt` before each run (the `unix:/` form: `unix:gw-evidence.txt` is "No such file", and a leftover file makes `--until` match at once).

**End state (v1.4/v1.5 build).** HQ-PC1 ping 10.10.10.1, `ping -6` Internet host, 192.0.2.200, 10.50.51.1 and BR1-PC1: 0 % loss; DIST1/DIST2 inconsistent ports 0; DIST1 RAs every 4 s, lifetime 12 s; ACC1 native 999 on both uplinks, `ipv6 nd raguard attach-policy` on Et0/3, Et1/0, Et1/1 only; no new NATIVE_VLAN_MISMATCH lines; FUS1 cells 0->50 denied 6, 10->50 permitted 4, 20->50 denied 4 / permitted 5.

## Failure / Recovery Behaviour

Note: do V2's log check (no error or warning messages in the campus switching logs) before the V10 failure tests; transient `%SPANTREE-2-ROOTGUARD_BLOCK/UNBLOCK` and `LOOPGUARD_BLOCK/UNBLOCK` lines appear after V10 restores.

Failure methods: V5 is a **silent failure** (`link stop` on HQ-EDGE1 e0/0 to PROV-ISP1 e0/0; the interfaces stay up); V9 is a **cable pull** (`shutdown` on both ends); V10 is a **silent total loss** of all the switch's links (`link stop` x4, REST calls issued in parallel; no switch restart, so the RA lifetime is untouched); the AAA test is a **node stop**.

| Scenario (trigger -> end condition) | Runs (raw) | Documented range | Basis |
|---|---|---|---|
| V5 `link stop` EDGE1-ISP1 -> HQ-PC1 reaches 192.0.2.200 again (ping -i 1, lost pings = seconds) | lost 17, 16, 16 s (v1.3 build: 18, 17, 14) | 12-22 s (requirement: 30 s) | EDGE1 SLA 10 freq 5 + track `delay down 5`, then OSPF flush; CORE1 re-learns the hub default |
| V5 return: `link start` -> CORE1 default `from 10.255.10.31` again (no loss) | 45 (first call includes the session start), 33, 33 s (v1.3 build: 30-35, 33, 33) | 24-50 s, measured from the end of the `link start` call | EDGE1 track `delay up 30`: the 30 s timer starts at the first good probe, which can precede the end of the REST call (other runs: 25, 31, 24 s) |
| CR2 hub path failed (`link stop` WAN1-INET1) -> `show track 20` Down / `link start` -> Up (a scripted CLI poll every 2 s) | Down after 5, 3, 3 s; Up after 8, 8, 8 s (include one poll interval) | Down about 14-15 s (range about 10-20 s), Up about 16-18 s (about 10-25 s); take the times from the router's `%TRACK-6-STATE` timestamps, not from a polling session whose connect time hides the delay (other runs: Down 14, 15, 14 s; Up 16, 18, 16 s) | SLA 20 freq 5 with the default 5 s timeout, `delay down 5 up 10` |
| V9 cable pull CORE1 e0/3 + EDGE1 e0/1 `shutdown` -> `unix:/gw-evidence.txt` exists | 2, 2, 4 s (an 8 s run was discarded: stale file; v1.3 measured 7 s) | 2-10 s | SLA 11 frequency and the EEM trigger; return to Up 7-13 s after `no shutdown` |
| V10 DIST1 (GLBP AVG, VLAN 10 root) silent total loss (`link stop` x4 in parallel) -> PC1 IPv4 gateway ping restored | lost 4, 4, 5 s | 3-8 s | ACC1 RSTP ages the silent uplink BPDU; failback loses about 1 ping |
| V10 DIST1 same trigger -> PC1 `ping -6 -i 1 2001:db8:f001:200::200` restored | lost 11, 12, 9 s | 8-14 s | the preferred default router's 12 s RA lifetime must expire; the surviving default is DIST2's (the F7 trap never recovers) |
| V10 DIST2 silent total loss -> IPv4 and IPv6 | IPv4 0, 0, 0 s; IPv6 3, 4, 0 s | IPv4 0-1 s; IPv6 0-4 s | **IPv4, CML artefact:** the VLAN 10 STP root DIST1 routes frames addressed to either GLBP MAC (CML platform behaviour, see LAB-075). On hardware a host holding DIST2's forwarder MAC would lose connectivity until DIST1 takes over that forwarder, about the GLBP hold time `(derived)`, so 0 s is not a hardware expectation. **IPv6, ECMP return path:** HQ-CORE1 holds two OSPFv3 paths to the user /64 (via DIST1 and via DIST2), so the Internet host's return traffic hashes onto either; flows returning via the lost DIST2 stay broken until OSPFv3 declares it dead, so the loss depends on the hash (0 s if the flow hashes to DIST1) |
| DC-AAA1 `node stop` -> local `admin` login works | first login 13, 12, 12 s (BR1, WAN1, CORE1); a second pass while the server stays marked dead 3, 2, 2 s | first fallback login 10-20 s; later 2-4 s | RADIUS dead-criteria then local; restore: `node start`, `netadmin` works within 10-35 s |

V9 takes 2-4 s after the second shutdown. Failure of both stacks is timed because the RA lifetime, not the STP time, sets the IPv6 outage.

The student's flood run must not overlap CR2's backup. The hub path was also failed on its own (CR2 branch above) with exactly one syslog message per change on DC-SYSLOG1 (v1.4/v1.5 build: 7 lines in all, `HUB-BACKUP-ON` at install 05:46:30 then OFF/ON pairs at 06:21:30 / 06:21:50 and so on, all through VRF MGMT).

## Answers to Analysis Questions

**Q1.** TK1: `show glbp` healthy on both DISTs but no ARP seen, so the fault is below the gateways; then the root-inconsistent ports and ACC1's own root bridge. TK2: BGP Established with prefixes (Aster's side and the handoff are fine), then FUS1's empty OSPF 50 neighbour table. TK3 (1): `test aaa` and DC-AAA1's `Login OK` rule out the server and the path; `show privilege` 1 against 15 on WAN1. TK3 (2): the edge-link event is real (track 11 moves), but the applet watches track 12. TK1 after the STP fix: PC1 pings the gateway but `ip -6 route` has no default and the DISTs' RAs are being sent, so the gateways are eliminated and the path between them and the host is the suspect; TK2 for the scanners: the route is present in VRF IOT, so the fusion's policy counters (unknown to 50 denied) rule out routing.

**Q2.** The pack omits Aster's prefixes (BDR1's loopbacks 10.60.10.1 and 10.60.20.1: found from FUS1's VRF tables), the hub's circuit policy (read `WAN1-INET-IN`), and the core's two SLA objects (read `show track brief`, `show ip sla configuration`). The monitoring excerpt makes SLA 12 look like an outage; it is a stale object. The script (netmiko through VRF MGMT) rebuilds the management facts on eight devices.

**Q3.** TK2 before CR1 (the fusion learns Veridian's prefixes through DC-RTR1, so F3 blocks the CR1 proof; F4's replace-versus-add mistake must not be repeated in the export design). CR2's failover test does not exercise F6 (an ISP-side silent failure does not move track 11; only V9's core-edge cable pull does); the real ticket/CR interaction is TK2 before CR1. CR3's flood must wait until CR2 is idle (the hub is then the Internet path). CR4's shaper makes the replay window necessary (CR4 interacts with the WAN design, not with a ticket). The management script runs first and last.

**Q4.** Service restored: F1, F7 (IPv6 gateways), F3, F4, F8 (the scanners), F5 (users, Aster, NOC rights). Redundancy or observability only: F2 (no user impact), F6 (evidence file), CR2 (nothing changes until the edge path fails), CR3 (nothing changes until a flood). Proof: failure tests with named methods (V5, V9, V10) and counters (CR3, CR4).

**Q5.** Pre-change: record `show spanning-tree inconsistentports`, BGP prefix counts per VRF, the compliance report, the track table. Post-change: the same set plus an end-to-end test from each user VLAN and a source-specific ping to the shared service from both Aster VRFs; run the compliance script as a gate; check the log for `%CDP-4-NATIVE_VLAN_MISMATCH` and `%SPANTREE-2-ROOTGUARD_BLOCK` after every switch replacement.

**Instructor debrief.** *Why TK2 needed two fixes:* the shared service reaches Aster by OSPF (DC-RTR1 to FUS1), then BGP redistribution with an export map; the adjacency (F3) and the prefix filter (F4) are different stages of the same path, and the second symptom only appears when the first clears. *Why IPv4 came back after the STP fix and IPv6 did not (TK1):* the router advertisement is the IPv6 gateway mechanism; the host-port RA guard was applied to the uplinks too, so the DISTs' RAs were dropped on entry to ACC1. *Why the F7 shortcut fails only for DIST1:* removing the guard on the forwarding uplink still lets DIST2's RAs through, so PC1 has two default routers; when DIST1 dies ACC1 forwards on the guarded alternate and the surviving router's RAs no longer arrive. *Why the office came back and the scanners did not (TK2):* the group lookup uses the ingress VRF's mapping, so scanner traffic entered VRF IOT unclassified and met the unknown-source cell (the unknown-source case of the group policy turned into a deny). *Why CR4 needs the hub:* the provider's shaper at INET1 drops blindly, so the priority queue has to exist upstream, per depot, without taking HQ's backup Internet into the queue; the shaper's reordering then needs the replay window on the receiver. *Why an ISP-side failure does not move the core's track:* track 11 probes EDGE1's core-facing address, which stays up when EDGE1's provider link fails; EDGE1's own track 10 and the OSPF default handle that failure, and only a core-to-edge cable pull moves track 11.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-18 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), external_connector, iol-xe (IOS XE 17.16.1a), ioll2-xe (IOS XE 17.16.1a), radius, syslog, ubuntu (Ubuntu 24.04), unmanaged_switch |
