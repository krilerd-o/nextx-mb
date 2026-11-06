require('dotenv').config();
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const { initPg, isPgReady } = require('./db/postgres');
const { initMongo, isMongoReady } = require('./db/mongo');
const { sendError } = require('./utils/http');
const { ensureAuthenticated, logSecurity } = require('./middleware/auth');
const { requireScope, buildPolicy } = require('./middleware/policy');
const { requestIdMiddleware, requestLogMiddleware } = require('./middleware/observability');
const { createAuthRouter } = require('./routes/auth');
const { createModulesRouter } = require('./routes/modules');
const { createFieldsRouter } = require('./routes/fields');
const { createPicklistsRouter } = require('./routes/picklists');
const { createEntityRouter } = require('./routes/entity');
const { createSystemRouter } = require('./routes/system');

const app = express();
const PORT = process.env.PORT || 4000;
const ALLOWED_ORIGINS = (process.env.ALLOWED_ORIGINS || '')
  .split(',')
  .map((x) => x.trim())
  .filter(Boolean);

app.use(requestIdMiddleware);
app.use(requestLogMiddleware);
app.use(helmet());
app.use(cors({
  origin(origin, callback) {
    if (!origin) return callback(null, true);
    if (ALLOWED_ORIGINS.length === 0 || ALLOWED_ORIGINS.includes(origin)) return callback(null, true);
    return callback(new Error('CORS_NOT_ALLOWED'));
  },
}));
app.use(express.json({ limit: '1mb' }));

// Request timeout (ms) — ป้องกัน request ค้าง
const REQ_TIMEOUT = parseInt(process.env.REQUEST_TIMEOUT_MS || '30000', 10);
app.use((req, res, next) => {
  req.setTimeout(REQ_TIMEOUT);
  res.setTimeout(REQ_TIMEOUT);
  next();
});

// Rate limit — รองรับหลักพันคน แต่จำกัดต่อ IP ป้องกัน abuse (ปรับได้ผ่าน env)
const RATE_WINDOW_MS = parseInt(process.env.RATE_LIMIT_WINDOW_MS || '60000', 10);
const RATE_MAX = parseInt(process.env.RATE_LIMIT_MAX_PER_IP || '300', 10);
const limiter = rateLimit({
  windowMs: RATE_WINDOW_MS,
  max: RATE_MAX,
  message: {
    status: 'E',
    messagestatus: 'Error',
    error_code: 'RATE_LIMIT_EXCEEDED',
    message: 'Too many requests, please try again later.',
  },
  standardHeaders: true,
  legacyHeaders: false,
});
app.use('/api/', limiter); // /health ไม่ผ่าน limiter (path ไม่ตรง /api/)

const policy = buildPolicy(ensureAuthenticated);

app.get('/health', (req, res) => {
  return res.status(200).json({
    status: 'S',
    messagestatus: 'Success',
    data: {
      ok: true,
      service: 'nextx-mobile-api',
      postgres: isPgReady(),
      mongodb: isMongoReady(),
    },
  });
});

app.get('/ready', (req, res) => {
  const ready = isPgReady() && isMongoReady();
  return res.status(ready ? 200 : 503).json({
    status: 'S',
    messagestatus: 'Success',
    data: {
      ok: ready,
      service: 'nextx-mobile-api',
      postgres: isPgReady(),
      mongodb: isMongoReady(),
    },
  });
});

app.use('/api/auth', createAuthRouter());
app.use('/api/modules', createModulesRouter(policy, requireScope));
app.use('/api/fields', createFieldsRouter(policy, requireScope));
app.use('/api/picklists', createPicklistsRouter(policy, requireScope));
app.use('/api/entity', createEntityRouter(policy, requireScope));
app.use('/api', createSystemRouter(policy));

app.use((err, req, res, next) => {
  if (!err) return next();
  if (err.message === 'CORS_NOT_ALLOWED') {
    logSecurity('cors_origin_blocked', req, { origin: req.header('origin') || null });
    return sendError(res, 'CORS_ORIGIN_NOT_ALLOWED', 'Origin is not allowed by CORS policy.', 403);
  }
  return sendError(res, 'INTERNAL_SERVER_ERROR', err.message || 'Internal server error', 500);
});

async function start() {
  app.listen(PORT, () => {
    console.log(`nextx-mobile-api listening on port ${PORT}`);
  });

  try {
    await initPg();
    console.log('PostgreSQL connected');
  } catch (err) {
    console.warn('PostgreSQL not available:', err.message);
  }
  try {
    await initMongo();
    console.log('MongoDB connected');
  } catch (err) {
    console.warn('MongoDB not available:', err.message);
  }
}

start();
