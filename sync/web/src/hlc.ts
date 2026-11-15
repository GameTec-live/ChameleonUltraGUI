/**
 * Hybrid logical clock, as in the app's `hlc.dart`: timestamps sort
 * lexicographically as `<ms, 15 digits>-<counter, 6 digits>-<node>`.
 */
export class Hlc {
  private ms = 0;
  private counter = 0;

  constructor(private readonly node: string) {}

  /** A timestamp greater than every one issued or observed before. */
  next(): string {
    const wall = Date.now();
    if (wall > this.ms) {
      this.ms = wall;
      this.counter = 0;
    } else {
      this.counter++;
    }
    return `${String(this.ms).padStart(15, "0")}-${String(this.counter).padStart(6, "0")}-${this.node}`;
  }

  /** Merges a remote timestamp so later local edits sort after it. */
  observe(timestamp: string) {
    const [ms = 0, counter = 0] = timestamp.split("-", 2).map(Number);
    if (ms > this.ms || (ms === this.ms && counter > this.counter)) {
      this.ms = ms;
      this.counter = counter;
    }
  }
}

/** Wall-clock time of a timestamp, for display. */
export const hlcDate = (timestamp: string) => {
  const ms = Number(timestamp.split("-", 1)[0]);
  return ms ? new Date(ms) : null;
};
