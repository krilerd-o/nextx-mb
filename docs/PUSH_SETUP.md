# คู่มือเปิดการแจ้งเตือนขึ้นเครื่อง (Push) + สายเรียกเข้า — NEXTX Mobile

> คู่มือนี้ทำครั้งเดียว ใช้ได้ทั้ง Android, iPhone/iPad และ Huawei
> **ห้ามส่งไฟล์กุญแจ / รหัส ในแชทหรือใส่ใน git** — ใส่ใน GitHub Secrets, Firebase, หรือ env ของเซิร์ฟเวอร์ตามที่ระบุเท่านั้น

## ภาพรวม: อะไรต้องใส่ที่ไหน

| # | สิ่งที่ต้องมี | ได้จาก | ใส่ที่ | ใช้ทำอะไร |
|---|---|---|---|---|
| 1 | `google-services.json` | Firebase (แอป Android) | GitHub Secret `GOOGLE_SERVICES_JSON_BASE64` | แอป Android รับแจ้งเตือน |
| 2 | `GoogleService-Info.plist` | Firebase (แอป iOS) | GitHub Secret `GOOGLE_SERVICE_INFO_PLIST_BASE64` | แอป iPhone รับแจ้งเตือน |
| 3 | APNs Key (`.p8`) + Key ID + Team ID | Apple Developer | Firebase (Cloud Messaging) **และ** หน้าเว็บ NEXTX → ตั้งค่า → การโทร | iPhone ได้แจ้งเตือน + สายเข้าแบบ CallKit |
| 4 | Service Account JSON | Google Cloud (โปรเจกต์ `moai-nextt`) | env backend `FCM_SERVICE_ACCOUNT_JSON` | เซิร์ฟเวอร์ส่งแจ้งเตือน |
| 5 | TURN (Cloudflare หรือ coturn) | Cloudflare Dashboard | หน้าเว็บ NEXTX → ตั้งค่า → การโทร | โทรข้ามเครือข่าย (4G ↔ Wi‑Fi) มีเสียง |
| 6 | (Huawei) `agconnect-services.json` + App ID/Client ID/Secret | AppGallery Connect | GitHub Secret `AGCONNECT_SERVICES_JSON_BASE64` + env backend `HMS_*` | เครื่อง Huawei ไม่มี Google |
| 7 | Deploy backend NEXTX (branch `develop`) | — | เซิร์ฟเวอร์จริง | โค้ดส่งแจ้งเตือน/VoIP/หน้าตั้งค่าการโทร |

ข้อมูลแอป: Bundle ID / Package = `com.moai.nextt.mobile`, Firebase project = `moai-nextt`

---

## ขั้นที่ 1 — Firebase: ไฟล์ตั้งค่าของแอป Android และ iOS

1. เปิด https://console.firebase.google.com → เลือกโปรเจกต์ **moai-nextt**
2. กดรูปเฟือง ⚙ ข้าง "Project Overview" → **Project settings** → แท็บ **General** → เลื่อนลงไปส่วน **Your apps**
3. **Android**
   - ถ้ามีแอป `com.moai.nextt.mobile` อยู่แล้ว → กดปุ่ม **google-services.json** เพื่อดาวน์โหลด
   - ถ้ายังไม่มี → **Add app** → ไอคอน Android → Package name `com.moai.nextt.mobile` → Register → ดาวน์โหลด `google-services.json` (ขั้นที่เหลือของตัวช่วยกด Next ข้ามได้)
4. **iOS**
   - ถ้ามีแอป iOS `com.moai.nextt.mobile` แล้ว → กดปุ่ม **GoogleService-Info.plist**
   - ถ้ายังไม่มี → **Add app** → ไอคอน iOS → Bundle ID `com.moai.nextt.mobile` → Register → ดาวน์โหลด `GoogleService-Info.plist`
