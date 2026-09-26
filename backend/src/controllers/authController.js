const User = require('../models/User');
const AppError = require('../utils/AppError');
const asyncHandler = require('../utils/asyncHandler');
const { signAccessToken, signRefreshToken, verifyRefreshToken } = require('../utils/jwt');
const { ROLES } = require('../utils/constants');
const { logAction } = require('../services/auditService');
const { isSuperadminAllowed } = require('../utils/superadminGuard');

// Defense in depth: even if a second superadmin document ever ends up in the
// database (manual DB edit, restored backup, etc.), only the one designated
// owner account may actually log in as superadmin.
function assertSuperadminAllowed(user) {
  if (user.role === ROLES.SUPERADMIN && !isSuperadminAllowed(user.email)) {
    throw new AppError(403, 'This superadmin account is not authorized to log in');
  }
}

function issueTokens(user) {
  return {
    accessToken: signAccessToken(user),
    refreshToken: signRefreshToken(user),
  };
}

const registerCustomer = asyncHandler(async (req, res) => {
  const { name, email, password, phone } = req.body;

  const existing = await User.findOne({ email });
  if (existing) throw new AppError(409, 'An account with this email already exists');

  const user = new User({ name, email, phone, role: ROLES.CUSTOMER });
  await user.setPassword(password);
  await user.save();

  const tokens = issueTokens(user);
  res.status(201).json({ user: user.toSafeJSON(), ...tokens });
});

const login = asyncHandler(async (req, res) => {
  const { email, password } = req.body;

  const user = await User.findOne({ email });
  if (!user || !user.isActive) throw new AppError(401, 'Invalid email or password');

  const valid = await user.comparePassword(password);
  if (!valid) throw new AppError(401, 'Invalid email or password');

  assertSuperadminAllowed(user);

  const tokens = issueTokens(user);
  res.json({ user: user.toSafeJSON(), ...tokens });
});

const refresh = asyncHandler(async (req, res) => {
  const { refreshToken } = req.body;

  let payload;
  try {
    payload = verifyRefreshToken(refreshToken);
  } catch {
    throw new AppError(401, 'Invalid or expired refresh token');
  }

  const user = await User.findById(payload.sub);
  if (!user || !user.isActive) throw new AppError(401, 'Account not found or deactivated');

  assertSuperadminAllowed(user);

  const tokens = issueTokens(user);
  res.json({ user: user.toSafeJSON(), ...tokens });
});

const me = asyncHandler(async (req, res) => {
  res.json({ user: req.user.toSafeJSON() });
});

// Superadmin creates admin/staff; Admin can only create staff.
const createStaffAccount = asyncHandler(async (req, res) => {
  const { name, email, password, role, phone, branch } = req.body;

  if (req.user.role === ROLES.ADMIN && role !== ROLES.STAFF) {
    throw new AppError(403, 'Admins may only create staff accounts');
  }

  const existing = await User.findOne({ email });
  if (existing) throw new AppError(409, 'An account with this email already exists');

  const user = new User({ name, email, phone, branch, role, createdBy: req.user._id });
  await user.setPassword(password);
  await user.save();

  await logAction({
    actor: req.user._id,
    action: 'user.create',
    entityType: 'User',
    entityId: user._id,
    details: { role: user.role, email: user.email },
  });

  res.status(201).json({ user: user.toSafeJSON() });
});

module.exports = { registerCustomer, login, refresh, me, createStaffAccount };
