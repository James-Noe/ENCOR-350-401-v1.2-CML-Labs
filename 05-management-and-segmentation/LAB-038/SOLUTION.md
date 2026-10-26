# LAB-038 — Solution

## Summary
(F1 is a narrowed DC line in HQ-CORE1's MGMT-HOSTS; the lost `vrf-also`, which is LAB-037's drill, is here the eliminated hypothesis.) Three independent tickets on the LAB-037 H3 management plane: the audit login (two devices, two causes), the missing syslog (two causes in series) and the unselected time source. Teaches evidence-led isolation across AAA/ACL (5.1.a, 5.1.b), VRF-aware services (2.2.a), logging (4.1) and NTP (3.3.a). Blueprint: 5.1.b:T, 5.1.a:T (the VTY ACL, F1), 4.1:T, 5.2.a:T (the VTY ACL, F1), 2.2.a:T (VRF-aware services), 3.3.a:T (NTP, F5), 3.1.a:R (VLAN 99 trunking ruled out). Earlier-module candidates (VLAN 99 trunking and STP, core routing) are ruled out by evidence (pings from DC-NMS1, other devices reachable, ACC3's alternate uplink is by design).

## Intentional Faults
| ID | Device | Change | Symptom |
|---|---|---|---|
| F1 | HQ-CORE1 | `ip access-list standard MGMT-HOSTS` line 20 `permit 10.50.50.48 0.0.0.7` (H3: `10.50.50.0 0.0.0.255`); `access-class MGMT-HOSTS in vrf-also` on the VTY lines and the SNMP group's `access MGMT-HOSTS` unchanged | line 20 covers 10.50.50.48-.55 only, so DC-NMS1 (.60) falls to `40 deny any log`: SSH from NMS1 `Connection refused` at TCP connect (no prompt, no RADIUS request); SNMPv3 from NMS1 `Timeout: No Response` (same ACL); sessions from VLAN 99 sources (line 10) accepted; HQ-PC1 refused as designed |
| F2 | HQ-DIST2 | `aaa group server radius RADGRP` without `ip vrf forwarding MGMT` | password prompt then `Connection closed`; `show aaa servers` `State: current DEAD`; only local `admin` logs in |
| F3 | HQ-CORE2 | `logging host 10.50.50.51` without `vrf MGMT` | nothing from CORE2 reaches the collector |
| F4 | HQ-CORE2 | `logging trap warnings` | with F3 fixed, no login (`%SEC_LOGIN-5`, `%SSH-5`) or config events |
| F5 | HQ-ACC3 | `ntp trusted-key 2` (key 1 is the one in use) | `10.50.50.1 configured ... authenticated (' ' reject) ... insane, invalid, unsynced, stratum 16`, `assoc in/out packets 0` |

Platform notes: `line vty 0 4` (this platform rejects `0 15`; IOL only: IOS-XE routers and switches have lines 0-15 by default, so configure `line vty 0 15` there), and F1 refuses at TCP connect instead of closing before authentication; T1 therefore says "refuses the connection". The v1.1 F1 ACL loaded as entered (no normalisation, no fallback needed).

## Diagnosis / Methodology
**T1.** NMS1 pings both management addresses and `show ip route vrf MGMT` is complete on both cores: path eliminated. Logins on the other devices work and DC-AAA1's console shows the auditors' successful logins: server and account eliminated as a common cause.
- CORE1: `show ip ssh` is enabled, version 2.0, yet NMS1 gets `Connection refused` at TCP connect, and the poller's `snmpget` to 10.10.99.2 times out although `ping vrf MGMT` works. A session from a VLAN 99 source is accepted (CORE2 `ssh -vrf MGMT -l netops 10.10.99.2`, source 10.10.99.3, reaches `Password:`): the service works, only some sources are refused. Eliminate the VTY binding (LAB-037's drill): `show running-config | section line vty` shows `access-class MGMT-HOSTS in vrf-also` as on every device, and an SNMP failure on the same device is not explained by a VTY keyword. `show access-lists MGMT-HOSTS`: the `40 deny any log` count rises with each NMS1 attempt (SSH and SNMP; a first denied packet from a new source logs at once, later hits only count, with the summary on the 5-minute timer) and `%SEC-6-IPACCESSLOGS: list MGMT-HOSTS denied 10.50.50.60 1 packet` is on CORE1's console and in DC-SYSLOG1's console log. Line 20 `10.50.50.48, wildcard bits 0.0.0.7` is .48-.55: the workstation .60 is outside it, and the other seven devices carry `10.50.50.0, wildcard bits 0.0.0.255`: F1. HQ-PC1's own refusals count on line 40 too; the source address in the log line separates them.
- DIST2: password prompt appears, then the session closes. `show aaa servers` shows `State: current DEAD` (alternates UP/DEAD with `deadtime 1`; `Authen: request 2, timeouts 2`). `ping vrf MGMT 10.50.50.52` works, but `show run | section aaa group server` lacks `ip vrf forwarding MGMT`. The local account `admin` works (fallback).

