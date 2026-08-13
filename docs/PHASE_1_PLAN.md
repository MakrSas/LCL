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

**Shipped (2026-08-13):** `chat` + `message` tables, external-content FTS5 with BM25 ranking,
Data Protection + backup exclusion on the DB file, and `ChatStore` — the actor exposing exactly
the operations `ChatViewModel` needs (`createChat`, `listChats`, `deleteChat`, `loadMessages`,
`insertMessage`, `finishMessage`, `search`). See `LCL/Core/Persistence/`. Tests in
`ChatStoreTests.swift` cover round-trip, ordering, cascade delete, ranked search, and FTS5's
special characters surviving ordinary user text — all against the real schema via
`AppDatabase.openInMemory()`, no device required.

`attachments`, `models`, `settings`, `archive_events` deliberately **not yet built** — nothing
in Phase 1 needs them yet (`settings` still lives in `AppSettings`, in-memory; attachments are
Phase 3 vision work; `models`/Model Manager is Step 8; `archive_events` is the Context Engine's,
Phase 2). Adding a table later is a new migration, not a rewrite of this one — GRDB's migrator
runs migrations forward-only and in order, so nothing here needs to anticipate their shape now.

**Still open:** wiring `ChatStore` into `ChatViewModel` itself (the five-point integration seam
below) and into `AppRoot`'s `onNewChat`. Deliberately left for its own change — it touches the
same files as this week's sidebar work, which has an unconfirmed on-device fix in flight
(docs/RESEARCH_LOG.md §11), and mixing the two would make a regression in either one harder to
isolate.

**Done:** round-trip tests ✅; FTS search returns ranked results ✅; migration from empty runs
clean ✅ (all in `ChatStoreTests.swift`, exercised on every CI run). `ChatViewModel` wiring is
the remaining item before Step 2 is fully done.

### `ChatViewModel` integration seam (`ChatStore` shipped, wiring TBD)

Reviewed 2026-08-13, before `ChatStore` existed, to save a research round-trip once the schema
landed — it has now (above), with method names chosen to match this seam exactly. `ChatViewModel`
today (`LCL/Features/Chat/ChatViewModel.swift`) still holds `messages: [ChatMessage]` purely in
memory — five concrete points need to change, and nowhere else does:

1. **`init`** needs a `chatID` and a `ChatStore`, and should call `loadMessages(chatID:)` instead
   of always starting empty.
2. **`send()`** calls `insertMessage(_:chatID:)` immediately after appending to memory — once for
   the user message (so it survives a kill before the assistant even responds), once for the
   assistant placeholder (empty, `isStreaming: true`) so a chat interrupted mid-stream still has a
   row to resume into.
3. **`flush()` must NOT call `insertMessage`/`finishMessage` on every call.** It already runs on a
   ~16ms display timer (`docs/ARCHITECTURE.md` §11) — writing to SQLite at that rate would be pure
   waste. The database only needs the *final* text.
4. **`finishStreaming()`** is therefore the one caller of `finishMessage(_:text:thinking:usage:)`:
   a single write of the completed text, thinking, and `TokenUsage` once a turn actually finishes
   (including on `stop()`, which already routes through `finishStreaming()` — a stopped generation
   still persists whatever arrived).
5. **`clear()`** currently wipes the in-memory array, which matches spec §80 for a mock model with
   nothing to lose — but is wrong the moment persistence exists. "New Chat" must call
   `createChat()` and switch the active `chatID`, never delete history the app promised never to
   destroy (`docs/CONTEXT_ENGINE.md` §1). `AppRoot`'s `onNewChat: { viewModel.clear() }` needs to
   become "create chat, switch to it" for the same reason.

None of `send`/`stop`/`regenerate`/`flush`'s *streaming* logic needs to change — persistence is
additive at specific points, not a rewrite of the flow.

---

## Step 3 — App shell + Sidebar

The first real UI, and the hardest gesture work in the app — done early because everything sits inside it.

- `AppRoot`: chat surface + custom sidebar container, no `NavigationStack` (nothing to push to
  yet, and its toolbar proved unreliable inside the drawer's offset/mask anyway — see below).
- Edge-swipe drawer: 1:1 finger tracking, no animation while dragging, velocity settle via
  `predictedEndTranslation`, interruptible mid-flight.
- Chat is masked to a narrower slice by a custom `RevealClip` shape, never actually resized —
  its layout stays full width throughout so nothing inside it (top bar, composer) ever has to
  relayout for the drawer. Asymmetric rounding: small at the reveal edge (clears the toolbar
  toggle and composer's `+`), full device-corner at the trailing edge (nothing sits there).
- Chat's own top bar is a plain `HStack` via `.safeAreaInset(edge: .top)` — matching the
  composer's `.safeAreaInset(edge: .bottom)`, which never had a positioning problem. A system
  toolbar did, once rendered inside the drawer's transformed ancestor; removed rather than
  chased further with padding guesses. Root cause confirmed, not just worked around:
  `NavigationStack`'s toolbar bridges to `UINavigationController` and has independently-reported
  reliability problems under layout changes (`docs/RESEARCH_LOG.md` §11). Safe-area insets are
  now captured once in `AppRoot` from a reader that never ignores the safe area, sidestepping a
  disputed `GeometryProxy.safeAreaInsets` behavior rather than relying on either side of it
  (`docs/RESEARCH_LOG.md` §11).
- No scale, no shadow on the reveal — both cost real frames for no benefit.
- Progressive backdrop dim, hit-testable only once genuinely open.
- One latched threshold haptic.
- VoiceOver button alternative.
- Rows: Recent (only when non-empty), New Chat, Settings. **Nothing that does not exist yet.**

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

- `MLXLLM` (+ `MLXLMCommon`) linked and building for iOS in CI, pinned at `mlx-swift-lm` **3.31.4**
  exactly — not `main` (`docs/RESEARCH_LOG.md` §3: `main`'s `Package.swift` lists
  `MLXGuidedGeneration`, which does not exist in the tagged release CI actually builds against).
  Guided generation is Phase 4's problem (tool calling), not Step 7's — `ModelCapabilities.gemma4E2B`
  already encodes `guidedGeneration: false` for exactly this reason.
- Model download via `URLSession` background config: resumable, Wi-Fi default, real byte progress.
  `mlx-swift-lm`'s `Downloader` (`Libraries/MLXLMCommon/Downloader.swift`) is a plain protocol —
  `download(id:revision:matching:useLatest:progressHandler:)` — not a fixed implementation, so LCL
  writes its own conformance backed by a real background `URLSession` rather than accepting
  whatever the library's built-in Hugging Face downloader does by default. `verified` (read
  directly at the pinned tag).
- Load/unload on a dedicated actor; `MLX.GPU.set(cacheLimit:)` by RAM tier.
- Chat template via `ChatSession` (`Libraries/MLXLMCommon/ChatSession.swift`) — it owns turn-tag
  assembly and KV-cache management internally from `Chat.Message`s; `Gemma4Provider` never
  hand-assembles `<|turn>` strings. `verified` (read directly at the pinned tag).
- Thinking-delimiter parsing → `.thinking` events. Concrete token strings and the exact
  `Generation`-to-`GenerationEvent` mapping now researched — `docs/RESEARCH_LOG.md` §12,
  `docs/MODEL_INTEGRATION.md` §3.
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
