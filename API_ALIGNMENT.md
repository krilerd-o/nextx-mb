# MOAI NEXT Mobile API - Alignment with Web API Standard

เอกสารนี้สรุปมาตรฐานจาก Postman collection ของเว็บ:
`D:\NEXTX Kit\Git\NEXTX\docs\MOAI-NEXT-API-All-Routes.postman_collection.json`

## สิ่งที่พบจากชุดเว็บ

- มี route ทั้งหมดประมาณ **439 routes** ใน **41 กลุ่ม**
- Collection กำหนดตัวแปรมาตรฐาน: `baseUrl`, `token`, `businessId`, `userId`
- ใช้ Bearer auth ระดับ collection (`Authorization: Bearer {{token}}`)
- รูปแบบ route เป็น `/api/...` และแยกเป็นกลุ่ม domain ชัดเจน (เช่น `auth`, `me`, `fields`, `entity`, `boards`, `analytics-reports`)

## มาตรฐานที่ Mobile API ต้องยึด

1. **Response Pattern (S/E)**
   - Success:
     ```json
     { "status": "S", "messagestatus": "Success", "data": { } }
     ```
   - Error:
     ```json
     { "status": "E", "messagestatus": "Error", "error_code": "XXXX_XXXX", "message": "..." }
     ```

2. **User/Business Context**
   - **มาตรฐานหลัก:** Bearer token (OAuth2)
   - claim ที่คาดหวัง: `sub` + `business_id` (หรือ `businessId`/`org_id`)
   - ช่วง transition เท่านั้นที่ยอมรับ `X-User-Id`, `X-Business-Id` หรือ query fallback

3. **Route Naming**
   - ใช้ path style เดียวกับเว็บ: `/api/<resource>`
   - ใช้ HTTP method ตามความหมาย (GET/POST/PUT/DELETE)
   - รองรับ nested resource เมื่อเป็น ownership relation

4. **Shared DB, Separate API**
   - Mobile API แยก service จากเว็บเพื่อ performance และ scope เฉพาะ mobile
   - แต่ใช้ DB เดียวกัน (PostgreSQL + MongoDB) ตาม env ที่กำหนดไว้

## Current alignment status (nextx-mb)

- ใช้ response S/E แล้วทุก route ใน `api/src/routes/*`
- มี `GET /api/health` ตาม pattern
- มี `GET /api/me` รองรับ OAuth2 และ transition legacy context
- รองรับ env แบบเว็บ/ใหม่: `DB_*`, `PG_*`, `MONGODB_*`, `MONGO_*`
- รองรับ env ด้าน security: `OAUTH_*`, `AUTH_TRANSITION_*`, `ALLOWED_ORIGINS`

## Endpoint policy levels

- `public`: endpoint เปิดสาธารณะ เช่น `/health`, `/api/health`
- `authenticated`: ต้องมี access token ที่ verify ผ่าน JWKS
- `businessScoped`: query ต้อง bind กับ business context เสมอ
- `admin`: ต้องมี scope/role ที่สูงกว่า user ปกติ

มี middleware กลางแยกไฟล์แล้ว:
- `ensureAuthenticated`
- `requireBusinessContext`
- `requireScope(requiredScopes, options)`

ตำแหน่ง:
- `api/src/middleware/auth.js`
- `api/src/middleware/policy.js`

## Route-policy matrix (เฟสปัจจุบัน)

- `public`
  - `GET /health`
  - `GET /ready`
  - `GET /api/health`
  - `POST /api/auth/login`
- `authenticated`
  - `GET /api/example-mongo`
- `businessScoped`
  - `GET /api/me`
  - `GET /api/modules`
  - `GET /api/fields/:module`
  - `GET /api/picklists`
  - `GET/POST/PUT/DELETE /api/entity/:module`
  - `POST /api/entity/:module/:id/duplicate`
- `admin`
  - `GET /api/admin/policy-check`

## แนวทางทำ endpoint ใหม่ (บังคับใช้)

ทุก endpoint ใหม่ใน Mobile API ให้ทำตาม checklist นี้:

