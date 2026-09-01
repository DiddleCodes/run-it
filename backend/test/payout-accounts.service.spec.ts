import { BadRequestException, NotFoundException, UnprocessableEntityException } from '@nestjs/common';
import { PayoutAccountsService } from '../src/payout-accounts/payout-accounts.service';
import { createPaystackMock, createPrismaMock } from './support/mocks';

function makeService() {
  const prisma = createPrismaMock();
  const paystack = createPaystackMock();
  const service = new PayoutAccountsService(prisma as any, paystack as any);
  return { service, prisma, paystack };
}

const dto = { userId: 'u1', bankCode: '058', accountNumber: '0123456789' };

describe('PayoutAccountsService.create', () => {
  it('throws if the user does not exist', async () => {
    const { service, prisma } = makeService();
    prisma.user.findUnique.mockResolvedValue(null);

    await expect(service.create(dto)).rejects.toThrow(NotFoundException);
  });

  it('rejects students — only restaurants and runners can register payout details', async () => {
    const { service, prisma } = makeService();
    prisma.user.findUnique.mockResolvedValue({ id: 'u1', accountType: 'student' });

    await expect(service.create(dto)).rejects.toThrow(BadRequestException);
  });

  it('rejects and never saves anything when Paystack cannot verify the account', async () => {
    const { service, prisma, paystack } = makeService();
    prisma.user.findUnique.mockResolvedValue({ id: 'u1', accountType: 'runner' });
    paystack.resolveAccount.mockRejectedValue(new UnprocessableEntityException('Could not verify bank account details with Paystack'));

    await expect(service.create(dto)).rejects.toThrow(UnprocessableEntityException);
    expect(paystack.createTransferRecipient).not.toHaveBeenCalled();
    expect(prisma.payoutAccount.upsert).not.toHaveBeenCalled();
  });

  it('saves the Paystack-resolved account name, not whatever was submitted, once verified', async () => {
    const { service, prisma, paystack } = makeService();
    prisma.user.findUnique.mockResolvedValue({ id: 'u1', accountType: 'restaurant' });
    paystack.resolveAccount.mockResolvedValue({ accountNumber: '0123456789', accountName: 'Real Registered Name Ltd' });
    paystack.createTransferRecipient.mockResolvedValue({ recipientCode: 'RCP_123' });
    prisma.payoutAccount.upsert.mockImplementation(({ create }: any) => Promise.resolve({ id: 'pa1', ...create }));

    const result = await service.create(dto);

    expect(paystack.createTransferRecipient).toHaveBeenCalledWith(
      expect.objectContaining({ accountName: 'Real Registered Name Ltd' }),
    );
    expect(result.accountName).toBe('Real Registered Name Ltd');
    expect(result.paystackRecipientCode).toBe('RCP_123');
  });
});
