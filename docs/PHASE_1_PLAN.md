# LCL — Phase 1 Implementation Plan

**Goal: a flawless foundation and a genuinely beautiful native interface — not feature count**
(spec §88).

Phase 1 ships when LCL is a small, complete, beautiful local chat app. Not a scaffold.

---

## Working method, given no Mac

CI is the compiler. Every step below has a **done-condition verifiable in CI**, plus a separate device
gate for the things only a phone can prove.

```
edit on Windows  →  push branch  →  Actions (macos-26, Xcode 26.6)
                                          │
                              ┌───────────┴───────────┐
                              ▼                       ▼
                     compact error JSON          green + test results
                     (read from Windows)                │
                              │                         ▼
                          fix, push                 design review gate
```

Rules:
- **Never accumulate broken code** (spec §80). One step at a time, each landing green.
- No step is "done" while CI is red or a warning is unaddressed.
- UI steps additionally pass the Design Review checklist ([DESIGN_SYSTEM.md](DESIGN_SYSTEM.md) §10).
- Device gates are batched — they need a real iPhone and a paid developer account.

---

## Step 0 — Project + CI *(no app code)*

Prove the pipeline before writing anything that depends on it.

- `LCL.xcodeproj`, hand-authored, using `PBXFileSystemSynchronizedRootGroup` folder references.
- Folder skeleton from [ARCHITECTURE.md](ARCHITECTURE.md) §2.
- SPM: `mlx-swift-lm`, `GRDB.swift`. `Package.resolved` committed.
- `.github/workflows/ci.yml`: pinned `macos-26` + Xcode 26.6, SPM cache, build for
  `generic/platform=iOS` with signing off, test on iOS 26 simulator, `xcresulttool` → compact
  diagnostics artifact.
- Deployment target **iOS 26.0**, Swift 6 strict concurrency.

**Done:** an empty app builds and one trivial test passes in CI.
**Why first:** if the hand-authored project file is wrong, we need to know now — not after 3000 lines.

---

## Step 1 — DesignSystem

Tokens and primitives before any screen, so nothing is retrofitted.

- `Palette`, `Space`, `Radius`, typography helpers.
- `MotionSystem`, `HapticManager` (semantic events only).
- `GlassCluster` with its **Reduce Transparency opaque fallback** as a real code path.
- `PrimaryButton`, `QuietButton`, `Chip`, `Row`, `SectionHeader`, `StatusGlyph`, `MetadataLabel`,
  `EmptyState`.
- A `DesignGallery` debug screen showing every component × light/dark × smallest/largest Dynamic Type.

**Done:** gallery renders in simulator tests; snapshot tests pass at both type extremes in both
appearances.

---

## Step 2 — Persistence

- GRDB stack: `DatabaseQueue` for writes, pool for reads, migrations.
- Schema: `chats`, `messages`, `attachments`, `models`, `settings`, `archive_events`.
- FTS5 virtual table over message content with BM25.
- `Archive` — append-only, never mutated.
- Data Protection on the DB file; excluded from iCloud backup.

**Done:** round-trip tests; FTS search returns ranked results; migration from empty runs clean.

---

## Step 3 — App shell + Sidebar

The first real UI, and the hardest gesture work in the app — done early because everything sits inside it.

- `AppRoot`: chat surface + custom sidebar container.
- Edge-swipe drawer: 1:1 finger tracking, no animation while dragging, velocity settle via
  `predictedEndTranslation`, interruptible mid-flight.
- Surface translate + small constant `Radius.sidebarReveal` (no scale, no shadow — both cost
  real frames); progressive backdrop dim, hit-testable only once genuinely open.
- One latched threshold haptic.
- VoiceOver button alternative.
- Rows: Library, Pinned, Recent, New Chat, Settings. **Nothing that does not exist yet.**

**Done:** CI green; sidebar works in simulator tests. **Device gate:** does the drag actually feel
native? This is the single most important feel question in Phase 1.

---

## Step 4 — Markdown renderer

Built before Chat, because Chat's performance depends entirely on it.

- Block-level incremental parser: headings, paragraphs, bold, italic, lists, tables, links,
  blockquotes, inline code, code blocks.
- **A settled block is immutable and never re-parsed.** Only the trailing block re-parses as tokens
  arrive.
- `CodeBlock`: language label, Copy, horizontal scroll, syntax highlighting for ~8 languages.
- Full Dynamic Type support; selectable text.

**Done:** unit tests for incremental parsing (append a token → only the last block changes);
performance test appending 4000 tokens stays within budget.

---

## Step 5 — Chat + Composer

- Transcript: `ScrollView` + `LazyVStack`, `.defaultScrollAnchor(.bottom)`.
- Assistant prose unwrapped, ~70ch max; user message on one soft surface.
- Composer: auto-grow to ~40% height then internal scroll; `safeAreaInset(edge: .bottom)`; exact
  keyboard tracking; `↑` ⇄ `■` in a fixed position.
