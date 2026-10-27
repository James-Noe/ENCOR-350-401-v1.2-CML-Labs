# LAB-001 — Solution

## Summary

The course's opening lab teaches the method before the technology: gather evidence with ping, traceroute, the log buffer and a filtered debug, then change one thing at a time. The student measures a path MTU and locates the limiting hop (R2 Ethernet0/1, `ip mtu 1400`), explains a loopback-sourced traceroute, limits a debug to one host before enabling it, reads link-state log messages by severity, secures R3 with SSH v2 and local login, and predicts NTP behaviour from configuration alone (R2 stratum 4; R3 never synchronises because it has no `ntp trusted-key`).

Blueprint mapping: **4.1** (ping/extended ping, traceroute, debug and conditional debug, syslog/log buffer) — Introduced; **5.1.a** (lines, local users, SSH) — Introduced; **3.3.a** (interpret NTP configuration) — Introduced. CCNA reinforcement: static routing, show commands.

The R2 MTU and the R3 NTP condition are observations, not faults (F/A lab).

## Intentional Faults

None (F/A lab). Designed observations, all in the day-0 configs:

| ID | Device | Condition | What the student observes |
|---|---|---|---|
| O1 | R2 | `ip mtu 1400` on Ethernet0/1 (rest of the path 1500) | DF-set packets > 1400 bytes fail with `M` (fragmentation needed) |
| O2 | R3 | `ntp authenticate` + key 1 + `ntp server 10.255.0.2 key 1`, but **no** `ntp trusted-key 1` | R3 never selects a time source (`authenticated (' ' reject)`, reach 0) |
| O3 | R3 | no `ip domain name`, no RSA keys, VTY `login` with no password, `transport input telnet ssh` | Telnet: `Password required, but none set`; SSH: `% Connection refused by remote host` |

## Diagnosis / Methodology

**R1 — path MTU.** Busybox `ping` on Alpine has no DF option (`ping: unrecognized option: M`), so the sweep runs on R1 sourced from Ethernet0/0 (10.0.1.1), which follows PC1's path. Interactive extended ping answers: target `10.0.3.102`, extended commands `y`, source `Ethernet0/0`, DF bit `y`, sweep `y`, min `1390`, max `1410`, interval `1` (the dialog prompts are standard IOS; the outputs below capture the boundary with single sizes). Sizes up to 1400 succeed (`!`), 1401 and above fail with `M`. The `M` is an ICMP "fragmentation needed" from the hop that cannot forward the packet. To locate it without reading configs: a 1401-byte DF ping to **10.0.23.2** (R2's own far-side address, delivered locally by R2) succeeds, while the same ping to **10.0.23.3** fails, so the packet dies when R2 tries to send it out Ethernet0/1. Confirmation: `show ip interface Ethernet0/1 | include MTU` on R2 → `MTU is 1400 bytes`; R1 Et0/1 shows 1500. Plausible wrong answers: R1 (its own interfaces are 1500; a 1401 packet leaves R1), R3 (a 1400-byte packet reaches R3 and PC2).

**R2 — traceroute.** Each line is the router that returned ICMP time-exceeded for a probe with TTL = n; the last line is PC2 answering (port unreachable for UDP probes). From R1 the first hop is R2 (10.0.12.2, the address of the interface facing R1); from PC1 there is one more line because PC1's first hop is its gateway R1 (10.0.1.1). The reported address is always the ingress interface of the replying router, which is why R3 appears as 10.0.23.3, not 10.255.0.3.

