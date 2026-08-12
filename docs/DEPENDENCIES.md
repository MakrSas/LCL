# LCL — Dependency Plan

Principle: **few dependencies, each load-bearing, each replaceable.** Anything we could write in a day
we write. Anything that is a research project (Metal kernels, grammar-constrained sampling, SQLite
FTS) we take.

All versions verified 2026-08-12 — see [RESEARCH_LOG.md](RESEARCH_LOG.md).

---

## Phase 1

| Package | Coordinates | Products | License | Why |
|---|---|---|---|---|
| **mlx-swift-lm** | `github.com/ml-explore/mlx-swift-lm` `upToNextMajor(3.31.3)` → resolves **3.31.4** | `MLXLLM`, `MLXLMCommon`, `MLXEmbedders` | MIT | On-device inference. Gemma 4 text support landed 3.31.3. `MLXEmbedders` gives on-device embeddings for semantic retrieval with no second framework. |
| **mlx-swift** | transitive (`~0.31.4`) | — | MIT | Metal array/NN framework under the above. Not pinned directly. |
| **swift-transformers** | transitive | — | Apache-2.0 | Tokenizer + Hugging Face Hub download. Pulled in by mlx-swift-lm. |
| **GRDB.swift** | `github.com/groue/GRDB.swift` `upToNextMajor(7.0.0)` | `GRDB` | MIT | SQLite with **FTS5 + BM25**. The reason we are not on SwiftData. |

That is the entire Phase 1 third-party surface: **two direct dependencies.**

### Version pinning

`Package.resolved` must be committed and CI must then build from it without re-resolving — otherwise
an upstream release breaks a build we cannot reproduce locally, which on Windows means we cannot
debug it at all.

**Bootstrapping:** it cannot be generated here (no Swift toolchain), so CI resolves the graph and
uploads it as the `package-resolved` artifact. Committed as of the first green run, pinning:

```
mlx-swift-lm 3.31.4 · mlx-swift 0.31.6 · GRDB 7.11.1
swift-syntax 603.0.2 · swift-numerics 1.1.1 · swift-argument-parser 1.8.2
```

**We deliberately do NOT pass `-disableAutomaticPackageResolution`.** A committed `Package.resolved`
already pins versions — SwiftPM honours it and only re-resolves when the manifest genuinely requires
it. Adding the flag would instead make CI *fail* whenever the two drift, and since we cannot
regenerate `Package.resolved` on Windows, every dependency change would need the flag temporarily
removed to bootstrap the new graph. Reproducibility comes from the committed file; the flag would only
add friction.

---

## Later phases

| Phase | Package | Coordinates | License | Why |
|---|---|---|---|---|
| 2 | `MLXVLM` | already in mlx-swift-lm | MIT | Vision. **Gated on Gemma 4 VLM support landing** — see risks. |
| 4 | `MLXGuidedGeneration` | mlx-swift-lm, **`main` only — not in 3.31.4** | MIT | Grammar-constrained tool calls. Blocked on a release; fallbacks in [RESEARCH_LOG.md](RESEARCH_LOG.md) §3. |
| 3 | SwiftSoup | `github.com/scinfu/SwiftSoup` | MIT | HTML parsing for `WebPageReader`. Alternative: `WKWebView` + injected Readability.js — heavier, but handles JS-rendered pages. Decide with measurements in Phase 3. |
| 4 | mcp-swift-sdk | `github.com/modelcontextprotocol/swift-sdk` `0.11.0` | MIT | Official MCP client. `HTTPClientTransport` (HTTP + SSE). **Remote servers only** — stdio is impossible on iOS. |
| 5 | — | — | — | GitHub: plain `URLSession` against the REST API. No SDK. Octokit-style clients add surface without solving anything. |

### Explicitly rejected

| Not using | Instead | Why |
|---|---|---|
| SwiftData | GRDB | No FTS5. A retrieval-first app cannot use it. |
| Alamofire | `URLSession` | Modern async `URLSession` is sufficient; we need custom TLS/ATS policy anyway. |
| A Markdown library | own renderer | We need *block-incremental* parsing for streaming. Every off-the-shelf renderer re-parses the whole document, which is exactly the perf bug spec §8 forbids. |
| A syntax-highlighting library | own tokenizer | We need ~8 languages. A regex tokenizer per language is smaller than the dependency and does not fight our type system. |
| XcodeGen / Tuist | hand-authored `.pbxproj` with synchronized folders | Both are Swift binaries — unrunnable on Windows. See below. |
| Community Gemma-4 Swift ports | upstream `mlx-swift-lm` | Unvetted, unmaintained, and we cannot test locally. Upstream already supports E2B text. |
| A crash reporter (Phase 1) | — | Adds a privacy story and a network dependency to a local-first app. Revisit before any public release. |

---

## Toolchain

