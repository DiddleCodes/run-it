enum RunnerAvailability { offline, online }

enum DeliveryStage { offered, accepted, pickedUp, delivered }

class RunnerStatus {
  const RunnerStatus({
    required this.availability,
    this.activeDeliveryId,
    this.isVerifiedRunner = true,
  });
  final RunnerAvailability availability;
  final String? activeDeliveryId;
  final bool isVerifiedRunner;
}

/// Task 21b: shaped directly by what `GET /matching/available` and the
/// `runner-dispatch` socket's `new_job_available` broadcast actually carry
/// — no campus tag (the backend has no per-order campus concept; see
/// `RunnerDispatchGateway`'s own doc comment), no distance/ETA (no vendor
/// geo data exists server-side to compute one from, so this never shows a
/// fabricated number), no per-job expiry (a broadcast job has no countdown
/// — that model retired with the single-offer flow).
class DeliveryJob {
  const DeliveryJob({
    required this.id,
    required this.eateryName,
    required this.eateryLocation,
    required this.dropoffZone,
    required this.dropoffLocation,
    required this.payoutAmount,
    required this.totalAmount,
    required this.offeredAt,
  });
  /// The order id — also what `POST /orders/:id/escrow/claim` takes.
  final String id;
  final String eateryName;
  final String eateryLocation;
  final String dropoffZone;
  final String dropoffLocation;
  final int payoutAmount;

  /// The order's full total (Task 21b) — a real, honest stand-in for the
  /// old fabricated distance/ETA stat, shown on the Available card instead.
  final int totalAmount;
  final DateTime offeredAt;
}

class ActiveDelivery {
  const ActiveDelivery({
    required this.job,
    required this.status,
    required this.orderItems,
    required this.orderNumber,
  });
  final DeliveryJob job;
  final DeliveryStage status;
  final List<String> orderItems;
  final String orderNumber;
  ActiveDelivery copyWith({DeliveryStage? status}) => ActiveDelivery(
    job: job,
    status: status ?? this.status,
    orderItems: orderItems,
    orderNumber: orderNumber,
  );
}

class EarningsRecord {
  const EarningsRecord({
    required this.deliveryId,
    required this.amount,
    required this.completedAt,
    required this.eateryName,
    required this.dropoffZone,
  });
  final String deliveryId;
  final int amount;
  final DateTime completedAt;

  /// Carried over from the job at the moment it's marked delivered — the
  /// job itself isn't kept once completed, so the Jobs screen's Completed
  /// tab needs these captured here rather than looked up after the fact.
  final String eateryName;
  final String dropoffZone;
}
