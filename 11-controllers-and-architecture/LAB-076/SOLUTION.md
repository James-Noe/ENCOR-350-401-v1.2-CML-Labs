# LAB-076 — Solution

## Summary

LAB-076 teaches how a controller's northbound API is used by a script (token authentication, intent reads, the asynchronous 202 + task + file pattern, expiry handling) and how to judge AI-driven assurance and an assistant's proposed change on evidence. Blueprint mapping: 4.5:A (Catalyst Center workflows and AI-driven assurance, assessed from the issue data), 6.4:P (a controller REST API used from Python, compared with the SD-WAN Manager API of LAB-073), 6.5:R (status codes, 202/401/403/404, error bodies, retry rules). There is no network device: the lab is one Ubuntu node running a stand-in that serves fixtures.

**Derived material.** Every Catalyst Center response is a `(derived)` fixture. Field names and paths follow the Cisco Catalyst Center Intent API reference as known at build time (`/dna/system/api/v1/auth/token`; `network-device`; `site-health`; `issues`; `network-device-poller/cli/read-request`; `task/{id}`; `file/{id}`; the 202 body `{"response": {"taskId", "url"}, "version"}`, a task body with `startTime`/`endTime`/`progress`/`isError`/`failureReason`, `progress` carrying `{"fileId": ...}`, a file body with `commandResponses` SUCCESS/FAILURE/BLACKLISTED). The reference pages (developer.cisco.com/docs/dna-center) could not be consulted from the build environment, so exact field coverage is by memory and the earlier A2 fixtures (LAB-062 `catc-network-device.json`, `catc-task.json`); values are invented. The `/issues` fields (`issueId`, `name`, `siteId`, `deviceId`, `deviceRole`, `aiDriven` "YES"/"NO", `clientMac`, `issue_occurence_count`, `last_occurence_time` epoch ms, `status`, `priority`, `category`, string `totalCount`) were aligned with the Intent API spec 2.3.7.10. The `description`, `baseline`, `observed`, `confidence` and `suggestedActions` blocks are NOT in that schema: they are an invented rendering of what the AI issue UI shows, kept so the evidence exists, and disclosed in LAB.md. `GET /network-device/count` (used by `expiry.py`) is listed in LAB.md's extract. Deviations from the real product, stated in LAB.md: token lifetime 10 minutes instead of 60; `GET /issues` in the real product is superseded by the assurance data API in recent releases; the command runner here completes after about 3.6 s.

## Intentional Faults

None (analysis lab).

## Diagnosis / Methodology