5. ใส่ GitHub Secrets: https://github.com/krilerd-o/nextx-mb → **Settings → Secrets and variables → Actions → New repository secret**

   | Name | Secret (วางอะไร) |
   |---|---|
   | `GOOGLE_SERVICES_JSON_BASE64` | เปิด `google-services.json` ด้วย Notepad/TextEdit แล้ว **คัดลอกทั้งไฟล์มาวาง** |
   | `GOOGLE_SERVICE_INFO_PLIST_BASE64` | เปิด `GoogleService-Info.plist` แล้ว **คัดลอกทั้งไฟล์มาวาง** |

   > ไม่ต้องแปลง base64 — CI รับเนื้อไฟล์ดิบได้ (ถ้าอยากแปลงก็ได้ ผลเหมือนกัน)

## ขั้นที่ 2 — Apple: สร้าง APNs Key (.p8)

> ใช้ key เดียวกันทั้งแจ้งเตือนทั่วไป (ผ่าน Firebase) และสายเรียกเข้า (VoIP) — สร้างครั้งเดียว

1. เปิด https://developer.apple.com/account → **Certificates, Identifiers & Profiles**
2. ตรวจ App ID ก่อน: **Identifiers** → `com.moai.nextt.mobile` → ต้องติ๊ก **Push Notifications** ไว้ (ถ้ายังไม่ติ๊ก → ติ๊ก → Save → แจ้งผม เพราะต้องสร้าง Provisioning Profile ใหม่แล้วอัปเดต secret `IOS_PROFILE_BASE64`)
3. **Keys** → ปุ่ม **+**
   - Key Name: `NEXTX Push`
   - ติ๊ก **Apple Push Notifications service (APNs)** → Configure → Environment เลือก **Sandbox & Production** → Key Restriction **Team Scoped (All Topics)** → Save
   - Continue → **Register** → **Download** ได้ไฟล์ `AuthKey_XXXXXXXXXX.p8` (**ดาวน์โหลดได้ครั้งเดียว** เก็บไว้ที่ปลอดภัย)
4. จดไว้ 2 ค่า:
   - **Key ID** = 10 ตัวอักษรในชื่อไฟล์ (หรือดูในหน้า Keys)
   - **Team ID** = มุมขวาบนของหน้า developer.apple.com (10 ตัวอักษร) หรือหน้า **Membership details**

## ขั้นที่ 3 — อัป APNs Key เข้า Firebase (ให้ iPhone ได้รับแจ้งเตือน)

1. Firebase Console → **moai-nextt** → ⚙ **Project settings** → แท็บ **Cloud Messaging**
2. ส่วน **Apple app configuration** → แอป iOS `com.moai.nextt.mobile` → **APNs Authentication Key** → **Upload**
3. เลือกไฟล์ `.p8`, ใส่ **Key ID** และ **Team ID** → Upload

> **สำคัญ — ส่งผ่าน Notify (`notify.moai-crm.com`)**: เมื่อเปิดใช้ Notify ในหน้าเว็บ NEXTX (ตั้งค่า → การแจ้งเตือนมือถือ)
> แจ้งเตือนทั่วไปจะส่งจาก Notify แทนเซิร์ฟเวอร์ NEXTX — **APNs Key ต้องอัปโหลดใน Firebase project เดียวกับที่บัญชี Notify (`moai-nextt`) ใช้ส่ง**
> และต้องเป็น project เดียวกับไฟล์ `GoogleService-Info.plist` / `google-services.json` ของแอป (token ของ FCM ผูกกับ project — ต่าง project กันจะส่งไม่ถึง)
> ถ้าไม่แน่ใจ: ดู `project_id` ในไฟล์ทั้งสองของแอป แล้วเทียบกับ project ที่ตั้งไว้ในบัญชี Notify (ทีม Notify ช่วยยืนยันได้)

## ขั้นที่ 4 — Service Account ให้เซิร์ฟเวอร์ NEXTX ส่งแจ้งเตือน

