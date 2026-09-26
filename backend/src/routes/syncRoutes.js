const express = require('express');
const validate = require('../middleware/validate');
const { authenticate, requireRole } = require('../middleware/auth');
const { syncPushSchema } = require('../validators/saleValidators');
const syncController = require('../controllers/syncController');
const { ROLES } = require('../utils/constants');

const router = express.Router();
router.use(authenticate, requireRole(ROLES.SUPERADMIN, ROLES.ADMIN, ROLES.STAFF));

router.post('/push', validate(syncPushSchema), syncController.pushSales);
router.get('/pull', syncController.pullDeltas);

module.exports = router;
