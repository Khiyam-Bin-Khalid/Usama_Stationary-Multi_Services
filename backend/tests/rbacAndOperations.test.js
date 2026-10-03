const { app, request, loginAs, createUser } = require('./helpers');
const Product = require('../src/models/Product');
const Notification = require('../src/models/Notification');
const AuditLog = require('../src/models/AuditLog');
const { ROLES, PRODUCT_CATEGORIES } = require('../src/utils/constants');

// Notifications are delivered off the request path (setImmediate); give the
// event loop a moment before asserting on them.
const settle = () => new Promise((resolve) => setTimeout(resolve, 60));

async function createProduct(token, overrides = {}) {
  const res = await request(app)
    .post('/api/products')
    .set('Authorization', `Bearer ${token}`)
    .send({
      name: 'Marker',
      sku: `SKU-${Date.now()}-${Math.random()}`,
      category: PRODUCT_CATEGORIES.STATIONERY,
      price: 80,
      currentStock: 10,
      reorderThreshold: 5,
      ...overrides,
    });
  expect(res.status).toBe(201);
  return res.body.product;
}

describe('Role permission matrix (spec §2)', () => {
  test('staff cannot add, edit, delete products or adjust stock', async () => {
    const { token: adminToken } = await loginAs(ROLES.ADMIN);
    const product = await createProduct(adminToken);
    const { token } = await loginAs(ROLES.STAFF);
    const auth = (r) => r.set('Authorization', `Bearer ${token}`);

    expect((await auth(request(app).post('/api/products')).send({ name: 'x', sku: 'X', category: 'stationery', price: 1 })).status).toBe(403);
    expect((await auth(request(app).patch(`/api/products/${product._id}`)).send({ price: 5 })).status).toBe(403);
    expect((await auth(request(app).delete(`/api/products/${product._id}`))).status).toBe(403);
    expect((await auth(request(app).post(`/api/products/${product._id}/adjust-stock`)).send({ delta: 1, reason: 'x' })).status).toBe(403);

    // ...but can read inventory
    const list = await auth(request(app).get('/api/products'));
    expect(list.status).toBe(200);
    expect(list.body.products).toHaveLength(1);
  });

  test('superadmin can change roles and delete accounts; deleted account cannot log in', async () => {
    const { token: superToken, user: superUser } = await loginAs(ROLES.SUPERADMIN);
    const { user: staffUser, password } = await createUser({ role: ROLES.STAFF });

    const promote = await request(app)
      .patch(`/api/users/${staffUser._id}/role`)
      .set('Authorization', `Bearer ${superToken}`)
      .send({ role: ROLES.ADMIN });
    expect(promote.status).toBe(200);
    expect(promote.body.user.role).toBe(ROLES.ADMIN);

    const selfDelete = await request(app).delete(`/api/users/${superUser._id}`).set('Authorization', `Bearer ${superToken}`);
    expect(selfDelete.status).toBe(403); // owner account is protected

    const del = await request(app).delete(`/api/users/${staffUser._id}`).set('Authorization', `Bearer ${superToken}`);
    expect(del.status).toBe(200);

    const login = await request(app).post('/api/auth/login').send({ email: staffUser.email, password });
    expect(login.status).toBe(401);

    const list = await request(app).get('/api/users').set('Authorization', `Bearer ${superToken}`);
    expect(list.body.users.find((u) => u._id === staffUser._id.toString())).toBeUndefined();

    const audit = await AuditLog.find({ action: { $in: ['user.role_change', 'user.delete'] } });
    expect(audit).toHaveLength(2);
    expect(audit.find((a) => a.action === 'user.role_change').before.role).toBe(ROLES.STAFF);
  });

  test('audit log is superadmin only', async () => {
    const { token: adminToken } = await loginAs(ROLES.ADMIN);
    expect((await request(app).get('/api/audit-logs').set('Authorization', `Bearer ${adminToken}`)).status).toBe(403);

    const { token: superToken } = await loginAs(ROLES.SUPERADMIN);
    const res = await request(app).get('/api/audit-logs').set('Authorization', `Bearer ${superToken}`);
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body.logs)).toBe(true);
  });

  test('product delete is a soft delete — record survives for reports', async () => {
    const { token } = await loginAs(ROLES.ADMIN);
    const product = await createProduct(token);
    const del = await request(app).delete(`/api/products/${product._id}`).set('Authorization', `Bearer ${token}`);
    expect(del.status).toBe(200);
    const stored = await Product.findById(product._id);
    expect(stored).not.toBeNull();
    expect(stored.isActive).toBe(false);
  });

  test('product creation falls back to the category default threshold and unit', async () => {
    const { token } = await loginAs(ROLES.ADMIN);
    const product = await createProduct(token, { reorderThreshold: undefined, unit: undefined, category: PRODUCT_CATEGORIES.GROCERY });
    expect(product.reorderThreshold).toBe(5);
    expect(product.unit).toBe('kg');

    const bad = await request(app)
      .post('/api/products')
      .set('Authorization', `Bearer ${token}`)
      .send({ name: 'x', sku: 'BAD-CAT', category: 'toys', price: 1 });
    expect(bad.status).toBe(400);
  });
});

