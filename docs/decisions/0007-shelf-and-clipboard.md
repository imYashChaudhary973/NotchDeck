# 0007. File Shelf and Clipboard History

- Status: Accepted
- Date: 2026-10-08

## Context

Phase 4 adds the File Shelf (content dropped on the notch, dragged out again later) and clipboard history. Both raise questions the earlier phases didn't:

1. **Drops.** The notch window receives drags, but a feature must not own the notch. Dropped content has to reach a provider without the provider touching the window.
2. **Reaching the notch.** The resting notch is small. A drag resting at the top edge of the screen for about a second opens Mission Control's Spaces bar (noted in Phase 1), so the shelf has to open before the pointer gets there.
3. **Files.** The shelf must not duplicate large files, and referenced files can move, be renamed or be deleted.
4. **Clipboard privacy.** macOS has no clipboard-change notification. Reading another app's copy is privacy-sensitive, and from macOS 15.4 it can show a system prompt ("Paste from Other Apps").
5. **Presentation.** Both features show lists of items that can be clicked, given a context menu and dragged out.

## Decision

### Drops go through the Activity Engine

- `ActivityProvider` gains `acceptsDrops` and `handleDrop(_:) -> Bool` (defaults: `false`). `ActivityEngine.acceptsDrops` is observable and true while a registered provider accepts drops. `ActivityEngine.routeDrop(_:)` offers a `NotchDrop` to those providers in registration order; the first one that returns `true` takes it.
- `NotchController` stays the only type that touches the window. It accepts a drag only if `engine.acceptsDrops`, the drag carries a readable type (`NotchDrop.canRead`) and the drag isn't NotchDeck's own (dragging an item out of the shelf passes over the notch). On drop it reads the drag pasteboard while it is still valid (`NotchDrop.items(from:)`), picks the drop tile under the pointer (`ShelfDropTargeting`: Shelf, Copy, AirDrop; anywhere else counts as Shelf), routes the drop and returns the state machine to where it was. A drop nobody takes returns to its source.
- `NotchDrop.items(from:)` reads the most specific kind only: file URLs, then file promises, then PNG/JPEG/TIFF/PDF data, then web links, then text. Only `http`/`https` links are kept. Size limits apply (100 items, 1 M characters, 100 MB of data).

### The shelf opens as a drag approaches

- `DragApproachMonitor` watches other apps' left-button mouse events with `NSEvent.addGlobalMonitorForEvents` (mouse monitors need no permission and receive nothing while the mouse is still). It runs only while a provider accepts drops and "Open the shelf as a drag approaches the notch" is on.
- `DragApproachTracker` (pure, unit tested) decides. A drag-and-drop session writes the drag pasteboard, so a change count that differs from the one at mouse-down means content is being dragged, not a window or a text selection. When such a drag enters the activation region (the notch plus 90 pt each side and 44 pt below) and carries a readable type (checked once per drag), the shelf opens. Leaving the open shelf or releasing the button closes it, unless AppKit is delivering the drag to the notch itself (a 300 ms grace lets a drop arrive first).

### File Shelf

- `ShelfProvider` (source `shelf`) publishes a `.commandCenter` activity (priority 25, above paused music) with the items, and a short confirmation on the notch after a drop (Time Sensitive, expires after 2.5 s).
- `ShelfCollection` (pure) holds the rules: newest first, dropping the same file/link/text again moves it to the front (keeping its pin, extending but never shortening its time), at most 30 items (the oldest unpinned make room), expiry, clearing unpinned items.
- **Retention**: each item expires after the lifetime setting (1 hour, or the end of the day), can be changed per item (Keep for 1 Hour, Keep Until Tonight), or is pinned (kept until removed). The provider wakes once, at the next expiry, on the continuous clock; nothing polls.
- **Files are referenced, not copied.** A dropped file or folder is stored as a bookmark (`ShelfFileReference`), validated when dropped and resolved when used, so it is found again after a move or rename. A missing file is shown dimmed as "Missing" and can only be removed. Only content without a file of its own is written: received file promises (Photos, Mail attachments) and dropped image/PDF data, each in its own directory under `~/Library/Application Support/NotchDeck/Shelf/Items/`, deleted with its item. Orphaned directories are deleted at start.
- **Actions**: click (Quick Look for files, open for links, copy for text), drag out (files, links and text, via `NSItemProvider`), and a context menu with Quick Look, Open, Copy, Show in Finder, Share (system share services), retention choices and Remove. The Copy tile writes the drop to the clipboard and the AirDrop tile opens AirDrop (`NSSharingService`), neither keeping it.
- Thumbnails come from Quick Look (`QLThumbnailGenerator`, 48 pt at 2×), made off the main thread only after the shelf has been on screen, never from the full image.
- Turning the shelf off removes every item.

