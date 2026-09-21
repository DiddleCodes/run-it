-- CreateEnum
CREATE TYPE "OrderType" AS ENUM ('standard', 'group');

-- AlterTable
ALTER TABLE "menu_items" ADD COLUMN     "is_main_meal" BOOLEAN NOT NULL DEFAULT false;

-- AlterTable
ALTER TABLE "orders" ADD COLUMN     "order_type" "OrderType" NOT NULL DEFAULT 'standard';