1. Firebase Console → ⚙ **Project settings** → แท็บ **Service accounts** → **Generate new private key** → Generate key → ได้ไฟล์ `.json`
   (สิทธิ์ที่ได้คือ Firebase Admin ของโปรเจกต์ moai-nextt ซึ่งพอสำหรับส่ง FCM)
2. ใส่ใน **env ของ backend NEXTX บนเซิร์ฟเวอร์** (ไม่ใช่ GitHub ของแอป) เลือกวิธีใดวิธีหนึ่ง:
   - วางไฟล์บนเซิร์ฟเวอร์ เช่น `/run/secrets/moai-nextt-fcm.json` แล้วตั้ง
     ```
     FCM_PROJECT_ID=moai-nextt
     FCM_SERVICE_ACCOUNT_FILE=/run/secrets/moai-nextt-fcm.json
     ```
   - หรือวางเนื้อ JSON ทั้งก้อนในบรรทัดเดียว
     ```
     FCM_PROJECT_ID=moai-nextt
     FCM_SERVICE_ACCOUNT_JSON={"type":"service_account",...}
     ```
3. restart backend หนึ่งครั้ง (ค่าชุดนี้อ่านตอนเริ่ม)

## ขั้นที่ 5 — สายเรียกเข้า iPhone (VoIP) และ TURN — ตั้งในหน้าเว็บ ไม่ต้องแก้ .env

> ต้อง deploy backend ก่อน (ขั้นที่ 7) หน้านี้จึงจะมี

1. เข้าเว็บ NEXTX ด้วยบัญชี **superadmin** → **ตั้งค่า → การโทร / วิดีโอคอล**
2. การ์ด **สายเข้า iPhone (APNs VoIP)**
   - Key ID, Team ID (จากขั้นที่ 2), อัปโหลดไฟล์ `.p8`
   - Bundle ID: `com.moai.nextt.mobile`
   - สภาพแวดล้อม: **Production** (สำหรับ TestFlight และ App Store)
3. การ์ด **โทรผ่าน 4G / ต่างเครือข่าย (TURN)** — แนะนำ **Cloudflare**
   - https://dash.cloudflare.com → **Realtime** (หรือ Calls) → **TURN** → **Create** → ได้ **Turn Token ID** และ **API Token**
   - เลือกการ์ด Cloudflare → วาง Key ID + API Token
   - (ทางเลือก) coturn ของเราเอง: ดู `docs/CALLS_SETUP.md`
4. กด **ทดสอบการเชื่อมต่อ** → ต้องเห็น ✓ ทุกข้อ (TURN Allocate ✓, เบราว์เซอร์ได้ relay ✓, APNs ✓) → กด **Activate**
   ใช้งานได้ทันที ไม่ต้อง restart

## ขั้นที่ 6 — Huawei (ทำเมื่อจะลง AppGallery)

1. https://developer.huawei.com/consumer/en/service/josp/agc/index.html → **My projects** → โปรเจกต์ของแอป
2. **Grow → Push Kit** → **Enable now**
3. **Project settings → General information** → ดาวน์โหลด `agconnect-services.json` → GitHub Secret `AGCONNECT_SERVICES_JSON_BASE64` (วางทั้งไฟล์)
4. หน้าเดียวกัน ส่วน **App information** จด **App ID**, **Client ID**, **Client secret** → env backend
   ```
   HMS_APP_ID=...
   HMS_CLIENT_ID=...
   HMS_CLIENT_SECRET=...
   ```
5. restart backend

## ขั้นที่ 7 — Deploy backend NEXTX

โค้ดส่งแจ้งเตือน (FCM/HMS), VoIP push, หน้าตั้งค่าการโทร อยู่ใน branch `develop` ของ NEXTX — ต้อง deploy ขึ้นเซิร์ฟเวอร์จริงก่อน (ผมไม่ deploy เอง) แล้วเช็ก:
- `https://<เซิร์ฟเวอร์>/api/mobile/health` มี `calls_turn: true` (หลังขั้นที่ 5)

