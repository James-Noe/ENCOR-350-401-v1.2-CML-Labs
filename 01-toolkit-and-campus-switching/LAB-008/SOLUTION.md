# LAB-008 — Solution

## Summary

Foundation lab (F · G3, 45 min) on the FND switch chain B topology (SW1–SW2–SW3 `ioll2-xe`, PC1/PC2 traffic hosts, PC3 an Alpine capture host with no IP). The student mirrors a local port with SPAN, then extends the capture across the switch chain with RSPAN, and works out what the transit switch (SW2, which never runs a SPAN session itself) needs so RSPAN traffic actually crosses it.

Blueprint mapping: **4.3:I** (SPAN/RSPAN/ERSPAN), reinforces **3.1.a:R** (trunks, allowed VLANs). No 4.1-toolkit V-item beyond the tcpdump capture itself, since capturing traffic on the wire *is* the toolkit skill this lab teaches.

No intentional faults (F lab). R2's "VLAN 950 not yet allowed on the trunks" is a designed discovery step, not a fault: LAB.md tells the student to verify the RSPAN path switch by switch if PC3 sees nothing, and V4 asks for a prediction before SW2 is configured, then the observed result.

## Diagnosis / Methodology

Not a troubleshooting lab. The evidence path for R2/R3 (the interesting part — R1 local SPAN is a single-switch operation):

1. Configure the RSPAN source session on SW1 and the destination session on SW3 (`vlan 950` / `remote-span` on both, `monitor session ... source/destination remote vlan 950`). At this point PC3 sees nothing (the expected V4 observation), because a remote-span VLAN behaves like any other VLAN for trunking purposes: it must be **allowed on every trunk link on the path**, and every switch it crosses must know about it.
2. `show vlan remote-span` and `show interfaces trunk` on each switch in turn, source to destination, show where the VLAN stops being carried. On SW1 and SW3 alone, the VLAN exists locally but is missing from `Vlans allowed on trunk` on **both** switches' own Et0/0, in addition to being entirely absent from SW2.
3. Once VLAN 950 is created and allowed end to end, `show interfaces trunk`'s "Vlans in spanning tree forwarding state and not pruned" column confirms the VLAN is actually forwarding, not just administratively allowed.

## Solution Configuration

As tested in CML.

**R1 — local SPAN on SW3** (PC2's port both directions → PC3's port):

```
! SW3
monitor session 1 source interface Ethernet1/0 both
monitor session 1 destination interface Ethernet1/1
```

**R2 — remove the local session, build RSPAN from SW1 to SW3:**

```
! SW3 — remove the local session first
no monitor session 1

! SW1 — remote source session
vlan 950
 remote-span
monitor session 1 source interface Ethernet1/0 both
monitor session 1 destination remote vlan 950

! SW3 — remote destination session
vlan 950
 remote-span
monitor session 2 source remote vlan 950
monitor session 2 destination interface Ethernet1/1
```

**R3 — what SW2 (the transit switch) needs, with no monitor session of its own:**

```
! SW2
vlan 950
 remote-span
interface range Ethernet0/0 - 1
 switchport trunk allowed vlan add 950
```

**The allowed-list gap on SW1 and SW3 themselves.** Creating `vlan 950`/`remote-span` and the monitor sessions on SW1 and SW3 does **not** automatically add VLAN 950 to those switches' own trunk allowed lists — a separate step, easy to forget:

```
! SW1
interface Ethernet0/0
 switchport trunk allowed vlan add 950
! SW3
interface Ethernet0/0
 switchport trunk allowed vlan add 950
```

**R4 — failure test** (remove VLAN 950 from the SW2–SW3 trunk only, on SW2):

```
! SW2 — break it
interface Ethernet0/1
 switchport trunk allowed vlan remove 950
! SW2 — restore it
interface Ethernet0/1
 switchport trunk allowed vlan add 950
```

## Verification

All output below was captured in CML (trimmed).

**R1 — local SPAN, before/after PC3's port** (from a fresh import, where PC3's initial state and the SPAN session were both observed fresh):

