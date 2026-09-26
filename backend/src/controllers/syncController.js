const Product = require('../models/Product');
const Promotion = require('../models/Promotion');
const asyncHandler = require('../utils/asyncHandler');
const { createSale } = require('../services/saleService');

// Push queued offline sales. Each is idempotent by clientTxnId, so retrying
// a partially-failed push is safe — already-synced items just come back
// marked alreadyExisted instead of erroring.
const pushSales = asyncHandler(async (req, res) => {
  const { sales } = req.body;
  const results = [];

  for (const saleInput of sales) {
    try {
      const { sale, alreadyExisted } = await createSale({
        ...saleInput,
        recordedOffline: true,
        cashierId: req.user._id,
      });
      results.push({ clientTxnId: saleInput.clientTxnId, status: 'ok', alreadyExisted, saleId: sale._id });
    } catch (err) {
      results.push({ clientTxnId: saleInput.clientTxnId, status: 'error', error: err.message });
    }
  }

  res.json({ results });
});

// Pull catalog/inventory/promotion deltas since a given timestamp so the
// Flutter app's local drift cache can stay current for offline use.
const pullDeltas = asyncHandler(async (req, res) => {
  const since = req.query.since ? new Date(req.query.since) : new Date(0);

  const [products, promotions] = await Promise.all([
    Product.find({ updatedAt: { $gte: since } }),
    Promotion.find({ updatedAt: { $gte: since } }),
  ]);

  res.json({ serverTime: new Date().toISOString(), products, promotions });
});

module.exports = { pushSales, pullDeltas };
