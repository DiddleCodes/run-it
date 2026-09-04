import { BadGatewayException, HttpException, UnprocessableEntityException } from '@nestjs/common';
import { WalletService } from '../src/wallet/wallet.service';
import { createAlertsMock, createPaystackMock, createPrismaMock, createWebhooksServiceMock } from './support/mocks';

function makeService() {
  const prisma = createPrismaMock();
  const paystack = createPaystackMock();
  const webhooks = createWebhooksServiceMock();
  const alerts = createAlertsMock();
  const service = new WalletService(prisma as any, paystack as any, webhooks as any, alerts as any);
  return { service, prisma, paystack, webhooks, alerts };
}

const wallet = { id: 'w1', userId: 'u1', balance: 10_000 };
const payoutAccount = { id: 'pa1', userId: 'u1', paystackRecipientCode: 'RCP_u1' };

describe('WalletService.initiateWithdrawal', () => {
  it('rejects when the user has no payout account on file', async () => {
    const { service, prisma } = makeService();
    prisma.wallet.findUnique.mockResolvedValue(wallet);
    prisma.payoutAccount.findUnique.mockResolvedValue(null);

    await expect(service.initiateWithdrawal({ userId: 'u1', amountKobo: 1_000 })).rejects.toThrow(
      UnprocessableEntityException,
    );
  });

  it('rejects — same conditional-decrement guarantee as OrderEscrowService.hold — when the balance does not cover the amount', async () => {
    const { service, prisma, paystack } = makeService();
    prisma.wallet.findUnique.mockResolvedValue(wallet);
    prisma.payoutAccount.findUnique.mockResolvedValue(payoutAccount);
    prisma.wallet.updateMany.mockResolvedValue({ count: 0 }); // gte check failed

    await expect(service.initiateWithdrawal({ userId: 'u1', amountKobo: 50_000 })).rejects.toThrow(HttpException);
    expect(paystack.initiateTransfer).not.toHaveBeenCalled();
  });

  it('debits the wallet, creates a pending ledger row, and initiates a real Paystack transfer to the confirmed recipient', async () => {
    const { service, prisma, paystack } = makeService();
    prisma.wallet.findUnique.mockResolvedValue(wallet);
    prisma.payoutAccount.findUnique.mockResolvedValue(payoutAccount);
    prisma.wallet.updateMany.mockResolvedValue({ count: 1 });
    prisma.walletTransaction.create.mockImplementation(({ data }: any) => Promise.resolve({ id: 'wt1', ...data }));
    paystack.initiateTransfer.mockResolvedValue({ reference: 'ref', transferCode: 'TRF_x', status: 'pending' });

    const result = await service.initiateWithdrawal({ userId: 'u1', amountKobo: 3_000 });

    expect(prisma.wallet.updateMany).toHaveBeenCalledWith({
      where: { id: 'w1', balance: { gte: 3_000 } },
      data: { balance: { decrement: 3_000 } },
    });
    expect(prisma.walletTransaction.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({ type: 'debit', amount: 3_000, status: 'pending' }),
      }),
    );
    expect(paystack.initiateTransfer).toHaveBeenCalledWith(
      expect.objectContaining({ amountKobo: 3_000, recipientCode: 'RCP_u1' }),
    );
    expect(result.status).toBe('pending');
  });

  // Mirrors OrderEscrowService.release()'s safe-failure pattern (Task 31):
  // the debit above already committed by the time Paystack rejects the
  // transfer — this proves it gets reversed through the shared path, not
  // left half-committed.
  it('reverses the debit via the shared webhook path when Paystack rejects the transfer, and never loses the money', async () => {
    const { service, prisma, paystack, webhooks, alerts } = makeService();
    prisma.wallet.findUnique.mockResolvedValue(wallet);
    prisma.payoutAccount.findUnique.mockResolvedValue(payoutAccount);
    prisma.wallet.updateMany.mockResolvedValue({ count: 1 });
    prisma.walletTransaction.create.mockImplementation(({ data }: any) => Promise.resolve({ id: 'wt1', ...data }));
    paystack.initiateTransfer.mockRejectedValue(new Error('Paystack transfer API timed out'));

    await expect(service.initiateWithdrawal({ userId: 'u1', amountKobo: 3_000 })).rejects.toThrow(BadGatewayException);

    expect(webhooks.applyVerifiedTransferResult).toHaveBeenCalledWith(
      expect.stringMatching(/^wallet_withdraw_/),
      'failed',
    );
    expect(alerts.send).toHaveBeenCalledWith(
      'Wallet withdrawal failed to initiate for user u1',
      expect.objectContaining({ userId: 'u1', amountKobo: 3_000 }),
    );
  });
});
