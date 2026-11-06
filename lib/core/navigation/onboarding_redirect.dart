import 'app_routes.dart';

/// Where the sign-in / setup flow should send the user, or null to stay.
///
/// welcome → server → login → business → package → role → tabs → app.
/// Once everything is set, the setup routes bounce to the main shell.
String? onboardingRedirect({
  required String loc,
  required bool ready,
  required bool loggedIn,
  required bool serverConfirmed,
  required bool hasBusiness,
  required bool hasPackage,
  required bool roleSetupDone,
}) {
  String? stay(Set<String> allowed, String fallback) => allowed.contains(loc) ? null : fallback;

  if (!ready) return stay({AppRoutes.splash}, AppRoutes.splash);
  if (!loggedIn) {
    return serverConfirmed
        ? stay({AppRoutes.login, AppRoutes.server, AppRoutes.welcome}, AppRoutes.login)
        : stay({AppRoutes.welcome, AppRoutes.server}, AppRoutes.welcome);
  }
  if (!hasBusiness) return stay({AppRoutes.hub}, AppRoutes.hub);
  if (!hasPackage) return stay({AppRoutes.package}, AppRoutes.package);
  if (!roleSetupDone) return stay({AppRoutes.roleSetup, AppRoutes.tabSetup}, AppRoutes.roleSetup);
  const setupOnly = {
    AppRoutes.splash,
    AppRoutes.welcome,
    AppRoutes.server,
    AppRoutes.login,
    AppRoutes.hub,
    AppRoutes.package,
    AppRoutes.roleSetup,
    AppRoutes.tabSetup,
    AppRoutes.gettingStarted,
  };
  return setupOnly.contains(loc) ? AppRoutes.mainShell : null;
}
