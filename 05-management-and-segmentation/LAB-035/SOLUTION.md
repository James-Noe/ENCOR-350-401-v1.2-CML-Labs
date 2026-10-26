# LAB-035 — Solution

## Summary
Implementation lab (G2). R1 (iol-xe) and SW1 (ioll2-xe) are made to feed the DC services: syslog to DC-SYSLOG1 from a fixed source at trap level informational, SNMPv3 (authPriv on R1, authNoPriv on SW1) plus v2c on R1 restricted by an ACL to DC-NMS1, a linkdown/linkup trap to the NMS, and NTP authentication against DC-RTR1 (`hmac-sha2-256` key 1). PTP is analysis only, from derived output in LAB.md. Blueprint: 4.1 (syslog, SNMP, NTP) :P, 3.3.a (PTP) :A. Platform notes: `hmac-sha2-256` NTP keys work on ioll2-xe too (no md5 fallback needed); `snmp-server enable traps snmp linkdown linkup` and a v3 `snmp-server host` are accepted on iol-xe 17.16.1a.

## Intentional Faults
None (implementation lab).

## Diagnosis / Methodology
Not a troubleshooting lab. Checkpoints: (1) collector console shows `%SYS-5-USERLOG_NOTICE` from `send log 5`; `send log 7` is only in `show logging`. (2) `snmpget` from DC-NMS1 at each level; negative tests with wrong community/password; a second NMS1 address (`ip addr add 10.50.50.61/24 dev eth0`, `ip route add 10.255.0.1/32 via 10.50.50.1 src 10.50.50.61`) and DC-RTR1 (`snmp-server manager`, `snmp get v2c 10.255.0.1 ENCOR-RO oid 1.3.6.1.2.1.1.5.0`) time out; the ACL counter increments only for 10.50.50.60. (3) `tshark -l -i eth0 -f "udp port 162"` on NMS1 (use `-l`; redirected output is block-buffered). (4) NTP: `show ntp associations` and `detail`.

## Solution Configuration
R1:
```
logging source-interface Loopback0
logging host 10.50.50.51
logging trap informational
ip access-list standard SNMP-NMS
 permit 10.50.50.60
snmp-server community ENCOR-RO RO SNMP-NMS
snmp-server group NMS v3 priv access SNMP-NMS
snmp-server user nmsuser NMS v3 auth sha AUTHPASS123 priv aes 128 PRIVPASS123
snmp-server source-interface traps Loopback0
snmp-server enable traps snmp linkdown linkup
snmp-server host 10.50.50.60 version 3 priv nmsuser
ntp authentication-key 1 hmac-sha2-256 NTPKEY123
ntp authenticate
ntp trusted-key 1
ntp server 10.0.1.0 key 1
```
SW1 (same logging, ACL and NTP lines; source `Vlan10`):
```
logging source-interface Vlan10
logging host 10.50.50.51
logging trap informational
ip access-list standard SNMP-NMS
 permit 10.50.50.60
snmp-server group NMS v3 auth access SNMP-NMS
snmp-server user nmsuser NMS v3 auth sha AUTHPASS123
ntp authentication-key 1 hmac-sha2-256 NTPKEY123
ntp authenticate
ntp trusted-key 1
ntp server 10.0.1.0 key 1
```
`snmp-server group PRIVTEST v3 priv` on SW1 gives `% Invalid input detected at '^' marker` (no SNMPv3 priv on ioll2-xe).

## Verification
Logging (captured): collector line `10.255.0.1 %SYS-5-USERLOG_NOTICE: Message from tty0(user id: ): ENCOR-R1-NOTICE` and `10.0.10.2 ... ENCOR-SW1-NOTICE`; level 7 appears only locally as `%SYS-7-USERLOG_DEBUG`.
```
R1# show logging | include Logging to|Trap logging|Buffer logging
    Buffer logging:  level debugging, 53 messages logged, xml disabled,
    Trap logging: level informational, 55 message lines logged
        Logging to 10.50.50.51  (udp port 514, audit disabled,
```
SNMP from DC-NMS1:
```
snmpget -v3 -l authPriv ... 10.255.0.1 1.3.6.1.2.1.1.5.0   -> "R1.veridian.example"
snmpget -v3 -l authNoPriv ... 10.0.10.2 ...                  -> "SW1.veridian.example"
snmpget -v2c -c ENCOR-RO 10.255.0.1 ...                      -> "R1.veridian.example"
snmpget -v2c -c WRONG ...                                    -> Timeout: No Response from 10.255.0.1.
wrong auth password                                          -> Authentication failure (incorrect password, community or key)
authNoPriv against R1 (group needs priv)                     -> Reason: authorizationError (access denied to that object)
```
Denied sources (second NMS1 address, v3 and v2c to R1, v3 to SW1; DC-RTR1 v2c): all `Timeout: No Response`. ACL counters: R1 `10 permit 10.50.50.60 (3 matches)`, SW1 `(1 match)`.