**T2.** Other devices' lines reach the collector (DC-SYSLOG1 console log, `cml-rest.sh log` or the CML console: lines from .2 .11 .12 .21 .22 .23, none from 10.10.99.3): collector eliminated. `ping vrf MGMT 10.50.50.51` works from CORE2 and SNMP works: routing eliminated. `show logging` shows `Logging to 10.50.50.51  (udp port 514` without `(MGMT)` (DIST2 shows `(MGMT)`): F3. After F3, `Trap logging: level warnings`: F4; a `send log 5` test shows the missing events.

**T3.** ACC3 is global by design and its RADIUS/syslog work, and the alternate (blocking) uplink is by design. Other switches select DC-RTR1. `show ntp associations detail` on ACC3 shows `authenticated (' ' reject)`, `insane, invalid`, `assoc in packets 0`; `show run | include ntp` shows key 1 used by the server line but `ntp trusted-key 2`: F5.

**Causality (each fault fixed alone).**
- F1 only (`no 20` / `20 permit 10.50.50.0 0.0.0.255`, no reload): NMS1 SSH to CORE1 (privilege 1) and the SNMPv3 `snmpget` work at once; HQ-PC1 still refused. Fix to first success 2 s, 1 s, 1 s (poll 2 s: effective on the next connection, no protocol timer). F2 only: DIST2 `netops` has privilege 1, `State: current UP`, and AAA1 shows `ACCT Start user=netops nas=10.10.99.12`.
- F4 only fixed (host still without VRF): the collector got nothing from CORE2. F3 only fixed: only `%SYS-3-USERLOG_ERR` (severity 3) arrived; the severity-5 test message and the SSH login events did not. Both fixed: `%SSH-5-SSH2_SESSION`, `%SEC_LOGIN-5-LOGIN_SUCCESS [user: netops] [Source: 10.50.50.60]` and the test message arrive from 10.10.99.3.
- F5 right fix: ACC3 selects DC-RTR1 (`*~10.50.50.1 ... authenticated ('*' sys.peer) ... sane, valid, stratum 3`, `assoc in packets 8, out 8`) about 20 s to 2.5 min after the fix once the master is ready (17-29 s and about 150 s in separate runs).

**Wrong fixes tried.**
- F1, each tried once on CORE1:
  1. Re-entering `access-class MGMT-HOSTS in vrf-also`: no change (NMS1 refused, SNMP timeout, line 40 keeps counting 8, 11, 14). The binding was never the cause.
  2. `no access-class MGMT-HOSTS in vrf-also` on the VTY lines: NMS1 SSH is accepted (privilege 1) but HQ-PC1 to 10.255.10.1 reaches `Password:` (V2 fails), and SNMP from NMS1 still times out (the SNMP group keeps the ACL), so T1's poller clause stays open.
  3. `30 permit host 10.50.50.60`: NMS1 SSH (privilege 1) and `snmpget` work, HQ-PC1 refused. T1 closes but CORE1 still differs from the other seven (line 20 narrower than the documented DC segment, an extra line 30): partial; the end state is line 20 restored.
