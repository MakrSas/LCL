# LCL — Product Specification

**LCL — LoCaL.** Your AI, running on your iPhone.

Rule that governs this document (spec §80): **no fake UI.** If a feature does not exist yet, its
control does not exist yet. No disabled buttons hinting at the future, no "coming soon". Phase 1 must
read as a finished small product, not a scaffold for a big one.

---

## 1. Information architecture

```
Chat  ←────────────  the app. everything else is reached from here.
 │
 ├─ edge swipe ──► Sidebar
 │                  ├─ Search
 │                  ├─ Library · Projects · Plugins · Activity
 │                  │  Scheduled · GitHub · Images
 │                  ├─ Pinned
 │                  ├─ Recent
 │                  └─ New Chat · Settings
 │
 ├─ title tap ───► chat options (rename, model, context, share)
 └─ toolbar ─────► Context inspector · Models
```

Chat is the root, not a tab. LCL is one conversation surface with things reachable from it — a tab bar
would imply five co-equal destinations, and they are not co-equal.

---

## 2. Phase 1 scope — what ships

| Screen | State |
|---|---|
| Onboarding (3 screens) | ✅ full |
| Chat | ✅ full |
| Composer | ✅ full (text, attachments-as-files, stop) |
| Sidebar | ✅ full |
| Chat list / Recent / Pinned | ✅ full |
| Model Manager | ✅ full (download, load, unload, delete, default) |
| Settings | ✅ General, Models, Chat, Appearance, Privacy, Advanced only |
| Markdown + code blocks | ✅ full |
| Context Inspector | ✅ read-only view of real budget |
| Search | ✅ chats + messages (FTS5) |

**Deliberately absent in Phase 1** — no entry points at all: Projects, Plugins, Activity, Scheduled,
GitHub, Images, Voice, Vision, Web search, Memory UI, Tools, Decisions.

Those sidebar rows appear as each phase lands. An empty "Projects" screen is worse than no Projects
row.

---

## 3. Onboarding

Three screens, no more (spec §73). Skippable after screen 1 is read.

**1.** `LCL` wordmark, calm. *Your AI, running on your iPhone.*
**2.** *Local by default.* — You decide when LCL can use the web, GitHub or plugins.
**3.** Download **Gemma 4 E2B** — size, what it can do, Wi-Fi/cellular choice. Then straight to chat.

Screen 3 is honest about the download: **~2.5 GB**, resumable, and what happens if they skip (chat is
available, the model is not, and there is one obvious button to start the download later).

---

## 4. Chat

The most important screen in the app.

```
┌─────────────────────────────────────┐
│ ☰            LCL              ⌄     │   glass toolbar
├─────────────────────────────────────┤
│                                     │
│                    ┌──────────────┐ │
│                    │ user message │ │   soft surface, radius 20
│                    └──────────────┘ │
│                                     │
│  Assistant prose sits directly on   │   NO bubble. ~70ch max width.
│  the canvas, unwrapped, with room   │
│  to breathe.                        │
│                                     │
│  ▸ Thinking                         │   collapsed by default, quiet
│                                     │
│  ⧉  ♫  ↗  ↻  ⋯                      │   copy · read aloud · share · regen · more
│                                     │
├─────────────────────────────────────┤
│ ┌─────────────────────────────────┐ │
│ │  Message                        │ │   floating glass composer
│ │  [+]        [Thinking] [🎙] [◉] │ │
│ └─────────────────────────────────┘ │
└─────────────────────────────────────┘
```

- **Assistant messages are never in bubbles** (spec §8). User messages get one soft surface.
- Streaming: block-incremental, coalesced at display rate. A settled block is immutable.
- Thinking is collapsed, `.secondaryLabel`, expandable. Never the visual focus.
- Action row appears when a message settles, not during streaming.
- `Read aloud` and `Sources` appear only once their features exist (Phase 7 / Phase 3).
- Long-press a message → Copy · Keep in Context · Remember for Chat · Share · Select Text.
- Scroll: `.defaultScrollAnchor(.bottom)`. A floating scroll-to-bottom button appears when the user
  scrolls up during generation — and **generation never yanks the view back down**. Fighting the
  user's scroll is the most common chat-UI sin.

### Empty state

**Phase 1: genuinely empty.** No wordmark, no tagline, and not scrollable. Decoration in the one
place the user is about to type is noise.

**Later: suggested actions, not recent history.** The empty chat is where LCL proposes work it could
take on — and the distinction that makes this good rather than demo-ish is *where the suggestions come
from*:

| | |
|---|---|
| ✅ **Derived from a real source** | "Diagnose the failing job in `MakrSas/LCL`" · "Continue the Model Manager task" · "Check this morning's CI". Each carries its source's icon and is actionable because the repo, task or schedule actually exists. |
| ❌ **A generic prompt grid** | "Write a poem" · "Explain quantum physics". Invented filler that teaches the user nothing about what this app can do. |

So a suggestion may only exist once its source does: connected repositories (Phase 5), scheduled tasks
(Phase 6), project files (Phase 2), an unfinished AgentTask. With no sources connected there are no
honest suggestions, and the empty state stays empty — same rule as everywhere else, no fake UI.

---

## 5. Composer

```
no text:    [ + ]              [Thinking] [Mic] [Voice]
with text:  message…
            [ + ]              [mode] [mic] [ ↑ ]
streaming:  [ + ]              [mode] [mic] [ ■ ]     ← Stop
```

Behaviour, all of which is the hard part:

