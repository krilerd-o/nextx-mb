# ส่งแอปขึ้น Google Play · App Store · Huawei AppGallery

แอปชุดเดียว บิลด์ได้ 2 แบบ:

| บิลด์ | ใช้กับ | Push | แผนที่ | เข้าสู่ระบบ |
|---|---|---|---|---|
| `NX_STORE=google` (ค่าเริ่มต้น) | Google Play, App Store | FCM | Google Maps (ถ้ามีคีย์) ไม่มีคีย์ใช้ OpenStreetMap | อีเมล/รหัสผ่าน, OTP, LINE, Google, Apple (เฉพาะ iOS) |
| `NX_STORE=huawei` | AppGallery | HMS Push Kit (ไม่มี HMS ใช้ FCM) | OpenStreetMap | อีเมล/รหัสผ่าน, OTP, LINE, Google (ใช้ได้ถ้ามี GBox / microG) |

ไม่รวม HarmonyOS NEXT (5 ขึ้นไป) ซึ่งไม่รันแอป Android

## 1. Secret ที่ต้องใส่ใน GitHub

Settings → Secrets and variables → Actions ทุกตัวไม่บังคับ: ไม่ใส่ CI ก็ยังบิลด์ผ่าน แค่ฟีเจอร์นั้นปิด

| Secret | ค่า | ใช้ทำอะไร |
|---|---|---|
| `ANDROID_TESTER_KEYSTORE_BASE64`, `ANDROID_TESTER_KEYSTORE_PASSWORD` | กุญแจทดสอบ (ดู `GOOGLE_SIGNIN.md`) | APK ทดสอบ SHA-1 คงที่ |
| `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` | กุญแจ upload ของ Play / AppGallery | AAB สำหรับส่ง store |
| `GOOGLE_SERVICES_JSON_BASE64` | `base64 -w0 google-services.json` (Firebase → Android app) | Push Android |
| `GOOGLE_SERVICE_INFO_PLIST_BASE64` | `base64 -w0 GoogleService-Info.plist` (Firebase → iOS app) | Push iPhone |
| `MAPS_API_KEY` | Google Maps SDK key (Android + iOS) | Google Maps |
| `IOS_GOOGLE_CLIENT_ID` | iOS OAuth client id `xxxx.apps.googleusercontent.com` | ปุ่ม Google บน iPhone |
| `IOS_DIST_CERT_P12_BASE64`, `IOS_DIST_CERT_PASSWORD` | ใบรับรอง Apple Distribution (.p12) | เซ็น .ipa |
| `IOS_PROFILE_BASE64` | App Store provisioning profile ของ `com.moai.nextt.mobile` | เซ็น .ipa |
| `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64` | App Store Connect API key | ส่ง TestFlight (เฉพาะ branch `main`) |
| `AGCONNECT_SERVICES_JSON_BASE64` | `base64 -w0 agconnect-services.json` (AppGallery Connect) | Push Huawei |

ไฟล์ที่ CI สร้างจาก secret อยู่ใน `.gitignore` ทั้งหมด ห้าม commit:
`google-services.json`, `GoogleService-Info.plist`, `ios/Flutter/Secrets.xcconfig`,
`agconnect-services.json`, `*.keystore`, `key.properties`

### ผลจาก CI (Actions → run → Artifacts)

- `app-release-arm64-apk` — APK ทดสอบ (Google)
- `app-release-aab-play` — ส่ง Google Play (เมื่อมีกุญแจ release)
- `app-huawei-appgallery` — APK arm64 และ AAB สำหรับ AppGallery
- `app-ios-ipa` — .ipa (เมื่อมี secret เซ็น iOS ครบ)

## 2. ค่าที่ต้องตั้งบนเซิร์ฟเวอร์ NEXTX (env)

เป็น endpoint เพิ่มใหม่ทั้งหมด ไม่กระทบเว็บเดิม

| env | ใช้กับ |
|---|---|
| `SUPPORT_EMAIL` | อีเมลติดต่อบนหน้า `/account-deletion` |
| `ANDROID_APP_SHA256` | SHA-256 ของกุญแจเซ็น (Play App Signing, AppGallery, ทดสอบ) คั่นด้วยคอมมา → `/.well-known/assetlinks.json` |
| `IOS_TEAM_ID` | Team ID ของ Apple → `/.well-known/apple-app-site-association` |
| `APPLE_CLIENT_IDS` | bundle id ที่รับ Sign in with Apple (ค่าเริ่มต้น `com.moai.nextt.mobile`) |
| `HMS_APP_ID`, `HMS_CLIENT_ID`, `HMS_CLIENT_SECRET` | ส่ง Push ผ่าน Huawei |
| FCM (`FCM_SERVICE_ACCOUNT_JSON` ฯลฯ) | ใช้ของเดิม |

ถ้าเว็บ `moainext.moai-crm.com` ไม่ได้ส่ง `/.well-known/*` และ `/account-deletion` ต่อไปที่ backend
ให้ตั้ง reverse proxy ส่งต่อ 3 path นี้ หรือวางไฟล์ JSON ที่ได้จาก backend ไว้บน web host

