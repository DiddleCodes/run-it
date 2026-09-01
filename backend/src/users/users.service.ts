import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { CreateUserDto } from './dto/create-user.dto';

@Injectable()
export class UsersService {
  constructor(private readonly prisma: PrismaService) {}

  async create(dto: CreateUserDto) {
    const user = await this.prisma.user.create({
      data: {
        email: dto.email,
        phone: dto.phone,
        accountType: dto.accountType,
      },
    });

    // Students only, for now — see order_escrows spec.
    if (dto.accountType === 'student') {
      await this.prisma.wallet.create({
        data: { userId: user.id, balance: 0 },
      });
    }

    return user;
  }

  async findById(id: string) {
    const user = await this.prisma.user.findUnique({ where: { id } });
    if (!user) throw new NotFoundException('User not found');
    return user;
  }
}
