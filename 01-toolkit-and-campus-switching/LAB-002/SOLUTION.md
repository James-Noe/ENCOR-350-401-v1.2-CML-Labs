# LAB-002 — Solution

## Summary

Foundation lab (F · G3, 75 min) on the FND switch chain A topology (SW1–SW2–SW3 `ioll2-xe`, PC1–PC4 Alpine). The student first observes the DTP mode matrix on one link, then replaces negotiation with static 802.1Q trunks (native 999, allowed 10,20,99, `nonegotiate`), and finally pilots VTP version 3 with SW1 as primary server so that VLAN 20, missing on SW2/SW3, arrives by VTP. It closes with the reasons Veridian ships switches in VTP transparent mode (module rule 3).

Blueprint mapping: **3.1.a:I** (trunks, DTP, allowed/native VLAN), **X-VTP:I** (VTP v3 domain, primary server, clients, revision). 4.1 toolkit recurrence (module rule 11): V6 asks for a log message and a sourced ping.

No intentional faults (F lab). The start state lacks VLAN 20 on SW2/SW3 and has no trunks by design, so that R3 has a visible effect.

## Diagnosis / Methodology

Not a troubleshooting lab. The evidence path the student should follow:

1. `show interfaces trunk` (empty everywhere) and `show dtp interface Et0/0` (`ACCESS/AUTO/ACCESS`, `S2:ACCESS`) explain why PC1 cannot reach PC3 at the start.
2. For the DTP matrix, read `TOS/TAS/TNS` (operational status / administrative status / neighbour status) and `FSM state` in `show dtp interface`, and `Operational Mode` in `show interfaces <intf> switchport`, on **both** ends after bouncing **both** ends.
3. For VTP, compare `show vtp status` (mode, revision, primary ID, MD5 digest) across the three switches, then `show vlan brief`.

## Solution Configuration

As tested in CML. R1 is exploratory: each row is `interface Ethernet0/0` / `switchport mode <mode>` (plus `switchport nonegotiate` for rows 8–9) on SW1 and SW2, followed by `shutdown` / `no shutdown` on both ends. Before the matrix:

```
! SW1 and SW2
interface Ethernet0/0
 switchport trunk encapsulation dot1q
```

Row 10 (domain mismatch), with both ends `dynamic desirable`:

```
! SW1 (config)              ! SW2 (config)
vtp domain VERIDIAN         vtp domain BENCH
! bounce Et0/0 on both; then on SW2:
vtp domain VERIDIAN
```

R2 — static trunks:

```
! SW1
interface Ethernet0/0
 switchport trunk encapsulation dot1q
 switchport trunk native vlan 999
 switchport trunk allowed vlan 10,20,99
 switchport mode trunk
 switchport nonegotiate
! SW2
interface range Ethernet0/0 - 1
 switchport trunk encapsulation dot1q
 switchport trunk native vlan 999
 switchport trunk allowed vlan 10,20,99
 switchport mode trunk
 switchport nonegotiate
! SW3
interface Ethernet0/0
 switchport trunk encapsulation dot1q
 switchport trunk native vlan 999
 switchport trunk allowed vlan 10,20,99
 switchport mode trunk
 switchport nonegotiate
```

R3 — VTP version 3:

```
! SW1 (config)
vtp domain VERIDIAN
vtp version 3
vtp mode server
! SW1 (exec) - no [confirm] prompt with "force"
vtp primary vlan force
! SW2 and SW3 (config)
vtp domain VERIDIAN
vtp version 3
vtp mode client
```

R4 needs no further configuration.

## Verification

All output below was captured in CML (trimmed).

**Start state** (identical on a fresh import of the YAML):

