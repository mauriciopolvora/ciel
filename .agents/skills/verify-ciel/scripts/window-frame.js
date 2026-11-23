// Prints the frame of a named window of an app and whether it fills the left half of the main screen's visible area.
ObjC.import("AppKit");
function run(argv) {
    const [appName, windowName] = argv;
    const windows = Application("System Events").processes.byName(appName).windows.whose({ name: windowName });
    if (windows.length === 0) throw new Error(appName + " has no window named " + windowName);
    const [x, y] = windows[0].position();
    const [width, height] = windows[0].size();
    const screen = $.NSScreen.screens.objectAtIndex(0).frame;
    const visible = $.NSScreen.mainScreen.visibleFrame;
    const top = screen.size.height - (visible.origin.y + visible.size.height);
    const near = (a, b) => Math.abs(a - b) <= 3;
    const leftHalf =
        near(x, visible.origin.x) && near(y, top) && near(width, visible.size.width / 2) && near(height, visible.size.height);
    return [
        "window " + [x, y, width, height].join(" "),
        "visible " + [visible.origin.x, top, visible.size.width, visible.size.height].join(" "),
        "left-half " + (leftHalf ? "yes" : "no"),
    ].join("\n");
}
