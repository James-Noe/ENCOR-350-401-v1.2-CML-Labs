# LAB-061 — Solution

## Summary

Instructor view. The lab turns LAB-060's read/write knowledge into a real change: objects are written only through RESTCONF (IETF and native models) and NETCONF `<edit-config>`, the student sees how PATCH, PUT and `operation="delete"` act on list entries and leaves, reads a natural 400 error path, and then hardens the API (dedicated account, HTTPS only, source restriction, connection limit, a certificate with a SAN that the client trusts). Blueprint: 4.6:P (REST/NETCONF/RESTCONF), 5.3:I (device access control and API security), 6.2:P (configuration management via models), 6.5:P (API based management). The end state is **stage A1** (`environments/AUTO/A1/`), written by this lab.

Measured platform behaviour (all on cat8000v 17.16.1a):
1. **IETF PUT without `ietf-ip:ipv4` keeps the address** (only the containers the body names are replaced); the same PUT with `"ietf-ip:ipv4":{}` removes it, and the **native PUT** on `native/interface/Loopback=101` removes it (the list entry is replaced). R4 therefore uses both and Q2 explains the difference.
2. A denied source (`ip http access-class`) completes the TLS handshake and then gets **HTTP 403** from the web server, not a refusal or reset.
3. The certificate cannot be part of day-0: a cat8000v deletes a day-0 `crypto pki trustpoint` at boot (`%PKI-2-NON_AUTHORITATIVE_CLOCK`), and a dangling `ip http secure-trustpoint` breaks TLS. A1's certificate is therefore created by AUTO-MGMT1's cloud-init bootstrap (SSH to RTR3). The student does it by CLI.
4. Certificate verification by name works, so Q7 asks about name matching and trust-on-first-use rather than pinning. **Q8 (candidate datastore) is optional** (R6/V7): the candidate datastore is accepted but enabling it restarts the DMI (about 2 min) and A1 does not contain it.
5. R2's 400 arises naturally (your own first attempt). R3 leaves only Gi1's description in A1 (the Gi2 one is deleted by the exercise).
6. R5's "connection from RTR1's Loopback0 refused" is replaced: a telnet to 443 from RTR1 closes immediately for a permitted source too (no TLS hello), so it proves nothing. The proof is a request from a second AUTO-MGMT1 address (`ip addr add`, `curl --interface`).

## Intentional Faults

None (I lab).

## Diagnosis / Methodology

Not a troubleshooting lab. Method hints for the three places students get stuck:
- **R2 NTP 400:** `error-type application`, `error-tag unknown-element`, `error-path /Cisco-IOS-XE-native:native/ntp`, message `unknown element: server in /ios:native/ios:ntp/ios:server`. The path says the `server` container is not a child of `ntp` in the *native* module: it is added by the augmenting module `Cisco-IOS-XE-ntp`, so the prefix must be given (`Cisco-IOS-XE-ntp:server`). Look it up with `get-schema`, the tree files or a GET after configuring NTP once on the CLI.
- **409 on a write:** read `error-tag`: `lock-denied` (DMI sync, retry) vs `data-exists` (wrong method).
- **R5 certificate:** `ip http secure-trustpoint API-TP` alone does not create anything; the server keeps the old certificate. With the auto `TP-self-signed-<n>` present, `crypto pki enroll API-TP` prints "The router has already generated a Self Signed Certificate ... will be deleted" and returns without enrolling. Remove the default trustpoint first (`no crypto pki trustpoint TP-self-signed-<n>`, answer yes), then enroll.

## Solution Configuration

All RESTCONF calls: `curl -sk -u admin:'Cisco123!'` (before the account exists) with `-H 'Content-Type: application/yang-data+json' -H 'Accept: application/yang-data+json'`, base `https://10.90.50.11/restconf/data/`. Retry on 409 `lock-denied` (6 x 10 s).

**R1** (PATCH, 204 each):

