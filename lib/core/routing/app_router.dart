import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/domain/auth_models.dart';
import '../../features/auth/presentation/account_type_screen.dart';
import '../../features/auth/presentation/biometric_setup_screen.dart';
import '../../features/auth/presentation/kyc/kyc_capture_screen.dart';
import '../../features/auth/presentation/kyc/kyc_intro_screen.dart';
import '../../features/auth/presentation/kyc/kyc_status_screen.dart';
import '../../features/auth/presentation/otp_screen.dart';
import '../../features/auth/presentation/kyc/runner_type_screen.dart';
import '../../features/auth/presentation/set_passcode_screen.dart';
import '../../features/auth/presentation/signup_screen.dart';
import '../../features/auth/presentation/verify_email_screen.dart';
import '../../features/auth/presentation/welcome_back_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/ordering/presentation/my_orders_screen.dart';
import '../../features/ordering/presentation/ordering_screens.dart';
import '../../features/payout/presentation/payout_account_screen.dart';
import '../../features/profile/presentation/run_it_plus_screen.dart';
import '../../features/profile/presentation/student_profile_screen.dart';
import '../../features/runner/presentation/runner_jobs_screen.dart';
import '../../features/runner/presentation/runner_messages_screen.dart';
import '../../features/runner/presentation/runner_profile_screen.dart';
import '../../features/runner/presentation/runner_scan_screen.dart';
import '../../features/runner/presentation/runner_screens.dart';
import '../../features/splash/presentation/splash_screen.dart';
import '../../features/vendor/domain/vendor_dashboard_models.dart';
import '../../features/vendor/presentation/restaurant_menu_screen.dart';
import '../../features/vendor/presentation/restaurant_metrics_screen.dart';
import '../../features/vendor/presentation/restaurant_orders_screen.dart';
import '../../features/vendor/presentation/restaurant_profile_screen.dart';
import '../../features/vendor/presentation/restaurant_profile_setup_screen.dart';
import '../../features/vendor/presentation/vendor_application_screen.dart';
import '../../features/wallet/presentation/wallet_screen.dart';
import '../widgets/app_nav_shell.dart';

/// Where a user who just finished OTP verification belongs — used by the
/// OTP route's `extra`-loss fallback (see its `builder`) to mirror what
/// `OtpScreen._submit` itself would have navigated to. Every fresh signup
/// — student or runner — goes to Set Passcode next; it's the same
/// screen/logic for both, only what comes *after* biometrics differs (see
/// [postBiometricDestination]).
String _postSignupDestination(UserProfile user) =>
    user.passcodeSet ? postAuthDestination(user) : AppRoutes.setPasscode;

/// Where Set Passcode / Biometric Setup hand off once biometrics are set
/// up or skipped — those two screens are shared verbatim between all
/// three account types, so only this destination differs: students land
/// on Home, runners continue on to pick a runner type before KYC capture,
/// and restaurants continue into the vendor-application wizard (Business
/// Info is its first step).
String postBiometricDestination(AccountType accountType) =>
    switch (accountType) {
      AccountType.runner => AppRoutes.runnerType,
      AccountType.restaurant => AppRoutes.vendorApplication,
      AccountType.student => AppRoutes.home,
    };

/// Where a *returning* user belongs once their session is established —
/// used by splash (session already restored) and by passcode/biometric
/// login on [WelcomeBackScreen]. Distinct from [_postSignupDestination]:
/// a returning runner — Verified or not — goes straight into the runner
/// shell, not back into the KYC intro/capture wizard; the shell itself
/// degrades for a non-Verified runner (read-only Jobs, a Pending-review
/// Profile state) rather than parking them on a standalone status screen.
/// A returning student always has a passcode already (that's how they got
/// a session), so they always land on home.
///
/// A returning restaurant always lands on Profile Setup (Task 12) — never
/// directly on the shell — because that screen itself checks the real
/// backend (`GET /vendors/me`) and either confirms an already-complete
/// profile straight through to [AppRoutes.restaurantOrders] or, for the
/// rare case of an app kill between wizard submission and finishing setup,
/// picks up exactly where they left off. That self-healing check is
/// simpler and more honest than caching a second local "is setup done"
/// flag here that could drift from what the backend actually has.
String postAuthDestination(UserProfile user) => switch (user.accountType) {
  AccountType.runner => AppRoutes.runnerHome,
  AccountType.restaurant => AppRoutes.restaurantProfileSetup,
  AccountType.student => AppRoutes.home,
};

abstract class AppRoutes {
  AppRoutes._();

