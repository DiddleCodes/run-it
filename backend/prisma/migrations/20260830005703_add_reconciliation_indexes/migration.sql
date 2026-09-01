-- CreateIndex
CREATE INDEX "order_escrows_status_released_at_idx" ON "order_escrows"("status", "released_at");

-- CreateIndex
CREATE INDEX "wallet_transactions_status_created_at_idx" ON "wallet_transactions"("status", "created_at");