- Action row on settled messages: Copy, Share, Regenerate.
- Long-press menu; destructive items red.
- Floating scroll-to-bottom; **generation never yanks the user's scroll**.

**Done:** CI green; keyboard and scroll behaviour covered by simulator UI tests.
**Device gate:** keyboard tracking with no jump; scroll under load.

---

## Step 6 — ModelProvider + MockModelProvider

The whole loop, testable with no GPU and no weights.

- `ModelProvider`, `ModelCapabilities`, `GenerationEvent`.
- `MockModelProvider` replaying scripted event sequences.
- `GenerationEngine`: streaming, display-rate coalescing, cancellation, token accounting.
- Wire Chat to the mock end to end.

**Done:** a scripted "conversation" streams into Chat in simulator tests, cancels cleanly, and
persists correctly. **This is the most valuable test infrastructure in the project** — it is how the
agent loop stays verifiable in later phases without a device.

---

## Step 7 — Gemma4Provider

- `MLXLLM` + `MLXGuidedGeneration` linked and building for iOS in CI.
- Model download via `URLSession` background config: resumable, Wi-Fi default, real byte progress.
- Load/unload on a dedicated actor; `MLX.GPU.set(cacheLimit:)` by RAM tier.
- Chat template via the tokenizer — **not** hand-assembled strings.
- Thinking-delimiter parsing → `.thinking` events.
- `ModelLifecycleCoordinator`: unload on background, memory pressure, thermal, idle.

**Done (CI):** links and builds; provider unit-testable with a stubbed container.
**Device gate — the big one:**
1. `gemma-4-e2b-it-4bit` downloads and loads.
2. Tokens actually stream.
3. Measure load time, tokens/sec, resident bytes, thermal after 5 min.
4. **Unload genuinely frees Metal buffers** — if `container = nil` does not release, the lifecycle
   design changes.

---

## Step 8 — Model Manager

- Model list + cards with real fields (spec §7).
- Download / Import / Delete / Load / Unload / Set Default.
- Live memory pressure + thermal + residency.
- **Capability chips show only what LCL actually supports today** — Gemma 4 E2B shows
  `Thinking · Tools`, not Vision.

**Done:** CI green; all actions exercised in simulator tests against a stub provider.

---

## Step 9 — Search, Settings, Onboarding

- Global search over chats + messages via FTS5.
- Settings: General, Models, Chat, Context (read-only), Appearance, Privacy, Advanced.
- Advanced Diagnostics reading real metrics.
- Three onboarding screens; honest download copy.
- Chat context menu: Rename, Pin, Share, Archive, Delete (red).

**Done:** CI green; search returns ranked results across a seeded corpus.

---

## Step 10 — Design Review + hardening

The step that most projects skip and most needs doing (spec §81).

- Full checklist per screen: Chat, Composer, Sidebar, Model Manager, Settings, Onboarding.
- Dynamic Type XS → accessibility5 on every screen.
- VoiceOver traversal; streaming announcements polite, not per-token.
- Reduce Motion, Reduce Transparency, Increase Contrast.
- Smallest and largest supported iPhone.
- Zero warnings. No `TODO` in shipped paths. No dead controls.

**Done:** every checklist item passes or is logged as explicit, named debt.

---

## Order rationale

```
0 CI ──► 1 Design ──► 2 Persistence ──► 3 Shell/Sidebar ──► 4 Markdown
                                                                 │
                                              ┌──────────────────┘
                                              ▼
                              5 Chat/Composer ──► 6 Mock provider ──► 7 Gemma
                                                        │
                                              8 Model Manager ──► 9 Search/Settings
                                                        │
                                              10 Design Review
```

- CI first, because on Windows an unverifiable project file is a total blocker.
- DesignSystem before screens, so no screen is retrofitted onto tokens.
- Markdown before Chat, because Chat's perf is Markdown's perf.
- **Mock provider before the real one**, so the loop is proven correct before GPU variables enter.
- Real model last, because it is the only part that cannot be verified without a device.

---

## Definition of done for Phase 1

1. CI green: builds for iOS, all tests pass, zero warnings.
2. On a real iPhone: download → load → chat → stream → persist → relaunch → history intact.
3. Design Review passed on all six screens.
4. Accessibility contract met.
5. Measured: load time, tokens/sec, peak memory, thermal after 5 minutes — **recorded in the repo**,
   not just observed.
6. No dead controls, no placeholder screens, no claimed-but-absent capability.
7. It feels like a finished product that happens to be small.

---

## Known Phase 1 gates outside CI

Batched because they need a real device and a paid Apple Developer account ($99/yr):

- Spring and haptic feel; sidebar drag quality.
- Keyboard tracking with no jump.
- Glass rendering over live content; OLED black.
- Real tokens/sec, memory, thermal under sustained inference.
- Whether unload actually frees GPU memory.

Until then CI proves LCL **compiles and its logic holds**. Only the phone proves it **feels right** —
and feel is requirement #0.
