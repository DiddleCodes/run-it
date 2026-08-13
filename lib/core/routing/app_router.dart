import 'package:go_router/go_router.dart';
import '../../features/auth/presentation/phone_auth_screen.dart';
import '../../features/campus/presentation/campus_select_screen.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/splash/presentation/splash_screen.dart';

abstract class AppRoutes {
  AppRoutes._();

  static const splash = '/';
  static const onboarding = '/onboarding';
  static const phoneAuth = '/auth/phone';
  static const campusSelect = '/campus-select';
}

final appRouter = GoRouter(
  initialLocation: AppRoutes.splash,
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
      path: AppRoutes.phoneAuth,
      builder: (context, state) => const PhoneAuthScreen(),
    ),
    GoRoute(
      path: AppRoutes.campusSelect,
      builder: (context, state) => const CampusSelectScreen(),
    ),
  ],
);
