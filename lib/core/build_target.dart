/// Which store this build is for, set at build time:
/// `--dart-define=NX_STORE=google` (Play Store + iOS, default) or
/// `--dart-define=NX_STORE=huawei` (Huawei AppGallery, phones without
/// Google services: HMS push, OpenStreetMap).
const String kStore = String.fromEnvironment('NX_STORE', defaultValue: 'google');

bool get isHuaweiBuild => kStore == 'huawei';
