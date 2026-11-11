const { app, request, loginAs, createUser } = require('./helpers');
const { ROLES, PRODUCT_CATEGORIES } = require('../src/utils/constants');
const Sale = require('../src/models/Sale');
const Shift = require('../src/models/Shift');
const Product = require('../src/models/Product');
const InventoryLog = require('../src/models/InventoryLog');

const auth = (token) => ({ Authorization: `Bearer ${token}` });
let seq = 0;
const nextId = (prefix) => { seq += 1; return `${prefix}-${Date.now()}-${seq}`; };

async function newProduct(token, overrides = {}) {
  const res = await request(app).post('/api/products').set(auth(token))
    .send({ name: 'Pen', category: PRODUCT_CATEGORIES.STATIONERY, price: 10, currentStock: 10, ...overrides });
  expect(res.status).toBe(201);
  return res.body.product;
}

const push = (token, sales) => request(app).post('/api/sync/push').set(auth(token)).send({ sales });
const op = (token, body) => request(app).post('/api/sync/ops').set(auth(token)).send(body);

describe('POST /sync/push', () => {
  test('keeps the real sale time and echoes the confirmed sale', async () => {
    const { token } = await loginAs(ROLES.ADMIN);
    const product = await newProduct(token);
    const soldAt = new Date(Date.now() - 3 * 24 * 60 * 60 * 1000).toISOString();

    const res = await push(token, [{ clientTxnId: nextId('pos'), items: [{ product: product._id, quantity: 2 }], paymentMethod: 'cash', soldAt }]);

    expect(res.status).toBe(200);
    expect(res.body.results[0]).toMatchObject({ status: 'ok', alreadyExisted: false });
    expect(res.body.results[0].sale.createdAt).toBe(soldAt);
    expect(res.body.results[0].sale.invoiceNumber).toMatch(/^INV/);
    expect(res.body.results[0].sale.recordedOffline).toBe(true);
    expect((await Product.findById(product._id)).currentStock).toBe(8);
  });

  test('a device clock in the future cannot date a sale ahead of now', async () => {
    const { token } = await loginAs(ROLES.ADMIN);
    const product = await newProduct(token);
    const soldAt = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();
    const res = await push(token, [{ clientTxnId: nextId('pos'), items: [{ product: product._id, quantity: 1 }], soldAt }]);
    expect(new Date(res.body.results[0].sale.createdAt).getTime()).toBeLessThanOrEqual(Date.now());
  });

  test('a retried push is not counted twice', async () => {
    const { token } = await loginAs(ROLES.ADMIN);
    const product = await newProduct(token);
    const sale = { clientTxnId: nextId('pos'), items: [{ product: product._id, quantity: 1 }] };

    await push(token, [sale]);
    const retry = await push(token, [sale]);

    expect(retry.body.results[0].alreadyExisted).toBe(true);
    expect(await Sale.countDocuments({ clientTxnId: sale.clientTxnId })).toBe(1);
    expect((await Product.findById(product._id)).currentStock).toBe(9);
  });

  test('admin pushing the queue credits the sale to the staff member who made it', async () => {
    const { token } = await loginAs(ROLES.ADMIN);
    const { user: cashier } = await createUser({ role: ROLES.STAFF, email: 'cashier-a@example.com' });
    const product = await newProduct(token);

    const res = await push(token, [{ clientTxnId: nextId('pos'), items: [{ product: product._id, quantity: 1 }], cashierId: cashier._id.toString() }]);

    expect(res.body.results[0].status).toBe('ok');
    expect(res.body.results[0].sale.cashier._id).toBe(cashier._id.toString());
  });

  test('staff cannot credit a sale to somebody else', async () => {
    const { token: adminToken, user: admin } = await loginAs(ROLES.ADMIN);
    const { token } = await loginAs(ROLES.STAFF);
    const product = await newProduct(adminToken);

    const res = await push(token, [{ clientTxnId: nextId('pos'), items: [{ product: product._id, quantity: 1 }], cashierId: admin._id.toString() }]);

    expect(res.body.results[0]).toMatchObject({ status: 'error', error: 'Staff may only sync their own sales' });
    expect((await Product.findById(product._id)).currentStock).toBe(10);
  });

  test('a sale from before the open shift stays out of that shift', async () => {
    const { token, user } = await loginAs(ROLES.ADMIN);
    const product = await newProduct(token);
    const shift = await Shift.create({ staff: user._id, openingCash: 0, openedAt: new Date(Date.now() - 60 * 60 * 1000) });

    const [before, during] = (await push(token, [
      { clientTxnId: nextId('pos'), items: [{ product: product._id, quantity: 1 }], soldAt: new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString() },
      { clientTxnId: nextId('pos'), items: [{ product: product._id, quantity: 1 }], soldAt: new Date(Date.now() - 60 * 1000).toISOString() },
    ])).body.results;

    expect(before.sale.shift).toBeUndefined();
    expect(during.sale.shift).toBe(shift._id.toString());
  });

  test('one rejected sale does not block the rest of the batch', async () => {
    const { token } = await loginAs(ROLES.ADMIN);
    const scarce = await newProduct(token, { currentStock: 1 });
    const plenty = await newProduct(token);

    const res = await push(token, [
      { clientTxnId: nextId('pos'), items: [{ product: scarce._id, quantity: 5 }] },
      { clientTxnId: nextId('pos'), items: [{ product: plenty._id, quantity: 1 }] },
    ]);

    expect(res.body.results.map((r) => r.status)).toEqual(['error', 'ok']);
    expect(res.body.results[0].error).toContain('Insufficient stock');
  });
});

