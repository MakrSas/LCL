# LCL — Design System

Design is requirement #0 (spec §0). "It works" is not a passing grade. This document is the contract:
if a screen disagrees with it, the screen is wrong.

**Baseline:** iOS 26.0, Liquid Glass available. iOS 27 refinements behind `if #available(iOS 27, *)`.

---

## 1. What LCL feels like

> Calm, premium, native, minimal, tactile, spacious, content-first.

Five working principles, each with a testable consequence:

| Principle | Consequence |
|---|---|
| **Content first** | Text sits on the background. Chrome floats above it. If a container adds no meaning, delete it. |
| **Glass is for chrome** | Glass marks *what floats*. A paragraph never floats. |
| **Calm surfaces** | ≤ 2 elevation levels visible at once. No card inside a card, ever. |
| **Motion explains** | Every animation answers "where did this come from?" Decorative motion is a bug. |
| **Tactile, not noisy** | Haptics mark state changes the user caused. Never progress, never tokens. |

### Anti-patterns — automatic design review failure

- Assistant text in a bubble. Assistant prose is **unwrapped**, directly on the background (spec §8).
- A screen that is a vertical stack of rounded cards.
- Glass behind body text.
- Custom fonts, custom-drawn switches, custom-drawn navigation.
- A "dashboard": grids of metric tiles the user did not ask for.
- Two competing accent colours.
- Emoji as iconography. **SF Symbols only.**
- `.easeInOut` anywhere. Springs describe physical motion; ease curves describe nothing.

---

## 2. Colour

Semantic system colours first — they solve dark mode, Increase Contrast and vibrancy for free. LCL
adds exactly one brand hue and a small set of role tokens.

### Brand

A single restrained hue used for interactive accents and nothing else. **Never** for surfaces,
message backgrounds, or decoration.

The accent is **user-selectable** in Settings → Appearance: Teal (default), Blue, Indigo, Amber, Rose,
Graphite. The rule is "one accent at a time", not "one hardcoded hue".

```
teal   light #2F6F6B   dark #5FB3AC   (default — calm, not "AI purple")
```

Each choice carries a lifted dark variant, because a colour that reads on white fails on true black.
Teal as the default deliberately avoids the violet/indigo gradient cliché of AI apps (spec §74: our own
identity, no borrowed branding).

**Implementation:** `AccentChoice` is applied once as `.tint()` at the root, and components read
`Color.accentColor`. There is deliberately **no** `Palette.accent` — a palette constant beside a tint
would be a second source of truth and the two would drift.

### Role tokens

Everything else derives from system colours so the OS keeps its promises:

```swift
enum Palette {
    static let canvas          = Color(.systemBackground)          // chat background
    static let canvasRaised    = Color(.secondarySystemBackground) // sidebar, sheets
    static let surfaceUser     = Color(.tertiarySystemFill)        // user message only
    static let separator       = Color(.separator)
    static let textPrimary     = Color(.label)
    static let textSecondary   = Color(.secondaryLabel)
    static let textTertiary    = Color(.tertiaryLabel)             // timestamps, token counts
    static let accent          = Color("lclAccent")
    static let destructive     = Color(.systemRed)
    static let success         = Color(.systemGreen)
    static let warning         = Color(.systemOrange)
    static let thinking        = Color(.secondaryLabel)            // reasoning is quiet
}
```

### OLED dark mode

Dark mode is the primary mode and gets designed first.

- Canvas is **true black** `#000000`. On OLED this is pixels off — deeper than any grey, and it makes
  glass chrome read as genuinely floating.
- Raised surfaces step up in *luminance*, never in hue: `#000` → `#0E0E10` → `#1A1A1D`.
- No pure-white text. `Color(.label)` in dark mode is already softened; keep it.
- Accent lifts to `#5FB3AC` — the light-mode teal fails contrast on black.
- **Never** a dark gradient behind text. It defeats OLED black and muddies glass.

### Contrast

Body text ≥ 7:1 (AAA), secondary ≥ 4.5:1, tertiary ≥ 3:1 and only for non-essential text. Verified at
both extremes of Dynamic Type. Under Increase Contrast: separators become opaque, glass loses
translucency, tertiary text promotes to secondary.

---

## 3. Typography

**System fonts only** — SF Pro via `.font(.body)` etc. Dynamic Type is not optional.

| Role | Style | Weight | Use |
|---|---|---|---|
| Screen title | `.largeTitle` | `.bold` | navigation large titles |
| Section | `.title3` | `.semibold` | sheet and group headers |
| **Assistant body** | `.body` | `.regular` | the most important text in the app |
| User message | `.body` | `.regular` | inside `surfaceUser` |
| Supporting | `.subheadline` | `.regular` | descriptions, model cards |
| Metadata | `.footnote` | `.regular` | timestamps, source counts |
| Micro | `.caption2` | `.medium` | token counts, badges |
| Code | `.body.monospaced()` | `.regular` | code blocks, diffs, logs |