## ขั้นที่ 8 — บอกผม แล้วผม Build ใหม่

บอกว่า **"ใส่ push แล้ว"** → ผมสั่ง Build Android `0.05.000 (6)` + iOS `0.5.0` build ใหม่ และตรวจ log ว่า **ไม่มี** คำเตือน
`push notifications are off` ทั้ง Android และ iPhone

## ขั้นที่ 9 — ทดสอบบนเครื่องจริง

ติดตั้ง build ใหม่ (Android ผ่าน Firebase App Distribution, iPhone ผ่าน TestFlight) แล้วเข้าสู่ระบบ — แอปลงทะเบียนเครื่องเองอัตโนมัติ

| ทดสอบ | วิธี | ผลที่ต้องได้ |
|---|---|---|
| อนุญาตแจ้งเตือน | เปิดแอปครั้งแรก | ขึ้นถามสิทธิ์ → กดอนุญาต |
| แจ้งเตือนงาน | ให้อีกคน assign งานให้ / คอมเมนต์ @ถึงคุณ | ขึ้นแจ้งเตือนบนเครื่อง แตะแล้วเปิดงานนั้น |
| แจ้งเตือนแชท | ส่งข้อความหา ขณะปิดแอป | ขึ้นแจ้งเตือน แตะแล้วเข้าห้องแชท |
| สายเข้า (ปิดแอป/ล็อกจอ) | โทรจากเว็บหรืออีกเครื่อง | iPhone: หน้าจอรับสายของระบบ (CallKit) · Android: หน้าจอสายเข้าเต็มจอ |
| สายไม่ได้รับ | โทรแล้วไม่รับจนหมดเวลาเรียก (ค่าเริ่มต้น 45 วิ) | ได้แจ้งเตือน "สายที่ไม่ได้รับ" |
| ต่างเครือข่าย | เครื่องหนึ่ง 4G อีกเครื่อง Wi‑Fi | รับสายแล้วได้ยินเสียงทั้งสองฝั่ง |

## iPhone: แอปได้ token อย่างไร (สำหรับนักพัฒนา)

- **`GoogleService-Info.plist` ต้องอยู่ใน app bundle** — Firebase อ่านไฟล์นี้ตอนเปิดแอป ถ้าไม่มี แอปจะไม่ได้ FCM token เลย (ไม่ขึ้น error ให้เห็น แค่ log `[push] Firebase init skipped`)
  - CI เขียนไฟล์ลง `ios/Runner/GoogleService-Info.plist` จาก secret `GOOGLE_SERVICE_INFO_PLIST_BASE64` (ไฟล์อยู่ใน `.gitignore` ห้าม commit)
  - Xcode project มี build phase **"Bundle GoogleService-Info.plist"** (ต่อจาก Copy Bundle Resources) คัดลอกไฟล์เข้า `Runner.app` **เมื่อมีไฟล์** — ไม่ได้ใส่เป็น Resources ตรง ๆ เพราะจะทำให้ build ที่ไม่มี secret (PR, เครื่องนักพัฒนา) พังทันที
  - build ที่ไม่มีไฟล์จะขึ้น `warning: Runner/GoogleService-Info.plist not found - push notifications are off in this build.` ใน log ของ Xcode
  - build เองบนเครื่อง: วางไฟล์ที่ดาวน์โหลดจาก Firebase (ขั้นที่ 1) ไว้ที่ `ios/Runner/GoogleService-Info.plist` ก่อน build
- **APNs environment**
  - `ios/Runner/Runner.entitlements` (Debug + Profile) = `development` — ใช้กับ build ลงเครื่องจาก Xcode / `flutter run`
  - `ios/Runner/RunnerRelease.entitlements` (Release) = `production` — ตรงกับ App Store profile ที่ CI ใช้ (TestFlight / App Store รับ push จาก APNs production)
  - ถ้าแก้ entitlement อื่น (Associated Domains, Sign in with Apple) ต้องแก้ **ทั้งสองไฟล์**
  - ถ้าจะ `flutter run --release` ลงเครื่องด้วย development profile แล้ว Xcode ฟ้องว่า aps-environment ไม่ตรงกับ profile: ชั่วคราวเปลี่ยน Release → Build Settings → Code Signing Entitlements กลับเป็น `Runner/Runner.entitlements` (อย่า commit)
