# LCL — Context Engine

> **The model may forget. LCL must not.** (spec §85)

The ContextEngine is what makes a 2.3B model feel like a capable agent. The model is small; the app's
memory is not. Every architectural choice here follows from one rule: **the active context is a
*view* over durable state, never the state itself.**

---

## 1. Budget

> **Corrected 2026-08-13.** An earlier version of this document budgeted the model's full 128K.
> That was a category error: **128K is a model capability, not a device capability.** The KV cache
> for a long context can run several times the size of the weight file, and the target device is an
> **iPhone 15 — 6 GB RAM, per-app limit ≈2.5–3 GB**, most of which the 4-bit weights already occupy.
> Budgeting 128K would guarantee a Jetsam kill. See [RESEARCH_LOG.md](RESEARCH_LOG.md) §9.

The working context is therefore `min(model max, device profile)`, chosen at load time from the RAM
tier. Two profiles for Phase 1; numbers are starting points to be replaced by measurement.

| Slot | 8K profile | ≈32K profile | Protected | Notes |
|---|---|---|---|---|
| System | 800 | 1 200 | ✅ | identity, rules, safety, output contract |
| Goal | 200 | 400 | ✅ | current AgentTask goal |
| Plan | 450 | 1 200 | ✅ | current plan + current step |
| Decisions | 350 | 1 200 | ✅ | explicit user choices — never dropped |
| Memory | 350 | 1 200 | — | chat + project + global, ranked |
| Conversation | 2 200 | 11 900 | — | recent turns, raw |
| Retrieved | 700 | 3 500 | — | `retrieve_context` results |
| Files | 400 | 3 000 | — | attached document chunks |
| Tool results | 800 | 4 500 | — | compacted excerpts + handles |
| Tool catalog | 350 | 1 200 | — | only tools relevant to this step |
| Task state | 400 | 1 400 | ✅ | branch, commits, build status, blockers |
| **Reserved** | **1 000** | **2 000** | ✅ | generation headroom — never allocated |

**8K is the Phase 1 default on a 6 GB device.** Anything larger depends on a quantized KV cache
(4-bit KV is reported to give ~3× the context at no quality cost) — and whether `mlx-swift-lm` exposes
one in Swift is **unverified**. Until measured on the actual phone, treat ≈32K as aspirational.

This is precisely why the ContextEngine exists. A small working context makes structured compaction
and retrieval the load-bearing features rather than nice-to-haves: the app remembers everything, and
the model is shown only the 8K that matter right now.

**Protected slots are never evicted by compaction.** If a protected slot cannot fit, that is an error
surfaced to the user, not silently truncated data. Losing the current plan or an explicit user
decision is worse than failing loudly.

Token counts come from the real tokenizer, never `chars/4`.

---

## 2. Assembly

Per turn, in priority order:

```
1. fill protected slots            (system, goal, plan, decisions, task state)
2. reserve generation headroom     (never negotiable)
3. select tool catalog             only tools plausibly relevant to the current step
4. fill conversation backwards     newest first, until slot full
5. anything displaced by (4)       →  compact  →  facts
6. retrieval                       if the turn implies a lookup
7. memory                          ranked, top-K
8. remaining budget                → file chunks, tool excerpts
```

Step 3 matters more than it appears. A 2.3B model given 30 tool schemas chooses badly no matter how
good the grammar is. Narrowing the catalog to the current step is a quality lever, not just a token
saving.

---

## 3. Structured compaction

Not `"Summary of conversation..."`. Compaction **extracts typed facts** (spec §50):

```swift
enum FactKind: String, Codable {
    case fact, goal, decision, preference, constraint
    case openQuestion, completedWork, technicalFinding, error
    case repository, branch, commit, userChoice
}

struct Fact: Codable {
    let id: UUID
    let kind: FactKind
    let content: String
    let sourceEventID: UUID      // ← never null. this is the anti-drift mechanism.
    let importance: Double
    let createdAt: Date
    let supersededBy: UUID?
}
```

Three invariants:

1. **Compaction never deletes.** Raw messages stay in the archive forever, flagged as
   archived-from-context. `Archive` is append-only.
2. **Every fact cites its source event.** This is what makes `retrieve_context` able to reconstitute
   the original.
