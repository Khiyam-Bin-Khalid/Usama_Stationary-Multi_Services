# Usama Book Depot — Backend API

Node.js + Express + MongoDB REST API for the POS system: role-based auth, inventory,
POS sales (with offline-sync support), online orders, promotions, payments (Stripe +
manual receipt-upload + cash on delivery), and analytical sales reporting.

## Setup

```bash
npm install
cp .env.example .env   # then edit values, especially MONGODB_URI and JWT secrets
```

You need a MongoDB instance reachable at `MONGODB_URI`. Options:
- Install MongoDB locally (`sudo apt install mongodb` / see mongodb.com/docs/manual/installation)
- Run it in Docker: `docker run -d -p 27017:27017 --name usama-mongo mongo:7`
- Use a free MongoDB Atlas cluster and put its connection string in `.env`

```bash
npm run seed   # creates the superadmin account from .env + a few sample products
npm run dev    # starts the API on http://localhost:4000 with auto-reload
npm test       # runs the Jest/Supertest suite against an in-memory MongoDB
```

## Payments

Three payment methods are supported behind one `PaymentMethod` interface
(`method` field on the `Payment` model):

- **`stripe`** — real Checkout Session + webhook integration. Only activates once you add
  your own `STRIPE_SECRET_KEY` / `STRIPE_WEBHOOK_SECRET` to `.env`; until then, orders placed
  with this method return a `503` explaining the other two options are available.
- **`manual_receipt`** — customer uploads a payment screenshot/receipt
  (`POST /api/payments/orders/:orderId/receipt`), order enters `payment_pending_review`, and an
  admin approves or rejects it from `GET /api/payments/pending-review` /
  `POST /api/payments/:id/review`.
- **`cash_on_delivery`** — no upfront payment; marked paid automatically when the order is
  marked `delivered`.

## FBR (Pakistan tax authority) integration

Postponed per SRS §5.6/§7 (conditional requirement). `Sale` and `Order` already carry
`fbrInvoiceNumber`, `fbrQrPayload`, and `fbrSyncStatus` fields so the live FBR PRAL API
integration can be added later without a schema change.

## API overview

| Area | Base path |
|---|---|
| Auth (login, register, refresh, staff creation) | `/api/auth` |
| User management (superadmin/admin) | `/api/users` |
| Products & inventory | `/api/products` |
| POS sales | `/api/sales` |
| Offline sync (push queued sales / pull catalog deltas) | `/api/sync` |
| Analytical reports (daily/weekly/monthly/yearly, category) | `/api/reports` |
| Promotions / seasonal deals | `/api/promotions` |
| Online orders | `/api/orders` |
| Payments (Stripe, manual receipt, review) | `/api/payments` |

See `src/routes/*.js` for exact endpoints and required roles.
