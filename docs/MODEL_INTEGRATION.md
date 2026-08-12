# LCL — Gemma 4 Integration Plan

Everything Gemma-shaped lives behind `Gemma4Provider`. Nothing in this document is visible above the
`AI` layer (spec §5).

Facts and sources: [RESEARCH_LOG.md](RESEARCH_LOG.md) §2–3.

---

## 1. Model choice

**Default: `mlx-community/gemma-4-e2b-it-4bit`**

| | |
|---|---|
| Effective params | 2.3B (5.1B including embeddings, Per-Layer Embeddings) |
| On disk, 4-bit | ~2–3 GB |
| Context | 128K |
| Modalities | text + image + audio in — **Swift supports text only today** |
| Tool calling | native function calling |
| License | **Apache 2.0** — commercial use, modification, redistribution all permitted |

Alternates surfaced in Model Manager, same provider:

- `gemma-4-e2b-it-qat-OptiQ-4bit` — QAT + mixed precision. Benchmark against baseline in Phase 1;
  QAT usually wins measurably at 4-bit.
- `gemma-4-e4b-it-4bit` — the escalation path if E2B's judgment proves too weak (~4B effective).
- Any `MLXLLM`-supported architecture, since `ModelProvider` is generic: Qwen3, Llama, Phi-3, Gemma 3n.

> Note on naming: the spec calls it "Gemma 4 Mobile E2B". The official identifier is `gemma-4-E2B`
> ("E" = *effective* parameters). Same model.

---

## 2. Loading

```swift
actor Gemma4Provider: ModelProvider {
    private var container: ModelContainer?

    func load(progress: @Sendable (Double) -> Void) async throws {
        // exact API confirmed against mlx-swift-lm 3.31.x in the first CI run
        container = try await #huggingFaceLoadModelContainer(
            configuration: descriptor.mlxConfiguration
        )
    }

    func unload() async {
        container = nil
        MLX.GPU.clearCache()
    }
}
```

Non-negotiables:

- **Never on the main actor.** `Gemma4Provider` is an `actor`; the container never crosses to
  `@MainActor`.
- Download uses `URLSession` background configuration — resumable, survives suspension, Wi-Fi by
  default with explicit cellular opt-in. A 3 GB download that restarts from zero is a product defect.
- Weights land in Application Support, **excluded from iCloud backup**, and *not* in `Caches` — iOS
  purges `Caches` under disk pressure and silently losing a 3 GB download would be maddening.
- `MLX.GPU.set(cacheLimit:)` at startup from the device RAM tier.
- Progress is reported for download *and* load separately; they have very different durations and
  conflating them makes the UI lie.

**Lifecycle is owned by `ModelLifecycleCoordinator`, not by any view.** It unloads on: background
transition, memory pressure warning, serious/critical thermal state, idle timeout, and before any
long non-model wait such as a CI build (spec §25, §43).

---

## 3. Prompt format

Gemma's turn structure, owned entirely here. The tokenizer's chat template is applied via
`swift-transformers` rather than hand-assembled — hand-built prompt strings drift from the trained
format and quietly degrade quality.

Two Gemma-specific facts we must respect:

- Gemma historically has **no system role**; system instructions are folded into the first user turn.
  mlx-swift-lm 3.31.4 includes a *"Fix Gemma 4 system message and modality order"* change, so the
  correct handling is version-dependent and **must be confirmed empirically**, not assumed.
- Thinking output is delimited by the model's own reasoning markers, parsed here and emitted as
  `.thinking` events — never mixed into `.prose`. The Chat UI receives two clean streams.

---

## 4. Tool calling — grammar-constrained

The central design decision. A 2.3B model *asked* for JSON will sometimes produce broken JSON; across
a 20-step agent task that is fatal. `MLXGuidedGeneration` (xgrammar) constrains sampling so
**malformed tool calls are unrepresentable.**

