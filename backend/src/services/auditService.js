const AuditLog = require('../models/AuditLog');

/**
 * Records one audit entry. Pass `actorUser` (a User doc / req.user) to fill
 * actor + actorRole in one go, or `actor`/`actorRole` explicitly. `before`
 * and `after` should be plain snapshots of the changed fields.
 */
async function logAction({ actor, actorUser, actorRole, action, entityType, entityId, before, after, details }) {
  await AuditLog.create({
    actor: actorUser ? actorUser._id : actor,
    actorRole: actorUser ? actorUser.role : actorRole,
    action,
    entityType,
    entityId,
    before,
    after,
    details,
  });
}

async function listAuditLogs({ action, actor, entityType, from, to, page = 1, limit = 50 }) {
  const filter = {};
  if (action) filter.action = new RegExp(`^${action.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}`, 'i');
  if (actor) filter.actor = actor;
  if (entityType) filter.entityType = entityType;
  if (from || to) {
    filter.createdAt = {};
    if (from) filter.createdAt.$gte = new Date(from);
    if (to) filter.createdAt.$lte = new Date(to);
  }
  const total = await AuditLog.countDocuments(filter);
  const logs = await AuditLog.find(filter)
    .sort({ createdAt: -1 })
    .skip((page - 1) * limit)
    .limit(limit)
    .populate('actor', 'name email role');
  return { logs, total, page, limit };
}

module.exports = { logAction, listAuditLogs };
