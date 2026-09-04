import { Body, Controller, Delete, ForbiddenException, Get, Param, Patch, Post, Query, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { JwtPayload } from '../auth/jwt-payload.interface';
import { CreateMenuItemDto } from './dto/create-menu-item.dto';
import { ListOrdersQueryDto } from './dto/list-orders-query.dto';
import { ListVendorsQueryDto } from './dto/list-vendors-query.dto';
import { MetricsQueryDto } from './dto/metrics-query.dto';
import { SetAvailabilityDto } from './dto/set-availability.dto';
import { UpdateMenuItemDto } from './dto/update-menu-item.dto';
import { UpdateOrderStatusDto } from './dto/update-order-status.dto';
import { UpsertVendorDto } from './dto/upsert-vendor.dto';
import { VendorsService } from './vendors.service';

function assertCanActAsVendor(user: JwtPayload): void {
  if (user.role === 'admin') return;
  if (user.accountType && user.accountType !== 'restaurant') {
    throw new ForbiddenException('Only restaurant accounts may manage a vendor profile');
  }
}

@Controller('vendors')
export class VendorsController {
  constructor(private readonly vendors: VendorsService) {}

  @Post('me')
  @UseGuards(JwtAuthGuard)
  upsertMe(@CurrentUser() user: JwtPayload, @Body() dto: UpsertVendorDto) {
    assertCanActAsVendor(user);
    return this.vendors.upsertMyVendor(user.sub, dto);
  }

  // The Restaurant Dashboard's Profile tab prefilling itself with the
  // vendor's own current business info before letting them edit it.
  @Get('me')
  @UseGuards(JwtAuthGuard)
  getMe(@CurrentUser() user: JwtPayload) {
    assertCanActAsVendor(user);
    return this.vendors.getMyVendor(user.sub);
  }

  // The Home screen's "Popular around campus" list, category chips, and
  // search bar all read from this (Task 14). Was public until Task 26 —
  // scoping "around campus" to the caller's *actual* campus needs to know
  // who's asking, so this now requires the same JWT every other
  // authenticated route does; the Flutter client was already logged in by
  // the time it ever reaches Home, so this is a tightening, not a breaking
  // change to any real flow.
  @Get()
  @UseGuards(JwtAuthGuard)
  listVendors(@CurrentUser() user: JwtPayload, @Query() query: ListVendorsQueryDto) {
    return this.vendors.listVendors(query, user.campusId ?? null);
  }

  // Public — the controlled category vocabulary (see VendorCategory's
  // schema doc comment). Feeds the vendor application form's category
  // picker and the Home screen's category chips, so both only ever offer
  // values `upsertMyVendor` will actually accept.
  @Get('categories')
  listCategories() {
    return this.vendors.listCategories();
  }

  // Public — a student browsing a restaurant needs no auth.
  @Get(':id/menu')
  getMenu(@Param('id') vendorId: string) {
    return this.vendors.getPublicMenu(vendorId);
  }

  @Post('me/menu-items')
  @UseGuards(JwtAuthGuard)
  createMenuItem(@CurrentUser() user: JwtPayload, @Body() dto: CreateMenuItemDto) {
    assertCanActAsVendor(user);
    return this.vendors.createMenuItem(user.sub, dto);
  }

  @Patch('me/menu-items/:id/availability')
  @UseGuards(JwtAuthGuard)
  setAvailability(@CurrentUser() user: JwtPayload, @Param('id') id: string, @Body() dto: SetAvailabilityDto) {
    assertCanActAsVendor(user);
    return this.vendors.setAvailability(user.sub, id, dto.isAvailable);
  }

  @Patch('me/menu-items/:id')
  @UseGuards(JwtAuthGuard)
  updateMenuItem(@CurrentUser() user: JwtPayload, @Param('id') id: string, @Body() dto: UpdateMenuItemDto) {
    assertCanActAsVendor(user);
    return this.vendors.updateMenuItem(user.sub, id, dto);
  }

  @Delete('me/menu-items/:id')
  @UseGuards(JwtAuthGuard)
  deleteMenuItem(@CurrentUser() user: JwtPayload, @Param('id') id: string) {
    assertCanActAsVendor(user);
    return this.vendors.deleteMenuItem(user.sub, id);
  }

  @Get('me/metrics')
  @UseGuards(JwtAuthGuard)
  metrics(@CurrentUser() user: JwtPayload, @Query() query: MetricsQueryDto) {
    assertCanActAsVendor(user);
    return this.vendors.metrics(user.sub, query);
  }

  // Task 11: orders awaiting pickup, each with the pickup code to show the
  // runner in person. Task 12 extended this with pagination + a status
  // filter for the Restaurant Dashboard's Orders tab — see
  // VendorsService.listIncomingOrders's doc comment for why this one
  // endpoint covers both rather than adding a second, overlapping GET.
  @Get('me/orders/incoming')
  @UseGuards(JwtAuthGuard)
  incomingOrders(@CurrentUser() user: JwtPayload, @Query() query: ListOrdersQueryDto) {
    assertCanActAsVendor(user);
    return this.vendors.listIncomingOrders(user.sub, query);
  }

  // The vendor's own forward-only nudge: placed -> preparing ->
  // ready_for_pickup. Everything after that is runner/delivery-driven
  // (Task 11) and not reachable through this route.
  @Patch('me/orders/:orderId/status')
  @UseGuards(JwtAuthGuard)
  updateOrderStatus(
    @CurrentUser() user: JwtPayload,
    @Param('orderId') orderId: string,
    @Body() dto: UpdateOrderStatusDto,
  ) {
    assertCanActAsVendor(user);
    return this.vendors.advanceOrderStatus(user.sub, orderId, dto);
  }
}
