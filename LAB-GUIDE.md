# How to work a lab

Every lab in this pack follows the same pattern. This guide explains what each part of a lab is for, what you are expected to produce, and how to use `SOLUTION.md` without spoiling the lab.

The short version: **a lab is finished when your notes hold text evidence for every Verification Criterion and an answer to every Analysis Question** (what that looks like is under "Your lab notes" below). Configuring the devices is only part of the work. The `show` output, measurements and pings that prove the result are part of what the lab asks for, and `SOLUTION.md` shows the expected version of exactly that evidence.

## What is in a lab folder

| File | What it is | When to open it |
|---|---|---|
| `LAB.md` | The brief: scenario, topology, start state, tasks, success criteria, questions | First, and keep it open while you work |
| `topology.svg` | The topology diagram, also shown at the top of LAB.md's Available Information | Any time |
| `LAB-NNN.yaml` | The CML topology with the start state already configured | Import it into CML |
| `SOLUTION.md` | Reference answer: configuration, expected output, answers | Only after you have finished (see below) |
| `*.pcap`, `BUILD.md` | Packet captures or a build procedure, in the few labs that use them | When LAB.md points to them |

## Reading the LAB.md header

The first line under the title gives the lab's type, guidance tier and estimated time.

**Type** tells you what kind of work the lab is:

| Code | Type | What you do |
|---|---|---|
| F | Foundation | Configure a technology (often named for you) and observe how it behaves |
| I | Implementation | Build to requirements stated as behaviour; you choose how |
| X | Expansion | Extend an existing network; earlier technologies are assumed |
| A | Analysis | Inspect a running network and explain it; little or no configuration |
| T | Troubleshooting | Find and fix faults from symptoms only |
| N | Integration | Several technologies at once, with outcome-based requirements |
| M | Milestone | Change requests and tickets across everything learned so far, with minimal guidance |

Two codes (`F/A`, `T/N` and so on) mean the lab mixes both.

**Guidance tier** tells you how much help the wording gives you:

- **G3 (guided):** the technology is named and the requirements are fairly specific.
- **G2 (requirements):** you get the required behaviour; you decide which technology or feature delivers it.
- **G1 (independent):** you get business outcomes or user tickets only.

Some labs mix tiers, for example G3 for the first device and G2 for the rest; the header says so. Labs move from G3 towards G1 through the course, so expect less hand-holding in later modules. That is deliberate.

**Estimated time** includes waiting for nodes to boot and protocols to converge, and any failure tests the lab asks for.

## The sections of LAB.md, and what you produce for each

Some sections are only for reading. The others each ask you to write something in your lab notes (next section).

| Section | What it gives you | What you produce |
|---|---|---|
| Scenario | The story and why the work matters | Nothing |
| Objectives | What you should be able to do afterwards | Nothing; check yourself against it at the end |
| Available Information | Topology, cabling, addressing, device logins, platform notes | Nothing; use it as reference. Note anything you find that doesn't match the lab |
| *Technology* in brief | A primer, in the first lab that uses a technology | Nothing; read it before you start, because later labs assume it |
| Starting State | What is already configured and working when the lab boots | **Baseline:** for each statement, the command and output that confirm it, captured before you change anything |
| Requirements / Change Requests (R1, R2, …) | The work to do | **Per R item:** the configuration you applied, per device, as text, plus one line on any choice you made and why |
| Reported Problems (T1, T2, …) | Tickets: symptoms, never causes (troubleshooting and milestone labs) | **Per ticket:** the symptom reproduced, your diagnosis steps, the root cause, the fix, and evidence that it is fixed |
| Verification Criteria (V1, V2, …) | What must be true, and the evidence you must show | **Per V item:** the proof (command and output, or measurements), and one sentence on why it proves the item |
| Analysis Questions (Q1, Q2, …) | Questions about what you saw and why | **Per Q item:** a written answer of a few sentences that cites your own evidence |

## Your lab notes: the work you produce

The Verification Criteria are the step that is easiest to miss. A V item is not just "check it works": the evidence that proves it is part of the lab, and it is what you compare with `SOLUTION.md`.

### Where to keep them

- **One Markdown or plain-text file per lab**, for example `LAB-017-notes.md`, kept in your own folder (for example `my-work/LAB-017/`). Don't write into `LAB.md`: keep the brief clean so you can redo the lab, and so a newer copy of the pack can replace it without losing your work.
- **Text, not pictures.** Everything on a router, a switch or a Linux host is text, so copy the command output from the console and paste it in. Text is searchable, it can be compared line by line with `SOLUTION.md`, and it is what you would paste into a change record or a ticket at work.
- **Screenshots only where the evidence exists only on screen:** the CML UI (node settings, link states), a web dashboard such as the SD-WAN Manager, or a Wireshark window. Save them next to your notes (`my-work/LAB-017/v3-capture.png`), link them from the V item, and add a sentence on what the picture shows. Never take a photo of terminal text; copy the text.
- **Packet captures:** keep the `.pcap` file in the same folder, and paste the few decoded lines that matter (from `tshark` or Wireshark) into your notes.

### How to write each piece of evidence