```
PATCH ietf-interfaces:interfaces
{"ietf-interfaces:interfaces":{"interface":[{"name":"Loopback101","type":"iana-if-type:softwareLoopback","enabled":true,"ietf-ip:ipv4":{"address":[{"ip":"10.255.90.101","netmask":"255.255.255.255"}]}}]}}

PATCH Cisco-IOS-XE-native:native/router/Cisco-IOS-XE-ospf:router-ospf/ospf/process-id=1
{"Cisco-IOS-XE-ospf:process-id":[{"id":1,"network":[{"ip":"10.255.90.101","wildcard":"0.0.0.0","area":0}]}]}
```

**R2.** First attempt (400, see Diagnosis): `PATCH Cisco-IOS-XE-native:native/ntp` with `{"Cisco-IOS-XE-native:ntp":{"server":{"server-list":[{"ip-address":"10.255.90.1"}]}}}`. Fixed (204):

```
PATCH Cisco-IOS-XE-native:native/ntp
{"Cisco-IOS-XE-native:ntp":{"Cisco-IOS-XE-ntp:server":{"server-list":[{"ip-address":"10.255.90.1"}]}}}

PATCH Cisco-IOS-XE-native:native
{"Cisco-IOS-XE-native:native":{"ip":{"route":{"ip-route-interface-forwarding-list":[{"prefix":"10.99.0.0","mask":"255.255.0.0","fwd-list":[{"fwd":"Null0"}]}]}}}}
```

**R3** (NETCONF 1.0 framing over `ssh -p 830 -s netconf`, hello first, each RPC followed by `]]>]]>`):

```
<rpc message-id="1" xmlns="urn:ietf:params:xml:ns:netconf:base:1.0"><edit-config><target><running/></target><default-operation>merge</default-operation><config><interfaces xmlns="urn:ietf:params:xml:ns:yang:ietf-interfaces"><interface><name>GigabitEthernet1</name><description>AUTO-SW API segment</description></interface><interface><name>GigabitEthernet2</name><description>Link to AUTO-RTR1</description></interface></interfaces></config></edit-config></rpc>]]>]]>
<rpc message-id="2" xmlns="urn:ietf:params:xml:ns:netconf:base:1.0"><get-config><source><running/></source><filter type="subtree"><interfaces xmlns="urn:ietf:params:xml:ns:yang:ietf-interfaces"><interface><name>GigabitEthernet1</name><description/></interface><interface><name>GigabitEthernet2</name><description/></interface></interfaces></filter></get-config></rpc>]]>]]>
<rpc message-id="3" xmlns="urn:ietf:params:xml:ns:netconf:base:1.0"><edit-config><target><running/></target><config><interfaces xmlns="urn:ietf:params:xml:ns:yang:ietf-interfaces"><interface><name>GigabitEthernet2</name><description xmlns:nc="urn:ietf:params:xml:ns:netconf:base:1.0" nc:operation="delete"/></interface></interfaces></config></edit-config></rpc>]]>]]>
```

**R4:**

```
(a) PATCH .../interface=Loopback101  {"ietf-interfaces:interface":[{"name":"Loopback101","description":"monitored loopback"}]}        address stays
(b) PUT   ietf-interfaces:interfaces/interface=Loopback101
    {"ietf-interfaces:interface":{"name":"Loopback101","type":"iana-if-type:softwareLoopback","enabled":true,"description":"monitored loopback"}}   204, address STAYS
(c) PUT   Cisco-IOS-XE-native:native/interface/Loopback=101
    {"Cisco-IOS-XE-native:Loopback":{"name":101,"description":"monitored loopback"}}                                                           204, address REMOVED
(d) PATCH ietf-interfaces:interfaces/interface=Loopback101
    {"ietf-interfaces:interface":[{"name":"Loopback101","ietf-ip:ipv4":{"address":[{"ip":"10.255.90.101","netmask":"255.255.255.255"}]}}]}      204, RTR1 route back in 2 s
    DELETE .../interface=Loopback101/description                                                                                              204
```

An IETF PUT whose body carries `"ietf-ip:ipv4":{}` (empty container) also removes the address (and description): the container is "named" and replaced by nothing.

