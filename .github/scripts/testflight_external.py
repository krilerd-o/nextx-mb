#!/usr/bin/env python3
"""
TestFlight External testing for a freshly uploaded build (App Store Connect API).

  1. find the app (bundle id) and wait until the build has processed
  2. export compliance (usesNonExemptEncryption = false) when not set yet
  3. "What to Test" (th + en-US), beta app description / feedback email / privacy URL
  4. Beta App Review details: contact + demo account (the reviewer must sign in)
  5. external group "External Testers" with the public link turned on, build added to it
  6. submit the build for Beta App Review (skipped when already submitted / approved)
  7. writes the public link + review state to $GITHUB_STEP_SUMMARY

Secrets come from the environment and are never printed.
Required: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8 (PEM text), BUILD_NUMBER, APP_VERSION,
          TF_REVIEW_SERVER, TF_REVIEW_USER, TF_REVIEW_PASSWORD,
          TF_CONTACT_FIRST, TF_CONTACT_LAST, TF_CONTACT_EMAIL, TF_CONTACT_PHONE
Optional: BUNDLE_ID (com.moai.nextt.mobile), TF_WHATS_NEW, TF_FEEDBACK_EMAIL, TF_PRIVACY_URL,
          TF_GROUP_NAME (External Testers), TF_WAIT_MINUTES (45)
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request

API = 'https://api.appstoreconnect.apple.com/v1'
REQUIRED = [
    'ASC_KEY_ID', 'ASC_ISSUER_ID', 'ASC_KEY_P8', 'BUILD_NUMBER', 'APP_VERSION',
    'TF_REVIEW_SERVER', 'TF_REVIEW_USER', 'TF_REVIEW_PASSWORD',
    'TF_CONTACT_FIRST', 'TF_CONTACT_LAST', 'TF_CONTACT_EMAIL', 'TF_CONTACT_PHONE',
]
SECRET_KEYS = {'ASC_KEY_P8', 'TF_REVIEW_PASSWORD', 'TF_REVIEW_USER'}


class AscError(RuntimeError):
    pass


def env(name, default=''):
    return (os.environ.get(name) or default).strip()


def log(msg):
    print(msg, flush=True)


def make_token():
    import jwt  # pyjwt[crypto]
    now = int(time.time())
    return jwt.encode(
        {'iss': env('ASC_ISSUER_ID'), 'iat': now, 'exp': now + 15 * 60, 'aud': 'appstoreconnect-v1'},
        os.environ['ASC_KEY_P8'],
        algorithm='ES256',
        headers={'kid': env('ASC_KEY_ID'), 'typ': 'JWT'},
    )


class Asc:
    """Tiny JSON:API client. `transport` can be replaced in tests."""

    def __init__(self, transport=None):
        self._token = None
        self._token_at = 0
        self.transport = transport or self._http

    def _auth(self):
        if not self._token or time.time() - self._token_at > 10 * 60:
            self._token = make_token()
            self._token_at = time.time()
        return self._token

    def _http(self, method, url, body):
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(url, data=data, method=method)
        req.add_header('Authorization', f'Bearer {self._auth()}')
        if data is not None:
            req.add_header('Content-Type', 'application/json')
        try:
            with urllib.request.urlopen(req, timeout=60) as res:
                raw = res.read()
                return res.status, (json.loads(raw) if raw else {})
        except urllib.error.HTTPError as e:
            raw = e.read()
            try:
                return e.code, json.loads(raw)
            except Exception:
                return e.code, {'errors': [{'detail': raw.decode(errors='replace')[:500]}]}

    def call(self, method, path, body=None, ok=(200, 201, 204)):
        url = path if path.startswith('http') else f'{API}{path}'
        status, data = self.transport(method, url, body)
        if status not in ok:
            errs = (data or {}).get('errors') or []
            detail = '; '.join(f"{e.get('title', '')}: {e.get('detail', '')}".strip(': ') for e in errs) or str(data)[:300]
            raise AscError(f'{method} {path.split("?")[0]} → HTTP {status}: {detail}')
        return status, data

    def get(self, path):
        return self.call('GET', path)[1]


def rel(type_, id_):
    return {'data': {'type': type_, 'id': id_}}


def run(asc, sleep=time.sleep):
    bundle = env('BUNDLE_ID', 'com.moai.nextt.mobile')
    version = env('APP_VERSION')
    build_no = env('BUILD_NUMBER')
    whats_new = env('TF_WHATS_NEW') or 'ทดสอบเวอร์ชันใหม่ของ NEXTX Mobile'
    group_name = env('TF_GROUP_NAME', 'External Testers')
    wait_min = int(env('TF_WAIT_MINUTES', '45') or 45)

    apps = asc.get(f'/apps?filter[bundleId]={bundle}&limit=1').get('data') or []
    if not apps:
        raise AscError(f'ไม่พบแอป bundle {bundle} ใน App Store Connect')
    app_id = apps[0]['id']
    log(f'app {bundle} → {app_id}')

    # 1) wait for processing
    build = None
    deadline = time.time() + wait_min * 60
    while True:
        rows = asc.get(
            f'/builds?filter[app]={app_id}&filter[version]={build_no}'
            f'&filter[preReleaseVersion.version]={version}&limit=1'
        ).get('data') or []
        if rows:
            build = rows[0]
            state = build['attributes'].get('processingState')
            log(f'build {version} ({build_no}) processingState={state}')
            if state == 'VALID':
                break
            if state in ('FAILED', 'INVALID'):
                raise AscError(f'Apple ประมวลผล build ไม่ผ่าน: {state}')
        else:
            log(f'build {version} ({build_no}) not visible yet')
        if time.time() > deadline:
            raise AscError(f'รอ build ประมวลผลเกิน {wait_min} นาที — สั่งงานนี้ใหม่ภายหลังได้ (ข้ามการอัปโหลด)')
        sleep(30)
    build_id = build['id']

    # 2) export compliance
    if build['attributes'].get('usesNonExemptEncryption') is None:
        asc.call('PATCH', f'/builds/{build_id}', {'data': {'type': 'builds', 'id': build_id, 'attributes': {'usesNonExemptEncryption': False}}})
        log('export compliance: usesNonExemptEncryption=false')

    # 3) what to test (per build) + beta app info (per app)
    have = {r['attributes']['locale']: r['id'] for r in asc.get(f'/builds/{build_id}/betaBuildLocalizations').get('data') or []}
    for loc in ('th', 'en-US'):
        if loc in have:
            asc.call('PATCH', f'/betaBuildLocalizations/{have[loc]}', {'data': {'type': 'betaBuildLocalizations', 'id': have[loc], 'attributes': {'whatsNew': whats_new}}})
        else:
            asc.call('POST', '/betaBuildLocalizations', {'data': {'type': 'betaBuildLocalizations', 'attributes': {'locale': loc, 'whatsNew': whats_new}, 'relationships': {'build': rel('builds', build_id)}}})
    log('what to test: set (th, en-US)')

    feedback = env('TF_FEEDBACK_EMAIL') or env('TF_CONTACT_EMAIL')
    privacy = env('TF_PRIVACY_URL') or (env('TF_REVIEW_SERVER').rstrip('/') + '/privacy')
    desc = ('NEXTX Mobile — CRM, Workspace, HR, chat and service jobs for MOAI NEXT teams. '
            'Sign in to your company Space (server URL) with your NEXTX account.')
    app_locs = asc.get(f'/apps/{app_id}/betaAppLocalizations').get('data') or []
    en = next((r for r in app_locs if r['attributes'].get('locale') == 'en-US'), None)
    attrs = {'description': desc, 'feedbackEmail': feedback, 'privacyPolicyUrl': privacy}
    if en:
        missing = {k: v for k, v in attrs.items() if not en['attributes'].get(k)}
        if missing:
            asc.call('PATCH', f"/betaAppLocalizations/{en['id']}", {'data': {'type': 'betaAppLocalizations', 'id': en['id'], 'attributes': missing}})
    else:
        asc.call('POST', '/betaAppLocalizations', {'data': {'type': 'betaAppLocalizations', 'attributes': {'locale': 'en-US', **attrs}, 'relationships': {'app': rel('apps', app_id)}}})
    log('beta app information: ok')

    # 4) review details (contact + demo account)
    detail = asc.get(f'/apps/{app_id}/betaAppReviewDetail').get('data')
    if not detail:
        raise AscError('ไม่พบ betaAppReviewDetail ของแอป')
    notes = (
        'This is a business app; every company has its own server ("Space").\n'
        f'1) Open the app → enter Server URL: {env("TF_REVIEW_SERVER")}\n'
        '2) Sign in with the demo account below (email + password).\n'
        'The demo account belongs to a test company and contains sample data only.'
    )
    asc.call('PATCH', f"/betaAppReviewDetails/{detail['id']}", {'data': {'type': 'betaAppReviewDetails', 'id': detail['id'], 'attributes': {
        'contactFirstName': env('TF_CONTACT_FIRST'),
        'contactLastName': env('TF_CONTACT_LAST'),
        'contactEmail': env('TF_CONTACT_EMAIL'),
        'contactPhone': env('TF_CONTACT_PHONE'),
        'demoAccountRequired': True,
        'demoAccountName': env('TF_REVIEW_USER'),
        'demoAccountPassword': env('TF_REVIEW_PASSWORD'),
        'notes': notes,
    }}})
    log('review details: contact + demo account set')

    # 5) external group with public link
    groups = asc.get(f'/betaGroups?filter[app]={app_id}&limit=200').get('data') or []
    group = next((g for g in groups if g['attributes'].get('name') == group_name and not g['attributes'].get('isInternalGroup')), None)
    if not group:
        _, created = asc.call('POST', '/betaGroups', {'data': {'type': 'betaGroups', 'attributes': {
            'name': group_name, 'publicLinkEnabled': True, 'publicLinkLimitEnabled': False, 'feedbackEnabled': True,
        }, 'relationships': {'app': rel('apps', app_id)}}})
        group = created['data']
        log(f'external group "{group_name}" created')
    elif not group['attributes'].get('publicLinkEnabled'):
        _, upd = asc.call('PATCH', f"/betaGroups/{group['id']}", {'data': {'type': 'betaGroups', 'id': group['id'], 'attributes': {'publicLinkEnabled': True, 'publicLinkLimitEnabled': False}}})
        group = upd['data']
    asc.call('POST', f"/betaGroups/{group['id']}/relationships/builds", {'data': [{'type': 'builds', 'id': build_id}]}, ok=(200, 201, 204, 409))
    log('build added to the external group')

    # 6) submit for beta review
    subs = asc.get(f'/betaAppReviewSubmissions?filter[build]={build_id}&limit=1').get('data') or []
    if subs:
        state = subs[0]['attributes'].get('betaReviewState')
        log(f'already submitted: {state}')
    else:
        status, res = asc.call('POST', '/betaAppReviewSubmissions', {'data': {'type': 'betaAppReviewSubmissions', 'relationships': {'build': rel('builds', build_id)}}}, ok=(200, 201, 409))
        state = (res.get('data') or {}).get('attributes', {}).get('betaReviewState') if status != 409 else 'ALREADY_SUBMITTED'
        log(f'submitted for beta review: {state}')

    fresh = asc.get(f"/betaGroups/{group['id']}").get('data') or group
    link = fresh['attributes'].get('publicLink') or '(Apple จะสร้างลิงก์ให้หลังอนุมัติรีวิว — ดูใน App Store Connect › TestFlight › External Testers)'
    summary = (
        f'### TestFlight External\n\n'
        f'- Build: **{version} ({build_no})**\n'
        f'- Beta App Review: **{state}**\n'
        f'- Group: **{group_name}**\n'
        f'- Public link: {link}\n'
    )
    log(summary)
    path = os.environ.get('GITHUB_STEP_SUMMARY')
    if path:
        with open(path, 'a', encoding='utf-8') as f:
            f.write(summary + '\n')
    return {'build_id': build_id, 'group_id': group['id'], 'state': state, 'link': link}


def main():
    missing = [k for k in REQUIRED if not env(k)]
    if missing:
        print('::error::TestFlight External ต้องมี GitHub Secrets/ค่าเหล่านี้: ' + ', '.join(missing), file=sys.stderr)
        sys.exit(2)
    try:
        run(Asc())
    except AscError as e:
        print(f'::error::{e}', file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
