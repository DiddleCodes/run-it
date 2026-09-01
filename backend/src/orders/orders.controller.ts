import { Body, Controller, Get, Param, Post, UseGuards } from '@nestjs/common';
import { JwtPayload } from '../auth/jwt-payload.interface';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { EscrowParty, EscrowPartyGuard } from '../common/guards/escrow-party.guard';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { DeliveryProofDto } from './dto/delivery-proof.dto';
import { VerifyCodeDto } from './dto/verify-code.dto';
import { OrdersService } from './orders.service';

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
  @Post('verify-pickup')
  @UseGuards(EscrowPartyGuard)
  @EscrowParty('runner')
  verifyPickup(@Param('orderId') orderId: string, @Body() dto: VerifyCodeDto) {
    return this.orders.verifyPickup(orderId, dto.code);
  }

  // The runner's own scan/entry of the student-shown delivery PIN — this
  // is what actually triggers escrow release (see OrdersService).
  @Post('verify-delivery')
  @UseGuards(EscrowPartyGuard)
  @EscrowParty('runner')
  verifyDelivery(@Param('orderId') orderId: string, @Body() dto: VerifyCodeDto) {
    return this.orders.verifyDelivery(orderId, dto.code);
  }

  // Fallback when PIN verification isn't possible (student's phone
  // unavailable) — flags the order for manual review rather than releasing.
  @Post('delivery-proof')
  @UseGuards(EscrowPartyGuard)
  @EscrowParty('runner')
  submitDeliveryProof(@Param('orderId') orderId: string, @Body() dto: DeliveryProofDto) {
    return this.orders.submitDeliveryProof(orderId, dto);
  }
}
