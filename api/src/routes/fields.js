const express = require('express');
const { queryPg, isPgReady } = require('../db/postgres');
const { sendError, sendSuccess } = require('../utils/http');
const { getModuleConfig } = require('../domain/moduleRegistry');
const { validate, moduleParamSchema } = require('../validation/schemas');

function createFieldsRouter(policy, requireScope) {
  const router = express.Router();

  router.get(
    '/:module',
    ...policy.businessScoped,
    requireScope(['fields:read'], { mode: 'any', allowLegacyBypass: true }),
    validate(moduleParamSchema, 'params'),
    async (req, res) => {
      if (!isPgReady()) return sendError(res, 'POSTGRES_NOT_READY', 'PostgreSQL not connected', 503);
      const cfg = getModuleConfig(req.params.module);
      if (!cfg) return sendError(res, 'MODULE_NOT_ALLOWED', `Module "${req.params.module}" is not allowed.`, 400);
      try {
        const result = await queryPg(
          `SELECT column_name, data_type
           FROM information_schema.columns
           WHERE table_schema = 'public' AND table_name = $1
           ORDER BY ordinal_position`,
          [cfg.table],
        );
        return sendSuccess(res, {
          module: req.params.module,
          table: cfg.table,
          fields: result.rows,
        });
      } catch (err) {
        return sendError(res, 'FIELDS_QUERY_FAILED', err.message, 500);
      }
    },
  );

  return router;
}

module.exports = { createFieldsRouter };
