# LAB-033 — Solution

## Summary
First AAA lab of the family. Students enable `aaa new-model` on two routers without a lock-out (named list `CON` with `none` on the console, named list `VTY` on the VTY lines), authenticate, authorize (exec, priv-lvl from `Cisco-AVPair`) and account against a FreeRADIUS node, tune dead-server detection, and prove the two failure semantics: a RADIUS reject is final, a RADIUS timeout falls back to local. Blueprint 5.1.b (RADIUS, TACACS+). Fault-free feature lab (no Intentional Faults).

## Intentional Faults
None (F lab).

## Diagnosis / Methodology
Not a troubleshooting lab. The method for R6/R7: watch `show aaa servers` (state UP/DEAD), `show logging | include RADIUS|SEC_LOGIN` on the router and the DC-AAA1 console log (`tools/cml-rest.sh log <lab> DC-AAA1 40 'Login|ACCT'`). A reject shows `Login incorrect` on the server and no timeout on the router; a failure shows `Authen: timeouts` and `%RADIUS-4-RADIUS_DEAD` on the router and nothing on the server.

Platform decisions (as built):
- The VTY lines are `line vty 0 4`. Day-0 with `line vty 0 15` on this IOL image leaves `line vty 0 4` with plain `login` and every SSH user gets `Permission denied`. (IOL only: IOS-XE routers and switches have lines 0-15 by default, so configure `line vty 0 15` there.)
- Both routers use Loopback0 as the RADIUS source (R1 10.255.0.1, DC-RTR1 10.255.50.1; both inside the server's client range 10.0.0.0/8, so the server accepts either).
- `tacacs server NAME` is rejected on this image, so TACACS+ is config-syntax only: use the legacy `tacacs-server host`, which IOS converts to `tacacs server 10.50.50.53`. There is no TACACS+ server (the `tacplus` node does not start), so nothing can be proven beyond the router accepting the lines.
- The `test aaa ... new-code` form is deprecated but works.
- SSH makes 4 attempts per login, so DC-AAA1 logs 4 rejects for one failed ssh.
- DC-NMS1 SSH tests: just run `ssh user@10.255.0.1`.

## Solution Configuration
Identical on R1 and DC-RTR1:
```
aaa new-model
aaa authentication login CON none
aaa authentication enable default enable none
radius server DC-AAA1
 address ipv4 10.50.50.52 auth-port 1812 acct-port 1813
 key RADKEY123
aaa group server radius RADGRP
 server name DC-AAA1
 ip radius source-interface Loopback0
radius-server dead-criteria time 5 tries 2
radius-server deadtime 1
aaa authentication login VTY group RADGRP local
aaa authorization exec VTY group RADGRP local
aaa accounting exec VTY start-stop group RADGRP
line con 0
 login authentication CON
line vty 0 4
 login authentication VTY
 authorization exec VTY
 accounting exec VTY
```
Apply the lists before assigning them to lines. `aaa authentication enable default enable none` keeps `enable` working on the console for accounts without an enable secret (the console is privilege 15 anyway).

TACACS+ (Q4, accepted on iol-xe with no server):
```
tacacs-server host 10.50.50.53 key TACKEY123
aaa group server tacacs+ TACGRP
 server 10.50.50.53
 ip tacacs source-interface Loopback0
aaa authentication login TACVTY group TACGRP local
aaa authorization exec TACVTY group TACGRP local
aaa authorization commands 15 TACVTY group TACGRP local
aaa accounting commands 15 TACVTY start-stop group TACGRP
```

## Verification
Captured on R1 (same on DC-RTR1):
```
test aaa group RADGRP netadmin netpass new-code   -> User successfully authenticated ... priv-lvl 0 15 (0xF)
test aaa group RADGRP netops opspass new-code     -> User successfully authenticated ... priv-lvl 0 1
test aaa group RADGRP netadmin WRONG new-code     -> User rejected
```
SSH from DC-NMS1 to both routers: `netadmin` -> `Current privilege level is 15`; `netops` -> `Current privilege level is 1`. R1: `%SEC_LOGIN-5-LOGIN_SUCCESS [user: netadmin]`. DC-AAA1 console:
```
Login OK: [netadmin]
ACCT Start user=netadmin nas=10.255.50.1 session=00000001
ACCT Stop user=netadmin nas=10.255.50.1 session=00000001
```
Reject (R7, server up): `admin`/`Cisco123!` from DC-NMS1 to R1: client prints only `Connection closed by 10.255.0.1 port 22` (rc=255, no `Permission denied` text); DC-AAA1: `Login incorrect (No Auth-Type found: rejecting the user via Post-Auth-Type = Reject): [admin/Cisco123!]` x4. `netadmin`/`WRONG`: the same client message; DC-AAA1: `Login incorrect (pap: Cleartext password does not match "known good" password)` x4. No fallback occurred.

Console exemption: console logins kept working on both routers throughout (console list `CON none`).

## Failure / Recovery Behaviour
Method: CML node stop of DC-AAA1 (silent failure: the router's link stays up, only RADIUS timeouts detect it).
- Without `dead-criteria`/`deadtime` (default 5 s timeout, 3 retransmits): every `admin` login takes about 18-25 s (measured 20-21 s twice) because each attempt waits out the timeouts, and the server stays UP.
- With `dead-criteria time 5 tries 2` and `deadtime 1`: the first `admin` login takes about 5-12 s (measured 10 s; log `Authen: timeouts 2`, then `State DEAD`, `%RADIUS-4-RADIUS_DEAD`, `%RADIUS-3-ALLDEADSERVER`, `%RADIUS-3-NOSERVERS`); `admin` logs in (`Login Success`); `netadmin` fails (rc=255). The next `admin` logins take about 0-2 s (measured 0 s) because the dead server is skipped.
- Recovery: after `node start DC-AAA1`, about 60 s after the DEAD mark (deadtime 1 minute) R1 logs `%RADIUS-6-SERVERALIVE` and `%RADIUS-4-RADIUS_ALIVE`; `netadmin` logs in with privilege 15 again. The radius node restarts cleanly with its stored config.
- Wrong key on R1 (`RADKEY123` replaced by `WRONGKEY`): DC-AAA1 logs `Login incorrect (pap: Cleartext password does not match ...)` with a garbled user password and, for accounting, `Received Accounting-Request packet from client 10.255.0.1 with invalid Request Authenticator! (Shared secret is incorrect.)`; the router discards the replies, times out, `%RADIUS-4-RADIUS_DEAD`, `%RADIUS-3-ALLDEADSERVER`, and falls back to local: `admin` logs in, `netadmin` fails. This confirms Q2 as designed.
Restored: R1 and DC-RTR1 wiped; start-checks re-run with the same results.

## Answers to Analysis Questions
Q1. `admin` exists only in the router's local database. The server is reachable and answers Access-Reject, and a reject is a definitive answer: the list stops (no local fallback). The server's log shows `Login incorrect ... [admin/...]`. So the emergency account works only when the server is unreachable or dead, never while it is alive: do not rely on it for routine work, keep its password out of daily use, store it offline, and rotate it after every use. (Note: DC-AAA1 logs failed passwords in clear text, `auth_badpass = yes`, which is itself a policy risk.) A way around this is a second method such as `local` before `group` for a dedicated account, or a RADIUS user for the emergency account.
Q2. A wrong user password gets an Access-Reject, which is final: no fallback, and the user simply retries. A wrong shared key makes the router unable to verify the server's replies (the authenticator does not match), so it discards them and counts timeouts. It then marks the server dead and falls back to local, even though the server is up. Everyone is silently pushed onto local accounts, centrally issued access and accounting stop working (the server drops accounting packets with `invalid Request Authenticator`), and the logs on the server look like ordinary bad passwords. Local fallback also means the router now accepts every local account.
Q3. If the console used `VTY`, a dead server would delay console logins by the timeouts and a reject would lock out the console as well as the VTY (no `none` fallback). Local is the final method, so the console would still work for local users, but a mistake in the list, a missing local user or a server reject would leave no emergency path. The `CON none` list keeps the console as the last-resort path, acceptable because the console is physical access.
Q4. RADIUS: UDP 1812/1813, encrypts only the password in the Access-Request, combines authentication and authorization in one response, and its accounting is session-level (per-command accounting and per-command authorization are not supported). TACACS+: TCP 49, encrypts the whole packet body, separates authentication, authorization and accounting, and supports per-command authorization and accounting. For administration TACACS+ is the better fit; RADIUS is common for network access (802.1X, VPN). Method list (accepted by the router, config only): `aaa authentication login TACVTY group TACGRP local`, `aaa authorization exec TACVTY group TACGRP local`, `aaa authorization commands 15 TACVTY group TACGRP local`, `aaa accounting commands 15 TACVTY start-stop group TACGRP`, with the server definition shown above.
Q5. `default` applies to every line without its own list, including the console. The console would try RADIUS first and then local: a dead server delays every console login, a reject locks it, and a console user needs a RADIUS or local account. It also overrides the intent of keeping the console exempt. (On this platform the scripted console login, which depends on `privilege level 15`, only keeps working because CON uses `none`.)

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-14 |
| CML | 2.10.0 |
| Node types | iol-xe (IOS XE 17.16.1a), net-tools, radius, unmanaged_switch |
