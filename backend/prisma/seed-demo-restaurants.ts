import { PrismaClient } from '@prisma/client';
import * as bcrypt from 'bcrypt';

/**
 * Task 55: dev/demo seed — 3-4 fictional restaurants per real Campus row,
 * each with a full menu, created through the same validation the real
 * vendor-application + admin-approval flow enforces (VendorCategory
 * lookup, Campus.requireById-equivalent existence check, the exact
 * `AdminVendorReviewService.approve` transaction shape including its audit
 * log entry) rather than a raw insert that skips those checks. Never run
 * against a production database — business names are original/fictional,
 * imagery is generic stock food photography (fine for clearly-labeled demo
 * data; real vendor onboarding still requires the vendor's own photos —
 * see MenuImagePlaceholder's doc comment and Task 54's sourcing rule).
 */

const BCRYPT_ROUNDS = 12;
const DEMO_PASSWORD = 'RunIt-Demo-2026!';

const prisma = new PrismaClient();

type Section = 'Mains' | 'Sides' | 'Swallow' | 'Grills' | 'Drinks' | 'Pastries' | 'Snacks' | 'Desserts';

interface DishTemplate {
  name: string;
  description: string;
  priceKobo: number;
  section: Section;
}

// One representative, appetizing stock photo per category — verified real
// Unsplash URLs (HTTP 200, image/jpeg, visually previewed before use).
// Reused across every restaurant/item in that category: this is demo data
// standing in for "generic food photography," not a specific vendor's own
// dish photo, so one well-chosen image per cuisine is honest rather than
// synthesizing a fake unique photo per line item.
const CATEGORY_IMAGE: Record<string, string> = {
  Nigerian: 'https://images.unsplash.com/photo-1665332195309-9d75071138f0?w=800&q=80&auto=format&fit=crop',
  'West African': 'https://images.unsplash.com/photo-1767974968707-db3d448d4ef3?w=800&q=80&auto=format&fit=crop',
  'Fast Food': 'https://images.unsplash.com/photo-1512058564366-18510be2db19?w=800&q=80&auto=format&fit=crop',
  Continental: 'https://images.unsplash.com/photo-1709389883900-b0b34592ba11?w=800&q=80&auto=format&fit=crop',
  'Bakery & Pastries': 'https://images.unsplash.com/photo-1422919869950-5fdedb27cde8?w=800&q=80&auto=format&fit=crop',
  'Drinks & Smoothies': 'https://images.unsplash.com/photo-1552286970-62449522d6f3?w=800&q=80&auto=format&fit=crop',
  Snacks: 'https://images.unsplash.com/photo-1515022376298-7333f33e704b?w=800&q=80&auto=format&fit=crop',
  Desserts: 'https://images.unsplash.com/photo-1535911765168-1fafc87dcfa3?w=800&q=80&auto=format&fit=crop',
};

