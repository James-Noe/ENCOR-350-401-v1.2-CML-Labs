# LAB-005 — Solution

## Summary

Troubleshooting lab (T · G2 · 45 min). Blueprint mapping: **3.1.b:T** (EtherChannel troubleshooting: member compatibility, mode mismatch between `on` and LACP), **3.1.a:R** (trunk mode on a member port), and 4.1 toolkit evidence (log buffer, sourced ping, traceroute). LAB.md lists domains only (3, 4).

The start state is LAB-004's finished design plus two faults from a "port cleanup" change. Each fault produces one ticket. T1 looks like a routing or gateway problem, because PC1 reaches its gateway and the static routes are configured, but the cause is the SW2–SW3 bundle. That bundle looks healthy from SW3, so the student must compare both ends. T2 has no port down: a member is suspended, not failed.

## Intentional Faults

| ID | Device | What was changed | Symptom |
|---|---|---|---|
| F1 | SW2 Ethernet0/1 (Po1 member) | `switchport mode access` instead of `switchport mode trunk`; the member keeps `channel-group 1 mode passive` and its other trunk lines | Member suspended: SW2 `Po1(SU) Et0/0(P) Et0/1(s)` and `%ETC-5-CANNOT_BUNDLE2: Et0/1 is not compatible with Po1 and will be suspended (dtp mode of Et0/1 is off, Po1 is on)`; SW1 `Et0/1(s)` with `%ETC-5-L3DONTBNDL2: Et0/1 suspended: LACP currently not enabled on the remote port.` Po1 drops to `BW 10000 Kbit/sec` → **T2** |
| F2 | SW3 Ethernet1/0–1/1 | `channel-group 3 mode on` (SW2 stays `mode active`) | SW3 `Po3(RU) - Et1/0(P) Et1/1(P)`, up/up, routes installed; SW2 `Po3(RD) LACP Et1/0(s) Et1/1(s)`, `%ETC-5-L3DONTBNDL2: Et1/0 suspended: LACP currently not enabled on the remote port.`, Port-channel3 down/down, so the static route to 10.0.30.0/24 is not installed → PC1 cannot reach PC2 (**T1**) |

The two faults are independent: F1 fixes T2 only, F2 fixes T1 only (both shown below).

## Diagnosis / Methodology

**T1 — PC1 cannot reach PC2**

1. From PC1: gateway 10.0.10.1 answers (3/3), so the host, VLAN 10 and the SW1–SW2 path are fine. `traceroute -n 10.0.30.102` → `1 10.0.10.1`, `2 10.0.10.1 !H * !H`: the gateway itself has no route.
2. SW2 `show ip route static`: empty, although the config has `ip route 10.0.30.0 255.255.255.0 10.0.23.1`. The next hop is not resolvable. `show ip interface brief`: `Port-channel3 10.0.23.0 ... down down`.
3. SW2 `show etherchannel summary`: `3 Po3(RD) LACP Et1/0(s) Et1/1(s)`; log `%ETC-5-L3DONTBNDL2: Et1/0 suspended: LACP currently not enabled on the remote port.`
4. SW3 (the red herring): `3 Po3(RU) - Et1/0(P) Et1/1(P)`, Port-channel3 up/up, statics installed. The protocol column `-` means static `on`. `ping 10.0.23.0` fails (0/3). Comparing both ends: SW2 negotiates LACP, SW3 does not negotiate at all → F2.

**T2 — SW1–SW2 capacity dropped**

1. No member is down (no `(D)` flag), but SW2 `show etherchannel summary` shows `1 Po1(SU) LACP Et0/0(P) Et0/1(s)`, and `show interfaces Port-channel1` shows `BW 10000 Kbit/sec`, `Members in this channel: Et0/0`.
2. SW2 log: `%ETC-5-CANNOT_BUNDLE2: Et0/1 is not compatible with Po1 and will be suspended (dtp mode of Et0/1 is off, Po1 is on)`. `show running-config interface Ethernet0/1` shows `switchport mode access` → F1. SW1 shows `Et0/1(s)` and `show lacp neighbor` Et0/1 with partner `0000.0000.0000` (SW2 sends no LACPDUs on a suspended port).
3. Side effect: Po1 costs 100 instead of 56, so spanning tree now forwards SW1–SW2 traffic over Po2 (`Po1 Altn BLK 100`, `Po2 Root FWD 56` on the non-root switch), whereas LAB-004 ended with Po1 forwarding.

**Plausible causes ruled out**

| Candidate | Evidence |
|---|---|
| Host or gateway (T1) | PC1 pings SW2 Vlan10 (10.0.10.1); PC2 pings SW3 Vlan30. Both hosts and both gateways are fine |
| Static routing (T1) | Routes are configured correctly on both switches. SW3's are installed; SW2's is missing only because its next hop (Po3) is down. Fixing the link, not the routes, restores it |
| L3 bundle (T1) | SW2 `Po3(RD)` with `(s)` members vs SW3 `Po3(RU)` with protocol `-`: F2 confirmed |
| Trunk/VLAN (T1) | `show interfaces trunk` on Po1/Po2: trunking, native 999, VLANs 10,99 forwarding. PC1 reaches its gateway, so VLAN 10 is carried. For T2, the member Et0/1 is not in trunk mode: F1 |
| Spanning tree | No blocked or inconsistent port on any path PC1 uses; Po2 forwards. The changed root port is a consequence of Po1's lower bandwidth, not a cause |
| Physical/port down (T2) | The member flag is `(s)` suspended, not `(D)` down, and Po1 is `(SU)`: the link is up but refused by the bundle |