- F2: `username netops privilege 1 secret opspass` on DIST2 lets the auditors in but AAA1 shows no `nas=10.10.99.12` authentication or accounting line: violates V1 (central accounts and accounting). `no username netops` prompts `[confirm]` and the CLI helper answers `n`: wipe the node to remove it.
- F5: `no ntp authenticate` was tried; ACC3 had still not selected the source after 100 s, so the outcome is inconclusive (the platform selects slowly). Not claimed to violate V2 beyond the policy text.
- `logging trap debugging` (F4) was not run: it plainly violates the documented severity.

## Solution Configuration
```
HQ-CORE1:
ip access-list standard MGMT-HOSTS
 no 20
 20 permit 10.50.50.0 0.0.0.255
HQ-DIST2:
aaa group server radius RADGRP
 ip vrf forwarding MGMT
HQ-CORE2:
no logging host 10.50.50.51
logging host 10.50.50.51 vrf MGMT
logging trap informational
HQ-ACC3:
ntp trusted-key 1
no ntp trusted-key 2
```
Check for the same mistake elsewhere: `show access-lists MGMT-HOSTS` (and the VTY and SNMP group references) on all eight devices (only CORE1 differs), `show run | section aaa group server`, `show logging | include Logging to`, `show run | include ntp trusted|ntp server` on all seven HQ devices. No other device has it.

## Verification
End state (all five fixed):
- `netops` from DC-NMS1: `Current privilege level is 1` on all seven devices (including CORE1 and DIST2). CORE1 `20 permit 10.50.50.0, wildcard bits 0.0.0.255 (3 matches)`; `snmpget` v3 from NMS1 to 10.10.99.2 returns the sysName; HQ-PC1 to 10.255.10.1: `Connection refused`.
- AAA1 console: `Auth: Login OK: [netops]`, `ACCT Start/Stop user=netops nas=10.10.99.2`; `nas=10.10.99.12` after the DIST2 fix.
- DIST2 `show aaa servers`: `State: current UP`. After F2 is fixed, local `admin` is REFUSED on DIST2 (`Connection closed`): the server answers and rejects it, there is no fallback while the server is reachable.
- CORE2 `Trap logging: level informational`, `Logging to 10.50.50.51  (MGMT) (udp port 514`; collector receives lines from all seven sources, including 10.10.99.3.
- ACC3 `*~10.50.50.1 127.127.1.1 3 ... reach 377` (ACC1/DIST1/CORE1 the same; time to select is 15-35 min after boot: 35 and 15 in two runs).
Start state (restored; identical on a fresh import): CORE1 `Connection refused`, `20 permit 10.50.50.48, wildcard bits 0.0.0.7`, `snmpget` to CORE1 `Timeout: No Response` (CORE2 answers), `show running-config | section line vty` has `vrf-also`; CORE2/DIST1/ACC1/2/3 privilege 1; DIST2 netops `Connection closed`, admin privilege 15; DIST2 `State: current DEAD`; CORE2 `Trap logging: level warnings`, no `(MGMT)`; no 10.10.99.3 lines at the collector; ACC3 `~10.50.50.1 .INIT./.TIME. 16 ... reach 0`, `ntp trusted-key 2`.

## Failure / Recovery Behaviour
Failure method: DC-AAA1 and DC-SYSLOG1 node stops are silent failures for the routers (the link stays up; only timeouts detect them). Timings below were measured in v1.1 (CML 2.10.0, 3 runs unless noted; clock = a scripted CLI poll with `show clock` or the outer wall clock).