- **Always include the prompt and the command.** The prompt (`R1#`) shows which device the output came from: `R1# show ip route 192.0.2.0`.
- **Trim, but don't edit.** Keep the lines that prove the point, use `| include`, `| section` or `| begin` where it helps, and replace removed lines with `...`. Never retype or change the output.
- **Measurements as a small table:** what you did, what you measured, and how. For example: link shut on R2 e0/0, 3 pings lost at 1 per second, so an outage of about 3 s, detected by the log line `%OSPF-5-ADJCHG ... Down`.
- **Before and after:** label the two blocks, and capture "before" before you change anything.
- **Every device, direction or site** that the V item names gets its own output.
- **One sentence of reasoning** under each block: what in the output proves the item. "Output above" on its own is not proof.

### A notes skeleton

Copy it for each lab and delete the parts the lab doesn't have. Number the headings after the lab's own R, T, V and Q items.

````markdown
# LAB-NNN notes

## Baseline (Starting State)
```
R1# show ip ospf neighbor
...
```
Matches Starting State: all four neighbours FULL.

## Work done
### R1: <short title>
Changed R1 and R2:
```
router ospf 1
 ...
```
Choice: <what you chose, and why>.

## Tickets (troubleshooting and milestone labs)
### T1
- Symptom (before): <output reproducing the problem>
- Diagnosis: hypothesis → command → result → conclusion, one line each
- Root cause: <device, what was wrong>
- Fix: <exact commands>
- After: <output showing it fixed>

## Verification
### V1: met (or: partly met, not met, and why)
```
R1# show ...
...
```
Proves V1 because <the line or value that shows it>.

### V2: met (measurements)
| Case | Trigger | Lost | Outage | Detected by |
|---|---|---|---|---|
| 1 | ... | ... | ... | ... |

## Analysis
### Q1
<answer in a few sentences, citing V1 and V2>

## Compared with SOLUTION.md (after you finish)
<what matched, what you missed, what you did differently>
````

A lab is complete when every R item (or ticket) and every V item has its evidence in your notes and every Q item has an answer. A typical lab's notes run to one or two screens per V item, not pages of raw output.

## Working the lab, step by step

1. **Read the whole LAB.md first**, including the Verification Criteria and Analysis Questions, so you know what evidence to collect as you go. Don't open `SOLUTION.md`.
2. **Import and start the lab.** CML UI: *Import Lab* and select `LAB-NNN.yaml`; or `tools/cml-rest.sh import LAB-NNN.yaml`. Start it and wait until every node has booted. Each lab's YAML holds its full start state, so labs don't depend on your previous lab.
3. **Confirm the Starting State** with `show` commands and save the output as your baseline.
4. **Do the work:** the Requirements in a build lab, the tickets in a troubleshooting lab, the questions in an analysis lab. Save evidence as you go, not afterwards.
5. **Prove every V item** and write it into your notes.
6. **Answer every Analysis Question** in writing, using your own output as the argument.
7. **Now open `SOLUTION.md`** and compare (next section).
8. **Clean up.** Stop the lab when you're done. Wipe or delete it if you need the server resources; you can always import a fresh copy.

## Using SOLUTION.md

Open it only after steps 1–6. Reading it earlier turns the lab into copying, especially in troubleshooting labs.

| SOLUTION.md section | Compare it with |
|---|---|
| Summary | What the lab was meant to teach; check your Objectives |
| Intentional Faults (T and M labs) | The causes of the tickets. Did you find each one, and fix it at its cause? |
| Diagnosis / Methodology | The evidence path an engineer would follow. Compare it with your own route; a different route that is evidence-based is fine |
| Solution Configuration | One working configuration. Yours may differ and still be correct if every V item holds |
| Verification | Captured output from a working lab: the expected version of **your V-item evidence** |
| Failure / Recovery Behaviour | What happened when things were broken on purpose, with measured timings and their normal range |
| Answers to Analysis Questions | Model answers. Check your reasoning, not just your wording |
| Lab Info | Last-modified date, CML version and node images |

Your output won't match the captured output character for character. Counters, uptimes, timestamps, MAC addresses, hash-based choices and measured times vary between runs. What must match is the state: the neighbours, routes, roles, next hops and pass/fail results. Output marked `(derived)` was worked out rather than captured.

## Troubleshooting labs (T) and milestones (M)

- **Reproduce each ticket first** and capture the symptom. That is your "before" evidence.
- **Work from evidence, not guesses.** Form a hypothesis, test it with a command, and narrow the problem down. Note each step; the Diagnosis section of the solution is compared against this.
- **Fix at the cause, with the smallest change.** Don't rebuild a device's configuration from scratch. A workaround that makes the symptom go away (a static route over a broken protocol, for example) is not a fix.
- **Don't stop at the first fault.** A lab may have one fault or several, and they can interact. Close every ticket, then check that the whole documented design still holds, not just the ticket.
- **Capture "after" evidence** for each ticket.
- Milestones read like a working day: change requests and tickets together, across everything up to that point. Plan before you type.

## Analysis labs (A)

Most of the work is reading state and explaining it. The deliverable is your written answers, each backed by output you captured. "Because the book says so" is not evidence; a `show` command is.

## If something doesn't work

- Re-check **Available Information**, especially the platform notes where the lab has them. They list behaviours of the CML images that differ from real hardware.
- If the start state isn't what Starting State says, wait for boot and convergence to finish. If it still doesn't match, stop, wipe and start the lab again, or import a fresh copy.
- If you are sure a lab is wrong, note the lab ID, what you expected and what you saw.