// Dish pools per category (matches the 8 real VendorCategory labels).
// Every restaurant in a category picks 9-10 of these, in order, so no two
// restaurants of the same category show an identical menu length/mix.
const DISH_POOLS: Record<string, DishTemplate[]> = {
  Nigerian: [
    { name: 'Jollof Rice & Fried Chicken', description: 'Smoky party-style jollof rice with a crispy fried chicken thigh.', priceKobo: 220000, section: 'Mains' },
    { name: 'Jollof Rice & Grilled Fish', description: 'The same smoky jollof paired with a whole grilled tilapia.', priceKobo: 250000, section: 'Mains' },
    { name: 'Efo Riro & Semo', description: 'Spinach stew loaded with assorted meat, served with smooth semovita.', priceKobo: 200000, section: 'Swallow' },
    { name: 'Amala & Ewedu', description: 'Yam-flour swallow with ewedu soup and a side of gbegiri.', priceKobo: 180000, section: 'Swallow' },
    { name: 'Egusi Soup & Pounded Yam', description: 'Melon-seed soup with stockfish, served with pounded yam.', priceKobo: 240000, section: 'Swallow' },
    { name: 'Ofada Rice & Ayamase', description: 'Local ofada rice with a fiery green-pepper sauce and assorted meat.', priceKobo: 260000, section: 'Mains' },
    { name: 'Fried Rice & Turkey', description: 'Nigerian-style fried rice with mixed vegetables and a turkey portion.', priceKobo: 230000, section: 'Mains' },
    { name: 'Ewa Agoyin & Plantain', description: 'Mashed beans in a spicy palm-oil stew with fried plantain.', priceKobo: 150000, section: 'Mains' },
    { name: 'Goat Meat Pepper Soup', description: 'Fiery spiced broth with tender, slow-cooked goat meat chunks.', priceKobo: 200000, section: 'Sides' },
    { name: 'Moin Moin', description: 'Steamed bean pudding with egg and fish flakes.', priceKobo: 90000, section: 'Sides' },
    { name: 'Native Soup & Fufu', description: 'Light native soup with assorted meat, served with fufu.', priceKobo: 210000, section: 'Swallow' },
    { name: 'Yam Porridge (Asaro)', description: 'Yam pieces simmered in a palm-oil pepper sauce.', priceKobo: 160000, section: 'Mains' },
  ],
  'West African': [
    { name: 'Suya Platter (Beef)', description: 'Spiced, char-grilled beef skewers with onions and cabbage.', priceKobo: 200000, section: 'Grills' },
    { name: 'Suya Platter (Chicken)', description: 'Yaji-spiced grilled chicken skewers.', priceKobo: 210000, section: 'Grills' },
    { name: 'Peppered Snail', description: 'Grilled snails tossed in a fiery pepper sauce.', priceKobo: 300000, section: 'Grills' },
    { name: 'Asun (Spicy Goat Meat)', description: 'Chopped, smoky grilled goat meat in pepper sauce.', priceKobo: 280000, section: 'Grills' },
    { name: 'Whole Grilled Catfish', description: 'Catfish marinated and grilled whole over an open flame.', priceKobo: 320000, section: 'Grills' },
    { name: 'Kilishi (Dried Beef)', description: 'Spiced, sun-dried beef jerky, sliced thin.', priceKobo: 150000, section: 'Snacks' },
    { name: 'Grilled Chicken & Chips', description: 'Half a grilled chicken with a side of fries.', priceKobo: 290000, section: 'Mains' },
    { name: 'Peppered Turkey', description: 'Turkey wings roasted then finished in a pepper sauce.', priceKobo: 270000, section: 'Grills' },
    { name: 'Isi Ewu', description: 'Spiced goat-head delicacy in a rich pepper sauce.', priceKobo: 340000, section: 'Mains' },
    { name: 'Bole & Grilled Fish', description: 'Roasted plantain (bole) with grilled fish.', priceKobo: 220000, section: 'Mains' },
  ],
  'Fast Food': [
    { name: 'Chicken Shawarma', description: 'Grilled chicken shawarma wrap with garlic sauce.', priceKobo: 180000, section: 'Mains' },
    { name: 'Beef Shawarma', description: 'Spiced beef shawarma wrap with fresh vegetables.', priceKobo: 190000, section: 'Mains' },
    { name: 'Fried Rice & Chicken', description: 'Classic fast-food fried rice with crispy fried chicken.', priceKobo: 200000, section: 'Mains' },
    { name: 'Jumbo Beef Burger', description: 'Grilled beef patty burger with cheese and a side of fries.', priceKobo: 250000, section: 'Mains' },
    { name: 'Spicy Chicken Wings (6pc)', description: 'Deep-fried wings tossed in a hot sauce glaze.', priceKobo: 170000, section: 'Snacks' },
    { name: 'Meat Pie & Soft Drink', description: 'Flaky meat pie combo with a chilled soft drink.', priceKobo: 120000, section: 'Snacks' },
    { name: 'Club Sandwich', description: 'Triple-decker sandwich with chicken, egg, and vegetables.', priceKobo: 160000, section: 'Mains' },
    { name: 'Chips & Chicken Nuggets', description: 'Crispy fries with breaded chicken nuggets.', priceKobo: 150000, section: 'Sides' },
    { name: 'Spaghetti Bolognese', description: 'Fast-food style spaghetti tossed in a rich meat sauce.', priceKobo: 190000, section: 'Mains' },
    { name: 'Hot Dog Combo', description: 'Grilled sausage hot dog with a side of fries.', priceKobo: 140000, section: 'Mains' },
  ],
  Continental: [
    { name: 'Grilled Chicken & Rice', description: 'Herb-marinated chicken breast with steamed rice and vegetables.', priceKobo: 280000, section: 'Mains' },
    { name: 'Beef Steak & Mashed Potatoes', description: 'Pan-seared steak with creamy mash and gravy.', priceKobo: 350000, section: 'Mains' },
    { name: 'Spaghetti Carbonara', description: 'Creamy pasta with bacon and parmesan.', priceKobo: 260000, section: 'Mains' },
    { name: 'Grilled Fish & Vegetables', description: 'Pan-grilled fish fillet with sautéed seasonal vegetables.', priceKobo: 300000, section: 'Mains' },
    { name: 'Chicken Alfredo Pasta', description: 'Fettuccine in a creamy alfredo sauce with grilled chicken.', priceKobo: 270000, section: 'Mains' },
    { name: 'Vegetable Stir-Fry', description: 'Mixed vegetables tossed in a light soy glaze.', priceKobo: 180000, section: 'Sides' },
    { name: 'Caesar Salad with Chicken', description: 'Crisp romaine, parmesan, and croutons with grilled chicken.', priceKobo: 220000, section: 'Sides' },
    { name: 'Herb-Crusted Lamb Chops', description: 'Lamb chops with a herb crust and roasted potatoes.', priceKobo: 350000, section: 'Mains' },
  ],
  'Bakery & Pastries': [
    { name: 'Nigerian Meat Pie', description: 'Flaky pastry filled with spiced minced meat and potato.', priceKobo: 80000, section: 'Pastries' },
    { name: 'Sausage Roll', description: 'Soft pastry wrapped around a seasoned sausage filling.', priceKobo: 80000, section: 'Pastries' },
    { name: 'Chin Chin (small pack)', description: 'Crunchy, lightly sweetened fried pastry cubes.', priceKobo: 90000, section: 'Snacks' },
    { name: 'Glazed Doughnut', description: 'Soft doughnut finished with a sweet glaze.', priceKobo: 80000, section: 'Pastries' },
    { name: 'Puff Puff (6pc)', description: 'Golden, fluffy deep-fried dough balls.', priceKobo: 90000, section: 'Snacks' },
    { name: 'Coconut Bread Slice', description: 'Dense, lightly sweet bread baked with shredded coconut.', priceKobo: 100000, section: 'Pastries' },
    { name: 'Meat Pie & Egg Roll Combo', description: 'A meat pie paired with a boiled-egg roll.', priceKobo: 140000, section: 'Pastries' },
    { name: 'Banana Bread Slice', description: 'Moist banana bread, baked fresh daily.', priceKobo: 110000, section: 'Pastries' },
    { name: 'Chicken Pie', description: 'Flaky pastry filled with a creamy chicken and vegetable mix.', priceKobo: 90000, section: 'Pastries' },
    { name: 'Scotch Egg', description: 'Boiled egg wrapped in seasoned sausage meat, breaded and fried.', priceKobo: 100000, section: 'Snacks' },
  ],
  'Drinks & Smoothies': [
    { name: 'Chapman (large)', description: 'The classic Nigerian mocktail, chilled and garnished.', priceKobo: 120000, section: 'Drinks' },
    { name: 'Fresh Watermelon Smoothie', description: 'Blended fresh watermelon, chilled and lightly sweetened.', priceKobo: 150000, section: 'Drinks' },
    { name: 'Mango & Pineapple Smoothie', description: 'A tropical blend of fresh mango and pineapple.', priceKobo: 160000, section: 'Drinks' },
    { name: 'Zobo Drink (chilled)', description: 'Hibiscus-leaf drink infused with ginger and fruit.', priceKobo: 100000, section: 'Drinks' },
    { name: 'Tiger Nut Milk (Kunun Aya)', description: 'Creamy, naturally sweet tiger-nut milk.', priceKobo: 110000, section: 'Drinks' },
    { name: 'Strawberry Banana Smoothie', description: 'Fresh strawberries and banana blended smooth.', priceKobo: 170000, section: 'Drinks' },
    { name: 'Fresh Orange Juice', description: 'Freshly squeezed orange juice, no added sugar.', priceKobo: 130000, section: 'Drinks' },
    { name: 'Iced Coffee', description: 'Chilled brewed coffee over ice with milk.', priceKobo: 140000, section: 'Drinks' },
    { name: 'Chilled Coconut Water', description: 'Straight from a fresh coconut, served cold.', priceKobo: 90000, section: 'Drinks' },
    { name: 'Avocado Smoothie', description: 'Creamy avocado blended with milk and a touch of honey.', priceKobo: 160000, section: 'Drinks' },
  ],
  Snacks: [
    { name: 'Small Chops Platter', description: 'An assorted platter of spring rolls, samosa, and puff puff.', priceKobo: 250000, section: 'Snacks' },
    { name: 'Spring Rolls (4pc)', description: 'Crispy vegetable spring rolls, fried golden.', priceKobo: 120000, section: 'Snacks' },
    { name: 'Samosa (4pc)', description: 'Spiced meat-filled pastry triangles, fried crisp.', priceKobo: 110000, section: 'Snacks' },
    { name: 'Peppered Gizzard', description: 'Chicken gizzard tossed in a spicy pepper sauce.', priceKobo: 200000, section: 'Snacks' },
    { name: 'Fish Rolls (4pc)', description: 'Flaky pastry rolls filled with seasoned fish.', priceKobo: 130000, section: 'Snacks' },
    { name: 'Chicken Suya Skewer Snack', description: 'A single yaji-spiced grilled chicken skewer.', priceKobo: 150000, section: 'Snacks' },
    { name: 'Plantain Chips (pack)', description: 'Thin, crunchy fried plantain chips.', priceKobo: 90000, section: 'Snacks' },
    { name: 'Puff Puff & Pepper Sauce', description: 'Fluffy puff puff served with a side of pepper sauce.', priceKobo: 100000, section: 'Snacks' },
    { name: 'Yam Balls (5pc)', description: 'Seasoned mashed yam, breaded and fried.', priceKobo: 120000, section: 'Snacks' },
    { name: 'Chicken Popcorn', description: 'Bite-sized breaded chicken pieces, fried crisp.', priceKobo: 160000, section: 'Snacks' },
  ],
  Desserts: [
    { name: 'Chocolate Cake Slice', description: 'Rich, moist chocolate cake with a chocolate glaze.', priceKobo: 150000, section: 'Desserts' },
    { name: 'Red Velvet Cupcake', description: 'Soft red velvet cupcake topped with cream-cheese frosting.', priceKobo: 100000, section: 'Desserts' },
    { name: 'Ice Cream Sundae', description: 'Vanilla ice cream with chocolate syrup and toppings.', priceKobo: 180000, section: 'Desserts' },
    { name: 'Vanilla Cheesecake Slice', description: 'Creamy vanilla cheesecake on a biscuit base.', priceKobo: 190000, section: 'Desserts' },
    { name: 'Bread Pudding', description: 'Warm, spiced bread pudding with a caramel drizzle.', priceKobo: 120000, section: 'Desserts' },
    { name: 'Fruit Salad Cup', description: 'A fresh mix of seasonal fruits in a chilled cup.', priceKobo: 130000, section: 'Desserts' },
    { name: 'Chocolate Brownie', description: 'Dense, fudgy chocolate brownie square.', priceKobo: 110000, section: 'Desserts' },
    { name: 'Coconut Candy', description: 'Sweet, chewy coconut and bread candy squares.', priceKobo: 90000, section: 'Desserts' },
    { name: 'Caramel Custard', description: 'Silky baked custard topped with a caramel sauce.', priceKobo: 140000, section: 'Desserts' },
    { name: 'Banana Split', description: 'Sliced banana with ice cream, syrup, and nuts.', priceKobo: 200000, section: 'Desserts' },
  ],
};

