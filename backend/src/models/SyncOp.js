const mongoose = require('mongoose');

// One row per offline product change applied through POST /sync/ops. opId is
// generated on the device, so a push retried after a lost response is answered
// from here instead of being applied twice (duplicate product, double stock
// adjustment). Rows expire after 90 days: far longer than any device queue.
const syncOpSchema = new mongoose.Schema(
  {
    opId: { type: String, required: true, unique: true },
    type: { type: String, required: true },
    product: { type: mongoose.Schema.Types.ObjectId, ref: 'Product' },
    actor: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
    createdAt: { type: Date, default: Date.now, expires: 60 * 60 * 24 * 90 },
  }
);

module.exports = mongoose.model('SyncOp', syncOpSchema);