```
! before: PC3's port is an ordinary access port
SW3# show interfaces status
Et1/1        PC3                connected    10           full   auto 10/100/1000BaseTX

! after: monitor session 1 source interface Ethernet1/0 both / destination interface Ethernet1/1
SW3# show monitor session 1
Session 1
---------
Type                     : Local Session
Source Ports             :
    Both                 : Et1/0
Destination Ports        : Et1/1
    Encapsulation        : Native
SW3# show interfaces status
Et1/1        PC3                monitoring   10           full   auto 10/100/1000BaseTX
SW3# show interfaces Ethernet1/1
Ethernet1/1 is up, line protocol is down (monitoring)
SW3# show spanning-tree vlan 10
! only Et0/0 (Root FWD) and Et1/0 (Desg FWD Edge) listed — Et1/1 has left the spanning tree
```

PC3 capture (30 s bg tcpdump, `icmp` filter) while PC1 pinged PC2 (10.0.10.102):

```
PC3$ sudo timeout 30 tcpdump -nni eth0 icmp
02:27:27.779449 IP 10.0.10.101 > 10.0.10.102: ICMP echo request, id 2, seq 0, length 64
02:27:27.780504 IP 10.0.10.102 > 10.0.10.101: ICMP echo reply, id 2, seq 0, length 64
02:27:28.779302 IP 10.0.10.101 > 10.0.10.102: ICMP echo request, id 2, seq 1, length 64
02:27:28.780319 IP 10.0.10.102 > 10.0.10.101: ICMP echo reply, id 2, seq 1, length 64
02:27:29.779514 IP 10.0.10.101 > 10.0.10.102: ICMP echo request, id 2, seq 2, length 64
02:27:29.781462 IP 10.0.10.102 > 10.0.10.101: ICMP echo reply, id 2, seq 2, length 64
6 packets captured, 0 dropped
```

**R2/R3 — the intermediate state (V4)**, captured verbatim before SW2 or the SW1/SW3 allowed lists were fixed:

```
! SW1 — remote source session exists, but Et0/0 still only allows 10,99
SW1# show monitor session all
Type                     : Remote Source Session
    Both                 : Et1/0
Dest RSPAN VLAN          : 950
SW1# show interfaces trunk
Vlans allowed on trunk
Et0/0          10,99

! SW3 — remote destination session exists, Et1/1 already "monitoring", but Et0/0 still only allows 10,99
SW3# show monitor session all
Session 2
Type                     : Remote Destination Session
Source RSPAN VLAN        : 950
Destination Ports        : Et1/1
SW3# show interfaces trunk
Vlans allowed on trunk
Et0/0          10,99

! SW2 — has never heard of VLAN 950 at all
SW2# show vlan brief
! no VLAN 950 listed
SW2# show running-config | section vlan 950
! (empty)
SW2# show interfaces trunk
Vlans allowed on trunk
Et0/0          10,99
Et0/1          10,99
```

At this point PC3 sees no ICMP traffic even though both SW1 and SW3 report their monitor sessions as active. Cause: VLAN 950 cannot reach SW3 because SW2 does not carry it, **and** even after SW2 is fixed, SW1's and SW3's own Et0/0 ports still exclude it locally.

**R3/R2 — after fixing SW2, then SW1 and SW3:** (R3 allows "justify why nothing is needed" as a possible answer, but here it is wrong: SW2 carries the monitored traffic as a transit switch, so it needs VLAN 950 defined and the trunks allowing it; without them R2 receives nothing.)

```
SW2# show vlan remote-span
Remote SPAN VLANs
950
SW2# show interfaces trunk
Vlans allowed on trunk
Et0/0          10,99,950
Et0/1          10,99,950

SW1# show interfaces trunk
Vlans allowed on trunk
Et0/0          10,99,950
Vlans in spanning tree forwarding state and not pruned
Et0/0          10,99,950

SW3# show interfaces trunk
Vlans allowed on trunk
Et0/0          10,99,950
Vlans in spanning tree forwarding state and not pruned
Et0/0          10,99,950
```