No Swift toolchain, no Xcode, and no Mac on the development machine. This is a *constraint*, not a
problem to solve — the pipeline is designed for it.

| Need | Solution |
|---|---|
| Xcode project | Hand-authored `LCL.xcodeproj` using `PBXFileSystemSynchronizedRootGroup` folder references. **Adding a `.swift` file requires no project edit.** |
| Compiler | GitHub Actions `macos-26`, Xcode 26.6. Free for this public repo. |
| Tests | `xcodebuild test` on an iOS 26 simulator in CI. **The only automated verification that exists** — with no Mac, this is what keeps the agent loop's invariants (permission gates, branch policy, checkpoint restore, compaction) checkable at all. Installing a build and using it cannot catch a silently broken invariant. |
| Diagnostics | `-resultBundlePath` + `xcresulttool` → compact JSON of errors, so failures are readable from Windows and parseable by the agent. |
| Formatting | `swift-format` in CI (ships with Xcode). Advisory, not blocking. |
| Device install | **Sideloading** — unsigned `.ipa` from CI, installed with SideStore / AltStore / iLoader / LiveContainer. No paid Apple Developer Program needed. Requires the **Increased Memory Limit** entitlement, which AltStore 2.2+ and SideStore support for sideloaded apps (see [RESEARCH_LOG.md](RESEARCH_LOG.md) §9 for the free-vs-paid-certificate caveat). TestFlight stays the option if entitlements turn out to be blocked. |

**What we cannot verify without a Mac or a device:** real spring/haptic feel, actual tokens/sec,
memory pressure and thermal behaviour under sustained inference, and how glass renders over live
content. These are exactly the things the spec cares most about, so they are gated on device testing,
not on CI green. CI proves it *compiles and its logic holds*; only the phone proves it *feels right*.

---

## Risk register

| # | Risk | Sev | Mitigation |
|---|---|---|---|
| 1 | **No background GPU on iPhone** ⇒ no background inference. Structural, unfixable. | **blocker (accepted)** | Architecture splits steps into `needsModel` / `hostOnly`. UI states this truthfully. Never promised in copy. |
| 2 | Gemma 4 **vision** unconfirmed in `MLXVLM` | high | Phase 1 is text-only anyway (matches spec phasing — Vision is Phase 2). Verify before committing Phase 2 scope; fall back to a Gemma 3 VLM or defer. |
| 3 | E2B tool-call quality at 2.3B may still be weak even with grammar | high | Grammar guarantees *form*, not *judgment*. Mitigate with small tool count per turn, one-tool-at-a-time routing, and host-side retry with a narrowed grammar. Benchmark early; E4B is a drop-in escalation. |
| 4 | Hand-authored `.pbxproj` breaks and cannot be repaired locally | high | Synchronized folders keep it nearly static. CI validates it parses on every push. Keep a known-good copy tagged. |
| 5 | Metal toolchain missing on the Xcode 27 runner image ([#14450](https://github.com/actions/runner-images/issues/14450)) | medium | Stay on `macos-26`/Xcode 26.6 until resolved. Pin the image explicitly — never `macos-latest`. |
| 6 | `mlx-swift-lm` is pre-1.0 and moves fast (3.31.x, breaking majors) | medium | Pin exactly; commit `Package.resolved`; `ModelProvider` isolates the whole API surface to one file. |
| 7 | Multi-GB model download on cellular / interrupted | medium | `URLSession` background config, resumable, Wi-Fi default with explicit cellular opt-in. |
| 8 | **Memory on the actual target device.** iPhone 15 = 6 GB RAM, per-app limit ≈2.5–3 GB; E2B 4-bit weights are ~2–3 GB before any KV cache | **high** | 8K working context by default (biggest lever), Increased Memory Limit entitlement, quantized KV cache if Swift exposes one, aggressive unload, low `MLX.GPU.set(cacheLimit:)`. **Decided by the first device test, not by CI.** See [RESEARCH_LOG.md](RESEARCH_LOG.md) §9 |
| 9 | **App Review**: an app that downloads model weights and can modify its own source | high | Weights are data, not code — the established pattern for on-device ML apps. Self-development targets a *GitHub repo*, never live app code; nothing executable is downloaded. **Must be confirmed before submission.** |
| 10 | Prompt injection from web/MCP/GitHub content reaching an agent with repo write access | high | Taint tracking at the boundary; untrusted content delimited as data; tainted results can never widen permissions or authorize actions; High Impact always needs fresh human consent. |
| 11 | Search API key must live on-device (no backend) | medium | BYOK per provider, Keychain-stored, replaceable `SearchProvider`. Documented honestly to the user in Privacy. |
| 12 | iOS 27 GA slips or changes Liquid Glass again | low | Deployment target is iOS 26; iOS 27 APIs are additive and behind availability checks. |
