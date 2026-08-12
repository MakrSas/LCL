# LCL — Architecture

> **The model may forget. LCL must not.**
> **The model proposes intent. The host verifies and executes.**

Every fact this document depends on is sourced in [RESEARCH_LOG.md](RESEARCH_LOG.md).

---

## 1. The one rule

```
┌───────────────────────────────────────────────────────────────┐
│  MODEL (Gemma 4 E2B)          │  HOST (LCL)                    │
├───────────────────────────────┼────────────────────────────────┤
│  understanding                │  persistent plans              │
│  reasoning                    │  permissions                   │
│  proposing plans              │  credentials                   │
│  writing code                 │  context assembly              │
│  choosing tools               │  memory                        │
│  writing prose                │  task state & checkpoints      │
│                               │  branch / merge policy         │
│                               │  tool execution                │
│                               │  scheduling                    │
│                               │  notifications                 │
│                               │  security                      │
└───────────────────────────────────────────────────────────────┘
```

The model never holds a capability, a credential, or a source of truth. It emits *intents*. Every
intent crosses a validation boundary before anything happens. This is what lets a 2.3B model drive a
system that can write to a GitHub repository without being dangerous.

Corollary that shapes the whole codebase: **there is no code path from a `Secret` to a prompt
string.** Enforced by type, not by discipline — see §7.

---

## 2. Layers

Strict downward dependency. A layer may only import layers below it. Enforced by module boundaries
in the Xcode project, not by convention.

```
┌──────────────────────────────────────────────────────────────────────┐
│ Features        Chat · Sidebar · Projects · Models · Library ·        │
│                 Plugins · GitHub · Activity · Scheduled · Context ·   │
│                 Voice · Settings                                     │
├──────────────────────────────────────────────────────────────────────┤
│ Agent           AgentTask · AgentPlan · Checkpoint · Decision ·       │
│                 Research · ActivityLog                               │
├──────────────────────────────────────────────────────────────────────┤
│ Tools           ToolRegistry · Permissions · Web · MCP · GitHub ·     │
│                 Files · Notifications · DynamicTools                 │
├──────────────────────────────────────────────────────────────────────┤
│ AI              ModelProvider · Gemma4Provider · GenerationEngine ·   │
│                 AgentLoop · ContextEngine · ToolCalling · Planning    │
├──────────────────────────────────────────────────────────────────────┤
│ Core            Persistence · Networking · Security · DesignSystem ·  │
│                 Motion · Haptics · Diagnostics                        │
└──────────────────────────────────────────────────────────────────────┘
```

Two rules that keep this honest:

- **`Features` never imports `AI`.** A view cannot start a generation. It sends an intent to the
  Agent layer. This is what stops Gemma-specific behaviour leaking into Chat UI (spec §5).
- **`AI` never imports `Tools`.** The `AgentLoop` receives a `ToolCatalog` value and returns
  `ToolInvocation` values. It cannot execute anything. Execution lives one layer up, behind
  permissions.

### Directory layout

```
LCL/
├── App/                        LCLApp.swift, AppRoot, DI container, deep links
├── Core/
│   ├── Persistence/            Database, migrations, DAOs, Archive
│   ├── Networking/             HTTPClient, ATS/TLS policy, rate limiting, retry
│   ├── Security/               Keychain, Secret<T>, Redactor, PermissionStore
│   ├── DesignSystem/           tokens, materials, typography, components
│   ├── Motion/                 MotionSystem
│   ├── Haptics/                HapticManager
│   └── Diagnostics/            metrics, thermal/memory observers, logging
├── AI/
│   ├── ModelProvider/          protocol, capabilities, registry, lifecycle
│   ├── Gemma4Provider/         MLX loading, chat template, grammar, parsing
│   ├── GenerationEngine/       streaming, cancellation, token accounting
│   ├── ContextEngine/          budget, assembly, compaction, retrieval
│   ├── AgentLoop/              turn state machine
│   ├── Planning/               plan mutation semantics
│   └── ToolCalling/            schemas, grammar compilation, intent parsing
├── Tools/
│   ├── ToolRegistry/           registration, validation, permission gate, dispatch
│   ├── Web/                    SearchProvider, WebPageReader, CitationManager
│   ├── MCP/                    MCPManager, server store, OAuth
│   ├── GitHub/                 GitHubProvider, BuildMonitor, BuildLogAnalyzer
│   ├── Files/                  import, chunking, extraction
│   ├── Notifications/          NotificationTool, semantic actions
│   └── DynamicTools/           ToolBuilder, ToolValidator, DynamicToolRegistry
├── Agent/                      AgentTask, AgentPlan, Checkpoint, Decision, Activity
├── Features/                   one folder per feature, view + view model
└── Resources/                  Assets, Info.plist, PrivacyInfo.xcprivacy
```

