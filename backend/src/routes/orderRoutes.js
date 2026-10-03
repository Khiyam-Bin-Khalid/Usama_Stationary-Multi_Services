const express = require('express');
const validate = require('../middleware/validate');
const { authenticate, requireRole } = require('../middleware/auth');
const {
  createOrderSchema,
  quoteOrderSchema,
  updateOrderStatusSchema,
  listOrdersQuerySchema,
} = require('../validators/orderValidators');
const orderController = require('../controllers/orderController');
const { ROLES } = require('../utils/constants');

const router = express.Router();
router.use(authenticate);

// Customer routes
router.post('/quote', requireRole(ROLES.CUSTOMER), validate(quoteOrderSchema), orderController.quote);
router.post('/', requireRole(ROLES.CUSTOMER), validate(createOrderSchema), orderController.placeOrder);
router.get('/mine', requireRole(ROLES.CUSTOMER), orderController.myOrders);
router.get('/mine/:id', requireRole(ROLES.CUSTOMER), orderController.getMyOrder);

// Admin/staff routes
const staffUp = requireRole(ROLES.SUPERADMIN, ROLES.ADMIN, ROLES.STAFF);
router.get('/', staffUp, validate(listOrdersQuerySchema, 'query'), orderController.listOrders);
router.get('/status-counts', staffUp, orderController.statusCounts);
router.get('/:id', staffUp, orderController.getOrder);
router.patch(
  '/:id/status',
  requireRole(ROLES.SUPERADMIN, ROLES.ADMIN),
  validate(updateOrderStatusSchema),
  orderController.changeOrderStatus
);

module.exports = router;
