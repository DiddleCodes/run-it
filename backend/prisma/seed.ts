import { PrismaClient } from '@prisma/client';
import * as bcrypt from 'bcrypt';

/**
 * Dev-only seed for the web dashboard's email+password login — creates one
 * admin account and one restaurant account (with its Vendor row) so
 * Task 13a's login → role-guard → shell flow can be exercised end to end
 * locally. Never run against a production database.
 */

const BCRYPT_ROUNDS = 12;
const DEV_PASSWORD = 'RunIt-Dev-2026!';

const prisma = new PrismaClient();

// Task 26: multi-school from the start — the migration itself only seeds
// the one campus every pre-existing user gets backfilled onto (University
// of Ibadan, id fixed at 00000000-0000-4000-8000-000000000001 so that
// backfill and this seed never disagree about which row is "the same
// one"). These three are the same real schools the old Flutter-only
// `kCampuses` static list carried (never persisted anywhere server-side
// before this task) — domains are a reasonable placeholder convention
// (matching student.ui.edu.ng's existing pattern in this codebase's test
// fixtures), not verified real domains; a real deployment would confirm
// each school's actual student email domain(s) before enabling it.
const ADDITIONAL_CAMPUSES = [
  { name: 'Bingham University', allowedEmailDomains: ['student.bu.edu.ng'] },
  { name: 'Obafemi Awolowo University', allowedEmailDomains: ['student.oauife.edu.ng'] },
  { name: 'Covenant University', allowedEmailDomains: ['student.cu.edu.ng'] },
];

async function main() {
  const passwordHash = await bcrypt.hash(DEV_PASSWORD, BCRYPT_ROUNDS);

  for (const campus of ADDITIONAL_CAMPUSES) {
    const existing = await prisma.campus.findFirst({ where: { name: campus.name } });
    if (!existing) {
      await prisma.campus.create({ data: campus });
    }
  }

  const admin = await prisma.user.upsert({
    where: { email: 'admin@runit.dev' },
    update: {},
    create: {
      email: 'admin@runit.dev',
      name: 'Amara Osei',
      password: passwordHash,
      accountType: 'admin',
    },
  });

  const restaurantUser = await prisma.user.upsert({
    where: { email: 'restaurant@runit.dev' },
    update: {},
    create: {
      email: 'restaurant@runit.dev',
      name: 'Ji-Yeon Park',
      password: passwordHash,
      accountType: 'restaurant',
    },
  });

  await prisma.vendor.upsert({
    where: { userId: restaurantUser.id },
    update: {},
    create: {
      userId: restaurantUser.id,
      businessName: 'Spice Garden',
      category: 'West African',
      status: 'active',
    },
  });

  console.log('Seeded dashboard accounts (dev only):');
  console.log(`  admin@runit.dev      / ${DEV_PASSWORD}  (id: ${admin.id})`);
  console.log(`  restaurant@runit.dev / ${DEV_PASSWORD}  (id: ${restaurantUser.id})`);
}

main()
  .catch((err) => {
    console.error(err);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