3. **Facts are extracted from raw events, never from other facts.** No summary-of-summary. When
   re-compaction is needed, we re-extract from the raw archive at a coarser granularity. The
   information degrades gracefully instead of drifting into fiction (spec §52).

A fact is superseded, not edited — `supersededBy` preserves the history of what the model used to
believe, which matters when debugging why it did something.

---

## 4. Retrieval

```
retrieve_context(query: String, scope: ...) -> [ContextItem]
retrieve_tool_result(handle: String, focus: String?) -> String
```

Hybrid, in stages — cheap filters first:

```
FTS5 / BM25 over raw text      →  top 200 candidates
        ↓
embedding cosine rerank        →  MLXEmbedders, over candidates only
        ↓
score = 0.45·semantic + 0.30·bm25 + 0.15·recency + 0.10·importance
        ↓
+ boost: same task, pinned, decision, protected
        ↓
top K, token-budgeted
```

Embedding only the 200 FTS candidates rather than the whole corpus is what keeps this fast enough to
run inside a turn. Brute-force cosine over a few hundred vectors with Accelerate is microseconds; over
100k rows it is not.

Searchable: raw messages, AgentTasks, plans, decisions, project docs, research briefs, GitHub events,
tool results, memories.

### Automatic recovery (spec §54)

Before the model is allowed to answer *"I don't know"* / *"I have no information about"*, the AgentLoop
intercepts, runs retrieval on the user's question, and if anything relevant surfaces, retries the turn
with it injected.

The user should never have to repeat something LCL already knows. This single behaviour does more for
the perceived intelligence of a small model than any prompt tuning.

---

## 5. Tool result offloading

Never in context: full HTML, giant GitHub JSON, a 100 KB build log (spec §57).

```
raw result  →  Archive (full fidelity, addressable by handle)
                     │
                     ▼
            ToolResultCompactor
                     │
      ┌──────────────┼──────────────┐
      ▼              ▼              ▼
   excerpt        summary        handle
  (relevant     (2–3 lines)   (retrieve_tool_result)
   spans)
```

Per-type compactors, because "relevant" means something different each time:

| Type | Kept |
|---|---|
| Web page | readable main content, chunked, cited |
| Search results | title + URL + snippet, deduped by host |
| GitHub file | requested span + a little surrounding context |
| GitHub tree | paths only, depth-limited |
| **Build log** | `BuildLogAnalyzer`: failing job, compiler diagnostics, referenced files + surrounding source |
| MCP result | declared structured output if present, else truncated with handle |

`BuildLogAnalyzer` is the highest-leverage one: a raw Xcode log is tens of thousands of lines and
almost entirely useless. Extracting the failing job and its diagnostics turns ~100K tokens into a few
hundred (spec §58).

---

## 6. Memory

Three scopes, all user-visible and user-editable (spec §56): **chat**, **project**, **global**
(opt-in, default off).

Memory is written only on: an explicit user pin, an explicit "remember this", a stated durable
preference, or a recorded decision. **Not every passing phrase.** A memory system that saves
everything is noise, and noise crowds out the 2K budget that actually matters.

User controls: View, Edit, Forget, Disable, Clear. Nothing is hidden.

### Pinning (spec §55)

Long-press a message → **Keep in Context** · **Remember for Chat** · **Remember for Project**.
Pinned items get a large retrieval boost and survive compaction.

---

## 7. Context Inspector

The user can see exactly what the model receives (spec §47–48).

```
Context                                    43%

System            3.0k  ████
Conversation     14.2k  ████████████████
Task              4.1k  █████
Plan              1.8k  ██
Memory            2.0k  ██
Files             5.2k  ██████
GitHub            4.0k  █████
Tools             2.1k  ██
Reserved          8.0k  ░░░░░░░░

              Preview What Model Sees  →
```

`Preview What Model Sees` renders the **actual assembled prompt**, in order, with each slot labelled
and each retrieved item linked to its source.

Secrets are absent — not redacted-at-render but structurally impossible to be there (`Secret` cannot
become a `PromptFragment`; see ARCHITECTURE §7). The GitHub token cannot appear on this screen because
no code path exists that would put it in the prompt in the first place.

This screen is also our best debugging tool. When the model does something inexplicable, the answer is
almost always here.
