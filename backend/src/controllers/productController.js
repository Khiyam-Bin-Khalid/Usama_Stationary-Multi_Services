const Product = require('../models/Product');
const InventoryLog = require('../models/InventoryLog');
const AppError = require('../utils/AppError');
const asyncHandler = require('../utils/asyncHandler');
const { logAction } = require('../services/auditService');
const { storeFile, removeLocalFile } = require('../services/fileStorageService');
const productService = require('../services/productService');

function escapeRegex(value) {
  return String(value).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

const listProducts = asyncHandler(async (req, res) => {
  const { category, q, barcode, sku, isAvailableOnline, isActive, lowStockOnly, sellableOnly, page, limit } = req.query;
  const filter = {};

  if (category) filter.category = category;
  if (isAvailableOnline !== undefined) filter.isAvailableOnline = isAvailableOnline;
  filter.isActive = isActive !== undefined ? isActive : true;
  // Free-text search matches name, SKU and barcode (partial, case-insensitive)
  // so a cashier can type either the product name or part of its code.
  if (q) {
    const re = new RegExp(escapeRegex(q), 'i');
    filter.$or = [{ name: re }, { sku: re }, { barcode: re }, { description: re }];
  }
  if (barcode) filter.barcode = barcode;
  if (sku) filter.sku = sku.toUpperCase();
  // Spec §4.1: out-of-stock products are hidden from sellable lists but kept.
  // Unauthenticated (storefront) callers always get sellable-only results.
  // Combined with $and: both this and the search above are $or clauses, and
  // merging them onto one object would silently discard the search.
  if (sellableOnly || !req.user) {
    const { $or: inStock, ...sellable } = Product.sellableFilter();
    Object.assign(filter, sellable, { isActive: filter.isActive, $and: [{ $or: inStock }] });
  }

  let query = Product.find(filter).sort({ name: 1 });
  if (lowStockOnly) {
    query = Product.find({ ...filter, isMadeToOrder: false, $expr: { $lte: ['$currentStock', '$reorderThreshold'] } });
  }
  // Staff/Admin/Super Admin (Inventory screen) can see who added each
  // product; the public storefront never gets staff identities, not even
  // the raw user id.
  query = req.user ? query.populate('createdBy', 'name role') : query.select('-createdBy');

  const total = await Product.countDocuments(query.getFilter());
  const products = await query.skip((page - 1) * limit).limit(limit);

  res.json({ products, total, page, limit });
});

const getProduct = asyncHandler(async (req, res) => {
  let query = Product.findById(req.params.id);
  query = req.user ? query.populate('createdBy', 'name role') : query.select('-createdBy');
  const product = await query;
  if (!product) throw new AppError(404, 'Product not found');
  res.json({ product });
});

const createProduct = asyncHandler(async (req, res) => {
  const product = await productService.createProduct(req.body, req.user);
  res.status(201).json({ product });
});

const updateProduct = asyncHandler(async (req, res) => {
  const product = await productService.updateProduct(req.params.id, req.body, req.user);
  res.json({ product });
});

const deleteProduct = asyncHandler(async (req, res) => {
  const product = await productService.deleteProduct(req.params.id, req.user);
  res.json({ ok: true, product });
});

const adjustStock = asyncHandler(async (req, res) => {
  const { product, log } = await productService.adjustStock(req.params.id, req.body, req.user);
  res.json({ product, log });
});

const getProductInventoryLog = asyncHandler(async (req, res) => {
  const logs = await InventoryLog.find({ product: req.params.id }).sort({ createdAt: -1 }).limit(200);
  res.json({ logs });
});

// Spec: product photo, shown to staff in Inventory and to customers browsing
// the storefront catalog. Uploaded as a separate step after create/update so
// the form works the same whether or not a photo is attached.
const uploadProductImage = asyncHandler(async (req, res) => {
  if (!req.file) throw new AppError(400, 'No image file uploaded');
  const product = await Product.findById(req.params.id);
  if (!product) throw new AppError(404, 'Product not found');

  const before = { imageUrl: product.imageUrl };
  product.imageUrl = await storeFile(req.file, { folder: 'products' });
  await product.save();
  // Only after the new URL is saved: the old local file is no longer served.
  if (before.imageUrl !== product.imageUrl) await removeLocalFile(before.imageUrl);
  await product.populate('createdBy', 'name role');

  await logAction({
    actorUser: req.user,
    action: 'product.image',
    entityType: 'Product',
    entityId: product._id,
    before,
    after: { imageUrl: product.imageUrl },
  });
  res.json({ product });
});

module.exports = {
  listProducts,
  getProduct,
  createProduct,
  updateProduct,
  deleteProduct,
  adjustStock,
  getProductInventoryLog,
  uploadProductImage,
};
