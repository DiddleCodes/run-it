import { Controller, Get, Query } from '@nestjs/common';
import { CampusService } from './campus.service';
import { CheckEmailQueryDto } from './dto/check-email-query.dto';

// Public — real reference data (school names), same convention as
// GET /vendors/categories. Never exposes allowedEmailDomains: that list is
// an enforcement detail, not something a client has any legitimate reason
// to read (and echoing it back would make the domain check trivially
// enumerable for no benefit to any real caller).
@Controller('campuses')
export class CampusController {
  constructor(private readonly campus: CampusService) {}

  @Get()
  async list() {
    const campuses = await this.campus.list();
    return campuses.map((c) => ({ id: c.id, name: c.name }));
  }

  // Task 27: real-time signup-field feedback. Still doesn't leak the
  // domain list — only a yes/no (plus the same honest message
  // resolveByEmail would throw) for the one address the caller already
  // typed, exactly what POST /auth/otp already reveals today at submit
  // time, just earlier and non-mutating.
  @Get('check-email')
  checkEmail(@Query() query: CheckEmailQueryDto) {
    return this.campus.checkEmail(query.email);
  }
}
