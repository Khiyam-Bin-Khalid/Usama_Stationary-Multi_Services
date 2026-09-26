const Promotion = require('../models/Promotion');
const AppError = require('../utils/AppError');
const asyncHandler = require('../utils/asyncHandler');
const { logAction } = require('../services/auditService');

// Public: storefront shows currently-active promotions (SRS FR-5.5).
const listActivePromotions = asyncHandler(async (req, res) => {
  const now = new Date();
  const promotions = await Promotion.find({ isActive: true, startDate: { $lte: now }, endDate: { $gte: now } });
  res.json({ promotions });
});

// Admin: manage all promotions regardless of date window.
const listAllPromotions = asyncHandler(async (req, res) => {
  const promotions = await Promotion.find().sort({ startDate: -1 });
  res.json({ promotions });
});

const createPromotion = asyncHandler(async (req, res) => {
  const promotion = await Promotion.create({ ...req.body, createdBy: req.user._id });
  await logAction({ actor: req.user._id, action: 'promotion.create', entityType: 'Promotion', entityId: promotion._id });
  res.status(201).json({ promotion });
});

const updatePromotion = asyncHandler(async (req, res) => {
  const promotion = await Promotion.findByIdAndUpdate(req.params.id, req.body, { new: true, runValidators: true });
  if (!promotion) throw new AppError(404, 'Promotion not found');
  await logAction({ actor: req.user._id, action: 'promotion.update', entityType: 'Promotion', entityId: promotion._id, details: req.body });
  res.json({ promotion });
});

module.exports = { listActivePromotions, listAllPromotions, createPromotion, updatePromotion };
