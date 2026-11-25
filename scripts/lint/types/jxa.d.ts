interface JxaElement {
  [property: string]: () => string | number | boolean | null;
}

interface JxaWindow {
  position(): [number, number];
  size(): [number, number];
}

interface JxaWindows {
  readonly length: number;
  readonly 0: JxaWindow;
  whose(filter: { name: string }): JxaWindows;
}

interface JxaProcess {
  windows: JxaWindows & (() => Array<JxaElement>);
}

interface JxaProcesses {
  readonly length: number;
  readonly 0: JxaProcess;
  byName(name: string): JxaProcess;
  whose(filter: { unixId: number }): JxaProcesses;
}

declare function Application(name: "System Events"): { processes: JxaProcesses };

interface NSRect {
  origin: { x: number; y: number };
  size: { width: number; height: number };
}

interface NSScreen {
  frame: NSRect;
  visibleFrame: NSRect;
}

declare const ObjC: { import(framework: "AppKit"): void };

declare const $: {
  NSScreen: { screens: { count: number; objectAtIndex(index: number): NSScreen } };
};