describe('Inventory events + notifications (spec §4.1, §5)', () => {
  test('crossing the threshold creates a LOW_STOCK notification + audit entry', async () => {
    const { token: adminToken } = await loginAs(ROLES.ADMIN);
    const product = await createProduct(adminToken, { currentStock: 7, reorderThreshold: 5 });
    const { token } = await loginAs(ROLES.STAFF);

    await request(app)
      .post('/api/sales')
      .set('Authorization', `Bearer ${token}`)
      .send({ clientTxnId: 'txn-low-1', items: [{ product: product._id, quantity: 3 }], paymentMethod: 'cash' });
    await settle();

    const notif = await Notification.findOne({ type: 'low_stock' });
    expect(notif).not.toBeNull();
    expect(notif.recipientRoles).toEqual(expect.arrayContaining([ROLES.ADMIN, ROLES.SUPERADMIN]));
    expect(notif.payload.currentStock).toBe(4);
    expect(await AuditLog.countDocuments({ action: 'inventory.low_stock' })).toBe(1);

    // A second sale still under the threshold must not spam another alert.
    await request(app)
      .post('/api/sales')
      .set('Authorization', `Bearer ${token}`)
      .send({ clientTxnId: 'txn-low-2', items: [{ product: product._id, quantity: 1 }], paymentMethod: 'cash' });
    await settle();
    expect(await Notification.countDocuments({ type: 'low_stock' })).toBe(1);

    // Admin sees it in their feed with unread count; staff does not.
    const feed = await request(app).get('/api/notifications').set('Authorization', `Bearer ${adminToken}`);
    expect(feed.body.notifications).toHaveLength(1);
    expect(feed.body.notifications[0].isRead).toBe(false);
    const unread = await request(app).get('/api/notifications/unread-count').set('Authorization', `Bearer ${adminToken}`);
    expect(unread.body.unread).toBe(1);
    const staffFeed = await request(app).get('/api/notifications').set('Authorization', `Bearer ${token}`);
    expect(staffFeed.body.notifications).toHaveLength(0);

    await request(app).patch(`/api/notifications/${notif._id}/read`).set('Authorization', `Bearer ${adminToken}`);
    const after = await request(app).get('/api/notifications/unread-count').set('Authorization', `Bearer ${adminToken}`);
    expect(after.body.unread).toBe(0);
  });

  test('reaching 0 marks out-of-stock, hides from sellable lists, keeps the record', async () => {
    const { token: adminToken } = await loginAs(ROLES.ADMIN);
    const product = await createProduct(adminToken, { currentStock: 2, reorderThreshold: 5 });
    const { token } = await loginAs(ROLES.STAFF);

    await request(app)
      .post('/api/sales')
      .set('Authorization', `Bearer ${token}`)
      .send({ clientTxnId: 'txn-oos-1', items: [{ product: product._id, quantity: 2 }], paymentMethod: 'cash' });
    await settle();

    expect(await Notification.countDocuments({ type: 'out_of_stock' })).toBe(1);
    expect(await AuditLog.countDocuments({ action: 'inventory.out_of_stock' })).toBe(1);

    const storefront = await request(app).get('/api/products'); // anonymous → sellable only
    expect(storefront.body.products).toHaveLength(0);

    const posList = await request(app).get('/api/products?sellableOnly=true').set('Authorization', `Bearer ${token}`);
    expect(posList.body.products).toHaveLength(0);

    const inventory = await request(app).get('/api/products').set('Authorization', `Bearer ${adminToken}`);
    expect(inventory.body.products).toHaveLength(1);
    expect(inventory.body.products[0].isOutOfStock).toBe(true);
    expect(inventory.body.products[0].isActive).toBe(true);
  });

  test('stock is decremented within its own category only', async () => {
    const { token: adminToken } = await loginAs(ROLES.ADMIN);
    const product = await createProduct(adminToken, { category: PRODUCT_CATEGORIES.SPORTS });
    const { applyStockChange } = require('../src/services/inventoryService');
    await expect(
      applyStockChange({ productId: product._id, category: PRODUCT_CATEGORIES.GROCERY, delta: -1, type: 'sale', actor: adminToken })
    ).rejects.toThrow(/belongs to category/);
  });

  test('customer registration and online order notify the store', async () => {
    const { token: adminToken } = await loginAs(ROLES.ADMIN);
    const product = await createProduct(adminToken, { isAvailableOnline: true });

    const reg = await request(app)
      .post('/api/auth/register-customer')
      .send({ name: 'Ali Customer', email: 'ali@example.com', password: 'Password123' });
    expect(reg.status).toBe(201);

    await request(app)
      .post('/api/orders')
      .set('Authorization', `Bearer ${reg.body.accessToken}`)
      .send({
        items: [{ product: product._id, quantity: 1 }],
        paymentMethod: 'cash_on_delivery',
        delivery: { address: { line1: '1 St', city: 'Lahore', phone: '0300' } },
      });
    await settle();

    expect(await Notification.countDocuments({ type: 'customer_registered' })).toBe(1);
    const orderNotif = await Notification.findOne({ type: 'order_placed' });
    expect(orderNotif).not.toBeNull();
    expect(orderNotif.recipientRoles).toEqual(expect.arrayContaining([ROLES.ADMIN, ROLES.STAFF]));
  });
});

