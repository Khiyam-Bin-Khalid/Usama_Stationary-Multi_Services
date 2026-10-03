const express = require('express');
const validate = require('../middleware/validate');
const { authenticate, requireRole } = require('../middleware/auth');
const { reviewPaymentSchema } = require('../validators/paymentValidators');
const { receiptUpload } = require('../utils/uploadConfig');
const paymentController = require('../controllers/paymentController');
const { ROLES } = require('../utils/constants');

const router = express.Router();

// Public — Stripe calls this directly; body is raw (mounted in app.js).
router.post('/stripe/webhook', paymentController.stripeWebhook);

router.use(authenticate);

router.post(
  '/orders/:orderId/receipt',
  requireRole(ROLES.CUSTOMER),
  receiptUpload.single('receipt'),
  paymentController.uploadReceipt
);

router.get('/pending-review', requireRole(ROLES.SUPERADMIN, ROLES.ADMIN), paymentController.listPendingReview);
router.get('/orders/:orderId', requireRole(ROLES.SUPERADMIN, ROLES.ADMIN, ROLES.STAFF), paymentController.getOrderPayment);
router.post(
  '/:id/review',
  requireRole(ROLES.SUPERADMIN, ROLES.ADMIN),
  validate(reviewPaymentSchema),
  paymentController.reviewPayment
);

module.exports = router;
