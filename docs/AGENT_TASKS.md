# LCL — AgentTask Architecture

A long-running piece of AI work is a **first-class persistent object**, not a conversation that happens
to still be open. It outlives the ChatView, the app process, and the model's residency in memory
(spec §26).

---

## 1. Model

```swift
struct AgentTask: Identifiable, Codable {
    let id: UUID
    var title: String
    var goal: String
    var status: TaskStatus
    var plan: AgentPlan
    var originChatID: UUID?          // where it started — not an owner
    var projectID: UUID?
    var repository: RepoRef?
    var branch: String?
    var commits: [CommitRef]
    var builds: [BuildRef]
    var decisions: [Decision]
    var research: [ResearchBriefRef]
    var checkpoint: Checkpoint?
    var permissionGrant: PermissionGrant?   // task-scoped autonomy, if granted
    var events: [TaskEvent]                 // append-only
    var createdAt: Date
    var updatedAt: Date
}

enum TaskStatus: String, Codable {
    case scheduled          // will start later
    case waitingForSystem   // handed to BGTaskScheduler; iOS decides
    case running
    case waitingForModel    // needs the model; app must be foreground
    case waitingForUser     // needs a decision or a permission
    case suspended          // checkpointed, resumable
    case completed
    case failed
    case cancelled
}
```

`waitingForModel` exists because of a platform fact, not a design preference: **the model cannot run
in the background on iPhone** (no background GPU — see [RESEARCH_LOG.md](RESEARCH_LOG.md) §6). Making
it an explicit status means the UI can be honest and the resume path can be obvious.

`originChatID` is deliberately not an owner. A task belongs to the user, not to a chat (spec §72): ask
*"how's the Model Manager going?"* in a brand-new chat and retrieval finds the task by title, goal and
branch, and injects its current state.

---

## 2. Plans

The plan lives in the host database, not in an old model message (spec §30). The model proposes plan
mutations; the host applies and persists them.

```swift
struct AgentPlan: Codable {
    var steps: [PlanStep]
    var currentStepID: UUID?
    var revision: Int
    var history: [PlanRevision]   // every prior version, with the reason for the change
}

struct PlanStep: Codable, Identifiable {
    let id: UUID
    var title: String
    var status: StepStatus        // pending | active | done | failed | skipped
    var needsModel: Bool          // ← determines background eligibility
    var note: String?
}
```

Tools the model gets (spec §31): `create_plan`, `update_plan`, `add_plan_step`, `complete_plan_step`,
`fail_plan_step`, `replan`.

Before each significant action the model receives **Goal + Plan + Current Step + relevant state** —
freshly assembled, not recalled. This is what keeps a small model on task across twenty steps.

`replan` is legitimate and expected: research routinely invalidates a plan written before the research
(spec §32). Every revision is retained with its reason. A materially different plan is surfaced to the
user rather than silently swapped.

`needsModel` on each step is what makes the whole background story work.

---

## 3. Execution and the model-residency seam

```
        ┌──────────── foreground ────────────┐
        │  hostOnly steps    ✅              │
        │  needsModel steps  ✅              │
        └────────────────────────────────────┘

        ┌──────────── background ────────────┐
        │  hostOnly steps    ✅              │
        │    · GitHub polling                │
        │    · web monitors                  │
        │    · time conditions               │
        │    · URLSession weight downloads   │
        │                                    │
        │  needsModel steps  ❌              │
        │    → checkpoint                    │
        │    → status = waitingForModel      │
        │    → notify (if important)         │
        └────────────────────────────────────┘
```

For simple checks — a CI status poll, a web monitor, a time condition — **the model is never loaded at
all** (spec §43). Most scheduled work is host work wearing an AI costume, and treating it that way is
what keeps LCL from eating the battery.

### Background mechanisms actually used

| Mechanism | Used for |
|---|---|
| `BGProcessingTask` | periodic host-only task advancement, CI polling |
| `BGAppRefreshTask` | light condition checks |
| `BGContinuedProcessingTask` | user-initiated long host work; gets system progress UI. **Submitted from a foreground action only**, and **without** `.gpu` on iPhone — that resource is iPad-only and a request for it is rejected at submission |
| `URLSession` background | model weight downloads, large artifact fetches |

