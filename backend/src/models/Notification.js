const mongoose = require('mongoose');
const { NOTIFICATION_TYPES, ROLES } = require('../utils/constants');

// Spec §7 `notifications`: one document per alert, addressed to roles (not
// individual users) so a newly created admin sees the store's open alerts
// too. Read state is tracked per user in `readBy`.
const notificationSchema = new mongoose.Schema(
  {
    type: { type: String, enum: Object.values(NOTIFICATION_TYPES), required: true, index: true },
    title: { type: String, required: true },
    message: { type: String, required: true },
    recipientRoles: { type: [String], enum: Object.values(ROLES), default: [], index: true },
    // Set for notifications addressed to one person (e.g. a customer whose
    // receipt was rejected). Role-addressed alerts leave this empty.
    recipientUser: { type: mongoose.Schema.Types.ObjectId, ref: 'User', index: true },
    channels: { type: [String], enum: ['in_app', 'email'], default: ['in_app'] },
    payload: { type: mongoose.Schema.Types.Mixed },
    readBy: [{ type: mongoose.Schema.Types.ObjectId, ref: 'User' }],
  },
  { timestamps: true }
);

notificationSchema.index({ createdAt: -1 });

module.exports = mongoose.model('Notification', notificationSchema);
