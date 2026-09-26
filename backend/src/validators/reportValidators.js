const Joi = require('joi');
const { PRODUCT_CATEGORIES } = require('../utils/constants');

const salesReportQuerySchema = Joi.object({
  period: Joi.string().valid('daily', 'weekly', 'monthly', 'yearly').default('daily'),
  source: Joi.string().valid('pos', 'online', 'all').default('all'),
  category: Joi.string().valid(...Object.values(PRODUCT_CATEGORIES)),
  from: Joi.date(),
  to: Joi.date(),
});

const categoryReportQuerySchema = Joi.object({
  source: Joi.string().valid('pos', 'online', 'all').default('all'),
  from: Joi.date(),
  to: Joi.date(),
});

module.exports = { salesReportQuerySchema, categoryReportQuerySchema };
