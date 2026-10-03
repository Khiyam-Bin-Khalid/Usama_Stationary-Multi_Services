const { app, request, loginAs } = require('./helpers');
const { ROLES, PRODUCT_CATEGORIES } = require('../src/utils/constants');

async function createProduct(token, overrides = {}) {
  const res = await request(app)
    .post('/api/products')
    .set('Authorization', `Bearer ${token}`)
    .send({
      name: 'Notebook',
      sku: `SKU-${Date.now()}-${Math.random()}`,
      category: PRODUCT_CATEGORIES.STATIONERY,
      price: 100,
      currentStock: 10,
      reorderThreshold: 3,
      ...overrides,
    });
  return res.body.product;
}

// Backs the desktop/web "Daily Sale" tab: today's sold-out products, scoped
// per role, with enough detail (name/category/qty/price) to render an
// itemized list without extra product lookups.
describe('Daily Sale listing (GET /api/sales)', () => {
  test('a from/to range returns the sale with its line items intact', async () => {
    const { token: adminToken } = await loginAs(ROLES.ADMIN);
    const product = await createProduct(adminToken);
    const { token: staffToken } = await loginAs(ROLES.STAFF);

    await request(app)
      .post('/api/sales')
      .set('Authorization', `Bearer ${staffToken}`)
      .send({ clientTxnId: 'txn-daily-001', items: [{ product: product._id, quantity: 2 }], paymentMethod: 'cash' });

    const now = new Date();
    const startOfDay = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const res = await request(app)
      .get('/api/sales')
      .set('Authorization', `Bearer ${staffToken}`)
      .query({ from: startOfDay.toISOString(), to: now.toISOString() });

    expect(res.status).toBe(200);
    expect(res.body.sales).toHaveLength(1);
    expect(res.body.sales[0].items[0]).toMatchObject({ name: 'Notebook', category: PRODUCT_CATEGORIES.STATIONERY, quantity: 2, lineTotal: 200 });
  });

  test('staff only see their own sales; Admin sees everyone\'s', async () => {
    const { token: adminToken } = await loginAs(ROLES.ADMIN);
    const product = await createProduct(adminToken, { currentStock: 20 });
    const { token: staffAToken } = await loginAs(ROLES.STAFF);
    const { token: staffBToken } = await loginAs(ROLES.STAFF);

    await request(app)
      .post('/api/sales')
      .set('Authorization', `Bearer ${staffAToken}`)
      .send({ clientTxnId: 'txn-daily-a', items: [{ product: product._id, quantity: 1 }], paymentMethod: 'cash' });
    await request(app)
      .post('/api/sales')
      .set('Authorization', `Bearer ${staffBToken}`)
      .send({ clientTxnId: 'txn-daily-b', items: [{ product: product._id, quantity: 1 }], paymentMethod: 'cash' });

    const staffAView = await request(app).get('/api/sales').set('Authorization', `Bearer ${staffAToken}`);
    expect(staffAView.body.sales).toHaveLength(1);
    expect(staffAView.body.sales[0].clientTxnId).toBe('txn-daily-a');

    const adminView = await request(app).get('/api/sales').set('Authorization', `Bearer ${adminToken}`);
    expect(adminView.body.sales.map((s) => s.clientTxnId).sort()).toEqual(['txn-daily-a', 'txn-daily-b']);
    // Admin/Super Admin can verify which staff member made the sale.
    expect(adminView.body.sales[0].cashier).toHaveProperty('name');
  });
});
