const asyncHandler = require('../utils/asyncHandler');
const { listMovements, lowStockProducts } = require('../services/inventoryService');

// GET /api/inventory/movements — every stock change across the shop, newest
// first: product, SKU, previous stock, delta, resulting stock, type, related
// sale/order, who did it and when.
const movements = asyncHandler(async (req, res) => {
  res.json(await listMovements(req.query));
});

// GET /api/inventory/low-stock — products at/below their reorder level.
const lowStock = asyncHandler(async (req, res) => {
  const products = await lowStockProducts();
  res.json({ products, total: products.length });
});

module.exports = { movements, lowStock };
