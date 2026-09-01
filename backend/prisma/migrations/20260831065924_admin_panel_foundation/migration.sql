-- CreateEnum
CREATE TYPE "DisputeStatus" AS ENUM ('open', 'resolved');

-- CreateEnum
CREATE TYPE "DisputeResolutionType" AS ENUM ('release', 'refund', 'deny');

-- AlterEnum
-- This migration adds more than one value to an enum.
-- With PostgreSQL versions 11 and earlier, this is not possible
-- in a single migration. This can be worked around by creating
-- multiple migrations, each migration adding only one value to
-- the enum.


ALTER TYPE "VendorStatus" ADD VALUE 'pending';
ALTER TYPE "VendorStatus" ADD VALUE 'rejected';

-- AlterTable
ALTER TABLE "users" ADD COLUMN     "suspended_at" TIMESTAMP(3);

-- AlterTable
ALTER TABLE "vendors" ADD COLUMN     "rejection_reason" TEXT;

-- CreateTable
CREATE TABLE "disputes" (
    "id" TEXT NOT NULL,
    "order_id" TEXT NOT NULL,
    "status" "DisputeStatus" NOT NULL DEFAULT 'open',
    "reason" TEXT NOT NULL,
    "resolution_type" "DisputeResolutionType",
    "resolution_note" TEXT,
    "resolved_by" TEXT,
    "resolved_at" TIMESTAMP(3),
    "opened_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "disputes_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "admin_audit_logs" (
    "id" TEXT NOT NULL,
    "actor_id" TEXT NOT NULL,
    "action" TEXT NOT NULL,
    "target_type" TEXT NOT NULL,
    "target_id" TEXT NOT NULL,
    "reason" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "admin_audit_logs_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "reconciliation_runs" (
    "id" TEXT NOT NULL,
    "started_at" TIMESTAMP(3) NOT NULL,
    "finished_at" TIMESTAMP(3) NOT NULL,
    "wallet_checked" INTEGER NOT NULL,
    "transfer_legs_checked" INTEGER NOT NULL,
    "mismatch_count" INTEGER NOT NULL,
    "triggered_by" TEXT,

    CONSTRAINT "reconciliation_runs_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "reconciliation_resolutions" (
    "reference" TEXT NOT NULL,
    "resolved_by" TEXT NOT NULL,
    "note" TEXT NOT NULL,
    "resolved_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "reconciliation_resolutions_pkey" PRIMARY KEY ("reference")
);

-- CreateIndex
CREATE UNIQUE INDEX "disputes_order_id_key" ON "disputes"("order_id");

-- CreateIndex
CREATE INDEX "disputes_status_opened_at_idx" ON "disputes"("status", "opened_at");

-- CreateIndex
CREATE INDEX "admin_audit_logs_target_type_target_id_idx" ON "admin_audit_logs"("target_type", "target_id");

-- CreateIndex
CREATE INDEX "admin_audit_logs_created_at_idx" ON "admin_audit_logs"("created_at");

-- CreateIndex
CREATE INDEX "reconciliation_runs_started_at_idx" ON "reconciliation_runs"("started_at");

-- AddForeignKey
ALTER TABLE "disputes" ADD CONSTRAINT "disputes_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "orders"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
