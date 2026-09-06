import { CampusService } from '../src/campus/campus.service';

function makeService(campuses: { id: string; name: string; allowedEmailDomains: string[] }[]) {
  const prisma = { campus: { findMany: jest.fn().mockResolvedValue(campuses) } };
  return new CampusService(prisma as any);
}

// Task 27: checkEmail is the real-time, non-throwing sibling of
// resolveByEmail — same matching, just surfaced as a result instead of an
// exception so a public "is this domain recognized" endpoint can back live
// signup-field feedback without becoming the real enforcement itself
// (resolveByEmail, called at actual OTP request/verify, still is).
describe('CampusService.checkEmail', () => {
  const campuses = [{ id: 'campus-1', name: 'University of Ibadan', allowedEmailDomains: ['student.ui.edu.ng'] }];

  it('reports a match for a recognized domain, with the campus name', async () => {
    const service = makeService(campuses);

    const result = await service.checkEmail('ada@student.ui.edu.ng');

    expect(result).toEqual({ valid: true, campusName: 'University of Ibadan' });
  });

  it('reports no match for an unrecognized domain, with the same honest message resolveByEmail throws', async () => {
    const service = makeService(campuses);

    const result = await service.checkEmail('ada@gmail.com');

    expect(result.valid).toBe(false);
    expect(result.message).toContain('gmail.com');
    expect(result.message).toContain('RUN-It');
  });

  it('reports no match for a malformed address, rather than throwing', async () => {
    const service = makeService(campuses);

    const result = await service.checkEmail('not-an-email');

    expect(result.valid).toBe(false);
    expect(result.message).toBeDefined();
  });

  it('matches domain-only, never a spoofed subdomain', async () => {
    const service = makeService(campuses);

    const result = await service.checkEmail('ada@student.ui.edu.ng.evil.com');

    expect(result.valid).toBe(false);
  });
});

// Task 51: deactivating a campus must stop it from matching new signups —
// resolveByEmail/list are the two real enforcement points, so both need to
// filter on isActive at the query level, not just trust every row returned.
describe('CampusService — isActive filtering (Task 51)', () => {
  it('list() only queries active campuses', async () => {
    const prisma = { campus: { findMany: jest.fn().mockResolvedValue([]) } };
    const service = new CampusService(prisma as any);

    await service.list();

    expect(prisma.campus.findMany).toHaveBeenCalledWith(
      expect.objectContaining({ where: { isActive: true } }),
    );
  });

  it('resolveByEmail() only queries active campuses', async () => {
    const prisma = { campus: { findMany: jest.fn().mockResolvedValue([]) } };
    const service = new CampusService(prisma as any);

    await service.resolveByEmail('ada@student.ui.edu.ng').catch(() => {});

    expect(prisma.campus.findMany).toHaveBeenCalledWith({ where: { isActive: true } });
  });
});
