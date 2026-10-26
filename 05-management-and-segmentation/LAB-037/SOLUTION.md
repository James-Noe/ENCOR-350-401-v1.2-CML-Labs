# LAB-037 — Solution

## Summary
Integration lab: students extend the LAB-033/034/035 hardening from branch scale to the HQ campus and carry it in a management VRF (LAB-031). Blueprint: 2.2.a (VRF, per-VRF OSPF, VRF-aware services), 5.1.a/5.1.b (AAA, access control), 5.2.a (access-class, IPv6 VTY ACL), 4.1 (syslog, SNMPv3, NTP), 3.3.a (time). The end state is exactly `environments/HQ/H3/` (the solved configs; this lab's YAML is the pre-staged start). The AI proposal is correct by design: the exercise is testing it, not fixing it.

## Intentional Faults
None (X lab). Platform findings the students will meet, all recorded as expected:

| ID | Where | Behaviour | Teaching point |
|---|---|---|---|
| P1 | all IOL | `line vty 0 15` is rejected (`% Invalid input` at `15`); only `vty 0 4` exist | the proposal's literal text does not apply; "every VTY line" means 0 4 here (IOL only: IOS-XE routers and switches have lines 0-15 by default, so configure `line vty 0 15` there) |
| P2 | all IOL | line `30 permit host 10.50.50.60` typed after line 20 is refused: `% Access rule can't be configured at higher sequence num as it is part of the existing rule at sequence num 20` | line 30 is redundant (covered by 20): style note, not a defect |
| P3 | DIST SVI | `vrf forwarding` on Vlan99 removes its address: `% Interface Vlan99 IPv4 disabled and address(es) removed` | Q5: re-add the address; the SSH session dies |

## Diagnosis / Methodology
1. Read ACC1 as the reference (`show running-config | section aaa|line vty`, `show aaa servers`, `show ip sla`): it marks the server dead (`%RADIUS-4-RADIUS_DEAD`, logged at the first central login attempt; at boot `show aaa servers` still says UP) because 10.50.50.52 has no route in the global table.
2. Routing plan: management table `MGMT` on CORE1, CORE2, DC-RTR1 and the DIST Vlan99 interfaces; per-VRF OSPF 99 on dot1q-99 subinterfaces next to the global OSPF 1 on the same physical links; VLAN 99 gateway moves from DIST HSRP to CORE VRRPv3 group 99 on VRF subinterfaces of the straight trunks (allowed lists get VLAN 99).
3. Order the cut-over so the interruption is one convergence: pre-stage everything shut down, then in one block move both DIST SVIs and `no shutdown` the core subinterfaces.
4. Services: RADIUS group and logging/NTP bound to the VRF; SNMP needs nothing (replies follow the request's VRF); `vrf-also` on the VTY `access-class`.
5. Test the ACL from DC-NMS1 (permit), HQ-PC1 IPv4 and IPv6 (deny, counters, `%SEC-6-IPACCESSLOGS`), and without `vrf-also` on one core (sessions refused before the ACL is evaluated: counters do not move).

## Solution Configuration
Tested as the scripts below (the final state per device is in `environments/HQ/H3/`; the `description` lines there are cosmetic, and `standby version 2` on the live DISTs is inherited from H2).

Step 1, DC link and management table (CORE1, CORE2; DC-RTR1 is pre-configured):
```
! HQ-CORE1                                  ! HQ-CORE2: Ethernet0/0.99 uses 10.10.254.3/31, router-id 10.10.254.3, plus:
vrf definition MGMT                         interface Ethernet1/0
 address-family ipv4                         ip address 10.10.255.128 255.255.255.254
 exit-address-family                         ip ospf network point-to-point
interface Ethernet0/0.99                     ip ospf cost 10
 encapsulation dot1q 99                      ip ospf hello-interval 1
 vrf forwarding MGMT                         ip ospf dead-interval 4
 ip address 10.10.254.2 255.255.255.254      ip ospf 1 area 50
 ip ospf network point-to-point              no shutdown
 ip ospf cost 10                            interface Ethernet1/0.99
 ip ospf hello-interval 1                    encapsulation dot1q 99
 ip ospf dead-interval 4                     vrf forwarding MGMT
 ip ospf 99 area 0                           ip address 10.10.254.0 255.255.255.254
router ospf 99 vrf MGMT                      (same p2p/cost/timers, ip ospf 99 area 0)
 router-id 10.10.254.2                      router ospf 1
 passive-interface default                   no passive-interface Ethernet1/0
 no passive-interface Ethernet0/0.99        router ospf 99 vrf MGMT (router-id 10.10.254.3, also
                                              no passive-interface Ethernet1/0.99)
```
Step 2, pre-stage VLAN 99 (DIST1 e1/0, DIST2 e1/1 `switchport trunk allowed vlan add 99`; `vrf definition MGMT` on both):
```
HQ-CORE1: interface Ethernet0/1.99 / encapsulation dot1q 99 / vrf forwarding MGMT / ip address 10.10.99.2 255.255.255.0 /
  ip ospf 99 area 0 / vrrp 99 address-family ipv4 / address 10.10.99.1 primary / priority 110 / preempt delay minimum 30 / exit-vrrp / shutdown
HQ-CORE2: same on Ethernet0/2.99 with 10.10.99.3, no priority line, shutdown
```
Step 3, cut-over in one block (DIST2 identical with .12):
```
HQ-DIST1: interface Vlan99 / no standby 99 / no ip ospf 1 area 10 / vrf forwarding MGMT / ip address 10.10.99.11 255.255.255.0 / no shutdown
          ip route vrf MGMT 0.0.0.0 0.0.0.0 10.10.99.1
HQ-CORE1: interface Ethernet0/1.99 / no shutdown        HQ-CORE2: interface Ethernet0/2.99 / no shutdown
```
Step 4, access standard (CORE1 shown; CORE2 uses Ethernet0/2.99 as source interface; DIST1/2 use Vlan99 and `snmp-server group NMSGROUP v3 auth`, no `priv` on the user):
```
aaa new-model
aaa authentication login CON none
aaa authentication enable default enable none
radius server DC-AAA1
 address ipv4 10.50.50.52 auth-port 1812 acct-port 1813
 key RADKEY123
aaa group server radius RADGRP
 server name DC-AAA1
 ip vrf forwarding MGMT
 ip radius source-interface Ethernet0/1.99
radius-server dead-criteria time 5 tries 2
radius-server deadtime 1
aaa authentication login VTY group RADGRP local
aaa authorization exec VTY group RADGRP local
aaa accounting exec VTY start-stop group RADGRP
logging host 10.50.50.51 vrf MGMT
logging trap informational
logging source-interface Ethernet0/1.99 vrf MGMT
snmp-server group NMSGROUP v3 priv
snmp-server user nmsuser NMSGROUP v3 auth sha AUTHPASS123 priv aes 128 PRIVPASS123
ntp authentication-key 1 hmac-sha2-256 NTPKEY123
ntp authenticate
ntp trusted-key 1
ntp server vrf MGMT 10.50.50.1 key 1
line con 0
 login authentication CON
line vty 0 4
 login authentication VTY
 authorization exec VTY
 accounting exec VTY
 exec-timeout 10 0
 transport input ssh
```
Step 5, approved ACL on all eight devices (HQ-CORE1/2, DIST1/2, ACC1/2/3, DC-RTR1). Approved as an amendment (line 30 redundant, refused by the platform; `vty 0 4` instead of `0 15`):
```
ip access-list standard MGMT-HOSTS
 10 permit 10.10.99.0 0.0.0.255
 20 permit 10.50.50.0 0.0.0.255
 40 deny any log
ipv6 access-list NO-VTY6
 deny ipv6 any any log
line vty 0 4
 access-class MGMT-HOSTS in vrf-also
 ipv6 access-class NO-VTY6 in
snmp-server group NMSGROUP v3 priv access MGMT-HOSTS     ! routers; "v3 auth access MGMT-HOSTS" on switches
```
Student's own test of the amendment case: remove `vrf-also` on one core, retest, restore.

## Verification
Captured in CML; the start state was re-verified on a fresh import of the YAML.
- CORE2 `show ip ospf neighbor`: FULL on Ethernet1/0 (10.255.50.1, global area 50) and Ethernet1/0.99 (10.50.50.1, via `ospf 99`); MGMT table `O 10.50.50.0/24 [110/20] via 10.10.254.1, Ethernet1/0.99`.
- VRRP: CORE1 `Et0/1.99 grp 99 MASTER 10.10.99.2(local)`, CORE2 `Et0/2.99 BACKUP`.
- Cut-over (R2): IP SLA icmp-echo 10.10.99.1 on ACC1, freq 1 s, timeout 500 ms: failures 0 to 13 (about 13 s), then successes continue. Limit 30 s: met.
- V1: DC-NMS1 SSH `netadmin` `Current privilege level is 15`, `netops` `is 1` on 10.50.50.1, 10.10.99.2/.3/.11/.12/.21.
- V2: DC-SYSLOG1 console `10.10.99.12 %SEC_LOGIN-5-LOGIN_SUCCESS: Login Success [user: netadmin] [Source: 10.50.50.60]` (also .2/.3/.11/.21, 10.50.50.1); DC-AAA1 log `ACCT Start user=netadmin nas=10.10.99.21`, `ACCT Stop ...`.
- V3: `snmpget -v3 -l authPriv ... 1.3.6.1.2.1.1.5.0` returns DC-RTR1, HQ-CORE1, HQ-CORE2; `-l authNoPriv` returns HQ-DIST1/2, HQ-ACC1/2/3. No extra VRF command needed (ioll2-xe has no SNMPv3 priv, hence auth on switches).
- V4 (about 25 min after start): DC-RTR1 `Clock is synchronized, stratum 3, reference is 127.127.1.1`; all seven HQ devices `*~10.50.50.1 127.127.1.1 3 ... reach 377`.
- V5 from HQ-PC1: ssh to 10.10.10.2, 10.255.10.1, 10.10.10.1, 2001:db8:10:10::2 `Connection refused`; 10.10.99.21 `Host is unreachable`; ping 10.50.50.1/.60 and 10.10.99.1/.21 100% loss. Counters: DIST1 `20 permit 10.50.50.0 (2 matches)`, `40 deny any log (2 matches)`, `deny ipv6 any any log (1 match)`; CORE1 log `%SEC-6-IPACCESSLOGS: list MGMT-HOSTS denied 10.10.10.101 1 packet`.
- Without `vrf-also` (CORE1, DIST1): NMS1 ssh `Connection refused` on 10.10.99.2/.11 while CORE2 (still `vrf-also`) accepts; ACL counters unchanged (`20 ... (4 matches)`, `40 ... (1 match)`); restored, both accept.

## Failure / Recovery Behaviour
- DC-AAA1 node stop: `admin`/`Cisco123!` gets privilege 15 on 10.10.99.2, .12, .21 and 10.50.50.1; `netadmin` to 10.10.99.21 `Connection closed by 10.10.99.21 port 22`. CORE1 `State: current DEAD`, `%RADIUS-4-RADIUS_DEAD ... 10.50.50.52`, `%RADIUS-3-ALLDEADSERVER: Group RADGRP`. After node start (about 1 min, `deadtime 1`): `netadmin` priv 15 again, no device restart.
- HQ-CORE1 node stop (after `write memory`; silent failure for neighbours): ACC1 SLA failures 13 to 16 (about 3 s gap), CORE2 `Et0/2.99 grp 99 MASTER`, OSPF to DC-RTR1 stays FULL, SSH from NMS1 to 10.10.99.12/.21 priv 15, HQ-PC1 ping 10.10.10.1 and 10.255.50.1 0% loss. After start: configuration survived, CORE1 preempts back (delay 30 s), all adjacencies FULL.

## Answers to Analysis Questions
1. Q1. The switches were already configured (RADIUS 10.50.50.52, source VLAN 99). Their only problem was the missing route: the MGMT table now holds 10.50.50.0/24 (OSPF 99 from DC-RTR1) and the cores hold the VLAN 99 gateway, so requests and replies flow with no switch change; `show aaa servers` goes from DEAD to UP.
2. Q2. RADIUS (`ip vrf forwarding` in the server group plus `ip radius source-interface`), syslog (`logging host ... vrf`, `logging source-interface ... vrf`), NTP (`ntp server vrf`) and the VTY `vrf-also` needed the keyword. SNMP agent replies leave via the VRF the request arrived in, so nothing was needed; syslog, RADIUS and NTP are device-initiated and must be told which table to use.
3. Q3. If CORE2 stops, the DC link and DC-RTR1's MGMT adjacency are gone: logging, AAA (break-glass only), SNMP and NTP stop for every device; the gateway itself survives on CORE1. A second DC link (CORE1 to DC-RTR1, a reserved /31 exists) or a second DC router removes it.
4. Q4. Amend: apply the proposal as written except `line vty 0 4` instead of `0 15` (platform); line 30 is redundant and the platform refuses it; everything else approved. Evidence: permit from DC-NMS1 and VLAN 99, deny from HQ-PC1 in IPv4/IPv6 with log counters, `vrf-also` required (refused without it, counters unmoved). Line 30 is redundant (covered by line 20; the platform even refuses to add it). Line 40 is not redundant: the implicit deny does not log, and the explicit line adds the log entries the audit wants.
5. Q5. `vrf forwarding` on an SVI deletes its IPv4 address, and the SVI leaves the global table the session rides, so the SSH session to it dies. Avoid lock-out by working from the console (or a session through another path), pre-staging the core subinterfaces shut, re-adding the address in the same config block and bringing the cores up straight after (13 s measured).

Available Information note (reference standard vs the LAB-032 policy). Model answer for the change log: the H3 reference differs from 032 in three points: (1) RSA 2048 where 032 enforced 3072; (2) `exec-timeout 10 0` where 032 set 5 minutes; (3) no `login block-for` / `login on-failure log`, where 032 set block-for 60/3/30. A good audit flags all three and gives a verdict with a reason. Accept: at HQ the VTY ACL (MGMT-HOSTS) already limits who can try a login to VLAN 99 and the DC segment, and central AAA records every failure at the server; `login block-for` without `login quiet-mode access-class` lets one burst of failed logins (an auditor's script, a misconfigured client) lock the management station out of every device (032 Q5). Close: block-for with `login quiet-mode access-class MGMT-HOSTS`, a 5-minute timeout and a 3072-bit key rotation announced as in 032 Q2. Either verdict passes if the reason is given; the weak answer is not noticing the differences. The course keeps the H3 standard as built; the three differences are part of the standard, not faults.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-15 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), iol-xe (IOS XE 17.16.1a), ioll2-xe (IOS XE 17.16.1a), net-tools, radius, syslog, unmanaged_switch |
