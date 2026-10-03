const User = require('../models/User');
const AppError = require('../utils/AppError');
const asyncHandler = require('../utils/asyncHandler');
const { signAccessToken, signRefreshToken, verifyRefreshToken } = require('../utils/jwt');
const { ROLES } = require('../utils/constants');
const { logAction } = require('../services/auditService');
const { isSuperadminAllowed } = require('../utils/superadminGuard');
const { domainEvents, EVENTS } = require('../services/events');

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

  // Spec §3.4: new registration notifies Admin / Super Admin.
  domainEvents.emitSafe(EVENTS.CUSTOMER_REGISTERED, { userId: user._id, name: user.name, email: user.email });

  const tokens = issueTokens(user);
  res.status(201).json({ user: user.toSafeJSON(), ...tokens });
});

async function logFailedLogin(email, reason, selectedRole) {
  await logAction({
    action: 'auth.login_failed',
    entityType: 'User',
    details: { email, reason, selectedRole },
  });
}

const login = asyncHandler(async (req, res) => {
  const { email, password, role: selectedRole } = req.body;

  const user = await User.findOne({ email, deletedAt: null });
  if (!user || !user.isActive) {
    await logFailedLogin(email, 'unknown_or_inactive', selectedRole);
    throw new AppError(401, 'Invalid email or password');
  }

  const valid = await user.comparePassword(password);
  if (!valid) {
    await logFailedLogin(email, 'bad_password', selectedRole);
    throw new AppError(401, 'Invalid email or password');
  }

  // Spec §1: the role picked on the login screen is a UX hint only. The
  // account's real role wins, and a mismatch is rejected + audit-logged
  // (e.g. a Staff account trying to enter via the "Admin" tile).
  if (selectedRole && selectedRole !== user.role) {
    await logFailedLogin(email, `role_mismatch:${user.role}`, selectedRole);
    throw new AppError(403, `This account is registered as ${user.role}, not ${selectedRole}. Select the correct role to sign in.`);
  }

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

  const user = await User.findOne({ _id: payload.sub, deletedAt: null });
  if (!user || !user.isActive) throw new AppError(401, 'Account not found or deactivated');

  assertSuperadminAllowed(user);

  const tokens = issueTokens(user);
  res.json({ user: user.toSafeJSON(), ...tokens });
});

const me = asyncHandler(async (req, res) => {
  res.json({ user: req.user.toSafeJSON() });
});

// Spec §2: only Super Admin registers Admin and Staff accounts (the route
// is guarded with requireRole(SUPERADMIN); this is defence in depth).
const createStaffAccount = asyncHandler(async (req, res) => {
  const { name, email, password, role, phone, branch } = req.body;

  if (req.user.role !== ROLES.SUPERADMIN) {
    throw new AppError(403, 'Only the Super Admin may create staff or admin accounts');
  }

  const existing = await User.findOne({ email });
  if (existing) throw new AppError(409, 'An account with this email already exists');

  const user = new User({ name, email, phone, branch, role, createdBy: req.user._id });
  await user.setPassword(password);
  await user.save();

  await logAction({
    actorUser: req.user,
    action: 'user.create',
    entityType: 'User',
    entityId: user._id,
    after: { role: user.role, email: user.email, name: user.name },
  });

  res.status(201).json({ user: user.toSafeJSON() });
});

module.exports = { registerCustomer, login, refresh, me, createStaffAccount };
