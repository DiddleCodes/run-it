import { randomInt } from 'crypto';

/**
 * A short, human-enterable numeric code — never derived from the order id
 * or any other value the counterparty already has, so it can't be guessed
 * from context. Zero-padded so a code can start with `0` and still always
 * be exactly 4 digits.
 */
export function generateVerificationCode(): string {
  return String(randomInt(0, 10_000)).padStart(4, '0');
}
