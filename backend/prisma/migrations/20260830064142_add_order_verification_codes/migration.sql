-- AlterEnum
ALTER TYPE "OrderStatus" ADD VALUE 'picked_up';

-- AlterTable (added nullable first — existing rows are pre-Task-11 and
-- already terminal, so they're backfilled with an inert placeholder below
-- rather than a real usable code; only orders created after this migration
-- ever go through pickup/delivery verification).
ALTER TABLE "orders" ADD COLUMN     "delivery_pin" TEXT,
ADD COLUMN     "delivery_proof_submitted_at" TIMESTAMP(3),
ADD COLUMN     "delivery_proof_url" TEXT,
ADD COLUMN     "needs_manual_review" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "pickup_code" TEXT;

UPDATE "orders" SET "pickup_code" = '0000', "delivery_pin" = '0000' WHERE "pickup_code" IS NULL;

ALTER TABLE "orders" ALTER COLUMN "pickup_code" SET NOT NULL;
ALTER TABLE "orders" ALTER COLUMN "delivery_pin" SET NOT NULL;
