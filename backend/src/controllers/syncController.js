const Product = require('../models/Product');
const Promotion = require('../models/Promotion');
const Sale = require('../models/Sale');
const SyncOp = require('../models/SyncOp');
const User = require('../models/User');
const AppError = require('../utils/AppError');
const asyncHandler = require('../utils/asyncHandler');
const { createSale } = require('../services/saleService');
const productService = require('../services/productService');
const { domainEvents, EVENTS } = require('../services/events');
const { ROLES } = require('../utils/constants');
const {
  createProductSchema,
  updateProductSchema,
  adjustStockSchema,
} = require('../validators/productValidators');

const STAFF_ROLES = [ROLES.SUPERADMIN, ROLES.ADMIN, ROLES.STAFF];

// Whoever syncs next may not be who rang the sale up (a shared counter device).
// Admins may push on behalf of any staff account; staff only for themselves.
async function resolveCashier(pusher, claimedId) {
  if (!claimedId || claimedId === pusher._id.toString()) return pusher;
  if (pusher.role === ROLES.STAFF) throw new AppError(403, 'Staff may only sync their own sales');
  const cashier = await User.findOne({ _id: claimedId, role: { $in: STAFF_ROLES } });
  if (!cashier) throw new AppError(404, `Cashier not found: ${claimedId}`);
  return cashier;
}

// Push queued offline sales. Each is idempotent by clientTxnId, so retrying
// a partially-failed push is safe — already-synced items just come back
// marked alreadyExisted instead of erroring.
const pushSales = asyncHandler(async (req, res) => {
  const { sales } = req.body;
  const results = [];

  for (const saleInput of sales) {
    try {
      const { cashierId, ...input } = saleInput;
      const cashier = await resolveCashier(req.user, cashierId); // eslint-disable-line no-await-in-loop
      const { sale, alreadyExisted } = await createSale({ // eslint-disable-line no-await-in-loop
        ...input,
        recordedOffline: true,
        cashierId: cashier._id,
        cashierRole: cashier.role,
      });
      // Echoed back so the device can swap its PENDING placeholder for the real invoice.
      const confirmed = await Sale.findById(sale._id).populate('cashier', 'name email'); // eslint-disable-line no-await-in-loop
      results.push({ clientTxnId: saleInput.clientTxnId, status: 'ok', alreadyExisted, saleId: sale._id, sale: confirmed });
    } catch (err) {
      results.push({ clientTxnId: saleInput.clientTxnId, status: 'error', error: err.message });
    }
  }

  // Spec §5: a queued sale the server rejects is a sync failure the
  // owner/admin must know about — the terminal can't fix it on its own.
  const failed = results.filter((r) => r.status === 'error');
  if (failed.length) {
    domainEvents.emitSafe(EVENTS.SYNC_FAILED, {
      cashierId: req.user._id,
      cashierName: req.user.name,
      failedCount: failed.length,
      firstError: failed[0].error,
      clientTxnIds: failed.map((f) => f.clientTxnId),
    });
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

function validated(schema, payload) {
  const { error, value } = schema.validate(payload, { abortEarly: false, stripUnknown: true });
  if (error) throw new AppError(400, 'Validation failed', error.details.map((d) => d.message));
  return value;
}

const OP_HANDLERS = {
  product_create: ({ payload, user }) => productService.createProduct(validated(createProductSchema, payload), user),
  product_update: ({ productId, payload, user }) => productService.updateProduct(productId, validated(updateProductSchema, payload), user),
  product_delete: ({ productId, user }) => productService.deleteProduct(productId, user),
  stock_adjust: async ({ productId, payload, user }) => (await productService.adjustStock(productId, validated(adjustStockSchema, payload), user)).product,
};

// Applies one queued offline product change. Devices send them one at a time,
// in order, because a later op may depend on the id a product_create returns.
// The opId is claimed first, so a retry or a concurrent duplicate cannot apply
// the change twice; the claim is released if applying it fails.
const applyOp = asyncHandler(async (req, res) => {
  const { opId, type, productId, payload } = req.body;

  try {
    await SyncOp.create({ opId, type, product: productId, actor: req.user._id });
  } catch (err) {
    if (err.code !== 11000) throw err;
    const done = await SyncOp.findOne({ opId });
    const product = done && done.product ? await Product.findById(done.product) : null;
    return res.json({ status: 'ok', alreadyApplied: true, product });
  }

  try {
    const product = await OP_HANDLERS[type]({ productId, payload, user: req.user });
    await SyncOp.updateOne({ opId }, { product: product._id });
    res.json({ status: 'ok', alreadyApplied: false, product });
  } catch (err) {
    await SyncOp.deleteOne({ opId });
    throw err;
  }
});

module.exports = { pushSales, pullDeltas, applyOp };