---

## 3. The turn — how one message becomes work

```
user message
   │
   ▼
AgentLoop.begin(turn)
   │
   ├─► ContextEngine.assemble(budget) ──────────────► [system, goal, plan, memory,
   │                                                    conversation, retrieved,
   │                                                    tool results, catalog]
   ▼
GenerationEngine.stream(context, grammar: .toolOrProse)
   │
   ├─ prose delta ──────────────────────────────────► Chat UI (incremental)
   │
   └─ tool intent (grammar-guaranteed valid JSON)
        │
        ▼
   ToolRegistry.validate(intent)          ← schema + argument bounds
        │
        ▼
   PermissionGate.authorize(intent)       ← Read / Write / HighImpact
        │                                   may suspend the turn and ask the user
        ▼
   Tool.execute(args)                     ← host code. never the model.
        │
        ▼
   ToolResult (raw)  ──► Archive.store(raw)        full fidelity, forever
        │
        └──► ToolResultCompactor ──► excerpt + summary + handle
                    │
                    ▼
              back into context, loop
```

`AgentLoop` is a state machine, persisted at every transition:

```
idle → assembling → generating → toolPending → awaitingPermission
     → awaitingDecision → executing → compacting → generating → … → done
                                                              ↘ failed
                                                              ↘ suspended (checkpointed)
```

Persisted because of the platform reality: the app can be terminated at any moment, and the model
cannot run in the background at all. Any state that exists only in memory is state we lose.

---

## 4. `ModelProvider`

The abstraction the spec requires (§6), sized to what it must actually carry — no more.

```swift
protocol ModelProvider: Sendable {
    var descriptor: ModelDescriptor { get }
    var capabilities: ModelCapabilities { get }

    func load(progress: @Sendable (Double) -> Void) async throws
    func unload() async

    func stream(_ request: GenerationRequest) -> AsyncThrowingStream<GenerationEvent, Error>
    func countTokens(_ text: String) throws -> Int
}

struct ModelCapabilities: Sendable, Equatable {
    var maxContextTokens: Int
    var supportsVision: Bool
    var supportsAudioInput: Bool
    var supportsThinking: Bool
    var toolCalling: ToolCallingSupport   // .none | .promptBased | .native
    var guidedGeneration: Bool            // grammar-constrained decoding available
    var estimatedResidentBytes: Int
}

enum GenerationEvent: Sendable {
    case prose(String)                    // delta
    case thinking(String)                 // delta, separately routed
    case toolIntent(ToolInvocation)
    case usage(TokenUsage)
    case finished(FinishReason)
}
```

`ModelCapabilities` drives the UI directly. The Composer's Thinking control, the attachment menu's
camera entry, and the tool availability all read from the loaded provider's capabilities — so
swapping in a model without vision removes the camera button with no per-feature code. That is the
whole point of the abstraction, and it is the only reason it exists.

**`Gemma4Provider`** owns everything Gemma-shaped: MLX model container lifecycle, the chat template,
system-message placement, the grammar used for tool calls, thinking-block delimiters, and tool-result
formatting. None of it is visible above the `AI` layer.

---

## 5. Tool calling — grammar, not hope

The central technical bet. A 2.3B model asked politely for JSON will eventually produce malformed
JSON, and an agent whose tool calls fail 5% of the time is unusable across a 20-step task.

`MLXGuidedGeneration` (xgrammar) constrains sampling to a grammar, so **malformed tool calls are not
merely rare, they are unrepresentable.**

Two-phase turn:

1. **Route.** Constrained to a tiny grammar: either open prose, or a tool envelope whose `name` is an
   enum over *currently permitted* tool names.
2. **Fill.** If a tool was chosen, constrain to that one tool's JSON Schema. Arguments are then valid
   by construction — correct types, required fields present, enums in range.

```swift
struct ToolInvocation: Sendable, Hashable {
    let callID: String
    let name: ToolName
    let arguments: JSONValue      // schema-valid by construction
    let proposedAt: Date
}
```

