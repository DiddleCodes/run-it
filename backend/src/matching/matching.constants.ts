export const MATCHING_QUEUE = 'matching';
export const REBROADCAST_JOB = 'rebroadcast';
export const ESCALATE_JOB = 'escalate';

// BullMQ rejects a custom job id containing ':' (it uses that internally
// as a Redis key separator) — found live, not in the mocked unit tests,
// since jest never exercises BullMQ's own real Job.create validation.
export function rebroadcastJobId(orderId: string): string {
  return `${REBROADCAST_JOB}-${orderId}`;
}

export function escalateJobId(orderId: string): string {
  return `${ESCALATE_JOB}-${orderId}`;
}
