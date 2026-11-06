/// Canonical CRM UI types — mirrors NEXTX `UITYPE_OPTIONS` plus gallery extras.
enum FieldUiType {
  text,
  longText,
  richText,
  link,
  address,
  addressMap,
  enumeration,
  picklist,
  radioGroup,
  emotionalEmoji,
  picklistUser,
  multiSelect,
  multiPicklistUser,
  email,
  phone,
  date,
  dateTime,
  time,
  file,
  number,
  currency,
  yesNo,
  tag,
  leadSelect,
  accountSelect,
  contactSelect,
  productSelect,
  serviceSelect,
  quotationSelect,
  assetSelect,
  jobSelect,
  locationSelect,
  caseSelect,
  contractSelect,
  licenseArea,
  color,
  percent,
  duration,
  dateRange,
  monthRange,
  yearRange,
  monthPicker,
  yearPicker,
  drawing,
  image,
  latLong,
  video,
  post,
  xy,
  progress,
  counter,
  app,
  owner,
  assignTo,
  taxId,
  inspectionSelect,
  skillSelect,
}

/// 52 values from `UITYPE_OPTIONS` — tests must cover every one.
const List<String> kUitypeOptionValues = [
  'Text',
  'LongText',
  'RichText',
  'Link',
  'Address',
  'AddressMap',
  'Enum',
  'Picklist',
  'RadioGroup',
  'EmotionalEmoji',
  'PicklistUser',
  'MultiSelect',
  'MultiPicklistUser',
  'Email',
  'Phone',
  'Date',
  'DateTime',
  'Time',
  'File',
  'Number',
  'Currency',
  'YesNo',
  'Tag',
  'LeadSelect',
  'AccountSelect',
  'ContactSelect',
  'ProductSelect',
  'ServiceSelect',
  'QuotationSelect',
  'AssetSelect',
  'JobSelect',
  'LocationSelect',
  'CaseSelect',
  'ContractSelect',
  'LicenseArea',
  'Color',
  'Percent',
  'Duration',
  'DateRange',
  'MonthRange',
  'YearRange',
  'MonthPicker',
  'YearPicker',
  'Drawing',
  'Image',
  'LatLong',
  'Video',
  'Post',
  'XY',
  'Progress',
  'Counter',
  'App',
];

enum FieldUiGroup {
  text,
  number,
  datetime,
  select,
  location,
  media,
  relations,
}

extension FieldUiTypeX on FieldUiType {
  String get wireName {
    switch (this) {
      case FieldUiType.text:
        return 'Text';
      case FieldUiType.longText:
        return 'LongText';
      case FieldUiType.richText:
        return 'RichText';
      case FieldUiType.link:
        return 'Link';
      case FieldUiType.address:
        return 'Address';
      case FieldUiType.addressMap:
        return 'AddressMap';
      case FieldUiType.enumeration:
        return 'Enum';
      case FieldUiType.picklist:
        return 'Picklist';
      case FieldUiType.radioGroup:
        return 'RadioGroup';
      case FieldUiType.emotionalEmoji:
        return 'EmotionalEmoji';
      case FieldUiType.picklistUser:
        return 'PicklistUser';
      case FieldUiType.multiSelect:
        return 'MultiSelect';
      case FieldUiType.multiPicklistUser:
        return 'MultiPicklistUser';
      case FieldUiType.email:
        return 'Email';
      case FieldUiType.phone:
        return 'Phone';
      case FieldUiType.date:
        return 'Date';
      case FieldUiType.dateTime:
        return 'DateTime';
      case FieldUiType.time:
        return 'Time';
      case FieldUiType.file:
        return 'File';
      case FieldUiType.number:
        return 'Number';
      case FieldUiType.currency:
        return 'Currency';
      case FieldUiType.yesNo:
        return 'YesNo';
      case FieldUiType.tag:
        return 'Tag';
      case FieldUiType.leadSelect:
        return 'LeadSelect';
      case FieldUiType.accountSelect:
        return 'AccountSelect';
      case FieldUiType.contactSelect:
        return 'ContactSelect';
      case FieldUiType.productSelect:
        return 'ProductSelect';
      case FieldUiType.serviceSelect:
        return 'ServiceSelect';
      case FieldUiType.quotationSelect:
        return 'QuotationSelect';
      case FieldUiType.assetSelect:
        return 'AssetSelect';
      case FieldUiType.jobSelect:
        return 'JobSelect';
      case FieldUiType.locationSelect:
        return 'LocationSelect';
      case FieldUiType.caseSelect:
        return 'CaseSelect';
      case FieldUiType.contractSelect:
        return 'ContractSelect';
      case FieldUiType.licenseArea:
        return 'LicenseArea';
      case FieldUiType.color:
        return 'Color';
      case FieldUiType.percent:
        return 'Percent';
      case FieldUiType.duration:
        return 'Duration';
      case FieldUiType.dateRange:
        return 'DateRange';
      case FieldUiType.monthRange:
        return 'MonthRange';
      case FieldUiType.yearRange:
        return 'YearRange';
      case FieldUiType.monthPicker:
        return 'MonthPicker';
      case FieldUiType.yearPicker:
        return 'YearPicker';
      case FieldUiType.drawing:
        return 'Drawing';
      case FieldUiType.image:
        return 'Image';
      case FieldUiType.latLong:
        return 'LatLong';
      case FieldUiType.video:
        return 'Video';
      case FieldUiType.post:
        return 'Post';
      case FieldUiType.xy:
        return 'XY';
      case FieldUiType.progress:
        return 'Progress';
      case FieldUiType.counter:
        return 'Counter';
      case FieldUiType.app:
        return 'App';
      case FieldUiType.owner:
        return 'Owner';
      case FieldUiType.assignTo:
        return 'AssignTo';
      case FieldUiType.taxId:
        return 'taxid';
      case FieldUiType.inspectionSelect:
        return 'InspectionSelect';
      case FieldUiType.skillSelect:
        return 'SkillSelect';
    }
  }

