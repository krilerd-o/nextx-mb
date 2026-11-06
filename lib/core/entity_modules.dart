/// Entity module slugs used by CRM / FSM lists and deep links.
class EntityModules {
  EntityModules._();

  static const lead = 'lead';
  static const contact = 'contact';
  static const account = 'account';
  static const deal = 'deal';
  static const quotation = 'quotation';
  static const caseModule = 'case';
  static const product = 'product';
  static const service = 'service';
  static const job = 'job';
  static const inspection = 'inspection';
  static const serviceContract = 'service_contract';
  static const asset = 'asset';
  static const serviceLocation = 'service_location';
  static const skill = 'skill';
  static const activity = 'activity';

  static const fsm = {
    job,
    inspection,
    serviceContract,
    asset,
    serviceLocation,
    skill,
  };

  static const titles = <String, String>{
    lead: 'ผู้มุ่งหวัง',
    contact: 'ผู้ติดต่อ',
    account: 'บัญชีลูกค้า',
    deal: 'ดีล',
    quotation: 'ใบเสนอราคา',
    caseModule: 'เคส',
    product: 'สินค้า',
    service: 'บริการ',
    job: 'ใบสั่งงาน',
    inspection: 'ใบตรวจรับ',
    serviceContract: 'สัญญาบริการ',
    asset: 'สินทรัพย์',
    serviceLocation: 'พื้นที่บริการ',
    skill: 'ทักษะ',
    activity: 'กิจกรรม',
  };

  static bool isFsm(String module) => fsm.contains(normalize(module));

  static String normalize(String module) {
    switch (module) {
      case 'service-contract':
        return serviceContract;
      case 'service-location':
        return serviceLocation;
      default:
        return module;
    }
  }

  static String titleOf(String module) {
    final key = normalize(module);
    return titles[key] ?? module;
  }

  static String menuKeyOf(String module) {
    switch (normalize(module)) {
      case caseModule:
        return 'case';
      case serviceContract:
        return 'service-contract';
      case serviceLocation:
        return 'service-location';
      case activity:
        return 'calendar';
      default:
        return normalize(module);
    }
  }
}
