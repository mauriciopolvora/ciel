declare class Lenis {
  constructor(options: {
    duration: number;
    easing: (time: number) => number;
    autoRaf: boolean;
    anchors: boolean;
  });
  start(): void;
  stop(): void;
  scrollTo(target: number): void;
}
