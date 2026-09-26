const Joi = require('joi');
const { PRODUCT_CATEGORIES } = require('../utils/constants');

const createProductSchema = Joi.object({
  name: Joi.string().min(1).max(150).required(),
  sku: Joi.string().min(1).max(50).required(),
  category: Joi.string().valid(...Object.values(PRODUCT_CATEGORIES)).required(),
  unit: Joi.string().max(20).default('pcs'),
  price: Joi.number().min(0).required(),
  costPrice: Joi.number().min(0).default(0),
  currentStock: Joi.number().min(0).default(0),
  reorderThreshold: Joi.number().min(0).default(5),
  isMadeToOrder: Joi.boolean().default(false),
  isAvailableOnline: Joi.boolean().default(true),
  imageUrl: Joi.string().uri().allow('', null),
  description: Joi.string().max(2000).allow('', null),
  branch: Joi.string().max(100).allow('', null),
});

const updateProductSchema = Joi.object({
  name: Joi.string().min(1).max(150),
  category: Joi.string().valid(...Object.values(PRODUCT_CATEGORIES)),
  unit: Joi.string().max(20),
  price: Joi.number().min(0),
  costPrice: Joi.number().min(0),
  reorderThreshold: Joi.number().min(0),
  isMadeToOrder: Joi.boolean(),
  isAvailableOnline: Joi.boolean(),
  isActive: Joi.boolean(),
  imageUrl: Joi.string().uri().allow('', null),
  description: Joi.string().max(2000).allow('', null),
  branch: Joi.string().max(100).allow('', null),
}).min(1);

const adjustStockSchema = Joi.object({
  delta: Joi.number().invalid(0).required(),
  reason: Joi.string().max(300).required(),
});

const listProductsQuerySchema = Joi.object({
  category: Joi.string().valid(...Object.values(PRODUCT_CATEGORIES)),
  q: Joi.string().max(100),
  isAvailableOnline: Joi.boolean(),
  isActive: Joi.boolean(),
  lowStockOnly: Joi.boolean(),
  page: Joi.number().integer().min(1).default(1),
  limit: Joi.number().integer().min(1).max(200).default(50),
});

module.exports = {
  createProductSchema,
  updateProductSchema,
  adjustStockSchema,
  listProductsQuerySchema,
};
