# ตั้งค่าการโทร / วิดีโอคอล (เว็บ + แอป)

การโทรใช้ WebRTC ต่อตรงระหว่างผู้ใช้ (mesh สูงสุด 4 คน) โดยเซิร์ฟเวอร์ NEXTX ทำหน้าที่ต่อไปนี้:

- ส่งสัญญาณผ่าน Socket.io (`rtc:*`)
- เรียกทุกอุปกรณ์
- เขียนประวัติการโทรลงห้องแชท
- ส่ง push สายเข้า

เสียงและวิดีโอไม่ผ่านเซิร์ฟเวอร์ ยกเว้นกรณีที่ต้องผ่าน TURN

```
[เว็บ / แอป] ──socket rtc:*──▶ [NEXTX backend] ──push──▶ FCM (Android) / APNs VoIP (iOS) / HMS (Huawei)
     ▲                                  │
     └──────── WebRTC (P2P หรือผ่าน TURN) ───────▶ [อีกฝั่ง]
```

## 1. TURN server (coturn)

ถ้าไม่มี TURN จะโทรติดเฉพาะเครือข่ายที่ต่อตรงกันได้ เช่น ในออฟฟิศเดียวกัน แต่ผ่าน 4G หรือ NAT บางแบบจะไม่ติด

1. ติดตั้งบนเครื่องที่มี IP สาธารณะ (Ubuntu):
   ```bash
   sudo apt-get install -y coturn
   ```
2. แก้ `/etc/turnserver.conf`:
   ```
   listening-port=3478
   tls-listening-port=5349
   fingerprint
   use-auth-secret
   static-auth-secret=<สุ่มยาว ๆ เก็บเป็นความลับ>
   realm=turn.moai-crm.com
   total-quota=200
   no-cli
   no-multicast-peers
   denied-peer-ip=10.0.0.0-10.255.255.255
   denied-peer-ip=172.16.0.0-172.31.255.255
   denied-peer-ip=192.168.0.0-192.168.255.255
   cert=/etc/letsencrypt/live/turn.moai-crm.com/fullchain.pem
   pkey=/etc/letsencrypt/live/turn.moai-crm.com/privkey.pem
   ```
3. เปิด firewall:
   - 3478 UDP/TCP
   - 5349 TCP
   - 49152–65535 UDP (relay)
4. เปิดใช้งาน:
   ```bash
   sudo systemctl enable --now coturn
   ```
5. ทดสอบด้วยปุ่ม "ทดสอบการเชื่อมต่อ" ในหน้าตั้งค่า (ข้อ 2) ซึ่งตรวจ relay จริงทั้งจากเซิร์ฟเวอร์และเบราว์เซอร์

## 2. ตั้งค่าในเว็บ NEXTX (แนะนำ ไม่ต้องแก้ .env และไม่ต้องรีสตาร์ท)

เว็บ NEXTX → **ตั้งค่า → การโทร / วิดีโอคอล** (แก้ได้เฉพาะ superadmin; คนอื่นเห็นแค่สถานะ)

1. **โทรผ่าน 4G (TURN)** เลือกแบบใดแบบหนึ่ง:
   - **Cloudflare TURN (แนะนำ เร็วสุด):** Cloudflare Dashboard → Realtime → TURN Server → Create → ได้ *TURN Key ID* และ *API Token* → วางในหน้านี้
   - **coturn ของเราเอง:** ทำตามข้อ 1 แล้วใส่ TURN URL (บรรทัดละ 1) และ shared secret
   - **ชื่อผู้ใช้/รหัสคงที่:** สำหรับผู้ให้บริการอื่น เช่น Metered, Twilio
2. **สายเข้า iPhone (APNs VoIP):** เปิดสวิตช์ → ใส่ Key ID, Team ID, เลือกไฟล์ `AuthKey_XXXX.p8`, Bundle ID, Production/Sandbox
3. **ตัวเลือกการโทร:** จำนวนคนต่อสาย (2–4), เวลาเรียกก่อนเป็นสายที่ไม่ได้รับ, เวลารอเน็ตหลุดกลับมา
4. กด **ทดสอบการเชื่อมต่อ** — ระบบทดสอบจริงทีละข้อ:
   - จากเซิร์ฟเวอร์: DNS → เซิร์ฟเวอร์ตอบ (STUN) → ขอช่อง relay ด้วยรหัสจริง (TURN Allocate) ทุก URL
   - จากเบราว์เซอร์ที่เปิดอยู่: ต้องได้ candidate ชนิด `relay`
   - APNs: ตรวจกุญแจกับ Apple โดยตรง (ไม่ต้องมี iPhone)