- Grows with content to a max of ~40% of screen height, then scrolls internally.
- **Tracks the keyboard exactly**, with no jump during the keyboard animation. Implemented via
  `safeAreaInset(edge: .bottom)` so the transcript's insets stay correct.
- Attachments show as chips **above** the composer, each removable.
- `↑` becomes `■` during generation. Same position, same size — the control does not move.
- Send is disabled on empty/whitespace input; the button does not visually flicker.
- One `GlassEffectContainer` for the whole control cluster.
- Mic and Voice appear only in Phase 7. In Phase 1 the right side is `[Thinking] [↑]`.

---

## 6. Sidebar

Interactive, finger-following. `NavigationSplitView` collapses to a stack on iPhone and gives no
drag-to-reveal drawer, so this is a custom container (spec §10).

```
LCL                        ⌕

Library
Projects
Plugins
Activity
Scheduled
GitHub
Images

Pinned
  › Native Model Manager

Recent
  › Streaming performance
  › Liquid Glass questions

[New Chat]          [Settings]
```

- Edge swipe from the left, **1:1 with the finger**, no animation while dragging.
- Velocity-aware settle using `predictedEndTranslation`; **interruptible** mid-flight.
- Chat surface translates and scales slightly, gaining `Radius.sidebarPeel` corners.
- Backdrop dims progressively with drag position.
- One latched haptic at the open/close threshold — no chatter on re-crossing.
- Tap outside or swipe back to close.
- **VoiceOver gets a real button**, because an edge swipe is not discoverable.
- Phase 1 shows only rows that exist: Library, Recent, Pinned, New Chat, Settings.

---

## 7. Model Manager

```
┌──────────────────────────────────────┐
│  Gemma 4 E2B                    ✓    │
│  Google · 2.3B effective · 4-bit     │
│  2.5 GB · ~3.1 GB RAM                │
│  Context 8K on this iPhone           │
│  Thinking                            │
│                            [Loaded]  │
└──────────────────────────────────────┘
```

Two honesty rules on this card, both learned the hard way:

- **Context shows the *working* context, not the model's maximum.** Gemma 4 E2B supports 128K; a 6 GB
  iPhone cannot hold the KV cache for it ([RESEARCH_LOG.md](RESEARCH_LOG.md) §9). Printing "128K" next
  to a model that will actually run at 8K is exactly the kind of lie spec §80 forbids.
- **Capability chips list only what LCL supports today.** No `Tools` chip until tool calling exists in
  Phase 4; no `Vision` until Swift-side Gemma 4 vision is confirmed.

Card fields per spec §7. Actions: Download · Import · Delete · Load · Unload · Set Default.

Honest signals, because this is where users get burned:

- Capability chips reflect **what LCL actually supports for that model today**. Gemma 4 E2B shows
  `Thinking · Tools` in Phase 1 — **not** Vision, because Swift-side vision is unconfirmed. Claiming a
  capability we cannot deliver is the exact failure spec §80 forbids.
- RAM estimate and recommended device shown before download, not after.
- Live: memory pressure, thermal state, and whether the model is resident.
- Download is resumable and shows real bytes, not a fake percentage.

---

## 8. Settings — Phase 1

```
General      appearance, haptics, default model
Models       manage, default, memory behaviour
Chat         streaming, thinking visibility, title generation
Context      budget display, compaction (read-only in Phase 1)
Appearance   theme, accent, text size note
Privacy      what leaves the device — "nothing, in Phase 1"
Advanced     diagnostics
```

Web, GitHub, Plugins, Memory, Notifications, Scheduled appear with their phases.

**Privacy** is a real screen from day one, and in Phase 1 it says something genuinely true: nothing
leaves the device except the model download. That is the product's core claim; it should be verifiable
on the Privacy screen, not just in marketing.

### Advanced Diagnostics (spec §78)

Model · tokens/sec · input/output tokens · context utilization · compaction count · retrieved items ·
memory usage · thermal state · generation duration · tool duration · active tasks.

Not hidden behind a gesture — just at the bottom of Settings, where a curious user finds it and a
casual user does not care.

---

## 9. Copy rules

- Plain, calm, lowercase-free of exclamation marks. No "✨ AI magic".
- Never claim local processing for something that leaves the device (spec §61, §62).
- Errors say what happened and what to do:
  *"Not enough storage to download Gemma 4 E2B. 2.5 GB needed, 1.1 GB free."*
- Waiting states name what is being waited on:
  *"Waiting to continue · needs LCL open"* — never a bare spinner.
- Destructive confirmations name the object: *"Delete Gemma 4 E2B? The 2.5 GB download will be
  removed."*

---

## 10. Phase map

| Phase | Adds |
|---|---|
| **1 · Native Foundation** | shell, DesignSystem, Chat, Composer, Sidebar, model load, streaming, Markdown, persistence, Model Manager, Search |
| 2 · Intelligence | Thinking UI, Vision, ContextEngine, Inspector, compaction, Memory, Planning, Decisions, Projects, Files |
| 3 · Web & Research | search, WebReader, citations, Sources, ProductResearchAgent, ResearchBrief |
| 4 · Tools & MCP | ToolRegistry, permissions UI, MCP/Plugins, Dynamic Tools, tool activity cards |
| 5 · GitHub Agent | token, GitHubProvider, browser, diff, Actions, BuildMonitor, AgentTask, Activity, self-development |
| 6 · Background | Scheduled, checkpoints, notifications, Live Activities, Dynamic Island |
| 7 · Advanced | Voice, remote providers, deeper retrieval, polish |

Phase 1 must already feel finished (spec §79). Fewer features, no rough edges.