  FieldUiGroup get group {
    switch (this) {
      case FieldUiType.text:
      case FieldUiType.longText:
      case FieldUiType.richText:
      case FieldUiType.email:
      case FieldUiType.phone:
      case FieldUiType.link:
      case FieldUiType.taxId:
        return FieldUiGroup.text;
      case FieldUiType.number:
      case FieldUiType.currency:
      case FieldUiType.percent:
      case FieldUiType.progress:
      case FieldUiType.duration:
      case FieldUiType.counter:
        return FieldUiGroup.number;
      case FieldUiType.date:
      case FieldUiType.dateTime:
      case FieldUiType.time:
      case FieldUiType.dateRange:
      case FieldUiType.monthRange:
      case FieldUiType.yearRange:
      case FieldUiType.monthPicker:
      case FieldUiType.yearPicker:
        return FieldUiGroup.datetime;
      case FieldUiType.enumeration:
      case FieldUiType.picklist:
      case FieldUiType.radioGroup:
      case FieldUiType.emotionalEmoji:
      case FieldUiType.picklistUser:
      case FieldUiType.multiSelect:
      case FieldUiType.multiPicklistUser:
      case FieldUiType.yesNo:
      case FieldUiType.tag:
        return FieldUiGroup.select;
      case FieldUiType.address:
      case FieldUiType.addressMap:
      case FieldUiType.licenseArea:
      case FieldUiType.latLong:
      case FieldUiType.xy:
        return FieldUiGroup.location;
      case FieldUiType.file:
      case FieldUiType.image:
      case FieldUiType.video:
      case FieldUiType.drawing:
      case FieldUiType.color:
      case FieldUiType.post:
        return FieldUiGroup.media;
      case FieldUiType.owner:
      case FieldUiType.assignTo:
      case FieldUiType.app:
      case FieldUiType.leadSelect:
      case FieldUiType.accountSelect:
      case FieldUiType.contactSelect:
      case FieldUiType.productSelect:
      case FieldUiType.serviceSelect:
      case FieldUiType.quotationSelect:
      case FieldUiType.assetSelect:
      case FieldUiType.jobSelect:
      case FieldUiType.locationSelect:
      case FieldUiType.caseSelect:
      case FieldUiType.contractSelect:
      case FieldUiType.inspectionSelect:
      case FieldUiType.skillSelect:
        return FieldUiGroup.relations;
    }
  }

