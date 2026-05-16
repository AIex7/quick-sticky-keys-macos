# StickyKeys

A tiny macOS menu-bar app that implements its own simple sticky modifier behavior.

When Command, Shift, Option, or Control is pressed, the app keeps that modifier logically active for one second. If another modifier is pressed while sticky modifiers are still active, the active set is extended to the longest expiration time so combinations can be built naturally.

## Build

```sh
swift build
```

Run the debug build:

```sh
.build/debug/StickyKeys
```

Create a clickable app bundle:

```sh
sh Scripts/build-app.sh
open .build/StickyKeys.app
```

The app requires Accessibility permission because it observes and rewrites keyboard events. Use the menu-bar item to open the correct System Settings pane, enable the app or terminal you launched it from, then relaunch.

## Notes

- This intentionally handles only Command, Shift, Option, and Control.
- It modifies outgoing key event flags with a `CGEventTap`; it does not enable or depend on macOS built-in Sticky Keys.
