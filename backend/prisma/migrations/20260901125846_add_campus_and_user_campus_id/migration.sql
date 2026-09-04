-- AlterTable
ALTER TABLE "users" ADD COLUMN     "campus_id" TEXT;

-- CreateTable
CREATE TABLE "campuses" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "allowed_email_domains" TEXT[],
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "campuses_pkey" PRIMARY KEY ("id")
);

-- Data backfill (Task 26): every pre-existing user (seeded dashboard
-- accounts, and every prior task's test fixtures — all of which
-- consistently assumed a single campus, University of Ibadan, with
-- student emails under student.ui.edu.ng) is assigned to one seeded
-- default campus so existing data/tests keep working after this
-- migration, rather than being left with campus_id null. A fresh install
-- with no existing users still gets this one row as a sane starting
-- campus admins can rename/add siblings to.
INSERT INTO "campuses" ("id", "name", "allowed_email_domains")
VALUES ('00000000-0000-4000-8000-000000000001', 'University of Ibadan', ARRAY['student.ui.edu.ng']);

UPDATE "users" SET "campus_id" = '00000000-0000-4000-8000-000000000001' WHERE "campus_id" IS NULL;

-- AddForeignKey
ALTER TABLE "users" ADD CONSTRAINT "users_campus_id_fkey" FOREIGN KEY ("campus_id") REFERENCES "campuses"("id") ON DELETE SET NULL ON UPDATE CASCADE;
