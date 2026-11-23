// Prints the frame of a named window of an app, the visible area of the screen that holds its center, and whether it fills the left half of that area.
ObjC.import("AppKit");
function run(argv) {
    const [appName, windowName] = argv;
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
    const centerX = x + width / 2;
    const centerY = y + height / 2;
    let visible = null;
    for (let index = 0; index < screens.count; index++) {
        const screen = screens.objectAtIndex(index);
        const frame = topLeft(screen.frame);
        const inside =
            centerX >= frame.x && centerX < frame.x + frame.width && centerY >= frame.y && centerY < frame.y + frame.height;
        if (inside) visible = topLeft(screen.visibleFrame);
    }
    if (visible === null) throw new Error("no screen holds the center of the window " + windowName);
    const near = (a, b) => Math.abs(a - b) <= 3;
    const leftHalf =
        near(x, visible.x) && near(y, visible.y) && near(width, visible.width / 2) && near(height, visible.height);
    return [
        "window " + [x, y, width, height].join(" "),
        "visible " + [visible.x, visible.y, visible.width, visible.height].join(" "),
        "left-half " + (leftHalf ? "yes" : "no"),
    ].join("\n");
}
