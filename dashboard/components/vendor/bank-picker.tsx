"use client";

import { Bank, vendorClient } from "@/lib/api/vendor-client";
import { SearchPickerField } from "./search-picker-field";

interface BankPickerProps {
  value: Bank | null;
  onChange: (bank: Bank) => void;
  errorText?: string;
}

/** Payout bank picker — real GET /payout-accounts/banks (Paystack bank list, 24h server-cached). */
export function BankPicker({ value, onChange, errorText }: BankPickerProps) {
  return (
    <SearchPickerField
      label="Bank"
      displayValue={value?.name ?? ""}
      placeholder="Choose your bank"
      fetchItems={vendorClient.getBanks}
      // `code` alone isn't guaranteed unique — Paystack's real bank list
      // has a handful of distinct banks sharing a code (e.g. two MFBs both
      // coded 50572). Pairing with `name` keeps the React key unique.
      getKey={(b) => `${b.code}-${b.name}`}
      getLabel={(b) => b.name}
      onSelect={onChange}
      errorText={errorText}
    />
  );
}
