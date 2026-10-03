const mongoose = require('mongoose');

// Spec §7 `audit_logs`: every create/update/delete across the system with
// actor, role, timestamp and before/after values. Super Admin only (§3.1).
const auditLogSchema = new mongoose.Schema(
  {
    // Optional so security events with no authenticated actor (e.g. a failed
    // login attempt) can still be recorded.
    actor: { type: mongoose.Schema.Types.ObjectId, ref: 'User', index: true },
    actorRole: { type: String },
    action: { type: String, required: true, index: true }, // e.g. "inventory.adjust", "user.role_change", "auth.login_failed"
    entityType: { type: String, required: true },
    entityId: { type: mongoose.Schema.Types.ObjectId },
    before: { type: mongoose.Schema.Types.Mixed },
    after: { type: mongoose.Schema.Types.Mixed },
    details: { type: mongoose.Schema.Types.Mixed },
  },
  { timestamps: true }
);

auditLogSchema.index({ createdAt: -1 });

module.exports = mongoose.model('AuditLog', auditLogSchema);