1. **Authenticate (R1).** `POST .../auth/token` with HTTP Basic returns `{"Token"}`; every intent call then sends `X-Auth-Token`. Compare: LAB-060 RESTCONF sends Basic credentials (username and password, reusable) on every request and nothing expires; LAB-073 logs in once with `j_security_check` (form post), keeps a session cookie (JSESSIONID) and fetches an XSRF token (`X-XSRF-TOKEN`) that must accompany writes, the session idling out on the Manager; LAB-076 sends the password once, then a bearer token that expires after a fixed time (10 min here, 60 in the product). Theft: Basic = the password itself, valid until changed and reusable on every interface that accepts the account; session cookie = full use of the session (reads and, after `GET /dataservice/client/token`, writes) until idle timeout or logout; the XSRF token only stops cross-site request forgery from a browser, it is no protection against a stolen cookie (LAB-073 R4 row D); token = the account's API rights until expiry (10 min here), but not the password, and it can be revoked by expiry rather than a password change. All three are sent in clear inside TLS only: pinning the certificate matters in all three.
2. **Assurance (R2).** Site health: HQ 86 (6 of 7 devices healthy, access layer 67), BR1 50 (the only device is only ping-reachable). Issue ISS-0001 (HQ-ACC3 unreachable, P1, `aiDriven: "NO"`) is an Assurance workflow issue produced by a fixed rule (reachability lost for more than N polls). Device-level evidence: ping and traceroute to 10.255.10.13 from a device in the same site, `show interfaces status`/`show ip interface brief` on the upstream distribution switch for the access port or uplink, `show logging` and syslog/SNMP trap history (power, link down), `show cdp neighbors` on the distribution switch, and the device console. Issue ISS-0002 (abnormal DHCP response, P2, `aiDriven: "YES"`) is also an Assurance issue (AI-driven, baseline model). Workflow answer for both issues: the Assurance workflow; the difference is how each issue is raised, ISS-0001 by a fixed threshold rule (`aiDriven: "NO"`, confirmed by a reachability check) and ISS-0002 by a learned baseline (`aiDriven: "YES"`, confirmed by checking the baseline's training days against the observation window); its suggested action would run in the Provision workflow (template deployment). Device-level evidence: `show ip dhcp snooping statistics` and `show ip dhcp binding` on the access switch, `show ip helper-address`/relay settings on the SVI gateway, `debug`-free capture (SPAN/CML capture) of DORA on the client VLAN, server pool utilisation and logs on the DHCP server, STP/uplink counters.
3. **Is the baseline claim supported?** Partly. The baseline (mean 180 ms, sd 60, threshold 360) was learned from 3 days that are Friday, Saturday, Sunday; the observation is Monday 07:35 to 07:55, the morning log-on peak, a load the baseline has never seen. HQ-ACC1 (6 clients, mean 920 ms, p95 1480 ms) is far above even a fair threshold; HQ-ACC2 (41 clients, mean 340 ms) is below the 360 ms threshold; HQ-ACC3 has no clients because it is down (ISS-0001). Only 6 of 212 clients saw timeouts, all on one switch. The claim "DHCP is abnormal at HQ" is not supported site-wide, and "the access switches are missing a standard configuration" is not in the data at all (no configuration or compliance data is shown, the confidence figure of 87% is unexplained).
4. **Command runner (R3).** `POST .../cli/read-request` answers 202 with a task id and URL: the request was accepted, nothing has run. Poll `task/{id}` until `endTime` is present; `isError: true` ends the task with `failureReason`; on success `progress` is a JSON string holding the `fileId`, fetched from `file/{id}`. For the unreachable HQ-ACC3 the task ends with `isError: true`, `failureReason` "NCCP-10017: Unable to establish SSH session to HQ-ACC3 (10.255.10.13): connection timed out". A command the device rejects (`show foo`) is not a task error: it appears under `FAILURE` in the file. The stand-in refuses a non-show command with 400 at request time; the real command runner accepts the request and reports the command under `BLACKLISTED` in the result file `(derived)`.
5. **Expiry (R4).** Any intent call with an expired token returns 401 with a JSON body. The client re-authenticates once, retries the failed call once, and raises if it fails again (no loop). Connection errors are retried a bounded number of times; a restarted stand-in forgets all tokens and tasks, so the first call after the outage returns 401 and the one re-authentication follows.
6. **Critique of the assistant (R5).** For: the DHCP symptom exists on HQ-ACC1 (920 ms vs 180 ms baseline, 6 clients); DHCP snooping rate-limit and trust templates are common practice. Against: the evidence points at one switch, not all access switches; the trigger (Monday morning peak vs a weekend-only baseline) is a baseline artefact until proven otherwise; ACC2 is within threshold; ACC3 is unreachable so a push would fail there; "missing DHCP configuration" is asserted without any config or compliance data; the template enables DHCP snooping and `limit rate 15` on 24 ports, which can drop legitimate bursts and, with `trust` only on the C9200L uplinks listed, break DHCP for every user on a switch whose uplinks use other interfaces (the template assumes port numbering); `no ip dhcp snooping information option` changes relay behaviour; "forced, no pre-checks" and "rollback not needed" are not acceptable; blast radius = every access switch in HQ at once (about 212 clients). Controls: change ticket with approval, canary on one switch (HQ-ACC1), pre-checks (read-only command runner: `show running-config | include dhcp`, `show ip dhcp snooping`, `show interfaces trunk`, baseline DORA time), staged waves, rollback template ready, post-checks (same commands, DORA time via `issues`/client health, `site-health`), stop rule. API calls to verify: `GET task/{id}` for each deployment until `endTime` and `isError: false`, then command-runner reads and `GET issues`/`site-health`; device-side: `show ip dhcp snooping statistics` (drops = 0), `show ip dhcp binding` entries present, client DHCP success from a test client.

## Solution Configuration

No device configuration. The reference scripts, as tested on AUTO-MGMT1 in `/home/cisco/catc/work/` (run with `python3`; `catc.py` is the shared library):

`catc.py`
```python
#!/usr/bin/env python3
"""Reference client for the Catalyst Center stand-in (LAB-076 solution)."""
import json, sys, time
import requests

BASE = "https://127.0.0.1:9443"
CERT = "/home/cisco/catc/certs/catc.pem"
AUTH = ("catc-api", "Sandbox#2026")


class TaskError(Exception):
    pass


class Catc:
    def __init__(self):
        self.s = requests.Session()
        self.s.verify = CERT          # pinned self-signed certificate
        self.token = None
        self.logins = 0

    def login(self):
        r = self.s.post(BASE + "/dna/system/api/v1/auth/token", auth=AUTH, timeout=10)
        r.raise_for_status()
        self.token = r.json()["Token"]
        self.logins += 1

    def call(self, method, path, check=True, **kw):
        """One re-authentication on 401, then give up (no loop). Bounded retry on connection errors.
        check=True: any non-2xx answer (also a second 401) raises with the status and the body, so a script
        never indexes ["response"] of an error body."""
        reauthed = False
        for attempt in range(1, 6):
            try:
                if self.token is None:
                    self.login()
                r = self.s.request(method, BASE + path, headers={"X-Auth-Token": self.token}, timeout=10, **kw)
            except requests.ConnectionError as e:
                print("  connection error (attempt %d): %s" % (attempt, type(e).__name__), file=sys.stderr)
                self.token = self.token  # unchanged; a restarted server will answer 401 next
                time.sleep(3)
                continue
            if r.status_code == 401 and not reauthed:
                print("  401 -> re-authenticating once", file=sys.stderr)
                reauthed = True
                self.token = None
                continue
            if check and not 200 <= r.status_code < 300:
                raise RuntimeError("%s %s -> HTTP %s: %s" % (method, path, r.status_code, r.text[:200]))
            return r
        raise RuntimeError("giving up on %s %s" % (method, path))

    def run_command(self, device_id, command):
        r = self.call("POST", "/dna/intent/api/v1/network-device-poller/cli/read-request",
                      json={"name": "read-only", "commands": [command], "deviceUuids": [device_id], "timeout": 60}, check=False)
        if r.status_code != 202:
            raise TaskError("request refused: %s %s" % (r.status_code, r.text))
        url = r.json()["response"]["url"]            # /api/v1/task/<id>: the reference uses the intent prefix
        tid = url.rsplit("/", 1)[1]
        for _ in range(30):
            t = self.call("GET", "/dna/intent/api/v1/task/" + tid).json()["response"]
            if t.get("isError"):
                raise TaskError(t.get("failureReason") or t.get("progress"))
            if "endTime" in t:
                fid = json.loads(t["progress"])["fileId"]
                return self.call("GET", "/dna/intent/api/v1/file/" + fid).json()
            time.sleep(1)
        raise TaskError("timeout waiting for task " + tid)
```

`inventory.py` (R1)
```python
#!/usr/bin/env python3
from catc import Catc
c = Catc()
devs = c.call("GET", "/dna/intent/api/v1/network-device").json()["response"]
print("%-10s %-15s %-9s %-15s %-14s %s" % ("hostname", "platform", "software", "reachability", "role", "id"))
for d in devs:
    print("%-10s %-15s %-9s %-15s %-14s %s" % (d["hostname"], d["platformId"], d["softwareVersion"], d["reachabilityStatus"], d["role"], d["id"]))
print("logins:", c.logins)
```

`cmdrun.py` (R3, usage `python3 cmdrun.py "show version" HQ-DIST1 HQ-ACC3`)
```python
#!/usr/bin/env python3
import sys
from catc import Catc, TaskError
c = Catc()
devs = {d["hostname"]: d["id"] for d in c.call("GET", "/dna/intent/api/v1/network-device").json()["response"]}
for host in sys.argv[2:] or ["HQ-DIST1", "HQ-ACC3"]:
    print("== %s: %s" % (host, sys.argv[1] if len(sys.argv) > 1 else "show version"))
    try:
        res = c.run_command(devs[host], sys.argv[1] if len(sys.argv) > 1 else "show version")
        for r in res:
            for cmd, out in r["commandResponses"]["SUCCESS"].items():
                print(out)
            for cmd, out in r["commandResponses"]["FAILURE"].items():
                print("FAILED:", cmd, out)
    except TaskError as e:
        print("task failed:", e)
```

`expiry.py` (R4, usage `python3 expiry.py 60 780`: one call every 60 s for 780 s)
```python
#!/usr/bin/env python3
"""Call the API every INTERVAL seconds for DURATION seconds; show the one re-login at expiry."""
import sys, time
from catc import Catc
interval, duration = int(sys.argv[1]), int(sys.argv[2])
c = Catc(); t0 = time.time()
while time.time() - t0 < duration:
    before = c.logins
    r = c.call("GET", "/dna/intent/api/v1/network-device/count")
    print("%4ds status %s logins %d%s" % (time.time() - t0, r.status_code, c.logins, "  <- re-authenticated" if c.logins > before and before else ""), flush=True)
    time.sleep(interval)
```

`assurance.py` (R2) prints the site health and the issues with the baseline and observed samples (its output is below)
```python
#!/usr/bin/env python3
from datetime import datetime, timezone
from catc import Catc
c = Catc()
api = "/dna/intent/api/v1/"
devs = {d["id"]: d["hostname"] for d in c.call("GET", api + "network-device").json()["response"]}
for s in c.call("GET", api + "site-health").json()["response"]:
    print("site %-22s health %3d devices %d clients %d" % (s["siteName"], s["networkHealthAverage"], s["numberOfNetworkDevice"], s["numberOfClients"]))
iss = c.call("GET", api + "issues").json()
print("totalCount:", iss["totalCount"])
for i in iss["response"]:
    last = datetime.fromtimestamp(i["last_occurence_time"] / 1000, timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
    print("%s [%s %s] aiDriven=%s device=%s role=%s count=%d last=%s UTC" % (i["issueId"], i["priority"], i["category"], i["aiDriven"], devs[i["deviceId"]], i["deviceRole"], i["issue_occurence_count"], last))
    print("  " + i["name"])
    b = i.get("baseline")
    if b:
        print("  baseline: mean %s sd %s from %s (%s)" % (b["mean"], b["stdDev"], b["learnedFrom"], "/".join(b["learnedDayTypes"])))
        for o in i["observed"]["samples"]:
            print("  observed %-9s clients %-3d mean %s p95 %s" % (o["device"], o["clients"], o["meanMs"], o["p95Ms"]))
        print("  clients with timeouts %d of %d" % (i["observed"]["clientsWithTimeouts"], i["observed"]["totalClientsAtSite"]))
```

Its output is below. A student's equivalent using `urllib` from the standard library is acceptable (certificate pinned with `ssl.create_default_context(cafile=...)`).

## Verification

Captured on the built lab (R1 to R3 run in one pass; the last two calls show a rejected device command and a refused non-show command: the 400 is the stand-in's behaviour, the real runner reports it under `BLACKLISTED`):

```
== AUTO-MGMT1 ==
cd /home/cisco/catc/work && python3 inventory.py
hostname   platform        software  reachability    role           id
HQ-CORE1   C9500-24Y4C     17.9.4    Reachable       CORE           5b1e0c2a-7d3f-4a10-9c11-000000000001
HQ-DIST1   C9300-48UXM     17.9.4    Reachable       DISTRIBUTION   5b1e0c2a-7d3f-4a10-9c11-000000000002
HQ-DIST2   C9300-48UXM     17.9.4    Reachable       DISTRIBUTION   5b1e0c2a-7d3f-4a10-9c11-000000000003
HQ-ACC1    C9200L-24P-4G   17.9.3    Reachable       ACCESS         5b1e0c2a-7d3f-4a10-9c11-000000000004
HQ-ACC2    C9200L-48P-4G   17.9.3    Reachable       ACCESS         5b1e0c2a-7d3f-4a10-9c11-000000000005
HQ-ACC3    C9200L-24P-4G   17.6.5    Unreachable     ACCESS         5b1e0c2a-7d3f-4a10-9c11-000000000006
HQ-EDGE1   ISR4331/K9      17.9.4    Reachable       BORDER ROUTER  5b1e0c2a-7d3f-4a10-9c11-000000000007
BR1-RTR1   C8000V          17.12.2   Ping Reachable  BORDER ROUTER  5b1e0c2a-7d3f-4a10-9c11-000000000008
logins: 1
cd /home/cisco/catc/work && python3 assurance.py
site Global/Veridian/HQ     health  86 devices 7 clients 212
site Global/Veridian/BR1    health  50 devices 1 clients 19
totalCount: 2
ISS-7f31a9c0-0001 [P1 Availability] aiDriven=NO device=HQ-ACC3 role=ACCESS count=72 last=2026-10-12 07:58:11 UTC
  Network Device HQ-ACC3 is unreachable from Catalyst Center
ISS-7f31a9c0-0002 [P2 Onboarding] aiDriven=YES device=HQ-ACC1 role=ACCESS count=4 last=2026-10-12 07:55:00 UTC
  Abnormal DHCP response time at HQ (AI-driven)
  baseline: mean 180 sd 60 from 2026-10-09 to 2026-10-11 (Friday/Saturday/Sunday)
  observed HQ-ACC1   clients 6   mean 920 p95 1480
  observed HQ-ACC2   clients 41  mean 340 p95 520
  observed HQ-ACC3   clients 0   mean None p95 None
  clients with timeouts 6 of 212
cd /home/cisco/catc/work && python3 cmdrun.py "show ip dhcp snooping statistics" HQ-DIST1 HQ-ACC3
== HQ-DIST1: show ip dhcp snooping statistics
Packets Forwarded                                     = 18402
Packets Dropped                                       = 0
Packets Dropped From untrusted ports                  = 0
== HQ-ACC3: show ip dhcp snooping statistics
task failed: NCCP-10017: Unable to establish SSH session to HQ-ACC3 (10.255.10.13): connection timed out
cd /home/cisco/catc/work && python3 cmdrun.py "show foo" HQ-ACC1
== HQ-ACC1: show foo
FAILED: show foo % Invalid input detected at '^' marker.
cd /home/cisco/catc/work && python3 cmdrun.py "configure terminal" HQ-ACC1
== HQ-ACC1: configure terminal
task failed: request refused: 400 {
  "response": {
    "errorCode": "INVALID_INPUT",
    "message": "Only read-only show commands are supported",
    "detail": "configure terminal"
  },
  "version": "1.0"
}
```

V7, request log of the stand-in (`/home/cisco/catc/logs/requests.log`):

```
2026-10-12T15:59:53 127.0.0.1 "POST /dna/intent/api/v1/network-device-poller/cli/read-request HTTP/1.1" 202 -
2026-10-12T15:59:53 127.0.0.1 "GET /dna/intent/api/v1/task/1f44d2c8-0d94-4c4e-9961-9478033220d2 HTTP/1.1" 200 -
2026-10-12T15:59:54 127.0.0.1 "GET /dna/intent/api/v1/task/1f44d2c8-0d94-4c4e-9961-9478033220d2 HTTP/1.1" 200 -
2026-10-12T16:25:06 127.0.0.1 "GET /dna/intent/api/v1/network-device/count HTTP/1.1" 401 -
2026-10-12T16:25:06 127.0.0.1 "POST /dna/system/api/v1/auth/token HTTP/1.1" 200 -
```

R4 across a real expiry (`python3 expiry.py 60 780`, token issued at 16:15:05):

```
 540s status 200 logins 1
  401 -> re-authenticating once
 600s status 200 logins 2  <- re-authenticated
 660s status 200 logins 2
 720s status 200 logins 2
```

Stand-in unchanged: no write other than the token request and the command-runner read request is accepted (`POST`/`PUT`/`PATCH`/`DELETE` elsewhere return 403 `FORBIDDEN`).

## Failure / Recovery Behaviour

Method: the stand-in is a service on the host; "restart" is `systemctl stop catc-mock`, 8 s, `systemctl start catc-mock` while the R4 script (`expiry.py 3 45`) runs. Captured: calls succeed until the stop, then three `ConnectionError` retries (3 s apart), the first answer after start is 401 (tokens are in memory), one re-authentication, then 200 until the end (`logins 2`).

| Scenario (trigger, end condition) | Runs (raw) | Documented range | Basis |
|---|---|---|---|
| Token lifetime: token issued, first 401 on a 2 s poll | 601.4 s, 600.3 s, 600.7 s | 598 to 604 s | `CATC_TOKEN_TTL=600` plus the 2 s poll interval and request time |
| Command-runner task, success: POST accepted, `endTime` seen by the client (whole `cmdrun.py` run) | 3.60 s, 3.60 s, 3.61 s | 3 to 6 s | task completes 3 s after the POST, client polls every 1 s, plus 0.6 s process start-up |
| Command-runner task, device unreachable: POST accepted, `isError: true` seen | 3.62 s, 3.62 s, 3.56 s | 3 to 6 s | same fixed 3 s task time |
| Service stop for 8 s while `expiry.py` runs: stop, first 200 after start | 1 run: stop at about 15 s, first 200 at 24 s (9 s) | 8 to 20 s | 3 retries x 3 s plus the 8 s outage; one run (not timing-critical, recorded only) |
| Boot: lab start, `catc-mock` active | CML BOOTED 86 s; service active 67 s after OS boot | 70 to 150 s | cloud-init run time on an idle server |

## Answers to Analysis Questions

**Q1.** A 202 promises that the request was accepted for processing and that the response carries a handle (`taskId` and URL) with which to ask about the outcome. It does not promise that the work has started, that it will succeed, or when it finishes; the final result is only known from the task (`endTime`, `isError`, `failureReason`) and, for command runner, from the file. A script that treats 202 as success will report success for a task such as HQ-ACC3's that fails after 3 s.

**Q2.** Intent APIs describe outcomes (device, site, issue, template) instead of exposing the CLI. This helps: one interface for many platforms and releases, validated input, no screen-scraping, RBAC and audit in one place, tasks are traceable. It hurts when the symptom lives below the abstraction: the API says "unreachable" or "abnormal DHCP time", but the cause (a port error, a relay setting, an STP state) is only visible in device state. The command runner is the bridge, and it is limited to read-only `show` commands and to reachable devices; so keep the CLI evidence skills.

**Q3.** A threshold fires at a fixed number and either misses slow degradation below it or flags normal peaks above it. A baseline learns what is normal for this site and time pattern and can flag a deviation that is small in absolute terms (a quiet branch whose DHCP time doubles) or suppress a known peak. It explains nothing: it says "different from what I learned", not why; its quality depends on the training window (here Friday to Sunday only, so a Monday peak looks abnormal), the number of samples (6 clients) and hidden confidence figures. The engineer still needs device evidence to give a cause.

**Q4.** For an unattended nightly job: the Catalyst Center token model (this lab), with a dedicated read-only service account, the password in a secret store rather than in the script, a short-lived token requested at the start of each run, a re-authentication on 401 limited to one retry, and the pinned certificate. RESTCONF with Basic keeps a reusable password in every request and has no expiry (but also no session to lose mid-run, and works without a controller). SD-WAN Manager (LAB-073) needs a session cookie plus XSRF handling, session idle timeouts and a form login: more moving parts, no advantage for a batch job. Any choice also needs account scoping (read-only), logging of the account's calls, and a certificate check.

**Q5.** Treat it as a change: scope and approval; read-only inventory and pre-checks (reachability, software, current config via command runner), skip or fix unreachable devices; a canary switch, then waves (for example 1, 10, 50, rest) with a soak and a stop rule after each; asynchronous handling (poll each task to `endTime`, never assume 202 means done, record `isError` and `failureReason`); post-checks (device show commands, client health, assurance issues); idempotent templates with a tested rollback template; rate limiting and bounded retries; logs and a report per wave; a maintenance window and a way to pause (stop launching new tasks).

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-17 |
| CML | 2.10.0 |
| Node types | ubuntu (Ubuntu 24.04) |
