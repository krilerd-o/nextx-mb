const { z } = require('zod');
const { sendError } = require('../utils/http');

const moduleParamSchema = z.object({
  module: z.string().regex(/^[a-z0-9_]+$/i),
});

const idParamSchema = z.object({
  id: z.coerce.number().int().positive(),
});

const moduleIdParamSchema = moduleParamSchema.merge(idParamSchema);

const paginationQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(20),
  offset: z.coerce.number().int().min(0).default(0),
});

const entityWriteBodySchema = z.object({
  payload: z.record(z.any()).optional(),
}).passthrough();

const authLoginBodySchema = z.object({
  code: z.string().min(8),
  codeVerifier: z.string().min(8),
  redirectUri: z.string().url().optional(),
});

function validate(schema, target = 'body') {
  return (req, res, next) => {
    const parsed = schema.safeParse(req[target] || {});
    if (!parsed.success) {
      return sendError(
        res,
        'VALIDATION_FAILED',
        parsed.error.issues.map((x) => `${x.path.join('.') || target}: ${x.message}`).join('; '),
        400,
      );
    }
    req[target] = parsed.data;
    return next();
  };
}

module.exports = {
  validate,
  moduleParamSchema,
  idParamSchema,
  moduleIdParamSchema,
  paginationQuerySchema,
  entityWriteBodySchema,
  authLoginBodySchema,
};
