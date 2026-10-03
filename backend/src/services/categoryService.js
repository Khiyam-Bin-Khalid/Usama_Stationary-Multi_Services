const Category = require('../models/Category');
const AppError = require('../utils/AppError');
const { DEFAULT_CATEGORIES } = require('../utils/constants');

// Idempotent: inserts the five SRS categories if missing, leaves existing
// rows untouched (an admin may have tuned thresholds/unit types).
async function ensureDefaultCategories() {
  for (const c of DEFAULT_CATEGORIES) {
    // eslint-disable-next-line no-await-in-loop
    await Category.updateOne({ key: c.key }, { $setOnInsert: c }, { upsert: true });
  }
}

async function getCategoryOrThrow(key) {
  const category = await Category.findOne({ key, isActive: true });
  if (!category) throw new AppError(400, `Unknown or inactive category: ${key}`);
  return category;
}

module.exports = { ensureDefaultCategories, getCategoryOrThrow };
