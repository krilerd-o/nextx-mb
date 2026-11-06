import '../../core/entity_modules.dart';
import '../../core/menu_access.dart';
import '../../core/session_state.dart';

const kGlobalSearchModules = [
  'lead',
  'contact',
  'account',
  'case',
  'deal',
  'activity',
  'job',
  'quotation',
  'product',
  'service',
  'inspection',
  'service_contract',
  'asset',
  'service_location',
  'skill',
];

List<String> globalSearchModulesFor(SessionState session) {
  return kGlobalSearchModules
      .where((m) => MenuAccess.allow(session, EntityModules.menuKeyOf(m)))
      .toList();
}
