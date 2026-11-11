const express = require('express');
const validate = require('../middleware/validate');
const { authenticate, requireRole } = require('../middleware/auth');
const { syncPushSchema, syncOpSchema } = require('../validators/saleValidators');
const syncController = require('../controllers/syncController');
const { ROLES } = require('../utils/constants');

const router = express.Router();
router.use(authenticate, requireRole(ROLES.SUPERADMIN, ROLES.ADMIN, ROLES.STAFF));

router.post('/push', validate(syncPushSchema), syncController.pushSales);
router.get('/pull', syncController.pullDeltas);
// Offline product changes follow the same rule as the REST routes: staff have
// read-only inventory access (spec §2), so this is Admin + Super Admin only.
router.post('/ops', requireRole(ROLES.SUPERADMIN, ROLES.ADMIN), validate(syncOpSchema), syncController.applyOp);

module.exports = router;