  String get groupLabelTh {
    switch (group) {
      case FieldUiGroup.text:
        return 'ข้อความและลิงก์';
      case FieldUiGroup.number:
        return 'ตัวเลขและค่าวัด';
      case FieldUiGroup.datetime:
        return 'วันที่และเวลา';
      case FieldUiGroup.select:
        return 'ตัวเลือกและสถานะ';
      case FieldUiGroup.location:
        return 'ที่อยู่และพิกัด';
      case FieldUiGroup.media:
        return 'ไฟล์และสื่อ';
      case FieldUiGroup.relations:
        return 'CRM และความสัมพันธ์';
    }
  }

  IconDataSpec get icon {
    switch (this) {
      case FieldUiType.email:
        return IconDataSpec.email;
      case FieldUiType.phone:
        return IconDataSpec.phone;
      case FieldUiType.link:
        return IconDataSpec.link;
      case FieldUiType.date:
      case FieldUiType.dateTime:
      case FieldUiType.dateRange:
      case FieldUiType.monthRange:
      case FieldUiType.yearRange:
      case FieldUiType.monthPicker:
      case FieldUiType.yearPicker:
        return IconDataSpec.calendar;
      case FieldUiType.time:
        return IconDataSpec.time;
      case FieldUiType.enumeration:
      case FieldUiType.picklist:
      case FieldUiType.radioGroup:
      case FieldUiType.app:
        return IconDataSpec.chevron;
      case FieldUiType.latLong:
      case FieldUiType.xy:
      case FieldUiType.addressMap:
        return IconDataSpec.pin;
      case FieldUiType.file:
      case FieldUiType.image:
      case FieldUiType.video:
        return IconDataSpec.clip;
      default:
        return IconDataSpec.none;
    }
  }

  String? get entityModule {
    switch (this) {
      case FieldUiType.leadSelect:
        return 'lead';
      case FieldUiType.accountSelect:
        return 'account';
      case FieldUiType.contactSelect:
        return 'contact';
      case FieldUiType.productSelect:
        return 'product';
      case FieldUiType.serviceSelect:
        return 'service';
      case FieldUiType.quotationSelect:
        return 'quotation';
      case FieldUiType.assetSelect:
        return 'asset';
      case FieldUiType.jobSelect:
        return 'job';
      case FieldUiType.locationSelect:
        return 'service_location';
      case FieldUiType.caseSelect:
        return 'case';
      case FieldUiType.contractSelect:
        return 'service_contract';
      case FieldUiType.inspectionSelect:
        return 'inspection';
      case FieldUiType.skillSelect:
        return 'skill';
      default:
        return null;
    }
  }

  bool get isSingleSelect =>
      this == FieldUiType.enumeration ||
      this == FieldUiType.picklist ||
      this == FieldUiType.radioGroup ||
      this == FieldUiType.app;

  bool get isUserSelect =>
      this == FieldUiType.picklistUser ||
      this == FieldUiType.owner ||
      this == FieldUiType.assignTo ||
      this == FieldUiType.multiPicklistUser;

  bool get isMulti =>
      this == FieldUiType.multiSelect ||
      this == FieldUiType.multiPicklistUser ||
      this == FieldUiType.tag;

  bool get usesBareTextField =>
      this == FieldUiType.text ||
      this == FieldUiType.longText ||
      this == FieldUiType.richText ||
      this == FieldUiType.email ||
      this == FieldUiType.phone ||
      this == FieldUiType.link ||
      this == FieldUiType.taxId ||
      this == FieldUiType.number ||
      this == FieldUiType.currency ||
      this == FieldUiType.duration ||
      this == FieldUiType.counter ||
      this == FieldUiType.address;
}

enum IconDataSpec { none, email, phone, link, calendar, time, chevron, pin, clip }

