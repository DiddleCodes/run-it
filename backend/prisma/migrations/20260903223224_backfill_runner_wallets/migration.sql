-- Task 33: runner earnings now land in an in-app wallet balance instead of
-- a direct Paystack transfer (OrderEscrowService.release()'s runner leg).
-- AuthService.verifyOtp now provisions a Wallet for every new runner at
-- signup, same as students — this backfills a zero-balance Wallet row for
-- every runner account that already existed before that change shipped.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

INSERT INTO "wallets" ("id", "user_id", "balance")
SELECT gen_random_uuid()::text, u."id", 0
FROM "users" u
WHERE u."account_type" = 'runner'
  AND NOT EXISTS (SELECT 1 FROM "wallets" w WHERE w."user_id" = u."id");
