const cron = require('node-cron');
const Product = require('../models/Product');

// SRS FR-2.3: alert admin/staff when stock falls below the reorder
// threshold. No SMS/email transport is wired yet, so this logs a summary
// server-side; the Flutter admin/POS shell also surfaces low-stock items
// directly from GET /api/products?lowStockOnly=true on demand.
function startLowStockJob() {
  cron.schedule('0 * * * *', async () => {
    try {
      const lowStockCount = await Product.countDocuments({
        isActive: true,
        isMadeToOrder: false,
        $expr: { $lte: ['$currentStock', '$reorderThreshold'] },
      });
      if (lowStockCount > 0) {
        console.log(`[low-stock-alert] ${lowStockCount} product(s) at or below reorder threshold`); // eslint-disable-line no-console
      }
    } catch (err) {
      console.error('[low-stock-alert] check failed:', err); // eslint-disable-line no-console
    }
  });
}

module.exports = { startLowStockJob };
