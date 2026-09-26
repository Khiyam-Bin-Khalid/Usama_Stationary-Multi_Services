const Product = require('../models/Product');
const InventoryLog = require('../models/InventoryLog');
const AppError = require('../utils/AppError');
const asyncHandler = require('../utils/asyncHandler');
const { applyStockChange } = require('../services/inventoryService');
const { INVENTORY_LOG_TYPES } = require('../utils/constants');
const { logAction } = require('../services/auditService');

const listProducts = asyncHandler(async (req, res) => {
  const { category, q, isAvailableOnline, isActive, lowStockOnly, page, limit } = req.query;
  const filter = {};

  if (category) filter.category = category;
  if (isAvailableOnline !== undefined) filter.isAvailableOnline = isAvailableOnline;
  filter.isActive = isActive !== undefined ? isActive : true;
  if (q) filter.$text = { $search: q };

  let query = Product.find(filter).sort({ name: 1 });
  if (lowStockOnly) {
    query = Product.find({ ...filter, isMadeToOrder: false, $expr: { $lte: ['$currentStock', '$reorderThreshold'] } });
  }

  const total = await Product.countDocuments(query.getFilter());
  const products = await query.skip((page - 1) * limit).limit(limit);

  res.json({ products, total, page, limit });
});

const getProduct = asyncHandler(async (req, res) => {
  const product = await Product.findById(req.params.id);
  if (!product) throw new AppError(404, 'Product not found');
  res.json({ product });
});

const createProduct = asyncHandler(async (req, res) => {
  const product = await Product.create(req.body);

  if (product.currentStock > 0) {
    await InventoryLog.create({
      product: product._id,
      type: INVENTORY_LOG_TYPES.PURCHASE,
      quantityDelta: product.currentStock,
      resultingStock: product.currentStock,
      reason: 'Initial stock on product creation',
      actor: req.user._id,
      branch: product.branch,
    });
  }

  await logAction({ actor: req.user._id, action: 'product.create', entityType: 'Product', entityId: product._id });
  res.status(201).json({ product });
});

const updateProduct = asyncHandler(async (req, res) => {
  const product = await Product.findByIdAndUpdate(req.params.id, req.body, { new: true, runValidators: true });
  if (!product) throw new AppError(404, 'Product not found');

  await logAction({ actor: req.user._id, action: 'product.update', entityType: 'Product', entityId: product._id, details: req.body });
  res.json({ product });
});

const adjustStock = asyncHandler(async (req, res) => {
  const { delta, reason } = req.body;
  const { product, log } = await applyStockChange({
    productId: req.params.id,
    delta,
    type: INVENTORY_LOG_TYPES.ADJUSTMENT,
    reason,
    actor: req.user._id,
    branch: req.user.branch,
  });

  await logAction({ actor: req.user._id, action: 'inventory.adjust', entityType: 'Product', entityId: product._id, details: { delta, reason } });
  res.json({ product, log });
});

const getProductInventoryLog = asyncHandler(async (req, res) => {
  const logs = await InventoryLog.find({ product: req.params.id }).sort({ createdAt: -1 }).limit(200);
  res.json({ logs });
});

module.exports = {
  listProducts,
  getProduct,
  createProduct,
  updateProduct,
  adjustStock,
  getProductInventoryLog,
};