```
SW3# show vlan brief
1    default    active    Et0/0, Et0/1, Et0/2, Et0/3, Et1/2, Et1/3
10   USERS      active    Et1/0
99   MGMT       active
999  NATIVE     active
SW3# show interfaces Ethernet1/1 switchport | include Access Mode
Access Mode VLAN: 20 (Inactive)
SW3# show vtp status
VTP version running             : 1
VTP Domain Name                 :
VTP Operating Mode                : Transparent
Configuration Revision            : 0
SW3# show dtp interface Ethernet0/0
  TOS/TAS/TNS:                              ACCESS/AUTO/ACCESS
  TOT/TAT/TNT:                              NATIVE/NEGOTIATE/NATIVE
  FSM state:                                S2:ACCESS
PC1$ ping -c 3 -W 1 10.0.10.103
3 packets transmitted, 0 packets received, 100% packet loss
PC2$ ping -c 3 -W 1 10.0.20.104
3 packets transmitted, 0 packets received, 100% packet loss
```

IOS did not auto-create VLAN 20 for the access port in transparent mode, so the port stays inactive.

**R1 — DTP matrix** (dot1q on both ends; each row read after bouncing both ends unless noted):

| # | SW1 | SW2 | Observed (`show dtp interface` TOS/TAS/TNS, FSM) | Trunk? |
|---|---|---|---|---|
| 1 | auto | auto | SW2 `ACCESS/AUTO/ACCESS`, `S2:ACCESS`; SW1 same | no |
| 2 | desirable | auto | SW2 `TRUNK/AUTO/TRUNK`, `S6:TRUNK`, `Operational Mode: trunk` | yes |
| 3 | desirable | desirable | SW1 `TRUNK/DESIRABLE/TRUNK`, `Operational Mode: trunk` | yes |
| 4 | trunk | auto | SW1 `TRUNK/ON/TRUNK`, `S6:TRUNK` | yes |
| 5 | trunk | desirable | SW2 `TRUNK/DESIRABLE/TRUNK`, `Operational Mode: trunk` | yes |
| 6 | access | auto | SW2 `ACCESS/AUTO/ACCESS`, `Operational Mode: static access` | no |
| 7 | access | desirable | SW1 `ACCESS/OFF/ACCESS`, `S1:OFF`, static access | no |
| 8 | trunk + nonegotiate | auto | SW2 `ACCESS/AUTO/ACCESS`, `S2:ACCESS`, static access; SW2 log `%SPANTREE-7-RECV_1Q_NON_TRUNK: Received 802.1Q BPDU on non trunk Ethernet0/0 VLAN1.` + `%SPANTREE-7-BLOCK_PORT_TYPE: Blocking Ethernet0/0 on VLAN0001. Inconsistent port type.` | one-sided (SW1 trunks) |
| 9 | trunk + nonegotiate | desirable | SW1 `TRUNK/NONEGOTIATE/TRUNK`, `Et0/0 on 802.1q trunking 1`; SW2 `ACCESS/DESIRABLE/ACCESS`, `S2:ACCESS`, same SPANTREE-7 pair logged | one-sided |
| 10 | desirable, domain VERIDIAN | desirable, domain BENCH | both `%DTP-5-DOMAINMISMATCH: Unable to perform trunk negotiation on port Et0/0 because of VTP domain mismatch.`; SW2 `ACCESS/DESIRABLE/ACCESS` (`1 domain mismatches`); SW1, after its own bounce, `ACCESS/DESIRABLE/ACCESS`, trunk table empty | no |

Platform observations:
- Without the bounce on both ends, the side that was not bounced keeps its previous state. In row 10 SW1 stayed `TRUNK/DESIRABLE/TRUNK` with `3 domain mismatches` until SW1 Et0/0 was bounced too, because an IOL `shutdown` does not take the peer's port down.
- With SW2's domain still NULL (only SW1 named `VERIDIAN`), desirable/desirable trunked normally (`0 domain mismatches`).
- With the encapsulation left at `negotiate` on **both** ends (the start state), desirable/auto **did** form a trunk, as **ISL**: SW2 `TRUNK/AUTO/TRUNK`, `TOT/TAT/TNT: ISL/NEGOTIATE/ISL`, `S6:TRUNK`. With SW2 set to dot1q and SW1 still `negotiate`, SW1 showed `Et0/0 desirable n-802.1q trunking 1`. This is why LAB.md tells students to set dot1q first.

**R2/R3 — end state:**

