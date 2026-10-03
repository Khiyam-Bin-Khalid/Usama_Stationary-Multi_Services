const express = require('express');
const validate = require('../middleware/validate');
const { authenticate, requireRole } = require('../middleware/auth');
const { createCategorySchema, updateCategorySchema } = require('../validators/miscValidators');
const categoryController = require('../controllers/categoryController');
const { ROLES } = require('../utils/constants');

const router = express.Router();

// Spec §8: GET /categories (superadmin, admin, staff). Customers' storefront
// also needs the labels, so the list is open to any authenticated user.
router.get('/', authenticate, categoryController.listCategories);

const adminUp = requireRole(ROLES.SUPERADMIN, ROLES.ADMIN);
router.post('/', authenticate, adminUp, validate(createCategorySchema), categoryController.createCategory);
router.patch('/:key', authenticate, adminUp, validate(updateCategorySchema), categoryController.updateCategory);

module.exports = router;
