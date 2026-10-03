# 0004. Command Center Presentation

- Status: Accepted
- Date: 2026-10-02

## Context

The first expanded design showed one activity in detail plus a short list. The product direction (reference designs) is a larger notch with distinct sections: a Now Playing card with artwork and transport controls, a column of widgets (Keep Awake toggle, upcoming meeting with Join, CPU and memory bars), a volume HUD, an approval-style agent peek and shelf drop tiles.

The architectural rule still holds: features publish activities, the notch decides what is shown. The redesign must not let features draw their own UI.

## Decision

- **Activity content styles.** `ActivityPresentation.content` is one of `.standard`, `.media`, `.level`, `.metric`, `.toggle`. Providers describe data (playback position, a 0…1 level, a toggle state); the notch owns every view. Interactive controls invoke action IDs routed to the owning provider.
- **Command center layout** is derived purely from the resolution (`CommandCenterLayout`): Overview + per-kind tabs, the section's first activity on a featured card, the next four in a widget column. Priority continues to decide prominence.
- **Peek extras:** `statusText` (short status beside the notch) and `revealsOnUpdate` (HUD-style activities reveal the notch on each update).
- **Sizes:** expanded 600 pt wide with content-fitted height (56–300 pt); peek 420 pt; shelf 600 × 156 pt; Live Activity ears 52 pt each, with a 16 pt glyph and 13 pt accessory inset 12 pt from the outer edges.
- **Edge-pinned rows.** The compact activity and Peek's top row pin their content to the outer edges as overlays. While the surface springs open, content rides the edges out of the notch instead of being re-laid out (and shifting) every frame.
- **Warm-up.** SwiftUI pays a one-time cost the first time a view is drawn (measured: expanded ≈ 36 ms, Live Activity ≈ 12 ms, Shelf ≈ 9 ms — dropped frames at the start of the first animation). One second after launch, `NotchPrewarmer` draws every state off-screen with sample activities covering each content style, in a private engine that never reaches the notch. First renders drop to ≈ 2 ms (Live, Peek), ≈ 4 ms (Shelf) and ≈ 10 ms (Expanded; the rest is per hosting view and can't be moved). Measured content-height corrections animate instead of snapping.
- The real features behind these styles stay in their roadmap phases; Phase 1 drives them from the debug provider.

## Alternatives Considered

- **Features supplying SwiftUI views.** Most flexible, but breaks the core rule and makes features responsible for notch layout and animation.
- **A fixed dashboard with a slot per feature.** Shows empty slots for disabled features and ignores priority — the "dashboard of generic cards" the plan warns against.

## Consequences

- New presentation needs (e.g. a timer ring) are added as content styles centrally, not per feature. Add a matching warm-up sample; `NotchPrewarmerTests` fails until you do.
- The warm-up costs ≈ 0.6 s of spaced-out main-thread work once per launch; nothing runs afterwards.
- Media playback progress ticks once per second only while the expanded card is visible and playing; nothing ticks when collapsed.
