import { createAdmin, emailProblem, MIN_ADMIN_PASSWORD_LENGTH, passwordProblem } from '../src/cli/create-admin';

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
});
