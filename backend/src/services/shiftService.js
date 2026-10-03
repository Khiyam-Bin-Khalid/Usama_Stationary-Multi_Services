const Shift = require('../models/Shift');
const Sale = require('../models/Sale');
const AppError = require('../utils/AppError');
const { SHIFT_STATUSES } = require('../utils/constants');

function currentOpenShift(staffId) {
  return Shift.findOne({ staff: staffId, status: SHIFT_STATUSES.OPEN });
}

async function openShift({ staffId, openingCash, branch, note }) {
  const existing = await currentOpenShift(staffId);
  if (existing) throw new AppError(409, 'You already have an open shift — close it before opening a new one');
  return Shift.create({ staff: staffId, openingCash, branch, note, openedAt: new Date() });
}

async function summarizeShiftSales(shiftId) {
  const [row] = await Sale.aggregate([
    { $match: { shift: shiftId } },
    {
      $group: {
        _id: null,
        salesCount: { $sum: 1 },
        salesTotal: { $sum: '$total' },
        cashSalesTotal: { $sum: { $cond: [{ $eq: ['$paymentMethod', 'cash'] }, '$total', 0] } },
        cardSalesTotal: { $sum: { $cond: [{ $eq: ['$paymentMethod', 'card'] }, '$total', 0] } },
        taxTotal: { $sum: '$taxAmount' },
      },
    },
  ]);
  return {
    salesCount: row?.salesCount || 0,
    salesTotal: Number((row?.salesTotal || 0).toFixed(2)),
    cashSalesTotal: Number((row?.cashSalesTotal || 0).toFixed(2)),
    cardSalesTotal: Number((row?.cardSalesTotal || 0).toFixed(2)),
    taxTotal: Number((row?.taxTotal || 0).toFixed(2)),
  };
}

async function closeShift({ staffId, closingCashActual, note }) {
  const shift = await currentOpenShift(staffId);
  if (!shift) throw new AppError(404, 'No open shift to close');

  const summary = await summarizeShiftSales(shift._id);
  shift.salesCount = summary.salesCount;
  shift.salesTotal = summary.salesTotal;
  shift.cashSalesTotal = summary.cashSalesTotal;
  shift.cardSalesTotal = summary.cardSalesTotal;
  shift.closingCashExpected = Number((shift.openingCash + summary.cashSalesTotal).toFixed(2));
  shift.closingCashActual = closingCashActual;
  shift.cashVariance = Number((closingCashActual - shift.closingCashExpected).toFixed(2));
  if (note) shift.note = note;
  shift.status = SHIFT_STATUSES.CLOSED;
  shift.closedAt = new Date();
  await shift.save();
  return shift;
}

// Live view of a shift (open or closed) — the Z-report (spec §6).
async function getShiftReport(shift) {
  const summary = await summarizeShiftSales(shift._id);
  const expected = Number((shift.openingCash + summary.cashSalesTotal).toFixed(2));
  return {
    shift,
    ...summary,
    closingCashExpected: shift.status === SHIFT_STATUSES.CLOSED ? shift.closingCashExpected : expected,
  };
}

module.exports = { currentOpenShift, openShift, closeShift, getShiftReport, summarizeShiftSales };