- [ ] path อยู่ใต้ `/api/...`
- [ ] validate input และ context (`userId`, `businessId`) ก่อน query
- [ ] ตอบกลับด้วยรูปแบบ S/E เท่านั้น
- [ ] ใช้ `error_code` ที่อ่านแล้วเข้าใจ domain
- [ ] ไม่ query ข้าม business โดยไม่ใส่เงื่อนไขสิทธิ์
- [ ] รองรับ pagination/filter/sort ใน endpoint list
- [ ] กำหนด policy level (`public/authenticated/businessScoped/admin`) ชัดเจน

## Priority endpoints (mobile-first baseline)

1. `POST /api/auth/login`
2. `GET /api/me`
3. `GET /api/modules`
4. `GET /api/entity/:module`
5. `POST /api/entity/:module`
6. `PUT /api/entity/:module/:id`
7. `DELETE /api/entity/:module/:id`
8. `GET /api/fields/:module`
9. `GET /api/picklists`

> หมายเหตุ: แม้เว็บมี route จำนวนมาก ให้เลือกเฉพาะที่ mobile ใช้จริงก่อน แล้วค่อยขยาย

## ไอแซคบันทึกประชุม (AI Minute Meeting) — `/api/ai/minutes`, `/api/public/minutes`

Menu key `ai-minute-meeting` (AI group). Backend: NEXTX `backend/src/routes/aiMinutes.js`, `publicAiMinutes.js`, docs `backend/docs/ai-minutes.md`.

| App | API |
|---|---|
| `getMinutesConfig` | `GET /api/ai/minutes/config` |
| `getMinuteMeetings` | `GET /api/ai/minutes?q=&source=&status=&limit=&offset=` |
| `createMinuteMeeting` / `uploadMinutePart` / `pause` / `resume` / `stopMinuteMeeting` | `POST /api/ai/minutes`, `/:id/parts`, `/:id/pause`, `/:id/resume`, `/:id/stop` (queued in `RecordingUploadQueue`, target `minute`) |
| live captions / translation | socket `stt:start {session_kind:'minute'}`, `stt:audio {meeting_id, pcm}`, `minute:translate` → `stt:segment`, `minute:segment_tr` |
| `getMinuteMeeting` / `updateMinuteMeeting` / `deleteMinuteMeeting` / `retryMinuteMeeting` | `GET/PATCH/DELETE /api/ai/minutes/:id`, `POST /:id/retry` |
| `editMinuteSegment`, `summarizeMinuteMeeting`, `translateMinuteMeeting`, `askMinuteMeeting`, `createMinuteTasks` | `PATCH /:id/segments/:seq`, `POST /:id/summarize`, `/translate`, `/ask`, `/actions/create-tasks` |
| `downloadMinuteExport`, `downloadMinuteMedia` | `GET /:id/export?format=pdf|docx|md|txt|srt|vtt`, `GET /:id/media` |
| `getMinuteLinks` / `createMinuteLink` / `revokeMinuteLink`, `emailMinutes` | `GET/POST /:id/share/links`, `DELETE /share/links/:linkId`, `POST /:id/share/email` |
| `MinuteUploader` | `POST /uploads`, `GET /uploads/:uid`, `PUT /uploads/:uid/parts/:n` (raw 16 MB parts), `POST /uploads/:uid/complete`, `DELETE /uploads/:uid` (phone video of a recording: `meeting_id` in the start body) |
| rooms | `POST /rooms`, `GET /rooms/:mid`, `PATCH /rooms/:mid/settings`, `POST /rooms/:mid/end`, `GET /rooms/:mid/participants`, `POST /rooms/:mid/admit|remove|cohost|invite`; public `GET/POST /api/public/minutes/rooms/:code[/join|/leave]` |
| room captions | socket `minute:room_join`, `minute:room_lang`, `minute:room_stt`, `minute:room_audio`, `minute:room_wait` → `minute:caption`, `minute:caption_tr`, `minute:room_admit`, `minute:room_waiting` |
| processing | socket `ai:minute_status`, `ai:minute_ready`, `ai:minute_translation` |
