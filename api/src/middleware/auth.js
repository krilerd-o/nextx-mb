const { createRemoteJWKSet, jwtVerify } = require('jose');
const { sendError } = require('../utils/http');

const AUTH_TRANSITION_MODE = (process.env.AUTH_TRANSITION_MODE || 'true').toLowerCase() === 'true';
const AUTH_TRANSITION_DEADLINE = process.env.AUTH_TRANSITION_DEADLINE || '';
const OAUTH_ISSUER = process.env.OAUTH_ISSUER || '';
const OAUTH_AUDIENCE = process.env.OAUTH_AUDIENCE || '';
const OAUTH_JWKS_URI = process.env.OAUTH_JWKS_URI || '';
const jwks = OAUTH_JWKS_URI ? createRemoteJWKSet(new URL(OAUTH_JWKS_URI)) : null;

function logSecurity(event, req, details = {}) {
  console.warn(JSON.stringify({
    level: 'warn',
    type: 'security',
    event,
    requestId: req.requestId,
    path: req.path,
    method: req.method,
    ip: req.ip,
    ...details,
  }));
}

function normalizeScopes(payload) {
  if (!payload || typeof payload !== 'object') return [];
  const fromScope = typeof payload.scope === 'string' ? payload.scope.split(' ') : [];
  const fromScp = Array.isArray(payload.scp) ? payload.scp : [];
  return [...new Set([...fromScope, ...fromScp].map((x) => String(x).trim()).filter(Boolean))];
}

function getLegacyContext(req) {
  return {
    userId: req.header('X-User-Id') || req.query.userId || null,
    businessId: req.header('X-Business-Id') || req.query.businessId || null,
  };
}

async function verifyAccessToken(req) {
  const authHeader = req.header('Authorization') || '';
  if (!authHeader.startsWith('Bearer ')) return null;
  if (!jwks || !OAUTH_ISSUER || !OAUTH_AUDIENCE) return null;
  const token = authHeader.slice('Bearer '.length).trim();
  const { payload } = await jwtVerify(token, jwks, {
    issuer: OAUTH_ISSUER,
    audience: OAUTH_AUDIENCE,
  });
  return payload;
}

async function resolveAuthContext(req) {
  try {
    const payload = await verifyAccessToken(req);
    if (payload) {
      return {
        source: 'oauth',
        userId: String(payload.sub || ''),
        businessId: String(
          payload.business_id || payload.businessId || payload.org_id || payload.organization_id || '',
        ),
        scopes: normalizeScopes(payload),
        claims: payload,
      };
    }
  } catch (err) {
    logSecurity('oauth_token_invalid', req, { reason: err.message });
    throw { code: 'AUTH_TOKEN_INVALID', message: 'Invalid or expired access token.', statusCode: 401 };
  }

  const legacy = getLegacyContext(req);
  if (legacy.userId && legacy.businessId && AUTH_TRANSITION_MODE) {
    return {
      source: 'legacy',
      userId: String(legacy.userId),
      businessId: String(legacy.businessId),
      scopes: [],
      claims: {},
    };
  }

  if (legacy.userId || legacy.businessId) {
    logSecurity('legacy_context_deprecated', req, { deadline: AUTH_TRANSITION_DEADLINE || null });
    throw {
      code: 'AUTH_CONTEXT_DEPRECATED',
      message: 'Legacy auth context is disabled. Use OAuth 2.0 Bearer token.',
      statusCode: 401,
    };
  }

  throw {
    code: 'AUTH_TOKEN_MISSING',
    message: 'Authorization Bearer token is required.',
    statusCode: 401,
  };
}

function sendAuthError(res, err) {
  return sendError(res, err.code || 'AUTH_FAILED', err.message || 'Unauthorized', err.statusCode || 401);
}

async function ensureAuthenticated(req, res, next) {
  if (req.authContext) return next();
  try {
    req.authContext = await resolveAuthContext(req);
    return next();
  } catch (err) {
    return sendAuthError(res, err);
  }
}

module.exports = {
  AUTH_TRANSITION_MODE,
  ensureAuthenticated,
  resolveAuthContext,
  logSecurity,
};
