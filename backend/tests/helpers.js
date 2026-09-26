const request = require('supertest');
const app = require('../src/app');
const User = require('../src/models/User');
const { ROLES } = require('../src/utils/constants');

async function createUser({ role = ROLES.STAFF, email, password = 'Password123', name = 'Test User' } = {}) {
  const user = new User({ name, email: email || `${role}-${Date.now()}@example.com`, role });
  await user.setPassword(password);
  await user.save();
  return { user, password };
}

async function loginAs(role, overrides = {}) {
  const { user, password } = await createUser({ role, ...overrides });
  const res = await request(app).post('/api/auth/login').send({ email: user.email, password });
  return { user, token: res.body.accessToken };
}

module.exports = { createUser, loginAs, app, request };