**R5** (AUTO-RTR3 CLI, `configure terminal`):

```
username apiuser privilege 15 secret Api#Pass2026
ip access-list standard API-CLIENTS
 permit 10.90.50.31
ip http access-class ipv4 API-CLIENTS
ip http max-connections 5
no crypto pki trustpoint TP-self-signed-<n>        (answer yes; n from "show running-config | include TP-self-signed")
crypto pki trustpoint API-TP
 enrollment selfsigned
 subject-name CN=rtr3.auto.veridian.example
 subject-alt-name rtr3.auto.veridian.example
 revocation-check none
 rsakeypair API-KEY 2048
ip http secure-trustpoint API-TP
end
crypto pki enroll API-TP
```

`crypto pki enroll API-TP` (exec) prints "Router Self Signed Certificate successfully created"; the server presents it at once, no restart. AUTO-MGMT1:

```
echo '10.90.50.11 rtr3.auto.veridian.example' | sudo tee -a /etc/hosts
mkdir -p /home/cisco/trust
echo | openssl s_client -connect rtr3.auto.veridian.example:443 -servername rtr3.auto.veridian.example 2>/dev/null | openssl x509 > /home/cisco/trust/rtr3.pem
```

The copy is trust on first use: it is only as good as the network path at that moment; production fetches it from the router console (`show crypto pki certificates`) or a CA (Q7). The router's key pair is regenerated on every boot of the lab router, so `rtr3.pem` is always fetched, never shipped.

**V6 (priv-1 user)**: `username viewer privilege 1 secret ...` (a `no username` later asks `[confirm]`: answer interactively), then GET and PATCH as `viewer` from MGMT1.

**R6 (optional):** `netconf-yang feature candidate-datastore` (the command took about 2 min; GET 200 again about 128 s after); then the hello lists `candidate:1.0` and `confirmed-commit:1.0/1.1`; edit-config with `<target><candidate/>`, then `<commit/>`. A1 does not contain this feature.

## Verification

**R1 / V1.** PATCH calls returned 204 first try. RTR3 `router ospf 1` has `network 10.255.90.101 0.0.0.0 area 0`. RTR1 `show ip route 10.255.90.101`: `Known via "ospf 1"`, metric 11, via 10.90.255.3 Ethernet0/2, learned within about 20 s.

**R2 / V2.** NTP 400 payload: `error-type application`, `error-tag unknown-element`, `error-path /Cisco-IOS-XE-native:native/ntp`, message `unknown element: server in /ios:native/ios:ntp/ios:server`. After the fix 204; `ntp server 10.255.90.1` and `ip route 10.99.0.0 255.255.0.0 Null0` in the running config; `show ip route 10.99.0.0`: static, directly connected, via Null0. A GET of the absent NTP or route node returns an empty 204 before the change. System peer (RTR3, checked last): `*~10.255.90.1 127.127.1.1 st 3 ... reach 177`; `show ntp status` stays `Clock is unsynchronized, stratum 4, reference is 10.255.90.1` (normal on this pod).

**R3 / V3.** The merge RPC (both descriptions in one RPC) answered `<ok/>`; the `<get-config>` subtree returned both descriptions; the delete RPC answered `<ok/>` and `show interfaces description` then showed Gi1 with its text and Gi2 blank. Hello capabilities include base:1.0/1.1, writable-running, rollback-on-error, validate, xpath, notification, interleave; **no candidate by default**.

**R4 / V4.** (b) 204 and the address stays (description added, RTR1 route stays). (c) 204: address removed (`no ip address`), RTR1 `show ip route 10.255.90.101` -> `% Subnet not in table`. (d) restore 204, RTR1 route back after 2 s (poll). An IETF PUT with `"ietf-ip:ipv4":{}` also removed address and description.

