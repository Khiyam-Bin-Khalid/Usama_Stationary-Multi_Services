const express = require('express');
const validate = require('../middleware/validate');
const { authenticate, requireRole } = require('../middleware/auth');
const { openShiftSchema, closeShiftSchema } = require('../validators/miscValidators');
const shiftController = require('../controllers/shiftController');
const { ROLES } = require('../utils/constants');

const router = express.Router();
router.use(authenticate, requireRole(ROLES.SUPERADMIN, ROLES.ADMIN, ROLES.STAFF));

router.post('/open', validate(openShiftSchema), shiftController.open);
router.post('/close', validate(closeShiftSchema), shiftController.close);
router.get('/current', shiftController.current);
router.get('/', shiftController.list);
router.get('/:id', shiftController.report);

module.exports = router;