Rules:

- Assistant body line length capped at **~70 characters** via `.frame(maxWidth:)` on wide devices.
  Full-width text at large sizes is unreadable.
- Line spacing `+0.18em` on assistant prose. It is read continuously; it needs air.
- **Never** `.lineLimit(1)` on user content without `.minimumScaleFactor` or truncation affordance.
- Numerals in metrics use `.monospacedDigit()` so streaming counters don't jitter.
- Dynamic Type is honoured to `.accessibility5`. Above `.xxLarge`, horizontal control rows reflow to
  vertical — tested, not hoped.

---

## 4. Space, radius, hit targets

An 8pt grid with a 4pt half-step. Four spacing values, not fifteen.

```swift
enum Space {
    static let hair: CGFloat = 4
    static let tight: CGFloat = 8
    static let base: CGFloat = 16     // default gutter
    static let loose: CGFloat = 24    // between semantic groups
    static let section: CGFloat = 40  // between major regions
}

enum Radius {
    static let control: CGFloat = 12  // buttons, chips
    static let surface: CGFloat = 20  // user message, cards
    static let sheet: CGFloat = 28    // sheets, composer
    static let sidebarPeel: CGFloat = 36  // chat surface when sidebar is open
    // containers use .rect(cornerRadius:style: .continuous) — never .circular
}
```

- Screen gutter: `Space.base` (16pt).
- Minimum hit target **44×44pt**, enforced with `.contentShape()` when the glyph is smaller.
- Concentric radii: a control inset by `n` inside a surface of radius `R` uses `R - n`. Mismatched
  concentricity is the most common reason custom UI looks amateur.

---

## 5. Liquid Glass — where it is allowed

Glass communicates **"this floats above content."** Using it anywhere else destroys that meaning.

**Allowed:** floating composer · navigation and toolbars · sidebar scrim and controls · overlays and
popovers · contextual floating controls (scroll-to-bottom, stop) · Dynamic Island-adjacent chrome.

**Banned:** behind assistant or user message text · list rows · settings rows · code blocks · diff
views · anything containing a paragraph · nested inside another glass surface.

```swift
// Correct: one glass container, children share it.
GlassEffectContainer(spacing: Space.tight) {
    HStack(spacing: Space.tight) {
        plusButton
        Spacer()
        modeButton
        micButton
        sendButton
    }
}
.glassEffect(.regular.interactive(), in: .rect(cornerRadius: Radius.sheet, style: .continuous))
```

Rules:

- **One `GlassEffectContainer` per floating cluster.** Sibling glass views inside one container blend
  and morph correctly; separate containers produce visible seams and cost more to render.
- `.interactive()` only on things that respond to touch.
- Prefer `.regular` over `.clear`. `.clear` needs a busy backdrop to read as glass; over a chat
  transcript it looks like a rendering bug.
- **Reduce Transparency ⇒ opaque.** Every glass surface has a defined opaque fallback using
  `Palette.canvasRaised` plus a hairline separator. This is a real code path, tested, not an
  afterthought.
- iOS 27's Liquid Glass personalization slider is a *user* setting. We never fight it — no hardcoded
  translucency values, only the system materials.

---

## 6. MotionSystem

One place defines motion. Nothing else calls `.animation` with a literal (spec §3).

```swift
enum MotionSystem {
    // Interruptible springs — no durations, no ease curves.
    static let instant  = Animation.spring(response: 0.22, dampingFraction: 1.0)  // no overshoot
    static let standard = Animation.spring(response: 0.32, dampingFraction: 0.86) // default
    static let gentle   = Animation.spring(response: 0.45, dampingFraction: 0.90) // large surfaces
    static let sidebar  = Animation.spring(response: 0.38, dampingFraction: 0.85) // drawer settle
    static let pop      = Animation.spring(response: 0.28, dampingFraction: 0.68) // slight bounce

    static func reduced(_ a: Animation) -> Animation { .linear(duration: 0.001) }
}
```

Usage:

| Motion | Animation |
|---|---|
| Message appears | `standard`, opacity + 6pt rise. **No scale.** |
| Streaming text | no animation on the text itself — see below |
| Sidebar drag | direct 1:1 to finger, **no animation while dragging** |
| Sidebar settle | `sidebar`, initial velocity from `predictedEndTranslation` |
| Sheet | system presentation, untouched |
| Composer grows | `standard` on height |
| Tool card expands | `standard` height + opacity |
| Button press | `instant` scale to 0.96 |
| Task completes | `pop` on the status glyph only |

**Streaming text is not animated.** Newly arrived characters appear immediately; only the *block* fades
in when it first appears. Animating per-token opacity looks cheap and costs a full layout pass per
token.

