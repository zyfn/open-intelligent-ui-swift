/** Error reporting must also accept thrown values with no usable conversion. */
export function normalizeError(cause: unknown): Error {
  try { return cause instanceof Error ? cause : new Error(String(cause)); }
  catch { return new Error('Error details could not be read'); }
}
