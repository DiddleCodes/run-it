import { IsUUID } from 'class-validator';

export class AssignCampusDto {
  @IsUUID()
  campusId!: string;
}
