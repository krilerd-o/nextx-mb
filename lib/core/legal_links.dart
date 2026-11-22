import 'package:url_launcher/url_launcher.dart';

import 'i18n.dart';

/// Public pages on the MOAI NEXT web (the same URLs given to the App Store and Google Play).
/// One fixed site for every Space, so the store listing and the app always show the same text.
const kLegalSite = 'https://moainext.moai-crm.com';

enum LegalPage { privacy, terms, accountDeletion }

Uri legalUri(LegalPage page) {
  final path = switch (page) {
    LegalPage.privacy => 'privacy',
    LegalPage.terms => 'terms',
    LegalPage.accountDeletion => 'account-deletion',
  };
  return Uri.parse('$kLegalSite/$path${L10n.isEn ? '?lang=en' : ''}');
}

/// Tests replace this to see which page was opened.
Future<bool> Function(Uri uri) legalLauncher = (uri) => launchUrl(uri, mode: LaunchMode.inAppBrowserView);

Future<bool> openLegal(LegalPage page) async {
  try {
    return await legalLauncher(legalUri(page));
  } catch (_) {
    return false;
  }
}
