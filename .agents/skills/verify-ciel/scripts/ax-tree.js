function run(argv) {
    const pid = Number(argv[0]);
    const processes = Application("System Events").processes.whose({ unixId: pid });
    if (processes.length === 0) throw new Error("no process with pid " + pid);
    const lines = [];
    const read = (element, property) => {
        try {
            const value = element[property]();
            return value === null || value === undefined ? "" : String(value);
        } catch (error) {
            return "";
        }
    };
    const walk = (element, depth) => {
        const fields = [read(element, "role") || "?"];
        for (const property of ["title", "description", "value"]) {
            const value = read(element, property);
            if (value && value !== "missing value") fields.push(property + '="' + value.replace(/\n/g, " ") + '"');
        }
        lines.push("  ".repeat(depth) + fields.join(" "));
        let children = [];
        try {
            children = element.uiElements();
        } catch (error) {
            lines.push("  ".repeat(depth + 1) + "AXReadError");
        }
        for (const child of children) walk(child, depth + 1);
    };
    for (const window of processes[0].windows()) walk(window, 0);
    return lines.join("\n");
}