- Firebase console: APNs Authentication Key (.p8) ต้องอัปโหลดไว้ใน **Cloud Messaging → Apple app configuration** ของแอป iOS ใน project `moai-nextt` (ขั้นที่ 3) — ใช้ได้ทั้ง development และ production

## กดแจ้งเตือนแล้วแอปทำอะไร

- push ทุกอันมี `data` (ตัวอักษรทั้งหมด): `url`, `id`, `extra`, `notification_id`, `event`, `business_id`, `badge`, `type: "notification"` — แอปแปลงเป็นหน้าในแอป (`lib/core/navigation/notification_deep_link.dart`, `push_tap.dart`)
  - `id` = id ของ**เรื่อง** (link_id เช่น ห้องแชท ใบลา) ส่วน `notification_id` = แถวกระดิ่ง
  - เซิร์ฟเวอร์รุ่นก่อน (รอบ 1) ส่ง `id` = แถวกระดิ่ง (เท่ากับ `notification_id`) — แอปถือว่าไม่มี id ของเรื่อง
  - แชท: ใช้ `?room=` ใน `url` ก่อนเสมอ แล้วจึงใช้ `id`
- `business_id` ไม่ใช่ของพื้นที่ทำงานที่เปิดอยู่ แต่เครื่องนี้มีพื้นที่ทำงานนั้น → สลับพื้นที่ทำงานก่อนแล้วจึงเปิดเรื่อง
- `url` = `/announcements/<id>` (ประกาศ / ปิดปรับปรุง / ประกาศทั่วไป / อัปเดตแอป) → หน้าอ่านประกาศ (`GET /api/announcements/:id`) และอ่านแถวกระดิ่งนั้นแล้ว
- `event: app_update` + `store_android` / `store_ios` → เปิดร้านค้าแอปของเครื่องนั้น; ไม่มีลิงก์ที่ใช้ได้ → หน้าอ่านประกาศ (มีปุ่ม **อัปเดตแอป**)
- `leave_request` → หน้าใบลา แท็บอนุมัติ, `leave_result` → หน้าใบลา แท็บของฉัน (ใบที่เกี่ยวข้องขึ้นก่อนและมีกรอบ)
- `announcement` / `system_notice` ที่ไม่มี `/announcements/<id>` / เรื่องที่ไม่มีหน้าในแอป → ศูนย์การแจ้งเตือน เปิดอ่านข้อความเต็ม
- แอปเปิดอยู่ตอน push มาถึง: นับเลขแจ้งเตือนที่ยังไม่อ่านเพิ่ม (ใช้ `badge` ถ้ามี); iPhone ให้ระบบแสดงแถบเอง (ไม่ซ้ำ 2 อัน) ส่วน Android แอปแสดงเอง
  - Android: แชทห้องเดียวกันใช้ id + tag เดียวกัน (`chat-<ห้อง>`) ข้อความใหม่จึง**แทนที่**อันเดิมของห้องนั้น ไม่ซ้อนกันเป็นกอง
- ทดสอบได้จากแอป: โปรไฟล์ → จัดการการแจ้งเตือน → **ส่งทดสอบมาที่เครื่องนี้** (`POST /api/notifications/test`) — เซิร์ฟเวอร์ใหม่แสดงผลรายเครื่อง (ส่งแล้ว / เครื่องใช้ไม่ได้แล้ว / ส่งไม่สำเร็จ)
- โปรไฟล์ → จัดการอุปกรณ์ → **อุปกรณ์ที่รับแจ้งเตือน** (`GET /api/notifications/devices`) แสดงเครื่องที่รับแจ้งเตือนอยู่
- แอปบอกภาษาของผู้ใช้ให้เซิร์ฟเวอร์ (`PUT /api/me/language {lang}`) ตอนสลับ TH/EN และครั้งแรกหลังเข้าสู่ระบบ — ข้อความแจ้งเตือนจึงมาตามภาษานั้น

