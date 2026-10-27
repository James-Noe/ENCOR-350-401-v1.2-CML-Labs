# LAB-032 — Solution

## Summary
An implementation lab (I, G2): the auditor's findings A1 to A8 are the requirements, so there are no hidden faults. The student closes each finding on R1 (iol-xe), R2 (iol-xe) and SW1 (ioll2-xe) and writes a re-test for each from PC1 (net-tools). Skills: secret types 0/5/7/8/9 and why type 7 is reversible, `algorithm-type scrypt secret`, RSA key replacement, SSH version and cipher control, consistent VTY lines, `exec-timeout`, `login block-for` with logging, disabling the HTTP servers, `nmap` and `ssh` as the auditor's tools. Blueprint 5.1.a.

## Intentional Faults
None (I lab). The start-state configuration behind each finding:

| ID | Device | Start-state configuration | Visible as |
|---|---|---|---|
| A1 | R1 | `line vty 3 4`: `password cisco`, `login`, `transport input telnet` | nmap: 23 open; telnet with `cisco` gives privilege 1 |
| A1 | SW1 | `line vty 3 4`: `transport input ssh telnet` | nmap: 23 open |
| A2 | R1 | `enable password cisco`, `username admin privilege 15 password 0 Cisco123!` | config review |
| A2 | R2 | `service password-encryption`, `username admin privilege 15 password 7 072C285F4D0648574453` | config review (type 7 decodes) |
| A3 | R1 | day-0 RSA 2048 key, no `ip ssh version` | `ssh-keyscan` 2048 bits |
| A4 | R1 | `ip ssh server algorithm encryption aes128-cbc aes256-ctr` | `ssh -c aes128-cbc` connects |
| A5 | SW1 | `line vty 3 4`: `password cisco`, `login` | config review; vty 0 2 use `login local` |
| A6 | R1, R2, SW1 | no `exec-timeout` on R1/SW1 VTY (IOS default 10 min, longer than the 5-minute policy), `exec-timeout 0 0` on R2 (`0 0` = never) | config review |
| A7 | R1, SW1 | `ip http server`, `ip http secure-server` | config review (ports 80/443 are closed anyway) |
| A8 | all | no `login block-for` | `show login`: not enabled |

Deviations from the plan (all by what teaches the objective, recorded here): VTY lines `5 15` do not exist on iol-xe or ioll2-xe, so everything is on `vty 0 4` (R1 and SW1 are split 0-2 / 3-4; IOL only: IOS-XE routers and switches have lines 0-15 by default, so configure `line vty 0 15` there); SSH never uses a line password, so SW1 SSH works only on vty 0-2; this image rejects RSA moduli below 2048 ("Invalid input") and `show ip ssh` already says version 2.0 (`ip ssh version 2` is accepted but not displayed in the running configuration), so A3 became "minimum 2048-bit key, version not pinned, policy 3072"; the HTTP servers are enabled but never listen (nmap sees 80/443 closed before and after), so A7 is a config-review finding (Q3); the type 7 decode is done on PC1 because IOS `show key chain` shows the type 7 string unchanged on 17.16.

## Diagnosis / Methodology
1. Scan from PC1 for what a network attacker sees: `nmap -Pn -p 22,23,80,443 10.0.10.1 10.0.10.2 10.0.12.1` (R1 and SW1: 22 and 23 open; R2: 22 only; 80/443 closed everywhere).
2. Enumerate SSH: `nmap -Pn -p 22 --script ssh2-enum-algos,ssh-hostkey 10.0.10.1` (CBC and SHA-1 offered, 2048-bit RSA key), `ssh-keyscan -t rsa 10.0.10.1 | ssh-keygen -lf -`, `ssh -c aes128-cbc admin@10.0.10.1` connects.
3. Read each device's configuration for what no scan shows: `show running-config | include enable|username|http|ssh`, `show running-config | section line vty`, `show login`.
4. Telnet to R1 and SW1 with `cisco` reaches the device (privilege 1): the shared password, no account.
5. Decode the R2 type 7 string on PC1 (`python3 t7.py 072C285F4D0648574453` gives `Cisco123!`): that proves why `service password-encryption` is not a fix.

## Solution Configuration
Tested from a fresh import; apply the blocks below in order. `no username admin` asks `[confirm]` (answer `y`; a script that cannot answer the prompt hangs until timeout, so use the interactive console for this line); a user cannot hold both `password` and `secret`, so remove and re-create it.