Honest statuses in the UI (spec §44): Scheduled · Waiting for system · Running · Suspended · Waiting
for user · Waiting to continue · Completed. **"Waiting for system"** is shown as exactly that, because
iOS does not guarantee when it will run a background task and pretending otherwise trains the user to
distrust the app.

---

## 4. Checkpoints

Written before every model unload, and at every AgentLoop state transition (spec §45).

```swift
struct Checkpoint: Codable {
    let taskID: UUID
    var goal: String
    var planSnapshot: AgentPlan
    var currentStepID: UUID?
    var completedWork: [String]
    var decisions: [Decision]
    var researchRefs: [ResearchBriefRef]
    var branch: String?
    var latestCommit: CommitRef?
    var buildStatus: BuildRef?
    var openQuestions: [String]
    var nextIntendedAction: String    // ← the crucial one
    var createdAt: Date
}
```

`nextIntendedAction` is what turns a resume from "re-derive everything from scratch" into "continue".
Without it the model burns a full turn rediscovering where it was.

On resume the model receives the checkpoint as compact structured state — not a transcript replay.

---

## 5. Decisions

```swift
struct Decision: Codable, Identifiable {
    let id: UUID
    var question: String
    var options: [DecisionOption]     // 2–4
    var chosenOptionID: UUID?
    var customAnswer: String?
    var chosenBy: Chooser             // .user | .userDefault
    var decidedAt: Date?
}
```

`chosenBy` has no `.model` case. **The model can never record a decision as made by the user**
(spec §34). It may recommend; recommendation is not consent (spec §24).

```
DecisionRequest created
        ↓
task.status = waitingForUser
        ↓
notification (if important) → native Decision UI
        ↓
user chooses / writes their own
        ↓
save decision  →  update plan  →  resume task
```

A recorded decision enters **protected context** and cannot be evicted by compaction — the failure mode
where an agent forgets a choice and re-litigates it is one of the most irritating things an agent can
do, and it is entirely preventable.

---

## 6. Activity

Every task carries an append-only `[TaskEvent]` — the honest record of what the AI did (spec §29).

```
14:31  Research started
14:33  Read Apple documentation          3 sources     ▸
14:36  Read ModelManager.swift           GitHub        ▸
14:39  Edited 4 files                                  ▸
14:40  Commit 4f82c9                                   ▸
14:41  Build started                     Actions       ▸
```

- Every tool call expands to show arguments and the compacted result.
- The raw result is one tap further, from the Archive.
- **Secrets cannot appear** — structurally, not by filtering.
- Timestamps are real. Nothing is inferred or back-filled.

The Activity screen groups tasks as **Active / Waiting / Completed** (spec §27), with the timeline per
task (spec §28).

---

## 7. Notifications

The model may notify with its own content (spec §35) but must choose from **semantic actions** — it
never supplies an executable action:

`Open Task` · `View Research` · `View Diff` · `Retry` · `Continue` · `Pause` · `Stop` · `Review` ·
`Open Build` · `Open PR`

The host binds these to real handlers and App Intents. **Permission enforcement is unchanged by the
route** — tapping `Retry` on a notification does not bypass a High Impact check (spec §40). A
notification is a shortcut to a screen, never a shortcut past a gate.

Default setting: **Only important** (spec §37) — task completed, decision needed, build failed/passed,
blocker found, research complete, monitor condition met. Not every tool call.

---

## 8. Live Activities

An active task may have a Live Activity showing **last known real state** with its timestamp
(spec §41).

We have no backend, so: no push-to-start, no remote updates. Activities start and update while the app
runs or during a background wake. The UI therefore never shows an extrapolated step count or a fake
progress bar — it shows what was true as of a stated moment.

Interactive buttons route through App Intents into the same permission system as everything else. A
Live Activity is not a way around the gate.
