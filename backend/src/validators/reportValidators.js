const Joi = require('joi');
const salesReportQuerySchema = Joi.object({
  period: Joi.string().valid('daily', 'weekly', 'monthly', 'yearly').default('daily'),
  source: Joi.string().valid('pos', 'online', 'all').default('all'),
  category: Joi.string().pattern(/^[a-z][a-z0-9_]*$/).max(40),
  product: Joi.string().hex().length(24),
  from: Joi.date(),
  to: Joi.date(),
});

const productReportQuerySchema = Joi.object({
  source: Joi.string().valid('pos', 'online', 'all').default('all'),
  category: Joi.string().pattern(/^[a-z][a-z0-9_]*$/).max(40),
  from: Joi.date(),
  to: Joi.date(),
  limit: Joi.number().integer().min(1).max(100).default(20),
});

const inventoryMovementsQuerySchema = Joi.object({
  product: Joi.string().hex().length(24),
  sku: Joi.string().max(50),
  category: Joi.string().pattern(/^[a-z][a-z0-9_]*$/).max(40),
  type: Joi.string().max(30),
  from: Joi.date(),
  to: Joi.date(),
  page: Joi.number().integer().min(1).default(1),
  limit: Joi.number().integer().min(1).max(200).default(50),
});

const categoryReportQuerySchema = Joi.object({
  source: Joi.string().valid('pos', 'online', 'all').default('all'),
  from: Joi.date(),
  to: Joi.date(),
});

module.exports = { salesReportQuerySchema, categoryReportQuerySchema, productReportQuerySchema, inventoryMovementsQuerySchema };
