# Mobile API Security Standard (OAuth2 + Transition)

เอกสารนี้เป็นมาตรฐานความปลอดภัยสำหรับ Mobile API หลังจากนี้

## 1) Authentication Standard

- ใช้ **OAuth 2.0 Authorization Code + PKCE** สำหรับ Mobile App
- ใช้ **External IdP** (เช่น Auth0/Cognito/Keycloak) เป็นผู้ issuing token
- Mobile API ตรวจสอบ `Bearer` access token ผ่าน `JWKS` เท่านั้น
- Access token ต้องมีอย่างน้อย claim:
  - `sub` = user id
  - `business_id` (หรือ `businessId`/`org_id`) = business context

## 2) Transition Policy (Legacy Header -> OAuth)

- ช่วงย้ายระบบ:
  - `AUTH_TRANSITION_MODE=true` อนุญาต `X-User-Id` + `X-Business-Id` ชั่วคราว
- หลัง cutover:
  - `AUTH_TRANSITION_MODE=false` ปิด legacy context ทั้งหมด
- บังคับกำหนด `AUTH_TRANSITION_DEADLINE` เพื่อแจ้งวันปิดใช้งาน

## 3) API Security Baseline

- Security headers: `helmet`
- CORS allowlist ผ่าน `ALLOWED_ORIGINS`
- Request timeout และ rate limit เปิดใช้งานเสมอ
- Structured security log สำหรับ auth/cors failure
- Response error ใช้ pattern เดียว:
  - `AUTH_TOKEN_MISSING`
  - `AUTH_TOKEN_INVALID`
  - `AUTH_CONTEXT_DEPRECATED`
  - `CORS_ORIGIN_NOT_ALLOWED`

## 4) Token Policy

- Access token อายุสั้น (แนะนำ 5-15 นาที)
- Refresh token rotation จัดการที่ IdP
- ห้ามเก็บ secret/key ใน source code
- เก็บค่าความลับผ่าน environment variables เท่านั้น

### Token exchange endpoint (Mobile API)

- `POST /api/auth/login` ใช้ authorization code + code_verifier เพื่อแลก token กับ External IdP
- ตั้งค่าผ่าน env:
  - `OAUTH_TOKEN_ENDPOINT`
  - `OAUTH_CLIENT_ID`
  - `OAUTH_CLIENT_SECRET` (optional)
  - `OAUTH_REDIRECT_URI`

## 5) Endpoint Policy Levels

- `public`: ไม่ต้อง auth (`/health`, `/api/health`)
- `authenticated`: ต้องมี token ที่ valid
- `businessScoped`: ต้องมี `business_id` และ query เฉพาะ tenant
- `admin`: ต้องตรวจ scope/role เพิ่ม

### Middleware baseline

- `ensureAuthenticated` ตรวจ Bearer token (OAuth/JWKS) หรือ legacy context ตอน transition
- `requireBusinessContext` บังคับ `userId` + `businessId`
- `requireScope([...])` สำหรับ endpoint ที่ต้องการสิทธิ์พิเศษ (เช่น `admin`)

### Hybrid scope strategy

- เริ่มด้วย simple scopes:
  - `modules:read`
  - `fields:read`
  - `picklists:read`
  - `entity:read`
  - `entity:write`
  - `admin`
- รองรับ granular ในอนาคตโดยไม่ break route:
  - `entity:create`, `entity:update`, `entity:delete`
- middleware มี compatibility layer ให้ `entity:write` ผ่าน granular checks ได้

### กลุ่ม endpoint ที่ยกระดับแล้ว (phase นี้)

- `public`
  - `GET /health`
  - `GET /ready`
  - `GET /api/health`
  - `POST /api/auth/login`
- `businessScoped`
  - `GET /api/me`
  - `GET /api/example-pg`
  - `GET /api/modules`
  - `GET /api/fields/:module`
  - `GET /api/picklists`
  - `GET/POST/PUT/DELETE /api/entity/:module`
  - `POST /api/entity/:module/:id/duplicate`
- `authenticated`
  - `GET /api/example-mongo`
- `admin`
  - `GET /api/admin/policy-check` (endpoint สำหรับตรวจ policy/scopes)

## 6) Rollout Checklist

1. ตั้งค่า `OAUTH_ISSUER`, `OAUTH_AUDIENCE`, `OAUTH_JWKS_URI`
2. เปิด transition mode (`AUTH_TRANSITION_MODE=true`) ช่วงแรก
3. อัปเดต Mobile app ให้ส่ง `Authorization: Bearer <token>`
4. เฝ้าดู log `legacy_context_deprecated` และลดลงจนเป็นศูนย์
5. ปิด transition mode (`AUTH_TRANSITION_MODE=false`)
6. ลบโค้ด fallback legacy ในรอบถัดไป

## 7) Verification checklist

- No token -> `AUTH_TOKEN_MISSING`
- Invalid token -> `AUTH_TOKEN_INVALID`
- Legacy header + transition ON -> ผ่าน endpoint ระดับ businessScoped
- Legacy header + transition OFF -> `AUTH_CONTEXT_DEPRECATED`
- Scope ไม่พอ -> `AUTH_SCOPE_REQUIRED`
- Module ไม่อยู่ allowlist -> `MODULE_NOT_ALLOWED`
- Pagination เกิน limit -> `VALIDATION_FAILED`
