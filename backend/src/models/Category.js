const mongoose = require('mongoose');

// Spec §4 / §7 `categories`: each product line carries its own unit type and
// default low-stock threshold. `key` is the stable slug stored on products,
// sales and orders (e.g. "stationery"); `name` is the display label.
const categorySchema = new mongoose.Schema(
  {
    key: { type: String, required: true, unique: true, lowercase: true, trim: true, match: /^[a-z][a-z0-9_]*$/ },
    name: { type: String, required: true, trim: true },
    unitType: { type: String, required: true, default: 'piece' }, // piece, ream, kg, meter, job-order
    defaultReorderThreshold: { type: Number, required: true, min: 0, default: 5 },
    isActive: { type: Boolean, default: true },
  },
  { timestamps: true }
);

module.exports = mongoose.model('Category', categorySchema);