## เลขบนไอคอนแอป (badge) และเสียง

- แอปตั้งเลขบนไอคอน = จำนวนแจ้งเตือนที่ยังไม่อ่าน (แพ็กเกจ `app_badge_plus`, `lib/services/app_icon_badge.dart`)
  - ตอนเปิดแอป / กลับเข้าแอป / ได้ push ขณะเปิดแอป (ใช้ `badge` จาก push) / อ่านแจ้งเตือน / อ่านทั้งหมด
  - ออกจากระบบ → ล้างเลขเป็น 0
  - Android: แสดงเป็นตัวเลขเฉพาะ launcher ที่รองรับ (Samsung, Huawei/Honor, Xiaomi, OPPO, vivo, Sony ฯลฯ); launcher อื่น (เช่น Pixel) แสดงเป็นจุดตามแจ้งเตือนที่ค้างอยู่
- Android ใช้ channel `high_importance_channel` (ตั้งใน `AndroidManifest.xml` เป็น channel ปริยายของ FCM ด้วย): ความสำคัญสูง (ขึ้นแถบด้านบน) มีเสียงและสั่น
  - Android จำค่าของ channel ตั้งแต่ครั้งแรกที่สร้าง — ถ้าผู้ใช้ปิดเสียงเองในตั้งค่าเครื่อง แอปเปลี่ยนกลับให้ไม่ได้
- **ข้อจำกัด: ตอนแอปปิดสนิท iPhone จะยังไม่ขึ้น/ไม่เปลี่ยนเลขบนไอคอน** จนกว่า Notify จะส่ง `apns.badge` ไปกับ push (ตอนนี้ Notify ยังไม่รองรับ)
  - เลขจะถูกต้องทันทีที่ผู้ใช้เปิดแอปครั้งถัดไป
  - Android ตอนแอปปิด: launcher ส่วนใหญ่นับจากแจ้งเตือนที่ค้างในถาด จึงยังเห็นจุด/เลข

## ข้อควรรู้ / แก้ปัญหา

- **iPhone ไม่ขึ้นแจ้งเตือน** → ตรวจขั้นที่ 3 (อัป .p8 ใน Firebase project เดียวกับที่ Notify ใช้แล้ว) และ build มาจาก CI รอบหลังใส่ `GOOGLE_SERVICE_INFO_PLIST_BASE64` (log ของ Xcode ต้องมี `Bundled GoogleService-Info.plist`)
- **สายเข้า iPhone ไม่ขึ้นตอนปิดแอป** → APNs ในหน้าตั้งค่าการโทรต้องเป็น **Production** และ Activate แล้ว (build จาก TestFlight ใช้ Production เสมอ)
- **Android 14 ขึ้นไป** ถ้าสายเข้าขึ้นเป็นแค่แถบแจ้งเตือน (ไม่เต็มจอ): ตั้งค่าเครื่อง → แอป → NEXTX → การแจ้งเตือน → เปิด **"แจ้งเตือนแบบเต็มหน้าจอ"**
- **Huawei / Xiaomi / OPPO / vivo** บางรุ่น: ตั้งค่า → แบตเตอรี่ → แอป NEXTX → **ไม่จำกัด / อนุญาตทำงานเบื้องหลัง** ไม่งั้นแจ้งเตือนอาจช้า
- **รับสายแล้วไม่มีเสียง (อยู่คนละเครือข่าย)** → ขั้นที่ 5 TURN ยังไม่ Activate
- ถ้าต้องการหยุดใช้ key ใด ลบใน Apple/Firebase แล้วสร้างใหม่ตามคู่มือนี้ได้เสมอ
