const { app, request, loginAs } = require('./helpers');
const { ROLES, PRODUCT_CATEGORIES, PAYMENT_METHODS } = require('../src/utils/constants');

async function createOnlineProduct(token) {
  const res = await request(app)
    .post('/api/products')
    .set('Authorization', `Bearer ${token}`)
    .send({
      name: 'Notebook',
      sku: `SKU-ORD-${Date.now()}-${Math.random()}`,
      category: PRODUCT_CATEGORIES.STATIONERY,
      price: 200,
      currentStock: 10,
      reorderThreshold: 2,
      isAvailableOnline: true,
    });
  return res.body.product;
}

describe('Online orders + manual receipt payment review', () => {
  test('customer can place a cash-on-delivery order and track it', async () => {
    const { token: adminToken } = await loginAs(ROLES.ADMIN);
    const product = await createOnlineProduct(adminToken);
    const { token: customerToken } = await loginAs(ROLES.CUSTOMER);

    const orderRes = await request(app)
      .post('/api/orders')
      .set('Authorization', `Bearer ${customerToken}`)
      .send({
        items: [{ product: product._id, quantity: 2 }],
        paymentMethod: PAYMENT_METHODS.CASH_ON_DELIVERY,
        delivery: { address: { line1: '123 Main St', city: 'Lahore', phone: '03001234567' }, window: 'evening' },
      });

    expect(orderRes.status).toBe(201);
    expect(orderRes.body.order.total).toBe(400);
    expect(orderRes.body.order.status).toBe('pending');

    const myOrders = await request(app).get('/api/orders/mine').set('Authorization', `Bearer ${customerToken}`);
    expect(myOrders.body.orders).toHaveLength(1);
  });

  test('Stripe checkout is rejected with a clear message when no keys are configured', async () => {
    const { token: adminToken } = await loginAs(ROLES.ADMIN);
    const product = await createOnlineProduct(adminToken);
    const { token: customerToken } = await loginAs(ROLES.CUSTOMER);

    const orderRes = await request(app)
      .post('/api/orders')
      .set('Authorization', `Bearer ${customerToken}`)
      .send({
        items: [{ product: product._id, quantity: 1 }],
        paymentMethod: PAYMENT_METHODS.STRIPE,
        delivery: { address: { line1: '123 Main St', city: 'Lahore', phone: '03001234567' } },
      });

    expect(orderRes.status).toBe(503);
    expect(orderRes.body.error).toMatch(/Stripe is not configured/i);
  });

  test('manual receipt-upload order goes through admin approval flow', async () => {
    const { token: adminToken } = await loginAs(ROLES.ADMIN);
    const product = await createOnlineProduct(adminToken);
    const { token: customerToken } = await loginAs(ROLES.CUSTOMER);

    const orderRes = await request(app)
      .post('/api/orders')
      .set('Authorization', `Bearer ${customerToken}`)
      .send({
        items: [{ product: product._id, quantity: 1 }],
        paymentMethod: PAYMENT_METHODS.MANUAL_RECEIPT,
        delivery: { address: { line1: '456 Side St', city: 'Lahore', phone: '03007654321' } },
      });
    expect(orderRes.status).toBe(201);
    const orderId = orderRes.body.order._id;

    const uploadRes = await request(app)
      .post(`/api/payments/orders/${orderId}/receipt`)
      .set('Authorization', `Bearer ${customerToken}`)
      .attach('receipt', Buffer.from('fake-image-bytes'), { filename: 'receipt.png', contentType: 'image/png' });
    expect(uploadRes.status).toBe(200);
    expect(uploadRes.body.payment.status).toBe('pending_review');

    const pendingRes = await request(app)
      .get('/api/payments/pending-review')
      .set('Authorization', `Bearer ${adminToken}`);
    expect(pendingRes.body.payments).toHaveLength(1);
    const paymentId = pendingRes.body.payments[0]._id;

    const approveRes = await request(app)
      .post(`/api/payments/${paymentId}/review`)
      .set('Authorization', `Bearer ${adminToken}`)
      .send({ approve: true, note: 'Looks good' });
    expect(approveRes.status).toBe(200);
    expect(approveRes.body.payment.status).toBe('approved');

    const orderCheck = await request(app)
      .get(`/api/orders/mine/${orderId}`)
      .set('Authorization', `Bearer ${customerToken}`);
    expect(orderCheck.body.order.paymentStatus).toBe('approved');
    expect(orderCheck.body.order.status).toBe('confirmed');
    expect(orderCheck.body.order.statusHistory.map((h) => h.status)).toEqual([
      'pending',
      'payment_submitted',
      'payment_under_review',
      'payment_approved',
      'confirmed',
    ]);
    // The customer can see the uploaded receipt and its review outcome.
    expect(orderCheck.body.order.payment.receiptImageUrl).toMatch(/^\/uploads\//);
    expect(orderCheck.body.order.payment.status).toBe('approved');
  });

  test('receipt upload never auto-approves and fulfilment is blocked until the admin approves', async () => {
    const { token: adminToken } = await loginAs(ROLES.ADMIN);
    const product = await createOnlineProduct(adminToken);
    const { token: customerToken } = await loginAs(ROLES.CUSTOMER);

    const orderRes = await request(app)
      .post('/api/orders')
      .set('Authorization', `Bearer ${customerToken}`)
      .send({
        items: [{ product: product._id, quantity: 1 }],
        paymentMethod: PAYMENT_METHODS.MANUAL_RECEIPT,
        delivery: { address: { line1: '1 St', city: 'Lahore', phone: '03000000000' } },
      });
    const orderId = orderRes.body.order._id;

    await request(app)
      .post(`/api/payments/orders/${orderId}/receipt`)
      .set('Authorization', `Bearer ${customerToken}`)
      .attach('receipt', Buffer.from('fake-image-bytes'), { filename: 'receipt.png', contentType: 'image/png' });

    const mine = await request(app).get(`/api/orders/mine/${orderId}`).set('Authorization', `Bearer ${customerToken}`);
    expect(mine.body.order.status).toBe('payment_under_review');
    expect(mine.body.order.paymentStatus).toBe('pending_review');

    const blocked = await request(app)
      .patch(`/api/orders/${orderId}/status`)
      .set('Authorization', `Bearer ${adminToken}`)
      .send({ status: 'processing' });
    expect(blocked.status).toBe(400);
    expect(blocked.body.error).toMatch(/not been approved/i);

    // payment_* statuses can't be set by hand either.
    const forbidden = await request(app)
      .patch(`/api/orders/${orderId}/status`)
      .set('Authorization', `Bearer ${adminToken}`)
      .send({ status: 'payment_approved' });
    expect(forbidden.status).toBe(400);

    // Admin gets a "receipt needs review" alert (delivered asynchronously).
    await new Promise((r) => setTimeout(r, 50));
    const alerts = await request(app).get('/api/notifications').set('Authorization', `Bearer ${adminToken}`);
    expect(alerts.body.notifications.some((n) => n.type === 'payment_review_required')).toBe(true);
  });

  test('order items snapshot the product image + SKU and keep them after the product changes', async () => {
    const { token: adminToken } = await loginAs(ROLES.ADMIN);
    const product = await createOnlineProduct(adminToken);
    const png = Buffer.from('89504e470d0a1a0a0000000d49484452', 'hex');
    const imgRes = await request(app)
      .post(`/api/products/${product._id}/image`)
      .set('Authorization', `Bearer ${adminToken}`)
      .attach('image', png, { filename: 'notebook.png', contentType: 'image/png' });
    const originalImage = imgRes.body.product.imageUrl;
    const { token: customerToken } = await loginAs(ROLES.CUSTOMER);

    const quoteRes = await request(app)
      .post('/api/orders/quote')
      .set('Authorization', `Bearer ${customerToken}`)
      .send({ items: [{ product: product._id, quantity: 2 }] });
    expect(quoteRes.status).toBe(200);
    expect(quoteRes.body.quote.items[0]).toMatchObject({ sku: product.sku, imageUrl: originalImage, lineTotal: 400 });
    expect(quoteRes.body.quote.total).toBe(400);

    const orderRes = await request(app)
      .post('/api/orders')
      .set('Authorization', `Bearer ${customerToken}`)
      .send({
        items: [{ product: product._id, quantity: 2 }],
        paymentMethod: PAYMENT_METHODS.CASH_ON_DELIVERY,
        delivery: { address: { line1: '1 St', city: 'Lahore', phone: '03000000000' } },
      });
    const orderId = orderRes.body.order._id;
    expect(orderRes.body.order.items[0]).toMatchObject({ product: product._id, sku: product.sku, imageUrl: originalImage });

    // Catalog product re-photographed, renamed and soft-deleted afterwards.
    await request(app)
      .post(`/api/products/${product._id}/image`)
      .set('Authorization', `Bearer ${adminToken}`)
      .attach('image', png, { filename: 'new.png', contentType: 'image/png' });
    await request(app).patch(`/api/products/${product._id}`).set('Authorization', `Bearer ${adminToken}`).send({ name: 'Renamed' });
    await request(app).delete(`/api/products/${product._id}`).set('Authorization', `Bearer ${adminToken}`);

    const mine = await request(app).get(`/api/orders/mine/${orderId}`).set('Authorization', `Bearer ${customerToken}`);
    expect(mine.body.order.items[0]).toMatchObject({ name: 'Notebook', sku: product.sku, imageUrl: originalImage });
    const admin = await request(app).get(`/api/orders/${orderId}`).set('Authorization', `Bearer ${adminToken}`);
    expect(admin.body.order.items[0].imageUrl).toBe(originalImage);
    expect(admin.body.order.customer.name).toBeDefined();

    // Full fulfilment chain for a COD order, then the inventory trail.
    for (const status of ['confirmed', 'processing', 'packing', 'dispatched', 'out_for_delivery', 'delivered', 'completed']) {
      // eslint-disable-next-line no-await-in-loop
      const res = await request(app)
        .patch(`/api/orders/${orderId}/status`)
        .set('Authorization', `Bearer ${adminToken}`)
        .send({ status });
      expect(res.status).toBe(200);
      expect(res.body.order.status).toBe(status);
    }
    const done = await request(app).get(`/api/orders/${orderId}`).set('Authorization', `Bearer ${adminToken}`);
    expect(done.body.order.paymentStatus).toBe('paid');
    expect(done.body.order.delivery.status).toBe('delivered');

    const movements = await request(app).get('/api/inventory/movements').set('Authorization', `Bearer ${adminToken}`);
    const saleRow = movements.body.logs.find((l) => l.type === 'sale' && l.reference === orderRes.body.order.orderNumber);
    expect(saleRow).toMatchObject({ sku: product.sku, previousStock: 10, quantityDelta: -2, resultingStock: 8 });
    expect(saleRow.product.name).toBe('Renamed');
  });

  test('admin can reject a receipt with a reason', async () => {
    const { token: adminToken } = await loginAs(ROLES.ADMIN);
    const product = await createOnlineProduct(adminToken);
    const { token: customerToken } = await loginAs(ROLES.CUSTOMER);

    const orderRes = await request(app)
      .post('/api/orders')
      .set('Authorization', `Bearer ${customerToken}`)
      .send({
        items: [{ product: product._id, quantity: 1 }],
        paymentMethod: PAYMENT_METHODS.MANUAL_RECEIPT,
        delivery: { address: { line1: '789 Side St', city: 'Lahore', phone: '03001112222' } },
      });
    const orderId = orderRes.body.order._id;

    await request(app)
      .post(`/api/payments/orders/${orderId}/receipt`)
      .set('Authorization', `Bearer ${customerToken}`)
      .attach('receipt', Buffer.from('fake-image-bytes'), { filename: 'receipt.png', contentType: 'image/png' });

    const pendingRes = await request(app).get('/api/payments/pending-review').set('Authorization', `Bearer ${adminToken}`);
    const paymentId = pendingRes.body.payments[0]._id;

    const rejectRes = await request(app)
      .post(`/api/payments/${paymentId}/review`)
      .set('Authorization', `Bearer ${adminToken}`)
      .send({ approve: false, note: 'Receipt amount does not match order total' });
    expect(rejectRes.body.payment.status).toBe('rejected');

    const orderCheck = await request(app).get(`/api/orders/${orderId}`).set('Authorization', `Bearer ${adminToken}`);
    expect(orderCheck.body.order.paymentStatus).toBe('rejected');
    expect(orderCheck.body.order.status).toBe('payment_rejected');
    expect(orderCheck.body.order.payment.reviewNote).toMatch(/does not match/);

    // Customer is told and can upload a corrected receipt, which goes back
    // under review (never auto-approved).
    await new Promise((r) => setTimeout(r, 50));
    const myAlerts = await request(app).get('/api/notifications').set('Authorization', `Bearer ${customerToken}`);
    expect(myAlerts.body.notifications.some((n) => n.type === 'payment_rejected')).toBe(true);

    const again = await request(app)
      .post(`/api/payments/orders/${orderId}/receipt`)
      .set('Authorization', `Bearer ${customerToken}`)
      .attach('receipt', Buffer.from('fixed-bytes'), { filename: 'receipt2.png', contentType: 'image/png' });
    expect(again.status).toBe(200);
    expect(again.body.payment.status).toBe('pending_review');
    const pendingAgain = await request(app).get('/api/payments/pending-review').set('Authorization', `Bearer ${adminToken}`);
    expect(pendingAgain.body.payments).toHaveLength(1);
  });
});
