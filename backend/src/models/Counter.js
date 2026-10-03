const mongoose = require('mongoose');

// Atomic per-key sequence used for auto-generated SKUs (STN-00001, ...).
// findOneAndUpdate with $inc + upsert is atomic on a single document, so two
// admins adding products at the same time can never receive the same number.
const counterSchema = new mongoose.Schema(
  {
    key: { type: String, required: true, unique: true },
    seq: { type: Number, required: true, default: 0 },
  },
  { timestamps: true }
);

counterSchema.statics.next = async function next(key) {
  const doc = await this.findOneAndUpdate({ key }, { $inc: { seq: 1 } }, { new: true, upsert: true });
  return doc.seq;
};

module.exports = mongoose.model('Counter', counterSchema);
