-- CreateEnum
CREATE TYPE "OrderDeclineReason" AS ENUM ('out_of_stock', 'kitchen_closed', 'too_busy', 'other');

-- AlterEnum
ALTER TYPE "NotificationType" ADD VALUE 'order_declined';

-- AlterTable
ALTER TABLE "orders" ADD COLUMN     "decline_reason" "OrderDeclineReason",
ADD COLUMN     "decline_reason_note" TEXT,
ADD COLUMN     "declined_at" TIMESTAMP(3);
