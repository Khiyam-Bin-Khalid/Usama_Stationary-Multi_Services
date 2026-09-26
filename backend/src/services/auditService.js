const AuditLog = require('../models/AuditLog');

async function logAction({ actor, action, entityType, entityId, details }) {
  await AuditLog.create({ actor, action, entityType, entityId, details });
}

module.exports = { logAction };
