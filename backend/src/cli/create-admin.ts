/**
 * Creates a dashboard admin account — the production replacement for the
 * dev seed's admin@runit.dev. Run it inside the deployed backend so it uses
 * that environment's DATABASE_URL:
 *
 *   railway ssh -s run-it -- node dist/cli/create-admin.js --email you@example.com --name "Your Name"
 *
 * Only the password is typed, at a prompt: it is never a command-line
 * argument (so never in shell history or the process list), it is read
 * with the terminal's echo off, and nothing prints it. --email and --name
 * are optional; anything not given is asked for. Refuses to run without an
 * interactive terminal, so a password can't be piped in from a file.
 * Never changes an existing account — a forgotten admin password is reset
 * from the dashboard's "Forgot password?".
 *
 * Every prompt ends in a newline: Railway's SSH relay holds output until a
 * line ends, so a prompt left on the same line as the answer only appeared
 * after Enter.
 */
import { PrismaClient } from '@prisma/client';
import * as bcrypt from 'bcrypt';

// Same cost factor AuthService uses for dashboard passwords.
const BCRYPT_ROUNDS = 12;
export const MIN_ADMIN_PASSWORD_LENGTH = 12;

export function emailProblem(email: string): string | null {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ? null : 'That is not a valid email address.';
}

export function passwordProblem(password: string, confirmation: string): string | null {
  if (password.length < MIN_ADMIN_PASSWORD_LENGTH) {
    return `Use at least ${MIN_ADMIN_PASSWORD_LENGTH} characters.`;
  }
  if (password.trim() !== password) return 'The password starts or ends with a space — leave those out.';
  if (password !== confirmation) return "The two passwords don't match.";
  return null;
}

/** `--email a@b.co --name "Ada O"` or `--email=a@b.co`. Never accepts a password. */
export function parseArgs(argv: string[]): { email?: string; name?: string; error?: string } {
  const out: { email?: string; name?: string } = {};
  for (let i = 0; i < argv.length; i++) {
    const [flag, inline] = argv[i].split(/=(.*)/s, 2);
    if (flag !== '--email' && flag !== '--name') {
      return {
        error: /pass/i.test(flag)
          ? 'The password is never taken as an argument — you will be asked for it.'
          : `Unknown argument "${flag}". Use --email and --name.`,
      };
    }
    const value = inline ?? argv[++i];
    if (value === undefined || value.startsWith('--')) return { error: `${flag} needs a value.` };
    out[flag === '--email' ? 'email' : 'name'] = value;
  }
  return out;
}

type Users = Pick<PrismaClient['user'], 'findUnique' | 'create'>;

/** Creates the admin, or explains why not. Never touches an existing account. */
export async function createAdmin(
  users: Users,
  input: { email: string; name: string; password: string },
  hash: (password: string) => Promise<string> = (p) => bcrypt.hash(p, BCRYPT_ROUNDS),
): Promise<{ ok: true; id: string } | { ok: false; reason: string }> {
  const email = input.email.trim().toLowerCase();
  const existing = await users.findUnique({ where: { email } });
  if (existing) {
    return {
      ok: false,
      reason:
        existing.accountType === 'admin'
          ? 'An admin with that email already exists. To change its password, use "Forgot password?" on the dashboard.'
          : `That email already belongs to a ${existing.accountType} account. Use a different email for the admin.`,
    };
  }
  const user = await users.create({
    data: { email, name: input.name.trim() || null, password: await hash(input.password), accountType: 'admin' },
  });
  return { ok: true, id: user.id };
}

export interface Terminal {
  /** Writes a whole line (a newline is added). */
  line(text: string): void;
  /** Reads one line; `hidden` reads with echo off. */
  readLine(hidden: boolean): Promise<string>;
}

/**
 * The interactive flow, separate from the real terminal so a test can check
 * every prompt is a complete line before anything is read.
 */
