# LAB-060 — Solution

## Summary

The lab teaches the two model-driven management planes of IOS XE on the same YANG models: NETCONF (SSH 830, XML, sessions, hello/capabilities, `<get>`/`<get-config>`/`<get-schema>`) and RESTCONF (HTTPS 443, JSON/XML, HTTP verbs, status codes plus an `error-tag` payload), and the TLS basics under RESTCONF. It also builds the response code card that LAB-061 (writes), LAB-062 (Python) and LAB-065 (diagnosis) reuse. Blueprint: 4.6:I (REST and NETCONF/RESTCONF), 6.3:P (YANG, `<get-schema>`), 6.5:I (API based management). CCNA+ primer: PKI/X.509/TLS (R6, Q7). The end state is **stage A0** (`environments/AUTO/A0/`), written by this lab.

Measured deviations from the textbook (all on cat8000v 17.16.1a): `Cisco-IOS-XE-native` and `candidate` are **absent from the NETCONF hello** (the module is still served and found through the YANG library/`get-schema`); `lock-denied` appears for 2-3 s after a **RESTCONF write**, not after a CLI change; `?depth=2` on `ietf-interfaces:interfaces` returns an empty `interface` list (depth counts the container); `content=nonconfig` on `ietf-interfaces:interfaces/...` returns 204; AUTO-RTR3 needs `cpus: 2` or the API never starts; `loopback100.json` is not on AUTO-MGMT1 (LAB.md gives the body).

## Intentional Faults

None (F/I lab). The four induced errors in R5 are exercise steps.

## Diagnosis / Methodology

Not a troubleshooting lab. Method for R1: start from the CLI (`show ip http server status`, `show platform software yang-management process`), then from AUTO-MGMT1 test the three ports with `/dev/tcp`. A 502 from nginx or `confd` not listed as Running in `show platform software yang-management process` means the DMI is not up yet (wait; a router with one vCPU never gets there). Port 443 open but HTTP 404 on `/restconf` means `restconf` is not configured; refused on 443 means `ip http secure-server` is off.

## Solution Configuration

AUTO-RTR3 (one config block):

```
netconf-yang
restconf
ip http secure-server
ip http authentication local
```

`no ip http server` and `no ip http secure-server` are in the start config; the last is replaced by `ip http secure-server`. `ip http secure-server` prints `Failed to generate persistent self-signed certificate. Secure server will use temporary self-signed certificate.` This is expected on the Catalyst 8000V: the certificate is still created (`TP-self-signed-<n>` in `show crypto pki certificates`, 10-year validity), so it is not a fault. First `GET /restconf/data` returns 200 about 150 s after the commands.

AUTO-MGMT1 commands (test aids):

```
for p in 80 443 830; do timeout 3 bash -c "echo > /dev/tcp/10.90.50.11/$p" 2>/dev/null && echo "port $p OPEN" || echo "port $p CLOSED"; done
curl -sk -u admin:'Cisco123!' -H 'Accept: application/yang-data+json' https://10.90.50.11/restconf/data/ietf-interfaces:interfaces
```

NETCONF by hand: `ssh -p 830 admin@10.90.50.11 -s netconf`, enter the password, paste the client hello below, then each RPC followed by `]]>]]>`:

```
<hello xmlns="urn:ietf:params:xml:ns:netconf:base:1.0"><capabilities><capability>urn:ietf:params:netconf:base:1.0</capability></capabilities></hello>]]>]]>
<rpc message-id="1" xmlns="urn:ietf:params:xml:ns:netconf:base:1.0"><get-config><source><running/></source><filter type="subtree"><native xmlns="http://cisco.com/ns/yang/Cisco-IOS-XE-native"><hostname/></native></filter></get-config></rpc>]]>]]>
<rpc message-id="2" xmlns="urn:ietf:params:xml:ns:netconf:base:1.0"><get-schema xmlns="urn:ietf:params:xml:ns:yang:ietf-netconf-monitoring"><identifier>ietf-interfaces</identifier></get-schema></rpc>]]>]]>
<rpc message-id="3" xmlns="urn:ietf:params:xml:ns:netconf:base:1.0"><close-session/></rpc>]]>]]>
```

