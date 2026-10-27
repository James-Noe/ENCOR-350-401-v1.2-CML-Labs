# How to work a lab

Every lab in this pack follows the same pattern. This guide explains what each part of a lab is for, what you are expected to produce, and how to use `SOLUTION.md` without spoiling the lab.

The short version: **a lab is finished when its `ANSWERS.md` holds text evidence for every Requirement and Verification Criterion and an answer to every Analysis Question** (what that looks like is under "Your answer file" below). Configuring the devices is only part of the work. The `show` output, measurements and pings that prove the result are part of what the lab asks for, and `SOLUTION.md` shows the expected version of exactly that evidence.

## What is in a lab folder

| File | What it is | When to open it |
|---|---|---|
| `LAB.md` | The brief: scenario, topology, start state, tasks, success criteria, questions | First, and keep it open while you work |
| `topology.svg` | The topology diagram, also shown at the top of LAB.md's Available Information | Any time |
| `LAB-NNN.yaml` | The CML topology with the start state already configured | Import it into CML |
| `SOLUTION.md` | Reference answer: configuration, expected output, answers | Only after you have finished (see below) |
| `*.pcap`, `BUILD.md` | Packet captures or a build procedure, in the few labs that use them | When LAB.md points to them |
| `ANSWERS.md` | Your answer file: one blank section per R item and per Q item, which you fill in | As you work |
| `GRADING.md` | Feedback on your answers, written when you have Claude Code grade them (see "Grading your answers"); not there until then | After grading |

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

Some sections are only for reading. The others each ask you to write something in your `ANSWERS.md` (next section).

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

## Your answer file: the work you produce

The Verification Criteria are the step that is easiest to miss. A V item is not just "check it works": the evidence that proves it is part of the lab, and it is what you compare with `SOLUTION.md`.

### Where to keep them

- **Write your work into the lab's `ANSWERS.md`.** It has one section per requirement (**Commands used**, **Command output**, **Explanation**) and one per Analysis Question (**Answer**). Keep those headings as they are; grading follows them. Don't write into `LAB.md`: keep the brief clean so you can redo the lab.
- **Sections you add yourself.** Verification Criteria have no section of their own: put each V item's evidence in the R section that delivers it, and name it in the Explanation (`V2: met, because …`). Add `## Baseline` at the top for the Starting State output, and in troubleshooting labs and milestones a `## T1`, `## T2`, … section per ticket with the same three headings.
- **When you get a newer copy of the pack**, its `ANSWERS.md` files are blank again. Keep your `ANSWERS.md`, `GRADING.md`, screenshots and captures: copy them into the new pack's lab folders (replacing the blank `ANSWERS.md`), or keep your old copy of the pack next to the new one.
- **Text, not pictures.** Everything on a router, a switch or a Linux host is text, so copy the command output from the console and paste it in. Text is searchable, it can be compared line by line with `SOLUTION.md`, and it is what you would paste into a change record or a ticket at work.
- **Screenshots only where the evidence exists only on screen:** the CML UI (node settings, link states), a web dashboard such as the SD-WAN Manager, or a Wireshark window. Save them in the lab folder next to `ANSWERS.md` (`LAB-017/v3-capture.png`), link them from the section they prove, and add a sentence on what the picture shows. Never take a photo of terminal text; copy the text.
- **Packet captures:** keep your `.pcap` file in the lab folder too, named so it can't be confused with a capture the lab ships (`my-v3.pcap`), and paste the few decoded lines that matter (from `tshark` or Wireshark) into `ANSWERS.md`.

### How to write each piece of evidence

- **Always include the prompt and the command.** The prompt (`R1#`) shows which device the output came from: `R1# show ip route 192.0.2.0`.
- **Trim, but don't edit.** Keep the lines that prove the point, use `| include`, `| section` or `| begin` where it helps, and replace removed lines with `...`. Never retype or change the output.
- **Measurements as a small table:** what you did, what you measured, and how. For example: link shut on R2 e0/0, 3 pings lost at 1 per second, so an outage of about 3 s, detected by the log line `%OSPF-5-ADJCHG ... Down`.
- **Before and after:** label the two blocks, and capture "before" before you change anything.
- **Every device, direction or site** that the V item names gets its own output.
- **One sentence of reasoning** under each block: what in the output proves the item. "Output above" on its own is not proof.

### A filled-in answer file

Part of one, to show what goes where. The R and Q sections come with the file; `## Baseline` and the `V1:` lines are yours.

````markdown
# LAB-NNN — Answers

## Baseline
```
R1# show ip ospf neighbor
...
```
Matches Starting State: all four neighbours FULL.

## R1 — <title from LAB.md>
**Commands used:**
```
R1(config)# router ospf 1
R1(config-router)# ...
R1# show ip ospf interface brief
```
**Command output:**
```
R1# show ip ospf interface brief
...
```
**Explanation:**
Changed R1 and R2 as above. Choice: <what you chose, and why>.
V1: met, because <the line or value in the output that shows it>.

## Q1
**Answer:**
<a few sentences, citing your output under R1>
````

For a ticket (`## T1`): the symptom output and your diagnosis commands go under **Commands used** and **Command output**, one hypothesis → command → result step at a time; the **Explanation** gives the root cause (device, what was wrong), the exact fix, and the "after" output that shows it fixed. Measurements go in the Explanation as a small table.

A lab is complete when every R item (or ticket) and every V item has its evidence in `ANSWERS.md` and every Q item has an answer. A typical lab's answers run to one or two screens per V item, not pages of raw output.

## Working the lab, step by step

1. **Read the whole LAB.md first**, including the Verification Criteria and Analysis Questions, so you know what evidence to collect as you go. Don't open `SOLUTION.md`.
2. **Import and start the lab.** CML UI: *Import Lab* and select `LAB-NNN.yaml`; or `tools/cml-rest.sh import LAB-NNN.yaml`. Start it and wait until every node has booted. Each lab's YAML holds its full start state, so labs don't depend on your previous lab.
3. **Confirm the Starting State** with `show` commands and save the output under `## Baseline` in `ANSWERS.md`.
4. **Do the work:** the Requirements in a build lab, the tickets in a troubleshooting lab, the questions in an analysis lab. Save evidence as you go, not afterwards.
5. **Prove every V item** and write the evidence into the R section it belongs to.
6. **Answer every Analysis Question** in writing, using your own output as the argument.
7. **Now open `SOLUTION.md`** and compare (next section).
8. **Optionally, have your answers graded** (see "Grading your answers").
9. **Clean up.** Stop the lab when you're done. Wipe or delete it if you need the server resources; you can always import a fresh copy.

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

## Grading your answers

The pack root holds a `CLAUDE.md`: grading instructions for Claude Code. Open Claude Code in the pack folder and ask it to grade a lab, for example "grade LAB-017". It reads the lab's `ANSWERS.md` (or, if that is blank, other notes in the lab folder, and says which file it graded) and writes its review to `GRADING.md` in the same folder, newest review at the top under a dated heading, older reviews kept. It grades by what would help or hurt on the exam, not by how closely you followed `SOLUTION.md`, which it doesn't treat as automatically right. The review lists, in order: what would cost exam marks (each rated High, Medium or Low and tied to a blueprint objective), gaps to study, what is already exam-ready, and briefly, any skipped steps or missing output.

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
