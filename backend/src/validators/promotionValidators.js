const Joi = require('joi');
const { PRODUCT_CATEGORIES } = require('../utils/constants');

const createPromotionSchema = Joi.object({
  name: Joi.string().min(1).max(150).required(),
  description: Joi.string().max(1000).allow('', null),
  discountType: Joi.string().valid('percent', 'flat').required(),
  discountValue: Joi.number().min(0).required(),
  categories: Joi.array().items(Joi.string().valid(...Object.values(PRODUCT_CATEGORIES))).default([]),
  products: Joi.array().items(Joi.string().hex().length(24)).default([]),
  startDate: Joi.date().required(),
  endDate: Joi.date().greater(Joi.ref('startDate')).required(),
  isActive: Joi.boolean().default(true),
});

const updatePromotionSchema = Joi.object({
  name: Joi.string().min(1).max(150),
  description: Joi.string().max(1000).allow('', null),
  discountType: Joi.string().valid('percent', 'flat'),
  discountValue: Joi.number().min(0),
  categories: Joi.array().items(Joi.string().valid(...Object.values(PRODUCT_CATEGORIES))),
  products: Joi.array().items(Joi.string().hex().length(24)),
  startDate: Joi.date(),
  endDate: Joi.date(),
  isActive: Joi.boolean(),
}).min(1);

module.exports = { createPromotionSchema, updatePromotionSchema };
