# LAB-059 — JSON and YANG

**Module:** 09 Programmability and Automation · **Type:** F (Foundation) · **Guidance tier:** G3 (the technology is named; you choose the exact commands) · **Estimated time:** 90 min · **Blueprint objectives:** 6.2:I, 6.3:I

## Scenario

Veridian's automation team will manage the new virtual routers of the AUTO site through their APIs. Before anyone touches a device, the network team learns to read the data those APIs exchange. You work only on the automation host, AUTO-MGMT1, with the data files and the models Cisco publishes. No router is involved; the body you build in R5 is used again in LAB-060.

## Objectives

- Read and validate JSON, and name the type of every value.
- Extract values from a JSON document with `jq` and with Python.
- Read a YANG module through `pyang -f tree`: containers, lists and keys, leaves, optional and state data.
- Tell a data model from its encoding (JSON or XML).
- Build a RESTCONF-ready JSON body, and the same instance in XML, from the models alone.

## Available Information

![LAB-059 topology](topology.svg)

| Item | Value |
|---|---|
| Host | AUTO-MGMT1, user `cisco`, password `cisco` (sudo allowed) |
| Installed | `curl`, `jq`, `python3` 3.12, `requests`; no `pip`, no `pyang`, no virtual environment |
| Internet | via `ens3` (NAT). Every online step has an offline fallback below |
| Python packages | pinned: `pyang==2.7.1`, in a virtual environment `/home/cisco/venv` |

Files already on the host (read-only data, do not edit the originals; work on copies):

| Path | Content |
|---|---|
| `/home/cisco/json/` | `ntp-servers.json`, `banner.json`, `inventory.json`, `restconf-interfaces-reply.json` |
| `/home/cisco/yang/` | 22 YANG modules (IETF: `ietf-interfaces`, `ietf-ip`, `ietf-inet-types`, `ietf-yang-types`, `iana-if-type`; Cisco IOS XE 17.16.1: `Cisco-IOS-XE-native`, `Cisco-IOS-XE-ntp` and the other modules they import) |
| `/home/cisco/trees/` | `ietf-interfaces.txt` and `native-ntp.txt`: pre-generated `pyang -f tree` output (offline fallback for R3 and R4) |

`restconf-interfaces-reply.json` is a **captured** reply: `GET https://<AUTO-RTR3>/restconf/data/ietf-interfaces:interfaces` with `Accept: application/yang-data+json`, taken from a Cisco Catalyst 8000V (IOS XE 17.16.1a). It is real device output.

## Starting State

AUTO-MGMT1 is booted with the NAT link up (a DHCP address on `ens3`) and the files above in place. Nothing else is installed. `ntp-servers.json` and `banner.json` are deliberately broken (exercise material). Create your working directory `/home/cisco/lab059/` yourself.

## YANG trees in brief

A YANG module describes the data a device exposes as a tree of nodes. `pyang -f tree` (RFC 8340) prints that tree, one node per line, indented by depth. Reading it is the skill R3 and R4 test:

- `module:` names the module that defines the nodes below it. When a second module adds nodes to another module's tree, the output shows `augment <path>:` under the augmenting module, so you see which module a node comes from.
- `rw` marks a configuration node you can write; `ro` marks a read-only node (`config false`: operational state such as counters). `-x` marks an RPC or action and `-n` a notification.
- A suffix after the name shows the node's cardinality: `?` optional (it may be absent), `*` a list or a leaf-list (several entries), no suffix a mandatory leaf or a container.
- `[name]` after a list shows the key leaf or leaves that identify one entry.
- `!` after a container marks a presence container: its existence itself carries meaning (configured or not); without `!` a container only groups nodes.
- Parentheses `(choice)` and `:(case)` show alternatives of which one is used; `{feature}?` after a leaf means it exists only where the device implements that feature.
- The type follows the name (`string`, `uint8`, `inet:ipv4-address`, `boolean`). A prefix such as `inet:` points to the module that defines the type, which is why a tree can fail to print when an imported module is missing.

