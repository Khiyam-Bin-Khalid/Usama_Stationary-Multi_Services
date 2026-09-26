const { app, request, loginAs } = require('./helpers');
const { ROLES, PRODUCT_CATEGORIES } = require('../src/utils/constants');

describe('Reporting + Promotions', () => {
  test('daily sales report reflects a recorded POS sale', async () => {
    const { token } = await loginAs(ROLES.ADMIN);
    const productRes = await request(app)
      .post('/api/products')
      .set('Authorization', `Bearer ${token}`)
      .send({ name: 'Pen', sku: 'SKU-RPT-1', category: PRODUCT_CATEGORIES.STATIONERY, price: 50, currentStock: 100 });
    const product = productRes.body.product;

    await request(app)
      .post('/api/sales')
      .set('Authorization', `Bearer ${token}`)
      .send({ clientTxnId: 'rpt-txn-00001', items: [{ product: product._id, quantity: 4 }], paymentMethod: 'cash' });

    const reportRes = await request(app)
      .get('/api/reports/sales?period=daily&source=pos')
      .set('Authorization', `Bearer ${token}`);

    expect(reportRes.status).toBe(200);
    expect(reportRes.body.summary.totalRevenue).toBe(200);
    expect(reportRes.body.buckets).toHaveLength(1);
  });

  test('staff cannot request a weekly report (limited reporting access)', async () => {
    const { token } = await loginAs(ROLES.STAFF);
    const res = await request(app).get('/api/reports/sales?period=weekly').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(403);
  });

  test('active promotion is discoverable on the public endpoint and discounts an order', async () => {
    const { token: adminToken } = await loginAs(ROLES.ADMIN);
    const productRes = await request(app)
      .post('/api/products')
      .set('Authorization', `Bearer ${adminToken}`)
      .send({
        name: 'Summer Shirt',
        sku: 'SKU-PROMO-1',
        category: PRODUCT_CATEGORIES.GARMENT,
        price: 1000,
        currentStock: 5,
        isAvailableOnline: true,
      });
    const product = productRes.body.product;

    const now = new Date();
    const startDate = new Date(now.getTime() - 86400000).toISOString();
    const endDate = new Date(now.getTime() + 86400000).toISOString();

    await request(app)
      .post('/api/promotions')
      .set('Authorization', `Bearer ${adminToken}`)
      .send({
        name: 'Special Summer Deal',
        discountType: 'percent',
        discountValue: 10,
        categories: [PRODUCT_CATEGORIES.GARMENT],
        startDate,
        endDate,
      });

    const activeRes = await request(app).get('/api/promotions/active');
    expect(activeRes.body.promotions).toHaveLength(1);

    const { token: customerToken } = await loginAs(ROLES.CUSTOMER);
    const orderRes = await request(app)
      .post('/api/orders')
      .set('Authorization', `Bearer ${customerToken}`)
      .send({
        items: [{ product: product._id, quantity: 1 }],
        paymentMethod: 'cash_on_delivery',
        delivery: { address: { line1: '1 St', city: 'Lahore', phone: '0300' } },
      });

    expect(orderRes.body.order.discountTotal).toBe(100);
    expect(orderRes.body.order.total).toBe(900);
  });
});
