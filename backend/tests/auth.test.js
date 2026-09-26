const { app, request, loginAs } = require('./helpers');
const { ROLES } = require('../src/utils/constants');

describe('Auth & RBAC', () => {
  test('customer can self-register and login', async () => {
    const registerRes = await request(app).post('/api/auth/register-customer').send({
      name: 'Jane Customer',
      email: 'jane@example.com',
      password: 'Password123',
    });
    expect(registerRes.status).toBe(201);
    expect(registerRes.body.user.role).toBe(ROLES.CUSTOMER);
    expect(registerRes.body.accessToken).toBeDefined();

    const loginRes = await request(app)
      .post('/api/auth/login')
      .send({ email: 'jane@example.com', password: 'Password123' });
    expect(loginRes.status).toBe(200);
    expect(loginRes.body.user.email).toBe('jane@example.com');
  });

  test('rejects wrong password', async () => {
    await request(app).post('/api/auth/register-customer').send({
      name: 'Jane Customer',
      email: 'jane2@example.com',
      password: 'Password123',
    });
    const res = await request(app)
      .post('/api/auth/login')
      .send({ email: 'jane2@example.com', password: 'wrong' });
    expect(res.status).toBe(401);
  });

  test('superadmin can create an admin account, admin cannot create another admin', async () => {
    const { token: superadminToken } = await loginAs(ROLES.SUPERADMIN);
    const { token: adminToken } = await loginAs(ROLES.ADMIN);

    const createAdmin = await request(app)
      .post('/api/auth/staff')
      .set('Authorization', `Bearer ${superadminToken}`)
      .send({ name: 'New Admin', email: 'newadmin@example.com', password: 'Password123', role: ROLES.ADMIN });
    expect(createAdmin.status).toBe(201);

    const adminTriesToCreateAdmin = await request(app)
      .post('/api/auth/staff')
      .set('Authorization', `Bearer ${adminToken}`)
      .send({ name: 'Another Admin', email: 'anotheradmin@example.com', password: 'Password123', role: ROLES.ADMIN });
    expect(adminTriesToCreateAdmin.status).toBe(403);
  });

  test('unauthenticated request to a protected route is rejected', async () => {
    const res = await request(app).get('/api/users');
    expect(res.status).toBe(401);
  });

  test('staff cannot access user management', async () => {
    const { token } = await loginAs(ROLES.STAFF);
    const res = await request(app).get('/api/users').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(403);
  });
});
