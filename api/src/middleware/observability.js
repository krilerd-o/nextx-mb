const crypto = require('crypto');

function requestIdMiddleware(req, res, next) {
  req.requestId = req.header('X-Request-Id') || crypto.randomUUID();
  res.setHeader('X-Request-Id', req.requestId);
  next();
}

function requestLogMiddleware(req, res, next) {
  const startedAt = Date.now();
  res.on('finish', () => {
    const durationMs = Date.now() - startedAt;
    const authSource = req.authContext?.source || 'none';
    console.log(JSON.stringify({
      level: 'info',
      type: 'request',
      requestId: req.requestId,
      method: req.method,
      path: req.path,
      statusCode: res.statusCode,
      durationMs,
      authSource,
    }));
  });
  next();
}

module.exports = { requestIdMiddleware, requestLogMiddleware };
