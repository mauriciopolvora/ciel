ObjC.import("AppKit");
const near = (a, b) => Math.abs(a - b) <= 3;
function run(argv) {
    const [appName, windowName, expected] = argv;
    const windows = Application("System Events").processes.byName(appName).windows.whose({ name: windowName });
    if (windows.length === 0) throw new Error(appName + " has no window named " + windowName);
    const [x, y] = windows[0].position();
    const [width, height] = windows[0].size();
    const nsScreens = $.NSScreen.screens;
    const primaryHeight = nsScreens.objectAtIndex(0).frame.size.height;
    const topLeft = (rect) => ({
        x: rect.origin.x,
        y: primaryHeight - (rect.origin.y + rect.size.height),
        width: rect.size.width,
        height: rect.size.height,
    });
    const screens = [];
    for (let index = 0; index < nsScreens.count; index++) {
        const screen = nsScreens.objectAtIndex(index);
        screens.push({ full: topLeft(screen.frame), visible: topLeft(screen.visibleFrame) });
    }
    screens.sort((a, b) => (a.full.x === b.full.x ? a.full.y - b.full.y : a.full.x - b.full.x));
    const overlap = (frame) =>
        Math.max(0, Math.min(x + width, frame.x + frame.width) - Math.max(x, frame.x)) *
        Math.max(0, Math.min(y + height, frame.y + frame.height) - Math.max(y, frame.y));
    const distance = (frame) =>
        Math.hypot(x + width / 2 - (frame.x + frame.width / 2), y + height / 2 - (frame.y + frame.height / 2));
    let best = 0;
    for (let index = 1; index < screens.length; index++) {
        const area = overlap(screens[index].full);
        const bestArea = overlap(screens[best].full);
        if (area > bestArea || (area === bestArea && distance(screens[index].full) < distance(screens[best].full))) best = index;
    }
    const compare = expected === undefined ? best : Number(expected);
    if (!(compare >= 0 && compare < screens.length)) throw new Error("no screen with index " + expected);
    const visible = screens[compare].visible;
    const fills = (share) =>
        best === compare &&
        near(x, visible.x) &&
        near(y, visible.y) &&
        near(width, visible.width * share) &&
        near(height, visible.height);
    return [
        "window " + [x, y, width, height].join(" "),
        "screen " + best,
        "visible " + [visible.x, visible.y, visible.width, visible.height].join(" "),
        "left-half " + (fills(0.5) ? "yes" : "no"),
        "maximized " + (fills(1) ? "yes" : "no"),
    ].join("\n");
}