  static const splash = '/';
  static const onboarding = '/onboarding';
  static const login = '/auth/login';
  static const accountType = '/auth/account-type';
  static const signup = '/auth/signup';
  static const verifyEmail = '/auth/verify-email';
  static const otp = '/auth/otp';
  static const setPasscode = '/auth/set-passcode';
  static const biometricSetup = '/auth/biometric-setup';
  static const runnerType = '/kyc/runner-type';
  static const kycIntro = '/kyc/intro';
  static const kycCapture = '/kyc/capture';
  static const kycStatus = '/kyc/status';
  static const home = '/home';
  static const menu = '/menu';
  static const basket = '/basket';
  static const checkout = '/checkout';
  static const orderTracking = '/order-tracking';
  static const studentOrders = '/orders';
  static const studentWallet = '/wallet';
  static const studentProfile = '/profile';
  static const runItPlus = '/plus';
  static const runnerHome = '/runner';
  static const runnerOffer = '/runner/offer';
  static const runnerDelivery = '/runner/delivery';
  static const earnings = '/runner/earnings';
  static const runnerJobs = '/runner/jobs';
  static const runnerScan = '/runner/scan';
  static const runnerMessages = '/runner/messages';
  static const runnerProfile = '/runner/profile';
  static const payoutAccount = '/payout-account';
  static const vendorApplication = '/vendor/apply';
  static const restaurantProfileSetup = '/vendor/profile-setup';
  static const restaurantOrders = '/restaurant/orders';
  static const restaurantMenu = '/restaurant/menu';
  static const restaurantMenuAdd = '/restaurant/menu/add';
  static const restaurantMenuEdit = '/restaurant/menu/edit';
  static const restaurantMetrics = '/restaurant/metrics';
  static const restaurantProfile = '/restaurant/profile';

  static const _publicRoutes = {
    splash,
    onboarding,
    login,
    accountType,
    signup,
    verifyEmail,
    otp,
  };

  /// Reachable the instant a runner account exists, KYC status regardless
  /// — TASK 4g §1: "account exists, earning doesn't, until cleared".
  /// Each of these screens degrades itself for a non-Verified runner
  /// (read-only Jobs, a Pending-review Profile state, no "go online" on
  /// Home) rather than being hidden behind a hard redirect.
  static const _runnerShellRoutes = {
    runnerHome,
    runnerJobs,
    runnerMessages,
    runnerProfile,
  };

  /// Only reachable once Verified — these all presuppose either an
  /// already-accepted job (offer/delivery/scan) or completed deliveries
  /// (earnings), neither of which a non-Verified runner can ever produce
  /// since [RunnerController] itself refuses to go online/accept jobs for
  /// them — this is defense-in-depth against a direct deep link, not the
  /// primary gate.
  static const _runnerVerifiedOnlyRoutes = {
    runnerOffer,
    runnerDelivery,
    earnings,
    runnerScan,
  };

  /// The student main-screen shell — mirrors [_runnerShellRoutes] one tier
  /// up, so a restaurant account (which has neither) can be kept off both.
  static const _studentShellRoutes = {
    home,
    studentOrders,
    studentWallet,
    studentProfile,
  };

  /// The Restaurant Dashboard shell — Task 12's mirror of
  /// [_runnerShellRoutes]/[_studentShellRoutes].
  static const _restaurantShellRoutes = {
    restaurantOrders,
    restaurantMenu,
    restaurantMetrics,
    restaurantProfile,
  };

  /// Every mobile surface a restaurant account has any business reaching —
  /// the wizard, first-run profile setup, the dashboard shell, and the
  /// (not shell-wrapped, same treatment as the runner's Scan screen)
  /// Add/Edit Menu Item screens.
  static const _vendorOnlyRoutes = {
    vendorApplication,
    restaurantProfileSetup,
    restaurantMenuAdd,
    restaurantMenuEdit,
    ..._restaurantShellRoutes,
  };
}

