# LAB-065 — Solution

## Summary

A troubleshooting lab on one automation pod after an AAA migration. Three tickets, five faults, in two series (T1 F1 then T2 F2 then F3; T3 F4 then F5). The student must separate identification (who is the caller) from permission, the account from the central server, the device and the client, and a payload error from a method error from a transient lock; and must fix the job so that it is idempotent without weakening the pod's hardening.

Blueprint mapping (kept out of LAB.md): 4.6:T (AAA, local fallback), 6.2:T (JSON payload error in T3), 6.5:T (Catalyst Center asynchronous task, Q6 on a derived fixture), 5.1.b:T (device access control on the API), 5.3:P (RADIUS, central authentication), 6.6:T (EEM applet).

## Intentional Faults

| ID | Device | Change | Symptom |
|---|---|---|---|
| F1 | AUTO-RTR3 | The migration created `VTY-LOGIN`, `VTY-AUTHZ`, `API-LOGIN` (all `group RAD-GRP local`) and `ip http authentication aaa login-authentication API-LOGIN`, but `aaa authentication login default local` was left. RESTCONF on cat8000v 17.16.1a ignores the `ip http authentication` lists and authenticates through the **default** login list (measured on cat8000v 17.16.1a). The privilege still comes from the account (local level or the RADIUS reply): a priv-1 account gets 403 (LAB-061 V6) | `apijob` (central only) gets 401 `access-denied` on every call; DC-AAA1 sees no request; SSH with `apijob` works (priv 15); `test aaa` authenticates; local `apiuser`/`admin` still get 200 |
| F2 | AUTO-MGMT1 `/home/cisco/jobs/desc.json` | `"enabled": "True"` (string) instead of boolean `true` | step 1 PATCH 400 `malformed-message`, error-path `/ietf-interfaces:interfaces`, message names `enabled` and the value |
| F3 | AUTO-MGMT1 `nightly.py` step 2 | POST of Loopback101 on the parent `ietf-interfaces:interfaces` instead of an idempotent write; the helper treats every 409 as a datastore lock | 409 `data-exists` six times (waits 2..12 s), `FAILED (no usable answer)` after 44 s |
| F4 | AUTO-RTR1 | `event syslog pattern "LINEPROTO-5-UPDOWN.*ethernet0/2.*down"` (lower case; the message says `Ethernet0/2`) | applet never fires: empty `show event manager history events | include UPLINK`, no file |
| F5 | AUTO-RTR1 | action `show ip ospf neighbor | include FULL | append unix:uplink-evidence.txt` (second pipe after the first) | with F4 fixed: history shows `Actv success` and the applet's own `uplink evidence saved` line, but `dir unix:` shows no file |

F1 and the break-glass accounts: before the fix `apiuser` and `admin` get 200 on RESTCONF, which violates the design intent (accepted only when RADIUS does not answer). The cause is F1 itself: RESTCONF uses the default login list, which stays `local` only, so the local accounts are checked and RADIUS is never asked. After the fix the default list is `group RAD-GRP local`, so a local account is accepted only when DC-AAA1 does not answer; an Access-Reject from DC-AAA1 is final and gives 401 (measured in Failure / Recovery).

Series: F1 hides everything behind it (every call 401). F2 stops the job at step 1, so F3 (step 2) is only seen after F2 is fixed. F5 hides behind F4. T1/T2 and T3 are independent.

## Diagnosis / Methodology

**T1 (401 for every call).**
1. Transport and TLS: `curl --cacert` returns an HTTP 401 with a RESTCONF error body and `WWW-Authenticate: Basic realm="restconf"`: TCP, TLS (trust file) and the access class are fine; `show ip http server status` shows the secure server enabled and access class `API-CLIENTS`; `show platform software yang-management process` shows `nginx` and `dmiauthd` running. `-k` does not change a 401 (and weakens the client: V3).
2. Account and central server: `test aaa group RAD-GRP apijob Job#Pass2026 legacy` -> `User was successfully authenticated.`; DC-AAA1 log shows `Login OK: [apijob]` for SSH/test but **no entry for the RESTCONF calls**: the request never reaches RADIUS. SSH with `apijob` lands in privilege 15 (`show privilege`), so authorisation data is fine too. RADIUS reachability, key, routing and the account are ruled out.
3. Which list does the HTTP service use? `show ip http server status` says `aaa login authentication list: API-LOGIN`, and `API-LOGIN` is correct (`group RAD-GRP local`): this is the red herring. Testing the other accounts shows that local `apiuser` and `admin` get 200: the service still authenticates against the local database, i.e. the default login list. `show running-config | include ^aaa authentication login` shows `default local`.
4. Wrong fixes tried and rejected: `-k` (401, weakens the client), `ip http authentication local` (401; `apijob` has no local account; RESTCONF ignores the list), a local `username apijob privilege 15` (200, but the account is no longer central and now exists twice: V2), running the job as `apiuser`/`admin` (works only while the default list is `local`; breaks the shift rule and is refused after the fix).