5. กด **Activate** — ทดสอบซ้ำ ผ่านแล้วจึงเปิดใช้ **สายถัดไปใช้ค่าใหม่ทันที** ถ้าไม่ผ่าน ค่าที่ใช้อยู่เดิมไม่เปลี่ยน
   - "บันทึกร่าง" ยังไม่มีผลกับการโทรจนกว่าจะ Activate
   - "ปิดใช้งาน" = กลับไปใช้ค่าจาก .env
   - ขั้นสูง → "ผ่าน TURN เสมอ" ใช้ตรวจปัญหา (บังคับเสียง/วิดีโอวิ่งผ่าน TURN)

ค่าลับ (secret, token, .p8) เก็บในฐานข้อมูลแบบเข้ารหัส (ตาราง `aicrm_call_settings`, สร้างให้อัตโนมัติ หรือ `npm run migrate-call-settings`) และไม่ส่งกลับมาที่หน้าเว็บ
ถ้าเซิร์ฟเวอร์รันหลาย instance ค่าใหม่มีผลภายใน 30 วินาที

## 2.1 ตัวแปร env ของ backend (ค่าสำรอง ใช้เฉพาะส่วนที่ยังไม่ได้ตั้งในเว็บ)

| ตัวแปร | ตัวอย่าง | ความหมาย |
|---|---|---|
| `TURN_URLS` | `turn:turn.moai-crm.com:3478?transport=udp,turns:turn.moai-crm.com:5349?transport=tcp` | TURN (คั่นด้วย ,) |
| `TURN_SECRET` | (ค่าเดียวกับ `static-auth-secret`) | ใช้ออก credential ชั่วคราว (coturn REST) |
| `TURN_TTL_SECONDS` | `3600` | อายุ credential |
| `STUN_URLS` | (ไม่ใส่ = STUN ของ Google) | STUN เพิ่มเติม |
| `CALL_MAX_PARTICIPANTS` | `4` | จำนวนคนสูงสุดต่อสาย (mesh) |
| `CALL_RING_TIMEOUT_MS` | `45000` | เวลาเรียกก่อนเป็น "ไม่มีผู้รับสาย" |
| `APNS_KEY_ID`, `APNS_TEAM_ID` | | กุญแจ APNs (.p8) สำหรับ VoIP push |
| `APNS_KEY_P8_BASE64` | (base64 ของไฟล์ .p8) | หรือใช้ `APNS_KEY_P8` / `APNS_KEY_FILE` แทน |
| `APNS_BUNDLE_ID` | `com.moai.nextt.mobile` | topic จะเป็น `<bundle>.voip` |
| `APNS_PRODUCTION` | `1` | TestFlight / App Store = 1, Xcode debug = ไม่ใส่ |

FCM (Android) และ HMS (Huawei) ใช้ค่าที่ตั้งไว้แล้ว (`FCM_SERVICE_ACCOUNT_*`, `HMS_*`) ไม่ต้องเพิ่ม

> ค่าความลับ (secret, .p8) ใส่ที่ env ของเซิร์ฟเวอร์เท่านั้น ห้ามใส่ใน git

**ข้อจำกัด:** สถานะการโทรเก็บในหน่วยความจำของ backend
- ถ้ารัน backend หลาย instance ต้องให้ทุก socket ไปที่ instance เดียวกัน หรือรันเพียง instance เดียว (ค่าปัจจุบันใน `docker-compose.yml` เป็น 1 instance)
- reverse proxy ต้องเปิด WebSocket ที่ `/api/socket.io`

## 3. iOS: VoIP push + CallKit (สายเข้าตอนปิดแอป / ล็อกจอ)

1. สร้างกุญแจ APNs:
   - ไปที่ Apple Developer → Certificates, Identifiers & Profiles → **Keys** → `+`
   - เลือก "Apple Push Notifications service (APNs)" แล้วดาวน์โหลด `.p8`
   - จด Key ID และ Team ID
   - แปลงไฟล์: `base64 -i AuthKey_XXXX.p8` แล้วใส่เป็น `APNS_KEY_P8_BASE64`
