# LAB-059 — Solution

## Summary

Foundation lab for module 09 (6.2:I, 6.3:I): read JSON, read YANG, tell model from encoding. One Ubuntu 24.04 host (AUTO-MGMT1) with a NAT link; no router. The student validates four JSON files (two are broken on purpose: `ntp-servers.json` has a trailing comma, `banner.json` has single quotes), extracts values from a captured RESTCONF reply, installs `pyang` 2.7.1 and reads `pyang -f tree` for `ietf-interfaces`/`ietf-ip` and for `/native/ntp`, then builds the Loopback100 body (JSON and XML) that LAB-060 sends to AUTO-RTR3. The captured reply is real output from AUTO-RTR3 (IOS XE 17.16.1a, five interfaces, no `description` leaves).

Build notes: the stock image lacks `python3-venv` (added to R3 as an apt step, 47 s via NAT); the R4 failure output measured 328 lines, not the 70 in the plan; the R3 tree command loads `ietf-ip` too because the `ipv4`/`ipv6` containers R5 needs are an augment of it.

## Intentional Faults

None (F lab). The invalid files are exercise material.

| ID | File | Defect | Parser message (captured) |
|---|---|---|---|
| E1 | `json/ntp-servers.json` | trailing comma after the last array element | `json.tool`: `Expecting value: line 14 column 5 (char 219)`; `jq`: `Expected another array element at line 14, column 5` |
| E2 | `json/banner.json` | single-quoted string (`'Authorized use only'`) | `json.tool`: `Expecting value: line 3 column 13 (char 28)`; `jq`: `Invalid numeric literal at line 3, column 24` |

## Diagnosis / Methodology

1. Run `python3 -m json.tool FILE` on all four files: two print a parse error with line and column, two print the pretty-printed document. The reported position is where the parser gave up, which is at or just after the real error (E1: the `]` on line 14 after the comma; E2: the quote on line 3).
2. Fix only that character in a copy (`sed`/editor), re-run, repeat until clean.
3. Types in the reply: top level is an object; `interface` is an array of objects; `name` a string; `enabled` a boolean; `"ietf-ip:ipv6": {}` of Gi3 an object (empty). `owner: null` in `inventory.json` is the null example.
4. For YANG, always give pyang the search path (`-p yang`) and every module that augments or imports: the tree is built from the modules you load, not from the device.

## Solution Configuration

On AUTO-MGMT1 (user `cisco`). The stock image has no `ensurepip`, so the venv needs the `python3-venv` package first (apt through the NAT link).

```
mkdir -p ~/lab059 && cd ~/lab059
# R1
cp ~/json/ntp-servers.json ~/json/banner.json . ; nano ntp-servers.json banner.json   # E1: delete the comma before ]   E2: 'x' -> "x"
python3 -m json.tool ntp-servers.json >/dev/null && echo OK
# R2
jq -r '."ietf-interfaces:interfaces".interface[] | "\(.name) \(.enabled)"' ~/json/restconf-interfaces-reply.json
python3 -c 'import json;d=json.load(open("/home/cisco/json/restconf-interfaces-reply.json"));[print(i["name"],i["enabled"]) for i in d["ietf-interfaces:interfaces"]["interface"]]'
# R3
sudo apt-get update -q && sudo apt-get install -y python3-venv
python3 -m venv ~/venv && ~/venv/bin/pip install pyang==2.7.1
cd ~ && ~/venv/bin/pyang -p yang -f tree yang/ietf-interfaces.yang yang/ietf-ip.yang
# R4
cd ~ && ~/venv/bin/pyang -p yang -f tree --tree-path=/native/ntp yang/Cisco-IOS-XE-native.yang yang/Cisco-IOS-XE-ntp.yang
# R5, R6: files below
```

R5 body (`~/lab059/loopback100.json`, identical to the body used in LAB-060):

```
{"ietf-interfaces:interface":{"name":"Loopback100","description":"API test","type":"iana-if-type:softwareLoopback","enabled":true,"ietf-ip:ipv4":{"address":[{"ip":"10.255.90.100","netmask":"255.255.255.255"}]}}}
```

R6 XML (`~/lab059/loopback100.xml`):