```
SW1# show vtp status
VTP version running             : 3
VTP Domain Name                 : VERIDIAN
VTP Operating Mode                : Primary Server
Configuration Revision            : 1
Primary ID                        : aabb.cc80.2c00
Primary Description               : SW1
MD5 digest                        : 0xC2 0xA4 0x96 0x0B 0xFC 0x91 0x37 0x53 ...
SW1# show logging | include VTP_PRIMARY
%SW_VLAN-4-VTP_PRIMARY_SERVER_CHG: aabb.cc80.2c00 has become the primary server for the VLAN VTP feature
SW1# show interfaces trunk
Port           Mode             Encapsulation  Status        Native vlan
Et0/0          on               802.1q         trunking      999
Port           Vlans allowed on trunk
Et0/0          10,20,99
Port           Vlans allowed and active in management domain
Et0/0          10,20,99
Port           Vlans in spanning tree forwarding state and not pruned
Et0/0          10,20,99

SW2# show vtp status
VTP version running             : 3
VTP Domain Name                 : VERIDIAN
VTP Operating Mode                : Client
Configuration Revision            : 1
Primary ID                        : aabb.cc80.2c00
Primary Description               : SW1
MD5 digest                        : 0xC2 0xA4 0x96 0x0B 0xFC 0x91 0x37 0x53 ...
SW2# show vlan brief
10   USERS                            active
20   OPS                              active
99   MGMT                             active
999  NATIVE                           active
SW2# show running-config | section ^vlan|^vtp
vlan internal allocation policy ascending
SW2# show interfaces trunk
Et0/0          on               802.1q         trunking      999
Et0/1          on               802.1q         trunking      999

SW3# show vtp status | include Mode|Revision|Primary
VTP Operating Mode                : Client
Configuration Revision            : 1
Primary ID                        : aabb.cc80.2c00
SW3# show interfaces Ethernet1/1 switchport | include Access Mode
Access Mode VLAN: 20 (OPS)
SW3(config)# vlan 50
VTP VLAN configuration not allowed when device is in CLIENT mode.
SW3# ping 10.0.99.1 source Vlan99 repeat 5
Packet sent with a source address of 10.0.99.3
.!!!!
Success rate is 80 percent (4/5)
```

`vtp primary vlan force` returned `This system is becoming primary server for feature vlan` with **no `[confirm]` prompt**, so VTP v3 primary election needs no confirmation on this image and no v2 fallback was needed. A transparent switch changed to client (revision 0) adopted the primary's database, VLAN 20 included. VTP kept working over trunks whose allowed list excludes VLAN 1.

**R4:**

```
PC1$ ping -c 3 -W 1 10.0.10.103
3 packets transmitted, 3 packets received, 0% packet loss
PC2$ ping -c 3 -W 1 10.0.20.104
3 packets transmitted, 3 packets received, 0% packet loss
```

(Alpine reports `ttl=42` on replies; this is cosmetic, see the L2-PROG report.)

Note: while R2 is applied one switch at a time, the end already set to native 999 logs a short burst of `%CDP-4-NATIVE_VLAN_MISMATCH` messages until the other end matches (seen in one run: 5 messages on SW2 over ~7 s, 1 on SW1). This is expected and stops once both ends carry native 999.

## Failure / Recovery Behaviour

**Test:** one trunk end set back to access: SW3 Et0/0 `switchport mode access`, while SW2 Et0/1 stays a static trunk.

- PC2 → PC4: `3 packets transmitted, 0 packets received, 100% packet loss` (VLAN 10 is cut the same way).
- SW3: `show interfaces trunk` is empty; `Operational Mode: static access`, `Access Mode VLAN: 1 (default)`. VLAN 20 stays in SW3's database (`20 OPS active Et1/1`), but SW3 is now the root of an isolated VLAN 20 (`This bridge is the root`, only Et1/1 in the VLAN).
- Logs: `%CDP-4-NATIVE_VLAN_MISMATCH: Native VLAN mismatch discovered on Ethernet0/0 (1), with SW2.veridian.example Ethernet0/1 (999).` on SW3, and the mirror message on SW2. SW2 Et0/1 still shows `on 802.1q trunking 999`.
- The `%SPANTREE-7-RECV_1Q_NON_TRUNK` / `BLOCK_PORT_TYPE ... Inconsistent port type` pair you might expect was **not** logged in this test, where the trunk has native 999 and VLAN 1 is not allowed. It **was** logged during the DTP matrix (rows 8–9 and one intermediate step), where a trunk with native VLAN 1 faced an access port. Use the matrix rows to show it.
- **Recovery:** SW3 Et0/0 `switchport mode trunk` → PC2 → PC4 `3 packets received, 0% packet loss`.

