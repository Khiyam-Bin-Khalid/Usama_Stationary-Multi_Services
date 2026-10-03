const { connectDb } = require('../config/db');
const env = require('../config/env');
const User = require('../models/User');
const Product = require('../models/Product');
const { ROLES, PRODUCT_CATEGORIES } = require('./constants');
const { ensureDefaultCategories } = require('../services/categoryService');

async function seed() {
  await connectDb();
  await ensureDefaultCategories();
  console.log('Ensured default categories'); // eslint-disable-line no-console

  if (!env.superadmin.email || !env.superadmin.password) {
    throw new Error('Set SUPERADMIN_EMAIL and SUPERADMIN_PASSWORD in .env before seeding');
  }

  let superadmin = await User.findOne({ email: env.superadmin.email });
  if (!superadmin) {
    superadmin = new User({ name: env.superadmin.name, email: env.superadmin.email, role: ROLES.SUPERADMIN });
    await superadmin.setPassword(env.superadmin.password);
    await superadmin.save();
    console.log(`Created superadmin: ${superadmin.email}`); // eslint-disable-line no-console
  } else {
    console.log(`Superadmin already exists: ${superadmin.email}`); // eslint-disable-line no-console
  }

  const sampleProducts = [
    { name: 'A4 Copier Paper (Ream)', sku: 'STN-00001', barcode: '8901234567890', category: PRODUCT_CATEGORIES.STATIONERY, unit: 'ream', price: 850, costPrice: 650, currentStock: 40, reorderThreshold: 10 },
    { name: 'Ballpoint Pen (Box of 10)', sku: 'STN-00002', barcode: '8901234567906', category: PRODUCT_CATEGORIES.STATIONERY, unit: 'box', price: 300, costPrice: 200, currentStock: 60, reorderThreshold: 15 },
    { name: 'Custom T-Shirt Printing', sku: 'GAR-00001', category: PRODUCT_CATEGORIES.GARMENT, unit: 'pcs', price: 1200, costPrice: 700, currentStock: 0, reorderThreshold: 0, isMadeToOrder: true },
    { name: 'Banner Printing (per sq. ft)', sku: 'PRT-00001', category: PRODUCT_CATEGORIES.PRINTING, unit: 'sq.ft', price: 60, costPrice: 30, currentStock: 0, reorderThreshold: 0, isMadeToOrder: true },
    { name: 'Basmati Rice (5kg)', sku: 'GRO-00001', barcode: '8901234567913', category: PRODUCT_CATEGORIES.GROCERY, unit: 'bag', price: 1450, costPrice: 1250, currentStock: 25, reorderThreshold: 5 },
    { name: 'Football (Size 5)', sku: 'SPT-00001', barcode: '8901234567920', category: PRODUCT_CATEGORIES.SPORTS, unit: 'pcs', price: 1800, costPrice: 1300, currentStock: 12, reorderThreshold: 3 },
  ];

  for (const p of sampleProducts) {
    // eslint-disable-next-line no-await-in-loop
    await Product.updateOne({ sku: p.sku }, { $setOnInsert: p }, { upsert: true });
  }
  console.log(`Seeded ${sampleProducts.length} sample products (existing SKUs left untouched)`); // eslint-disable-line no-console

  process.exit(0);
}

seed().catch((err) => {
  console.error('Seed failed:', err); // eslint-disable-line no-console
  process.exit(1);
});
