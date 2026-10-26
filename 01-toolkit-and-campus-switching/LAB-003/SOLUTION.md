# LAB-003 — Solution

## Summary

First troubleshooting lab of the course (T · G3, 45 min) on the FND switch chain A topology used by LAB-002. The start state is LAB-002's end state converted back to VTP transparent (module rule 3): VLANs are defined per switch, and trunks are static with native VLAN 999 and DTP off. Two faults, typical of a hand-made rollback, are injected. They interact: VLAN 20 fails end to end until **both** are fixed, so the student must check the whole path rather than stop at the first finding.

Blueprint mapping (kept out of LAB.md, which lists domains 3 and 4 only): **3.1.a:T** (allowed-VLAN list on a trunk), **X-VTP:T** (VLAN database per switch after a VTP rollback; ruling VTP/DTP out as the cause), **4.1:P** (sourced ping as evidence, V5).

## Intentional Faults

| ID | Device | What was changed | Symptom it causes |
|---|---|---|---|
| F1 | SW2 Et0/0 (toward SW1) | `switchport trunk allowed vlan 10,99` instead of `10,20,99` (VLAN 20 lost by an `allowed vlan` edit without `add`) | VLAN 20 is not carried between SW1 and SW2. Visible only on SW2: SW1's end still shows 10,20,99 |
| F2 | SW3 | no `vlan 20` in the configuration (transparent mode), while Et1/1 is still `switchport access vlan 20` | PC4's port is in an inactive VLAN (`Access Mode VLAN: 20 (Inactive)`), and SW3 does not forward VLAN 20 on its trunk |

Interaction (tested): fixing F1 alone or F2 alone leaves PC2 → PC4 at 100% loss; fixing both restores it. Neither fault produces a log message.

## Diagnosis / Methodology

1. **Reproduce** from the user's vantage point: PC2 `ping 10.0.20.104` → 100% loss; PC1 `ping 10.0.10.103` → 0% loss. The problem is specific to VLAN 20, so the physical path, the trunks as a whole and the hosts' NICs are working (VLAN 10 uses the same links).
2. **Candidate subsystems and the evidence that confirms or eliminates each:**

| Candidate | Evidence | Verdict |
|---|---|---|
| Host addressing (PC2/PC4) | PC2 `ip -4 addr` `inet 10.0.20.102/24`, `ip route` `10.0.20.0/24 dev eth0`; PC4 is `.104/24` in the same subnet | eliminated |
| Physical links / trunk down | VLAN 10 and management work across both links (PC1 → PC3 OK; SW2 pings 10.0.99.1 and 10.0.99.3); `show interfaces trunk` shows both links `trunking` | eliminated |
| DTP / VTP (the rollback itself) | trunks are `on` + `nonegotiate` on both ends (no negotiation involved); `show vtp status` on every switch: `Transparent`, domain `VERIDIAN`. VTP cannot add or remove VLANs in transparent mode | eliminated: the rollback method is not the cause, but it is where the manual errors were made |
| STP blocking | `show spanning-tree vlan 20`: only designated/root ports in `FWD`; a loop-free chain has no alternate ports. On SW3 `Spanning tree instance(s) for vlan 20 does not exist.` (a consequence of F2, not a separate STP fault) | eliminated |
| Native VLAN mismatch | native 999 at every trunk end; no `%CDP-4-NATIVE_VLAN_MISMATCH` in any log | eliminated |
| VLAN database per switch | `show vlan brief`: SW1 and SW2 have 20 `OPS`; **SW3 has no VLAN 20** | **F2 confirmed** |
| Access-port VLAN assignment | SW3 `show interfaces e1/1 switchport`: `Access Mode VLAN: 20 (Inactive)`. Note that `show interfaces status` still prints `Et1/1 PC4 connected 20`, so it looks fine at a glance | **F2 confirmed** |
| Trunk allowed / active VLANs, both ends | SW2 `show interfaces trunk`: `Et0/0` allowed **10,99**, `Et0/1` 10,20,99. SW1 Et0/0 shows 10,20,99 (so checking only SW1 misses it). SW3 Et0/0: allowed 10,20,99 but active/forwarding 10,99 (F2 again) | **F1 confirmed** on SW2 only |

3. Fix each fault, then re-test from the hosts after each change. Because of the interaction, the first fix does not clear the ticket, which should push the student to keep going instead of assuming the fix failed.

## Solution Configuration

As tested in CML:

```
! SW2 - F1
interface Ethernet0/0
 switchport trunk allowed vlan add 20
! SW3 - F2
vlan 20
 name OPS
```

`switchport trunk allowed vlan 10,20,99` on SW2 Et0/0 is an equivalent fix. Re-enabling VTP server/client to "push" VLAN 20 violates the policy stated in LAB.md and does not fix F1.

## Verification

Captured in CML (trimmed).

**Start state (identical on a fresh import of the YAML):**