interface RestaurantTemplate {
  slug: string;
  businessName: string;
  ownerName: string;
  category: string;
  description: string;
}

// 4 restaurants per campus, spread across 4 different categories each, so
// every campus has a realistic, varied food scene rather than four clones.
const CAMPUS_RESTAURANTS: Record<string, RestaurantTemplate[]> = {
  'University of Ibadan': [
    { slug: 'mama-bisis-kitchen', businessName: "Mama Bisi's Kitchen", ownerName: 'Bisi Adewale', category: 'Nigerian', description: 'Home-style Nigerian classics made fresh daily, from smoky jollof to hearty swallow and soup combos.' },
    { slug: 'grillhouse-7', businessName: 'Grillhouse 7', ownerName: 'Chidi Okonkwo', category: 'West African', description: 'Open-flame suya, asun, and grilled specialties straight off the grill.' },
    { slug: 'golden-crust-bakery', businessName: 'Golden Crust Bakery', ownerName: 'Tunde Bakare', category: 'Bakery & Pastries', description: 'Fresh-baked meat pies, pastries, and snacks for the ultimate campus grab-and-go.' },
    { slug: 'quickbite-express', businessName: 'QuickBite Express', ownerName: 'Ngozi Eze', category: 'Fast Food', description: 'Fast, filling combos — shawarma, fried rice, and burgers in minutes.' },
  ],
  'Bingham University': [
    { slug: 'iya-basiras-pot', businessName: "Iya Basira's Pot", ownerName: 'Basira Muhammed', category: 'Nigerian', description: 'Traditional soups and swallow, cooked the way grandma used to.' },
    { slug: 'sip-and-blend', businessName: 'Sip & Blend', ownerName: 'Kemi Alabi', category: 'Drinks & Smoothies', description: 'Fresh juices, smoothies, and chilled local drinks to beat the campus heat.' },
    { slug: 'campus-continental', businessName: 'Campus Continental', ownerName: 'Femi Ogunleye', category: 'Continental', description: 'Steaks, pastas, and grilled plates for a proper sit-down feel on the go.' },
    { slug: 'naija-snacks-corner', businessName: 'Naija Snacks Corner', ownerName: 'Aisha Bello', category: 'Snacks', description: 'Small chops, spring rolls, and all your favorite bite-sized cravings.' },
  ],
  'Obafemi Awolowo University': [
    { slug: 'amala-spot-oau', businessName: 'Amala Spot OAU', ownerName: 'Bimbo Adeyemi', category: 'Nigerian', description: "OAU's go-to for amala, ewedu, and rich native soups." },
    { slug: 'sweet-tooth-desserts', businessName: 'Sweet Tooth Desserts', ownerName: 'Tolu Fashola', category: 'Desserts', description: 'Cakes, pastries, and sweet treats to cap off any meal.' },
    { slug: 'suya-junction', businessName: 'Suya Junction', ownerName: 'Yusuf Danladi', category: 'West African', description: 'Late-night suya and grilled meats, spiced just right.' },
    { slug: 'crusty-bites-bakery', businessName: 'Crusty Bites Bakery', ownerName: 'Grace Nwosu', category: 'Bakery & Pastries', description: 'Freshly baked pies, rolls, and pastries every morning.' },
  ],
  'Covenant University': [
    { slug: 'cu-jollof-house', businessName: 'CU Jollof House', ownerName: 'Chuka Obi', category: 'Nigerian', description: 'Signature party-style jollof and classic Nigerian mains.' },
    { slug: 'frost-and-fizz', businessName: 'Frost & Fizz', ownerName: 'Zainab Suleiman', category: 'Drinks & Smoothies', description: 'Cold-pressed juices and smoothies made fresh to order.' },
    { slug: 'the-grillmaster', businessName: 'The Grillmaster', ownerName: 'Emeka Nnamdi', category: 'West African', description: 'Smoky grilled meats and suya platters, made to share.' },
    { slug: 'quick-serve-diner', businessName: 'Quick Serve Diner', ownerName: 'Funke Adigun', category: 'Fast Food', description: 'Quick combos — shawarma, burgers, and fried rice for busy students.' },
  ],
};

