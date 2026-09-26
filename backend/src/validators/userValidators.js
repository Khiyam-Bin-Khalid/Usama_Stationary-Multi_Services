const Joi = require('joi');
const { ROLES } = require('../utils/constants');

const updateUserSchema = Joi.object({
  name: Joi.string().min(2).max(100),
  phone: Joi.string().max(20).allow('', null),
  branch: Joi.string().max(100).allow('', null),
  role: Joi.string().valid(ROLES.ADMIN, ROLES.STAFF),
  isActive: Joi.boolean(),
}).min(1);

const listUsersQuerySchema = Joi.object({
  role: Joi.string().valid(...Object.values(ROLES)),
  isActive: Joi.boolean(),
  q: Joi.string().max(100),
});

module.exports = { updateUserSchema, listUsersQuerySchema };