**T2 (after login).** Run the job again after the fix: step 0 is 200, step 1 fails with 400. The body names the leaf and the value (`invalid value for: enabled ... "True" is not a valid value`): payload, not URL or method. `jq '.["ietf-interfaces:interfaces"].interface[0].enabled|type' desc.json` -> `"string"`; the YANG type is boolean. Fix, run again: step 1 204, step 2 fails: six 409s. The log line says only "409, assuming a lock"; run the same call with `curl` to read the `error-tag`: `data-exists`, not `lock-denied`. A lock clears by itself (`show platform software yang-management process` has no sync in progress at job time); `data-exists` means the object is already there, so POST is the wrong method. Widening the retry loop (MAX_TRIES 10, WAIT 1) ends in `gave up after 10 attempts`: V4.

**T3 (no evidence file).** The event is generated: a cable pull (`shutdown` on RTR1 e0/2 and RTR3 Gi2) puts `%LINEPROTO-5-UPDOWN: ... Ethernet0/2, changed state to down` in RTR1's log. `show event manager policy registered` lists `UPLINK-EVIDENCE`, but `show event manager history events | include UPLINK` stays empty after the pull: the pattern does not match (case-sensitive regex). After the fix the history shows the run and `uplink evidence saved`, but `dir unix:` has no file: `debug event manager action cli` (read with `show logging | include HA_EM`) shows the command and an empty output, no error. Splitting the command shows that `show ip ospf neighbor | append unix:uplink-evidence.txt` (one pipe) writes the file; `| redirect` followed by another pipe also writes nothing.

Ruled out as the cause: RADIUS reachability and keys, OSPF/route to DC (module 03/05), NTP/time, TLS trust, the 02:10 flap itself (genuine; documented, not to be fixed).

## Solution Configuration

AUTO-RTR3:
```
aaa authentication login default group RAD-GRP local
```
(The console keeps `aaa authentication login CON none`, so a lock-out is impossible.)

AUTO-MGMT1 (as `cisco`, in `/home/cisco/jobs`):
```
sed -i 's/"True"/true/' desc.json
sed -i 's#call(session, "POST", f"{BASE}/ietf-interfaces:interfaces", LOOPBACK)#call(session, "PUT", f"{BASE}/ietf-interfaces:interfaces/interface=Loopback101", LOOPBACK)#' nightly.py
```

AUTO-RTR1:
```
event manager applet UPLINK-EVIDENCE
 event syslog pattern "LINEPROTO-5-UPDOWN.*Ethernet0/2.*down"
 no action 1.1
 action 1.1 cli command "show ip ospf neighbor | append unix:uplink-evidence.txt"
```
(`| include FULL` is dropped, so the evidence file holds the whole neighbour table.)

## Verification

Captured on a fresh import of the YAML; causality tested one fix at a time.

