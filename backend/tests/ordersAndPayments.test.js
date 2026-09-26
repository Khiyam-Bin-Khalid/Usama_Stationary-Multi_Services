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
    expect(approveRes.body.payment.status).toBe('paid');

    const orderCheck = await request(app)
      .get(`/api/orders/mine/${orderId}`)
      .set('Authorization', `Bearer ${customerToken}`);
    expect(orderCheck.body.order.paymentStatus).toBe('paid');
    expect(orderCheck.body.order.status).toBe('confirmed');
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
  });
});
