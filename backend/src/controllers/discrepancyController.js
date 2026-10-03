const DiscrepancyReport = require('../models/DiscrepancyReport');
const asyncHandler = require('../utils/asyncHandler');
const { reportDiscrepancy, resolveDiscrepancy } = require('../services/discrepancyService');
const { ROLES } = require('../utils/constants');

const create = asyncHandler(async (req, res) => {
  const report = await reportDiscrepancy({
    productId: req.body.product,
    countedQty: req.body.countedQty,
    note: req.body.note,
    reporter: req.user,
  });
  res.status(201).json({ report });
});

// Staff see only what they reported; admin/superadmin see everything.
const list = asyncHandler(async (req, res) => {
  const { status, page, limit } = req.query;
  const filter = {};
  if (status) filter.status = status;
  if (req.user.role === ROLES.STAFF) filter.reportedBy = req.user._id;

  const total = await DiscrepancyReport.countDocuments(filter);
  const reports = await DiscrepancyReport.find(filter)
    .sort({ createdAt: -1 })
    .skip((page - 1) * limit)
    .limit(limit)
    .populate('reportedBy', 'name email')
    .populate('resolvedBy', 'name email');
  res.json({ reports, total, page, limit });
});

const resolve = asyncHandler(async (req, res) => {
  const report = await resolveDiscrepancy({ reportId: req.params.id, resolver: req.user, ...req.body });
  res.json({ report });
});

module.exports = { create, list, resolve };
