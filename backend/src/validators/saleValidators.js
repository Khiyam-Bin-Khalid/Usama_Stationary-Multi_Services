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

// A sale queued on a device also carries when it really happened and who rang
// it up: it may be pushed days later, by whoever logs in next.
const syncSaleSchema = createSaleSchema.keys({
  soldAt: Joi.date().iso(),
  cashierId: Joi.string().hex().length(24),
});

const syncPushSchema = Joi.object({
  sales: Joi.array().items(syncSaleSchema).max(200).required(),
});

const SYNC_OP_TYPES = ['product_create', 'product_update', 'product_delete', 'stock_adjust'];

const syncOpSchema = Joi.object({
  opId: Joi.string().min(8).max(100).required(),
  type: Joi.string().valid(...SYNC_OP_TYPES).required(),
  // Required for everything except product_create.
  productId: Joi.string().hex().length(24).when('type', {
    is: 'product_create',
    then: Joi.forbidden(),
    otherwise: Joi.required(),
  }),
  payload: Joi.object().default({}),
});

const listSalesQuerySchema = Joi.object({
  from: Joi.date(),
  to: Joi.date(),
  category: Joi.string(),
  shift: Joi.string().hex().length(24),
  page: Joi.number().integer().min(1).default(1),
  limit: Joi.number().integer().min(1).max(200).default(50),
});

module.exports = { createSaleSchema, syncPushSchema, syncOpSchema, listSalesQuerySchema };
