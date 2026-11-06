const express = require('express');
const { sendError, sendSuccess } = require('../utils/http');
const { validate, authLoginBodySchema } = require('../validation/schemas');

const OAUTH_TOKEN_ENDPOINT = process.env.OAUTH_TOKEN_ENDPOINT || '';
const OAUTH_CLIENT_ID = process.env.OAUTH_CLIENT_ID || '';
const OAUTH_CLIENT_SECRET = process.env.OAUTH_CLIENT_SECRET || '';
const OAUTH_REDIRECT_URI = process.env.OAUTH_REDIRECT_URI || '';

async function exchangeCode(body) {
  if (!OAUTH_TOKEN_ENDPOINT || !OAUTH_CLIENT_ID) {
    throw new Error('OAuth token exchange is not configured.');
  }

  const payload = new URLSearchParams();
  payload.set('grant_type', 'authorization_code');
  payload.set('code', body.code);
  payload.set('client_id', OAUTH_CLIENT_ID);
  payload.set('code_verifier', body.codeVerifier);
  payload.set('redirect_uri', body.redirectUri || OAUTH_REDIRECT_URI);
  if (OAUTH_CLIENT_SECRET) payload.set('client_secret', OAUTH_CLIENT_SECRET);

  const response = await fetch(OAUTH_TOKEN_ENDPOINT, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: payload.toString(),
  });
  const json = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(json.error_description || json.error || `Token exchange failed (${response.status})`);
  }
  return json;
}

function createAuthRouter() {
  const router = express.Router();

  router.post('/login', validate(authLoginBodySchema), async (req, res) => {
    try {
      const token = await exchangeCode(req.body);
      return sendSuccess(res, {
        token_type: token.token_type || 'Bearer',
        access_token: token.access_token,
        expires_in: token.expires_in,
        refresh_token: token.refresh_token || null,
        id_token: token.id_token || null,
        scope: token.scope || null,
      });
    } catch (err) {
      return sendError(res, 'AUTH_LOGIN_EXCHANGE_FAILED', err.message, 401);
    }
  });

  return router;
}

module.exports = { createAuthRouter };
