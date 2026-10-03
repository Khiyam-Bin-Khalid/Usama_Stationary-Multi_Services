const User = require('../models/User');
const { verifyAccessToken } = require('../utils/jwt');
const AppError = require('../utils/AppError');
const asyncHandler = require('../utils/asyncHandler');
const { ROLES } = require('../utils/constants');
const { isSuperadminAllowed } = require('../utils/superadminGuard');

const authenticate = asyncHandler(async (req, res, next) => {
  const header = req.headers.authorization || '';
  const [scheme, token] = header.split(' ');

  if (scheme !== 'Bearer' || !token) {
    throw new AppError(401, 'Authentication required');
  }

  let payload;
  try {
    payload = verifyAccessToken(token);
  } catch {
    throw new AppError(401, 'Invalid or expired token');
  }

  const user = await User.findOne({ _id: payload.sub, deletedAt: null });
  if (!user || !user.isActive) {
    throw new AppError(401, 'Account not found or deactivated');
  }

  // Only the one designated owner account may act as superadmin, even with
  // an otherwise-valid token (see authController's login/refresh guard).
  if (user.role === ROLES.SUPERADMIN && !isSuperadminAllowed(user.email)) {
    throw new AppError(403, 'This superadmin account is not authorized');
  }

  req.user = user;
  next();
});

function requireRole(...roles) {
  return (req, res, next) => {
    if (!req.user || !roles.includes(req.user.role)) {
      return next(new AppError(403, 'You do not have permission to perform this action'));
    }
    next();
  };
}

module.exports = { authenticate, requireRole };