**Reduce Motion:** movement and scale are removed; opacity cross-fades survive. Sidebar becomes an
immediate cross-fade with no translation. Nothing becomes non-functional — it becomes still.

Gesture-driven motion must be **interruptible**: a spring settle that cannot be grabbed mid-flight is
the single clearest tell of non-native UI.

---

## 7. HapticManager

Semantic events only. A view never names a haptic *style* — it names what happened (spec §3).

```swift
enum HapticEvent {
    case selection          // segment, mode, list pick
    case reasoningDetent    // reasoning panel snaps to a detent
    case messageSent        // light impact
    case sidebarThreshold   // crossed the open/close threshold — fires once per drag
    case menuOpened         // soft
    case toggle             // switch flip
    case taskCompleted      // success
    case buildPassed        // success
    case buildFailed        // error
    case confirmationNeeded // warning
    case modelLoaded        // subtle success
    case destructiveArmed   // rigid — a destructive confirmation appeared
}
```

**Never fires on:** a token, a scroll event, a progress update, a tool call, a stream start/stop, or
anything the user did not cause.

Implementation: SwiftUI `.sensoryFeedback(_:trigger:)` for everything expressible that way — it
respects system haptic settings and degrades correctly on devices without a Taptic Engine. Core Haptics
only if a genuinely custom curve is needed, which so far it is not.

`sidebarThreshold` is latched: crossing back and forth during one drag must not chatter.

---

## 8. Component inventory

Built once, in `Core/DesignSystem`, used everywhere. A feature that invents its own version of one of
these is a design review failure.

| Component | Notes |
|---|---|
| `GlassCluster` | the only glass wrapper; handles Reduce Transparency fallback |
| `PrimaryButton` / `QuietButton` / `DestructiveButton` | press states, 44pt targets |
| `Chip` | attachments, filters, sources |
| `SectionHeader` | consistent `.title3` + spacing |
| `Row` | settings/list row with optional accessory and full-row hit area |
| `StatusGlyph` | ● running / ○ waiting / ✓ done / ✕ failed — one shape language |
| `MetadataLabel` | `.footnote`, `.monospacedDigit()`, tertiary |
| `MarkdownView` | block-incremental renderer (§11 of ARCHITECTURE) |
| `CodeBlock` | language label, Copy, horizontal scroll, syntax highlight |
| `ProgressCapsule` | determinate/indeterminate, no haptics, no per-frame layout |
| `EmptyState` | glyph + one line + at most one action |
| `PermissionSheet` | the one and only permission surface |

`StatusGlyph` matters more than it looks: Activity, Plan, Tasks and Build all show status, and one
consistent shape language is what makes them feel like one app.

---

## 9. Accessibility contract

Non-negotiable. Checked per screen (spec §76).

- **VoiceOver:** every control labelled; decorative images hidden. A message is one element reading
  role → content → time. Streaming uses a **polite** announcement on block completion, never per
  token — per-token announcements make VoiceOver unusable.
- **Dynamic Type** to `.accessibility5`; horizontal rows reflow vertically above `.xxLarge`.
- **Reduce Motion** → `MotionSystem.reduced`.
- **Reduce Transparency** → opaque fallbacks.
- **Increase Contrast** → opaque separators, promoted text tiers.
- **Differentiate Without Color** → status conveyed by glyph shape, never colour alone (this is why
  `StatusGlyph` is a shape system).
- Tap targets ≥ 44pt. Custom gestures (sidebar) have an accessible alternative — VoiceOver users get
  a button, because an edge-swipe is not discoverable to them.
- Respects system haptic and Reduce Animation settings.

---

## 10. Design Review gate

Run before any UI feature is called done. **Compiling is not done** (spec §81).

**Native**
1. Would this look at home beside Apple's own apps on this OS?
2. Native APIs used where they exist? Nothing hand-rolled that the system provides?
3. Does any part read as a web page?

**Structure**
4. Clear hierarchy — is the primary content obviously primary?
5. Card count: is any card doing nothing? Any card inside a card?
6. Glass only on floating chrome? Any glass behind text?
7. Spacing on the scale? Radii concentric?

**Appearance**
8. OLED dark: true black canvas, no muddy gradients, accent readable?
9. Light mode genuinely designed, not an inversion?

**Interaction**
10. Keyboard: does the composer track it without jumping?
11. Gestures: 1:1 with the finger, velocity-aware, interruptible?
12. Animation: springs, interruptible, explaining origin?
13. Haptics: semantic, and silent on progress?

**Accessibility**
14. Dynamic Type XS and accessibility5?
15. VoiceOver traversal sensible; streaming not chatty?
16. Reduce Motion, Reduce Transparency, Increase Contrast?

**Fit**
17. Smallest supported iPhone and largest?
18. Does this look like it was always part of LCL?

Any "no" is a defect. Fix it or explicitly log it as known debt — never silently ship it.
