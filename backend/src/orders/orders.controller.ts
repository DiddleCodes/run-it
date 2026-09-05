import { Body, Controller, ForbiddenException, Get, Param, Post, Query, UseGuards } from '@nestjs/common';
import { JwtPayload } from '../auth/jwt-payload.interface';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { EscrowParty, EscrowPartyGuard } from '../common/guards/escrow-party.guard';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { DeliveryProofDto } from './dto/delivery-proof.dto';
import { DEFAULT_PAGE_SIZE, ListMyOrdersQueryDto, MAX_PAGE_SIZE } from './dto/list-my-orders-query.dto';
import { ReportProblemDto } from './dto/report-problem.dto';
import { VerifyCodeDto } from './dto/verify-code.dto';
import { VerifyPickupDto } from './dto/verify-pickup.dto';
import { OrdersService } from './orders.service';

// Task 46: a separate, param-less controller class from the one below
// (`orders/:orderId`) — `GET /orders` and `GET /orders/:orderId` don't
// collide (Nest routes purely on path shape), and this keeps the
// student-only "my history" concern out of the party-scoped single-order
// one.
@Controller('orders')
export class OrdersHistoryController {
  constructor(private readonly orders: OrdersService) {}

  // Deliberately ignores any studentUserId the caller might try to pass —
  // this is always "my own orders," scoped by the JWT, never an arbitrary
  // id (that would let one student page through another's order history).
  @Get()
  @UseGuards(JwtAuthGuard)
  list(@CurrentUser() user: JwtPayload, @Query() query: ListMyOrdersQueryDto) {
    if (user.accountType && user.accountType !== 'student') {
      throw new ForbiddenException('Only student accounts have an order history here');
    }
    const page = query.page ?? 1;
    const limit = Math.min(query.limit ?? DEFAULT_PAGE_SIZE, MAX_PAGE_SIZE);
    return this.orders.getOrderHistoryForStudent(user.sub, page, limit);
  }
}

// Task 47: a runner's own real-time view of what they currently owe the
// platform from completed Pay on Delivery deliveries — the Wallet screen's
// "cash owed" total. Same "always me, never an arbitrary id" shape as
// OrdersHistoryController above.
@Controller('runners/me/cash-debt')
export class RunnerCashDebtController {
  constructor(private readonly orders: OrdersService) {}

  @Get()
  @UseGuards(JwtAuthGuard)
  get(@CurrentUser() user: JwtPayload) {
    if (user.accountType && user.accountType !== 'runner') {
      throw new ForbiddenException('Only runner accounts have a cash-collection debt here');
    }
    return this.orders.getMyCashDebtSummary(user.sub);
  }
}

@Controller('orders/:orderId')
export class OrdersController {
  constructor(private readonly orders: OrdersService) {}

  // Any party to the order (student, assigned runner, owning vendor, or
  // admin/internal) may fetch it — which codes actually appear in the
  // response is scoped per-viewer inside the service, not by a separate
  // guard per role.
  @Get()
  @UseGuards(JwtAuthGuard)
  get(@Param('orderId') orderId: string, @CurrentUser() user: JwtPayload) {
    return this.orders.getOrderForViewer(orderId, user);
  }

  // The runner's own scan/entry of the vendor-shown pickup code — same
  // identity boundary as escrow release (EscrowPartyGuard, 'runner'): only
  // the runner actually assigned to this order's escrow may call it.
  // Task 30: also where the required handoff photo is registered — see
  // VerifyPickupDto/Order.handoffPhotoUrl's own doc comments.
  @Post('verify-pickup')
  @UseGuards(EscrowPartyGuard)
  @EscrowParty('runner')
  verifyPickup(@Param('orderId') orderId: string, @Body() dto: VerifyPickupDto) {
    return this.orders.verifyPickup(orderId, dto.code, dto.handoffPhotoUrl);
  }

  // The runner's own scan/entry of the student-shown delivery PIN — this
  // is what actually triggers escrow release (see OrdersService).
  @Post('verify-delivery')
  @UseGuards(EscrowPartyGuard)
  @EscrowParty('runner')
  verifyDelivery(@Param('orderId') orderId: string, @Body() dto: VerifyCodeDto) {
    return this.orders.verifyDelivery(orderId, dto.code, dto.amountCollectedKobo);
  }

  // Fallback when PIN verification isn't possible (student's phone
  // unavailable) — flags the order for manual review rather than releasing.
  @Post('delivery-proof')
  @UseGuards(EscrowPartyGuard)
  @EscrowParty('runner')
  submitDeliveryProof(@Param('orderId') orderId: string, @Body() dto: DeliveryProofDto) {
    return this.orders.submitDeliveryProof(orderId, dto);
  }

  // Task 30: the real student-facing "report a problem" entry point —
  // plain JwtAuthGuard (not EscrowPartyGuard/AdminGuard) since the
  // authorization check here is simpler than either: just "is this JWT's
  // subject the student who placed this exact order," enforced inside
  // OrdersService.reportProblem itself, same style as
  // getOrderForViewer's own inline per-viewer checks.
  @Post('report')
  @UseGuards(JwtAuthGuard)
  report(@Param('orderId') orderId: string, @CurrentUser() user: JwtPayload, @Body() dto: ReportProblemDto) {
    if (user.accountType && user.accountType !== 'student') {
      throw new ForbiddenException('Only the ordering student may report a problem with this order');
    }
    return this.orders.reportProblem(orderId, user.sub, dto);
  }
}
