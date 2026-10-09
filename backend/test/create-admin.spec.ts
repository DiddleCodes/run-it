import {
  createAdmin,
  emailProblem,
  MIN_ADMIN_PASSWORD_LENGTH,
  parseArgs,
  passwordProblem,
  run,
  Terminal,
} from '../src/cli/create-admin';

const hash = async (p: string) => `hashed:${p.length}`;

function users(existing: { accountType: string } | null = null) {
  return {
    findUnique: jest.fn().mockResolvedValue(existing),
    create: jest.fn().mockResolvedValue({ id: 'admin-1' }),
  };
}

describe('create-admin', () => {
  it('validates the email', () => {
    expect(emailProblem('ops@bridgitcampus.com')).toBeNull();
    for (const bad of ['', 'ops', 'ops@', 'ops@bridgitcampus', 'o ps@bridgitcampus.com']) {
      expect(emailProblem(bad)).not.toBeNull();
    }
  });

  it('needs a long enough password, typed the same twice, without stray spaces', () => {
    const good = 'x'.repeat(MIN_ADMIN_PASSWORD_LENGTH);
    expect(passwordProblem(good, good)).toBeNull();
    expect(passwordProblem('short', 'short')).toMatch(/at least/);
    expect(passwordProblem(good, `${good}y`)).toMatch(/match/);
    expect(passwordProblem(` ${good}`, ` ${good}`)).toMatch(/space/);
  });

  it('creates an admin with a hashed password and a lower-cased email', async () => {
    const u = users();
    const result = await createAdmin(u as any, { email: ' Ops@BridgitCampus.com ', name: ' Ops ', password: 'a-long-password' }, hash);

    expect(result).toEqual({ ok: true, id: 'admin-1' });
    expect(u.create).toHaveBeenCalledWith({
      data: { email: 'ops@bridgitcampus.com', name: 'Ops', password: 'hashed:15', accountType: 'admin' },
    });
    expect(JSON.stringify(u.create.mock.calls)).not.toContain('a-long-password');
  });

  it('never changes an existing account', async () => {
    const admin = users({ accountType: 'admin' });
    expect(await createAdmin(admin as any, { email: 'a@b.co', name: '', password: 'pw' }, hash)).toEqual({
      ok: false,
      reason: expect.stringMatching(/already exists.*Forgot password/),
    });
    const restaurant = users({ accountType: 'restaurant' });
    expect(await createAdmin(restaurant as any, { email: 'a@b.co', name: '', password: 'pw' }, hash)).toEqual({
      ok: false,
      reason: expect.stringMatching(/restaurant account/),
    });
    expect(admin.create).not.toHaveBeenCalled();
    expect(restaurant.create).not.toHaveBeenCalled();
  });

  it('reads --email and --name, in either form, and never a password', () => {
    expect(parseArgs(['--email', 'ops@bridgitcampus.com', '--name', 'Ada O'])).toEqual({
      email: 'ops@bridgitcampus.com',
      name: 'Ada O',
    });
    expect(parseArgs(['--email=ops@bridgitcampus.com'])).toEqual({ email: 'ops@bridgitcampus.com' });
    expect(parseArgs([])).toEqual({});
    expect(parseArgs(['--password', 'x']).error).toMatch(/never taken as an argument/);
    expect(parseArgs(['--email']).error).toMatch(/needs a value/);
    expect(parseArgs(['--email', '--name', 'x']).error).toMatch(/needs a value/);
    expect(parseArgs(['--role', 'x']).error).toMatch(/Unknown argument/);
  });

  /** Records the order of whole lines written and lines read. */
  function fakeTerminal(answers: { text: string; hidden: boolean }[]) {
    const events: string[] = [];
    const term: Terminal = {
      line: (text) => events.push(`OUT ${text}`),
      readLine: async (hidden) => {
        const next = answers.shift();
        if (!next) throw new Error('read past the scripted answers');
        expect(hidden).toBe(next.hidden);
        events.push(`IN${hidden ? ' (hidden)' : ''}`);
        return next.text;
      },
    };
    return { term, events };
  }

  it('with --email and --name, only the password is asked — each prompt a whole line before the read', async () => {
    const pw = 'Correct-Horse-Battery-9';
    const { term, events } = fakeTerminal([
      { text: pw, hidden: true },
      { text: pw, hidden: true },
    ]);
    const u = users();
    const code = await run(term, ['--email', 'Ops@BridgitCampus.com', '--name', 'Ops'], u as any);

    expect(code).toBe(0);
    expect(events).toEqual([
      'OUT Create a Bridgit dashboard admin. Nothing you type is saved anywhere but the database.',
      'OUT Admin: ops@bridgitcampus.com (Ops)',
      expect.stringMatching(/^OUT Password, at least 12 characters\. Nothing will show/),
      'IN (hidden)',
      'OUT Type it again, then Enter:',
      'IN (hidden)',
      'OUT Created admin ops@bridgitcampus.com. Sign in at the dashboard with this email and password.',
    ]);
    expect(events.join('\n')).not.toContain(pw);
    expect(u.create).toHaveBeenCalledTimes(1);
  });

  it('without arguments, asks for email and name first (visible), and re-asks a bad email or password', async () => {
    const pw = 'Correct-Horse-Battery-9';
    const { term, events } = fakeTerminal([
      { text: 'nope', hidden: false },
      { text: 'ops@bridgitcampus.com', hidden: false },
      { text: '', hidden: false },
      { text: 'short', hidden: true },
      { text: 'short', hidden: true },
      { text: pw, hidden: true },
      { text: pw, hidden: true },
    ]);
    expect(await run(term, [], users() as any)).toBe(0);
    expect(events.filter((e) => e.startsWith('OUT')).map((e) => e.slice(4))).toEqual(
      expect.arrayContaining(['That is not a valid email address.', 'Use at least 12 characters.', 'Admin: ops@bridgitcampus.com']),
    );
    // Every read is directly preceded by a written prompt line.
    events.forEach((e, i) => {
      if (e.startsWith('IN')) expect(events[i - 1]).toMatch(/^OUT /);
    });
  });

  it('a bad --email is re-asked rather than used', async () => {
    const pw = 'Correct-Horse-Battery-9';
    const { term } = fakeTerminal([
      { text: 'ops@bridgitcampus.com', hidden: false },
      { text: pw, hidden: true },
      { text: pw, hidden: true },
    ]);
    const u = users();
    expect(await run(term, ['--email', 'not-an-email', '--name', ''], u as any)).toBe(0);
    expect(u.create.mock.calls[0][0].data.email).toBe('ops@bridgitcampus.com');
  });

  it('refuses a password passed as an argument without creating anything', async () => {
    const { term, events } = fakeTerminal([]);
    const u = users();
    expect(await run(term, ['--email', 'a@b.co', '--password', 'x'], u as any)).toBe(1);
    expect(events).toEqual([expect.stringMatching(/never taken as an argument/)]);
    expect(u.create).not.toHaveBeenCalled();
  });
});
