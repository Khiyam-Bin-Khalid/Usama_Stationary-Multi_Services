const Joi = require('joi');

const openShiftSchema = Joi.object({
  openingCash: Joi.number().min(0).default(0),
  branch: Joi.string().max(100).allow('', null),
  note: Joi.string().max(300).allow('', null),
});

const closeShiftSchema = Joi.object({
  closingCashActual: Joi.number().min(0).required(),
  note: Joi.string().max(300).allow('', null),
});

const createCategorySchema = Joi.object({
  key: Joi.string().pattern(/^[a-z][a-z0-9_]*$/).max(40).required(),
  name: Joi.string().min(2).max(60).required(),
  unitType: Joi.string().max(30).default('piece'),
  defaultReorderThreshold: Joi.number().min(0).default(5),
});

const updateCategorySchema = Joi.object({
  name: Joi.string().min(2).max(60),
  unitType: Joi.string().max(30),
  defaultReorderThreshold: Joi.number().min(0),
  isActive: Joi.boolean(),
}).min(1);

const reportDiscrepancySchema = Joi.object({
  product: Joi.string().hex().length(24).required(),
  countedQty: Joi.number().min(0).required(),
  note: Joi.string().max(500).allow('', null),
});

const resolveDiscrepancySchema = Joi.object({
  applyAdjustment: Joi.boolean().default(false),
  dismiss: Joi.boolean().default(false),
  resolution: Joi.string().max(500).allow('', null),
});

const listDiscrepanciesQuerySchema = Joi.object({
  status: Joi.string().valid('open', 'resolved', 'dismissed'),
  page: Joi.number().integer().min(1).default(1),
  limit: Joi.number().integer().min(1).max(200).default(50),
});

const listNotificationsQuerySchema = Joi.object({
  unreadOnly: Joi.boolean().default(false),
  page: Joi.number().integer().min(1).default(1),
  limit: Joi.number().integer().min(1).max(200).default(50),
});

const listAuditQuerySchema = Joi.object({
  action: Joi.string().max(100),
  actor: Joi.string().hex().length(24),
  entityType: Joi.string().max(50),
  from: Joi.date(),
  to: Joi.date(),
  page: Joi.number().integer().min(1).default(1),
  limit: Joi.number().integer().min(1).max(200).default(50),
});

module.exports = {
  openShiftSchema,
  closeShiftSchema,
  createCategorySchema,
  updateCategorySchema,
  reportDiscrepancySchema,
  resolveDiscrepancySchema,
  listDiscrepanciesQuerySchema,
  listNotificationsQuerySchema,
  listAuditQuerySchema,
};
