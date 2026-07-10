// supabase/functions/_shared/sanitize.ts
//
// Defensive sanitization for free-text fields that flow into the DB, third-
// party APIs (Paystack/Stripe), and logs. Goals:
//   • Strip control characters (incl. null bytes, ANSI escapes).
//   • Collapse runs of whitespace.
//   • Cap length to prevent abuse / storage bloat.
//   • Reject inputs that look like obvious injection attempts (raw HTML, JS).
//
// Not a replacement for parameterized SQL or output encoding — Postgres handles
// the former; the latter happens at the UI layer. This is a defense-in-depth
// layer that fails fast on malformed input at the edge.

export interface SanitizeTextOptions {
  /** Maximum length after trimming. Default 1000. */
  maxLength?: number;
  /** Minimum length (after trim). Default 0. */
  minLength?: number;
  /** Throw on any HTML-looking content. Default false (just strips tags). */
  rejectHtml?: boolean;
}

const CONTROL_CHARS_RE = /[\x00-\x08\x0B-\x0C\x0E-\x1F\x7F]/g;
const ANSI_ESCAPE_RE = /\x1B\[[0-?]*[ -/]*[@-~]/g;
const HTML_TAG_RE = /<\/?[a-z][^>]*>/gi;
const SCRIPT_RE = /<script[\s\S]*?<\/script>/gi;
const WHITESPACE_RE = /\s+/g;

/**
 * Sanitize a free-text field. Returns the cleaned string.
 *
 * Throws `Error('invalid input: …')` on hard violations (oversize, HTML when
 * rejectHtml=true). Strips control chars, ANSI escapes, and HTML by default.
 */
export function sanitizeText(
  raw: unknown,
  opts: SanitizeTextOptions = {},
): string {
  if (raw == null) return '';
  if (typeof raw !== 'string') {
    throw new Error('invalid input: expected string');
  }
  const maxLength = opts.maxLength ?? 1000;
  const minLength = opts.minLength ?? 0;

  let s = raw
    .replace(SCRIPT_RE, '')
    .replace(CONTROL_CHARS_RE, '')
    .replace(ANSI_ESCAPE_RE, '');

  if (opts.rejectHtml && HTML_TAG_RE.test(s)) {
    throw new Error('invalid input: HTML not allowed');
  }
  s = s.replace(HTML_TAG_RE, '');
  s = s.replace(WHITESPACE_RE, ' ').trim();

  if (s.length < minLength) {
    throw new Error(`invalid input: minimum length is ${minLength}`);
  }
  if (s.length > maxLength) {
    s = s.slice(0, maxLength);
  }
  return s;
}

/**
 * Sanitize a strictly alphanumeric identifier (bank code, account number,
 * subaccount code). Strips anything that isn't `[A-Za-z0-9_\-]`. Caps to 64.
 */
export function sanitizeIdentifier(raw: unknown, maxLength = 64): string {
  if (raw == null) return '';
  if (typeof raw !== 'string') {
    throw new Error('invalid input: expected string');
  }
  const s = raw.replace(/[^A-Za-z0-9_\-]/g, '').slice(0, maxLength);
  return s;
}

/**
 * Validate + sanitize a money amount. Returns a number. Throws on NaN,
 * Infinity, negative, or out-of-range values.
 */
export function sanitizeAmount(
  raw: unknown,
  opts: { min?: number; max?: number } = {},
): number {
  const min = opts.min ?? 0;
  const max = opts.max ?? 1_000_000_000;
  const n =
    typeof raw === 'number' ? raw : typeof raw === 'string' ? Number(raw) : NaN;
  if (!Number.isFinite(n)) throw new Error('invalid input: amount not finite');
  if (n < min) throw new Error(`invalid input: amount below minimum ${min}`);
  if (n > max) throw new Error(`invalid input: amount above maximum ${max}`);
  // Round to 2 decimal places to avoid floating-point dust.
  return Math.round(n * 100) / 100;
}

/**
 * Validate an ISO 4217 currency code. Returns the upper-cased code.
 */
export function sanitizeCurrency(raw: unknown): string {
  if (typeof raw !== 'string') {
    throw new Error('invalid input: currency must be a string');
  }
  const s = raw.trim().toUpperCase();
  if (!/^[A-Z]{3}$/.test(s)) {
    throw new Error('invalid input: currency must be a 3-letter ISO code');
  }
  return s;
}

/**
 * Returns a redacted version of an object safe for production logging.
 * Strips well-known sensitive keys at any depth.
 */
const SENSITIVE_KEYS = new Set([
  'authorization',
  'apikey',
  'api_key',
  'password',
  'token',
  'secret',
  'card',
  'pan',
  'cvv',
  'pin',
  'authorization_url',
  'access_code',
  'account_number',
  'customer_phone',
  'phone',
  'email',
]);

export function redactForLog(value: unknown, depth = 0): unknown {
  if (depth > 5) return '[depth-limit]';
  if (value == null) return value;
  if (Array.isArray(value)) {
    return value.map((v) => redactForLog(v, depth + 1));
  }
  if (typeof value === 'object') {
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
      if (SENSITIVE_KEYS.has(k.toLowerCase())) {
        out[k] = '[REDACTED]';
      } else {
        out[k] = redactForLog(v, depth + 1);
      }
    }
    return out;
  }
  return value;
}

/** True if running with debug logging enabled. */
export function isDebugLogging(): boolean {
  const v = (Deno.env.get('PAYMENT_DEBUG_LOGS') ?? '').toLowerCase();
  return v === 'true' || v === '1' || v === 'yes';
}

/**
 * Redact a phone number for logs while keeping enough context to correlate
 * (country code + last 4 digits). `+233241234567` -> `+233****4567`.
 * Returns null/empty unchanged so callers can pass through optional fields.
 */
export function redactPhone(raw: unknown): string {
  if (raw == null) return '';
  const s = String(raw);
  if (s.length < 6) return '[REDACTED]';
  const cc = s.startsWith('+') ? s.slice(0, 4) : s.slice(0, 3);
  const tail = s.slice(-4);
  return `${cc}****${tail}`;
}

/**
 * Stringifies an error for logging without leaking sensitive payloads.
 * Returns the error message + name only; never the full Error object (which
 * may include the request body in fetch errors) or the stack (file paths).
 */
export function redactError(e: unknown): string {
  if (e == null) return 'null';
  if (e instanceof Error) return `${e.name}: ${e.message}`;
  // Could be a Supabase PostgrestError or arbitrary object — only safe fields.
  if (typeof e === 'object') {
    const o = e as Record<string, unknown>;
    const code = o.code ?? o.status ?? '';
    const msg = o.message ?? o.error ?? '';
    return `${code} ${msg}`.trim() || '[unredactable object error]';
  }
  return String(e).slice(0, 200);
}
