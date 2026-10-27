# LAB-028 — Solution

## Summary

Foundation lab for EEM (blueprint 6.6:I, with 4.1:R syslog reading): applets with a track event, a syslog pattern, a watchdog timer and `event none`; `cli command` / `syslog msg` actions; `| append unix:`; `maxrun`; history. No intentional faults: the three pitfalls (R5) are guided exercises. Bench: LAB-026 design on R1 only (SLA 1/track 1; SLA 2–4 absent); platform iol-xe 17.16.1a, evidence files on `unix:` (no `flash:`). Failure method: silent failure = CML link stop R1 e0/0 – R3 e0/0 (detected in about 10 s, as measured on the same SLA in LAB-026).

## Intentional Faults

None.

## Diagnosis / Methodology

Pitfall evidence (all observed on R1):
1. **Missing `enable`.** The EEM CLI session starts unprivileged even though consoles are privileged. Without `action cli command "enable"` the applet history says `success`, the log shows no error, but `| append` writes no file and `$_cli_result` is empty. Only a missing file (`dir unix:`) reveals it. Fix: `action 0.1 cli command "enable"` first.
2. **Pattern that never matches.** `event syslog pattern "%TRACK-6-STATE: 1 ip sla 1 reachability up -> down"` (lowercase): never fires, no history entry, still listed by `show event manager policy registered`. Fix: copy the exact text from `show logging` (case, spaces, `->`).
3. **Self-trigger.** Pattern `%SYS-5-CONFIG_I` with actions `enable`, `configure terminal`, `end`: each run logs a config change that triggers it again: 100+ runs in 3 seconds, history shows the same applet name repeating within one second. Stopped at once by `no event manager applet CONFIG-LOOP`. (An applet matching its own `action syslog msg` does not loop on iol-xe: EEM-generated syslog is not seen by `event syslog`, tested twice.)
4. **Maxrun.** Applet WAIT-LONG (`action wait 30`, default maxrun 20 s): history Status `abort`, the later action never ran.

## Solution Configuration

```
! R1
event manager applet TRACK1-EVIDENCE
 event track 1 state down
 action 0.1 cli command "enable"
 action 1.0 cli command "show clock | append unix:evidence-track.txt"
 action 2.0 cli command "show ip route 0.0.0.0 | append unix:evidence-track.txt"
 action 3.0 cli command "show track 1 | append unix:evidence-track.txt"
 action 4.0 cli command "show ip sla statistics 1 | append unix:evidence-track.txt"
 action 5.0 syslog msg "TRACK1-EVIDENCE saved to unix:evidence-track.txt"
event manager applet SYSLOG-EVIDENCE
 event syslog pattern "%TRACK-6-STATE: 1 ip sla 1 reachability Up -> Down"
 action 0.1 cli command "enable"
 action 1.0 cli command "show clock | append unix:evidence-syslog.txt"
 action 2.0 cli command "show ip route 0.0.0.0 | append unix:evidence-syslog.txt"
 action 3.0 cli command "show track 1 | append unix:evidence-syslog.txt"
 action 4.0 cli command "show ip sla statistics 1 | append unix:evidence-syslog.txt"
 action 5.0 syslog msg "SYSLOG-EVIDENCE saved to unix:evidence-syslog.txt"
event manager applet MANUAL-EVIDENCE
 event none
 action 0.1 cli command "enable"
 action 1.0 cli command "show clock | append unix:evidence-manual.txt"
 action 2.0 cli command "show ip route 0.0.0.0 | append unix:evidence-manual.txt"
 action 3.0 cli command "show track 1 | append unix:evidence-manual.txt"
 action 4.0 cli command "show ip sla statistics 1 | append unix:evidence-manual.txt"
 action 5.0 syslog msg "MANUAL-EVIDENCE saved to unix:evidence-manual.txt"
event manager applet RTT-WATCH
 event timer watchdog time 60
 action 1.0 cli command "enable"
 action 2.0 cli command "show ip sla statistics 1 | include Latest RTT"
 action 3.0 syslog msg "SLA1 $_cli_result"
! remove after 5 minutes
no event manager applet RTT-WATCH
```

