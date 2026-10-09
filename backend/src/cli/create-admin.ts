/**
 * Creates a dashboard admin account — the production replacement for the
 * dev seed's admin@runit.dev. Run it inside the deployed backend so it uses
 * that environment's DATABASE_URL:
 *
 *   railway ssh -s run-it -- node dist/cli/create-admin.js
 *
 * Everything is typed at prompts: nothing secret is ever a command-line
 * argument (so never in shell history or the process list), the password
 * is not echoed while typed, and nothing prints it. Refuses to run without
 * an interactive terminal, so a password can't be piped in from a file.
 * Never changes an existing account — a forgotten admin password is reset
 * from the dashboard's "Forgot password?".
 */
import { PrismaClient } from '@prisma/client';
import * as bcrypt from 'bcrypt';
import * as readline from 'node:readline';

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

/** Prompts on the terminal; `hidden` answers are not echoed. */
function prompter() {
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout, terminal: true });
  let muted = false;
  // readline echoes each keystroke through _writeToOutput — swallow it while
  // a hidden answer is being typed.
  (rl as unknown as { _writeToOutput: (s: string) => void })._writeToOutput = (s: string) => {
    if (!muted) process.stdout.write(s);
  };
  const ask = (question: string, hidden = false) =>
    new Promise<string>((resolve) => {
      process.stdout.write(question);
      muted = hidden;
      rl.question('', (answer) => {
        muted = false;
        if (hidden) process.stdout.write('\n');
        resolve(answer);
      });
    });
  return { ask, close: () => rl.close() };
}

async function main(): Promise<number> {
  if (!process.stdin.isTTY || !process.stdout.isTTY) {
    console.error('Run this in an interactive terminal (railway ssh -s run-it -- node dist/cli/create-admin.js).');
    return 1;
  }
  const { ask, close } = prompter();
  const prisma = new PrismaClient();
  try {
    console.log('Create a Bridgit dashboard admin. Nothing you type here is saved anywhere but the database.\n');

    let email = '';
    for (;;) {
      email = (await ask('Admin email: ')).trim();
      const problem = emailProblem(email);
      if (!problem) break;
      console.log(problem);
    }
    const name = await ask('Display name (optional): ');

    let password = '';
    for (;;) {
      password = await ask(`Password (at least ${MIN_ADMIN_PASSWORD_LENGTH} characters, not shown): `, true);
      const confirmation = await ask('Type it again: ', true);
      const problem = passwordProblem(password, confirmation);
      if (!problem) break;
      console.log(problem);
    }

    const result = await createAdmin(prisma.user, { email, name, password });
    password = '';
    if (!result.ok) {
      console.error(`\nNot created: ${result.reason}`);
      return 1;
    }
    console.log(`\nCreated admin ${email.toLowerCase()}. Sign in at the dashboard with this email and password.`);
    return 0;
  } finally {
    close();
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
