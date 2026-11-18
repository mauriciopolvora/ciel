# Ciel design system

Ciel opens as one empty black input box. There is no visible text or symbol until the user types. The caret shows that the input has focus. Keep the cloud painting in the app icon. Use a monochrome interface inside the app.

## Tokens

`Sources/Ciel/DesignSystem.swift` owns the visual tokens. Every interface uses dark appearance, including Settings, Keyboard Guide, Window Shortcuts, and status messages. The palette remains black when macOS uses light appearance. Surfaces are opaque so the desktop cannot tint them blue.

| Role | Gray value | Use |
| --- | --- | --- |
| Surface | 0.035 | Black launcher and settings background |
| Group | 0.075 | Settings groups and switch tracks |
| Selection | 0.14 | Hovered result and selected input text |
| Border | 0.30 | Quiet surface boundaries. `Theme.hairline` draws it at 35% for group outlines and row dividers, or fully under Increase Contrast |
| Secondary | 0.62 | Descriptions and key hints |
| Accent | 0.92 | Selected result fill, actions and shortcut labels |
| Text | 0.94 | Search input and result names |
| Guide | 1.0 | Placement guide lines during a drag |
| Selected text | 0.07 | Result name on the selected row |
| Selected secondary | 0.36 | Key hint, app icon tint and window symbol on the selected row (5.6:1 on Accent) |

These colors have equal red, green, and blue values. App icons retain their source colors. Errors use system red with an explicit message. Enabled access uses white text. Settings switches use gray tracks and white thumbs, with native button keyboard and accessibility behavior.

## Layout and type

- Launcher width: 640 points. Empty launcher height: 68 points.
- Input starts 24 points from the left edge. It has no placeholder or search icon.
- A trimmed empty query shows no results, category button, or empty-result message.
- Typing reveals result titles, app icons or window symbols, and the category control.
- Clearing the query restores the empty input immediately. Whitespace and catalog refreshes keep it empty.
- Result rows: 44 points. One result produces a 120-point panel. Show up to seven full rows before scrolling.
- The selected row is a near-white fill with near-black text. Under Increase Contrast it also gets a border ring. Hover uses Selection at 70%.
- Panel radius: 16 points. Group radius: 10 points. Row radius: 8 points.
- Use the macOS system font. Input: 24 points. Results: 15 points medium. Key hints: 12 points medium. No matches: 15 points medium over a 13-point line. Setting labels: 13 points. Descriptions: 12 points.
- Settings use a text header and neutral controls. Keep the cloud artwork outside the daily interface.

## Settings

Settings and onboarding use two columns. `Sources/Ciel/SettingsLayout.swift` draws them.

- Names sit in a right-aligned column in secondary gray at 13 points that ends at 172 points. Controls start at 188 points and end by 444 points.
- Lines are 36 points. A name and its controls share a first baseline.
- Hairline rules inset 36 points separate Launcher shortcut, General, Accessibility and Dictation.
- The launcher shortcut is a menu: ⌘Space (marked Replaces Spotlight), ⌃⌥Space and Record Shortcut…. Beside it, a 12-point caption says Replaces Spotlight or Used by Spotlight.
- A launcher shortcut that Spotlight holds opens System Settings at Keyboard Shortcuts with Spotlight selected. A 300-point floating card sits under the System Settings window while System Settings is frontmost. Its top is the row to change: a checkbox, the action name, and the shortcut right-aligned in secondary gray, on a Group fill with the row radius. Below it, Turn off and the action name at 13 points medium, over In Keyboard Shortcuts, under Spotlight. The checkbox is pressed and unticks in a 2.4-second loop. It stays ticked and still under Reduce Motion or with animations off. When Spotlight lets go, the box stays unticked, the card says the shortcut now opens Ciel for 1.6 seconds, then closes.
- Each switch has its name as a clickable label to its right. Check for Updates… sits under Automatically check for updates, and is off while Sparkle cannot check.
- Shortcut recorders and action buttons are 120 points wide. A status sits right before its button in 12-point tabular digits. Ready and allowed use text white, waiting states use secondary gray, and a failure uses system red with its message.
- Footer buttons are standard push buttons, 20 points in from each side.

## Placement

Drag the empty input or the search surface margins. Typed text keeps normal selection behavior. Guides appear only during a drag. They divide the usable display at 25%, 50%, and 75% on both axes. Nearby guides brighten within 24 points. On release, the input center snaps to those guides. Hold Option to disable snapping. The guides disappear on release.

Dragging uses [AppKit event tracking](https://developer.apple.com/documentation/appkit/nswindow/trackevents(matching:timeout:mode:handler:)) for the launcher’s own mouse events. The tracking stops on release. Read the pointer position from each mouse event so a later cursor movement cannot change the drop position. It needs no global input monitor or idle timer.

The overlay ignores mouse events and stays behind the launcher. Its lines use white at 18% opacity, or 70% for an active guide. It does not dim the desktop or display labels.

Save positions by display UUID. Keep the input’s top edge as the anchor. Store its relative position so a resolution change keeps it visible. Expanding results does not overwrite the saved placement. Clamp the visible panel to the usable screen. A display without a saved position uses the original default placement.

## Interaction

Opening, closing, search, selection, category switching, and panel resizing are immediate. Do not animate keyboard actions. Empty Return and Command-number actions do nothing. Tab and Shift–Tab keep their category behavior without adding visible content to an empty launcher.

Pointer hover uses a 120 ms opacity transition and the curve `(0.23, 1, 0.32, 1)`. Status messages use short opacity fades. Dictation shows two black capsules at the bottom center of the screen with the pointer. The lower one is a waveform: its bars follow the microphone level with a fast rise and a slower fall, the newest level in the middle flowing out to the edges, and a slow ripple while Ciel transcribes. The upper one holds the live transcript, the settled words in text gray and the guesses after them in secondary gray. Each line is centered. It springs out of the waveform once words arrive, widens to fit the first line up to 360 pt, then grows a line at a time up to three lines. Past that, new lines push the text up and older lines fade out under the top edge. Every change uses an interruptible critically damped spring, driven by the display link. Reduce Motion and the app animation switch make each change instant, keep the bars on the live level without the flow, and hold them still while Ciel transcribes. Increase Contrast strengthens boundaries. All surfaces already satisfy Reduce Transparency by being opaque.

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
| Three unlabeled Settings cards | General, Permissions and Dictation sections with headers and row dividers | Show what each group is for at a glance |
| Status under the label, button centered beside both lines | Status and its action on one line, on a shared trailing edge | Read the state and the fix together |
| Gray inline footer buttons | Standard push buttons | Stop the footer from looking disabled |
| Grouped Settings rows with section headers | Two columns, names on the left and controls on the right | Picked by the operator from three prototypes |
| Gray selected row with a faint ring, 21-point input, divider under the input | Near-white selected row, 24-point input, no divider | Picked by the operator from three prototypes |
| Left-aligned transcript lines | Centered transcript lines | Keep the text on the pill's center line as it grows |
| Replacing Spotlight opened the Keyboard pane and left the user to find Spotlight | Keyboard Shortcuts opens at Spotlight, and a card under System Settings shows the box to untick | Land the user on the exact checkbox and say when Ciel has the shortcut |

## Validation

Check the initial launcher, typing, clearing, whitespace, empty execution, and catalog refresh. Check native text selection and keyboard shortcuts. Inspect launcher, Settings, and guide captures under both system appearances. Check switch keyboard and accessibility behavior. Keep the window-control grant separate from interface checks.
