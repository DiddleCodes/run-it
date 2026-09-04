import { Injectable, NotFoundException, UnprocessableEntityException } from '@nestjs/common';
import { Campus } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';

/**
 * Task 26: the real, multi-school Campus directory — replaces the
 * previous "campus" concept, which existed only as a hardcoded static list
 * (`kCampuses`) inside the Flutter client and was never persisted or
 * enforced server-side at all (see the Task 26 investigation report).
 */
@Injectable()
export class CampusService {
  constructor(private readonly prisma: PrismaService) {}

  list(): Promise<Campus[]> {
    return this.prisma.campus.findMany({ orderBy: { name: 'asc' } });
  }

  async requireById(id: string): Promise<Campus> {
    const campus = await this.prisma.campus.findUnique({ where: { id } });
    if (!campus) throw new NotFoundException('Campus not found');
    return campus;
  }

  /**
   * Task 26's actual enforcement mechanism for students: extracts the
   * domain from `email` and matches it against every campus's
   * `allowedEmailDomains`, case-insensitively. Matching is a plain
   * domain-string comparison (not a suffix/subdomain match) — a listed
   * domain must equal the email's domain exactly, so a school's real
   * domain can't be spoofed by prefixing an arbitrary subdomain in front
   * of it (e.g. `student.ui.edu.ng.evil.com` must never match
   * `student.ui.edu.ng`).
   *
   * Throws (not a nullable return) so every caller is forced to handle
   * the no-match case explicitly rather than accidentally treating a
   * missing campus as "no restriction" — that would silently defeat the
   * whole point of this method.
   */
  async resolveByEmail(email: string): Promise<Campus> {
    const domain = email.split('@')[1]?.toLowerCase().trim();
    if (!domain) {
      throw new UnprocessableEntityException('That email address doesn\'t look valid.');
    }

    const campuses = await this.prisma.campus.findMany();
    const match = campuses.find((campus) =>
      campus.allowedEmailDomains.some((allowed) => allowed.toLowerCase() === domain),
    );

    if (!match) {
      throw new UnprocessableEntityException(
        `We don't recognize "${domain}" as a registered campus email domain. RUN-It is currently only available to students at supported schools — contact support if your school should be added.`,
      );
    }

    return match;
  }

  /**
   * Task 27: the real-time signup-field version of `resolveByEmail` — same
   * matching logic, but returns a result instead of throwing, so a public
   * endpoint can surface it as live UI feedback while the user is still
   * typing. `resolveByEmail` (used at actual OTP request/verify) remains
   * the real enforcement; this is purely advisory.
   */
  async checkEmail(email: string): Promise<{ valid: boolean; campusName?: string; message?: string }> {
    try {
      const campus = await this.resolveByEmail(email);
      return { valid: true, campusName: campus.name };
    } catch (err) {
      if (err instanceof UnprocessableEntityException) {
        const response = err.getResponse();
        const message = typeof response === 'string' ? response : (response as { message: string }).message;
        return { valid: false, message };
      }
      throw err;
    }
  }
}
