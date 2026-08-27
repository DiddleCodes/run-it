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

class DeliveryJob {
  const DeliveryJob({
    required this.id,
    required this.campusId,
    required this.eateryName,
    required this.eateryLocation,
    required this.dropoffZone,
    required this.dropoffLocation,
    required this.payoutAmount,
    required this.estimatedDistanceMeters,
    required this.offeredAt,
    required this.expiresAt,
  });
  final String id;

  /// The campus the originating eatery belongs to — a runner may only be
  /// offered and may only accept jobs where this matches their own campus.
  final String campusId;
  final String eateryName;
  final String eateryLocation;
  final String dropoffZone;
  final String dropoffLocation;
  final int payoutAmount;
  final int estimatedDistanceMeters;
  final DateTime offeredAt;
  final DateTime expiresAt;
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