The three evidence applets differ only in the event line, the file name and the syslog text. Check the result with `show event manager policy registered`.

## Verification

Silent failure (link stop, 06:03:07): `%TRACK-6-STATE: 1 ip sla 1 reachability Up -> Down` at 06:03:07.319; history: SYSLOG-EVIDENCE and TRACK1-EVIDENCE both `success` 06:03:07; log `%HA_EM-6-LOG: TRACK1-EVIDENCE: TRACK1-EVIDENCE saved to unix:evidence-track.txt`. Each file (755 bytes) holds the clock, `show ip route 0.0.0.0` (already `via 10.0.14.4`, distance 5), `show track 1` (Down, "Tracked by: HSRP, Static IP Routing, EEM applet TRACK1-EVIDENCE") and `show ip sla statistics 1` (return code Timeout, failures 5).

On-demand: `event manager run MANUAL-EVIDENCE` wrote `unix:evidence-manual.txt`; log `%HA_EM-6-LOG: MANUAL-EVIDENCE: ...saved to unix:evidence-manual.txt`.

Watchdog: `RTT-WATCH` logged at 06:06:14 (RTT 3), 06:07:14 (RTT 11), 06:08:14 (RTT 3), every 60 s; after `no event manager applet RTT-WATCH` no more lines. A watchdog timer also fires once immediately when the applet is configured (first run at configuration time), then every 60 s. In one run 4 cycles were observed in total; the full 5 minutes was not observed, so the exact count is not claimed. Remove the applet when done, as it keeps running.

Start state (fresh import): track 1 Up, default static distance 1 via R3, HSRP Active 110 with standby 10.0.10.3, SLA 1 OK, no EEM policies, no evidence files, PC1 pings 10.0.100.3.

## Failure / Recovery Behaviour

- Silent failure R1 e0/0 – R3 e0/0: track Down within about 10 s (frequency 5, timeout 2 s; taken from the LAB-026 measurement for the same SLA, not timed again in this lab); both applets ran once.
- Link start: track 1 Up at 06:04:32 (`delay up 30`); no further run, files unchanged (applets are keyed to `state down`, no duplicate capture).
- R1 was wiped and restarted afterwards; start-state checks matched.

## Answers to Analysis Questions

Q1. The track event is more robust: it fires from the tracking object itself, whatever the message text, severity or logging configuration. A syslog pattern depends on the exact text (observed: a lowercase pattern silently never fires), on logging being generated, and breaks if the message format changes. The pattern is the choice when no object exists for the event.
Q2. `enable` raises the EEM CLI session to privileged mode. Without it nothing worked in these tests: the history said `success`, but no `| append` file was written and `$_cli_result` stayed empty, and nothing was logged. Only the absence of the file (`dir unix:`) shows it. (The original plan premise, that the same show works without `enable` in one applet, did not reproduce.)
Q3. A timestamp, the route as the failure left it, the track and probe state (return code, failure counter) and a pointer to where the file is. Observed: by the time the applet ran, the default route was already via 10.0.14.4 (distance 5), observed once; EEM and static routing are both track clients with no documented order between them, so do not rely on it. Here the evidence shows the new state and the track/SLA lines show the reason, so also capture earlier state with a periodic applet or the log.
Q4. EEM runs inside the device's own operating system, so it can only act on and record what that device sees, and it can do nothing when that device is down or isolated. Evidence for that case must come from off-box sources: syslog or SNMP sent to a collector, or an applet on a peer device. (On this bench EEM runs only on the iol-xe routers; the unmanaged switches and the ioll2-xe image have none.)

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-25 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), iol-xe (IOS XE 17.16.1a), unmanaged_switch |