## 3. Google Play

1. Play Console → สร้างแอป `com.moai.nextt.mobile`
2. เปิด **Play App Signing** แล้วอัปโหลด AAB จาก artifact `app-release-aab-play`
3. App integrity → คัดลอก SHA-1 และ SHA-256 ของ **App signing key**
   - SHA-1 → Google Cloud: สร้าง Android OAuth client เพิ่ม (ดู `GOOGLE_SIGNIN.md`)
   - SHA-256 → env `ANDROID_APP_SHA256` ของเซิร์ฟเวอร์ (App Links)
4. App content:
   - **Data safety**: เก็บ ชื่อ อีเมล เบอร์โทร ตำแหน่งที่แม่นยำ รูปภาพ ข้อมูลระบุตัวตน ข้อมูลแอป crash log
     เพื่อการทำงานของแอปเท่านั้น ไม่ขาย ไม่แชร์เพื่อโฆษณา เข้ารหัสระหว่างส่ง ผู้ใช้ขอลบได้
   - **Account deletion**: ใส่ลิงก์ `https://<เซิร์ฟเวอร์>/account-deletion` และบอกว่าลบในแอปได้ที่ โปรไฟล์ → บัญชีและความปลอดภัย → ลบบัญชี
   - **Location permission**: ใช้ขณะใช้งานแอปเท่านั้น (เช็คอิน ลงเวลา)
   - Privacy policy URL
5. ภาพหน้าจอ: มือถือ 1080×1920 ขึ้นไป, แท็บเล็ต 7" และ 10", มือถือจอพับ (แนะนำ)

## 4. App Store (iPhone / iPad)

1. Apple Developer → Identifiers → `com.moai.nextt.mobile` เปิด capability:
   Push Notifications, Sign in with Apple, Associated Domains
2. Certificates: Apple Distribution (.p12) และ Profile แบบ App Store → ใส่ secret
3. Keys:
   - APNs key (.p8) → อัปโหลดใน Firebase → Project settings → Cloud Messaging → Apple app
   - App Store Connect API key → secret `ASC_*`
4. Google Cloud → สร้าง OAuth client ชนิด **iOS** (bundle id `com.moai.nextt.mobile`) ในโปรเจกต์เดียวกับ Web client ของเซิร์ฟเวอร์ → secret `IOS_GOOGLE_CLIENT_ID`
5. App Store Connect:
   - **App Privacy**: ตรงกับ `ios/Runner/PrivacyInfo.xcprivacy` (ไม่มีการติดตามผู้ใช้)
   - บัญชีทดสอบสำหรับผู้ตรวจ (เป็นผู้ใช้ทดสอบ ไม่ใช่บัญชีลูกค้าจริง)
   - หมายเหตุถึงผู้ตรวจ: ลบบัญชีได้ที่ โปรไฟล์ → บัญชีและความปลอดภัย → ลบบัญชี
6. ภาพหน้าจอ: iPhone 6.9" หรือ 6.7", iPhone 6.5", iPad 13"
7. iPad รองรับ Split View / Stage Manager แล้ว (`UIRequiresFullScreen = false`) ทดสอบหน้าสองช่องที่หลายขนาดหน้าต่าง

### 4.1 ส่งขึ้น TestFlight (ไม่ต้อง merge)

**สร้างใบรับรอง .p12 แบบไม่มี Mac** (เครื่องไหนก็ได้ที่มี openssl; เก็บ `dist.key` เป็นความลับ ห้ามเข้า git)

```bash
openssl req -new -newkey rsa:2048 -nodes -keyout dist.key -out dist.csr -subj "/emailAddress=you@example.com/CN=A I System/C=TH"
```

อัปโหลด `dist.csr` ที่ developer.apple.com → Certificates → **+** → Apple Distribution แล้วดาวน์โหลด `distribution.cer`

```bash
openssl x509 -inform DER -in distribution.cer -out dist.pem
```

```bash
openssl pkcs12 -export -legacy -inkey dist.key -in dist.pem -out dist.p12
```

(ตั้งรหัสผ่านตอน export → ใช้เป็น `IOS_DIST_CERT_PASSWORD`; openssl รุ่นเก่าไม่มี `-legacy` ให้ตัดออก)

**แปลงไฟล์เป็น base64 เพื่อใส่ secret**

```bash
base64 -w0 dist.p12
```

(macOS: `base64 -i dist.p12`, Windows: `certutil -encode dist.p12 out.txt` แล้วลบบรรทัด BEGIN/END)
ทำแบบเดียวกันกับ `.mobileprovision` และ `.p8`

**สั่งอัป:** GitHub → Actions → Flutter CI → **Run workflow** → เลือก branch → ติ๊ก **testflight** → Run
- เลขบิลด์ = เลขรอบของ CI (ไม่ซ้ำเอง), เวอร์ชันมาจาก `pubspec.yaml`
- ประมวลผลใน App Store Connect → TestFlight ราว 5–30 นาที แล้วเพิ่ม Internal Testers
- ไม่ต้องตอบคำถามการเข้ารหัส (ตั้ง `ITSAppUsesNonExemptEncryption = false` ไว้แล้ว)