R1:
```
crypto key generate rsa label SSH3072 modulus 3072     ! exec mode; generates in the background, wait for `show crypto key mypubkey rsa`
ip ssh rsa keypair-name SSH3072
ip ssh version 2
enable algorithm-type scrypt secret Cisco123!
no enable password
no username admin                                      ! confirm with y
username admin privilege 15 algorithm-type scrypt secret Cisco123!
no ip ssh server algorithm kex          ! optional: returns the key-exchange list to the image default
no ip ssh server algorithm mac          ! optional: image default MAC list (hmac-sha1 is still offered; removing it is an optional extra finding)
no ip ssh server algorithm hostkey      ! optional: image default host-key list
ip ssh server algorithm encryption aes256-ctr aes192-ctr aes128-ctr
no ip http server
no ip http secure-server
line vty 0 4
 no password
 login local
 transport input ssh
 exec-timeout 5 0
login block-for 60 attempts 3 within 30
login on-failure log
login on-success log
```
R2:
```
ip ssh version 2
no username admin                                      ! confirm with y
username admin privilege 15 algorithm-type scrypt secret Cisco123!
line vty 0 4
 exec-timeout 5 0
login block-for 60 attempts 3 within 30
login on-failure log
login on-success log
```
SW1:
```
no ip http server
no ip http secure-server
line vty 0 4
 no password
 login local
 transport input ssh
 exec-timeout 5 0
login block-for 60 attempts 3 within 30
login on-failure log
login on-success log
```
All three: `write memory`. R2 keeps `service password-encryption` (harmless once no type 7 secret remains; Q1). Both `algorithm-type scrypt` (type 9) and the fallback type 8 are accepted on iol-xe and ioll2-xe (SW1 already holds type 9 secrets). The interactive alternative is `crypto key generate rsa modulus 3072`, which asks whether to replace the existing key; the labelled form leaves the old key in place and needs no prompt, which suits scripts.

Re-tests (R5):

| ID | Re-test from PC1 or the device | Closed result |
|---|---|---|
| A1 | `nmap -Pn -p 23 10.0.10.1 10.0.10.2`; `nc 10.0.10.1 23` | 23 closed; "Connection refused" |
| A2 | `show running-config \| include enable\|username\|password` on R1, R2 | only `secret 9`; no `password 0/7`, no `enable password` |
| A3 | `ssh-keyscan -t rsa 10.0.10.1 \| ssh-keygen -lf -`; `show ip ssh` | 3072 bits (`ip ssh version 2` is the only version on this image and is not displayed, so only the key size can be proven) |
| A4 | `ssh -c aes128-cbc admin@10.0.10.1` | "no matching cipher found" |
| A5 | `show running-config \| section line vty` on SW1 | all lines `login local`, no `password` |
| A6 | `show running-config \| section line vty` (CML console) | `exec-timeout 5 0` everywhere |
| A7 | `show ip http server status` on R1, SW1 | both servers Disabled |
| A8 | three bad SSH logins, then `show login` and `show logging \| include SEC_LOGIN` | `QUIET_MODE_ON`, later `QUIET_MODE_OFF` |

Accepted exception: consoles open in privileged mode (`line con 0` has `privilege level 15`, `exec-timeout 0 0`).

## Verification
Start state:
```
nmap: 10.0.10.1  22/tcp open ssh, 23/tcp open telnet | 10.0.10.2  22, 23 open | 10.0.12.1  22 open
SSH-2.0-Cisco-1.25 (all three)
nmap ssh-hostkey R1: 2048 ... (RSA); enc offered: aes128-cbc, aes256-ctr; mac hmac-sha1
ssh admin@R1/R2/SW1 'show privilege': Current privilege level is 15
ssh -c aes128-cbc admin@10.0.10.1: Current privilege level is 15
nc 10.0.10.1 23 / 10.0.10.2 23, password cisco: Current privilege level is 1
R1: enable password cisco / username admin privilege 15 password 0 Cisco123! / ip http server / ip http secure-server
R2: service password-encryption / username admin privilege 15 password 7 072C285F4D0648574453
```
End state:
```
nmap: 22/tcp open, 23/tcp closed, 80/tcp closed, 443/tcp closed on 10.0.10.1, 10.0.10.2, 10.0.12.1
ssh -c aes128-cbc admin@10.0.10.1: Unable to negotiate with 10.0.10.1 port 22: no matching cipher found. Their offer: aes256-ctr,aes192-ctr,aes128-ctr
ssh admin@10.0.10.1 / 10.0.12.1 / 10.0.10.2 'show privilege': Current privilege level is 15
nc 10.0.10.1 23: Connection refused
ssh-keyscan -t rsa 10.0.10.1 | ssh-keygen -lf -  ->  3072 SHA256:... 10.0.10.1 (RSA)   (R2: 2048; not named in A3)
R1 show ip ssh: SSH Enabled - version 2.0 ; Encryption Algorithms:aes256-ctr,aes192-ctr,aes128-ctr
R1 show ip http server status: HTTP server status: Disabled / HTTP secure server status: Disabled
R1/R2/SW1 enable secret 9 ..., username admin privilege 15 secret 9 ...  (no password lines)
startup-config (after write memory in the same session): line vty 0 4 / exec-timeout 5 0 / login local / transport input ssh
```
Type 7 decode on PC1 (a short Python type-7 decoder): `072C285F4D0648574453` decodes to `Cisco123!`. IOS `show key chain` does not decode it on this image (`key 1 -- text "072C285F4D0648574453"`).