The permitted-tool enum is computed per turn from privacy mode, project settings, chat settings,
task-scoped grants, and MCP connection state. **A tool the user has not enabled is not merely
rejected — it is absent from the grammar and cannot be named.** That is a stronger guarantee than a
post-hoc check, and it costs nothing.

We still validate after parsing. Grammar conformance is not semantic validity: a schema-valid path
can still escape a sandbox, and a schema-valid ref can still be `main`.

Gemma 4 has native function calling; where its native format is well-defined we use it as the
grammar target rather than inventing our own envelope, so we stay on the model's trained
distribution.

---

## 6. Permissions

Three tiers (spec §64), enforced entirely host-side:

| Tier | Examples | Rule |
|---|---|---|
| **Read** | web search, read file, list repos, read build log | auto after one-time consent |
| **Write** | write file, commit, create branch, create PR, MCP write | ask — unless a task-scoped grant covers it |
| **High Impact** | **merge**, force push, delete branch, secrets, account changes | **always** explicit, per action, never grantable in advance |

```swift
struct PermissionGrant {
    let tool: ToolName
    let scope: Scope        // .once | .chat(id) | .project(id) | .task(id) | .global
    let resource: ResourceConstraint?   // repo + branch, host allowlist, path prefix
    let expires: Date?
}
```

Autonomous development (spec §65) is a `.task(id)` grant bound to **one repository and one branch**.
It permits the edit→commit→build→fix loop. It **cannot** be widened by the model, cannot outlive the
task, and does not include any High Impact action.

**Permission inheritance (spec §19).** A dynamic tool is a composition of primitives. Its effective
permission is the **union of its constituents' permissions**, computed by the host at build time and
re-checked at execution. A tool the model authored cannot acquire a right the model did not already
have. There is no code path by which it could — `ToolBuilder` emits a declarative graph over
registered primitives, never executable code.

**Branch and merge policy** are host invariants, not instructions in a prompt:

- Any code change requires a branch matching `ai/*`. The host creates it.
- Writes to `main`, `master`, `release*`, `production*` are **rejected at the provider layer**,
  regardless of what any plan, prompt, or tool argument says.
- `merge` requires a fresh, explicit user action in the current session. The model's own
  recommendation is never consent (spec §24). A `DecisionRequest` the model created cannot satisfy it.

---

## 7. Security

**Secrets cannot reach the model — by type.**

```swift
@propertyWrapper
struct Secret<T>: Sendable {
    private let value: T
    var wrappedValue: T { value }          // only host code can read it
}
```

`Secret` is not `Codable`, has no `description`, and cannot be interpolated into a string.
`ContextEngine` accepts only `PromptFragment` values, and there is no conversion from `Secret` to
`PromptFragment`. The GitHub token therefore cannot appear in a prompt, in the Context Inspector, in
a checkpoint, in a log, or in an activity entry — because no function exists that would put it there.
Compile-time, not review-time.

Beyond that:

- Tokens live in Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` — never synced,
  never in an iCloud backup, available to background tasks after first unlock.
- **All external data is untrusted and tainted at the boundary**: web pages, MCP tool output, GitHub
  API responses, file contents. Tainted content enters the prompt inside explicit delimiters marked
  as untrusted data, never as instructions. This is the primary defence against prompt injection —
  which matters enormously here, because a successful injection would be talking to something that
  can write to the user's repositories.
- A tainted-origin tool result can never *widen* permissions or auto-authorize an action. Injection
  can at worst waste a turn; it cannot escalate.
- Database file protected; secrets never logged; tool arguments validated; no silent destructive ops.

---

## 8. Persistence — one store, never destructive

**GRDB.swift (SQLite).** Chosen for one decisive reason: the ContextEngine needs **FTS5** with BM25
ranking, and SwiftData does not expose it. A local-first agent whose entire premise is "history is
never destroyed and must be retrievable" cannot be built on a store without full-text search.

```
messages ─┬─ raw content, never mutated, never deleted by compaction
          ├─ FTS5 virtual table (BM25)
          └─ embedding BLOB (MLXEmbedders, lazy)