**R3 — conditional debug.** On iol-xe 17.16.1a both `debug condition` forms were tested with `debug ip icmp`: neither filtered (PC2's echo replies were logged). The working limited debug is an ACL on `debug ip packet`. Named ACLs are rejected by `debug ip packet` (`% Invalid input`); use a numbered one. Transit PC1→PC2 traffic is CEF-switched and never appears, so PC1 must ping R2 itself.

**R4 — logs.** `%LINK-5-CHANGED` (severity 5, notification: an administrative change), `%LINEPROTO-5-UPDOWN` (5, notification), `%LINK-3-UPDOWN` (3, error: the physical link changed state), `%SYS-5-CONFIG_I` (5). During the shutdown, PC1's traceroute ends at R2 with `!H` (R2 has a static route whose exit interface is down, so it returns host unreachable).

**R5 — SSH.** The key generation fails until a domain name exists (`% Please define a domain-name first.`), which is the most common first obstacle.

## Solution Configuration

On router R1: none (exec commands only).

On router R2 (requirement R3, limited debug; ACL in configuration mode, debug in exec mode):
```
configure terminal
 access-list 101 permit icmp host 10.0.1.101 any
 access-list 101 permit icmp any host 10.0.1.101
end
debug ip packet 101 detail
! ... PC1: ping -c 2 10.0.12.2   PC2: ping -c 2 10.0.23.2 ; ping -c 2 10.0.12.2
show logging | include IP: s=
undebug all
show debugging
configure terminal
 no access-list 101
end
```

On router R2 (requirement R4, log test):
```
configure terminal
 interface Ethernet0/1
  shutdown
! ... PC1: ping -c 3 10.0.3.102 ; traceroute -n 10.0.3.102
 interface Ethernet0/1
  no shutdown
end
show logging | include %LINK|%LINEPROTO|%SYS-5-CONFIG
```

On router R3 (requirement R5, SSH):
```
configure terminal
 ip domain name veridian.example
 crypto key generate rsa modulus 2048
 ip ssh version 2
 line vty 0 4
  login local
  transport input ssh
end
```

Login test on router R1 (requirement R5): `ssh -v 2 -l admin 10.255.0.3` (password `Cisco123!`), then on R3 `show users` / `show ssh`.

Optional (requirement R6) on router R3: `ntp trusted-key 1`.

## Verification

All outputs captured on CML 2.10.0; trimmed.

**Start state.** R1:
```
R1#traceroute 10.0.3.102 source Loopback0 numeric
  1 10.0.12.2 2 msec 1 msec 2 msec
  2 10.0.23.3 3 msec 2 msec 3 msec
  3 10.0.3.102 3 msec 3 msec 4 msec
```
PC1:
```
$ traceroute -n 10.0.3.102
 1  10.0.1.1  5.098 ms  1.929 ms  1.954 ms
 2  10.0.12.2  7.977 ms  9.952 ms  10.033 ms
 3  10.0.23.3  16.247 ms  17.027 ms  15.247 ms
 4  10.0.3.102  18.107 ms  19.911 ms  17.938 ms
```
(Alpine ping replies show `ttl=42`: a CML cosmetic artefact.)

**R1 — MTU boundary** (R1, source Ethernet0/0):
```
R1#ping 10.0.3.102 source Ethernet0/0 size 1400 df-bit repeat 3
Packet sent with the DF bit set
!!!
Success rate is 100 percent (3/3)
R1#ping 10.0.3.102 source Ethernet0/0 size 1401 df-bit repeat 3
Packet sent with the DF bit set
M.M
Success rate is 0 percent (0/3)
R1#ping 10.0.3.102 source Ethernet0/0 size 1500 repeat 3
!!!                                  <- without DF, R2 fragments
R1#ping 10.0.23.2 source Ethernet0/0 size 1401 df-bit repeat 3
!!!
R1#ping 10.0.23.3 source Ethernet0/0 size 1401 df-bit repeat 3
M.M
R2#show ip interface Ethernet0/1 | include MTU
  MTU is 1400 bytes
```
The `.` between the `M`s is R2's ICMP unreachable rate limit (one unreachable per 500 ms by default), not packet loss on the wire. A 1501-byte DF ping returns `..` with no `M`: R1 itself cannot send it (its own Et0/1 is 1500) and no ICMP is generated.

**R3 — `debug condition` does not filter `debug ip icmp`** (test on R2):
```
R2#debug condition ip 10.0.1.101
Condition 1 set
R2#debug ip icmp
ICMP packet debugging is on
R2#show logging | include ICMP
ICMP: echo reply sent, src 10.0.12.2, dst 10.0.1.101, topology BASE, dscp 0 topoid 0
ICMP: echo reply sent, src 10.0.23.2, dst 10.0.3.102, topology BASE, dscp 0 topoid 0   <- PC2, not filtered
R2#show debug condition
Condition 1: ip 10.0.1.101 :: (0 flags triggered)
```
`debug condition interface Ethernet0/0` behaved the same (PC2's pings arriving on Et0/1 were still logged).

**R3 — working ACL-limited debug** (PC1 pinged 10.0.12.2 and PC2; PC2 pinged 10.0.23.2 and 10.0.12.2 at the same time):
```
R2#debug ip packet 101 detail
IP packet debugging is on (detailed) for access list 101
R2#show logging
*Sep 26 23:22:50.593: IP: s=10.0.1.101 (Ethernet0/0), d=10.0.12.2 (nil), len 84, rcvd 2
*Sep 26 23:22:50.593:     ICMP type=8, code=0
*Sep 26 23:22:50.593: IP: s=10.0.12.2 (local), d=10.0.1.101 (Ethernet0/0), len 84, sending
*Sep 26 23:22:50.593:     ICMP type=0, code=0
```
(`detail` also adds `FIBipv4-packet-proc` lines.) No line for 10.0.3.102 and none for PC1's transit pings to PC2. Removal:
```
R2#undebug all
All possible debugging has been turned off
R2#show debug condition
% No conditions found
```
`undebug all` also removes debug conditions (`1 conditions have been removed` when one exists).

**R4 — logs** (R2):
```
*Sep 26 23:23:50.179: %LINK-5-CHANGED: Interface Ethernet0/1, changed state to administratively down
*Sep 26 23:23:51.179: %LINEPROTO-5-UPDOWN: Line protocol on Interface Ethernet0/1, changed state to down
*Sep 26 23:24:08.553: %SYS-5-CONFIG_I: Configured from console by console
*Sep 26 23:24:11.058: %LINK-3-UPDOWN: Interface Ethernet0/1, changed state to up
*Sep 26 23:24:12.058: %LINEPROTO-5-UPDOWN: Line protocol on Interface Ethernet0/1, changed state to up
```
PC1 during the shutdown:
```
$ ping -c 3 -W 2 10.0.3.102
3 packets transmitted, 0 packets received, 100% packet loss
$ traceroute -n -w 1 -m 4 10.0.3.102
 1  10.0.1.1  2.034 ms ...
 2  10.0.12.2  2.947 ms ...
 3  10.0.12.2  2.408 ms !H  *  3.136 ms !H
```
R2 during the shutdown:
```
R2#show ip route static | include ^S
S        10.0.1.0/24 [1/0] via 10.0.12.1
S        10.255.0.1/32 [1/0] via 10.0.12.1
R2#show ip route 10.0.3.102
% Subnet not in table
```
After `no shutdown` the two routes via 10.0.23.3 return and PC1 → PC2 is 3/3. R3 logged nothing (CML: the far end stays up/up).

**R5 — SSH.** Start state (R1):
```
R1#telnet 10.255.0.3 /source-interface Loopback0
Trying 10.255.0.3 ... Open
Password required, but none set
[Connection to 10.255.0.3 closed by foreign host]
R1#ssh -l admin 10.255.0.3
% Connection refused by remote host
```
After the fix:
```
R3#show ip ssh | include SSH
SSH Enabled - version 2.0
R1#telnet 10.255.0.3
Trying 10.255.0.3 ...
% Connection refused by remote host
R1#ssh -v 2 -l admin 10.255.0.3
Password:
```
The login is checked at the `Password:` prompt: type the password (`Cisco123!`); R3's `show users` then lists the session from 10.0.12.1, R1's exit address, and `show ssh` shows the SSH v2 session.

**R6 — NTP.** Predict first (Q4), then confirm at least 15 minutes after the lab started:
```
R2# show ntp associations
  address         ref clock       st   when   poll reach  delay  offset   disp
*~10.255.0.1      127.127.1.1      3    137    256   377  2.000  -0.240  2.460
R2# show ntp status
Clock is synchronized, stratum 4, reference is 10.255.0.1
...
loopfilter state is 'CTRL' (Normal Controlled Loop), drift is 0.000000017 s/s

R3# show ntp associations
  address         ref clock       st   when   poll reach  delay  offset   disp
 ~10.255.0.2      .TIME.          16      -     64     0  0.000   0.000 16000.
R3# show ntp status | include Clock
Clock is unsynchronized, stratum 16, no reference clock
R3# show clock
*02:12:10.109 UTC Sun Sep 27 2026
```
(captured on a fresh import, about 2.5 hours after boot). R2 first selects R1 (`*`, reach 7) about 15–17 minutes after boot. For a few more minutes `show ntp status` still reports `Clock is unsynchronized, stratum 4` with loopfilter `FREQ` while the drift is measured; it later changes to `Clock is synchronized`. `show ntp associations detail` on R3 shows `authenticated (' ' reject) ... insane, invalid, unsynced, stratum 16`.

Optional change: on R3, `ntp trusted-key 1`. In a test run, R3 selected R2 (`*~10.255.0.2 10.255.0.1 4 ...`) and reported stratum 5 about 13 minutes after the change, because R2 serves time only once its own loop filter has left `FREQ`. This proves the missing trusted key was the only thing stopping R3.

## Failure / Recovery Behaviour

| Test | Result |
|---|---|
| R2 Ethernet0/1 `shutdown` | PC1→PC2 100 % loss; PC1 traceroute stops at R2 with `!H`; R2 logs `%LINK-5-CHANGED` and `%LINEPROTO-5-UPDOWN ... down`; the static routes via 10.0.23.3 leave R2's table while the interface is down. R3's Ethernet0/0 stays up/up and logs nothing (CML behaviour). |
| R2 Ethernet0/1 `no shutdown` | `%LINK-3-UPDOWN ... up` then `%LINEPROTO-5-UPDOWN ... up` one second later; PC1→PC2 3/3 immediately; `10.0.3.0/24 via 10.0.23.3` back in R2's table. |

## Answers to Analysis Questions

**Q1.** Once a debug is enabled it starts generating output immediately for every matching event. On a busy router, `debug ip packet` without a filter sends every process-switched packet to the logging process, which can saturate the CPU and the console, and you may lose the session before you can type `undebug all`. Setting the ACL (or condition) first means the very first debug message is already limited. Also verify that the filter really works on a harmless test (this lab shows that `debug condition ip` is accepted on this image but does not restrict `debug ip icmp`). Prefer the log buffer to the console (`logging buffered` + `show logging`).

**Q2.** Every link is 1500 bytes except R2 Ethernet0/1 (`ip mtu 1400`), so the largest DF-set packet from 10.0.1.1 to PC2 is 1400 bytes, exactly the sweep boundary. The 1401-byte ping to 10.0.23.2 is addressed to R2 itself; R2 receives it on Ethernet0/0 (MTU 1500) and never has to forward it out Ethernet0/1, so it succeeds. The ping to 10.0.23.3 must leave R2 through Ethernet0/1, so R2 returns ICMP type 3 code 4 (fragmentation needed and DF set), shown as `M`. The `.` characters are timeouts: R2 rate-limits ICMP unreachables (500 ms by default), so every other probe gets no answer. Without DF, R2 fragments the packet and the ping succeeds.

**Q3.** `%LINK-5-CHANGED` and `%LINEPROTO-5-UPDOWN` are severity 5 (notifications): normal but significant events, here an administrator's action and its consequence on the line protocol. `%LINK-3-UPDOWN` is severity 3 (error): a physical link state change. `%SYS-5-CONFIG_I` is 5. Severity decides where a message is sent (buffer, console, syslog `logging trap` level). Timestamps let you order events across devices (for example, "the link went down, then the neighbour's route disappeared"). That only works when every device agrees on the time, hence NTP. A leading `*` means the router's clock is not authoritative (not synchronised); a `.` would mean it was synchronised but has lost its source. In this lab, R2's timestamps carried the `*` because R2 had not yet synchronised.

**Q4.** R1 has `ntp master 3`, so once its clock is usable it serves time at **stratum 3** (its local reference clock `127.127.1.1` shows as stratum 2 in `show ntp associations`). R2 has `ntp server 10.255.0.1 key 1` with `ntp authenticate`, the key and `ntp trusted-key 1`: it accepts R1's authenticated packets and becomes **stratum 4**. R3 has `ntp authenticate` and key 1 and points at R2 with key 1, but has **no `ntp trusted-key 1`**. With `ntp authenticate`, a server is accepted only if its key is trusted, so R3 rejects R2 forever: it never synchronises and stays at stratum 16. Configuring a key is not the same as trusting it.

**Q5.** The VTY password (or local login) protects *who* can log in; `transport input` controls *which protocols* can reach the lines. Telnet sends the username, password and the whole session in clear text, so anyone who can capture traffic on the path gets the credentials. With `transport input ssh`, Telnet connections are refused before any login prompt (R1 saw `% Connection refused by remote host`), and only an encrypted, server-authenticated SSH v2 session can carry the credentials.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-14 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), iol-xe (IOS XE 17.16.1a) |
