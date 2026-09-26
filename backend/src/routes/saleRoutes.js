const express = require('express');
const validate = require('../middleware/validate');
const { authenticate, requireRole } = require('../middleware/auth');
const { createSaleSchema, listSalesQuerySchema } = require('../validators/saleValidators');
const saleController = require('../controllers/saleController');
const { ROLES } = require('../utils/constants');

const router = express.Router();
router.use(authenticate, requireRole(ROLES.SUPERADMIN, ROLES.ADMIN, ROLES.STAFF));

router.post('/', validate(createSaleSchema), saleController.recordSale);
router.get('/', validate(listSalesQuerySchema, 'query'), saleController.listSales);
router.get('/:id', saleController.getSale);

module.exports = router;
