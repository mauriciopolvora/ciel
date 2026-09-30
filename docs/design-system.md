# Ciel design system

Ciel opens as one empty black input box. There is no visible text or symbol until the user types. The caret shows that the input has focus. Keep the cloud painting in the app icon. Use a monochrome interface inside the app.

## Tokens

`Sources/Ciel/DesignSystem.swift` owns the visual tokens. Every interface uses dark appearance, including Settings, Keyboard Guide, Window Shortcuts, and status messages. The palette remains black when macOS uses light appearance. Surfaces are opaque so the desktop cannot tint them blue.

| Role | Gray value | Use |
| --- | --- | --- |
| Surface | 0.035 | Black launcher and settings background |
| Group | 0.075 | Settings groups and switch tracks |
| Selection | 0.14 | Selected result and selected input text |
| Border | 0.30 | Quiet surface boundaries |
| Secondary | 0.62 | Descriptions and key hints |
| Accent | 0.92 | Actions and shortcut labels |
| Text | 0.94 | Search input and result names |

These colors have equal red, green, and blue values. App icons retain their source colors. Errors use system red with an explicit message. Enabled access uses white text. Settings switches use gray tracks and white thumbs, with native button keyboard and accessibility behavior.

## Layout and type

- Launcher width: 640 points. Empty launcher height: 68 points.
- Input starts 24 points from the left edge. It has no placeholder or search icon.
- A trimmed empty query shows no results, category button, divider, or empty-result message.
- Typing reveals result titles, app icons or window symbols, and the category control.
- Clearing the query restores the empty input immediately. Whitespace and catalog refreshes keep it empty.
- Result rows: 44 points. One result produces a 120-point panel. Show up to seven full rows before scrolling.
- Panel radius: 16 points. Group radius: 10 points. Row radius: 8 points.
- Use the macOS system font. Input: 21 points. Results: 15 points. Setting labels: 14 points. Descriptions: 12 points.
- Settings use a text header and neutral controls. Keep the cloud artwork outside the daily interface.

## Placement

Drag the empty input or the search surface margins. Typed text keeps normal selection behavior. Guides appear only during a drag. They divide the usable display at 25%, 50%, and 75% on both axes. Nearby guides brighten within 24 points. On release, the input center snaps to those guides. Hold Option to disable snapping. The guides disappear on release.

Dragging uses [AppKit event tracking](https://developer.apple.com/documentation/appkit/nswindow/trackevents(matching:timeout:mode:handler:)) for the launcher’s own mouse events. The tracking stops on release. Read the pointer position from each mouse event so a later cursor movement cannot change the drop position. It needs no global input monitor or idle timer.

The overlay ignores mouse events and stays behind the launcher. Its lines use white at 18% opacity, or 70% for an active guide. It does not dim the desktop or display labels.

Save positions by display UUID. Keep the input’s top edge as the anchor. Store its relative position so a resolution change keeps it visible. Expanding results does not overwrite the saved placement. Clamp the visible panel to the usable screen. A display without a saved position uses the original default placement.

## Interaction

Opening, closing, search, selection, category switching, and panel resizing are immediate. Do not animate keyboard actions. Empty Return and Command-number actions do nothing. Tab and Shift–Tab keep their category behavior without adding visible content to an empty launcher.

Pointer hover uses a 120 ms opacity transition and the curve `(0.23, 1, 0.32, 1)`. Status messages use short opacity fades. Reduce Motion and the app animation switch disable these effects. Increase Contrast strengthens boundaries. All surfaces already satisfy Reduce Transparency by being opaque.

Use native text editing, scrolling, focus behavior, and accessibility labels. The input retains its spoken search label even though it has no visible placeholder. Full result names remain available to accessibility and tooltips.

## Design review

Applied [Emil Kowalski’s design engineering skill](https://github.com/emilkowalski/skills/tree/main/skills/emil-design-eng). Keep frequent keyboard actions immediate and use motion only for useful pointer feedback.

| Before | After | Why |
| --- | --- | --- |
| Suggested results on opening | Empty focused input | Start with only the user’s query |
| Search icon, placeholder, and category label while empty | Caret only | Remove visible text and symbols before typing |
| Blue surface, selection, and accent | Black surface, gray selection, white actions | Follow the requested monochrome direction |
| Desktop-tinted material | Opaque black surface | Keep the color stable on every desktop |
| Appearance follows macOS | Dark app appearance in both system modes | Keep the black interface consistent |
| Painted icon inside Settings | Plain text header | Keep Settings aligned with the minimal interface |
| Fixed launcher position on every open | Drag placement, temporary guides, and saved positions | Let the user arrange the input |
| Unreadable credits in the standard About panel | Black About window with explicit white and gray text | Keep all description and credit text readable |
| Menu bar icon always visible | Saved Show menu bar icon switch | Let the user hide the icon and restore it through launcher Settings |
| Wait after each window resize and move | Send the frame updates together and verify the final frame | Remove Ciel's visible pause between resize and move |
| Native accent-colored switches | Neutral switches with native button behavior | Remove blue from preference controls |

## Validation

Check the initial launcher, typing, clearing, whitespace, empty execution, and catalog refresh. Check native text selection and keyboard shortcuts. Inspect launcher, Settings, and guide captures under both system appearances. Check switch keyboard and accessibility behavior. Keep the window-control grant separate from interface checks.