**Restore:** stop → wipe → start the lab returned every switch to VTP v1 transparent, no domain, revision 0, no trunks, VLAN 20 only on SW1, and both host pairs failing.

## Answers to Analysis Questions

**Q1.** Observed on this platform, with dot1q on both ends: a trunk forms when at least one end actively asks for it (`desirable` or `trunk`) and the other end is willing (`auto`, `desirable` or `trunk`): rows 2, 3, 4 and 5. No trunk forms with `auto`/`auto` (row 1: neither side asks), with `access` on either end (rows 6 and 7), or when a `trunk` + `nonegotiate` end faces a dynamic port (rows 8 and 9): the dynamic end never receives a DTP frame, so it stays access while the other end trunks. The result is a one-sided trunk, which the access side reports as `%SPANTREE-7-RECV_1Q_NON_TRUNK` / `BLOCK_PORT_TYPE ... Inconsistent port type`. At an administrative boundary you never want the other party to decide whether your port becomes a trunk: a device that sends DTP (or a desirable/auto port on your side) could otherwise gain access to every VLAN (VLAN hopping by switch spoofing). `switchport mode access` for host/server ports, or `switchport mode trunk` + `switchport nonegotiate` for a trunk, makes the port's role fixed and stops DTP frames leaving it.

**Q2.** DTP frames carry the sender's VTP domain name. When both switches have a domain name and the names differ, DTP refuses to negotiate: row 10 logged `%DTP-5-DOMAINMISMATCH: Unable to perform trunk negotiation on port Et0/0 because of VTP domain mismatch.` and both ends stayed `ACCESS/DESIRABLE/ACCESS` (`S2:ACCESS`) even though both were `desirable`. A switch with no domain name (NULL) does not trigger the check; the trunk stayed up while SW2's domain was empty. So a VTP change (renaming a domain, adding a switch from another domain) can silently stop dynamic trunks from forming after the next link flap. Static trunks (`mode trunk`) are not affected, which is one more reason for R2. On this platform the behaviour is demonstrable, not only theory.

**Q3.** In VTP v1/v2, any server or client with the same domain name (and password, if one is set) and a higher configuration revision is believed by every other switch: its VLAN database overwrites theirs. A bench switch with only a few VLANs and a higher revision would delete the production VLANs everywhere, and access ports in those VLANs would go inactive (the "VTP bomb"). In VTP v3, only the **primary server** can change the VLAN database for the domain. Ordinary servers are secondary servers and cannot originate changes, and clients accept updates only from the primary whose ID they know (`Primary ID : aabb.cc80.2c00`). Becoming primary is an explicit, logged action (`vtp primary vlan [force]`, `%SW_VLAN-4-VTP_PRIMARY_SERVER_CHG`), not a side effect of plugging a switch in. A new switch also arrives as a secondary server or client by default, so its revision number alone can no longer overwrite the domain. Client mode also refuses local VLAN changes (`VTP VLAN configuration not allowed when device is in CLIENT mode.`).

**Q4.** (1) Blast radius: with VTP transparent, a VLAN mistake on one switch stays on that switch, and there is no domain-wide revision to overwrite. (2) Backup and restore: in transparent (or off) mode the VLANs are `vlan` lines in the running/startup configuration, so a configuration backup, a config-management tool or a CML export contains them. In server/client mode they live only in `vlan.dat` and disappear from the configuration (seen on SW2 after R3: only `vlan internal allocation policy ascending` remained). A switch restored from its config file, or a wiped CML node, would come back without its VLANs. Also acceptable: VLANs are pruned per switch by explicit allowed lists anyway, so VTP adds little in a small campus.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-14 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), ioll2-xe (IOS XE 17.16.1a) |
