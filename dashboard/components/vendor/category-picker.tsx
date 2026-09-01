"use client";

import { vendorClient } from "@/lib/api/vendor-client";
import { SearchPickerField } from "./search-picker-field";

interface CategoryPickerProps {
  value: string;
  onChange: (label: string) => void;
  errorText?: string;
}

/** Vendor.category picker — real GET /vendors/categories, matches upsertMyVendor's controlled vocabulary exactly. */
export function CategoryPicker({ value, onChange, errorText }: CategoryPickerProps) {
  return (
    <SearchPickerField
      label="Category"
      displayValue={value}
      placeholder="Select a category"
      fetchItems={vendorClient.getCategories}
      getKey={(c) => c.slug}
      getLabel={(c) => c.label}
      onSelect={(c) => onChange(c.label)}
      errorText={errorText}
    />
  );
}
