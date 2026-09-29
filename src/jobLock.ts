/**
 * Tracks in-flight print jobs so the self-updater can wait for the
 * printer to go idle before it swaps files (spec: "Do not update the
 * agent while it is in the middle of a print job").
 */
let inFlight = 0;

export function beginJob(): void {
  inFlight++;
}

export function endJob(): void {
  inFlight = Math.max(0, inFlight - 1);
}

export function isBusy(): boolean {
  return inFlight > 0;
}
