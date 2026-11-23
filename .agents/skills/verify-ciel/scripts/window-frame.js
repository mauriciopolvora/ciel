// Prints the frame of a named window of an app, the screen it overlaps most (Ciel's rule), that screen's visible area, and whether the window fills the left half of it.
// A third argument names the screen index to compare with, so a window that moved to another display never passes.
ObjC.import("AppKit");
function run(argv) {
    const [appName, windowName, expected] = argv;
    const windows = Application("System Events").processes.byName(appName).windows.whose({ name: windowName });
    if (windows.length === 0) throw new Error(appName + " has no window named " + windowName);
    const [x, y] = windows[0].position();
    const [width, height] = windows[0].size();
    const screens = $.NSScreen.screens;
    const primaryHeight = screens.objectAtIndex(0).frame.size.height;
    const topLeft = (rect) => ({
        x: rect.origin.x,
        y: primaryHeight - (rect.origin.y + rect.size.height),
        width: rect.size.width,
        height: rect.size.height,
    });
    const overlap = (frame) =>
        Math.max(0, Math.min(x + width, frame.x + frame.width) - Math.max(x, frame.x)) *
        Math.max(0, Math.min(y + height, frame.y + frame.height) - Math.max(y, frame.y));
    let best = -1;
    let bestArea = 0;
    for (let index = 0; index < screens.count; index++) {
        const area = overlap(topLeft(screens.objectAtIndex(index).frame));
        if (area > bestArea) {
            best = index;
            bestArea = area;
        }
    }
    if (best < 0) throw new Error("the window " + windowName + " is on no screen");
    const compare = expected === undefined ? best : Number(expected);
    if (!(compare >= 0 && compare < screens.count)) throw new Error("no screen with index " + expected);
    const visible = topLeft(screens.objectAtIndex(compare).visibleFrame);
    const near = (a, b) => Math.abs(a - b) <= 3;
    const leftHalf =
        best === compare &&
        near(x, visible.x) &&
        near(y, visible.y) &&
        near(width, visible.width / 2) &&
        near(height, visible.height);
    return [
        "window " + [x, y, width, height].join(" "),
        "screen " + best,
        "visible " + [visible.x, visible.y, visible.width, visible.height].join(" "),
        "left-half " + (leftHalf ? "yes" : "no"),
    ].join("\n");
}
