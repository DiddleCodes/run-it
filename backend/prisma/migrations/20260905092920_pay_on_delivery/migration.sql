-- CreateEnum
CREATE TYPE "OrderPaymentMethod" AS ENUM ('wallet', 'pay_on_delivery');

-- CreateEnum
CREATE TYPE "CashCollectionDebtStatus" AS ENUM ('pending', 'settled', 'disputed');

-- DropForeignKey
ALTER TABLE "order_escrows" DROP CONSTRAINT "order_escrows_student_wallet_transaction_id_fkey";

-- AlterTable
ALTER TABLE "order_escrows" ALTER COLUMN "student_wallet_transaction_id" DROP NOT NULL;

-- AlterTable
ALTER TABLE "orders" ADD COLUMN     "payment_method" "OrderPaymentMethod" NOT NULL DEFAULT 'wallet';

-- AlterTable
ALTER TABLE "vendors" ADD COLUMN     "pay_at_delivery_enabled" BOOLEAN NOT NULL DEFAULT false;

-- CreateTable
CREATE TABLE "cash_collection_debts" (
    "id" TEXT NOT NULL,
    "order_id" TEXT NOT NULL,
    "runner_id" TEXT NOT NULL,
    "amount_owed" INTEGER NOT NULL,
    "amount_collected" INTEGER NOT NULL,
    "status" "CashCollectionDebtStatus" NOT NULL DEFAULT 'pending',
    "settled_at" TIMESTAMP(3),
    "settled_by" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "cash_collection_debts_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "cash_collection_debts_order_id_key" ON "cash_collection_debts"("order_id");

-- CreateIndex
CREATE INDEX "cash_collection_debts_runner_id_status_idx" ON "cash_collection_debts"("runner_id", "status");

-- AddForeignKey
ALTER TABLE "order_escrows" ADD CONSTRAINT "order_escrows_student_wallet_transaction_id_fkey" FOREIGN KEY ("student_wallet_transaction_id") REFERENCES "wallet_transactions"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "cash_collection_debts" ADD CONSTRAINT "cash_collection_debts_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "orders"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "cash_collection_debts" ADD CONSTRAINT "cash_collection_debts_runner_id_fkey" FOREIGN KEY ("runner_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