const Map<String, FieldUiType> _byWire = {
  'text': FieldUiType.text,
  'longtext': FieldUiType.longText,
  'textarea': FieldUiType.longText,
  'richtext': FieldUiType.richText,
  'link': FieldUiType.link,
  'url': FieldUiType.link,
  'address': FieldUiType.address,
  'addressmap': FieldUiType.addressMap,
  'enum': FieldUiType.enumeration,
  'picklist': FieldUiType.picklist,
  'radiogroup': FieldUiType.radioGroup,
  'emotionalemoji': FieldUiType.emotionalEmoji,
  'picklistuser': FieldUiType.picklistUser,
  'multiselect': FieldUiType.multiSelect,
  'multipicklistuser': FieldUiType.multiPicklistUser,
  'email': FieldUiType.email,
  'phone': FieldUiType.phone,
  'tel': FieldUiType.phone,
  'date': FieldUiType.date,
  'datetime': FieldUiType.dateTime,
  'time': FieldUiType.time,
  'file': FieldUiType.file,
  'number': FieldUiType.number,
  'decimal': FieldUiType.number,
  'integer': FieldUiType.number,
  'int': FieldUiType.number,
  'currency': FieldUiType.currency,
  'price': FieldUiType.currency,
  'money': FieldUiType.currency,
  'yesno': FieldUiType.yesNo,
  'checkbox': FieldUiType.yesNo,
  'boolean': FieldUiType.yesNo,
  'toggle': FieldUiType.yesNo,
  'tag': FieldUiType.tag,
  'tags': FieldUiType.tag,
  'leadselect': FieldUiType.leadSelect,
  'accountselect': FieldUiType.accountSelect,
  'contactselect': FieldUiType.contactSelect,
  'productselect': FieldUiType.productSelect,
  'serviceselect': FieldUiType.serviceSelect,
  'quotationselect': FieldUiType.quotationSelect,
  'assetselect': FieldUiType.assetSelect,
  'jobselect': FieldUiType.jobSelect,
  'locationselect': FieldUiType.locationSelect,
  'caseselect': FieldUiType.caseSelect,
  'contractselect': FieldUiType.contractSelect,
  'licensearea': FieldUiType.licenseArea,
  'color': FieldUiType.color,
  'percent': FieldUiType.percent,
  'duration': FieldUiType.duration,
  'daterange': FieldUiType.dateRange,
  'monthrange': FieldUiType.monthRange,
  'yearrange': FieldUiType.yearRange,
  'monthpicker': FieldUiType.monthPicker,
  'yearpicker': FieldUiType.yearPicker,
  'drawing': FieldUiType.drawing,
  'image': FieldUiType.image,
  'latlong': FieldUiType.latLong,
  'video': FieldUiType.video,
  'post': FieldUiType.post,
  'xy': FieldUiType.xy,
  'progress': FieldUiType.progress,
  'counter': FieldUiType.counter,
  'app': FieldUiType.app,
  'owner': FieldUiType.owner,
  'assignto': FieldUiType.assignTo,
  'assign_to': FieldUiType.assignTo,
  'taxid': FieldUiType.taxId,
  'inspectionselect': FieldUiType.inspectionSelect,
  'skillselect': FieldUiType.skillSelect,
};

FieldUiType? fieldUiTypeFromName(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  return _byWire[raw.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]'), '')] ??
      _byWire[raw.trim().toLowerCase()];
}

FieldUiType resolveFieldUiType(Map<String, dynamic> field) {
  final uitype = fieldUiTypeFromName(field['uitype']?.toString());
  if (uitype != null) return uitype;
  final type = fieldUiTypeFromName(field['type']?.toString());
  if (type != null) return type;
  final input = fieldUiTypeFromName(
    field['inputType']?.toString() ?? field['input_type']?.toString(),
  );
  if (input != null) return input;
  final col = (field['name'] ?? field['columnname'] ?? field['key'] ?? '')
      .toString()
      .toLowerCase();
  if (col == 'smownerid' || col == 'owner') return FieldUiType.owner;
  if (col == 'assign_to' || col == 'assigned_user_id' || col == 'assignto') {
    return FieldUiType.assignTo;
  }
  if (col == 'taxid' || col == 'tax_id') return FieldUiType.taxId;
  return FieldUiType.text;
}

bool fieldIsRequired(Map<String, dynamic> field) {
  final req = field['required'];
  if (req == true || req == 1 || req == '1') return true;
  if (field['mandatory'] == true || field['mandatory'] == 1) return true;
  final t = field['typeofdata']?.toString() ?? '';
  return t.contains('~M');
}

bool fieldIsReadonly(Map<String, dynamic> field) {
  final access = field['access']?.toString().toLowerCase();
  if (access == 'readonly' || access == 'hidden') return true;
  return field['readonly'] == true || field['readonly'] == 1;
}

String fieldLabel(Map<String, dynamic> field) =>
    field['label_th']?.toString() ??
    field['label']?.toString() ??
    field['labelTh']?.toString() ??
    field['name']?.toString() ??
    '';

String fieldName(Map<String, dynamic> field) =>
    field['name']?.toString() ?? field['key']?.toString() ?? '';
