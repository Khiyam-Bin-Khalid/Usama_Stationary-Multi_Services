const Joi = require('joi');
const { ROLES } = require('../utils/constants');

const updateUserSchema = Joi.object({
  name: Joi.string().min(2).max(100),
  phone: Joi.string().max(20).allow('', null),
  branch: Joi.string().max(100).allow('', null),
  isActive: Joi.boolean(),
}).min(1);

// Spec §8 PATCH /users/:id/role — superadmin only; nobody is promoted to
// superadmin through the API (single owner account, see superadminGuard).
const changeRoleSchema = Joi.object({
  role: Joi.string().valid(ROLES.ADMIN, ROLES.STAFF).required(),
});

const listUsersQuerySchema = Joi.object({
  role: Joi.string().valid(...Object.values(ROLES)),
  isActive: Joi.boolean(),
  q: Joi.string().max(100),
});

module.exports = { updateUserSchema, changeRoleSchema, listUsersQuerySchema };
