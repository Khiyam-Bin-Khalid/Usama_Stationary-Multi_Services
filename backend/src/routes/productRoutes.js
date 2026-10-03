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
const { productImageUpload } = require('../utils/uploadConfig');
const { ROLES } = require('../utils/constants');

const router = express.Router();
const staffUp = requireRole(ROLES.SUPERADMIN, ROLES.ADMIN, ROLES.STAFF);
const adminUp = requireRole(ROLES.SUPERADMIN, ROLES.ADMIN);

// Attaches req.user when a valid token is present, without rejecting
// anonymous callers — the storefront browses the catalog before login.
const optionalAuth = (req, res, next) => {
  if (!req.headers.authorization) return next();
  return authenticate(req, res, next);
};

// Public catalog browsing (customers, storefront). Anonymous callers get
// active + in-stock products only; staff roles can pass isActive/sellableOnly.
router.get('/', optionalAuth, validate(listProductsQuerySchema, 'query'), productController.listProducts);
router.get('/:id', optionalAuth, productController.getProduct);

router.use(authenticate);

// Spec §2: add/edit/delete products and edit stock — Admin + Super Admin.
// Staff have read-only inventory access (and report discrepancies instead).
router.post('/', adminUp, validate(createProductSchema), productController.createProduct);
router.patch('/:id', adminUp, validate(updateProductSchema), productController.updateProduct);
router.delete('/:id', adminUp, productController.deleteProduct);
router.post('/:id/adjust-stock', adminUp, validate(adjustStockSchema), productController.adjustStock);
router.post('/:id/image', adminUp, productImageUpload.single('image'), productController.uploadProductImage);
router.get('/:id/inventory-log', staffUp, productController.getProductInventoryLog);

module.exports = router;