Start state (V1 negative):
```
step 0 read interfaces: FAILED 401 { "ietf-restconf:errors": ...
apijob 401   netadmin 401   apiuser 200   admin 200
SSH-OK apijob Current privilege level is 15
SSH-FAIL apiuser NetmikoAuthenticationException
RTR3# show running-config | include ^aaa authentication login default
aaa authentication login default local
```
After F1 (symptom 401 gone; next failure is step 1):
```
apijob 200   netadmin 200   apiuser 401   admin 401
step 0 read interfaces: 200 ok
step 1 set descriptions: FAILED 400 ... "error-tag": "malformed-message", "error-path": "/ietf-interfaces:interfaces",
 "error-message": "invalid value for: enabled in /if:interfaces/if:interface[if:name='GigabitEthernet1']/if:enabled: \"True\" is not a valid value."
```
After F2 (step 1 204; next failure is step 2):
```
step 1 set descriptions: 204 ok
  POST 409 (attempt 1), assuming a lock, waiting 2 s ... (attempt 6) waiting 12 s
  POST: gave up after 6 attempts
step 2 ensure Loopback101: FAILED (no usable answer)
curl POST: {"error-type":"application","error-tag":"data-exists", "error-message":"object already exists: /if:interfaces/if:interface[if:name='Loopback101']"}
```
After F3 (V1, V5), three consecutive runs, each `EXIT=0`:
```
step 0 read interfaces: 200 ok / step 1 set descriptions: 204 ok / step 2 ensure Loopback101: 204 ok / job complete
RTR1# show ip route 10.255.90.101 | include ago      (before run 2)   00:06:12 ago
RTR1# show ip route 10.255.90.101 | include ago      (after run 3)    00:06:16 ago
```
V7 / V2 (RTR3 log, only effective changes are logged; identical PUT leaves no entry):
```
%DMI-5-AUTH_PASSED: ... User 'apijob' authenticated successfully from 10.90.50.31:0 for rest over http. External groups: PRIV15
%DMI-5-CONFIG_I: R0/0: dmiauthd: Configured from NETCONF/RESTCONF by apijob, transaction-id 98
```
DC-AAA1 log: `Auth: Login OK: [apijob]`, `Login incorrect (No Auth-Type found: rejecting the user via Post-Auth-Type = Reject): [apiuser/Api#Pass2026]` (a reject is final, no local fallback while the server answers).

V3: `show ip http server status` unchanged (`HTTP secure server status: Enabled`, `HTTP server IPv4 access class: API-CLIENTS`); plain HTTP to RTR3 gives connection refused; the job still uses `session.verify = /home/cisco/trust/rtr3.pem`.

T3 after F4 (history entry, still no file) and after F5:
```
%LINEPROTO-5-UPDOWN: Line protocol on Interface Ethernet0/2, changed state to down      18:58:56.128
%HA_EM-6-LOG: UPLINK-EVIDENCE: uplink evidence saved                                     18:58:56.653
10  12  Actv success  Sun Oct11 18:58:56 2026  syslog  applet: UPLINK-EVIDENCE
RTR1# more unix:uplink-evidence.txt
Neighbor ID     Pri   State           Dead Time   Address         Interface
10.255.50.1       0   FULL/  -        00:00:39    10.90.255.129   Ethernet0/3
```
(The RTR3 adjacency is already gone when the command runs, so one neighbour remains.)

Traps tried on the build lab: `curl -k` 401; `ip http authentication local` 401; local `apijob` user 200 (wrong); DELETE + POST of Loopback101 works but the route age resets (`Last update ... 00:00:00 ago`: V5 breach); widened retries `gave up after 10 attempts`; `| redirect` with a second pipe: no file.

## Failure / Recovery Behaviour

Method: DC-AAA1 `node stop` is a silent failure for RTR3 (RADIUS marked dead after `radius-server dead-criteria time 5 tries 2`, `deadtime 1`); the pull test is `shutdown` on both ends of RTR1 e0/2 and RTR3 Gi2. On DC-AAA1 stop RTR3 logs `%RADIUS-4-RADIUS_DEAD` and `%RADIUS-3-ALLDEADSERVER: Group RAD-GRP: No active radius servers found`, then `%RADIUS-6-SERVERALIVE` on recovery. `apijob` stays refused (401, no local account); `apiuser` is accepted through the local fallback; `netadmin` is refused (no local account).

| Scenario (trigger -> end condition) | Runs (raw) | Documented range | Basis |
|---|---|---|---|
| `shutdown` of RTR1 e0/2 -> `uplink-evidence.txt` listed by `dir unix:` (tool clock, `--until --every 2`) | 13 s, 9 s, 10 s | 9-13 s (device clock: file saved 0.43 s after the down message, 3 runs) | the tool figure includes about 8 s of console polling; V6's 10 s is met on the device clock |
| `node stop DC-AAA1` -> answer to the first `apijob` request | 10.15 s, 10.21 s, 15.56 s | 10-16 s (outliers 34 s and 86 s seen in idle probes) | dead-criteria 5 s x 2 tries; the job's own 10 s timeout reads it as a ReadTimeout |
| same, later requests while the server is marked dead: `apiuser` 200 / `netadmin` 401 | 0.43, 0.44, 3.75 s then 0.2-0.3 s / 0.05-0.13 s | 0.05-4 s | the group is dead for `deadtime` (1 min), requests go straight to the local fallback |
| `node start DC-AAA1` -> first `apijob` 200 (MGMT1 loop every 3 s) | 56 s, 60 s, 51 s | 45-75 s | RTR3's 60 s deadtime plus a probe and the server's boot (the server answers within about 6 s of the start) |
| cat8000v wipe + start -> RESTCONF 401 | about 18-20 min (1 observation, restore step) | 15-25 min | day-0 applies after a factory-reset reload; `BOOTED` is reported much earlier |