```
<interface xmlns="urn:ietf:params:xml:ns:yang:ietf-interfaces"><name>Loopback100</name><description>API test</description><type xmlns:ianat="urn:ietf:params:xml:ns:yang:iana-if-type">ianat:softwareLoopback</type><enabled>true</enabled><ipv4 xmlns="urn:ietf:params:xml:ns:yang:ietf-ip"><address><ip>10.255.90.100</ip><netmask>255.255.255.255</netmask></address></ipv4></interface>
```

Changed between JSON and XML: the syntax (braces/quotes versus tags), the way a namespace is carried (a `module:` prefix on a name in JSON, an `xmlns` attribute in XML, with the identityref value written `iana-if-type:softwareLoopback` in JSON and `ianat:softwareLoopback` with a prefix declaration in XML), booleans/numbers as JSON types versus text, and arrays versus repeated elements. Unchanged: the model (same nodes, same hierarchy, same names, same key `ip`, same values).

## Verification

All outputs captured on AUTO-MGMT1 (Ubuntu 24.04, Python 3.12.3, jq 1.7, requests 2.31.0).

Invalid files (V1):

```
python3 -m json.tool banner.json        -> Expecting value: line 3 column 13 (char 28)
python3 -m json.tool ntp-servers.json   -> Expecting value: line 14 column 5 (char 219)
jq . banner.json                        -> jq: parse error: Invalid numeric literal at line 3, column 24
jq . ntp-servers.json                   -> jq: parse error: Expected another array element at line 14, column 5
```

R2 (`jq` and Python give the same five pairs):

```
GigabitEthernet1 true      (jq)      GigabitEthernet1 True   (Python)
GigabitEthernet2 true                GigabitEthernet2 True
GigabitEthernet3 false               GigabitEthernet3 False
GigabitEthernet4 false               GigabitEthernet4 False
Loopback0 true                       Loopback0 True
```

R3: `pyang --version` prints `pyang 2.7.1`; `pyang -p yang -f tree yang/ietf-interfaces.yang yang/ietf-ip.yang` is identical (diff-clean) to `trees/ietf-interfaces.txt`. Excerpt:

```
module: ietf-interfaces
  +--rw interfaces
  |  +--rw interface* [name]
  |     +--rw name                        string
  |     +--rw description?                string
  |     +--rw type                        identityref
  |     +--rw enabled?                    boolean
  |     +--rw link-up-down-trap-enable?   enumeration {if-mib}?
  +--ro interfaces-state
     +--ro interface* [name]
        ...
        +--ro higher-layer-if*   interface-state-ref
module: ietf-ip
  augment /if:interfaces/if:interface:
    +--rw ipv4!
    |  +--rw address* [ip]
    |  |  +--rw ip                     inet:ipv4-address-no-zone
    |  |  +--rw (subnet)
    |  |     +--:(prefix-length)
    |  |     |  +--rw prefix-length?   uint8
    |  |     +--:(netmask)
    |  |        +--rw netmask?         yang:dotted-quad {ipv4-non-contiguous-netmasks}?
```

Marks: list key = `[name]` on `interface*`; state leaf = anything under `+--ro interfaces-state` (e.g. `oper-status`); optional leaf = `description?`; leaf-list = `higher-layer-if*` (the only leaf-list in this tree); presence container = `ipv4!`/`ipv6!`.

R4 (zero-error tree, 351 lines, identical to `trees/native-ntp.txt`) starts `module: Cisco-IOS-XE-native / +--rw native / +--rw ntp`. With only `Cisco-IOS-XE-native.yang` and `Cisco-IOS-XE-ntp.yang` in an otherwise empty directory the same command printed **328 lines**, of which 78 lines contain "not found":

```
Cisco-IOS-XE-native.yang:6: error: module "cisco-semver" not found in search path
Cisco-IOS-XE-native.yang:12: error: module "Cisco-IOS-XE-types" not found in search path
Cisco-IOS-XE-native.yang:15: error: module "Cisco-IOS-XE-features" not found in search path
...        (47 lines of: node Cisco-IOS-XE-native::interface is not found)
```

Two message kinds: `module "X" not found in search path` (an `import`/`include` cannot be resolved) and `node ... is not found` (an `augment` target is missing because the module that defines it was not loaded). The import closure needed for a zero-error `/native/ntp` tree (each file removed in turn, every removal produced errors): `cisco-semver`, `Cisco-IOS-XE-types`, `-features`, `-interface-common`, `-interfaces`, `-ip`, `-ipv6`, `-hsrp`, `-license`, `-line`, `-location`, `-logging`, `-parser`, `-transceiver-monitor`, `-transport` (15 files) plus `Cisco-IOS-XE-native` and `-ntp`. `-p` must point at the directory holding them. Note: pyang also searches the current directory, so test the closure from a clean directory. The five IETF/IANA modules are needed for R3/R5, not for R4.

