const { app, request, loginAs, createUser } = require('./helpers');
const AuditLog = require('../src/models/AuditLog');
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

  test('only superadmin can create admin/staff accounts (spec §2)', async () => {
    const { token: superadminToken } = await loginAs(ROLES.SUPERADMIN);
    const { token: adminToken } = await loginAs(ROLES.ADMIN);

    const createAdmin = await request(app)
      .post('/api/auth/register-admin')
      .set('Authorization', `Bearer ${superadminToken}`)
      .send({ name: 'New Admin', email: 'newadmin@example.com', password: 'Password123', role: ROLES.ADMIN });
    expect(createAdmin.status).toBe(201);

    const createStaff = await request(app)
      .post('/api/auth/register-staff')
      .set('Authorization', `Bearer ${superadminToken}`)
      .send({ name: 'New Staff', email: 'newstaff@example.com', password: 'Password123', role: ROLES.STAFF });
    expect(createStaff.status).toBe(201);

    const adminTriesToCreateStaff = await request(app)
      .post('/api/auth/staff')
      .set('Authorization', `Bearer ${adminToken}`)
      .send({ name: 'Another Staff', email: 'anotherstaff@example.com', password: 'Password123', role: ROLES.STAFF });
    expect(adminTriesToCreateStaff.status).toBe(403);
  });

  test('login role selector is validated server-side (spec §1)', async () => {
    const { user, password } = await createUser({ role: ROLES.STAFF });

    const wrongTile = await request(app)
      .post('/api/auth/login')
      .send({ email: user.email, password, role: ROLES.ADMIN });
    expect(wrongTile.status).toBe(403);
    expect(wrongTile.body.error).toMatch(/registered as staff/i);

    const rightTile = await request(app)
      .post('/api/auth/login')
      .send({ email: user.email, password, role: ROLES.STAFF });
    expect(rightTile.status).toBe(200);

    const audit = await AuditLog.findOne({ action: 'auth.login_failed' });
    expect(audit).not.toBeNull();
    expect(audit.details.reason).toBe('role_mismatch:staff');
  });

  test('unauthenticated request to a protected route is rejected', async () => {
    const res = await request(app).get('/api/users');
    expect(res.status).toBe(401);
  });

  test('staff and admin cannot access user management', async () => {
    const { token } = await loginAs(ROLES.STAFF);
    const res = await request(app).get('/api/users').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(403);

    const { token: adminToken } = await loginAs(ROLES.ADMIN);
    const adminRes = await request(app).get('/api/users').set('Authorization', `Bearer ${adminToken}`);
    expect(adminRes.status).toBe(403);
  });
});
