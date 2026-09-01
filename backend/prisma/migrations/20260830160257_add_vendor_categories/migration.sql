-- CreateTable
CREATE TABLE "vendor_categories" (
    "slug" TEXT NOT NULL,
    "label" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "vendor_categories_pkey" PRIMARY KEY ("slug")
);

-- CreateIndex
CREATE UNIQUE INDEX "vendor_categories_label_key" ON "vendor_categories"("label");

-- Seed: a starter set covering every category value already in use by an
-- existing vendor row, plus headroom for common campus food categories.
-- Ops can add more later with a plain INSERT — no code deploy required.
INSERT INTO "vendor_categories" ("slug", "label") VALUES
  ('nigerian', 'Nigerian'),
  ('west-african', 'West African'),
  ('fast-food', 'Fast Food'),
  ('continental', 'Continental'),
  ('bakery-pastries', 'Bakery & Pastries'),
  ('drinks-smoothies', 'Drinks & Smoothies'),
  ('snacks', 'Snacks'),
  ('desserts', 'Desserts');