tool_results ── raw payload + handle; context gets excerpt+summary only
facts ───────── typed compaction output, each with source_event_id
tasks / plans / checkpoints / decisions / events
memories ────── chat | project | global scope
```

**Compaction never deletes.** It writes a compact representation *alongside* the raw record and marks
the raw record as archived-from-context. `Archive` is append-only. Every compacted fact carries a
`source_event_id`, which is what makes `retrieve_context` able to reconstitute the original and what
prevents summary-of-summary drift (spec §52).

---

## 9. Platform reality, designed for rather than around

Three hard constraints from [RESEARCH_LOG.md](RESEARCH_LOG.md) §6, and how the architecture answers.

**1. No background GPU on iPhone ⇒ no background inference.**
The model runs only while the app is foreground. This is not negotiable, so it becomes an explicit
architectural seam: every AgentTask is a sequence of steps, each labelled `needsModel` or
`hostOnly`.

```
foreground:  hostOnly + needsModel steps run freely
background:  hostOnly steps only (GitHub polling, web monitors, time
             conditions, URLSession weight downloads)
             a needsModel step → checkpoint, notify, wait for foreground
```

The UI never implies otherwise. A task blocked on the model reads **"Waiting to continue · needs LCL
open"** — truthful, and it makes the resume tap obvious.

**2. No backend server ⇒ no push-to-start, no remote Live Activity updates.**
Live Activities start and update while the app runs or during a background wake. They display the
**last known real state** with its timestamp, never an extrapolation (spec §41).

**3. The app can be terminated at any time.**
Hence checkpointing is not a feature of long tasks — it is how the AgentLoop persists, at every
transition. Resume is the normal path, not the recovery path.

**Memory governance.** `ModelLifecycleCoordinator` owns load/unload and is the only thing that may
hold the container. It unloads on: background transition, memory pressure warning, serious/critical
thermal state, idle timeout, and before any long non-model wait such as a CI build (spec §25).
`MLX.GPU.set(cacheLimit:)` is set from the device RAM tier at startup.

---

## 10. Self-development loop

LCL editing its own source is a normal `AgentTask` with one repository target, subject to every rule
above. The only reason it is special is that **CI is our compiler** — no Mac exists locally, so the
edit→verify loop runs through GitHub Actions for the agent exactly as it does for us.

```
need → research → plan → ai/* branch → edit → commit
                                                 │
                                                 ▼
                                        GitHub Actions (macos-26)
                                                 │
                              ┌──────────────────┴─────────────────┐
                              ▼                                    ▼
                          failed                                passed
                              │                                    │
                    BuildLogAnalyzer                        user reviews diff
                    (failing job, compiler                         │
                     errors, referenced files,              user asks to merge
                     surrounding context only)                     │
                              │                                    ▼
                        model fixes ──► commit ──┘              merge
```

While a build runs, the model is **unloaded** — a CI run is minutes long and there is nothing for it
to do. `GitHubBuildMonitor` is host-only and pollable from a background task. The model is reloaded
only if reasoning is actually required.

`BuildLogAnalyzer` exists because a raw Xcode log is tens of thousands of useless lines and our
entire context budget is 128K shared with everything else. It extracts the failing job, the compiler
diagnostics, the referenced files and a few lines of surrounding source — typically a few hundred
tokens instead of a hundred thousand.

---

## 11. Concurrency

Swift 6 strict concurrency, `Sendable` throughout.

- **Inference never touches the main actor.** `Gemma4Provider` runs on a dedicated actor.
- Streaming deltas are **coalesced on a display timer**, not delivered per token. Per-token SwiftUI
  invalidation is the standard way these apps end up at 15fps.
- The Markdown pipeline is **block-incremental**: only the trailing block re-parses as tokens arrive.
  A settled block is immutable and never re-rendered (spec §8).
- Database writes go through one `DatabaseQueue`; reads use a pool.
- Every tool execution is cancellable and has a timeout. A cancelled turn cancels in-flight tools.

---

## 12. Testability

The agent loop is the part most likely to break subtly, and we cannot run the app locally — so it
must be testable in CI on a simulator, without a model.

`MockModelProvider` replays a scripted `GenerationEvent` sequence. That makes the interesting things
unit-testable with no GPU and no weights:

- tool intent → validation → permission → execution → result → next turn
- a High Impact action is refused without explicit authorization
- `main` is unwritable no matter how the intent is phrased
- a `Secret` cannot reach an assembled prompt (compile-time, plus a runtime redaction assertion)
- compaction preserves every protected slot and every `source_event_id`
- checkpoint → kill → restore reaches an identical loop state
- an injected instruction inside a tainted web result does not alter permissions

Design-system snapshot tests at the smallest and largest Dynamic Type sizes, in light and dark,
guard the thing the spec cares most about — that the UI does not quietly rot.
