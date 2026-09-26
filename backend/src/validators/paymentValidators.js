const Joi = require('joi');

const reviewPaymentSchema = Joi.object({
  approve: Joi.boolean().required(),
  note: Joi.string().max(300).allow('', null),
});

module.exports = { reviewPaymentSchema };
