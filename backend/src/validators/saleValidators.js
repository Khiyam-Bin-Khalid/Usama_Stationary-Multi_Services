const Joi = require('joi');

const saleItemInputSchema = Joi.object({
  product: Joi.string().hex().length(24).required(),
  quantity: Joi.number().min(0.01).required(),
});

const createSaleSchema = Joi.object({
  clientTxnId: Joi.string().min(8).max(100).required(),
  items: Joi.array().items(saleItemInputSchema).min(1).required(),
  paymentMethod: Joi.string().valid('cash', 'card').default('cash'),
  taxRate: Joi.number().min(0).max(100).default(0),
  branch: Joi.string().max(100).allow('', null),
  recordedOffline: Joi.boolean().default(false),
});

const syncPushSchema = Joi.object({
  sales: Joi.array().items(createSaleSchema).max(200).required(),
});

const listSalesQuerySchema = Joi.object({
  from: Joi.date(),
  to: Joi.date(),
  category: Joi.string(),
  page: Joi.number().integer().min(1).default(1),
  limit: Joi.number().integer().min(1).max(200).default(50),
});

module.exports = { createSaleSchema, syncPushSchema, listSalesQuerySchema };
