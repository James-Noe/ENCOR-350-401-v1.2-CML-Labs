# LAB-076 — Catalyst Center and AI workflows

**Module:** 11 Controllers and Architecture · **Type:** A (Verification/Analysis) · **Guidance tier:** G1 · **Estimated time:** 120 min · **Blueprint objectives:** 4.5:A, 6.4:P, 6.5:R

## Scenario

Veridian is evaluating Catalyst Center for the campus. The vendor sent an API sandbox export. You have no Catalyst Center appliance: a local stand-in on the automation host serves the vendor's saved responses (inventory, assurance, command-runner results), shaped after the published Catalyst Center Intent API reference. Every response is a `(derived)` fixture, not data from a live controller, and the stand-in never changes any device.

The automation team wants to know how its scripts would work against this API, and whether the "AI-powered" features in the sales deck would help or hurt operations. Your manager wants a short written assessment, backed by scripts that run.

## Objectives

- Authenticate to a controller API and read inventory and assurance data with a script.
- Compare this API's authentication with the SD-WAN Manager session and the Basic-over-HTTPS login you used earlier.
- Use an asynchronous API correctly: accept a "request received" answer, poll for the outcome, collect the result and handle a failure.
- Keep a script working across a credential that expires.
- Judge traditional and AI-driven assurance, and an assistant's proposed change, on evidence.

## Available Information

```
AUTO-MGMT1 (Ubuntu 24.04, console login cisco / cisco)
   no network links; everything runs on this host
   Catalyst Center stand-in:  https://127.0.0.1:9443   (self-signed certificate)
```

| Item | Value |
|---|---|
| API user (HTTP Basic, token request only) | `catc-api` / `Sandbox#2026` |
| Stand-in certificate | `/home/cisco/catc/certs/catc.pem` |
| Request log of the stand-in | `/home/cisco/catc/logs/requests.log` |
| Your working directory (scripts and written assessment) | `/home/cisco/catc/work/` |
| Assistant chat export (ticket NET-4417) | `/home/cisco/catc/ai/assistant-transcript.md` |
| Tools | `python3` (3.12) with the `requests` library, `curl`, `openssl`, `jq` |

Vendor API reference extract (all paths are on the base URL above):

| Method and path | Purpose |
|---|---|
| `POST /dna/system/api/v1/auth/token` | Returns `{"Token": ...}`; Basic authentication |
| `GET /dna/intent/api/v1/network-device` | Device inventory (optional `hostname` filter) |
| `GET /dna/intent/api/v1/network-device/count` | Number of devices (small, cheap call; optional `hostname` filter) |
| `GET /dna/intent/api/v1/site-health` | Health per site |
| `GET /dna/intent/api/v1/issues` | Assurance issues: `issueId`, `name`, `siteId`, `deviceId`, `deviceRole`, `aiDriven` ("YES"/"NO"), `priority`, `category`, `status`, `issue_occurence_count`, `last_occurence_time` (epoch ms). The stand-in's issues also carry `description`, `baseline`, `observed` and `suggestedActions`, which the real list endpoint does not; treat them as the issue's detail data |
| `POST /dna/intent/api/v1/network-device-poller/cli/read-request` | Command runner: body `{"commands": [...], "deviceUuids": [...]}`; read-only commands |
| `GET /dna/intent/api/v1/task/{taskId}` | State of an asynchronous task |
| `GET /dna/intent/api/v1/file/{fileId}` | Result file of a finished task |

Every intent request carries the token in the header `X-Auth-Token`. Error answers carry a JSON body. The vendor states that tokens in production last 60 minutes; the stand-in uses a shorter lifetime so that you can see expiry within a lab session.

Earlier labs for comparison: LAB-073 (SD-WAN Manager session cookie and XSRF token), LAB-060 (RESTCONF with HTTP Basic over HTTPS), LAB-062 (status codes and saved Catalyst Center responses).

## Starting State

The stand-in is running and its fixtures are loaded. Your working directory is empty. All consoles open in privileged mode where the platform has one; AUTO-MGMT1 opens as user `cisco` with sudo. Nothing else is installed or configured for you.