**R2/V3 — end-to-end RSPAN capture:**

```
PC1$ ping -c 5 10.0.10.102
5 packets transmitted, 5 packets received, 0% packet loss

PC3$ sudo timeout 40 tcpdump -nni eth0 icmp
02:19:26.363095 IP 10.0.10.101 > 10.0.10.102: ICMP echo request, id 2, seq 0, length 64
02:19:26.367007 IP 10.0.10.102 > 10.0.10.101: ICMP echo reply, id 2, seq 0, length 64
02:19:27.364330 IP 10.0.10.101 > 10.0.10.102: ICMP echo request, id 2, seq 1, length 64
02:19:27.368250 IP 10.0.10.102 > 10.0.10.101: ICMP echo reply, id 2, seq 1, length 64
02:19:28.364270 IP 10.0.10.101 > 10.0.10.102: ICMP echo request, id 2, seq 2, length 64
02:19:28.368329 IP 10.0.10.102 > 10.0.10.101: ICMP echo reply, id 2, seq 2, length 64
02:19:29.365025 IP 10.0.10.101 > 10.0.10.102: ICMP echo request, id 2, seq 3, length 64
02:19:29.369059 IP 10.0.10.102 > 10.0.10.101: ICMP echo reply, id 2, seq 3, length 64
02:19:30.365128 IP 10.0.10.101 > 10.0.10.102: ICMP echo request, id 2, seq 4, length 64
02:19:30.369283 IP 10.0.10.102 > 10.0.10.101: ICMP echo reply, id 2, seq 4, length 64
10 packets captured, 0 dropped
```

10 frames for 5 pings (5 request + 5 reply), no duplicates in this run — LAB.md's platform note that RSPAN copies "can" arrive twice is a *can*, not an *always*; this run shows the clean case.

## Failure / Recovery Behaviour

**Test (R4):** remove VLAN 950 from the SW2–SW3 trunk (Et0/1) only, on SW2; SW2's other trunk (Et0/0, to SW1) is untouched.

```
SW2(config)# interface Ethernet0/1
SW2(config-if)# switchport trunk allowed vlan remove 950
SW2# show interfaces trunk
Vlans allowed on trunk
Et0/0          10,99,950
Et0/1          10,99
```

- PC1 → PC2: `ping -c 5 10.0.10.102` → 5/5, 0% packet loss (VLAN 10 is untouched; only VLAN 950 was removed).
- PC3: `sudo timeout 40 tcpdump -nni eth0 icmp` → only the tcpdump startup banner, **0 ICMP frames captured**, over a 10 s window while PC1 pinged PC2. RSPAN traffic dies at SW2's Et0/1 because it is no longer an allowed VLAN on that trunk, even though the RSPAN VLAN and monitor sessions on SW1/SW3 are untouched.
- SW2 log: `%SYS-5-CONFIG_I: Configured from console by console` at `02:20:38`/`02:20:39`, matching the moment the change was made (the platform logs the generic "configured from console" event, not a VLAN-specific message, for this kind of change).
- **Recovery:** `switchport trunk allowed vlan add 950` on SW2 Et0/1 → `show interfaces trunk` shows both trunks `10,99,950` again (log: `%SYS-5-CONFIG_I` at `02:21:40`/`02:21:41`, ~62 s after the removal). PC1 → PC2 ping repeated (5/5, 0% loss) with a fresh PC3 capture: ICMP frames present again, confirming the capture resumes.

**Restore:** stop → wipe → start SW1/SW2/SW3 (PC1–PC3 were never reconfigured, only used to generate/observe traffic) returned every switch to the day-0 state: trunks `10,99` only on all links, "No SPAN configuration is present in the system" on all three switches, PC3's port back to plain `connected` (not `monitoring`), PC1 → PC2 still working. The same was re-verified on a fresh import (`tools/cml-rest.sh import`).

## Answers to Analysis Questions

