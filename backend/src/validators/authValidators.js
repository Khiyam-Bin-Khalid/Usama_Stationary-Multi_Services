const Joi = require('joi');

const registerCustomerSchema = Joi.object({
  name: Joi.string().min(2).max(100).required(),
  email: Joi.string().email().required(),
  password: Joi.string().min(6).max(128).required(),
  phone: Joi.string().max(20).allow('', null),
});

// `role` is the role picked on the desktop login screen (spec §1). It is a
// UX hint only: the server compares it with the account's real role and
// rejects a mismatch — it never grants anything.
const loginSchema = Joi.object({
  email: Joi.string().email().required(),
  password: Joi.string().required(),
  role: Joi.string().valid('superadmin', 'admin', 'staff', 'customer'),
});

const refreshSchema = Joi.object({
  refreshToken: Joi.string().required(),
});

const createStaffSchema = Joi.object({
  name: Joi.string().min(2).max(100).required(),
  email: Joi.string().email().required(),
  password: Joi.string().min(6).max(128).required(),
  role: Joi.string().valid('admin', 'staff').required(),
  phone: Joi.string().max(20).allow('', null),
  branch: Joi.string().max(100).allow('', null),
});

module.exports = { registerCustomerSchema, loginSchema, refreshSchema, createStaffSchema };