Paste the same bytes interactively.

## Verification

**R1 / V1.** `show ip http server status`: HTTP server Disabled, HTTP secure server Enabled, authentication local, trustpoint `TP-self-signed-<n>` (blank right after enabling, until the self-signed certificate has been created; later e.g. `TP-self-signed-3882553164`). `show platform software yang-management process` prints a process list, each line `<name> : Running` (`confd`, `nesd`, `ndbmand`, `nginx` and others); all Running means the DMI is up. From AUTO-MGMT1: ports 22 OPEN, 80 CLOSED, 443 OPEN, 830 OPEN; `GET /restconf` with `Accept: application/yang-data+json` returns 200 `{"ietf-restconf:restconf":{"data":{},"operations":{},"yang-library-version":"2019-01-04"}}`. Syslog at enable: `%PSD_MOD-5-DMI_NOTIFY_NETCONF_START`, `..._RESTCONF_START`, `%DMI-5-NACM_INIT`, `%DMI-5-SYNC_NEEDED ... 'Initial sync'`, `SYNC_START`, `SYNC_COMPLETE` (about 5 s).

**R2 / V2 (NETCONF hello, 1.0-only client).** Server announces **353** capabilities (the count varies with the image; the student records their own). It offers `base:1.0` and `base:1.1` (the client chose 1.0, so `]]>]]>` framing). `writable-running:1.0`, `rollback-on-error`, `validate:1.0/1.1`, `xpath`, `interleave`, `notification`, `with-defaults` (basic-mode explicit; also report-all-tagged, report-all), `yang-library:1.0/1.1` (revision 2019-01-04) and `ietf-interfaces?module=ietf-interfaces&revision=2014-05-08&features=pre-provisioning,if-mib,arbitrary-names&deviations=cisco-xe-ietf-ip-deviation` are announced. **`candidate` is not offered**: `<get-config><source><candidate/>` returns `rpc-error` type protocol, tag `invalid-value`, "Unsupported capability :candidate". **`Cisco-IOS-XE-native` is not in the hello** (35 `cisco.com` capabilities, 76 openconfig, 8 tail-f), yet `<get-config>` on its namespace works: the module is found through the YANG library / `get-schema`.

**R3 / V3.** `<get-config>` filter `native/hostname` returns `<hostname>AUTO-RTR3</hostname>`; the interface filter returns GigabitEthernet1-4 and Loopback0; `<get>` of `interfaces-state/interface[name=GigabitEthernet1]` returns oper-status up and in-octets/out-octets/in-errors (e.g. 232421/277266/0). `<get-schema>` for `ietf-interfaces` returns `<data xmlns=".../ietf-netconf-monitoring"><![CDATA[module ietf-interfaces {` (24 564 bytes, `revision 2014-05-08`); after removing the CDATA wrapper it is identical to `/home/cisco/yang/ietf-interfaces.yang` (diff clean, blank lines ignored). An `edit-config` create and delete of Loopback100 returned `<ok/>` both times.

**R4 / V4.** `GET /.well-known/host-meta` (authenticated): 200 `<XRD xmlns='http://docs.oasis-open.org/ns/xri/xrd-1.0'><Link rel='restconf' href='/restconf'/></XRD>`; without credentials 302 to `/login.html`. `GET interfaces?depth=2` returns 200 with `"interface": [ ]` (empty: depth counts the container; `depth=3` shows the entries with name, type, enabled and empty ipv4/ipv6). `?fields=interface(name;enabled)` returns only name and enabled. Full JSON reply of the base state: the router returned five interfaces (Gi1-Gi4, Loopback0) and no `description` leaves; Gi3 and Gi4 `enabled: false`. Operational data: `.../interfaces-state/interface=GigabitEthernet1?content=nonconfig&fields=oper-status;statistics` 200; `Cisco-IOS-XE-interfaces-oper:interfaces/interface=GigabitEthernet1/oper-status` 200 `"if-oper-state-ready"`. `content=nonconfig` on `ietf-interfaces:interfaces/interface=GigabitEthernet1` returns **204** (no non-config leaves in that tree).

**R5 / V5-V6 response code card** (curl -sk -u admin:Cisco123!, measured):