**Q1.** A SPAN/RSPAN destination port stops participating in the switch's normal forwarding and spanning-tree logic because its only job while it is a destination is to transmit copies of the monitored traffic (`both` in the session refers to the source port's received and sent frames); by default it accepts no ingress traffic, does not learn MACs and leaves spanning tree. It is deliberately taken out of MAC learning and STP so that mirrored frames cannot be mistaken for real traffic or create a loop. PC3's port reported `Et1/1 PC3 monitoring 10` in `show interfaces status` and `Ethernet1/1 is up, line protocol is down (monitoring)` in `show interfaces Ethernet1/1`; it dropped out of `show spanning-tree vlan 10` entirely. `show monitor session 1 detail` on this platform (ioll2-xe) has no ingress-state line, so the no-ingress default is shown by behaviour instead: with SPAN active, a host on the destination port (10.0.10.103) pinging PC2 got 0 of 5 replies and PC2 saw no frames from it; after `no monitor session 1` the same ping succeeded 3/3 and the port returned to `connected`. A user plugged into a SPAN destination port would appear to have a working physical link (LED up) but no connectivity at all: the port neither learns their MAC address nor forwards their frames onto the VLAN, so DHCP, ARP and every other exchange would simply fail.

**Q2.** Sourcing an entire VLAN or a whole trunk (instead of one access port) copies every frame that crosses that VLAN or link, in both directions, onto a single destination port. Two problems follow. First, the aggregate traffic on a busy VLAN or trunk can easily exceed the destination port's own speed (in this lab, 10 Mb/s on `ioll2-xe`): once the mirrored volume exceeds what the destination port can transmit, the switch silently drops the overflow rather than mirroring everything, so the capture becomes incomplete without any obvious error. Second, mirroring "both" directions of a link effectively doubles the traffic that must be squeezed onto that one port, since traffic that would normally split across two directions on the source is combined onto one direction on the destination. A single access port's traffic, as used in this lab (PC1's and PC2's ports), stays well under the destination port's capacity and mirrors only the traffic that actually matters for the investigation.

**Q3.** RSPAN copies traffic by flooding it, unencapsulated as ordinary Ethernet frames, into a dedicated VLAN (950 here) that is carried like any other VLAN across 802.1Q trunks between the source and destination switches — every switch in the path must know that VLAN and allow it on its trunks, exactly as this lab demonstrates with SW2. Because it is still a Layer 2, single-broadcast-domain mechanism, RSPAN cannot cross a routed (Layer 3) hop, and every intermediate switch must be RSPAN-capable and correctly configured; the RSPAN VLAN is also excluded from normal MAC learning and (in this lab's platform note) can arrive at the destination duplicated. ERSPAN instead encapsulates each mirrored frame inside a GRE/IP packet and routes it as ordinary IP traffic to a destination anywhere reachable by IP — including across Layer 3 boundaries, a WAN, or to a remote analysis tool — at the cost of GRE/IP overhead and needing IP reachability and MTU headroom end to end, plus platform support for ERSPAN encapsulation and decapsulation (available on `cat8000v` in this project's environment, not on `ioll2-xe` or `iol-xe`; met again in lab 066). Choose ERSPAN when the source and destination are not on the same Layer 2 domain, when the capture must cross routed infrastructure, or when the destination is a remote tool rather than a directly attached local host.

**Q4.** PC3 sees PC1's traffic despite having no IP address because SPAN/RSPAN operates below Layer 3: the switch copies frames at Layer 2 based on the source port or VLAN, without regard to whether the destination host has any IP configuration at all, and PC3's NIC in promiscuous capture mode (`tcpdump`) simply reads whatever frames its port receives. This is good practice for a dedicated capture host because it has no addressable presence on the network to attack, misconfigure, or accidentally route through — it cannot originate or accept normal traffic, cannot be pinged, and cannot become a security exposure through its own stack, yet it still gives full visibility into everything mirrored to it.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-17 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), ioll2-xe (IOS XE 17.16.1a) |
