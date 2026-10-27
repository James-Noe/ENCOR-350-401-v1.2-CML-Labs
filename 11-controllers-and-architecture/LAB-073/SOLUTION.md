# LAB-073 — Solution

## Summary

Educational intent: before touching edges (LAB-074), the student learns the three SD-WAN controller roles from live evidence: Validator = orchestration (Cisco "vBond"), Controller = control (vSmart), Manager = management (vManage); how they trust each other (organisation name, enterprise/Manager-signed certificates, the authorised serial list); how a depot router would join (Validator first, then Manager, then Controller); and how to automate the Manager API safely (session + XSRF token, 180 s timeouts, certificate handling, and detecting an authentication failure by content, not by status code alone). The Controller node stop shows what the control plane looks like during a controller outage and why different observers disagree.

Blueprint mapping: 1.2.a (SD-WAN control and data plane elements), 6.4 (Python/REST automation against a controller), 5.3 (API authentication and session security). Edge-side material (OMP, TLOC, BFD, policy) is not part of this lab: no edges are deployed, because edge onboarding fails on this CML server (tested).

Everything below is captured live on the reference build (Manager 20.16.1, csdwan 3.2.1), except the items marked `(derived)`, which come from Cisco's SD-WAN overlay documentation.

## Intentional Faults

Not a troubleshooting lab: there are no faults. The only trap is observational: the Manager answers an unauthenticated API call with HTTP 200 and an HTML login page (R4), and the Manager's device list flaps during the failure test (R6).

## Diagnosis / Methodology

Evidence path for each requirement:

1. **R1** `GET /dataservice/device` (or Monitor > Devices): three rows, personalities `vmanage`, `vsmart`, `vbond`. Roles: the Validator authenticates and orchestrates the join of devices (orchestration plane), the Controller runs OMP and distributes routes and policy (control plane), the Manager configures and monitors (management plane, NETCONF to devices).
2. **R2** `device/control/connections?deviceId=<system IP>` for 100.0.0.101 and 100.0.0.1, and `device/orchestrator/connections?deviceId=100.0.0.201`. All connections are DTLS, state `up`, port 12346 (the Validator's own view shows the controller-side ports 12446-13046 for the extra Manager sessions).
3. **R3** `settings/configuration/organization`, `settings/configuration/device` (Validator address), `certificate/vsmart/list`, `system/device/vedges`.
4. **R4** curl with a cookie jar, the table in Verification.
5. **R5** a script that checks the login result by content, not by status.
6. **R6** CML node stop; observe control connections on Manager and Validator, not the Manager device list.

Plausible-but-wrong approaches: reading `reachability` from the Manager's device list as the failure signal (it flapped back to `reachable` in one run while the control connection stayed down); treating a 200 as a successful call (an HTML login page is returned for no session and after logout).

## Solution Configuration

No device configuration changes. Student actions are API calls from SDW-MGMT1. Reference commands (all tested):

```
# SDW-MGMT1 (cisco/cisco)
curl -sk -c /tmp/cj -d 'j_username=admin&j_password=EncorSdwan#2026' https://172.16.0.1/j_security_check
TOK=$(curl -sk -b /tmp/cj https://172.16.0.1/dataservice/client/token)
curl -sk -b /tmp/cj -H "X-XSRF-TOKEN: $TOK" https://172.16.0.1/dataservice/device
curl -sk -b /tmp/cj -H "X-XSRF-TOKEN: $TOK" "https://172.16.0.1/dataservice/device/control/connections?deviceId=100.0.0.101"
curl -sk -b /tmp/cj -H "X-XSRF-TOKEN: $TOK" "https://172.16.0.1/dataservice/device/orchestrator/connections?deviceId=100.0.0.201"
curl -sk -b /tmp/cj -X POST -H "X-XSRF-TOKEN: $TOK" https://172.16.0.1/logout
```

R5 reference script (`controllers_report.py`, tested; ran in 2.7 s, wrote a 3-entry report, then removed):

```python
#!/usr/bin/env python3
"""Reference solution R5: Manager session -> report/controllers.json -> logout.
TLS: the Manager certificate is self-signed and issued for no name that matches 172.16.0.1,
so verify=False is used. Risk: a man in the middle on VPN0 could read the credentials.
Acceptable only on this isolated pilot VPN; production pins the enterprise root CA."""
import json, sys, requests, urllib3
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
BASE = "https://172.16.0.1"
T = 180  # real-time endpoints take 60-120 s
def need_json(r):
    """A lost session returns 200 + an HTML page: check status AND content type on every data call."""
    r.raise_for_status()
    if "application/json" not in r.headers.get("Content-Type", ""):
        raise SystemExit("not JSON (Content-Type %r, body starts %r): session lost?" % (r.headers.get("Content-Type"), r.text[:40]))
    return r
s = requests.Session()
s.verify = False
r = s.post(BASE + "/j_security_check", data={"j_username": "admin", "j_password": sys.argv[1]}, timeout=T)
r.raise_for_status()
if "<html" in r.text.lower():
    raise SystemExit("login failed (HTML login page returned with HTTP %d)" % r.status_code)
tok = s.get(BASE + "/dataservice/client/token", timeout=T)
tok.raise_for_status()
s.headers["X-XSRF-TOKEN"] = tok.text
try:
    devs = need_json(s.get(BASE + "/dataservice/device", timeout=T))
    certs = need_json(s.get(BASE + "/dataservice/certificate/vsmart/list", timeout=T))
    cstate = {(c.get("deviceIP") or c.get("configuredSystemIP")): c.get("state") for c in certs.json()["data"]}
    rows = [{"device": d["host-name"], "personality": d["personality"], "system-ip": d["system-ip"],
             "reachability": d["reachability"], "certificate-state": cstate.get(d["system-ip"], "n/a"),
             "control-connections": d.get("controlConnections")} for d in devs.json()["data"]]
    with open("/home/cisco/sdwan/report/controllers.json", "w") as f:
        json.dump(rows, f, indent=2)
    print(json.dumps(rows, indent=2))
finally:
    s.post(BASE + "/logout", timeout=T, allow_redirects=False)
```

TLS handling: `verify=False` with the risk stated (self-signed certificate, issued for no name that matches 172.16.0.1; a man in the middle on VPN 0 could read the credentials). Acceptable only on this isolated VPN; production fetches and pins the enterprise root CA.

## Verification

### R1 inventory (captured)

| Host | Personality | System IP | Site | Version | Reachability | Control conns | Certificate |
|---|---|---|---|---|---|---|---|
| Manager01 | vmanage | 100.0.0.1 | 100 | 20.16.1 | reachable | 2 | Valid |
| Controller01 | vsmart | 100.0.0.101 | 100 | 20.16.1 | reachable | 3 | Valid |
| Validator01 | vbond | 100.0.0.201 | 100 | 20.16.1 | reachable | 10 | Valid |

### R2 control connections (captured, `state: up`, `protocol: dtls`)

- Controller01 (3 rows): vbond 100.0.0.201 (twice, port 12346), vmanage 100.0.0.1 (port 12346).
- Manager01 (2 rows): vsmart 100.0.0.101 and vbond 100.0.0.201, port 12346.
- Validator01 orchestrator view (10 rows in total, vsmart and vmanage sessions on ports 12346 to 13046): the split between the two types varies by deployment (seen: 1 vsmart + 9 vmanage; 2 vsmart on 12346/12446 + 8 vmanage). Do not expect a fixed split: check that the total is 10 and that every row is in state `up`.

### R3 trust records (captured)

- Organisation name: `cml-sdwan-lab-tool`; Validator address: `validator.sdwan.local`, port 12346, pre-shared-key mode false.
- Certificates (`certificate/vsmart/list`): Validator01 serial 28DBF19E...DA541, state `Installed`, valid, expires Oct 11 2028; Manager01 5059618326C1...061D, `vBond Updated`, expires Oct 11 2028; Controller01 590F8172...AD16, `vBond Updated`, expires Oct 11 2028. Root certificate (`certificate/rootcertificate`) is the tool's `sign.sdwan_autopod` root.
- WAN edge list (`system/device/vedges`): 30 rows, all `validity: valid`, `vedgeCertificateState: tokengenerated`, chassis numbers `C8K-...`, `uploadSource: File Upload`, device model `vedge-C8000V-SD-ROUTING`.
- Onboarding sequence `(derived, Cisco SD-WAN overlay documentation)`: the Validator is configured and reachable first (it must be the first contact; its address is the only thing an edge needs besides the organisation name and its credential); the Manager is added next and pushes the authorised serial list to the Validator; then the Controller. A new edge (1) reaches the Validator through any transport, (2) the Validator checks the edge certificate/serial or chassis and token against the authorised list and the organisation name, (3) the edge is told the addresses of the Manager and Controller and the connection to the Validator is dropped, (4) the edge brings up control connections to the Manager (template/configuration push) and the Controller (OMP), then builds BFD/IPsec to other edges. The authorised list lives on the Manager (upload source) and is distributed to the Validator and Controller.

### R4 session and unauthenticated behaviour (captured with curl on SDW-MGMT1, Manager 20.16.1)

| # | Request | Result (measured) |
|---|---|---|
| A | GET /dataservice/device, no session | **200**, `text/html` (the login page, not JSON, not a redirect) |
| A2 | GET /dataservice/client/token, no session | 200, HTML login page |
| A3 | POST /j_security_check, wrong password | 200, 2022-byte HTML login page |
| B | POST /j_security_check, correct | 200, empty body, cookie `JSESSIONID` set |
| C | GET /dataservice/device with cookie | 200 `application/json` |
| D | GET /dataservice/client/token with cookie | 200, token of 100 characters |
| E | POST /dataservice/device/action/status/dummy with cookie, **no** X-XSRF-TOKEN | **403**, `text/html`, "SessionTokenFilter: Token provided via HTTP Header does not match the token generated by the server." |
| F | same POST with X-XSRF-TOKEN | 405 `application/json` (the token passed the filter; the dummy path allows no POST) |
| G | GET /logout with cookie | 405 (logout is POST); the session stays alive (GET device afterwards 200 JSON) |
| N | POST /logout with cookie and token | **302** to `https://172.16.0.1:443/welcome.html?nocache=...` |
| O | GET /dataservice/device with the same cookie after the POST logout | **200**, `text/html` (login page again) |
| P | POST with the old cookie and old token after logout | 200, `text/html` (login page; no 401) |
| J | GET /dataservice/device with HTTP Basic `admin:EncorSdwan#2026` | **200 JSON** (Basic is accepted); wrong password 401 |

Compared with the common expectation (403 for POST without XSRF, 401/302 for no session and after logout): the 403 is confirmed; no session and after logout both return **HTTP 200 with an HTML login page**. The only reliable failure signals are the content type (`text/html` instead of `application/json`), a body containing `<html`, and the absence of the expected JSON keys. R5's script checks `"<html" in response.text` after login for this reason.

### R5 (captured)

```
Manager01    vmanage 100.0.0.1    reachable  cert "vBond Updated"  control-connections 2
Controller01 vsmart  100.0.0.101  reachable  cert "vBond Updated"  control-connections 3
Validator01  vbond   100.0.0.201  reachable  cert "Installed"      control-connections 10
```
Script runtime 2.7 s; `report/controllers.json` 611 bytes. (`certificate/vsmart/list` rows are keyed `deviceIP`; some lack `configuredSystemIP`.)

## Failure / Recovery Behaviour

Trigger: CML node stop of Controller01 (a silent failure of the control plane: the peers get no teardown). Recovery: CML node start. Nothing was reconfigured and no wipe was needed; the start state returned every time. Clock: one clock, `time.time()` on the polling host, polling the Manager and Validator API about every 3-5 s (plus 2-3 s API latency), so each value is the first poll that showed the change and has a resolution of about 6 s.

Observers: **M-ctl** = Manager `device/control/connections?deviceId=100.0.0.1`, no `vsmart` row up; **V-orch** = Validator `device/orchestrator/connections?deviceId=100.0.0.201`, no `vsmart` row up; **M-dev** = `reachability` of Controller01 in the Manager `device` list.

| Scenario (trigger, end condition) | Runs (raw, s) | Documented range | Basis |
|---|---|---|---|
| Node stop until Manager control-connection view (M-ctl) has no vsmart up | 14.4, 15.4, 18.5, 14.8, 14.9 | 14-19 s | measured; consistent with DTLS hello 1 s x tolerance 12 s plus poll `(derived)` |
| Node stop until Validator orchestrator view (V-orch) has no vsmart up | 147.2, 142.3, 144.1, 142.9, 151.7 | 141-152 s | measured (5 runs; 3 more: 147.3, 141.5, 151.3); mechanism not established |
| Node start until V-orch lists vsmart up | run 2: 260.0, run 3: 263.4, run 4: 118.0, run 5: 166.3 (run 1 already up at the first poll, 266.2) | 118-277 s | measured; includes node boot 73-145 s (build 5 runs, validation 3 runs: 212-265 s here, inside 118-277 s) |
| Node start until M-ctl lists vsmart up | run 2: 272.7, run 3: 276.1, run 4: 123.9, run 5: 166.3 (run 1 up at 266.2) | 118-277 s | measured; always the Validator first, the Manager 0-13 s later |
| Node start until CML reports BOOTED | 113.3, 83.6, 96.7, 144.6 (run 1 not measured) | 73-145 s | measured (build 4 runs, 83.6-144.6; validation 3 runs, 72.8-74.5); wide spread, wait on BOOTED |

- During the outage the Validator view still shows Controller01 `up` for about 2.4 minutes after the Manager has lost it.
- M-dev is unreliable: it went unreachable at 14.4-18.5 s (the same poll as M-ctl), but in run 2 the device list showed Controller01 `reachable` again from 81 s to the end of the run while M-ctl stayed down. Use the control-connection views as evidence, not the device list.
- Students' ranges must cover these spreads; recovery is wide (118-277 s), so wait on the end condition, not a fixed time.

## Answers to Analysis Questions

**Q1.** The Validator (orchestrator): the edge starts with only the Validator address (`validator.sdwan.local`, port 12346 here), the organisation name and its identity (serial/chassis number, certificate or token). The Validator checks these against the authorised list and tells the edge where the Manager and Controller are. If the organisation name differs, the edge's certificate/organisation check fails at the Validator and the edge never learns the other controllers (so no control connections form) `(derived)`.

**Q2.** The control plane (Controller to edges) carries OMP: routes, TLOCs, service information and the policy to apply; the management plane (Manager to devices) carries configuration/templates and monitoring through NETCONF, plus the GUI/API. Once the data-plane IPsec tunnels and BFD are established between edges, forwarding needs neither controller: edges keep forwarding with the last-known state (OMP graceful restart) until its timer expires `(derived)`.

**Q3.** The session cookie authenticates the user once, and the XSRF token (sent as a header that a foreign web page cannot read or set) ties a state-changing request to the session, which protects against cross-site request forgery; Basic sends credentials on every call. Measured here: the POST without the token got 403, and HTTP Basic `admin:password` was nevertheless accepted with 200 JSON, so Basic works on this Manager and is not a security boundary against a script that holds the password; the session flow is the documented/GUI path and gives logout, token-bound writes and no credentials on every request. RESTCONF (LAB-060) uses Basic over HTTPS per request and no token. A script must verify TLS (or state the risk) either way.

**Q4.** Real-time endpoints (`device/control/...`, `device/orchestrator/...`) make the Manager query the device live over the control connection and wait for the answer, which took seconds here (about 3 s on this pilot, 60-120 s in larger networks); the script uses long client timeouts (180 s), one request at a time per device, avoids polling tightly, and logs out in a `finally` block.

**Q5.** The Manager lost the Controller control connection after 14-19 s; the Validator's view kept it for 141-152 s; the Manager device list could flap back to `reachable` while the connection was still down, so the control-connection views are the reliable observers; recovery took 118-277 s. Real edges keep forwarding user traffic on their existing IPsec tunnels and last-known OMP routes (graceful restart) while the Controller is away; no new routes, policy changes or edges can be learned or onboarded until it returns `(derived)`.

**Q6.** Expected (from the usual REST pattern): 401 or 302 for no session, 403 for the missing token, 401/302 after logout. Measured: 200 + HTML login page for no session and after logout, 403 for the missing token, 302 from the logout POST itself. A script must check `Content-Type: application/json` (or that the body parses as JSON with the expected keys), not only `raise_for_status()`; the reference script's `need_json()` helper does this on every data call (the login and token calls keep their own HTML check). *Note: the `need_json` helper was run on the bench: the script ran as written, and after logout or with no login it stopped with "not JSON (text/html): session lost?" and rc=1 without writing a report.*

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-18 |
| CML | 2.10.0 |
| Node types | Catalyst SD-WAN 20.16.1, deployed with csdwan 3.2.1 (see BUILD.md) |
