-- CreateEnum
CREATE TYPE "RunnerKycStatus" AS ENUM ('pending', 'approved', 'rejected');

-- CreateEnum
CREATE TYPE "RunnerKycRunnerType" AS ENUM ('student_runner', 'independent_rider');

-- CreateEnum
CREATE TYPE "RunnerKycIdType" AS ENUM ('student_id', 'government_id');

-- CreateEnum
CREATE TYPE "RunnerVehicleType" AS ENUM ('bicycle', 'motorbike', 'keke');

-- CreateTable
CREATE TABLE "runner_kyc" (
    "id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "runner_type" "RunnerKycRunnerType",
    "id_type" "RunnerKycIdType",
    "id_photo_url" TEXT,
    "selfie_photo_url" TEXT,
    "vehicle_photo_url" TEXT,
    "vehicle_type" "RunnerVehicleType",
    "vehicle_plate" TEXT,
    "status" "RunnerKycStatus" NOT NULL DEFAULT 'pending',
    "rejection_reason" TEXT,
    "submitted_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "reviewed_at" TIMESTAMP(3),

    CONSTRAINT "runner_kyc_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "runner_kyc_user_id_key" ON "runner_kyc"("user_id");

-- CreateIndex
CREATE INDEX "runner_kyc_status_submitted_at_idx" ON "runner_kyc"("status", "submitted_at");

-- AddForeignKey
ALTER TABLE "runner_kyc" ADD CONSTRAINT "runner_kyc_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