describe('POST /sync/ops', () => {
  test('a product created offline is not duplicated by a retry', async () => {
    const { token } = await loginAs(ROLES.ADMIN);
    const body = { opId: nextId('op'), type: 'product_create', payload: { name: 'Offline Ruler', category: PRODUCT_CATEGORIES.STATIONERY, price: 25, currentStock: 7 } };

    const first = await op(token, body);
    const retry = await op(token, body);

    expect(first.status).toBe(200);
    expect(first.body.alreadyApplied).toBe(false);
    expect(first.body.product.sku).toBe('STN-00001');
    expect(retry.body.alreadyApplied).toBe(true);
    expect(retry.body.product._id).toBe(first.body.product._id);
    expect(await Product.countDocuments({ name: 'Offline Ruler' })).toBe(1);
    expect(await InventoryLog.countDocuments({ product: first.body.product._id })).toBe(1);
  });

  test('stock adjustments apply exactly once and are logged', async () => {
    const { token } = await loginAs(ROLES.ADMIN);
    const product = await newProduct(token);
    const body = { opId: nextId('op'), type: 'stock_adjust', productId: product._id, payload: { delta: 5, reason: 'Delivery' } };

    await op(token, body);
    await op(token, body);

    expect((await Product.findById(product._id)).currentStock).toBe(15);
  });

  test('update and delete use the same rules as the REST routes', async () => {
    const { token } = await loginAs(ROLES.ADMIN);
    const product = await newProduct(token);

    const updated = await op(token, { opId: nextId('op'), type: 'product_update', productId: product._id, payload: { price: 12 } });
    expect(updated.body.product.price).toBe(12);

    const deleted = await op(token, { opId: nextId('op'), type: 'product_delete', productId: product._id });
    expect(deleted.body.product.isActive).toBe(false);
  });

  test('a failed op can be retried with the same opId after the problem is fixed', async () => {
    const { token } = await loginAs(ROLES.ADMIN);
    const product = await newProduct(token, { currentStock: 1 });
    const body = { opId: nextId('op'), type: 'stock_adjust', productId: product._id, payload: { delta: -5, reason: 'Damaged' } };

    expect((await op(token, body)).status).toBe(400);
    await request(app).post(`/api/products/${product._id}/adjust-stock`).set(auth(token)).send({ delta: 10, reason: 'Delivery' });

    const retry = await op(token, body);
    expect(retry.status).toBe(200);
    expect(retry.body.product.currentStock).toBe(6);
  });

  test('payloads are validated like the REST routes', async () => {
    const { token } = await loginAs(ROLES.ADMIN);
    const res = await op(token, { opId: nextId('op'), type: 'product_create', payload: { name: '', category: PRODUCT_CATEGORIES.STATIONERY, price: 1 } });
    expect(res.status).toBe(400);
    expect(res.body.details).toEqual(expect.arrayContaining([expect.stringContaining('name')]));
  });

  test('staff cannot change products through sync', async () => {
    const { token } = await loginAs(ROLES.STAFF);
    const res = await op(token, { opId: nextId('op'), type: 'product_create', payload: { name: 'Nope', category: PRODUCT_CATEGORIES.STATIONERY, price: 1 } });
    expect(res.status).toBe(403);
  });
});
