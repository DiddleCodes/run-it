-- AlterTable
ALTER TABLE "vendors" ADD COLUMN     "average_rating" DOUBLE PRECISION,
ADD COLUMN     "rating_count" INTEGER NOT NULL DEFAULT 0;

-- CreateTable
CREATE TABLE "vendor_ratings" (
    "id" TEXT NOT NULL,
    "order_id" TEXT NOT NULL,
    "vendor_id" TEXT NOT NULL,
    "student_id" TEXT NOT NULL,
    "stars" INTEGER NOT NULL,
    "comment" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "vendor_ratings_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "vendor_ratings_order_id_key" ON "vendor_ratings"("order_id");

-- CreateIndex
CREATE INDEX "vendor_ratings_vendor_id_idx" ON "vendor_ratings"("vendor_id");

-- AddForeignKey
ALTER TABLE "vendor_ratings" ADD CONSTRAINT "vendor_ratings_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "orders"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "vendor_ratings" ADD CONSTRAINT "vendor_ratings_vendor_id_fkey" FOREIGN KEY ("vendor_id") REFERENCES "vendors"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "vendor_ratings" ADD CONSTRAINT "vendor_ratings_student_id_fkey" FOREIGN KEY ("student_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
