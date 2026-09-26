const express = require('express');
const validate = require('../middleware/validate');
const { authenticate, requireRole } = require('../middleware/auth');
const {
  createProductSchema,
  updateProductSchema,
  adjustStockSchema,
  listProductsQuerySchema,
} = require('../validators/productValidators');
const productController = require('../controllers/productController');
const { ROLES } = require('../utils/constants');

const router = express.Router();
const staffUp = requireRole(ROLES.SUPERADMIN, ROLES.ADMIN, ROLES.STAFF);
const adminUp = requireRole(ROLES.SUPERADMIN, ROLES.ADMIN);

// Public catalog browsing (customers, storefront) — only active+online products are returned
// because listProducts always filters isActive by default.
router.get('/', validate(listProductsQuerySchema, 'query'), productController.listProducts);
router.get('/:id', productController.getProduct);

router.use(authenticate);

router.post('/', staffUp, validate(createProductSchema), productController.createProduct);
router.patch('/:id', adminUp, validate(updateProductSchema), productController.updateProduct);
router.post('/:id/adjust-stock', staffUp, validate(adjustStockSchema), productController.adjustStock);
router.get('/:id/inventory-log', staffUp, productController.getProductInventoryLog);

module.exports = router;
