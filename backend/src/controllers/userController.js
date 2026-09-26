const User = require('../models/User');
const AppError = require('../utils/AppError');
const asyncHandler = require('../utils/asyncHandler');
const { ROLES } = require('../utils/constants');
const { logAction } = require('../services/auditService');

// Superadmin sees admin+staff+customer; Admin sees only staff.
const listUsers = asyncHandler(async (req, res) => {
  const { role, isActive, q } = req.query;
  const filter = {};

  if (req.user.role === ROLES.ADMIN) {
    filter.role = ROLES.STAFF;
  } else if (role) {
    filter.role = role;
  } else {
    filter.role = { $in: [ROLES.SUPERADMIN, ROLES.ADMIN, ROLES.STAFF] };
  }

  if (isActive !== undefined) filter.isActive = isActive;
  if (q) filter.$or = [{ name: new RegExp(q, 'i') }, { email: new RegExp(q, 'i') }];

  const users = await User.find(filter).sort({ createdAt: -1 });
  res.json({ users: users.map((u) => u.toSafeJSON()) });
});

const getUser = asyncHandler(async (req, res) => {
  const user = await User.findById(req.params.id);
  if (!user) throw new AppError(404, 'User not found');
  res.json({ user: user.toSafeJSON() });
});

const updateUser = asyncHandler(async (req, res) => {
  const target = await User.findById(req.params.id);
  if (!target) throw new AppError(404, 'User not found');

  if (req.user.role === ROLES.ADMIN && target.role !== ROLES.STAFF) {
    throw new AppError(403, 'Admins may only manage staff accounts');
  }
  if (target.role === ROLES.SUPERADMIN && req.user.role !== ROLES.SUPERADMIN) {
    throw new AppError(403, 'Only a superadmin may modify a superadmin account');
  }

  const { role, ...rest } = req.body;
  if (role && req.user.role !== ROLES.SUPERADMIN) {
    throw new AppError(403, 'Only a superadmin may change roles');
  }

  Object.assign(target, rest);
  if (role) target.role = role;
  await target.save();

  await logAction({
    actor: req.user._id,
    action: 'user.update',
    entityType: 'User',
    entityId: target._id,
    details: req.body,
  });

  res.json({ user: target.toSafeJSON() });
});

module.exports = { listUsers, getUser, updateUser };