Trap (shutdown R1 e0/1 and SW1 e0/0, then no shutdown): `tshark -l` on NMS1 shows `10.255.0.1 -> 10.50.50.60 SNMP 300 encryptedPDU: privKey Unknown` at link down and a second ~15 s after restore (authPriv traps are encrypted, so tshark shows source and count only; `show snmp` Trap PDUs agrees). After restore R1 pings SW1 (first ping lost to ARP).

NTP (time checks last; `sys.peer` within a few minutes after DC-RTR1 serves; `Clock is synchronized` 25-35 min after configuration):
```
R1/SW1# show ntp associations
*~10.0.1.0        127.127.1.1      3     55     64     7  4.000   0.000  2.672
R1/SW1# show ntp associations detail | include authenticat
10.0.1.0 configured, ipv4, authenticated ('*' sys.peer), authtype (hmac-sha2-256), our_master, sane, valid, stratum 3
```
Wrong key (key 2 `WRONGKEY99`, trusted) on R1 after 150 s:
```
10.0.1.0 configured, ipv4, authenticated (' ' reject), authtype (hmac-sha2-256), insane, invalid, unsynced, stratum 16
Clock is unsynchronized, stratum 16, no reference clock
```
Restoring `ntp server 10.0.1.0 key 1` gives `*~10.0.1.0` again within about 90 s.

Keyless server (`ntp server 10.0.1.0` with no `key`, `ntp authenticate` still on), measured on R1 and SW1: the server is still selected as `sys.peer`. `show ntp associations detail | include authenticat` shows no `authenticated (...)` token for it (the line reads `configured, ipv4, our_master, sane, valid`), so the filter returns nothing for that association, but the clock still syncs to it. So on this IOS-XE image `ntp authenticate` does not stop the client using a keyless server; a wrong or untrusted key is rejected (above).

Timing: `show ntp status` can show `Clock is unsynchronized` for about 25-35 min after configuration even while `show ntp associations` already shows `*~10.0.1.0` (sys.peer, reach non-zero, authenticated). Meanwhile check the association table and detail output, then re-check the status later.

## Failure / Recovery Behaviour
Method: node stop of DC-SYSLOG1 (silent failure). R1 keeps `Logging to 10.50.50.51`, no error; `send log 5 ENCOR-DURING-OUTAGE` is in R1's buffer; the `Trap logging ... message lines logged` counter keeps counting, so it does not show delivery. After the node restarts, `send log 5 ENCOR-AFTER-RESTART` arrives at the collector; the outage message is lost (UDP, no replay, no buffering to the host). Cable pull for the trap test uses `shutdown` on both ends.

## Answers to Analysis Questions
Q1. ioll2-xe rejects `snmp-server group ... v3 priv` (no SNMPv3 privacy), so SW1 is limited to authNoPriv: authentication is still SHA, but the SNMP payload (including values read) is sent in clear and can be captured.
Q2. Informational (level 6) and `%SYS-5` notice messages needed `trap informational` (a level-7 message never reaches the collector). A `warnings` threshold would hide notices and informational messages such as `%SYS-5-CONFIG_I`, `%SYS-6-LOGGINGHOST_STARTSTOP`, and `%SYS-5-USERLOG_NOTICE`, i.e. config changes and routine state events.
Q3. `ntp authenticate` protects only servers whose `ntp server` line carries `key N` with N in `ntp trusted-key`. A wrong or untrusted key gives `authenticated (' ' reject)`, `unsynced`, and the clock stays unsynchronised; the correct key gives `*` sys.peer authenticated. A server line with no `key` bypasses it silently: on this platform it is still selected as sys.peer, and only `show ntp associations detail` (no `authenticated (...)` token on the association) reveals it. The textbook claim that only authenticated sources are used is not what this image does, so check every server line for `key N` and verify with the detail output, not by assuming `ntp authenticate` enforces it.
Q4. The status line lags on this platform: `Clock is unsynchronized` can persist 25-35 min even with a sys.peer, and it says nothing about which server was chosen or whether it was authenticated (DC-RTR1 itself serves from its local clock, 127.127.1.1). `sys.peer` (`*`) with `authenticated` and reach non-zero proves the specific authenticated server was selected.
Q5. (derived) Grandmaster: the clock with identity 0x4C:71:D:FF:FE:12:A0:01 (GM-SW, class 6, priority1 100). Boundary clock: BC-SW (`PTP Device Type: Boundary clock`). Ports: BC-SW Te1/0/1 SLAVE (towards the grandmaster), Te1/0/2 MASTER (towards the tester); GM-SW Te1/0/1 MASTER; tester Gi1/0/1 SLAVE.
Q6. PTP aims at sub-microsecond accuracy, which needs timestamps taken in hardware at the MAC/PHY (no queueing or software jitter); NTP's millisecond accuracy tolerates software timestamps.
Q7. Example: a Veridian trading or broadcast/industrial automation floor needing sub-microsecond time (e.g. synchronised sampling of plant telemetry) rather than NTP's milliseconds.

PTP material is derived from Cisco Catalyst/IE PTP configuration guides (not captured).

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-14 |
| CML | 2.10.0 |
| Node types | iol-xe (IOS XE 17.16.1a), ioll2-xe (IOS XE 17.16.1a), net-tools, syslog, unmanaged_switch |
