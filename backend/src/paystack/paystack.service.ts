import { BadGatewayException, Injectable, Logger, UnprocessableEntityException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import * as Sentry from '@sentry/nestjs';
import axios, { AxiosInstance, isAxiosError } from 'axios';
import { createHmac, timingSafeEqual } from 'crypto';
import {
  PaystackCreateTransferRecipientResponse,
  PaystackInitializeTransactionResponse,
  PaystackInitiateTransferResponse,
  PaystackListBanksResponse,
  PaystackListTransactionsResponse,
  PaystackListTransfersResponse,
  PaystackResolveAccountResponse,
  PaystackVerifyTransactionResponse,
  PaystackVerifyTransferResponse,
} from './paystack.types';

@Injectable()
export class PaystackService {
  private readonly logger = new Logger(PaystackService.name);
  private readonly http: AxiosInstance;
  private readonly secretKey: string;

  // Paystack's bank list changes rarely — cached in-memory so every picker
  // open across every client doesn't round-trip to Paystack.
  private bankListCache: { banks: { name: string; code: string }[]; fetchedAt: number } | null = null;
  private static readonly bankListTtlMs = 24 * 60 * 60 * 1000;

  constructor(private readonly config: ConfigService) {
    this.secretKey = this.config.get<string>('paystack.secretKey') as string;
    this.http = axios.create({
      baseURL: this.config.get<string>('paystack.baseUrl'),
      headers: {
        Authorization: `Bearer ${this.secretKey}`,
        'Content-Type': 'application/json',
      },
      timeout: 15_000,
    });
  }

  /**
   * Verifies the `x-paystack-signature` header against the raw request body,
   * per https://paystack.com/docs/payments/webhooks/#verify-event-origin.
   * Must run against the *raw* (unparsed) body — see main.ts's raw-body
   * middleware on the webhook route.
   */
  verifyWebhookSignature(rawBody: Buffer, signatureHeader: string | undefined): boolean {
    if (!signatureHeader) return false;
    const expected = createHmac('sha512', this.secretKey).update(rawBody).digest('hex');
    const expectedBuf = Buffer.from(expected, 'utf8');
    const gotBuf = Buffer.from(signatureHeader, 'utf8');
    if (expectedBuf.length !== gotBuf.length) return false;
    return timingSafeEqual(expectedBuf, gotBuf);
  }

  async initializeTransaction(params: {
    email: string;
    amountKobo: number;
    reference: string;
    metadata?: Record<string, unknown>;
  }): Promise<PaystackInitializeTransactionResponse['data']> {
    const { data } = await this.request<PaystackInitializeTransactionResponse>('post', '/transaction/initialize', {
      email: params.email,
      amount: params.amountKobo,
      reference: params.reference,
      metadata: params.metadata,
      callback_url: this.config.get<string>('paystack.callbackUrl'),
    });
    return data;
  }

  async listBanks(): Promise<{ name: string; code: string }[]> {
    const cached = this.bankListCache;
    if (cached && Date.now() - cached.fetchedAt < PaystackService.bankListTtlMs) {
      return cached.banks;
    }
    const { data } = await this.request<PaystackListBanksResponse>('get', '/bank?currency=NGN');
    const banks = data.filter((bank) => bank.active).map((bank) => ({ name: bank.name, code: bank.code }));
    this.bankListCache = { banks, fetchedAt: Date.now() };
    return banks;
  }

  async resolveAccount(params: { accountNumber: string; bankCode: string }): Promise<{ accountNumber: string; accountName: string }> {
    try {
      const { data } = await this.request<PaystackResolveAccountResponse>(
        'get',
        `/bank/resolve?account_number=${encodeURIComponent(params.accountNumber)}&bank_code=${encodeURIComponent(params.bankCode)}`,
      );
      return { accountNumber: data.account_number, accountName: data.account_name };
    } catch (err) {
      this.logger.warn(`Account resolve failed for ${params.bankCode}/${params.accountNumber}: ${(err as Error).message}`);
      throw new UnprocessableEntityException('Could not verify bank account details with Paystack');
    }
  }

  async createTransferRecipient(params: {
    accountName: string;
    accountNumber: string;
    bankCode: string;
  }): Promise<{ recipientCode: string }> {
    const { data } = await this.request<PaystackCreateTransferRecipientResponse>('post', '/transferrecipient', {
      type: 'nuban',
      name: params.accountName,
      account_number: params.accountNumber,
      bank_code: params.bankCode,
      currency: 'NGN',
    });
    return { recipientCode: data.recipient_code };
  }

  async initiateTransfer(params: {
    amountKobo: number;
    recipientCode: string;
    reference: string;
    reason: string;
  }): Promise<{ reference: string; transferCode: string; status: string }> {
    const { data } = await this.request<PaystackInitiateTransferResponse>('post', '/transfer', {
      source: 'balance',
      amount: params.amountKobo,
      recipient: params.recipientCode,
      reference: params.reference,
      reason: params.reason,
    });
    return { reference: data.reference, transferCode: data.transfer_code, status: data.status };
  }

  // Used by the reconciliation job to resolve a wallet_transaction that's
  // been stuck `pending` past the staleness threshold — self-healing for a
  // lost/never-delivered charge.success webhook.
  async verifyTransaction(reference: string): Promise<{ status: string; amount: number }> {
    const { data } = await this.request<PaystackVerifyTransactionResponse>(
      'get',
      `/transaction/verify/${encodeURIComponent(reference)}`,
    );
    return { status: data.status, amount: data.amount };
  }

  // Same idea, for a transfer leg stuck `pending` past the threshold —
  // resolves a lost/never-delivered transfer.success / transfer.failed
  // webhook.
  async verifyTransferStatus(reference: string): Promise<{ status: string }> {
    const { data } = await this.request<PaystackVerifyTransferResponse>(
      'get',
      `/transfer/verify/${encodeURIComponent(reference)}`,
    );
    return { status: data.status };
  }

  // Task 13c: reconciliation's real comparison view. Unlike
  // verifyTransaction (single reference), this lists everything Paystack
  // recorded in a date range — the only way to catch a transaction that
  // exists on Paystack but not in our own DB at all.
  async listTransactions(params: {
    from: string;
    to: string;
    page?: number;
  }): Promise<{ items: { reference: string; amount: number; status: string; paidAt: string | null }[]; page: number; pageCount: number }> {
    const query = new URLSearchParams({
      from: params.from,
      to: params.to,
      page: String(params.page ?? 1),
      perPage: '100',
    });
    const { data, meta } = await this.request<PaystackListTransactionsResponse>('get', `/transaction?${query.toString()}`);
    return {
      items: data.map((t) => ({ reference: t.reference, amount: t.amount, status: t.status, paidAt: t.paid_at })),
      page: meta.page,
      pageCount: meta.pageCount,
    };
  }

  // Same as listTransactions, for the separate /transfer API surface —
  // needed to reconcile OrderEscrow's transfer legs, not just wallet charges.
  async listTransfers(params: {
    from: string;
    to: string;
    page?: number;
  }): Promise<{ items: { reference: string; amount: number; status: string }[]; page: number; pageCount: number }> {
    const query = new URLSearchParams({
      from: params.from,
      to: params.to,
      page: String(params.page ?? 1),
      perPage: '100',
    });
    const { data, meta } = await this.request<PaystackListTransfersResponse>('get', `/transfer?${query.toString()}`);
    return {
      items: data.map((t) => ({ reference: t.reference, amount: t.amount, status: t.status })),
      page: meta.page,
      pageCount: meta.pageCount,
    };
  }

  private async request<T>(method: 'get' | 'post', url: string, body?: unknown): Promise<T> {
    try {
      const response = method === 'get' ? await this.http.get<T>(url) : await this.http.post<T>(url, body);
      return response.data;
    } catch (err) {
      if (isAxiosError(err)) {
        this.logger.error(`Paystack ${method.toUpperCase()} ${url} failed: ${JSON.stringify(err.response?.data ?? err.message)}`);
      }
      // Task 31: every caller below rethrows a generic BadGatewayException
      // (never the original error), which is what a client and Sentry's
      // global filter would otherwise see — losing the actual Paystack
      // failure reason. Captured explicitly here instead, with only the
      // method/path/status (no request/response body — that can carry bank
      // account details or the Paystack secret key never belongs in an
      // error tracker either way).
      Sentry.captureException(err, {
        tags: { integration: 'paystack' },
        extra: {
          method,
          url,
          status: isAxiosError(err) ? err.response?.status : undefined,
        },
      });
      throw new BadGatewayException('Paystack request failed');
    }
  }
}