describe('Staff discrepancy reports (spec §3.3)', () => {
  test('staff report → admin notified → admin resolves by applying the shelf count', async () => {
    const { token: adminToken } = await loginAs(ROLES.ADMIN);
    const product = await createProduct(adminToken, { currentStock: 10 });
    const { token } = await loginAs(ROLES.STAFF);

    const report = await request(app)
      .post('/api/inventory/discrepancies')
      .set('Authorization', `Bearer ${token}`)
      .send({ product: product._id, countedQty: 8, note: 'Two missing from shelf' });
    expect(report.status).toBe(201);
    expect(report.body.report.difference).toBe(-2);
    expect((await Product.findById(product._id)).currentStock).toBe(10); // untouched
    await settle();
    expect(await Notification.countDocuments({ type: 'inventory_discrepancy' })).toBe(1);

    const staffResolve = await request(app)
      .patch(`/api/inventory/discrepancies/${report.body.report._id}/resolve`)
      .set('Authorization', `Bearer ${token}`)
      .send({ applyAdjustment: true });
    expect(staffResolve.status).toBe(403);

    const resolve = await request(app)
      .patch(`/api/inventory/discrepancies/${report.body.report._id}/resolve`)
      .set('Authorization', `Bearer ${adminToken}`)
      .send({ applyAdjustment: true, resolution: 'Recounted, shelf is right' });
    expect(resolve.status).toBe(200);
    expect(resolve.body.report.status).toBe('resolved');
    expect(resolve.body.report.adjustmentApplied).toBe(-2);
    expect((await Product.findById(product._id)).currentStock).toBe(8);
  });
});

