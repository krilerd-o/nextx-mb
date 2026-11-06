const { sendError } = require('../utils/http');
const { AUTH_TRANSITION_MODE, logSecurity } = require('./auth');

const SIMPLE_TO_GRANULAR_SCOPE = {
  'entity:write': ['entity:create', 'entity:update', 'entity:delete'],
};

function expandScopes(scopes) {
  const set = new Set(scopes || []);
  for (const [simple, granular] of Object.entries(SIMPLE_TO_GRANULAR_SCOPE)) {
    if (set.has(simple)) granular.forEach((s) => set.add(s));
  }
  return set;
}

function requireBusinessContext(req, res, next) {
  const auth = req.authContext;
  if (!auth?.userId || !auth?.businessId) {
    return sendError(
      res,
      'AUTH_CONTEXT_REQUIRED',
      'userId/businessId is required in token or transition headers.',
      401,
    );
  }
  return next();
}

function requireScope(requiredScopes, options = {}) {
  const { mode = 'all', allowLegacyBypass = false } = options;
  const expected = Array.isArray(requiredScopes) ? requiredScopes : [requiredScopes];
  return (req, res, next) => {
    const auth = req.authContext;
    if (!auth) return sendError(res, 'AUTH_NOT_INITIALIZED', 'Authentication middleware is missing.', 500);
    if (auth.source === 'legacy' && allowLegacyBypass && AUTH_TRANSITION_MODE) return next();
    const scopeSet = expandScopes(auth.scopes || []);
    const hasScope = mode === 'any'
      ? expected.some((s) => scopeSet.has(s))
      : expected.every((s) => scopeSet.has(s));
    if (!hasScope) {
      logSecurity('oauth_scope_missing', req, { requiredScopes: expected, scopes: auth.scopes || [] });
      return sendError(res, 'AUTH_SCOPE_REQUIRED', `Missing required scope: ${expected.join(', ')}`, 403);
    }
    return next();
  };
}

function buildPolicy(ensureAuthenticated) {
  return {
    public: [],
    authenticated: [ensureAuthenticated],
    businessScoped: [ensureAuthenticated, requireBusinessContext],
    admin: [ensureAuthenticated, requireScope(['admin'], { mode: 'any' })],
  };
}

module.exports = { requireBusinessContext, requireScope, buildPolicy };
