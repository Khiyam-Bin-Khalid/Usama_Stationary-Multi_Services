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
const env = require('../config/env');

const router = express.Router();

// Tighter limit than the global /api limiter, specifically on the
// credential-guessing surface (login + customer self-registration).
const bruteForceGuard = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 20,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many attempts. Please try again later.' },
  // Test suites log in dozens of times per process; the limiter is a
  // production safeguard, not something to exercise in unit tests.
  skip: () => env.nodeEnv === 'test',
});

router.post('/register-customer', bruteForceGuard, validate(registerCustomerSchema), authController.registerCustomer);
router.post('/login', bruteForceGuard, validate(loginSchema), authController.login);
router.post('/refresh', validate(refreshSchema), authController.refresh);
router.get('/me', authenticate, authController.me);
// Spec §8: POST /auth/register-staff and /auth/register-admin are Super
// Admin only. Both map to the same handler with `role` in the body; the
// legacy `/staff` path is kept for the existing client.
const superadminOnly = [authenticate, requireRole(ROLES.SUPERADMIN), validate(createStaffSchema)];
router.post('/staff', ...superadminOnly, authController.createStaffAccount);
router.post('/register-staff', ...superadminOnly, authController.createStaffAccount);
router.post('/register-admin', ...superadminOnly, authController.createStaffAccount);

module.exports = router;
