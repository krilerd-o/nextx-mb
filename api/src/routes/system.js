const express = require('express');
const { queryPg, isPgReady } = require('../db/postgres');
const { getMongoDb, isMongoReady } = require('../db/mongo');
const { sendError, sendSuccess } = require('../utils/http');

function createSystemRouter(policy) {
  const router = express.Router();

  router.get('/health', (req, res) => sendSuccess(res, {
    ok: true,
    service: 'nextx-mobile-api',
    postgres: isPgReady(),
    mongodb: isMongoReady(),
  }));

  router.get('/ready', (req, res) => {
    const ready = isPgReady() && isMongoReady();
    return sendSuccess(res, {
      ok: ready,
      service: 'nextx-mobile-api',
      postgres: isPgReady(),
      mongodb: isMongoReady(),
    }, 'Success', ready ? 200 : 503);
  });

  router.get('/me', ...policy.businessScoped, async (req, res) => {
    const { userId, businessId } = req.authContext;
    if (!isPgReady()) return sendError(res, 'POSTGRES_NOT_READY', 'PostgreSQL not connected', 503);
    try {
      const userResult = await queryPg(
        'SELECT * FROM aicrm_users WHERE id = $1 LIMIT 1',
        [userId],
      );
      const businessResult = await queryPg(
        'SELECT * FROM aicrm_business WHERE id = $1 LIMIT 1',
        [businessId],
      );
      const userRow = userResult.rows[0] || null;
      const businessRow = businessResult.rows[0] || null;
      return sendSuccess(res, {
        user: userRow || { id: userId },
        business: businessRow || { id: businessId },
        auth_source: req.authContext.source,
      });
    } catch (err) {
      return sendError(res, 'ME_QUERY_FAILED', err.message, 500);
    }
  });

  router.get('/example-pg', ...policy.businessScoped, async (req, res) => {
    if (!isPgReady()) return sendError(res, 'POSTGRES_NOT_READY', 'PostgreSQL not connected', 503);
    try {
      const result = await queryPg('SELECT 1 as ok');
      return sendSuccess(res, result.rows);
    } catch (err) {
      return sendError(res, 'PG_QUERY_FAILED', err.message, 500);
    }
  });

  router.get('/example-mongo', ...policy.authenticated, async (req, res) => {
    if (!isMongoReady()) return sendError(res, 'MONGODB_NOT_READY', 'MongoDB not connected', 503);
    try {
      const db = getMongoDb();
      const col = db.collection(process.env.MONGO_COLLECTION || 'example');
      const docs = await col.find({}).limit(10).toArray();
      return sendSuccess(res, docs);
    } catch (err) {
      return sendError(res, 'MONGODB_QUERY_FAILED', err.message, 500);
    }
  });

  router.get('/admin/policy-check', ...policy.admin, (req, res) => {
    return sendSuccess(res, {
      ok: true,
      policy: 'admin',
      scopes: req.authContext?.scopes || [],
    });
  });

  return router;
}

module.exports = { createSystemRouter };
