const Joi = require('joi');
const { PAYMENT_METHODS, ORDER_STATUSES } = require('../utils/constants');

const orderItemInputSchema = Joi.object({
  product: Joi.string().hex().length(24).required(),
  quantity: Joi.number().integer().min(1).required(),
});

const createOrderSchema = Joi.object({
  items: Joi.array().items(orderItemInputSchema).min(1).required(),
  paymentMethod: Joi.string().valid(...Object.values(PAYMENT_METHODS)).required(),
  delivery: Joi.object({
    isHomeDelivery: Joi.boolean().default(true),
    address: Joi.object({
      line1: Joi.string().max(200).required(),
      line2: Joi.string().max(200).allow('', null),
      city: Joi.string().max(100).required(),
      phone: Joi.string().max(20).required(),
    }).required(),
    window: Joi.string().max(100).allow('', null),
  }).required(),
});

const updateOrderStatusSchema = Joi.object({
  status: Joi.string().valid(...Object.values(ORDER_STATUSES)).required(),
  note: Joi.string().max(300).allow('', null),
});

const listOrdersQuerySchema = Joi.object({
  status: Joi.string().valid(...Object.values(ORDER_STATUSES)),
  paymentStatus: Joi.string(),
  page: Joi.number().integer().min(1).default(1),
  limit: Joi.number().integer().min(1).max(200).default(50),
});

module.exports = { createOrderSchema, updateOrderStatusSchema, listOrdersQuerySchema };