R5/R6: `python3 -m json.tool ~/lab059/loopback100.json` prints the body indented; `xml.dom.minidom.parse` on the XML prints the pretty-printed document with the two namespaces. The R5 body was sent to AUTO-RTR3 in LAB-060 (see its SOLUTION.md for the 201).

## Failure / Recovery Behaviour

NAT failure: `sudo ip link set ens3 down` on AUTO-MGMT1. Result: `ping 8.8.8.8` -> `Network is unreachable`; `pip download pyang==2.7.1` -> `No matching distribution found`; the already installed `~/venv/bin/pyang --version` still prints `pyang 2.7.1` and the `trees/` files are unaffected. Recovery: `sudo ip link set ens3 up` (no `dhclient` on this image; systemd-networkd re-runs DHCP by itself).

| Scenario (trigger, end condition) | Runs (raw) | Documented range | Basis |
|---|---|---|---|
| `ip addr flush dev ens3` + `ip link set ens3 up` until `ping 8.8.8.8` succeeds (DHCP renewed through NAT) | 1146, 1090, 1092 ms (a plain down/up that keeps the address: 80 ms) | about 0.5 to 1.5 s (other runs: 1.1 s, 0.6 s) | networkd DHCP exchange; no protocol timer |
| install times via NAT (info): `apt-get update` + `install python3-venv` 47 s; `pip install pyang==2.7.1` into a fresh venv 7 s | one run each | under 2 min | download-bound |

Restore to the start state: node stop, wipe, start of AUTO-MGMT1 (booted in 52 s); the start-state checks matched the first run.

## Answers to Analysis Questions

**Q1.** The JSON standard (RFC 8259) defines no comment syntax: a document is pure data to keep parsers simple and interoperable. A configuration file in JSON therefore cannot explain itself: document in a separate file, a README or the filename/version control; or use a `"_comment"` key (which becomes data every consumer sees) or a superset such as YAML or JSON5, accepting that strict parsers reject it.

**Q2.** A container groups child nodes and exists at most once per parent; a list is a collection of entries of the same shape, each entry identified by the key leaf(s) (`interface* [name]`). The key makes each entry addressable (RESTCONF URL `interface=Loopback100`, NETCONF merge/replace targeting) and lets the server tell create from update; without a key there is no way to name one entry among many.

**Q3.** `config false` data is operational state (counters, oper-status, learned neighbours); the tree marks it `ro` (configuration is `rw`). RESTCONF returns it from the operational datastore, which `GET /restconf/data/...` merges with the running configuration, while `config` writes (POST/PUT/PATCH) only apply to configuration. `interfaces-state` is the example in this lab.

**Q4.** From the model: node names, hierarchy, types (identityref, boolean), the key `ip`, which leaves exist (`name`, `description`, `type`, `enabled`, `ipv4/address/ip/netmask`), which module owns them (the `ietf-ip:` prefix because `ipv4` is an augment from another module). From the encoding: braces, quotes, arrays (JSON) versus tags, `xmlns` and repeated elements (XML), the RFC 7951 `module:node` qualification (JSON) versus namespaces (XML), and the textual form of booleans and identityref values.

**Q5.** Native models mirror the device's CLI one-to-one and cover every feature (the NTP access-group tree in R4); IETF/OpenConfig models are vendor-neutral but cover only the common subset and are implemented to varying depth. A multi-vendor script gains portability from IETF/OpenConfig but loses features and may hit gaps; native models give completeness at the cost of one code path per vendor and per software release.

**Q6.** `node X is not found` means the module that defines the augment target (or the module being augmented) was not loaded or not imported; `augment` extends a node owned by another module, so that module must be in the set pyang loads and the search path (`-p`) must lead to it. `import` makes names from another module visible; a missing import gives `module "X" not found in search path`, and the augment errors are the consequence (47 of 328 lines here).

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-17 |
| CML | 2.10.0 |
| Node types | external_connector, ubuntu (Ubuntu 24.04) |
