const Shift = require('../models/Shift');
const AppError = require('../utils/AppError');
const asyncHandler = require('../utils/asyncHandler');
const { openShift, closeShift, currentOpenShift, getShiftReport } = require('../services/shiftService');
const { logAction } = require('../services/auditService');
const { ROLES } = require('../utils/constants');

const open = asyncHandler(async (req, res) => {
  const shift = await openShift({ staffId: req.user._id, branch: req.body.branch || req.user.branch, ...req.body });
  await logAction({ actorUser: req.user, action: 'shift.open', entityType: 'Shift', entityId: shift._id, after: { openingCash: shift.openingCash } });
  res.status(201).json({ shift });
});

const close = asyncHandler(async (req, res) => {
  const shift = await closeShift({ staffId: req.user._id, ...req.body });
  await logAction({
    actorUser: req.user,
    action: 'shift.close',
    entityType: 'Shift',
    entityId: shift._id,
    after: { closingCashExpected: shift.closingCashExpected, closingCashActual: shift.closingCashActual, cashVariance: shift.cashVariance },
  });
  res.json({ shift });
});

const current = asyncHandler(async (req, res) => {
  const shift = await currentOpenShift(req.user._id);
  if (!shift) return res.json({ shift: null, report: null });
  const report = await getShiftReport(shift);
  res.json(report);
});

// Staff see their own shifts; admin/superadmin see everyone's.
const list = asyncHandler(async (req, res) => {
  const filter = req.user.role === ROLES.STAFF ? { staff: req.user._id } : {};
  const shifts = await Shift.find(filter).sort({ openedAt: -1 }).limit(100).populate('staff', 'name email');
  res.json({ shifts });
});

const report = asyncHandler(async (req, res) => {
  const shift = await Shift.findById(req.params.id).populate('staff', 'name email');
  if (!shift) throw new AppError(404, 'Shift not found');
  if (req.user.role === ROLES.STAFF && !shift.staff._id.equals(req.user._id)) {
    throw new AppError(403, 'You may only view your own shifts');
  }
  res.json(await getShiftReport(shift));
});

module.exports = { open, close, current, list, report };