### Clipboard history

- `ClipboardProvider` (source `clipboard`) is **off by default**. While on, not paused and the screens are awake, it reads `NSPasteboard.changeCount` once a second (1 s timer, 0.5 s tolerance). The change count never reveals contents and never prompts. Contents are read only after a change. Polling stops while paused, while the screens sleep and while another user session is active.
- **Never read**: content marked concealed, transient or auto-generated (nspasteboard.org markers and common app-specific ones), copies made while a password manager is frontmost, copies from apps the user excluded, and NotchDeck's own writes. What was on the clipboard before the feature started isn't read either, except once right after the user turns the feature on, so the macOS prompt (if any) appears in context.
- **Access**: on macOS 15.4+, `NSPasteboard.accessBehavior` is checked before reading. If macOS asks each time or denies, NotchDeck doesn't read and shows a row with Open Settings… instead.
- `ClipboardCapture` (pure) classifies a copy: files (paths only), then text (recognized as a color, a single web link, code when copied from an editor or terminal, or plain text with small RTF kept), then an image, then a URL. Text over 100,000 characters, RTF over 256 KB and images over 20 MB aren't kept.
- `ClipboardHistory` (pure) holds the rules: deduplication by SHA-256 fingerprint (copying again moves the entry to the top, keeping its pin), a maximum number of unpinned entries (25/50/100/200), a retention period for unpinned entries (1/7/30 days or never), pinning, deleting, clearing (unpinned, or everything) and search (every word, ignoring case and diacritics).
- Stored in `~/Library/Application Support/NotchDeck/Clipboard/` (`history.json` plus an `Images` directory), written a second after the last change. Images are hashed and thumbnailed (96 px) off the main thread.
- The command center lists the 5 most recent entries (pinned first) with Search History, Pause/Resume and Clear Unpinned. The History window searches every entry.

### Presentation

- A new content style, `ActivityContent.collection(CollectionContent)`, describes items (title, subtitle, symbol, a small thumbnail, a color swatch, pinned, unavailable, monospaced, a drag-out `payload`, a primary action and context-menu actions) in a `tiles` (shelf) or `rows` (clipboard) layout. Item actions are encoded as `"action:itemID"` (`CollectionContent.actionID(_:item:)`), so the existing `perform(actionID:on:)` path is reused.
- Horizontal scrolling over the notch now reaches the content (the shelf's tile strip), and a vertical scroll no provider handles does too.
- A new activity kind, `shelf`, has its own command-center tab.

## Alternatives Considered

- **Letting the shelf register its own drag destination or window.** Simpler, but it breaks the rule that features don't own the notch.
- **Only accepting drags that reach the notch itself.** No mouse monitoring, but the target is small and the Spaces bar opens if the drag rests at the top edge.
- **Copying dropped files into the app's storage.** Robust against moves, but it duplicates large files. Bookmarks find moved files; deleted ones are shown as missing.
- **Security-scoped bookmarks.** The app isn't sandboxed yet ([ADR 0003](0003-app-runtime-configuration.md)). The references are plain bookmarks; when the sandbox is enabled they become security-scoped with the same storage format.
- **Polling the clipboard faster, or reading contents on every check.** Faster capture, but more wake-ups, and reading contents can show the privacy prompt. Reading the change count once a second is the lowest cost that still feels immediate.
- **Clipboard history on by default.** More discoverable, but it keeps what the user copies without asking.

## Consequences

- Idle cost: the shelf costs nothing when idle (one wake-up at the next expiry, mouse events only while the mouse moves). Clipboard history, when on, wakes once a second; turning it off or pausing it stops that.
- A copy made and replaced within the same second is missed. Copies made while paused, asleep or before the feature started are never recorded.
- The "Paste from Other Apps" prompt can appear once, right after the user turns clipboard history on. If the user chooses "Ask", NotchDeck stops reading until access is allowed.
- New stored data (shelf items, clipboard history) is documented in `PRIVACY.md`. Clearing everything is available in Settings even while the feature is off.
- The prewarmer samples include both collection layouts; `NotchPrewarmerTests` enforces this.
