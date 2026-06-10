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

Run without creating a menu-bar item:

```sh
.build/debug/StickyKeys --hide-menu-bar
```

Limit sticky behavior to specific modifiers:

```sh
.build/debug/StickyKeys --shift
.build/debug/StickyKeys --command --option
```

Supported modifier flags are `--shift`, `--control`, `--option`, and `--command`.
If none are provided, all four modifiers are sticky. Each flag also has a
`--sticky-...` alias, such as `--sticky-shift`.

Create a clickable app bundle:

```sh
sh Scripts/build-app.sh
open .build/StickyKeys.app
```

Pass arguments to the app bundle with `open --args`:

```sh
open .build/StickyKeys.app --args --hide-menu-bar --command --option
```

The app requires Accessibility permission because it observes and rewrites keyboard events. Use the menu-bar item to open the correct System Settings pane, enable the app or terminal you launched it from, then relaunch.

## Notes

- This intentionally handles only Command, Shift, Option, and Control.
- It modifies outgoing key event flags with a `CGEventTap`; it does not enable or depend on macOS built-in Sticky Keys.
