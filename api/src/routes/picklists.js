const express = require('express');
const { queryPg, isPgReady } = require('../db/postgres');
const { sendError, sendSuccess } = require('../utils/http');
const { validate, paginationQuerySchema } = require('../validation/schemas');

function createPicklistsRouter(policy, requireScope) {
  const router = express.Router();

  router.get(
    '/',
    ...policy.businessScoped,
    requireScope(['picklists:read'], { mode: 'any', allowLegacyBypass: true }),
    validate(paginationQuerySchema, 'query'),
    async (req, res) => {
      if (!isPgReady()) return sendError(res, 'POSTGRES_NOT_READY', 'PostgreSQL not connected', 503);
      const { businessId } = req.authContext;
      const { limit, offset } = req.query;
      try {
        const result = await queryPg(
          `SELECT *
           FROM aicrm_picklists
           WHERE business_id = $1
           ORDER BY id DESC
           LIMIT $2 OFFSET $3`,
          [businessId, limit, offset],
        );
        return sendSuccess(res, { items: result.rows, limit, offset });
      } catch (err) {
        if (err.code === '42P01') return sendSuccess(res, { items: [], limit, offset });
        return sendError(res, 'PICKLISTS_QUERY_FAILED', err.message, 500);
      }
    },
  );

  return router;
}

module.exports = { createPicklistsRouter };
