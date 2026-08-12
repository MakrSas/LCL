# LCL — Research Log

Verified facts behind every architectural decision. Checked **2026-08-12** against primary sources.
Rule: nothing enters an architecture doc unless it appears here with a source. Confidence is marked
honestly — `verified` means a primary source was read, `unverified` means it must be confirmed before
we depend on it.

---

## 1. The spec's premises — verdict

The spec is **current and accurate**. Both headline premises are real:

| Spec assumption | Reality | Status |
|---|---|---|
| `Gemma 4 Mobile E2B` is the model | **Gemma 4 E2B** exists. Released 2026-03-31 (family), Apache 2.0 | ✅ real (name is `gemma-4-E2B`, no "Mobile" in the official ID) |
| `iOS 27` is the target OS | **iOS 27** announced at WWDC 2026 (June 8–9, 2026) | ✅ real — **but still in beta on 2026-08-12** |
| Liquid Glass is the design language | Introduced iOS 26; iOS 27 adds a personalization slider | ✅ real |

Two corrections that change the plan, detailed below: **iOS 27 has not shipped yet**, and
**Gemma 4 in *Swift* is text-only**.

---

## 2. Gemma 4 E2B

- Family released **2026-03-31**; `Gemma 4 12B Unified` 2026-06-03; MTP variants 2026-04-16.
  Sizes: **E2B, E4B, 31B, 26B-A4B**. — [ai.google.dev/gemma/docs/releases](https://ai.google.dev/gemma/docs/releases) `verified`
- **License: Apache 2.0** — a major change from the Gemma Terms of Use of earlier generations.
  Commercial use, modification and redistribution are permitted. Removes the App Store licensing
  question entirely. — [Gemma 4 launch](https://discuss.ai.google.dev/t/gemma-4-launch-announcement/138069) `verified`
- **E2B: 2.3B effective parameters, 5.1B including embeddings**, Per-Layer Embeddings (PLE).
  The "E" is *effective*. Static weights on disk are larger than the effective count suggests. `verified`
- **~2–3 GB in 4-bit.** Context **128K** for E2B/E4B (256K on medium sizes). `verified`
- Modalities: **text + image + audio input**. **Native function calling** for agentic workflows. `verified`
- Official weights: `google/gemma-4-E2B`, `google/gemma-4-E2B-it`.
  MLX 4-bit: `mlx-community/gemma-4-e2b-it-4bit`, plus `-OptiQ-4bit` (mixed precision, sensitive
  layers at 8-bit) and `-qat-OptiQ-4bit` (QAT) variants. `verified`

**Decision:** `mlx-community/gemma-4-e2b-it-4bit` as the Phase 1 default. Evaluate the QAT/OptiQ
quants during Phase 1 benchmarking — QAT usually wins measurably at 4-bit.

---

## 3. MLX Swift — the critical finding

**The LLM libraries moved.** `mlx-swift-examples` is now only example apps; the real package is
**`ml-explore/mlx-swift-lm`**. — [github.com/ml-explore/mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) `verified`

```swift
.package(url: "https://github.com/ml-explore/mlx-swift-lm", .upToNextMajor(from: "3.31.3"))
```

Products: `MLXLLM`, `MLXVLM`, `MLXLMCommon`, `MLXEmbedders`, `MLXHuggingFace`,
`MLXFoundationModels`, `MLXGuidedGeneration`.
Package platforms floor: **macOS 14 / iOS 17 / tvOS 17 / visionOS 1**.
Depends on `mlx-swift` (~0.31.4) and `swift-syntax` (602–604). `verified`

### Gemma 4 support in Swift is text-only

| Capability | Status |
|---|---|
| Gemma 4 **text** (E2B, E4B) | ✅ **Supported** — added in **3.31.3** (2026-04-01), PR #185 |
| Gemma 4 **MTP speculative decoding** | ✅ added in 3.31.4 |
| Gemma 4 **vision** | ⚠️ unconfirmed in `MLXVLM`; `supported-models.md` lists Gemma3 for VLM, not Gemma 4 |
| Gemma 4 **audio** | ❌ open request — [mlx-swift-lm#207](https://github.com/ml-explore/mlx-swift-lm/issues/207) |
| Gemma 4 **26B MoE**, **31B dense** | ❌ broken — [mlx-swift-lm#282](https://github.com/ml-explore/mlx-swift-lm/issues/282) |

`supported-models.md` does **not** list `gemma4` — it lists `gemma`, `gemma2`, `gemma3`,
`gemma3_text`, `gemma3n`. The release notes contradict it; the release notes are newer and more
specific (they name the PR). Treat as: **text works, verify empirically in the first CI run.**
— [supported-models.md](https://github.com/ml-explore/mlx-swift-lm/blob/main/skills/mlx-swift-lm/references/supported-models.md), [releases](https://github.com/ml-explore/mlx-swift-lm/releases) `verified`/`likely`

The broken variants (31B `KVCacheSimple` crash, MoE tensor keys, `gemma4_assistant`) are all
**larger models we would never run on a phone**. They do not affect E2B.

> Stale issue: [mlx-swift#389](https://github.com/ml-explore/mlx-swift/issues/389) ("gemma4 not
> registered", 2026-04-05) was filed on the wrong repo one day *before* support landed downstream.

### `MLXGuidedGeneration` — real, but NOT in a release yet

> **Corrected 2026-08-13 by CI.** The build failed with
> `Missing package product 'MLXGuidedGeneration'`. The product list above was read from
> `Package.swift` on **`main`**; the tagged **3.31.4** release does not declare it.

Products actually in **3.31.4**: `MLXLLM`, `MLXVLM`, `MLXLMCommon`, `MLXEmbedders`,
`MLXHuggingFace` (+ `BenchmarkHelpers`, `IntegrationTestHelpers`).
`MLXGuidedGeneration` and `MLXFoundationModels` are **unreleased — `main` only.**
— [Package.swift @ 3.31.4](https://raw.githubusercontent.com/ml-explore/mlx-swift-lm/3.31.4/Package.swift) `verified`

What it is, when it lands: grammar-constrained ("guided") generation on **vendored xgrammar C++ via
CXGrammar**, constraining output to a **JSON Schema or EBNF**. Standalone — depends only on
CXGrammar + MLXLMCommon + MLX.

The architectural bet in `MODEL_INTEGRATION.md` §4 still stands — a 2.3B model needs tool calls that
are parseable *by construction*. But it is **not available in a pinned release today**, and tool
calling is Phase 4, so the decision is deferred rather than blocked. Options at that point, in
preference order:

1. A release that includes it (it is on `main`, so likely).
2. Pin `mlx-swift-lm` to a revision — acceptable only if the graph is otherwise stable.
3. [`petrukha-ivan/mlx-swift-structured`](https://github.com/petrukha-ivan/mlx-swift-structured) —
   third-party xgrammar wrapper.
4. Gemma 4's **native** function calling plus 3.31.4's *"JSON tool-call detection and parser
   hardening for mixed text/tool outputs"*, with host-side validation and retry. Weaker: it makes
   malformed calls rare rather than impossible.

**Lesson recorded:** read `Package.swift` at the tag we pin, never at `main`.

Also: `ChatSession` gained a `tools` parameter; 3.31.4 added *"JSON tool-call detection and parser
hardening for mixed text/tool outputs"* and *"Structured ChatSession continuation"*. `verified`

`MLXEmbedders` gives on-device embeddings from the same stack — no second inference framework
needed for semantic retrieval.

---

## 4. iOS platform state — iOS 27 has not shipped

- **iOS 27 announced at WWDC 2026** (June 8–9). 30% faster app launch, 70% faster photo library,
  80% faster AirDrop, **a personalization slider for Liquid Glass**, plain-English Shortcuts, Lock
  Screen refinements, a more conversational Siri. `verified`
- On **2026-08-12 iOS 27 is in beta** (Xcode 27 Beta 5 release notes exist). GA historically lands
  ~September. **iOS 26 is the current shipping OS.** `verified`
- **Xcode 27** requires macOS Tahoe 26.4+, **Apple silicon only**, ships the iOS 27 SDK, and drops
  deployment targets below **iOS 15**. `verified`

**Decision:** deployment target **iOS 26.0**, build with **Xcode 26.6**. Liquid Glass is fully
available on iOS 26 — we lose nothing on design. iOS 27-only refinements go behind
`if #available(iOS 27, *)`. Flip the CI baseline to Xcode 27 when it reaches GA.

Targeting iOS 27 as the *minimum* today would mean: zero installable users, no App Store
submission, and a CI image in public preview. Not acceptable for a foundation.

---

## 5. GitHub Actions as our only Mac — verified viable

- **`macos-26` (arm64) GA since 2026-02-26.** Labels: `macos-26`, `macos-26-intel`,
  `macos-26-large`, `macos-26-xlarge`. — [changelog](https://github.blog/changelog/2026-02-26-macos-26-is-now-generally-available-for-github-hosted-runners/) `verified`
- Xcode on that image: **26.6 default since 2026-07-21**; 26.5, 26.4.1, 26.3, 26.2, 26.1.1, 26.0.1
  also installed. `verified`
- Runner images are now keyed to **major Xcode version**, one per image. `verified`
- **`Xcode 27` image is public preview since 2026-07-16**, arm64 only. `verified`
- ⚠️ **[runner-images#14450](https://github.com/actions/runner-images/issues/14450): "Metal Toolchain
  is not installed on xcode-27".** MLX is Metal-based — this is a direct risk to building LCL on the
  Xcode 27 image. Another reason to stay on `macos-26`/Xcode 26.6. `verified`
- **Repo is public + MIT ⇒ Actions minutes are free**, including the normally 10× macOS multiplier. `verified`

### Maintaining an Xcode project from Windows

`PBXFileSystemSynchronizedRootGroup` (Xcode 16+, therefore present in Xcode 26) makes a folder a
**single project reference whose files Xcode discovers automatically** — no per-file `.pbxproj`
entries. — [pepicrft.me](https://pepicrft.me/blog/how-synchronized-groups-work-at-the-pbxproj-level/) `verified`

```
A16DD1E1... /* Sources */ = {isa = PBXFileSystemSynchronizedRootGroup; explicitFileTypes = {};
                             explicitFolders = (); path = Sources; sourceTree = "<group>"; };
```

This is the key that makes Windows-side iOS development sane: **adding a Swift file requires no
project-file edit at all.** XcodeGen and Tuist are Swift binaries and cannot run on Windows; they
would have to run in CI, producing a project file we cannot inspect locally. Rejected in favour of
one carefully hand-authored `.pbxproj` using synchronized folders.

---

## 6. Background execution — the honest limits

- **`BGContinuedProcessingTask`** (iOS 26): for *visible, user-initiated* work. Must be submitted
  from an explicit foreground user action (button tap/gesture). Gets system-provided progress UI.
  Continues if the app backgrounds. `BGContinuedProcessingTaskRequest` with a bundle-ID-prefixed
  identifier, `title`/`subtitle` for the system UI. — [WWDC25 session 227](https://developer.apple.com/videos/play/wwdc2025/227/) `verified`
- **Background GPU access is iPad-only.** The API and entitlement exist for both, but on iPhone it
  is not available. Set `requiredResources = .gpu` + Background GPU Access entitlement; query
  `supportedResources` at runtime; **requests for unavailable resources are rejected at submission.**
  — [Apple forums 816774](https://developer.apple.com/forums/thread/816774) `verified`

**Consequence, stated plainly: LCL cannot run LLM inference in the background on iPhone.**
MLX inference is Metal/GPU. This is not a limitation we can engineer around.

This validates the spec's own instincts (§41 "Live Activity ≠ background daemon", §43 "don't keep
the model in RAM"). The architecture follows: background = host-side non-GPU work only
(GitHub polling, web monitors, time conditions, `URLSession` weight downloads) + checkpoint/resume.
Anything needing reasoning waits for foreground, and we notify the user. See `AGENT_TASKS.md`.

---

## 7. MCP

- Official **`modelcontextprotocol/swift-sdk`**, current **0.11.0**. `verified`
- `HTTPClientTransport` — HTTP request/response plus **SSE streaming**; Apple-platforms only
  (uses Network framework + EventSource). `verified`
- **stdio transport is unusable on iOS** — a sandboxed app cannot spawn subprocesses.
  ⇒ **LCL can only ever connect to remote MCP servers.** `verified` (by platform constraint)
- Current spec revision **2026-07-28** (RC at time of writing). Streamable HTTP now requires
  `Mcp-Method` and `Mcp-Name` headers so gateways can route without reading the body.
  — [MCP blog](https://blog.modelcontextprotocol.io/posts/2026-07-28-release-candidate/) `verified`

---

## 9. Target device: iPhone 15 — and it is the binding constraint

Confirmed by the developer 2026-08-13: the only test device is an **iPhone 15** (not Pro).

- **iPhone 15: A16 Bionic, 6 GB RAM.** Per-app memory limit on a 6 GB iPhone is commonly
  **≈2.5–3 GB**; Apple does not publish exact figures and they shift between releases. `likely`
- `com.apple.developer.kernel.increased-memory-limit` raises it, but the amount is unspecified, not
  available on every device, and iOS may still terminate under pressure.
  — [zenn.dev/mtfum](https://zenn.dev/mtfum/articles/ios_memory_entitlements?locale=en) `verified`
- **Good news for a sideloaded build:** AltStore v2.2 (April 2025) shipped official support for
  sideloading apps *with* the Increased Memory Limit entitlement, and the same applies to SideStore;
  [`GetMoreRam`](https://github.com/hugeBlack/GetMoreRam) is an AltSign wrapper that adds it without
  Xcode, and [LiveContainer #388](https://github.com/LiveContainer/LiveContainer/discussions/388)
  documents doing it without compiling. `verified`
- ⚠️ **Caveat:** reports indicate the entitlement may require a **paid** certificate registered on the
  device rather than a free one. Unresolved — **must be tested empirically on the actual phone.** `unverified`

### Install route: SideStore direct is preferable to LiveContainer *for this app*

The developer's stated plan is LiveContainer. It will very likely work, but two properties make a plain
SideStore/AltStore install the better default for LCL specifically:

- **Guest apps do not inherit LiveContainer's entitlements.** Increased Memory Limit must be applied to
  the guest's App ID from inside LiveContainer using `GetMoreRam`
  ([Discussion #388](https://github.com/LiveContainer/LiveContainer/discussions/388)), and there are
  reported failures doing exactly that —
  [issue #429 "Failed to activate and acquire memory lock increment"](https://github.com/LiveContainer/LiveContainer/issues/429).
  AltStore 2.2+/SideStore support the entitlement directly on a normal install. `verified`
- **Guest apps lack normal sandboxing, so data isolation is limited.** LCL stores a GitHub PAT in the
  Keychain and its security model (`ARCHITECTURE.md` §7) assumes ordinary app isolation. Running under
  a weakened sandbox alongside other guests undercuts an assumption we otherwise enforce carefully.
  `likely`

**Metal is not a concern.** LiveContainer loads the guest in-process on iOS, so the GPU is the real
device GPU. (Searches surface "Metal/MLX cannot run in containers" — that concerns Docker and Linux VMs
on Apple Silicon and does not apply here.) Not empirically confirmed for MLX under LiveContainer.
`unverified`

**Recommendation:** install directly via SideStore/AltStore with the entitlement; keep LiveContainer as
the fallback if the 3-app limit becomes the binding problem. Either way the memory entitlement must be
confirmed working on the phone before trusting any load figures.

### Why this changes the architecture

Gemma 4 E2B 4-bit weights are ~2–3 GB, and PLE means static weights exceed what "2.3B effective"
suggests. That already fills the per-app budget before any KV cache, Metal scratch, or the app itself.

**KV cache is the thing that kills it.** At long context the KV cache can reach several times the
weight-file size — so the 128K context window is unusable on this device regardless of entitlements.
Mitigations, in order of leverage:

1. **Cap the working context** (8K default on 6 GB). Biggest lever by far — see `CONTEXT_ENGINE.md` §1.
2. **Quantized KV cache.** Python `mlx-lm` has `QuantizedKVCache` (8-bit, configurable group size);
   4-bit KV is reported to give ~3× context at zero or negative perf cost. **Whether `mlx-swift-lm`
   exposes an equivalent in Swift is unverified** and is a Phase 1 device-gate question. `unverified`
3. Aggressive unload via `ModelLifecycleCoordinator`, and a low `MLX.GPU.set(cacheLimit:)`.
4. QAT/OptiQ quants — same size, better quality, so no reason not to.

**Honest bottom line:** Gemma 4 E2B on a 6 GB iPhone 15 is *tight but plausible*. E4B is almost
certainly out of reach on this device. The first device test decides it, and the answer is not knowable
from CI.

---

## 10. Why the context can be large after all — architecture facts

The §9 conclusion above ("cap at 8K") was reasoned from a generic transformer. Gemma 4 E2B is not
generic, and the specifics change the answer.

- **MQA** — multi-query attention, i.e. the one-KV-head case of GQA. The physical minimum of KV per
  token. `likely`
- **Sliding-window : global attention in a 4:1 pattern**, with the final layer always global. Only the
  global layers grow with sequence length; sliding layers have a *fixed* cache. `likely`
- **Cross-layer KV sharing: 35 layers, but only the first 15 compute their own KV projections.** The
  final 20 reuse KV from the most recent earlier non-shared layer of the same attention type.
  Google reports **2.7 GB saved at bf16 on 128K contexts**. `likely`

Net effect: roughly **3 of 35 layers** grow with context. The KV cache is a minor line item beside the
~2–3 GB of weights — the opposite of the assumption in §9.

### Swift support is present

`mlx-swift-lm` exposes `QuantizedKVCache` (4/8-bit, `groupSize` default 64, `.affine`), and
`GenerateParameters(kvBits:kvGroupSize:quantizedKVStart:)`. `RotatingKVCache(maxSize:keep:step:)` gives
sliding windows with attention-sink retention. Prompt caches persist to `.safetensors` via
`makePromptCache` / `savePromptCache` / `loadPromptCache`.
— [kv-cache.md](https://github.com/ml-explore/mlx-swift-lm/blob/main/skills/mlx-swift-lm/references/kv-cache.md) `verified`

Two documented `fatalError` traps: `RotatingKVCache.toQuantized()` is unimplemented, and
`QuantizedKVCache.update()` must be `updateQuantized()`. The first is harmless for us — the rotating
(sliding) layers are the small fixed ones that need no quantization.

**Revised conclusion: 32K default with `kvBits: 4`.** The real ceiling is **prefill latency** on an
A16, not memory. Numbers above are architecture-derived estimates, not measurements — the device test
still decides.

**Lesson recorded:** derive memory budgets from the *specific* architecture. A generic
"KV cache is several times the weights" rule was wrong here by a large factor, in the pessimistic
direction, and nearly cost the product 4× its usable context.

---

## 8. Deliberately not yet researched

These do not affect Phase 1 and will be verified at the start of the phase that needs them.
Listed so nothing is silently assumed:

- ActivityKit exact lifetime budgets, Dynamic Island region size limits, push-to-start (Phase 6).
- GitHub API secondary rate-limit exact numbers; Actions job-log retrieval shape (Phase 5).
- Web search provider pricing/ToS and the BYOK key-exposure question (Phase 3).
- SwiftData vs GRDB benchmarked at scale — decision made on FTS5 availability, not measured perf.
- App Store Review Guidelines for apps that download model weights and modify their own source.
  **This is a real product risk and must be resolved before any submission.** Not a Phase 1 blocker.
- Whether `NavigationSplitView` can produce a finger-following drawer on iPhone. Assumed **no**
  (columns collapse to a stack); Phase 1 builds a custom container. Needs a device check.
- On-device Foundation Models framework as a cheap host-side worker (titles, compaction, query
  rewriting) — attractive, unverified.
