const express = require('express');
const rateLimit = require('express-rate-limit');
const validate = require('../middleware/validate');
const { authenticate, requireRole } = require('../middleware/auth');
const {
  registerCustomerSchema,
  loginSchema,
  refreshSchema,
  createStaffSchema,
} = require('../validators/authValidators');
const authController = require('../controllers/authController');
const { ROLES } = require('../utils/constants');

const router = express.Router();

// Tighter limit than the global /api limiter, specifically on the
// credential-guessing surface (login + customer self-registration).
const bruteForceGuard = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 20,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many attempts. Please try again later.' },
});

router.post('/register-customer', bruteForceGuard, validate(registerCustomerSchema), authController.registerCustomer);
router.post('/login', bruteForceGuard, validate(loginSchema), authController.login);
router.post('/refresh', validate(refreshSchema), authController.refresh);
router.get('/me', authenticate, authController.me);
router.post(
  '/staff',
  authenticate,
  requireRole(ROLES.SUPERADMIN, ROLES.ADMIN),
  validate(createStaffSchema),
  authController.createStaffAccount
);

module.exports = router;