// Fallback for any campus that exists in the database but isn't one of the
// four named above (e.g. one created later via Task 51's admin UI) — still
// gets a real, varied 4-restaurant scene rather than being silently
// skipped, cycling the same category rotation with the campus's own name
// worked into each description.
function fallbackRestaurantsFor(campusName: string): RestaurantTemplate[] {
  const rotation: Array<{ category: string; noun: string }> = [
    { category: 'Nigerian', noun: 'Kitchen' },
    { category: 'West African', noun: 'Grill' },
    { category: 'Bakery & Pastries', noun: 'Bakery' },
    { category: 'Fast Food', noun: 'Express' },
  ];
  const slugBase = campusName.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '');
  return rotation.map((r, i) => ({
    slug: `${slugBase}-${r.noun.toLowerCase()}`,
    businessName: `${campusName.split(' ')[0]} ${r.noun}`,
    ownerName: `Demo Owner ${i + 1}`,
    category: r.category,
    description: `A ${r.category.toLowerCase()} spot serving students at ${campusName}.`,
  }));
}

// Deterministic per-restaurant item selection/pricing/availability so
// re-running the seed is idempotent (upserts) without menu items reshuffling
// on every run.
function pickItems(category: string, restaurantIndex: number): DishTemplate[] {
  const pool = DISH_POOLS[category];
  const count = 9 + (restaurantIndex % 2); // 9 or 10 items
  const rotated = [...pool.slice(restaurantIndex % pool.length), ...pool.slice(0, restaurantIndex % pool.length)];
  return rotated.slice(0, Math.min(count, pool.length));
}

