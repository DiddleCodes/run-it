import { Body, Controller, Param, Post, UseGuards } from '@nestjs/common';
import { JwtPayload } from '../auth/jwt-payload.interface';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { EscrowParty, EscrowPartyGuard } from '../common/guards/escrow-party.guard';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { SelfOrAdminGuard } from '../common/guards/self-or-admin.guard';
import { HoldEscrowDto } from './dto/hold-escrow.dto';
import { OrderEscrowService } from './order-escrow.service';

@Controller('orders/:orderId/escrow')
export class OrderEscrowController {
  constructor(private readonly escrow: OrderEscrowService) {}

  // Called at checkout by the authenticated student themself.
  @Post('hold')
  @UseGuards(JwtAuthGuard, SelfOrAdminGuard)
  hold(@Param('orderId') orderId: string, @Body() dto: HoldEscrowDto) {
    return this.escrow.hold(orderId, dto);
  }

  // Task 21a: any authenticated runner may attempt this — unlike
  // release/refund below, there is no existing party to scope
  // EscrowPartyGuard against yet, since claiming is exactly what assigns
  // one. Ownership (accountType === 'runner') and the actual atomic
  // first-to-claim-wins logic both live in OrderEscrowService.claim.
  @Post('claim')
  @UseGuards(JwtAuthGuard)
  claim(@Param('orderId') orderId: string, @CurrentUser() user: JwtPayload) {
    return this.escrow.claim(orderId, user);
  }

  // Called by the runner's own delivery-confirmation scan (their JWT, scoped
  // to this exact order's escrow — see EscrowPartyGuard), the internal
  // service key, or an admin. Never by an arbitrary client for someone
  // else's order.
  @Post('release')
  @UseGuards(EscrowPartyGuard)
  @EscrowParty('runner')
  release(@Param('orderId') orderId: string) {
    return this.escrow.release(orderId);
  }

  // Called by the ordering student's own cancellation action (their JWT,
  // scoped to this exact order's escrow), the internal service key, or an
  // admin.
  @Post('refund')
  @UseGuards(EscrowPartyGuard)
  @EscrowParty('student')
  refund(@Param('orderId') orderId: string) {
    return this.escrow.refund(orderId);
  }
}
