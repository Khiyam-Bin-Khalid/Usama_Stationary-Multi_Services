const mongoose = require('mongoose');
const Sale = require('../models/Sale');
const Order = require('../models/Order');
const AppError = require('../utils/AppError');

const PERIOD_UNITS = { daily: 'day', weekly: 'week', monthly: 'month', yearly: 'year' };

function buildMatch({ from, to, cashierId }) {
  const match = {};
  if (cashierId) match.cashier = cashierId;
  if (from || to) {
    match.createdAt = {};
    if (from) match.createdAt.$gte = new Date(from);
    if (to) match.createdAt.$lte = new Date(to);
  }
  return match;
}

// Flattens a Sale/Order collection to one row per line item, tagging the
// source ('pos' | 'online') and computing per-item tax. Tax is a flat
// percentage of the document subtotal, so items.lineTotal * taxRate/100 is
// exact — no prorating error — because subtotal = sum(items.lineTotal).
function itemPipeline({ match, category, product, sourceLabel }) {
  const itemMatch = {};
  if (category) itemMatch['items.category'] = category;
  if (product) itemMatch['items.product'] = new mongoose.Types.ObjectId(product);
  return [
    { $match: match },
    { $addFields: { __source: sourceLabel } },
    { $unwind: '$items' },
    ...(Object.keys(itemMatch).length ? [{ $match: itemMatch }] : []),
    {
      $project: {
        createdAt: 1,
        __source: 1,
        lineTotal: '$items.lineTotal',
        quantity: '$items.quantity',
        category: '$items.category',
        product: '$items.product',
        productName: '$items.name',
        sku: '$items.sku',
        itemTax: {
          $multiply: ['$items.lineTotal', { $divide: [{ $ifNull: ['$taxRate', 0] }, 100] }],
        },
      },
    },
  ];
}

// Online orders only count as sales once the money is settled or the order
// is on its way — cancelled / rejected orders never inflate revenue.
const COUNTED_ORDER_STATUSES = ['confirmed', 'processing', 'packing', 'dispatched', 'out_for_delivery', 'delivered', 'completed'];

function orderMatch(base) {
  return { ...base, status: { $in: COUNTED_ORDER_STATUSES } };
}

async function getSalesReport({ from, to, category, product, period = 'daily', source = 'all', cashierId }) {
  const unit = PERIOD_UNITS[period];
  if (!unit) throw new AppError(400, `Invalid period: ${period}. Use daily, weekly, monthly, or yearly.`);
  if (!['pos', 'online', 'all'].includes(source)) throw new AppError(400, `Invalid source: ${source}`);

  const match = buildMatch({ from, to, cashierId });
  const salePipeline = itemPipeline({ match, category, product, sourceLabel: 'pos' });
  // Orders have no cashier — a cashier-scoped (staff) report is POS-only.
  const orderPipeline = itemPipeline({ match: orderMatch(buildMatch({ from, to })), category, product, sourceLabel: 'online' });

  const groupStages = [
    {
      $group: {
        _id: { $dateTrunc: { date: '$createdAt', unit, timezone: 'UTC' } },
        revenue: { $sum: '$lineTotal' },
        tax: { $sum: '$itemTax' },
        itemsSold: { $sum: '$quantity' },
      },
    },
    { $sort: { _id: 1 } },
    {
      $project: {
        _id: 0,
        period: '$_id',
        revenue: { $round: ['$revenue', 2] },
        tax: { $round: ['$tax', 2] },
        itemsSold: 1,
      },
    },
  ];

  // $unionWith requires running the aggregate on one base collection, so a
  // single-source report runs straight against that model instead.
  let buckets;
  if (source === 'pos') {
    buckets = await Sale.aggregate([...salePipeline, ...groupStages]);
  } else if (source === 'online') {
    buckets = await Order.aggregate([...orderPipeline, ...groupStages]);
  } else {
    buckets = await Sale.aggregate([
      ...salePipeline,
      { $unionWith: { coll: Order.collection.name, pipeline: orderPipeline } },
      ...groupStages,
    ]);
  }
  const summary = buckets.reduce(
    (acc, b) => ({
      totalRevenue: Number((acc.totalRevenue + b.revenue).toFixed(2)),
      totalTax: Number((acc.totalTax + b.tax).toFixed(2)),
      totalItemsSold: acc.totalItemsSold + b.itemsSold,
    }),
    { totalRevenue: 0, totalTax: 0, totalItemsSold: 0 }
  );

  return { period, source, category: category || null, product: product || null, from: from || null, to: to || null, buckets, summary };
}

async function getCategoryBreakdown({ from, to, source = 'all' }) {
  const match = buildMatch({ from, to });
  const salePipeline = itemPipeline({ match, sourceLabel: 'pos' });
  const orderPipeline = itemPipeline({ match: orderMatch(match), sourceLabel: 'online' });

  const groupStages = [
    {
      $group: {
        _id: '$category',
        revenue: { $sum: '$lineTotal' },
        itemsSold: { $sum: '$quantity' },
      },
    },
    { $sort: { revenue: -1 } },
    { $project: { _id: 0, category: '$_id', revenue: { $round: ['$revenue', 2] }, itemsSold: 1 } },
  ];

  if (source === 'pos') return Sale.aggregate([...salePipeline, ...groupStages]);
  if (source === 'online') return Order.aggregate([...orderPipeline, ...groupStages]);
  return Sale.aggregate([
    ...salePipeline,
    { $unionWith: { coll: Order.collection.name, pipeline: orderPipeline } },
    ...groupStages,
  ]);
}

// Revenue + units per product (top sellers), optionally within a category.
async function getProductBreakdown({ from, to, source = 'all', category, limit = 20 }) {
  const match = buildMatch({ from, to });
  const salePipeline = itemPipeline({ match, category, sourceLabel: 'pos' });
  const orderPipeline = itemPipeline({ match: orderMatch(match), category, sourceLabel: 'online' });

  const groupStages = [
    {
      $group: {
        _id: '$product',
        name: { $last: '$productName' },
        sku: { $last: '$sku' },
        category: { $last: '$category' },
        revenue: { $sum: '$lineTotal' },
        itemsSold: { $sum: '$quantity' },
      },
    },
    { $sort: { revenue: -1 } },
    { $limit: limit },
    { $project: { _id: 0, product: '$_id', name: 1, sku: 1, category: 1, revenue: { $round: ['$revenue', 2] }, itemsSold: 1 } },
  ];

  if (source === 'pos') return Sale.aggregate([...salePipeline, ...groupStages]);
  if (source === 'online') return Order.aggregate([...orderPipeline, ...groupStages]);
  return Sale.aggregate([
    ...salePipeline,
    { $unionWith: { coll: Order.collection.name, pipeline: orderPipeline } },
    ...groupStages,
  ]);
}

module.exports = { getSalesReport, getCategoryBreakdown, getProductBreakdown };