async function main() {
  const admin = await prisma.user.findUnique({ where: { email: 'admin@runit.dev' } });
  if (!admin) {
    throw new Error('admin@runit.dev not found — run `npm run prisma:seed` first');
  }

  const categories = await prisma.vendorCategory.findMany();
  const resolveCategory = (input: string): string => {
    const match = categories.find(
      (c) => c.label.toLowerCase() === input.toLowerCase() || c.slug.toLowerCase() === input.toLowerCase(),
    );
    if (!match) throw new Error(`Unknown vendor category "${input}" — not in vendor_categories`);
    return match.label;
  };

  const campuses = await prisma.campus.findMany({ where: { isActive: true }, orderBy: { createdAt: 'asc' } });
  if (campuses.length === 0) {
    throw new Error('No active campuses found — run `npm run prisma:seed` first');
  }

  const passwordHash = await bcrypt.hash(DEMO_PASSWORD, BCRYPT_ROUNDS);
  let vendorCount = 0;
  let menuItemCount = 0;

  for (const campus of campuses) {
    const templates = CAMPUS_RESTAURANTS[campus.name] ?? fallbackRestaurantsFor(campus.name);

    for (let i = 0; i < templates.length; i++) {
      const t = templates[i];
      const category = resolveCategory(t.category);
      const email = `${t.slug}@vendors.runit.dev`;

      const owner = await prisma.user.upsert({
        where: { email },
        update: {},
        create: { email, name: t.ownerName, password: passwordHash, accountType: 'restaurant' },
      });

      // Mirrors VendorsService.upsertMyVendor's real applicant shape: a
      // fresh submission always lands as `pending` with the applicant's
      // requestedCampusId set, never straight to `active`.
      const vendor = await prisma.vendor.upsert({
        where: { userId: owner.id },
        update: {
          businessName: t.businessName,
          category,
          description: t.description,
          logoUrl: CATEGORY_IMAGE[category],
          requestedCampusId: campus.id,
        },
        create: {
          userId: owner.id,
          businessName: t.businessName,
          category,
          description: t.description,
          logoUrl: CATEGORY_IMAGE[category],
          requestedCampusId: campus.id,
          status: 'pending',
        },
      });

      // Mirrors AdminVendorReviewService.approve's exact transaction shape:
      // vendor -> active, owning user's campusId assigned, real audit log
      // entry — never a raw status write that skips the approval trail.
      await prisma.$transaction(async (tx) => {
        await tx.vendor.update({
          where: { id: vendor.id },
          data: { status: 'active', rejectionReason: null },
        });
        await tx.user.update({ where: { id: owner.id }, data: { campusId: campus.id } });
        await tx.adminAuditLog.create({
          data: {
            actorId: admin.id,
            action: 'vendor.approve',
            targetType: 'vendor',
            targetId: vendor.id,
            reason: 'Seeded demo vendor (Task 55)',
          },
        });
      });
      vendorCount++;

      const existingItems = await prisma.menuItem.findMany({ where: { vendorId: vendor.id } });
      if (existingItems.length > 0) {
        // Idempotent re-run: menu already seeded for this vendor, don't duplicate.
        continue;
      }

      const items = pickItems(category, i);
      for (let j = 0; j < items.length; j++) {
        const dish = items[j];
        // A couple of items per restaurant flagged unavailable/sold-out so
        // the demo data doesn't read as uniformly, unrealistically perfect.
        const isAvailable = !(j === items.length - 1 || j === Math.floor(items.length / 2));
        // Every third item skips a photo to genuinely exercise
        // MenuImagePlaceholder's fallback path rather than always having one.
        const photoUrl = j % 3 === 2 ? null : CATEGORY_IMAGE[category];

        await prisma.menuItem.create({
          data: {
            vendorId: vendor.id,
            name: dish.name,
            description: dish.description,
            price: dish.priceKobo,
            photoUrl,
            category: dish.section,
            isAvailable,
          },
        });
        menuItemCount++;
      }
    }
  }

  console.log(`Seeded ${vendorCount} demo restaurants across ${campuses.length} campuses (${menuItemCount} menu items).`);
}

main()
  .catch((err) => {
    console.error(err);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
