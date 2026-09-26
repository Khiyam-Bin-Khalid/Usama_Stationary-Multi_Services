const asyncHandler = require('../utils/asyncHandler');
const AppError = require('../utils/AppError');
const { getSalesReport, getCategoryBreakdown } = require('../services/reportingService');
const { ROLES } = require('../utils/constants');

// SRS 3.3: staff have "limited reporting access" — daily figures for their
// own shift only, not weekly/monthly/yearly trend or cross-branch reports.
const salesReport = asyncHandler(async (req, res) => {
  if (req.user.role === ROLES.STAFF && req.query.period !== 'daily') {
    throw new AppError(403, 'Staff may only view daily sales figures');
  }
  const report = await getSalesReport(req.query);
  res.json(report);
});

const categoryReport = asyncHandler(async (req, res) => {
  const categories = await getCategoryBreakdown(req.query);
  res.json({ categories });
});

module.exports = { salesReport, categoryReport };
