const { app, request, loginAs } = require('./helpers');
const Product = require('../src/models/Product');
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

describe('Inventory + POS sale', () => {
  test('creating a product with initial stock logs an inventory entry', async () => {
    const { token } = await loginAs(ROLES.ADMIN);
    const product = await createProduct(token);
    expect(product.currentStock).toBe(10);

    const logRes = await request(app)
      .get(`/api/products/${product._id}/inventory-log`)
      .set('Authorization', `Bearer ${token}`);
    expect(logRes.body.logs).toHaveLength(1);
    expect(logRes.body.logs[0].quantityDelta).toBe(10);
  });

  test('recording a sale decrements stock via InventoryLog, not a direct overwrite', async () => {
    const { token: adminToken } = await loginAs(ROLES.ADMIN);
    const product = await createProduct(adminToken);
    const { token } = await loginAs(ROLES.STAFF);

    const saleRes = await request(app)
      .post('/api/sales')
      .set('Authorization', `Bearer ${token}`)
      .send({
        clientTxnId: 'txn-counter-001',
        items: [{ product: product._id, quantity: 3 }],
        paymentMethod: 'cash',
      });

    expect(saleRes.status).toBe(201);
    expect(saleRes.body.sale.total).toBe(300);

    const updated = await Product.findById(product._id);
    expect(updated.currentStock).toBe(7);
  });

  test('re-pushing the same clientTxnId does not double-decrement stock (offline sync idempotency)', async () => {
    const { token: adminToken } = await loginAs(ROLES.ADMIN);
    const product = await createProduct(adminToken, { currentStock: 5 });
    const { token } = await loginAs(ROLES.STAFF);

    const payload = {
      clientTxnId: 'txn-offline-42',
      items: [{ product: product._id, quantity: 2 }],
      paymentMethod: 'cash',
      recordedOffline: true,
    };

    const first = await request(app).post('/api/sales').set('Authorization', `Bearer ${token}`).send(payload);
    expect(first.status).toBe(201);

    const second = await request(app).post('/api/sales').set('Authorization', `Bearer ${token}`).send(payload);
    expect(second.status).toBe(200);
    expect(second.body.alreadyExisted).toBe(true);

    const updated = await Product.findById(product._id);
    expect(updated.currentStock).toBe(3); // decremented once, not twice
  });

  test('sync push endpoint processes a batch of offline sales idempotently', async () => {
    const { token: adminToken } = await loginAs(ROLES.ADMIN);
    const product = await createProduct(adminToken, { currentStock: 20 });
    const { token } = await loginAs(ROLES.STAFF);

    const sales = [
      { clientTxnId: 'sync-offline-1', items: [{ product: product._id, quantity: 1 }], paymentMethod: 'cash' },
      { clientTxnId: 'sync-offline-2', items: [{ product: product._id, quantity: 2 }], paymentMethod: 'cash' },
    ];

    const pushRes = await request(app)
      .post('/api/sync/push')
      .set('Authorization', `Bearer ${token}`)
      .send({ sales });
    expect(pushRes.status).toBe(200);
    expect(pushRes.body.results.every((r) => r.status === 'ok')).toBe(true);

    const retryRes = await request(app)
      .post('/api/sync/push')
      .set('Authorization', `Bearer ${token}`)
      .send({ sales });
    expect(retryRes.body.results.every((r) => r.alreadyExisted)).toBe(true);

    const updated = await Product.findById(product._id);
    expect(updated.currentStock).toBe(17); // 20 - 1 - 2, only counted once
  });

  test('insufficient stock is rejected', async () => {
    const { token: adminToken } = await loginAs(ROLES.ADMIN);
    const product = await createProduct(adminToken, { currentStock: 1 });
    const { token } = await loginAs(ROLES.STAFF);

    const res = await request(app)
      .post('/api/sales')
      .set('Authorization', `Bearer ${token}`)
      .send({ clientTxnId: 'txn-fail', items: [{ product: product._id, quantity: 5 }], paymentMethod: 'cash' });

    expect(res.status).toBe(400);
  });
});
