import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../network/api_config.dart';

/// Task 31: crash/error reporting.
///
/// Chose sentry_flutter over firebase_crashlytics despite firebase_core
/// already being a pubspec dependency (used for FCM push notifications on
/// the backend side) — that dependency is deceptive as a cost signal.
/// Firebase is not actually wired into this Flutter app at all: no
/// `Firebase.initializeApp()` call exists anywhere in `lib/`, no
/// google-services.json/GoogleService-Info.plist exists in android/ios,
/// and firebase_auth/cloud_firestore/firebase_storage (also pubspec
/// dependencies) are never imported by any file either. Adding Crashlytics
/// would mean standing up a real Firebase project and native platform
/// config from zero — there is no existing foundation to build on. Sentry
/// also already covers the backend (Task 31's other half), so one project
/// dashboard/account covers both sides instead of two.
///
/// `SentryFlutter.init` — not manual `FlutterError.onError` /
/// `PlatformDispatcher.instance.onError` assignment — is the documented
/// way to wire this up: it installs both handlers itself and runs
/// [appRunner] inside its own guarded zone, so assigning them here too
/// would either double-report or silently lose whichever handler runs
/// second.
Future<void> initializeCrashReporting({required VoidCallback appRunner}) async {
  if (sentryDsn.isEmpty) {
    debugPrint('SENTRY_DSN not configured — crash reporting is disabled for this build.');
    appRunner();
    return;
  }

  await SentryFlutter.init((options) {
    options.dsn = sentryDsn;
    options.environment = kReleaseMode ? 'production' : 'development';
    // Errors only, matching the backend's tracesSampleRate: 0 — this app
    // has no performance-monitoring requirement from Task 31, and leaving
    // tracing off keeps events limited to exactly what was asked for.
    options.tracesSampleRate = 0;
    // Off by default in the SDK already, but explicit: no IP address, no
    // device identifiers beyond what crash triage needs.
    options.sendDefaultPii = false;
    // Deliberately NOT adding SentryNavigatorObserver — GoRouter passes
    // real domain objects as route `extra` (order IDs, session tokens) in
    // several places in this app, and the navigator observer's default
    // breadcrumbs would otherwise capture route arguments verbatim. Task
    // 31 only asked for crash capture, not navigation breadcrumbs, so the
    // simplest way to guarantee no route-argument leakage is to not
    // install it at all.
    options.beforeSend = (event, hint) => _redact(event);
    options.beforeBreadcrumb = (breadcrumb, hint) =>
        breadcrumb == null ? null : _redactBreadcrumb(breadcrumb);
  }, appRunner: appRunner);
}

/// Defense in depth alongside the config above: strips anything that
/// could carry a token/OTP/photo URL even if it reached an event by some
/// path this file didn't anticipate (e.g. a future contributor logging a
/// request body into an exception message, or wrapping the HTTP client
/// with Sentry's breadcrumb client later). Request headers/cookies are
/// covered by `sendDefaultPii: false` already; dropping `request` entirely
/// covers the body too, which that flag does not — this app never
/// deliberately attaches request context to an event, so there is nothing
/// legitimate to preserve here.
SentryEvent _redact(SentryEvent event) {
  if (event.request == null) return event;
  event.request = null;
  return event;
}

Breadcrumb _redactBreadcrumb(Breadcrumb breadcrumb) {
  final data = breadcrumb.data;
  if (data == null) return breadcrumb;
  breadcrumb.data = Map<String, dynamic>.from(data)
    ..remove('data')
    ..remove('body')
    ..remove('headers')
    ..remove('cookies');
  return breadcrumb;
}
