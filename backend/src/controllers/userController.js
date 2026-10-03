const User = require('../models/User');
const AppError = require('../utils/AppError');
const asyncHandler = require('../utils/asyncHandler');
const { ROLES } = require('../utils/constants');
const { logAction } = require('../services/auditService');

// Spec §2: account management (list/edit/delete/role) is Super Admin only —
// routes are guarded with requireRole(SUPERADMIN). Customers are listed
// separately (?role=customer) so the owner can see registrations.
const listUsers = asyncHandler(async (req, res) => {
  const { role, isActive, q } = req.query;
  const filter = { deletedAt: null };
  filter.role = role || { $in: [ROLES.SUPERADMIN, ROLES.ADMIN, ROLES.STAFF] };
  if (isActive !== undefined) filter.isActive = isActive;
  if (q) filter.$or = [{ name: new RegExp(q, 'i') }, { email: new RegExp(q, 'i') }];

  const users = await User.find(filter).sort({ createdAt: -1 });
  res.json({ users: users.map((u) => u.toSafeJSON()) });
});

const getUser = asyncHandler(async (req, res) => {
  const user = await User.findOne({ _id: req.params.id, deletedAt: null });
  if (!user) throw new AppError(404, 'User not found');
  res.json({ user: user.toSafeJSON() });
});

function assertNotOwnerAccount(target) {
  if (target.role === ROLES.SUPERADMIN) {
    throw new AppError(403, 'The Super Admin account cannot be modified through the API');
  }
}

const updateUser = asyncHandler(async (req, res) => {
  const target = await User.findOne({ _id: req.params.id, deletedAt: null });
  if (!target) throw new AppError(404, 'User not found');
  assertNotOwnerAccount(target);

  const before = { name: target.name, phone: target.phone, branch: target.branch, isActive: target.isActive };
  Object.assign(target, req.body);
  await target.save();

  await logAction({ actorUser: req.user, action: 'user.update', entityType: 'User', entityId: target._id, before, after: req.body });
  res.json({ user: target.toSafeJSON() });
});

// Spec §8 PATCH /users/:id/role
const changeRole = asyncHandler(async (req, res) => {
  const target = await User.findOne({ _id: req.params.id, deletedAt: null });
  if (!target) throw new AppError(404, 'User not found');
  assertNotOwnerAccount(target);
  if (target.role === ROLES.CUSTOMER) throw new AppError(400, 'Customer accounts cannot be given staff roles');

  const before = { role: target.role };
  target.role = req.body.role;
  await target.save();

  await logAction({ actorUser: req.user, action: 'user.role_change', entityType: 'User', entityId: target._id, before, after: { role: target.role } });
  res.json({ user: target.toSafeJSON() });
});

// Spec §8 DELETE /users/:id — soft delete so sales/audit history that
// references the account stays intact.
const deleteUser = asyncHandler(async (req, res) => {
  const target = await User.findOne({ _id: req.params.id, deletedAt: null });
  if (!target) throw new AppError(404, 'User not found');
  assertNotOwnerAccount(target);
  if (target._id.equals(req.user._id)) throw new AppError(400, 'You cannot delete your own account');

  target.isActive = false;
  target.deletedAt = new Date();
  await target.save();

  await logAction({
    actorUser: req.user,
    action: 'user.delete',
    entityType: 'User',
    entityId: target._id,
    before: { role: target.role, email: target.email, isActive: true },
    after: { isActive: false, deletedAt: target.deletedAt },
  });
  res.json({ ok: true });
});

module.exports = { listUsers, getUser, updateUser, changeRole, deleteUser };