| Scenario (trigger, end condition) | Runs (raw) | Documented range | Basis |
|---|---|---|---|
| F1 fix on CORE1 (ACL line 20 restored), end: NMS1 SSH to CORE1 succeeds | 2 s, 1 s, 1 s | at once (about 2 s) | ACL is evaluated on the next connection; no protocol timer |
| F5 fix on ACC3 (`ntp trusted-key 1`), end: `*~10.50.50.1` selected, master ready | stale association: about 4-5 min (once); fresh association: 43 s, 56 s, 62 s | 40 s to 5 min once DC-RTR1 is synchronised as NTP master; if F5 is fixed before the master is ready, ACC3 selects it only when the master is usable (about 15-16 min after boot, association `.INIT.`/`.TIME.` meanwhile) | NTP poll back-off (an association that has been failing backs off its poll interval); 17-29 s was seen in one run |
| Boot to ACC3 selecting DC-RTR1 | 15-35 min (runs: 35, 15) | allow 25 min, up to 35 | master needs about 15 min, ioll2-xe clients select later |
| DC-AAA1 node stop, end: first `admin` (local fallback) login on DIST2 (F2 fixed) | 11 s, 11 s, 10 s | 10-12 s | RADIUS dead-criteria (5 s timeout, 2 tries); a second login is immediate because the server is marked DEAD (`Dead: total time 61s`, deadtime 1 min) |
| DC-AAA1 node start, end: `netops` (privilege 1) login on DIST2 works again | 35 s, 13 s, 13 s (outer clock, includes about 10 s of session connect) | about 15-60 s | node boot 14 s plus the remainder of `deadtime 1`; upper bound 60 s (derived) |
| F2 fix on DIST2 (server group in MGMT), end: `netops` login | first poll (server had been DEAD 60 s); server UP 290 s later | at once to about 5 min | the group works on the next request; `show aaa servers` returns to UP after the deadtime |
| DC-SYSLOG1 node stop, `send log 5` on CORE2, node start | node up 14 s after start; the message sent while stopped was lost; the next one arrived | one run | UDP, no replay |

After F2 is fixed with the server UP, `admin` (a local account) is refused on DIST2: the server answers and rejects it, so there is no fallback while the server is reachable.

## Answers to Analysis Questions
Q1. T1/CORE1: refused at TCP connect while the path and other logins work and VLAN 99 sources are accepted (path, account and service eliminated); the VTY `vrf-also` is present and SNMP from the same station fails too, so the binding is eliminated, and the rising deny counter points at the ACL's content; T1/DIST2: password prompt then refusal with DEAD server and a working VRF ping (server reachable by routing, so the group lacks the VRF); T2: SNMP works and the other devices log (collector and routing fine); T3: other devices select the source and ACC3's RADIUS/syslog work (path fine; authentication state `reject`).
Q2. Compare the same stanza on every device: `section aaa group server`, `logging host` lines with `(MGMT)`, `ntp trusted-key`/`ntp server key`. Cover every service that needs the VRF (RADIUS, syslog, NTP, SNMP, SSH access-class) on all seven HQ devices and DC-RTR1.
Q3. DC-AAA1's console shows whether requests arrived and the result (`Login OK`, `ACCT Start nas=...`), and the collector shows what really arrived; a device only shows what it sent or timed out.
Q4. Pings in `vrf MGMT`, SNMP to CORE2 and local `admin` on DIST2 worked: the routing and the fallback were fine; only the services' own VRF binding was wrong.
Q5. After any change: SSH as `netops` and `admin` to every device from DC-NMS1, from HQ-PC1 expect refusal, `show aaa servers` state, a `send log 5` test seen at the collector, `show ntp associations` with `*` and `authenticated`.
Instructor debrief: the auditors' CORE1 sessions match line 40 (`deny any log`): line 20 as written covers 10.50.50.48-.55 (DC-SYSLOG1 .51, DC-AAA1 .52), not NMS1 at .60. The poller failed through the same change because the SNMP group `access MGMT-HOSTS` uses the same ACL. Checking `vrf-also` (LAB-037's case) does not explain the ticket: it is present, SNMP also fails, and the counter moves (without `vrf-also` the counter stays still). Wrong fix 2 above shows the VTY binding alone never covered the SNMP half. SNMP works on CORE2 because replies leave in the VRF the request arrived in, while syslog is initiated by the device and uses the global table unless told otherwise. DIST2 accepted `admin` because with the server marked dead the method list fell back to local. A trusted-key mismatch is harder to spot than a wrong key string because the key is present and the client simply never sends (no packets in/out). 

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-16 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), iol-xe (IOS XE 17.16.1a), ioll2-xe (IOS XE 17.16.1a), net-tools, radius, syslog, unmanaged_switch |