2. ตั้งค่าที่ Identifier `com.moai.nextt.mobile`: ต้องเปิด **Push Notifications** (เปิดอยู่แล้ว)
3. ในโปรเจกต์แอป (ตั้งค่าไว้แล้วในรอบนี้):
   - `Info.plist` → `UIBackgroundModes` มี `voip` และ `audio`
   - `AppDelegate.swift` ลงทะเบียน PushKit → ส่ง token ให้ `flutter_callkit_incoming` → แอปส่ง token ขึ้นเซิร์ฟเวอร์เป็น platform `ios_voip`
   - เมื่อมี VoIP push เข้ามา จะแสดงหน้าจอ CallKit ทันที (Apple บังคับ)
4. profile สำหรับ App Store / TestFlight ต้องสร้างใหม่หลังเปิด Push ถ้ายังไม่ได้ทำ

## 4. Android: หน้าจอสายเข้าเต็มจอ

- ใช้ FCM data message `type=call_incoming` (priority high) → `flutter_callkit_incoming` แสดงหน้าจอสายเข้า (แม้ล็อกจอ)
- สิทธิ์ใน `AndroidManifest.xml` เพิ่มไว้แล้ว:
  - `USE_FULL_SCREEN_INTENT`
  - `FOREGROUND_SERVICE_PHONE_CALL` / `MICROPHONE` / `CAMERA`
  - `MANAGE_OWN_CALLS`
  - `BLUETOOTH_CONNECT`
- Android 14 ขึ้นไป: ถ้าแอปไม่ได้รับสิทธิ์ "แสดงแบบเต็มหน้าจอ" ระบบจะแสดงเป็นการแจ้งเตือนแทน ผู้ใช้เปิดสิทธิ์ได้ที่ ตั้งค่า → แอป → MOAI NEXT → การแจ้งเตือน
- Huawei (HMS): ได้การแจ้งเตือนสายเข้า (HMS ไม่มี data-only แบบปลุกแอป) เมื่อแตะแล้วแอปจะเปิดหน้าสายเข้าให้

## 5. ทดสอบ (ใช้ผู้ใช้ [QA])

1. **เว็บ ↔ เว็บ:**
   - โทร 1:1 (เสียง / วิดีโอ)
   - โทรกลุ่ม 3 คน
   - แชร์จอ
   - ปิดไมค์
   - ออกทีละคน
   - ยกเลิกระหว่างเรียก → อีกฝั่งหยุดดังและเห็น "สายที่ไม่ได้รับ"
2. **แอป ↔ เว็บ:**
   - แอปโทรหาเว็บและเว็บโทรหาแอป (protocol เดียวกัน)
   - รับด้วยเสียงอย่างเดียว
   - เปิดกล้องระหว่างสาย
   - สลับกล้อง
   - ลำโพง
   - ย่อเป็นวงลอยแล้วใช้แอปต่อ
3. **สายเข้าตอนปิดแอป:**
   - ปิดแอปหรือล็อกจอ แล้วโทรจากเว็บ → ต้องขึ้นหน้าจอ CallKit (iOS) / เต็มจอ (Android)
   - กดรับ → แอปเปิดและเชื่อมต่อ
   - กดปฏิเสธ → ผู้โทรเห็น "ปลายสายปฏิเสธ"
4. **ต่างเครือข่าย:** แอปใช้ 4G โทรหาเว็บที่อยู่หลัง NAT → ต้องติด (ต้องมี TURN)
5. **ประวัติการโทร:** ในห้องแชทมีการ์ด "วิดีโอคอล · 1:05", "สายที่ไม่ได้รับ" พร้อมปุ่มโทรกลับ

## 6. อ้างอิงโค้ด

- **Backend:**
  - `src/services/callSignaling.js` (rtc:*, สถานะสาย, ประวัติการโทร)
  - `src/services/callIce.js` (STUN / TURN, Cloudflare)
  - `src/services/callSettings.js` (ค่าจากหน้าตั้งค่า, ร่าง/Activate, cache 30 วิ)
  - `src/services/callTurnProbe.js` (ทดสอบ STUN/TURN Allocate จริง)
  - `src/routes/callSettings.js` (`/api/settings/calls`)
  - `src/services/callPush.js` (FCM / VoIP / HMS)
  - `src/services/apnsVoip.js`
  - `src/routes/calls.js`
- **เว็บ:**
  - `frontend/src/hooks/useCall.js` (mesh + perfect negotiation)
  - `frontend/src/components/CallUI.jsx`
  - `frontend/src/pages/settings/CallSettingsPage.jsx` (หน้าตั้งค่าการโทร)
- **แอป:**
  - `lib/services/calls/call_service.dart` (logic เดียวกับเว็บ)
  - `call_media_webrtc.dart`
  - `call_system_ui.dart` (CallKit)
  - `lib/screens/calls/call_overlay.dart`
