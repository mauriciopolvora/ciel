function run(argv) {
    const [pid, windowTitle, buttonTitle] = argv;
    const processes = Application("System Events").processes.whose({ unixId: Number(pid) });
    if (processes.length === 0) throw new Error("no process with pid " + pid);
    const windows = processes[0].windows.whose({ name: windowTitle });
    if (windows.length === 0) throw new Error("no window titled " + windowTitle);
    const read = (element, property) => {
        try {
            return element[property]();
        } catch (error) {
            return "";
        }
    };
    const find = (element) => {
        let children = [];
        try {
            children = element.uiElements();
        } catch (error) {
            return null;
        }
        for (const child of children) {
            if (read(child, "role") === "AXButton" && read(child, "title") === buttonTitle) return child;
            const found = find(child);
            if (found) return found;
        }
        return null;
    };
    const button = find(windows[0]);
    if (!button) throw new Error(windowTitle + " has no button titled " + buttonTitle);
    button.actions.byName("AXPress").perform();
    return "pressed " + buttonTitle;
}