> ⚠️ **Not available in a pinned release yet.** `MLXGuidedGeneration` exists only on
> `mlx-swift-lm`'s `main` branch, not in 3.31.4 ([RESEARCH_LOG.md](RESEARCH_LOG.md) §3). Tool calling
> is Phase 4, so this is deferred, not blocked — but the fallback must be chosen deliberately when we
> get there, and the fallback is strictly weaker: Gemma 4's native function calling plus host-side
> validation and retry makes malformed calls *rare*, not *impossible*. Everything below describes the
> target design.

### Two-phase turn

**Phase A — route.** Constrain to a minimal grammar: open prose, or a tool envelope whose `name` is
an enum over *currently permitted* tools.

```json
{ "type": "object",
  "oneOf": [
    { "properties": { "kind": {"const": "reply"} } },
    { "properties": { "kind": {"const": "tool"},
                      "name": {"enum": ["web_search", "read_file", "create_plan"]} } }
  ] }
```

**Phase B — fill.** If a tool was chosen, constrain to that single tool's JSON Schema. Arguments come
out with correct types, required fields present, enums in range — by construction.

### Why the enum matters more than it looks

The permitted-tool enum is computed per turn from privacy mode, project settings, chat settings,
task-scoped grants, and MCP connection state.

**A tool the user has not enabled is absent from the grammar and cannot be named.** That is a stronger
guarantee than a post-hoc rejection, and it costs nothing at runtime.

### Still validated afterwards

Grammar conformance is not semantic validity:

1. Schema conformance — free, by construction.
2. **Semantic validation** — path inside sandbox, URL scheme allowed, ref is not a protected branch,
   numbers within bounds.
3. **Permission gate** — tier check, may suspend the turn to ask the user.
4. Execute.

A schema-valid path can still escape a sandbox. A schema-valid ref can still say `main`.

### Failure handling

One tool at a time. Small tool count per turn — a 2.3B model given 30 tools chooses badly regardless
of grammar; the ContextEngine exposes only tools plausibly relevant to the current step.

On execution failure the model gets a **structured** error (what failed, why, what would be valid),
not a stack trace. If it fails the same tool twice, the host narrows the grammar to that tool's schema
and retries once, then escalates to the user rather than looping.

---

## 5. Streaming

```swift
func stream(_ request: GenerationRequest) -> AsyncThrowingStream<GenerationEvent, Error>
```

- Deltas are **coalesced on a display timer (~60 Hz)**, not emitted per token. Per-token SwiftUI
  invalidation is how these apps end up at 15fps.
- Cancellation is immediate and cooperative; a cancelled turn also cancels in-flight tools.
- `.usage` events carry prompt/completion tokens and tokens/sec, feeding both the Context Inspector
  and Advanced Diagnostics (spec §78).
- Thinking and prose are separate event cases, so the UI can collapse reasoning without string
  surgery.

---

## 6. Context

128K is generous but shared with everything. Budget in `CONTEXT_ENGINE.md`; the provider's only jobs
are to report `maxContextTokens` from `ModelCapabilities` and to count tokens with the real tokenizer
— **never** an estimate. `chars/4` heuristics cause context overflow crashes at exactly the worst
moment.

KV-cache reuse across turns is a Phase 1 stretch goal: a stable prefix (system + goal + plan) that
does not change between turns can avoid re-prefill. Worth real latency, but measure before building —
and note that Gemma 4's sliding-window/full-attention interleave is what broke KV caching for the
larger variants upstream, so treat cache reuse as unproven until tested.

---

## 7. Phase 1 verification

In order. Each step is verifiable in CI or on a device, and none is skipped.

1. `MLXLLM` + `MLXGuidedGeneration` link and build for `generic/platform=iOS` in CI.
2. `MockModelProvider` drives the full AgentLoop in simulator tests — no weights, no GPU.
3. **On device:** `gemma-4-e2b-it-4bit` downloads, loads, and produces tokens. *This is the first
   thing that cannot be proven in CI.*
4. Measure: load time, tokens/sec, resident bytes, thermal state after 5 minutes of generation.
5. Grammar-constrained tool call round-trips 50/50 on a fixed prompt set.
6. Unload actually frees Metal buffers — verify resident memory returns to baseline. If `container =
   nil` does not release, that is a serious finding and changes the lifecycle design.