| Step | Code | error-tag / note |
|---|---|---|
| POST `/data/ietf-interfaces:interfaces` (loopback100.json) | 201 | empty body |
| GET `interface=Loopback100` | 200 | description "API test", 10.255.90.100/255.255.255.255 |
| PATCH | 204 | |
| PUT (first and second) | 204, 204 | idempotent |
| DELETE | 204 | |
| GET after DELETE | 404 | error-type application, `invalid-value`, "uri keypath not found" |
| DELETE again | 404 | same (not 204) |
| malformed JSON POST | 400 | `malformed-message`, "1: Premature end of file" |
| wrong password / no credentials | 401 | type protocol, `access-denied`, no message |
| nonexistent interface or module | 404 | `invalid-value`, "uri keypath not found" |
| same POST twice | 409 | `data-exists`, "object already exists: /if:interfaces/if:interface[if:name='Loopback100']" |
| POST with `Content-Type: text/plain` | 415 | `malformed-message`, "Unsupported media type ..." |
| PUT body to the container path | 400 | `invalid-value`, "mismatched keypaths" |
| second RESTCONF write right after a first | 409 | `lock-denied`, "the configuration database is locked by session ... yang_mgmt_infra"; accepted again after 2.39, 1.90, 2.68 s |
| HTTP port 80 | refused | curl code 000 |

Syslog for each write: `%DMI-5-CONFIG_I: R0/0: dmiauthd: Configured from NETCONF/RESTCONF by admin, transaction-id 63` (create) and `... 68` (delete). A CLI change immediately before a POST did **not** cause `lock-denied` (POST returned 201 at 1.2 s).

**R6 / V7.** `openssl s_client -connect 10.90.50.11:443 -showcerts`: 1 certificate, subject = issuer = `CN = IOS-Self-Signed-Certificate-<n>` (the number changes per build), serial 1, sha512WithRSAEncryption, RSA 2048 bit, valid Oct 11 2026 to Oct 10 2036 (10 years, created at the first `ip http secure-server`), **no SAN extension**, only SKI/AKI/BasicConstraints (CA:TRUE critical). `Verify return code: 18 (self-signed certificate)`; TLS 1.3 TLS_AES_256_GCM_SHA384 (TLS 1.2 ECDHE-RSA-AES128-GCM-SHA256 also accepted). `curl` without `-k`: `curl: (60) SSL certificate problem: self-signed certificate`, exit 60. Router side: `show crypto pki certificates` lists `TP-self-signed-<n>` "Router Self-Signed Certificate".

## Failure / Recovery Behaviour

Method: `no restconf`, `ip http secure-server` toggles in a scripted config block with a CLI poll, GET loop on AUTO-MGMT1 once per second; times include 2-3 s of CLI latency.

| Scenario (trigger / end condition) | Runs (s) | Documented range | Basis |
|---|---|---|---|
| `no restconf` / first GET answer other than 200 (404; ports 443 and 830 still open) | 3, 2, 2 | up to about 5 s | measured |
| `restconf` / first 200 | 4, 4, 4 | up to about 10 s | measured, no DMI restart |
| `no ip http secure-server` / GET: requests hang (curl timeout) first, then connection refused (443 closed, 830 open) | about 65, 65, 76 | 60-80 s | measured, 1 s poll; the first 64 s of requests time out, only then refused |
| `ip http secure-server` / first 200 | 4, 2, 4 | up to about 10 s | measured |
| first enable of `netconf-yang`+`restconf`+HTTPS block / first GET 200 | 152, 153 | 150-160 s (2 runs only; a third was the 1-vCPU failure, not comparable) | measured; the DMI process starts |
| `no netconf-yang` then `netconf-yang` / GET 200 | 197 (one run, includes the disable step) | not a documented value | indicative: NETCONF changes restart the DMI |
| RESTCONF write, then a second write / first non-`lock-denied` answer | 2.39, 1.90, 2.68 | 2-3 s | measured; CLI-triggered `lock-denied` was seen once (MS-4) and can't be reproduced on demand (LAB-062) |
| cold boot of a router with the A0 day-0 (API on) / first GET 200 | about 4 min after BOOTED (1 run) | 4-5 min | measured once |

