const Sale = require('../models/Sale');
const Order = require('../models/Order');
const AppError = require('../utils/AppError');

const PERIOD_UNITS = { daily: 'day', weekly: 'week', monthly: 'month', yearly: 'year' };

function buildMatch({ from, to }) {
  const match = {};
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
function itemPipeline({ match, category, sourceLabel }) {
  return [
    { $match: match },
    { $addFields: { __source: sourceLabel } },
    { $unwind: '$items' },
    ...(category ? [{ $match: { 'items.category': category } }] : []),
    {
      $project: {
        createdAt: 1,
        __source: 1,
        lineTotal: '$items.lineTotal',
        quantity: '$items.quantity',
        category: '$items.category',
        itemTax: {
          $multiply: ['$items.lineTotal', { $divide: [{ $ifNull: ['$taxRate', 0] }, 100] }],
        },
      },
    },
  ];
}

async function getSalesReport({ from, to, category, period = 'daily', source = 'all' }) {
  const unit = PERIOD_UNITS[period];
  if (!unit) throw new AppError(400, `Invalid period: ${period}. Use daily, weekly, monthly, or yearly.`);
  if (!['pos', 'online', 'all'].includes(source)) throw new AppError(400, `Invalid source: ${source}`);

  const match = buildMatch({ from, to });
  const salePipeline = itemPipeline({ match, category, sourceLabel: 'pos' });
  const orderPipeline = itemPipeline({ match, category, sourceLabel: 'online' });

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

  return { period, source, category: category || null, buckets, summary };
}

async function getCategoryBreakdown({ from, to, source = 'all' }) {
  const match = buildMatch({ from, to });
  const salePipeline = itemPipeline({ match, sourceLabel: 'pos' });
  const orderPipeline = itemPipeline({ match, sourceLabel: 'online' });

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

module.exports = { getSalesReport, getCategoryBreakdown };