### 4.x TestFlight แบบ External (ส่งรีวิว + ลิงก์สาธารณะ)

ใส่ GitHub Secrets (Settings → Secrets and variables → Actions) — ค่าเหล่านี้ส่งให้ Apple เท่านั้น ไม่อยู่ใน git:

| Secret | ค่า |
|---|---|
| `TF_REVIEW_SERVER` | URL เซิร์ฟเวอร์ (Space) ที่ผู้รีวิวของ Apple ใช้เข้าสู่ระบบ เช่น `https://moainext.moai-crm.com` |
| `TF_REVIEW_USER` / `TF_REVIEW_PASSWORD` | บัญชีทดสอบสำหรับผู้รีวิว (สร้างเองใน Space นั้น ข้อมูลตัวอย่างเท่านั้น) |
| `TF_CONTACT_FIRST` / `TF_CONTACT_LAST` | ชื่อ-นามสกุลผู้ติดต่อ |
| `TF_CONTACT_EMAIL` / `TF_CONTACT_PHONE` | อีเมล / โทรศัพท์ (รูปแบบ `+66…`) |
| `TF_FEEDBACK_EMAIL`, `TF_PRIVACY_URL` | (ไม่บังคับ) อีเมลรับ feedback, URL นโยบายความเป็นส่วนตัว |

สั่ง Actions → Flutter CI → Run workflow: ติ๊ก `testflight` + `testflight_external` (+ `whats_new`)
→ อัปโหลด → รอ Apple ประมวลผล → ตั้ง "What to Test"/Test Information/บัญชีทดสอบ → เพิ่มเข้ากลุ่ม
**External Testers** (เปิด Public Link) → ส่ง Beta App Review → ลิงก์ `https://testflight.apple.com/join/…` อยู่ใน Summary ของ run

อัปโหลดไปแล้วแต่ยังไม่ได้ส่ง: Run workflow ใส่ `tf_build_number` = เลขบิลด์ (ไม่ต้อง build ใหม่)
Apple รีวิว beta ปกติราว 1 วัน; อนุมัติแล้วลิงก์ใช้ติดตั้งได้ทันที

## 5. Huawei AppGallery (EMUI / HarmonyOS 2–4)

1. AppGallery Connect → สร้างแอป package `com.moai.nextt.mobile`
2. เปิด **Push Kit** (Grow → Push Kit) แล้วดาวน์โหลด `agconnect-services.json` → secret `AGCONNECT_SERVICES_JSON_BASE64`
3. Project settings → App signing:
   - ใช้ App Signing ของ AppGallery และคัดลอก SHA-256 ของกุญแจเซ็นไปใส่ AGC (Certificate fingerprint) และ env `ANDROID_APP_SHA256`
   - คัดลอก SHA-1 ไปสร้าง Android OAuth client ใน Google Cloud ด้วย ไม่งั้นเครื่องที่มี GBox / microG จะขึ้น "บัญชีผิดปกติ"
4. Credentials → OAuth 2.0 client (Server) → ค่า client id / secret → env `HMS_CLIENT_ID`, `HMS_CLIENT_SECRET`, app id → `HMS_APP_ID`
5. อัปโหลด AAB หรือ APK จาก artifact `app-huawei-appgallery`
6. Privacy statement และลิงก์ลบบัญชี เหมือน Google Play
7. แผนที่ใช้ OpenStreetMap: tile.openstreetmap.org มีนโยบายจำกัดการใช้งานหนัก
   ถ้าผู้ใช้เยอะให้ใช้ผู้ให้บริการ tile (เช่น MapTiler, Stadia) แล้วบิลด์ด้วย `--dart-define=NX_OSM_TILES=https://.../{z}/{x}/{y}.png`

## 6. เช็กลิสต์ทดสอบบนเครื่องจริง

- [ ] Android: แจ้งเตือนเข้า แตะแล้วเปิดหน้าถูก, เข้าสู่ระบบด้วย Google / LINE / OTP
- [ ] มือถือจอพับ (Galaxy Fold / Pixel Fold): กางแบน รายการซ้าย รายละเอียดขวา ไม่คร่อมรอยพับ, ท่าวางบนโต๊ะไม่แยกช่อง
- [ ] Huawei ไม่มี GMS: แจ้งเตือนผ่าน HMS, แผนที่ OSM, กด Google แล้วได้ข้อความแนะนำ GBox / microG หรือ LINE / OTP
- [ ] Huawei มี GBox หรือ microG: เข้าสู่ระบบด้วย Google ได้ และแจ้งเตือนมาครั้งเดียว
- [ ] iPhone: แจ้งเตือน, เข้าสู่ระบบด้วย Apple / Google / LINE, ข้อความขอสิทธิ์เป็นภาษาของเครื่อง
- [ ] iPad: Split View, Stage Manager, หมุนจอทุกทิศ
- [ ] ลบบัญชี (ใช้บัญชีทดสอบเท่านั้น): ยืนยัน OTP แล้วเข้าสู่ระบบด้วยบัญชีนั้นไม่ได้อีก ข้อมูลงานของธุรกิจยังอยู่
