-- AlterTable
ALTER TABLE "vendors" ADD COLUMN     "requested_campus_id" TEXT;

-- AddForeignKey
ALTER TABLE "vendors" ADD CONSTRAINT "vendors_requested_campus_id_fkey" FOREIGN KEY ("requested_campus_id") REFERENCES "campuses"("id") ON DELETE SET NULL ON UPDATE CASCADE;
