/*
  Warnings:

  - You are about to drop the column `notes` on the `order_items` table. All the data in the column will be lost.
  - Added the required column `food_subtotal` to the `order_escrows` table without a default value. This is not possible if the table is not empty.
  - Added the required column `restaurant_commission` to the `order_escrows` table without a default value. This is not possible if the table is not empty.
  - Added the required column `restaurant_platform_fee` to the `order_escrows` table without a default value. This is not possible if the table is not empty.

*/
-- AlterTable
ALTER TABLE "order_escrows" ADD COLUMN     "food_subtotal" INTEGER NOT NULL,
ADD COLUMN     "restaurant_commission" INTEGER NOT NULL,
ADD COLUMN     "restaurant_platform_fee" INTEGER NOT NULL;

-- AlterTable
ALTER TABLE "order_items" DROP COLUMN "notes";

-- AlterTable
ALTER TABLE "orders" ADD COLUMN     "note" TEXT;
