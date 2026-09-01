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

async function main() {
  const passwordHash = await bcrypt.hash(DEV_PASSWORD, BCRYPT_ROUNDS);

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
