const express = require('express');
const validate = require('../middleware/validate');
const { authenticate, requireRole } = require('../middleware/auth');
const { inventoryMovementsQuerySchema } = require('../validators/reportValidators');
const inventoryController = require('../controllers/inventoryController');
const { ROLES } = require('../utils/constants');

const router = express.Router();
router.use(authenticate, requireRole(ROLES.SUPERADMIN, ROLES.ADMIN, ROLES.STAFF));

router.get('/movements', validate(inventoryMovementsQuerySchema, 'query'), inventoryController.movements);
router.get('/low-stock', inventoryController.lowStock);

module.exports = router;
