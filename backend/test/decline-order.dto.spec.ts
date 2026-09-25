import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import { DeclineOrderDto } from '../src/vendors/dto/decline-order.dto';

async function errorsFor(body: object) {
  const errors = await validate(plainToInstance(DeclineOrderDto, body));
  return errors.map((e) => e.property);
}

describe('DeclineOrderDto (Task 61)', () => {
  it.each(['out_of_stock', 'kitchen_closed', 'too_busy'])('accepts %s with no note', async (reason) => {
    expect(await errorsFor({ reason })).toEqual([]);
  });

  it('rejects a reason outside the fixed set', async () => {
    expect(await errorsFor({ reason: 'bored' })).toEqual(['reason']);
  });

  it('rejects a missing reason', async () => {
    expect(await errorsFor({})).toEqual(['reason']);
  });

  it("requires free text for 'other'", async () => {
    expect(await errorsFor({ reason: 'other' })).toEqual(['note']);
  });

  it("rejects whitespace-only free text for 'other'", async () => {
    expect(await errorsFor({ reason: 'other', note: '   ' })).toEqual(['note']);
  });

  it("accepts real free text for 'other'", async () => {
    expect(await errorsFor({ reason: 'other', note: 'Gas ran out' })).toEqual([]);
  });

  it('caps free text at 280 characters', async () => {
    expect(await errorsFor({ reason: 'other', note: 'x'.repeat(281) })).toEqual(['note']);
  });
});
