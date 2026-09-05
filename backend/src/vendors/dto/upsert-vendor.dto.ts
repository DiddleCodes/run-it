import { IsBoolean, IsOptional, IsString, IsUrl, IsUUID, MaxLength } from 'class-validator';

export class UpsertVendorDto {
  @IsString()
  @MaxLength(120)
  businessName!: string;

  @IsString()
  @MaxLength(60)
  category!: string;

  @IsOptional()
  @IsString()
  @MaxLength(1000)
  description?: string;

  @IsOptional()
  @IsUrl()
  logoUrl?: string;

  // Task 27: the applicant's own stated campus preference from the
  // application wizard — informational only (see Vendor.requestedCampusId's
  // doc comment). Omitted entirely on a later profile edit (the Restaurant
  // Dashboard's own "edit business info" reuses this same endpoint) leaves
  // whatever was captured at first submission untouched.
  @IsOptional()
  @IsUUID()
  requestedCampusId?: string;

  // Task 47: the restaurant's own opt-in for Pay on Delivery — omitted
  // entirely on a routine business-info edit (this same endpoint's other
  // use) leaves whatever was set before untouched, same convention as
  // requestedCampusId above.
  @IsOptional()
  @IsBoolean()
  payAtDeliveryEnabled?: boolean;
}
