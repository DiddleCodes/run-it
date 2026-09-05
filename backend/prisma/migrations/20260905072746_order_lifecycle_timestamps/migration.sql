-- AlterTable
ALTER TABLE "orders" ADD COLUMN     "accepted_at" TIMESTAMP(3),
ADD COLUMN     "cancelled_at" TIMESTAMP(3),
ADD COLUMN     "delivered_at" TIMESTAMP(3),
ADD COLUMN     "picked_up_at" TIMESTAMP(3);