## Catalyst Center assurance in brief

Catalyst Center is the controller for campus and branch networks built on Catalyst switches and routers: it keeps an inventory of the devices, deploys configuration through templates and workflows (the Provision workflow), and watches the network (the Assurance workflow). Assurance collects health scores per site, device and client, and raises **issues** (a problem with a priority, a category, the device it concerns and suggested actions). Two kinds of issue appear side by side:

- **Rule-based issues:** a fixed threshold or condition (for example a device not answering for several polls) raises the issue. You confirm it by checking the condition on the device.
- **AI-driven issues** (`aiDriven` = "YES"): the controller learns a baseline for a metric from past data, then flags observations that deviate from it. An issue like this is only as good as the data the baseline was learned from and the period it is judged against, so you confirm it by looking at both, not just at the claim.

The **command runner** lets you run read-only `show` commands on managed devices through the API. It is asynchronous: the request is accepted first, the work happens later, and the output is fetched as a file. Entry points are the paths in the reference table above (`site-health`, `issues`, `network-device`, `task`, `file`).

## Requirements / Change Requests

R1: With a script, authenticate and list the inventory: platform, software version, reachability and role per device. In your assessment, compare this API's authentication with LAB-073's and LAB-060's: what is sent on every request, what expires and when, and what an attacker who steals each value can do.
R2: Read site health and the two assurance issues. For each issue, say whether it came from a fixed threshold rule or from a learned baseline (AI-driven), using the issue's own fields, the Catalyst Center workflow that handles it, and what that means for how you confirm it; also state which device-level evidence an engineer would collect (using commands from earlier labs) to confirm it, and whether the AI-driven issue's own claim is supported by the data the issue carries.
R3: Run one read-only command on a reachable device and on the device the inventory shows as unreachable, through the command-runner API. Your script must not assume the first answer is the result. Report the failed device's error exactly as the API gives it.
R4: Make your script survive token expiry: one re-authentication when the API refuses the token, no endless retry, and a demonstration (with timestamps) that it keeps working across an expiry.
R5: Critique the assistant's proposed change in the chat export: evidence for and against it, the blast radius, the approvals and pre-checks and post-checks it needs, and which API calls would verify the outcome. Nothing can be tested on a device here. The deliverable is the critique.

Write your scripts and one written assessment (R1, R2, R5 and the answers below) in `/home/cisco/catc/work/`.

## Verification Criteria

V1: A script of yours lists all inventory devices with the four attributes of R1 in one run and authenticates by itself.
V2: The assessment compares the three authentication models on the three points of R1.
V3: For both issues the assessment says whether a threshold rule or a learned baseline raised it, the Catalyst Center workflow involved, at least two pieces of device-level evidence and a verdict (supported, partly supported or unsupported) on the issue's own data, quoting the numbers it relies on.
V4: A script run shows the command-runner request accepted, at least one status poll before the result, the result of the reachable device, and the failed device's error text.
V5: A run longer than the token lifetime shows successful calls before and after expiry and exactly one re-authentication.
V6: The critique names at least three risks of the proposal with a mitigation each, and the API calls and device-side evidence that would verify the outcome.
V7: Toolkit: the stand-in's request log shows your scripted calls, including one refused request followed by a token request and a successful retry, and a 202 answer followed by task polls.
V8: No script of yours sends anything to the stand-in except the token request, the read-only requests of the extract above and (for R3) the command-runner request.

## Analysis Questions

Q1: What does an HTTP 202 promise, and what does it not?
Q2: Why do intent APIs hide the device CLI, and when does that help or hurt troubleshooting?
Q3: Compare traditional (threshold) and AI-powered assurance: what can a baseline detect that a threshold cannot, and what can it not explain?
Q4: Which of the three authentication models (LAB-073, LAB-076, RESTCONF) would you choose for an unattended nightly job, and why?
Q5: How would you roll out an API-driven change to 200 switches safely?
