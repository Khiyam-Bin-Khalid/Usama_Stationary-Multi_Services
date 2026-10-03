const Category = require('../models/Category');
const AppError = require('../utils/AppError');
const asyncHandler = require('../utils/asyncHandler');
const { logAction } = require('../services/auditService');

const listCategories = asyncHandler(async (req, res) => {
  const categories = await Category.find({ isActive: true }).sort({ name: 1 });
  res.json({ categories });
});

const createCategory = asyncHandler(async (req, res) => {
  const existing = await Category.findOne({ key: req.body.key });
  if (existing) throw new AppError(409, `Category "${req.body.key}" already exists`);
  const category = await Category.create(req.body);
  await logAction({ actorUser: req.user, action: 'category.create', entityType: 'Category', entityId: category._id, after: req.body });
  res.status(201).json({ category });
});

const updateCategory = asyncHandler(async (req, res) => {
  const category = await Category.findOne({ key: req.params.key });
  if (!category) throw new AppError(404, 'Category not found');
  const before = category.toObject();
  Object.assign(category, req.body);
  await category.save();
  await logAction({
    actorUser: req.user,
    action: 'category.update',
    entityType: 'Category',
    entityId: category._id,
    before: { name: before.name, unitType: before.unitType, defaultReorderThreshold: before.defaultReorderThreshold, isActive: before.isActive },
    after: req.body,
  });
  res.json({ category });
});

module.exports = { listCategories, createCategory, updateCategory };
