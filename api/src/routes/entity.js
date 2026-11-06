const express = require('express');
const { queryPg, isPgReady } = require('../db/postgres');
const { sendError, sendSuccess } = require('../utils/http');
const { getModuleConfig } = require('../domain/moduleRegistry');
const {
  validate,
  moduleParamSchema,
  moduleIdParamSchema,
  paginationQuerySchema,
  entityWriteBodySchema,
} = require('../validation/schemas');

function quoteIdentifier(x) {
  return `"${String(x).replace(/"/g, '""')}"`;
}

async function getAllowedColumns(table) {
  const result = await queryPg(
    `SELECT column_name
     FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = $1`,
    [table],
  );
  return new Set(result.rows.map((x) => x.column_name));
}

function createEntityRouter(policy, requireScope) {
  const router = express.Router();

  router.get(
    '/:module',
    ...policy.businessScoped,
    requireScope(['entity:read'], { mode: 'any', allowLegacyBypass: true }),
    validate(moduleParamSchema, 'params'),
    validate(paginationQuerySchema, 'query'),
    async (req, res) => {
      if (!isPgReady()) return sendError(res, 'POSTGRES_NOT_READY', 'PostgreSQL not connected', 503);
      const cfg = getModuleConfig(req.params.module);
      if (!cfg) return sendError(res, 'MODULE_NOT_ALLOWED', `Module "${req.params.module}" is not allowed.`, 400);

      const { businessId } = req.authContext;
      const { limit, offset } = req.query;
      try {
        const result = await queryPg(
          `SELECT *
           FROM ${quoteIdentifier(cfg.table)}
           WHERE ${quoteIdentifier(cfg.businessColumn)} = $1
           ORDER BY ${quoteIdentifier(cfg.idColumn)} DESC
           LIMIT $2 OFFSET $3`,
          [businessId, limit, offset],
        );
        return sendSuccess(res, { items: result.rows, limit, offset });
      } catch (err) {
        return sendError(res, 'ENTITY_LIST_FAILED', err.message, 500);
      }
    },
  );

  router.post(
    '/:module',
    ...policy.businessScoped,
    requireScope(['entity:write', 'entity:create'], { mode: 'any', allowLegacyBypass: true }),
    validate(moduleParamSchema, 'params'),
    validate(entityWriteBodySchema, 'body'),
    async (req, res) => {
      if (!isPgReady()) return sendError(res, 'POSTGRES_NOT_READY', 'PostgreSQL not connected', 503);
      const cfg = getModuleConfig(req.params.module);
      if (!cfg) return sendError(res, 'MODULE_NOT_ALLOWED', `Module "${req.params.module}" is not allowed.`, 400);
      const payload = req.body.payload || req.body;
      try {
        const cols = await getAllowedColumns(cfg.table);
        const keys = Object.keys(payload).filter((k) => cols.has(k) && k !== cfg.idColumn);
        if (!cols.has(cfg.businessColumn)) {
          return sendError(res, 'MODULE_NOT_BUSINESS_SCOPED', `Module "${req.params.module}" missing business column.`, 400);
        }
        const insertKeys = [...keys.filter((k) => k !== cfg.businessColumn), cfg.businessColumn];
        const values = insertKeys.map((k) => (k === cfg.businessColumn ? req.authContext.businessId : payload[k]));
        const placeholders = insertKeys.map((_, i) => `$${i + 1}`).join(', ');
        const sql = `INSERT INTO ${quoteIdentifier(cfg.table)} (${insertKeys.map(quoteIdentifier).join(', ')})
                     VALUES (${placeholders})
                     RETURNING *`;
        const result = await queryPg(sql, values);
        return sendSuccess(res, result.rows[0], 'Success', 201);
      } catch (err) {
        return sendError(res, 'ENTITY_CREATE_FAILED', err.message, 500);
      }
    },
  );

  router.put(
    '/:module/:id',
    ...policy.businessScoped,
    requireScope(['entity:write', 'entity:update'], { mode: 'any', allowLegacyBypass: true }),
    validate(moduleIdParamSchema, 'params'),
    validate(entityWriteBodySchema, 'body'),
    async (req, res) => {
      if (!isPgReady()) return sendError(res, 'POSTGRES_NOT_READY', 'PostgreSQL not connected', 503);
      const cfg = getModuleConfig(req.params.module);
      if (!cfg) return sendError(res, 'MODULE_NOT_ALLOWED', `Module "${req.params.module}" is not allowed.`, 400);
      const payload = req.body.payload || req.body;
      try {
        const cols = await getAllowedColumns(cfg.table);
        const keys = Object.keys(payload).filter((k) => cols.has(k) && k !== cfg.idColumn && k !== cfg.businessColumn);
        if (keys.length === 0) return sendError(res, 'ENTITY_UPDATE_EMPTY', 'No valid fields to update.', 400);
        const sets = keys.map((k, i) => `${quoteIdentifier(k)} = $${i + 1}`).join(', ');
        const values = keys.map((k) => payload[k]);
        values.push(req.params.id, req.authContext.businessId);
        const sql = `UPDATE ${quoteIdentifier(cfg.table)}
                     SET ${sets}
                     WHERE ${quoteIdentifier(cfg.idColumn)} = $${values.length - 1}
                       AND ${quoteIdentifier(cfg.businessColumn)} = $${values.length}
                     RETURNING *`;
        const result = await queryPg(sql, values);
        if (!result.rows[0]) return sendError(res, 'ENTITY_NOT_FOUND', 'Entity not found.', 404);
        return sendSuccess(res, result.rows[0]);
      } catch (err) {
        return sendError(res, 'ENTITY_UPDATE_FAILED', err.message, 500);
      }
    },
  );

  router.delete(
    '/:module/:id',
    ...policy.businessScoped,
    requireScope(['entity:write', 'entity:delete'], { mode: 'any', allowLegacyBypass: true }),
    validate(moduleIdParamSchema, 'params'),
    async (req, res) => {
      if (!isPgReady()) return sendError(res, 'POSTGRES_NOT_READY', 'PostgreSQL not connected', 503);
      const cfg = getModuleConfig(req.params.module);
      if (!cfg) return sendError(res, 'MODULE_NOT_ALLOWED', `Module "${req.params.module}" is not allowed.`, 400);
      try {
        const result = await queryPg(
          `DELETE FROM ${quoteIdentifier(cfg.table)}
           WHERE ${quoteIdentifier(cfg.idColumn)} = $1
             AND ${quoteIdentifier(cfg.businessColumn)} = $2
           RETURNING ${quoteIdentifier(cfg.idColumn)}`,
          [req.params.id, req.authContext.businessId],
        );
        if (!result.rows[0]) return sendError(res, 'ENTITY_NOT_FOUND', 'Entity not found.', 404);
        return sendSuccess(res, { deletedId: req.params.id });
      } catch (err) {
        return sendError(res, 'ENTITY_DELETE_FAILED', err.message, 500);
      }
    },
  );

  router.post(
    '/:module/:id/duplicate',
    ...policy.businessScoped,
    requireScope(['entity:write', 'entity:create'], { mode: 'any', allowLegacyBypass: true }),
    validate(moduleIdParamSchema, 'params'),
    async (req, res) => {
      if (!isPgReady()) return sendError(res, 'POSTGRES_NOT_READY', 'PostgreSQL not connected', 503);
      const cfg = getModuleConfig(req.params.module);
      if (!cfg) return sendError(res, 'MODULE_NOT_ALLOWED', `Module "${req.params.module}" is not allowed.`, 400);
      try {
        const source = await queryPg(
          `SELECT *
           FROM ${quoteIdentifier(cfg.table)}
           WHERE ${quoteIdentifier(cfg.idColumn)} = $1
             AND ${quoteIdentifier(cfg.businessColumn)} = $2
           LIMIT 1`,
          [req.params.id, req.authContext.businessId],
        );
        if (!source.rows[0]) return sendError(res, 'ENTITY_NOT_FOUND', 'Entity not found.', 404);
        const cols = await getAllowedColumns(cfg.table);
        const row = source.rows[0];
        delete row[cfg.idColumn];
        const keys = Object.keys(row).filter((k) => cols.has(k));
        const values = keys.map((k) => row[k]);
        const placeholders = keys.map((_, i) => `$${i + 1}`).join(', ');
        const sql = `INSERT INTO ${quoteIdentifier(cfg.table)} (${keys.map(quoteIdentifier).join(', ')})
                     VALUES (${placeholders})
                     RETURNING *`;
        const result = await queryPg(sql, values);
        return sendSuccess(res, result.rows[0], 'Success', 201);
      } catch (err) {
        return sendError(res, 'ENTITY_DUPLICATE_FAILED', err.message, 500);
      }
    },
  );

  return router;
}

module.exports = { createEntityRouter };
