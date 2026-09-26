const express = require('express');
const validate = require('../middleware/validate');
const { authenticate, requireRole } = require('../middleware/auth');
const { salesReportQuerySchema, categoryReportQuerySchema } = require('../validators/reportValidators');
const reportController = require('../controllers/reportController');
const { ROLES } = require('../utils/constants');

const router = express.Router();
router.use(authenticate, requireRole(ROLES.SUPERADMIN, ROLES.ADMIN, ROLES.STAFF));

router.get('/sales', validate(salesReportQuerySchema, 'query'), reportController.salesReport);
router.get(
  '/categories',
  requireRole(ROLES.SUPERADMIN, ROLES.ADMIN),
  validate(categoryReportQuerySchema, 'query'),
  reportController.categoryReport
);

module.exports = router;