Entry commands: `pyang -f tree <module>.yang` (use `-p <dir>` for the directory holding imported modules), `pyang -f tree --tree-path /native/ntp <module>.yang` for one subtree.

## Requirements / Change Requests

R1: Validate the four JSON files with a JSON parser. Find the error in each invalid file, fix it in a copy in `/home/cisco/lab059/`, and show that the copy is valid. For `restconf-interfaces-reply.json`, state the JSON type (object, array, string, number, boolean or null) of: the top-level value, the value of `"interface"`, `"name"`, `"enabled"`, and `"ietf-ip:ipv6"` of Gi3.

R2: From the captured reply, list every interface name with its `enabled` value, once with `jq` and once with three lines of Python using `json.load`. Both outputs must agree.

R3: Install `pyang` 2.7.1 in a virtual environment `/home/cisco/venv` (offline fallback: use the files in `trees/`). Print the tree for `ietf-interfaces` together with the `ietf-ip` augmentation. Mark, on your own copy of the output, the list key of `interface`, a state (read-only) leaf, an optional leaf, a leaf-list, and a presence container.

R4: Print only the `/native/ntp` subtree of `Cisco-IOS-XE-native` (the NTP part of the native IOS XE model) with a zero-error tree. Then reproduce the failure when the modules `native` imports are missing and count the error lines.

R5: From the trees alone, write a JSON body that creates interface `Loopback100` with description `API test`, type software loopback and IPv4 address 10.255.90.100/32, using the `ietf-interfaces` and `ietf-ip` models, with `module:node` qualified names where RFC 7951 requires them. Save it as `/home/cisco/lab059/loopback100.json`; it must pass the JSON validator.

R6: Write the same instance in XML (`/home/cisco/lab059/loopback100.xml`) with the correct namespaces, and list what changed and what did not between the JSON and the XML.

## Verification Criteria

V1: The corrected copies of `ntp-servers.json` and `banner.json` are accepted by `python3 -m json.tool` and by `jq .`; the originals are unchanged and still rejected.

V2: The `jq` and Python outputs of R2 list five interfaces with identical `name`/`enabled` pairs.

V3: `/home/cisco/venv/bin/pyang --version` prints `pyang 2.7.1` (or the `trees/` files were used and the fallback is stated).

V4: The R3 output contains the `ietf-ip` `ipv4` and `ipv6` containers under `interface`, and you can point to the five marked elements.

V5: The R4 subtree output has no error line and contains `+--rw ntp` under `native`; the broken run prints more than 100 lines in total, and you can name the two kinds of message in it.

V6: `loopback100.json` is valid JSON, its top-level key is `ietf-interfaces:interface`, its `type` value is `iana-if-type:softwareLoopback`.

V7: `loopback100.xml` is well-formed (`python3 -c 'import xml.dom.minidom as m; m.parse("...")'`) and declares the `ietf-interfaces` namespace on its root element and the `ietf-ip` namespace on the IPv4 container.

V8: Toolkit: `ping -c 2 8.8.8.8` succeeds; with `ens3` down the installed `pyang` and the `trees/` files still work.

## Analysis Questions

Q1: Why does JSON have no comments, and what does that mean for how you document a configuration file that is JSON?

Q2: What is the difference between a YANG container and a list, and why does a list need a key?

Q3: What is `config false` data, which marker shows it in a `pyang` tree, and which RESTCONF datastore returns it?

Q4: Model versus encoding: one YANG model, two encodings. Which parts of R5 and R6 come from the model, and which from the encoding?

Q5: Why do vendors ship native models next to the IETF and OpenConfig ones, and what is the trade-off for a script that must manage devices of several vendors?

Q6: What does the `pyang` error `node ... is not found` tell you about YANG `augment` and `import`?