export async function run(term: Terminal, argv: string[], users: Users): Promise<number> {
  const args = parseArgs(argv);
  if (args.error) {
    term.line(args.error);
    return 1;
  }
  term.line('Create a Bridgit dashboard admin. Nothing you type is saved anywhere but the database.');

  let email = args.email?.trim() ?? '';
  for (;;) {
    if (!email) {
      term.line('Admin email, then Enter:');
      email = (await term.readLine(false)).trim();
    }
    const problem = emailProblem(email);
    if (!problem) break;
    term.line(problem);
    email = '';
  }
  let name = args.name;
  if (name === undefined) {
    term.line('Display name (optional), then Enter:');
    name = await term.readLine(false);
  }
  term.line(`Admin: ${email.toLowerCase()}${name.trim() ? ` (${name.trim()})` : ''}`);

  let password = '';
  for (;;) {
    term.line(`Password, at least ${MIN_ADMIN_PASSWORD_LENGTH} characters. Nothing will show as you type — type it, then Enter:`);
    password = await term.readLine(true);
    term.line('Type it again, then Enter:');
    const confirmation = await term.readLine(true);
    const problem = passwordProblem(password, confirmation);
    if (!problem) break;
    term.line(problem);
  }

  const result = await createAdmin(users, { email, name, password });
  password = '';
  if (!result.ok) {
    term.line(`Not created: ${result.reason}`);
    return 1;
  }
  term.line(`Created admin ${email.toLowerCase()}. Sign in at the dashboard with this email and password.`);
  return 0;
}

/**
 * The real terminal, in raw mode: echo is off for hidden answers and on
 * (written back by us) for visible ones. Handles Backspace and Ctrl-C.
 */
function rawTerminal(): Terminal & { close(): void } {
  const stdin = process.stdin;
  stdin.setRawMode(true);
  stdin.setEncoding('utf8');
  stdin.resume();
  let pending = '';
  let waiter: ((chunk: string) => void) | null = null;
  stdin.on('data', (chunk: string) => {
    if (waiter) waiter(chunk);
    else pending += chunk;
  });
  const nextChunk = () =>
    new Promise<string>((resolve) => {
      if (pending) {
        const chunk = pending;
        pending = '';
        resolve(chunk);
      } else {
        waiter = (chunk) => {
          waiter = null;
          resolve(chunk);
        };
      }
    });

  return {
    line: (text) => process.stdout.write(`${text}\n`),
    async readLine(hidden) {
      let value = '';
      for (;;) {
        const chunk = await nextChunk();
        for (let i = 0; i < chunk.length; i++) {
          const ch = chunk[i];
          if (ch === '\r' || ch === '\n') {
            if (i + 1 < chunk.length) pending = chunk.slice(i + 1).replace(/^\n/, '') + pending;
            process.stdout.write('\r\n');
            return value;
          }
          if (ch === '\u0003') {
            process.stdout.write('\r\nCancelled — nothing was created.\r\n');
            stdin.setRawMode(false);
            process.exit(130);
          }
          if (ch === '\u007f' || ch === '\b') {
            if (value) {
              value = value.slice(0, -1);
              if (!hidden) process.stdout.write('\b \b');
            }
            continue;
          }
          if (ch < ' ') continue; // other control keys
          value += ch;
          if (!hidden) process.stdout.write(ch);
        }
      }
    },
    close() {
      stdin.setRawMode(false);
      stdin.pause();
    },
  };
}

async function main(): Promise<number> {
  if (!process.stdin.isTTY || !process.stdout.isTTY) {
    console.error(
      'Run this in an interactive terminal: railway ssh -s run-it -- node dist/cli/create-admin.js --email you@example.com',
    );
    return 1;
  }
  const term = rawTerminal();
  // Raw mode turns off the terminal's own newline translation for output.
  const line = (text: string) => process.stdout.write(`${text}\r\n`);
  const prisma = new PrismaClient();
  try {
    return await run({ line, readLine: term.readLine }, process.argv.slice(2), prisma.user);
  } finally {
    term.close();
    await prisma.$disconnect();
  }
}

if (require.main === module) {
  main().then(
    (code) => process.exit(code),
    (err: Error) => {
      // The message only — a Prisma error can carry the connection string in its details.
      console.error(`Failed: ${err.message.split('\n')[0]}`);
      process.exit(1);
    },
  );
}