Tool caveat: CLI automation (such as unicon) resets `exec-timeout` on `line vty 0 4` to 0 each time it connects, so `show running-config` over automation always shows `exec-timeout 0 0`; read it on a CML console, or do `write memory` in the same session as the change and read `show startup-config`. Start-state A6 is therefore shown by the day-0 text, not by a CLI read (derived).

## Failure / Recovery Behaviour
Lock-out drill, from PC1 against R1 with the wrong password:
```
admin@10.0.10.1: Permission denied (publickey,keyboard-interactive,password).   (three attempts within 30 s)
R1# show login      Router presently in Quiet-Mode.   Will remain in Quiet-Mode for 50 seconds.
%SEC_LOGIN-4-LOGIN_FAILED: Login failed [user: admin] [Source: 10.0.10.100] ...  (x3)
%SEC_LOGIN-1-QUIET_MODE_ON: Still timeleft for watching failures is 22 secs, [user: admin] [Source: 10.0.10.100] ...
console: show privilege -> Current privilege level is 15   (console exempt)
client during quiet mode: Connection closed by 10.0.10.1 port 22
%SEC_LOGIN-5-QUIET_MODE_OFF: Quiet Mode is OFF, because block period timed out   (60 s after ON)
%SEC_LOGIN-5-LOGIN_SUCCESS: Login Success [user: admin] [Source: 10.0.10.100] ...  (next good login)
```
Recovery is by the timer only; the console and the lab's other devices keep working. Failure method: none of the CML link/node kinds is used; the lock-out is a logical failure over the access path.

## Answers to Analysis Questions
Q1. `service password-encryption` only obscures strings that are stored as plain passwords (type 7), which is a fixed-key XOR: anyone with the configuration decodes it in a line of Python (demonstrated on PC1). The fix is a one-way hash (`secret`, type 8/9), which the device compares by hashing the typed password.
Q2. A new key gives the router a new host key fingerprint. Every client that stored the old fingerprint (`known_hosts`, automation, monitoring) refuses to connect with a "host key changed" warning. Announce it in a change window, publish the new fingerprint (compare with `ssh-keyscan | ssh-keygen -lf -`), and tell users to remove the old entry. A labelled key (`ip ssh rsa keypair-name`) lets you stage the new key before switching.
Q3. A2 (storage), A6 (timeouts), A7 (the HTTP servers never listen on this platform, so 80/443 look closed), A8 (until someone fails logins) and A5 (a scan sees only that SSH/telnet is open). The auditor found them from a configuration review (`show running-config`, saved configuration files), which is why the report marks them "config review".
Q4. A console that opens in privilege 15 without a password gives anyone with physical or terminal-server access full control and bypasses AAA and accounting. Real networks replace it with `login authentication` on the console against AAA with a local fallback for the break-glass account, plus physical security and an out-of-band server that logs in through its own credentials (033 builds this).
Q5. Quiet mode refuses every source, so one attacker guessing passwords locks out the engineers too, a denial of service on management access. `login quiet-mode access-class <mgmt ACL>` lists the management station that stays allowed, which needs a management ACL; the management ACL itself (the VTY access-class) is built in 034, but the quiet-mode exception is not configured in any later lab.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-14 |
| CML | 2.10.0 |
| Node types | iol-xe (IOS XE 17.16.1a), ioll2-xe (IOS XE 17.16.1a), net-tools |