Deviation recorded: with 1 vCPU the DMI never finished starting (over 60 min), so AUTO-RTR3 is defined with `cpus: 2`.

## Answers to Analysis Questions

**Q1.** NETCONF is a long-lived, stateful SSH session (subsystem `netconf`, port 830): hello and capability negotiation, message framing (`]]>]]>` for 1.0, chunked for 1.1), locks, `commit`/`rollback-on-error` and notifications, so a script can do a transaction and keep a session. RESTCONF is stateless HTTP(S): each call stands alone (credentials, URL, verb, media type), friendly to `curl`/`requests`, with the status code and `error-tag` carrying the result; the TLS channel provides confidentiality and server authentication. SSH already provides authentication and encryption for NETCONF; HTTPS reuses web infrastructure for RESTCONF.

**Q2.** `<get-config>` returns only configuration datastore data; `<get>` returns configuration and operational state together. RESTCONF `content=config` is the `get-config` view, `content=nonconfig` the operational (read-only) leaves, `content=all` both. `ietf-interfaces:interfaces` is a configuration tree whose operational leaves live in the separate `interfaces-state` tree (and in `Cisco-IOS-XE-interfaces-oper`), so `nonconfig` on it returns 204 with no content.

**Q3.** POST creates a child in the target container and fails if it already exists (409 `data-exists`). PUT creates or replaces the whole resource at the target URL; repeating it gives the same result (204), so it is idempotent. PATCH merges the given fields into an existing resource and leaves the rest (204). A second POST names an existing list key, so it conflicts; a second PUT just replaces identical data.

**Q4.** Both are 409; the JSON `error-tag` differs: `data-exists` means the object is already there (use PUT/PATCH or read first, retrying never helps); `lock-denied` means the configuration database is locked by another session or a sync (retry after a short wait). In this build `lock-denied` appears for 2-3 s after a RESTCONF write (also while the DMI syncs); a CLI change did not produce it in the tests. A script reads `error-tag`, retries `lock-denied` a few times with a pause and stops on `data-exists`.

**Q5.** 401 says the request carried no valid credentials (here also "no credentials" gives 401 on the API; the body has `access-denied` and no message). It does not say whether the user exists, the password was wrong, or the account is locked, and it is not a privilege answer (a privilege failure would be 403; not tested here). Revealing less is deliberate.

**Q6.** Before using a feature check: `candidate` (offered? here no, so edit `running` directly), `validate:1.1`, `rollback-on-error`, `writable-running`, `with-defaults` modes, `xpath`, `notification`, `base:1.1` (framing). The hello lists protocol capabilities and a subset of modules (here `Cisco-IOS-XE-native` is missing from the hello); the full list of modules and revisions comes from `ietf-yang-library` or `<get-schema>`/`ietf-netconf-monitoring` schemas list, so a tool must not conclude a module is unsupported from the hello alone.

**Q7.** The client checks that the server certificate chains to a trusted CA, that the name or IP matches the certificate subject or SAN, that it is within its validity period and not revoked. The router's certificate is self-signed (subject = issuer, no SAN, chain length 1), so `curl` exits 60. A company-CA certificate with the router's name/IP in the SAN, installed on the router (and the CA trusted on AUTO-MGMT1), would verify and `curl` would work without `-k`. `-k` skips chain, name and validity checks, so a man-in-the-middle presenting any certificate gets the admin credentials sent in the Basic header.

**Q8.** `no restconf` is cheap: nginx keeps answering (404 within about 5 s), confd keeps running, and `restconf` returns 200 in 2-4 s. `no netconf-yang` stops and restarts the whole DMI (confd, nesd, ndbmand): the API is gone for 2-3 minutes (197 s for disable plus enable), so it belongs in a maintenance window. `no ip http secure-server` closes 443 but leaves NETCONF on 830; requests to 443 hang for about 64 s (timeouts) before the connection is refused (65-76 s measured), so a timeout right after the change is not yet a refusal.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-17 |
| CML | 2.10.0 |
| Node types | cat8000v (IOS XE 17.16.1a), external_connector, iol-xe (IOS XE 17.16.1a), ubuntu (Ubuntu 24.04), unmanaged_switch |