## Answers to Analysis Questions

- **Q1** The access chain, tested part by part: client (trust file and payload unchanged), transport/TLS (HTTP 401 with a RESTCONF body, so the request reached the web server), device (`yang-management` running, `show ip http server status`), central server (`test aaa` and the DC-AAA1 log). Identification vs permission: the first is an HTTP 401 with the account refused before any privilege is looked up; the account that identified itself and was refused leaves a trace on the identity server. Decisive evidence: DC-AAA1 shows no request for `apijob` when the RESTCONF call is made, while `test aaa` and SSH produce `Login OK`: the device never asked RADIUS, so it was consulting another method list. The break-glass accounts getting 200 confirmed it. (Measured on cat8000v 17.16.1a: RESTCONF authenticated through the `default` login list and ignored the `ip http authentication` list; the privilege still comes from the account, local level or the RADIUS reply, and a priv-1 account gets 403 as in LAB-061 V6. A permission failure was not seen here.)
- **Q2** Order: transport and TLS (curl with the trust file gives an HTTP answer), service (yang-management process running), account and server (`test aaa`, server log, SSH with the same account), then device configuration (the list the service uses), then the client (payload, method). RADIUS reachability/keys, routing, NTP and TLS trust are ruled out by the first two groups of tests.
- **Q3** 2xx: done. 400: fix the input, never retry (the body names the leaf). 401/403: fix credentials or permissions or alert; never retry in a loop (lock-outs, noise). 409: read the `error-tag`: `lock-denied` is transient (retry with back-off, bounded), `data-exists` is a method error (use PUT/PATCH). 5xx and no answer: bounded retry with back-off, then alert. 400, 401/403 and `data-exists` are never worth retrying.
- **Q4** Idempotence: PUT of the full object (or PATCH) converges to the same state; an identical second write changes nothing. Proof on this pod: three consecutive runs `EXIT=0`, RTR1's route age keeps increasing (no flap), and the second and third run leave no `%DMI-5-CONFIG_I` entry. POST fails the second night; DELETE+POST works but removes and re-learns the loopback route.
- **Q5** An applet that does not match never runs and logs nothing; one that runs with a bad action only logs its own `syslog` line. Only the registered-policy list, the history and a test (cable pull) show it. Monitor the monitor: a periodic synthetic event or a watchdog that checks the file or the history, an alert on the missing artefact, and a test after every change to the applet.
- **Q6** In the task response: `isError`, `failureReason`, `progress`, `endTime`; the 202 only says the request was accepted. So the job must poll the task by `taskId` and read `isError`/`failureReason` (here "Device 10.10.20.4 unreachable", 2 devices failed). On this pod RESTCONF answered synchronously, so the HTTP status and the error body (`error-tag`, `error-message`) were the whole answer.

Instructor debrief: SSH uses the named `VTY-LOGIN`/`VTY-AUTHZ` lists, RESTCONF (measured on cat8000v 17.16.1a) uses the default login list and ignored the `ip http authentication` list, while the privilege still comes from the account (a priv-1 account gets 403, LAB-061 V6); hence the same account worked over one and not the other (`show ip http server status` showing `API-LOGIN` is misleading). POST creates, so it cannot "ensure" an object exists, while PUT/PATCH converge. The break-glass accounts were refused after the fix because an Access-Reject is final: local fallback applies only when the server does not answer (measured in Failure / Recovery).

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-18 |
| CML | 2.10.0 |
| Node types | cat8000v (IOS XE 17.16.1a), external_connector, iol-xe (IOS XE 17.16.1a), radius, ubuntu (Ubuntu 24.04), unmanaged_switch |
