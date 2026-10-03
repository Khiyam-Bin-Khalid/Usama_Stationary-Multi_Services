const Counter = require('../models/Counter');
const Product = require('../models/Product');
const { SKU_PREFIXES } = require('../utils/constants');

// Product ID (Mongo _id), SKU (system business identifier) and Barcode
// (physical scan code) are three separate things. This service only owns
// the SKU: a per-category prefix + zero-padded sequence, e.g. STN-00001.
function skuPrefixFor(categoryKey) {
  if (SKU_PREFIXES[categoryKey]) return SKU_PREFIXES[categoryKey];
  const letters = String(categoryKey || 'gen').replace(/[^a-z]/gi, '').toUpperCase();
  return (letters.slice(0, 3) || 'GEN').padEnd(3, 'X');
}

function formatSku(prefix, seq) {
  return `${prefix}-${String(seq).padStart(5, '0')}`;
}

// Generates the next unused SKU for the category. The counter is atomic, but
// an admin may have typed a matching SKU by hand earlier (or seed data may
// use the same prefix), so the loop skips any number already taken.
async function generateSku(categoryKey) {
  const prefix = skuPrefixFor(categoryKey);
  for (let attempt = 0; attempt < 50; attempt += 1) {
    // eslint-disable-next-line no-await-in-loop
    const seq = await Counter.next(`sku:${prefix}`);
    const sku = formatSku(prefix, seq);
    // eslint-disable-next-line no-await-in-loop
    const taken = await Product.exists({ sku });
    if (!taken) return sku;
  }
  throw new Error(`Could not allocate a free SKU for prefix ${prefix}`);
}

module.exports = { generateSku, skuPrefixFor, formatSku };