/// Bridges Riverpod's auth state to go_router's `refreshListenable`, so a
/// login/logout/KYC-status change re-evaluates every route's `redirect`
/// immediately rather than only on the next navigation attempt.
class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(Ref ref) {
    ref.listen(authControllerProvider, (previous, next) => notifyListeners());
  }
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthRefreshNotifier(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final session = ref.read(authControllerProvider);
      final loc = state.matchedLocation;
      final isPublic = AppRoutes._publicRoutes.contains(loc);

      if (session == null) {
        return isPublic ? null : AppRoutes.accountType;
      }

      // Already signed in — don't let them linger on the pre-auth screens.
      // accountType/signup/verifyEmail/otp are excluded like splash: that
      // group is reached via context.push (a Navigator stack on top of the
      // last context.go location), so refreshListenable-triggered
      // redirects — fired the instant OTP verification sets the session —
      // see matchedLocation still pointing at accountType (the last .go()
      // target), not the pushed otp page actually on screen. Without this
      // exclusion that stale match sends every fresh signup straight to
      // home, unmounting OtpScreen before its own explicit
      // context.go(...) call ever runs.
      final exemptFromHomeKick = {
        AppRoutes.splash,
        AppRoutes.accountType,
        AppRoutes.signup,
        AppRoutes.verifyEmail,
        AppRoutes.otp,
      };
      final user = session.user;
      if (isPublic && !exemptFromHomeKick.contains(loc)) {
        return postAuthDestination(user);
      }

      switch (user.accountType) {
        case AccountType.runner:
          // A runner can always reach the shell (Home/Jobs/Messages/
          // Profile) — each degrades itself for a non-Verified runner
          // (read-only Jobs, a Pending-review Profile state) rather than
          // being hidden behind a hard redirect. Only screens that
          // presuppose an actual accepted job or earnings history stay
          // hard-gated on Verified.
          if (AppRoutes._runnerVerifiedOnlyRoutes.contains(loc) &&
              !user.canAccessRunnerJobs) {
            return AppRoutes.kycStatus;
          }
        case AccountType.restaurant:
          // A restaurant account has no business on the runner or student
          // shells — its own mobile surface is the vendor wizard, first-run
          // profile setup, and the Restaurant Dashboard shell (Task 12).
          if (AppRoutes._runnerShellRoutes.contains(loc) ||
              AppRoutes._runnerVerifiedOnlyRoutes.contains(loc) ||
              AppRoutes._studentShellRoutes.contains(loc)) {
            return AppRoutes.restaurantProfileSetup;
          }
        case AccountType.student:
          // A student account has no business on any runner or vendor
          // screen.
          if (AppRoutes._runnerShellRoutes.contains(loc) ||
              AppRoutes._runnerVerifiedOnlyRoutes.contains(loc) ||
              AppRoutes._vendorOnlyRoutes.contains(loc)) {
            return AppRoutes.home;
          }
      }

      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const WelcomeBackScreen(),
      ),
      GoRoute(
        path: AppRoutes.accountType,
        builder: (context, state) => const AccountTypeScreen(),
      ),
      GoRoute(
        path: AppRoutes.signup,
        // `extra` is only ever attached to the imperative push() call that
        // navigated here. A refreshListenable-triggered rebuild (e.g. the
        // auth-state change fired mid-OTP-verification) re-invokes this
        // `builder` directly — bypassing `redirect` entirely — with a
        // fresh `GoRouterState` that carries no `extra`. Since there's no
        // account type to recover in that case, bounce back to the choice
        // screen instead of crashing on the null check.
        builder: (context, state) {
          final extra = state.extra;
          if (extra is! AccountType) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) context.go(AppRoutes.accountType);
            });
            return const SizedBox.shrink();
          }
          return SignupScreen(accountType: extra);
        },
      ),
      GoRoute(
        path: AppRoutes.verifyEmail,
        // Same `extra`-loss pattern as signup/otp below.
        builder: (context, state) {
          final extra = state.extra;
          if (extra is! SignupArgs) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) context.go(AppRoutes.accountType);
            });
            return const SizedBox.shrink();
          }
          return VerifyEmailScreen(args: extra);
        },
      ),
      GoRoute(
        path: AppRoutes.otp,
        builder: (context, state) {
          final extra = state.extra;
          if (extra is! SignupArgs) {
            // Same `extra`-loss pattern as signup above — but here we can
            // do better than bouncing to a blank screen: the session set
            // just before this rebuild fired tells us exactly where this
            // user should have ended up.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!context.mounted) return;
              final session = ref.read(authControllerProvider);
              context.go(
                session == null
                    ? AppRoutes.accountType
                    : _postSignupDestination(session.user),
              );
            });
            return const SizedBox.shrink();
          }
          return OtpScreen(args: extra);
        },
      ),
      GoRoute(
        path: AppRoutes.setPasscode,
        builder: (context, state) => const SetPasscodeScreen(),
      ),
      GoRoute(
        path: AppRoutes.biometricSetup,
        builder: (context, state) => const BiometricSetupScreen(),
      ),
      GoRoute(
        path: AppRoutes.runnerType,
        builder: (context, state) => const RunnerTypeScreen(),
      ),
      GoRoute(
        path: AppRoutes.kycIntro,
        builder: (context, state) => const KycIntroScreen(),
      ),
      GoRoute(
        path: AppRoutes.kycCapture,
        builder: (context, state) => const KycCaptureScreen(),
      ),
      GoRoute(
        path: AppRoutes.kycStatus,
        builder: (context, state) => const KycStatusScreen(),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const StudentShell(child: HomeScreen()),
      ),
      GoRoute(
        path: AppRoutes.studentOrders,
        builder: (context, state) =>
            const StudentShell(child: MyOrdersScreen()),
      ),
      GoRoute(
        path: AppRoutes.studentWallet,
        builder: (context, state) => const StudentShell(child: WalletScreen()),
      ),
      GoRoute(
        path: AppRoutes.studentProfile,
        builder: (context, state) =>
            const StudentShell(child: StudentProfileScreen()),
      ),
      // A visual placeholder only (no real subscription/billing) — pushed
      // on top rather than shell-wrapped, same treatment as any other
      // one-off destination reached from Profile.
      GoRoute(
        path: AppRoutes.runItPlus,
        builder: (context, state) => const RunItPlusScreen(),
      ),
      // Task 14: `extra` is the real vendor id tapped on Home — `null`
      // (e.g. the closing screen's "Order again") means "whatever vendor
      // is already selected", not "pick one for me" — see
      // EateryMenuScreen's own doc comment.
      GoRoute(
        path: AppRoutes.menu,
        builder: (context, state) => EateryMenuScreen(vendorId: state.extra as String?),
      ),
      GoRoute(
        path: AppRoutes.basket,
        builder: (context, state) => const BasketScreen(),
      ),
      GoRoute(
        path: AppRoutes.checkout,
        builder: (context, state) => const CheckoutScreen(),
      ),
      GoRoute(
        path: AppRoutes.orderTracking,
        builder: (context, state) => const OrderTrackingScreen(),
      ),
      GoRoute(
        path: AppRoutes.runnerHome,
        builder: (context, state) =>
            const RunnerShell(child: RunnerHomeScreen()),
      ),
      GoRoute(
        path: AppRoutes.runnerOffer,
        builder: (context, state) => const JobOfferScreen(),
      ),
      GoRoute(
        path: AppRoutes.runnerDelivery,
        builder: (context, state) => const ActiveDeliveryScreen(),
      ),
      GoRoute(
        path: AppRoutes.earnings,
        builder: (context, state) => const RunnerShell(child: EarningsScreen()),
      ),
      GoRoute(
        path: AppRoutes.runnerJobs,
        builder: (context, state) =>
            const RunnerShell(child: RunnerJobsScreen()),
      ),
      // Deliberately not RunnerShell-wrapped: a full-screen camera
      // viewfinder shouldn't sit under a persistent bottom nav — same
      // treatment as runnerOffer/runnerDelivery above.
      GoRoute(
        path: AppRoutes.runnerScan,
        builder: (context, state) => const RunnerScanScreen(),
      ),
      GoRoute(
        path: AppRoutes.runnerMessages,
        builder: (context, state) =>
            const RunnerShell(child: RunnerMessagesScreen()),
      ),
      GoRoute(
        path: AppRoutes.runnerProfile,
        builder: (context, state) =>
            const RunnerShell(child: RunnerProfileScreen()),
      ),
      GoRoute(
        path: AppRoutes.payoutAccount,
        builder: (context, state) => const PayoutAccountScreen(),
      ),
      GoRoute(
        path: AppRoutes.vendorApplication,
        builder: (context, state) => const VendorApplicationScreen(),
      ),
      GoRoute(
        path: AppRoutes.restaurantProfileSetup,
        builder: (context, state) => const RestaurantProfileSetupScreen(),
      ),
      GoRoute(
        path: AppRoutes.restaurantOrders,
        builder: (context, state) =>
            const RestaurantShell(child: RestaurantOrdersScreen()),
      ),
      GoRoute(
        path: AppRoutes.restaurantMenu,
        builder: (context, state) =>
            const RestaurantShell(child: RestaurantMenuScreen()),
      ),
      GoRoute(
        path: AppRoutes.restaurantMenuAdd,
        builder: (context, state) => const RestaurantMenuEditScreen(),
      ),
      GoRoute(
        path: AppRoutes.restaurantMenuEdit,
        builder: (context, state) {
          final extra = state.extra;
          return RestaurantMenuEditScreen(item: extra is VendorMenuItem ? extra : null);
        },
      ),
      GoRoute(
        path: AppRoutes.restaurantMetrics,
        builder: (context, state) =>
            const RestaurantShell(child: RestaurantMetricsScreen()),
      ),
      GoRoute(
        path: AppRoutes.restaurantProfile,
        builder: (context, state) =>
            const RestaurantShell(child: RestaurantProfileScreen()),
      ),
    ],
  );
});
