const DiscrepancyReport = require('../models/DiscrepancyReport');
const Product = require('../models/Product');
const AppError = require('../utils/AppError');
const { applyStockChange } = require('./inventoryService');
const { logAction } = require('./auditService');
const { domainEvents, EVENTS } = require('./events');
const { DISCREPANCY_STATUSES, INVENTORY_LOG_TYPES } = require('../utils/constants');

async function reportDiscrepancy({ productId, countedQty, note, reporter }) {
  const product = await Product.findById(productId);
  if (!product) throw new AppError(404, 'Product not found');

  const report = await DiscrepancyReport.create({
    product: product._id,
    category: product.category,
    productName: product.name,
    systemQty: product.currentStock,
    countedQty,
    note,
    reportedBy: reporter._id,
  });

  await logAction({
    actorUser: reporter,
    action: 'inventory.discrepancy_reported',
    entityType: 'DiscrepancyReport',
    entityId: report._id,
    after: { product: product.name, systemQty: product.currentStock, countedQty },
  });

  domainEvents.emitSafe(EVENTS.DISCREPANCY_REPORTED, {
    reportId: report._id,
    productId: product._id,
    productName: product.name,
    category: product.category,
    systemQty: product.currentStock,
    countedQty,
    reportedByName: reporter.name,
  });

  return report;
}

async function resolveDiscrepancy({ reportId, applyAdjustment, resolution, dismiss, resolver }) {
  const report = await DiscrepancyReport.findById(reportId);
  if (!report) throw new AppError(404, 'Discrepancy report not found');
  if (report.status !== DISCREPANCY_STATUSES.OPEN) throw new AppError(409, 'This report has already been handled');

  let adjustmentApplied;
  if (!dismiss && applyAdjustment) {
    const product = await Product.findById(report.product);
    if (!product) throw new AppError(404, 'Product no longer exists');
    const delta = report.countedQty - product.currentStock;
    if (delta !== 0) {
      await applyStockChange({
        productId: product._id,
        category: product.category,
        delta,
        type: INVENTORY_LOG_TYPES.ADJUSTMENT,
        reference: report._id.toString(),
        reason: `Discrepancy report resolved: ${resolution || 'shelf count applied'}`,
        actor: resolver._id,
        actorRole: resolver.role,
        branch: product.branch,
      });
    }
    adjustmentApplied = delta;
  }

  report.status = dismiss ? DISCREPANCY_STATUSES.DISMISSED : DISCREPANCY_STATUSES.RESOLVED;
  report.resolvedBy = resolver._id;
  report.resolvedAt = new Date();
  report.resolution = resolution;
  report.adjustmentApplied = adjustmentApplied;
  await report.save();

  await logAction({
    actorUser: resolver,
    action: dismiss ? 'inventory.discrepancy_dismissed' : 'inventory.discrepancy_resolved',
    entityType: 'DiscrepancyReport',
    entityId: report._id,
    after: { resolution, adjustmentApplied },
  });

  return report;
}

module.exports = { reportDiscrepancy, resolveDiscrepancy };