**R5 / V5.** AUTO-MGMT1: `curl --cacert /home/cisco/trust/rtr3.pem https://rtr3.auto.veridian.example/restconf/...` -> 200; port 80 -> curl code 000; wrong password -> 401; `--cacert` to `https://10.90.50.11` -> exit 60 (the IP is not in the SAN); without `--cacert` -> exit 60. Certificate: subject `CN=rtr3.auto.veridian.example`, unstructuredName `AUTO-RTR3.veridian.example`, SAN `DNS:rtr3.auto.veridian.example`, validity 10 years. Denied source (second address `sudo ip addr add 10.90.50.32/24 dev ens2`): `curl --interface 10.90.50.32` -> **TLS completes, HTTP 403** with an openresty "403 Forbidden" page; `--interface 10.90.50.31` -> 200; swapping the ACL entry to a different host gave 403 for .31 too, and restoring it gave 200 (allow 20 s for the change). Toolkit V: `show logging | include apiuser` shows `%DMI-5-AUTH_PASSED: R0/0: dmiauthd: User 'apiuser' authenticated successfully from 10.90.50.31:0  for rest over http. External groups: PRIV15` (one line per call).

**V6 (priv-1 user).** GET and PATCH both answer **403** with `error-type application`, `error-tag access-denied`, message `access denied` (so authorisation failure is 403 and a bad password is 401). Needed by LAB-065.

**R6 / V7.** After `netconf-yang feature candidate-datastore` the hello lists `candidate:1.0` and `confirmed-commit:1.0/1.1`; edit-config to candidate `<ok/>`, `<get-config>` of running unchanged, `<commit/>` `<ok/>`, running contains the change.

Not a verification: `telnet 10.90.50.11 443 /source-interface Loopback0` on RTR1 prints "Open" and is then closed by the foreign host for permitted and denied sources alike (telnet sends option bytes, not a TLS hello), and `console` carries no syslog.

## Failure / Recovery Behaviour

Failure method: **silent failure** of the RTR1-RTR3 link (`tools/cml-rest.sh link stop`); both interfaces stay up/up. Clock: host `date` at the call midpoint vs RTR3 `show clock` read by the last poll of a scripted CLI poll every 1 s, calibrated against the device each run (offset 0.8-0.9 s); accuracy about 1.5 s. The cat8000v console carries no syslog, so ADJCHG could not be clocked directly.

| Scenario (trigger / end condition) | Runs (s) | Documented range | Basis |
|---|---|---|---|
| `link stop` RTR1-RTR3 / RTR3 OSPF neighbour gone (`Neighbor Down: Dead timer expired`, Gi2 up/up) | 40.1, 35.0, 38.6 (an earlier uncalibrated run: about 35) | 30-42 s | dead 40 s minus hello 10 s (a lower bound calculated from the timers) plus polling error; measured |
| `link start` / OSPF FULL on RTR3 | 4.3, 3.0, 5.4 (earlier run: about 2) | 2-12 s | measured; upper = hello 10 s + poll (calculated from the timers) |
| first enable after wipe (A0 cold boot) / first RESTCONF GET 200 | 157, 149 s after BOOTED | 150-160 s | measured (first boot; fresh import) |
| A1 cold boot / `rtr3.pem` present (MGMT1 bootstrap) | about 4 min after BOOTED | 4-5 min | measured once (A1 boot test) |
| `netconf-yang feature candidate-datastore` / API 200 again | 128 s (command itself about 2 min) | 2-3 min | measured once |

Route to 10.255.90.1 is gone during the outage (`% Subnet not in table`). The RESTCONF API on the connected Gi1 segment keeps answering (apiuser GET 200 from MGMT1) throughout: the management path is independent of the OSPF data path. The NTP association to 10.255.90.1 stays `*~` sys.peer for more than 3.5 minutes (reach decays 377 -> 310 in 199 s, `when` 327 s), so it does not age out within a practical test window: no NTP timing is documented.

## Answers to Analysis Questions

**Q1.** IETF `ietf-interfaces`/`ietf-ip` for the loopback, its address and the descriptions (portable, vendor-neutral, same on any platform that implements it, also used in NETCONF R3); native `Cisco-IOS-XE-native` for OSPF networks, NTP and the static route because no IETF model covers them on this platform (or covers them poorly). The native Loopback view carries Cisco features (ip ospf, ACLs, descriptions in the same list entry) and replaces the whole list entry on PUT; the IETF view is stable across vendors but exposes only the standard leaves, and PUT replaces only the containers the body names.