```
PC2$ ping -c 3 -W 1 10.0.20.104
3 packets transmitted, 0 packets received, 100% packet loss
PC1$ ping -c 3 -W 1 10.0.10.103
3 packets transmitted, 3 packets received, 0% packet loss
SW2# show interfaces trunk
Port           Mode             Encapsulation  Status        Native vlan
Et0/0          on               802.1q         trunking      999
Et0/1          on               802.1q         trunking      999
Port           Vlans allowed on trunk
Et0/0          10,99
Et0/1          10,20,99
Port           Vlans in spanning tree forwarding state and not pruned
Et0/0          10,99
Et0/1          10,20,99
SW2# ping 10.0.99.1 repeat 3   ->  .!!  Success rate is 66 percent (2/3)
SW2# ping 10.0.99.3 repeat 3   ->  .!!  Success rate is 66 percent (2/3)
SW3# show vlan brief
10   USERS                            active    Et1/0
99   MGMT                             active
999  NATIVE                           active
SW3# show interfaces Ethernet1/1 switchport | include Access Mode
Access Mode VLAN: 20 (Inactive)
SW3# show interfaces status | include Et1/1
Et1/1        PC4                connected    20           full   auto 10/100/1000BaseTX
SW3# show interfaces trunk
Et0/0          on               802.1q         trunking      999
Et0/0          10,20,99          (allowed)
Et0/0          10,99             (active)
Et0/0          10,99             (forwarding)
SW3# show spanning-tree vlan 20
Spanning tree instance(s) for vlan 20 does not exist.
SW1# show interfaces trunk
Et0/0          on               802.1q         trunking      999
Et0/0          10,20,99   (allowed / active / forwarding)
```

The first ping from a switch is lost to ARP resolution (`.!!`); this is normal.

**Each fix alone (causality):**

```
! F1 only (SW2 Et0/0 add 20; SW3 still without VLAN 20)
PC2$ ping -c 3 -W 1 10.0.20.104
3 packets transmitted, 0 packets received, 100% packet loss
SW2# show mac address-table vlan 20
  20    5254.006e.30d8    DYNAMIC     Et0/0
  20    aabb.cc00.4100    DYNAMIC     Et0/0
! F1 reverted, F2 only (SW3 vlan 20)
SW3# show interfaces Ethernet1/1 switchport | include Access Mode
Access Mode VLAN: 20 (OPS)
PC2$ ping -c 3 -W 1 10.0.20.104
3 packets transmitted, 0 packets received, 100% packet loss
! both
PC2$ ping -c 3 -W 1 10.0.20.104
3 packets transmitted, 3 packets received, 0% packet loss
```

**End state:**

```
SW2# show interfaces trunk
Et0/0          on               802.1q         trunking      999
Et0/1          on               802.1q         trunking      999
Et0/0          10,20,99   (allowed / active / forwarding)
Et0/1          10,20,99   (allowed / active / forwarding)
SW2# show spanning-tree vlan 20 | begin Interface
Et0/0               Root FWD 100       128.1    P2p
Et0/1               Desg FWD 100       128.2    P2p
SW1# ping 10.0.99.3 source Vlan99 repeat 5
Packet sent with a source address of 10.0.99.1
!!!!!
Success rate is 100 percent (5/5)
PC1$ ping -c 3 -W 1 10.0.10.103
3 packets transmitted, 3 packets received, 0% packet loss
```

## Failure / Recovery Behaviour

This lab has no separate failure scenario; its failure/recovery evidence is the per-fault test above. Findings:

- With only F1 fixed, PC2's frames reach SW2 over Et0/0 (PC2's MAC is learned in VLAN 20 on SW2), but SW3 has no VLAN 20 and discards them. With only F2 fixed, SW3 learns PC4 and SW2 in VLAN 20, but SW2 does not accept VLAN 20 from SW1. The symptom clears only when both are fixed.
- Neither fault produces a syslog message (no CDP, STP or DTP messages were logged during the whole build), so the log buffer does not help here. The evidence comes from comparing `show vlan brief` and `show interfaces trunk` across devices and link ends.
- Restore: stop → wipe → start of the lab brought back both faults and the symptom (PC2 → PC4 100% loss, PC1 → PC3 OK).

## Answers to Analysis Questions

**Q1.** VLAN 10 was defined on every switch and allowed on every trunk end, so its path was complete. Both faults only affect VLAN 20: F1 removes VLAN 20 from one trunk end, and F2 removes VLAN 20 from one switch's database. Trunks carry each VLAN independently, so the links, trunk state, native VLAN and STP were all healthy and VLAN 10 (and management VLAN 99) kept working over the same cables. This is why "the link works for VLAN 10" does not prove the link is fine for VLAN 20.

**Q2.** `show interfaces trunk`. For every trunk port it lists the allowed VLANs, the VLANs allowed *and* active in the local database, and the VLANs actually forwarding (STP, not pruned). The allowed list is enforced separately at each end, so it must be run on both ends. Here SW1 Et0/0 showed 10,20,99 while its peer SW2 Et0/0 showed 10,99; looking at SW1 alone would have cleared the link. The "allowed and active" row on SW3 (10,99 despite 10,20,99 allowed) also points straight at F2.

**Q3.** (Part 1, any sound rule for each cause you found is acceptable, e.g. a native-VLAN or VLAN-database change must be verified on both ends.) The `add`/`remove` rule: `switchport trunk allowed vlan <list>` **replaces** the whole list. An engineer who wanted to add or remove one VLAN and typed the command without `add`/`remove` silently drops every VLAN not in the new list, with no warning and no log message. `add`/`remove` change only the named VLAN. Yes, this is F1: SW2 Et0/0 ended up with `10,99` after an edit during the rollback. `switchport trunk allowed vlan add 20` restores it without touching the rest.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-17 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), ioll2-xe (IOS XE 17.16.1a) |
