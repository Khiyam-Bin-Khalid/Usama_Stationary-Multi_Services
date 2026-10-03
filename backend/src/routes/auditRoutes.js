const express = require('express');
const validate = require('../middleware/validate');
const { authenticate, requireRole } = require('../middleware/auth');
const { listAuditQuerySchema } = require('../validators/miscValidators');
const asyncHandler = require('../utils/asyncHandler');
const { listAuditLogs } = require('../services/auditService');
const { ROLES } = require('../utils/constants');

const router = express.Router();
// Spec §2 / §8: audit log is Super Admin only.
router.use(authenticate, requireRole(ROLES.SUPERADMIN));

router.get(
  '/',
  validate(listAuditQuerySchema, 'query'),
  asyncHandler(async (req, res) => res.json(await listAuditLogs(req.query)))
);

module.exports = router;
