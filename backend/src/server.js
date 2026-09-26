const app = require('./app');
const env = require('./config/env');
const { connectDb } = require('./config/db');
const { startLowStockJob } = require('./jobs/lowStockAlertJob');

async function start() {
  await connectDb();
  console.log('Connected to MongoDB'); // eslint-disable-line no-console

  startLowStockJob();

  app.listen(env.port, () => {
    console.log(`Usama Book Depot API listening on port ${env.port}`); // eslint-disable-line no-console
  });
}

start().catch((err) => {
  console.error('Failed to start server:', err); // eslint-disable-line no-console
  process.exit(1);
});