## Solution Configuration

Tested one fault at a time.

**F1 (SW2)**
```
interface Ethernet0/1
 switchport mode trunk
```
No bounce needed. Within seconds, SW2 showed `1 Po1(SU) LACP Et0/0(P) Et0/1(P)`, `BW 20000 Kbit/sec`, `Members in this channel: Et0/0 Et0/1`, and `Po1 Desg FWD 56`. Po3 was still `(RD)`, and PC1 → PC2 was still 0/3. **F1 fixes T2 only.**

**F2 (SW3)**
```
interface range Ethernet1/0 - 1
 no channel-group
 channel-group 3 mode active
```
Changing the mode directly is rejected: `Command rejected: is already part of a channel with a different type of protocol enabled` / `% Range command terminated because it failed on Ethernet1/0`. `no channel-group` keeps interface Port-channel3 and its IP address. `mode passive` on SW3 would also work, since SW2 is active, but the design says both active. **F2 fixes T1** (below).

## Verification

After both fixes:

SW2 `show etherchannel summary`
```
1      Po1(SU)         LACP        Et0/0(P)        Et0/1(P)
2      Po2(SU)         PAgP        Et0/2(P)        Et0/3(P)
3      Po3(RU)         LACP        Et1/0(P)        Et1/1(P)
```
SW2 log: `%LINK-3-UPDOWN: Interface Port-channel3, changed state to up`, then `%LINEPROTO-5-UPDOWN: Line protocol on Interface Port-channel3, changed state to up`. SW2 `show ip route static`: `S 10.0.30.0/24 [1/0] via 10.0.23.1`.

SW3: `3 Po3(RU) LACP Et1/0(P) Et1/1(P)`. `ping 10.0.10.101 source Vlan30 repeat 5` → `Packet sent with a source address of 10.0.30.1`, `!!!!!`, `Success rate is 100 percent (5/5)`.

SW1: `1 Po1(SU) LACP Et0/0(P) Et0/1(P)`, `2 Po2(SU) PAgP Et0/2(P) Et0/3(P)`; Po1 `BW 20000 Kbit/sec`; STP VLAN 10 `Po1 Root FWD 56`, `Po2 Altn BLK 56` (same as LAB-004's end state).

PC1
```
5 packets transmitted, 5 packets received, 0% packet loss
traceroute to 10.0.30.102
 1  10.0.10.1
 2  10.0.23.1
 3  10.0.30.102
```

## Failure / Recovery Behaviour

This lab has no failure test (the member-failure test belongs to LAB-004). Behaviour observed in testing:

- SW3's `on` bundle stayed `(RU)` for the whole start state (more than 3 minutes). The EtherChannel misconfiguration guard only acts on Layer 2 bundles (it watches spanning-tree BPDUs), so a routed `on` bundle is never err-disabled and stays silently broken.
- Both faults come back identically after a wipe and restart, and after a fresh import of LAB-005.yaml (same flags, same log lines).

## Answers to Analysis Questions

**Q1.** SW3 was the most misleading device (T1 cause, F2). `on` mode sends no negotiation frames and does not wait for any: as soon as its member links are up, SW3 bundles them and brings Port-channel3 up, and its connected and static routes install. Nothing tells SW3 that SW2 disagrees. SW2 runs LACP, hears no LACPDUs from SW3, and suspends its members (`L3DONTBNDL2`). SW2's Po3 is down, so SW3 sends traffic into links whose far end discards it: a black hole visible only from SW2. Because this is a routed bundle there are no BPDUs, so the misconfiguration guard never fires.

**Q2.**
- T2 (F1), on SW2: `%ETC-5-CANNOT_BUNDLE2: Et0/1 is not compatible with Po1 and will be suspended (dtp mode of Et0/1 is off, Po1 is on)`. The member's switchport mode (static access, so DTP is off) does not match the port-channel's trunk mode. SW1 logs the consequence: `%ETC-5-L3DONTBNDL2: Et0/1 suspended: LACP currently not enabled on the remote port.`
- T1 (F2), on SW2: `%ETC-5-L3DONTBNDL2: Et1/0 suspended: LACP currently not enabled on the remote port.` (and Et1/1), plus `%LINEPROTO-5-UPDOWN: Line protocol on Interface Port-channel3, changed state to down`. SW3 logs nothing unusual, only Port-channel3 coming up.

**Q3.** *F2 (T1):* the design uses LACP on both ends. Each LACP port bundles only after it receives LACPDUs from the partner with matching system ID and key, and it keeps checking them. If one side is not running LACP, or its ports go to a different device or channel, the ports are suspended or stand-alone instead of forming a one-sided bundle. The result is a visible failure on both ends (`(s)`/`(I)` flags, log messages), and the members can fall back to individual links, instead of a silent black hole. The protection works only if *both* ends negotiate: `on` on one end disables it, which is exactly F2.

*F1 (T2):* the design did not prevent F1, but it contained it. Po1's trunk definition plus LACP made SW2 suspend the incompatible member (`CANNOT_BUNDLE2`) instead of letting an access-mode port forward beside the bundle, so the mistake cost half the capacity rather than causing a trunk mismatch or a loop. Accept any answer that explains this containment, or that proposes a change standard that configures members only through the port-channel.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-14 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), ioll2-xe (IOS XE 17.16.1a) |
