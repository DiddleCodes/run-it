export interface PaystackInitializeTransactionResponse {
  status: boolean;
  message: string;
  data: {
    authorization_url: string;
    access_code: string;
    reference: string;
  };
}

export interface PaystackListBanksResponse {
  status: boolean;
  message: string;
  data: {
    name: string;
    code: string;
    active: boolean;
  }[];
}

export interface PaystackResolveAccountResponse {
  status: boolean;
  message: string;
  data: {
    account_number: string;
    account_name: string;
    bank_id: number;
  };
}

export interface PaystackCreateTransferRecipientResponse {
  status: boolean;
  message: string;
  data: {
    recipient_code: string;
    active: boolean;
  };
}

export interface PaystackInitiateTransferResponse {
  status: boolean;
  message: string;
  data: {
    reference: string;
    transfer_code: string;
    status: string;
  };
}

export interface PaystackVerifyTransactionResponse {
  status: boolean;
  message: string;
  data: {
    reference: string;
    amount: number;
    // 'success' | 'failed' | 'abandoned' | ...
    status: string;
  };
}

export interface PaystackVerifyTransferResponse {
  status: boolean;
  message: string;
  data: {
    reference: string;
    // 'success' | 'failed' | 'reversed' | 'pending' | ...
    status: string;
  };
}

// Task 13c: reconciliation's compareAgainstPaystack() needs the real
// transaction *list* (not a single-reference lookup) — it's the only way
// to catch "a Paystack transaction with nothing on our side" (a reference
// we'd never think to look up because we don't know it exists).
export interface PaystackListTransactionsResponse {
  status: boolean;
  message: string;
  data: {
    reference: string;
    amount: number;
    // 'success' | 'failed' | 'abandoned' | ...
    status: string;
    paid_at: string | null;
  }[];
  meta: {
    total: number;
    page: number;
    pageCount: number;
  };
}

// Same idea as PaystackListTransactionsResponse, but for the /transfer list
// — Paystack's charges and transfers are two separate API surfaces, and
// reconciliation needs to compare both against our own WalletTransaction
// (charges) and OrderEscrow transfer legs (transfers).
export interface PaystackListTransfersResponse {
  status: boolean;
  message: string;
  data: {
    reference: string;
    amount: number;
    status: string;
  }[];
  meta: {
    total: number;
    page: number;
    pageCount: number;
  };
}

export type PaystackChargeSuccessEvent = {
  event: 'charge.success';
  data: {
    reference: string;
    amount: number;
    status: string;
    customer: { email: string };
    metadata?: Record<string, unknown>;
  };
};

export type PaystackTransferEvent = {
  event: 'transfer.success' | 'transfer.failed' | 'transfer.reversed';
  data: {
    reference: string;
    transfer_code: string;
    amount: number;
    status: string;
  };
};

export type PaystackWebhookEvent = PaystackChargeSuccessEvent | PaystackTransferEvent | { event: string; data: Record<string, unknown> };
