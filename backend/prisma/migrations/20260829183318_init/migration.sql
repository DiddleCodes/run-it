-- CreateEnum
CREATE TYPE "AccountType" AS ENUM ('student', 'runner', 'restaurant');

-- CreateEnum
CREATE TYPE "WalletTransactionType" AS ENUM ('credit', 'debit');

-- CreateEnum
CREATE TYPE "WalletTransactionStatus" AS ENUM ('pending', 'success', 'failed');

-- CreateEnum
CREATE TYPE "EscrowStatus" AS ENUM ('held', 'released', 'refunded');

-- CreateEnum
CREATE TYPE "TransferLegStatus" AS ENUM ('not_applicable', 'pending', 'success', 'failed');

-- CreateTable
CREATE TABLE "users" (
    "id" TEXT NOT NULL,
    "email" TEXT,
    "phone" TEXT,
    "account_type" "AccountType" NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "users_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "wallets" (
    "id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "balance" INTEGER NOT NULL DEFAULT 0,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "wallets_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "wallet_transactions" (
    "id" TEXT NOT NULL,
    "wallet_id" TEXT NOT NULL,
    "type" "WalletTransactionType" NOT NULL,
    "amount" INTEGER NOT NULL,
    "reference" TEXT NOT NULL,
    "status" "WalletTransactionStatus" NOT NULL DEFAULT 'pending',
    "metadata" JSONB,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "wallet_transactions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "payout_accounts" (
    "id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "bank_code" TEXT NOT NULL,
    "account_number" TEXT NOT NULL,
    "account_name" TEXT NOT NULL,
    "paystack_recipient_code" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "payout_accounts_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "order_escrows" (
    "id" TEXT NOT NULL,
    "order_id" TEXT NOT NULL,
    "student_wallet_transaction_id" TEXT NOT NULL,
    "restaurant_user_id" TEXT NOT NULL,
    "runner_user_id" TEXT NOT NULL,
    "status" "EscrowStatus" NOT NULL DEFAULT 'held',
    "gross_amount" INTEGER NOT NULL,
    "platform_fee" INTEGER NOT NULL,
    "restaurant_share" INTEGER NOT NULL,
    "runner_share" INTEGER NOT NULL,
    "restaurant_transfer_reference" TEXT,
    "runner_transfer_reference" TEXT,
    "restaurant_transfer_status" "TransferLegStatus" NOT NULL DEFAULT 'not_applicable',
    "runner_transfer_status" "TransferLegStatus" NOT NULL DEFAULT 'not_applicable',
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "released_at" TIMESTAMP(3),

    CONSTRAINT "order_escrows_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "users_email_key" ON "users"("email");

-- CreateIndex
CREATE UNIQUE INDEX "users_phone_key" ON "users"("phone");

-- CreateIndex
CREATE UNIQUE INDEX "wallets_user_id_key" ON "wallets"("user_id");

-- CreateIndex
CREATE UNIQUE INDEX "wallet_transactions_reference_key" ON "wallet_transactions"("reference");

-- CreateIndex
CREATE UNIQUE INDEX "payout_accounts_user_id_key" ON "payout_accounts"("user_id");

-- CreateIndex
CREATE UNIQUE INDEX "order_escrows_order_id_key" ON "order_escrows"("order_id");

-- CreateIndex
CREATE UNIQUE INDEX "order_escrows_student_wallet_transaction_id_key" ON "order_escrows"("student_wallet_transaction_id");

-- AddForeignKey
ALTER TABLE "wallets" ADD CONSTRAINT "wallets_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "wallet_transactions" ADD CONSTRAINT "wallet_transactions_wallet_id_fkey" FOREIGN KEY ("wallet_id") REFERENCES "wallets"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "payout_accounts" ADD CONSTRAINT "payout_accounts_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "order_escrows" ADD CONSTRAINT "order_escrows_student_wallet_transaction_id_fkey" FOREIGN KEY ("student_wallet_transaction_id") REFERENCES "wallet_transactions"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