**Q2.** (b) The IETF PUT body named `name`, `type`, `enabled`, `description` but no `ietf-ip:ipv4`; the router replaced only those and left `ipv4` untouched, so the address (and the OSPF route) stayed. (c) The native PUT replaced the whole `Loopback=101` list entry with `{name, description}`, so the address, OSPF statement and everything else in the entry went. A PUT with an empty `ietf-ip:ipv4` container also removes it. Use PUT when you want the object to equal your document (an idempotent desired-state replace, with a body that is complete) and PATCH to change a leaf without touching the rest. The risk of "PUT the whole object": the effect depends on the model and the platform's mapping (here the same object behaves differently through two models), so a partial body silently deletes configuration or silently leaves it; test the exact behaviour before relying on it, and prefer PATCH for incremental changes.

**Q3.** The error-path `/Cisco-IOS-XE-native:native/ntp` with `unknown element: server` says the node `server` is not a child of `ntp` in that module's namespace. In the tree, `server` is added under `ntp` by the augmenting module `Cisco-IOS-XE-ntp` (a different namespace), so the child must be prefixed `Cisco-IOS-XE-ntp:server`. The native model is split into many modules that augment `native` (ospf, ntp, ip, ...), so one container name can exist in two modules; the prefix selects the module.

**Q4.** Over HTTPS basic authentication keeps the credential (base64 in the `Authorization` header) confidential on the wire and, with a verified certificate, sure of whom it is sent to. It does not give the credential an expiry, a scope or a revocation path: the same secret travels in every request (a MITM that is accepted via `-k` collects it), a leaked secret works until changed, and every call has the full rights of the account. V6: a privilege-1 user receives 403 `access-denied` (authorised failure, unlike the 401 of a bad password), so a script must separate "who are you" (401) from "you may not" (403) and the router enforces privilege per RESTCONF call.

**Q5.** A token API sends the credential once (POST to an auth endpoint) and receives a short-lived `X-Auth-Token` that is sent on every call: the secret travels once, the token expires and can be revoked, and it can carry scope. Stealing a token is still enough until expiry, so TLS is still required. RBAC decides what the authenticated identity may do: here it is the privilege level (priv 1 gets 403); on Catalyst Center it is the role bound to the token's user (read-only observer vs admin) which restricts the Intent API calls.

**Q6.** The access class decides **who may connect** (source address, acts on the web server for every method); the certificate decides **whom the client trusts** (server identity, acts on the client). They protect different sides: a perfect certificate does not stop another host from sending credentials guesses, and an access class does not stop a man-in-the-middle at the permitted address. The denied source completed the TLS handshake and received a 403 page, so the access class acts in the HTTP server after TLS, not at the TCP accept.

**Q7.** `--cacert` verifies the name in the URL against the certificate's SAN (`DNS:rtr3.auto.veridian.example`); the IP 10.90.50.11 is not in it, so verification fails (exit 60). The name is therefore needed, and `/etc/hosts` (or DNS) provides it. Fetching `rtr3.pem` with `openssl s_client` trusts whatever answered at that moment (trust on first use): an attacker on the path at that moment would be trusted forever. In production compare the fingerprint with the one shown on the router console (`show crypto pki certificates`), or issue the certificate from a company CA and install only the CA on the clients.

**Q8 (optional).** The candidate datastore holds changes apart from running; the client validates and then `<commit/>` applies them as one unit, and can discard instead (rollback). Writing running directly applies each edit at once and a failure half way leaves a partial change. The cost here: enabling the feature restarted the DMI (about 2 min of no API) and had to be planned like the `netconf-yang` change in LAB-060.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-17 |
| CML | 2.10.0 |
| Node types | cat8000v (IOS XE 17.16.1a), external_connector, iol-xe (IOS XE 17.16.1a), ubuntu (Ubuntu 24.04), unmanaged_switch |