describe('Shifts + staff-scoped reporting (spec §3.3, §6)', () => {
  test('sales attach to the open shift; closing reconciles cash; staff see own figures only', async () => {
    const { token: adminToken } = await loginAs(ROLES.ADMIN);
    const product = await createProduct(adminToken, { currentStock: 100, price: 50 });
    const { token: staffA } = await loginAs(ROLES.STAFF);
    const { token: staffB } = await loginAs(ROLES.STAFF);

    const open = await request(app).post('/api/shifts/open').set('Authorization', `Bearer ${staffA}`).send({ openingCash: 1000 });
    expect(open.status).toBe(201);
    const again = await request(app).post('/api/shifts/open').set('Authorization', `Bearer ${staffA}`).send({ openingCash: 5 });
    expect(again.status).toBe(409);

    await request(app).post('/api/sales').set('Authorization', `Bearer ${staffA}`)
      .send({ clientTxnId: 'shift-a-1', items: [{ product: product._id, quantity: 2 }], paymentMethod: 'cash' });
    await request(app).post('/api/sales').set('Authorization', `Bearer ${staffA}`)
      .send({ clientTxnId: 'shift-a-2', items: [{ product: product._id, quantity: 1 }], paymentMethod: 'card' });
    await request(app).post('/api/sales').set('Authorization', `Bearer ${staffB}`)
      .send({ clientTxnId: 'shift-b-1', items: [{ product: product._id, quantity: 4 }], paymentMethod: 'cash' });

    const current = await request(app).get('/api/shifts/current').set('Authorization', `Bearer ${staffA}`);
    expect(current.body.salesCount).toBe(2);
    expect(current.body.cashSalesTotal).toBe(100);
    expect(current.body.closingCashExpected).toBe(1100);

    // Staff A's daily report only contains their own two sales (150), not B's 200.
    const mine = await request(app).get('/api/reports/sales?period=daily').set('Authorization', `Bearer ${staffA}`);
    expect(mine.body.summary.totalRevenue).toBe(150);
    const all = await request(app).get('/api/reports/sales?period=daily&source=pos').set('Authorization', `Bearer ${adminToken}`);
    expect(all.body.summary.totalRevenue).toBe(350);

    const mySales = await request(app).get('/api/sales').set('Authorization', `Bearer ${staffA}`);
    expect(mySales.body.sales).toHaveLength(2);

    const close = await request(app).post('/api/shifts/close').set('Authorization', `Bearer ${staffA}`).send({ closingCashActual: 1090 });
    expect(close.status).toBe(200);
    expect(close.body.shift.closingCashExpected).toBe(1100);
    expect(close.body.shift.cashVariance).toBe(-10);
    expect(close.body.shift.status).toBe('closed');

    const dash = await request(app).get('/api/reports/dashboard').set('Authorization', `Bearer ${staffA}`);
    expect(dash.body.role).toBe(ROLES.STAFF);
    expect(dash.body.mySalesToday.salesCount).toBe(2);
    expect(dash.body.shift).toBeNull();
    expect(dash.body.today).toBeUndefined(); // no store-wide totals for staff

    const superDash = await request(app).get('/api/reports/dashboard').set('Authorization', `Bearer ${(await loginAs(ROLES.SUPERADMIN)).token}`);
    expect(superDash.body.today.posSalesCount).toBe(3);
    expect(superDash.body.accounts.staff).toBe(2);
    expect(Array.isArray(superDash.body.recentAudit)).toBe(true);
  });
});
