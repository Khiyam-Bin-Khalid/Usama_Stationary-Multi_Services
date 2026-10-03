const express = require('express');
const validate = require('../middleware/validate');
const { authenticate, requireRole } = require('../middleware/auth');
const {
  reportDiscrepancySchema,
  resolveDiscrepancySchema,
  listDiscrepanciesQuerySchema,
} = require('../validators/miscValidators');
const discrepancyController = require('../controllers/discrepancyController');
const { ROLES } = require('../utils/constants');

const router = express.Router();
router.use(authenticate, requireRole(ROLES.SUPERADMIN, ROLES.ADMIN, ROLES.STAFF));

router.post('/', validate(reportDiscrepancySchema), discrepancyController.create);
router.get('/', validate(listDiscrepanciesQuerySchema, 'query'), discrepancyController.list);
router.patch(
  '/:id/resolve',
  requireRole(ROLES.SUPERADMIN, ROLES.ADMIN),
  validate(resolveDiscrepancySchema),
  discrepancyController.resolve
);

module.exports = router;
