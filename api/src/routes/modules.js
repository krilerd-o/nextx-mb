const express = require('express');
const { sendSuccess } = require('../utils/http');
const { listModules } = require('../domain/moduleRegistry');

function createModulesRouter(policy, requireScope) {
  const router = express.Router();

  router.get(
    '/',
    ...policy.businessScoped,
    requireScope(['modules:read'], { mode: 'any', allowLegacyBypass: true }),
    (req, res) => sendSuccess(res, listModules()),
  );

  return router;
}

module.exports = { createModulesRouter };
