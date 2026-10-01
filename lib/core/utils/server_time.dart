/// Backend timestamps are ISO-8601 in UTC ("2026-10-01T08:30:00.000Z").
/// Everything the app shows is in the phone's own time zone — Lagos for
/// RUN-It's users — so every server timestamp is converted here, once,
/// as it's parsed, rather than at each screen that formats it.
DateTime parseServerTime(String value) => DateTime.parse(value).toLocal();

DateTime? parseServerTimeOrNull(Object? value) => value == null ? null : parseServerTime(value as String);
