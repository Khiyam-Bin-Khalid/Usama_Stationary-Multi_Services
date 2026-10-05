# Usama Stationary & Multi Services — Backend API

Node.js, Express, and MongoDB REST API for the store's POS, inventory, online
orders, payments, staff operations, notifications, and reporting.

## Run locally

Requirements: Node.js/npm and a MongoDB instance.

```bash
npm install
cp .env.example .env
# Edit .env with your local MongoDB URI, JWT secrets, and bootstrap admin details.
npm run seed
npm run dev
```

The API starts at `http://localhost:4000`; the API base URL is
`http://localhost:4000/api`. Check `GET /health` for server status.

Useful commands:

```bash
npm test          # Jest/Supertest tests
npm run test:postman  # Automated Newman/Postman end-to-end test (port 4100)
```

## Postman setup and credentials

1. Import `postman/UsamaStationary.postman_collection.json` for the automated
   regression walkthrough, `postman/UsamaStationary_API_Examples.postman_collection.json`
   for copy/paste examples of every API endpoint, and
   `postman/UsamaStationary.postman_environment.json`.
2. Select the **Usama Stationary - Local** environment. Set `baseUrl` to
   `http://localhost:4000/api` for a locally running API.
3. Enter the test account's email and password in the environment's
   `superadminEmail` and `superadminPassword` values in Postman. These must
   match the bootstrap superadmin configured in your local `.env`. Credentials
   are not supplied by this README; do not commit or share real credentials.
4. Send `POST {{baseUrl}}/auth/login` with:

   ```json
   {
     "email": "{{superadminEmail}}",
     "password": "{{superadminPassword}}"
   }
   ```

   For protected endpoints, set the request's authorization to use the returned
   `accessToken` in its token field. In Postman, open **Authorization**, set
   the auth type to **Bearer**, and paste the `accessToken` value in the token
   field (do not paste the `refreshToken`). Include
   `Content-Type: application/json` for JSON request bodies.
   The complete API examples collection includes a login request for each
   role and stores the returned tokens for use by protected requests. Update
   the sample role credentials in its collection variables after creating
   local test accounts. Use that collection for individual/manual requests;
   requests that create, update, or delete data are not intended to be run as
   one sequence against production.
5. For customer-only endpoints, first create a customer with
   `POST /auth/register-customer`, then log in as that customer. To test staff
   roles, use the superadmin token to create an admin or staff account via
   `POST /auth/register-staff` or `POST /auth/register-admin`, then log in with
   the new account. For example, choose **POST**, enter
   `http://localhost:4000/api/auth/register-staff`, set the request's
   **Authorization** type to **Bearer**, paste the superadmin's `accessToken`
   in the token field, and send this JSON body:

   ```json
   {
     "name": "Test Staff",
     "email": "staff.test@example.com",
     "password": "ChangeMe123!",
     "role": "staff",
     "phone": "03001234567",
     "branch": "Main"
   }
   ```

   Use the same request with `/auth/register-admin` and `"role": "admin"` to
   create an admin. These are example account details; use a unique email each
   time. Do not put real account passwords in this README or commit them.

The bundled collection focuses on product/image and POS-sale end-to-end
regression coverage; this README catalogs the complete API. The manual
Postman environment contains placeholders, not working credentials. The
automated `npm run test:postman` uses a temporary in-memory database and
separate test credentials; it does not use your `.env` MongoDB database.
Manual requests against a real database can create or change real records.

## Authentication and roles

Protected endpoints use JWT access tokens. In Postman, set the request's
authorization to use the returned `accessToken` in its token field.

Roles used below:

- **Public**: no login required.
- **Authenticated**: any valid account.
- **Superadmin**, **Admin**, **Staff**, **Customer**: restricted to the named
  role(s). “Admin+” means Admin or Superadmin; “Staff+” means Staff, Admin, or
  Superadmin.

Most successful responses are JSON. Request bodies are JSON unless noted.
Validation errors return a client error; access restrictions return
unauthorized/forbidden responses.

## Endpoint catalog

### Health

| Method and path | Access | Function |
|---|---|---|
| `GET /health` | Public | API health and current server time. |

### Authentication — `/auth`

| Method and path | Access | Function and request |
|---|---|---|
| `POST /auth/register-customer` | Public | Customer self-registration. Body: `name`, `email`, `password`; optional `phone`. |
| `POST /auth/login` | Public | Log in and receive access/refresh tokens and account details. Body: `email`, `password`; optional `role` hint (`superadmin`, `admin`, `staff`, `customer`). A role hint does not grant permissions. |
| `POST /auth/refresh` | Public | Exchange a valid refresh token for refreshed authentication tokens. Body: `refreshToken`. |
| `GET /auth/me` | Authenticated | Get the current account profile. |
| `POST /auth/staff` | Superadmin | Legacy staff-account creation endpoint. Body: `name`, `email`, `password`, `role` (`admin` or `staff`); optional `phone`, `branch`. |
| `POST /auth/register-staff` | Superadmin | Create a staff account. Same body as `POST /auth/staff`. |
| `POST /auth/register-admin` | Superadmin | Create an admin account. Same body as `POST /auth/staff`; set `role` to `admin`. |

### User administration — `/users`

All routes require a Superadmin token.

| Method and path | Function and request |
|---|---|
| `GET /users` | List users. Optional query: `role`, `isActive`, `q` (search text). |
| `GET /users/:id` | Get one user. |
| `PATCH /users/:id` | Update user profile/status. Body may include `name`, `phone`, `branch`, `isActive`. |
| `PATCH /users/:id/role` | Change role. Body: `role` (`admin` or `staff`); the API does not promote accounts to superadmin. |
| `DELETE /users/:id` | Soft-delete and deactivate a user while preserving referenced sales/audit history. |

### Products and inventory — `/products`

Product list/detail routes are public; a valid token enables role-aware catalog
filters. Product management is Admin+; inventory logs are Staff+.

| Method and path | Access | Function and request |
|---|---|---|
| `GET /products` | Public/Authenticated | Browse products. Optional query: `category`, `sellableOnly`, `q` (matches name, SKU, barcode, description), `barcode` / `sku` (exact lookups for scanners), `isAvailableOnline`, `isActive`, `lowStockOnly`, `page`, `limit`. Anonymous users see active, in-stock items. |
| `GET /products/:id` | Public/Authenticated | Get product detail. |
| `POST /products` | Admin+ | Create product. Required: `name`, `category`, `price`. **`sku` is optional — left blank it is generated by the system** (`STN-00001`, `GRO-00001`, … per category, see `services/skuService.js`). Optional: `barcode` (unique physical scan code, separate from SKU and from the Mongo `_id`), `unit`, `costPrice`, `currentStock`, `reorderThreshold`, `isMadeToOrder`, `isAvailableOnline`, `imageUrl`, `description`, `branch`. |
| `PATCH /products/:id` | Admin+ | Update product fields, including name, barcode, category, price, reorder level, online/active flags, image, description, and branch (SKU is immutable). |
| `DELETE /products/:id` | Admin+ | Soft-deactivate a product while retaining it for historical sales and reports. |
| `POST /products/:id/adjust-stock` | Admin+ | Make a stock adjustment. Body: non-zero `delta` and `reason`. |
| `POST /products/:id/image` | Admin+ | Upload a product image as multipart form-data, field name `image`. Multer stores uploads in `UPLOAD_DIR` (default `uploads`) with a generated filename; images go to Cloudinary when configured and otherwise remain available locally. |
| `GET /products/:id/inventory-log` | Staff+ | View the product's inventory movement history. |

### Inventory — `/inventory`

| Method and path | Access | Function and request |
|---|---|---|
| `GET /inventory/movements` | Staff+ | Stock-movement history across all products, newest first. Each row has product (populated with image/SKU/barcode), `sku`, `previousStock`, `quantityDelta`, `resultingStock`, `type` (`sale`, `purchase`, `adjustment`, `return`), `reference` (order number / POS txn), `reason`, `actor`, timestamp. Optional query: `product`, `sku`, `category`, `type`, `from`, `to`, `page`, `limit`. |
| `GET /inventory/low-stock` | Staff+ | Products at or below their reorder level (including out of stock). |
| `POST /inventory/discrepancies` … | Staff+ | Shelf-count discrepancy reports (see Discrepancies below). |

### Categories — `/categories`

| Method and path | Access | Function and request |
|---|---|---|
| `GET /categories` | Authenticated | List active categories. |
| `POST /categories` | Admin+ | Create category. Required: `key`, `name`; optional: `unitType`, `defaultReorderThreshold`. |
| `PATCH /categories/:key` | Admin+ | Update category `name`, `unitType`, `defaultReorderThreshold`, or `isActive`. |

### POS sales — `/sales`

All routes require Staff+.

| Method and path | Function and request |
|---|---|
| `POST /sales` | Record a POS sale and deduct inventory. Body: `clientTxnId`, `items` (each has product ID and `quantity`), optional `paymentMethod` (`cash` or `card`), `taxRate`, `branch`, `recordedOffline`. |
| `GET /sales` | List sales. Optional query: `from`, `to`, `category`, `shift`, `page`, `limit`. |
| `GET /sales/:id` | Get sale details. |

### Offline sync — `/sync`

All routes require Staff+.

| Method and path | Function and request |
|---|---|
| `POST /sync/push` | Synchronize queued POS sales. Body: `sales` array using the `POST /sales` sale format. Each transaction is idempotent by `clientTxnId`; response reports success/error per sale. |
| `GET /sync/pull` | Pull product and promotion changes. Optional query: `since` timestamp (ISO 8601); omitted means all available changes. |

### Reports and dashboard — `/reports`

All routes require Staff+. Staff are limited to their own daily POS figures;
Admin and Superadmin can view consolidated reporting.

| Method and path | Access | Function and query |
|---|---|---|
| `GET /reports/dashboard` | Staff+ | Role-specific dashboard metrics, including sales, shift, stock, orders, discrepancies, notifications; superadmins also receive account totals and recent audit activity. |
| `GET /reports/sales` | Staff+ | Sales trend buckets (line graph data). Optional query: `period` (`daily`, `weekly`, `monthly`, `yearly`), `source` (`pos`, `online`, `all`), `category`, `product`, `from`, `to` (any custom date range). Online orders count once they are confirmed or later; cancelled / payment-rejected orders are excluded. |
| `GET /reports/categories` | Admin+ | Sales breakdown by category. Optional query: `source` (`pos`, `online`, `all`), `from`, `to`. |
| `GET /reports/products` | Admin+ | Top products by revenue (name, SKU, revenue, items sold). Optional query: `source`, `category`, `from`, `to`, `limit`. |

### Promotions — `/promotions`

| Method and path | Access | Function and request |
|---|---|---|
| `GET /promotions/active` | Public | List currently active promotions. |
| `GET /promotions` | Admin+ | List promotions, including inactive/upcoming promotions. |
| `POST /promotions` | Admin+ | Create promotion. Required: `name`, `discountType` (`percent` or `flat`), `discountValue`, `startDate`, `endDate`. Optional: `description`, `categories`, `products`, `isActive`. |
| `PATCH /promotions/:id` | Admin+ | Update promotion fields, including discount, dates, targeting, and active status. |

### Online orders — `/orders`

| Method and path | Access | Function and request |
|---|---|---|
| `POST /orders/quote` | Customer | Price a cart without creating anything — the checkout summary. Body: `items`; optional `isHomeDelivery`. Returns the item snapshots (name, `sku`, `imageUrl`, unit price, quantity, line total), `subtotal`, `discountTotal` (+ promotion), `taxRate`/`taxAmount` (`ORDER_TAX_RATE`), `deliveryFee` (`DELIVERY_FEE`) and `total`. |
| `POST /orders` | Customer | Place an order. Body: `items` (product ID and integer `quantity`), `paymentMethod` (`stripe`, `manual_receipt`, or `cash_on_delivery`), and `delivery` with `address` (`line1`, `city`, `phone`; optional `line2`) and optional `isHomeDelivery`, `window`. Every order item stores a snapshot of the product — `name`, `sku`, `barcode`, `imageUrl`, `unitPrice` — so the image the customer chose stays on the order for its whole lifecycle even if the catalog product is edited or deleted later. Stock is reserved on placement and returned on cancellation. |
| `GET /orders/mine` | Customer | List the logged-in customer's orders. |
| `GET /orders/mine/:id` | Customer | Order detail including `payment` (receipt URL, review status/note) and `statusHistory`. |
| `GET /orders` | Staff+ | List orders. Optional query: `status`, `statuses` (comma-separated group, e.g. `processing,packing`), `paymentStatus`, `page`, `limit`. |
| `GET /orders/status-counts` | Staff+ | Order count per lifecycle status (for the admin queue tabs). |
| `GET /orders/:id` | Staff+ | Full order: customer, items with images/SKUs, totals, `payment` (uploaded receipt + review outcome), `statusHistory` with the acting user. |
| `PATCH /orders/:id/status` | Admin+ | Advance fulfilment. Body: `status` ∈ `confirmed`, `processing`, `packing`, `dispatched`, `out_for_delivery`, `delivered`, `completed`, `cancelled`; optional `note`, `courierName`, `trackingNote`. The `payment_*` statuses cannot be set here — they come only from the payment flow — and fulfilment statuses are refused until the payment is approved (or the order is cash on delivery). Completed / cancelled orders are final. |

**Order lifecycle:** `pending` → `payment_submitted` → `payment_under_review` → `payment_approved` → `confirmed` → `processing` → `packing` → `dispatched` → `out_for_delivery` → `delivered` → `completed`, with `payment_rejected` (customer re-uploads) and `cancelled` as side exits. Every transition is appended to `statusHistory` (`status`, `at`, `note`, `by`).

### Payments — `/payments`

| Method and path | Access | Function and request |
|---|---|---|
| `POST /payments/stripe/webhook` | Public (Stripe) | Receive Stripe payment events. Requires Stripe's raw request body and valid `Stripe-Signature`; normally called by Stripe, not manually. |
| `POST /payments/orders/:orderId/receipt` | Customer | Upload a manual-payment receipt (multipart field `receipt`, optional `note`). The payment becomes `pending_review`, the order moves to `payment_submitted` → `payment_under_review`, and admins get a `payment_review_required` notification (in-app + email). Nothing is approved automatically. Allowed again after a rejection (corrected proof). |
| `GET /payments/pending-review` | Admin+ | Receipts awaiting an explicit decision, each with the populated order (customer, items with images/SKUs, totals). |
| `GET /payments/orders/:orderId` | Staff+ | The payment record (receipt URL, review outcome) for one order. |
| `POST /payments/:id/review` | Admin+ | Explicit decision. Body: boolean `approve`; optional `note`. Approve → payment `approved`, order `payment_approved` → `confirmed`. Reject → payment `rejected`, order `payment_rejected`, customer notified (`payment_rejected`) so they can re-upload. |

Payment methods are `stripe`, `manual_receipt`, and `cash_on_delivery`.
Stripe checkout requires configured Stripe keys; manual receipt review and cash
on delivery are available without Stripe configuration.

### Shifts — `/shifts`

All routes require Staff+. Staff can view their own shifts; Admin and
Superadmin can view all shifts.

| Method and path | Function and request |
|---|---|
| `POST /shifts/open` | Open a staff shift. Optional body: `openingCash`, `branch`, `note`. |
| `POST /shifts/close` | Close the current staff shift. Required body: `closingCashActual`; optional `note`. |
| `GET /shifts/current` | Get the caller's open shift and report, or `null` when no shift is open. |
| `GET /shifts` | List shifts visible to the caller (up to the latest 100). |
| `GET /shifts/:id` | Get a shift report; Staff may only access their own shift. |

### Notifications — `/notifications`

Staff roles receive role-addressed alerts; customers receive their own order/payment
notifications (`payment_rejected`, `payment_approved`, `order_status_changed`, addressed via
`recipientUser`). Every route returns only what the caller may see.

| Method and path | Function and request |
|---|---|
| `GET /notifications` | List notifications. Optional query: `unreadOnly`, `page`, `limit`. |
| `GET /notifications/unread-count` | Get the unread notification count. |
| `POST /notifications/read-all` | Mark all caller-visible notifications as read. |
| `PATCH /notifications/:id/read` | Mark one notification as read. |

### Inventory discrepancies — `/inventory/discrepancies`

| Method and path | Access | Function and request |
|---|---|---|
| `POST /inventory/discrepancies` | Staff+ | Report counted stock. Body: `product` ID, `countedQty`; optional `note`. |
| `GET /inventory/discrepancies` | Staff+ | List reports. Optional query: `status` (`open`, `resolved`, `dismissed`), `page`, `limit`. Staff see only their own reports. |
| `PATCH /inventory/discrepancies/:id/resolve` | Admin+ | Resolve/dismiss a report. Optional body: `applyAdjustment`, `dismiss`, `resolution`. |

### Audit log — `/audit-logs`

| Method and path | Access | Function and query |
|---|---|---|
| `GET /audit-logs` | Superadmin | List audit activity. Optional query: `action`, `actor` user ID, `entityType`, `from`, `to`, `page`, `limit`. |

## Sample requests for Postman

Use the method and path in the endpoint catalog with the sample query or JSON
below. Prefix API paths with `http://localhost:4000/api`. For a protected
endpoint, set the **Authorization** type to **Bearer** and paste the
`accessToken` returned by login into the token field; the required role is
shown in the catalog. Replace `<...>` path
values with IDs returned by earlier requests. Requests marked **No body** do
not need a request body.

For `/auth/login`, use the email and password of an account in your local
database (for the superadmin, these are `SUPERADMIN_EMAIL` and
`SUPERADMIN_PASSWORD` from `backend/.env`):

```json
{
  "email": "your-superadmin@example.com",
  "password": "your-local-superadmin-password"
}
```

| Endpoint | Sample query or request body |
|---|---|
| `GET /health` | No body. URL: `http://localhost:4000/health` |
| `POST /auth/register-customer` | `{"name":"Test Customer","email":"customer.test@example.com","password":"ChangeMe123!","phone":"03001234567"}` |
| `POST /auth/login` | `{"email":"your-account@example.com","password":"your-local-password","role":"superadmin"}` (use the account's actual role; `role` is optional). |
| `POST /auth/refresh` | `{"refreshToken":"<REFRESH_TOKEN>"}` |
| `GET /auth/me` | No body. |
| `POST /auth/staff` | `{"name":"Test Staff","email":"staff.test@example.com","password":"ChangeMe123!","role":"staff","phone":"03001234567","branch":"Main"}` |
| `POST /auth/register-staff` | `{"name":"Test Staff","email":"staff.test@example.com","password":"ChangeMe123!","role":"staff","phone":"03001234567","branch":"Main"}` |
| `POST /auth/register-admin` | `{"name":"Test Admin","email":"admin.test@example.com","password":"ChangeMe123!","role":"admin","phone":"03007654321","branch":"Main"}` |
| `GET /users` | Query: `?role=staff&isActive=true&q=Test` |
| `GET /users/<USER_ID>` | No body. Replace `<USER_ID>` with a user ID. |
| `PATCH /users/<USER_ID>` | `{"name":"Updated Staff Name","phone":"03001234567","branch":"Main","isActive":true}` |
| `PATCH /users/<USER_ID>/role` | `{"role":"staff"}` (or `"admin"`). |
| `DELETE /users/<USER_ID>` | No body. Replace `<USER_ID>` with a user ID. |
| `GET /products` | Query: `?category=stationery&sellableOnly=true&page=1&limit=20` |
| `GET /products/<PRODUCT_ID>` | No body. Replace `<PRODUCT_ID>` with a product ID. |
| `POST /products` | `{"name":"Test Notebook","sku":"TEST-NB-001","category":"stationery","unit":"piece","price":250,"costPrice":150,"currentStock":20,"reorderThreshold":5,"isAvailableOnline":true,"description":"Sample product","branch":"Main"}` |
| `PATCH /products/<PRODUCT_ID>` | `{"price":275,"isAvailableOnline":true,"description":"Updated sample product"}` (use `/adjust-stock` to change stock). |
| `DELETE /products/<PRODUCT_ID>` | No body. Replace `<PRODUCT_ID>` with a product ID. |
| `POST /products/<PRODUCT_ID>/adjust-stock` | `{"delta":5,"reason":"Test stock replenishment"}` |
| `POST /products/<PRODUCT_ID>/image` | Body type **form-data**; key `image`, type **File**, select an image file. Do not set JSON content type. |
| `GET /products/<PRODUCT_ID>/inventory-log` | No body. Replace `<PRODUCT_ID>` with a product ID. |
| `GET /categories` | No body. |
| `POST /categories` | `{"key":"test_supplies","name":"Test Supplies","unitType":"piece","defaultReorderThreshold":5}` |
| `PATCH /categories/test_supplies` | `{"name":"Updated Test Supplies","unitType":"piece","defaultReorderThreshold":8,"isActive":true}` |
| `POST /sales` | `{"clientTxnId":"postman-sale-001","items":[{"product":"<PRODUCT_ID>","quantity":2}],"paymentMethod":"cash","taxRate":0,"branch":"Main","recordedOffline":false}` |
| `GET /sales` | Query: `?from=2026-10-01&to=2026-10-31&page=1&limit=20` |
| `GET /sales/<SALE_ID>` | No body. Replace `<SALE_ID>` with a sale ID. |
| `POST /sync/push` | `{"sales":[{"clientTxnId":"postman-sync-001","items":[{"product":"<PRODUCT_ID>","quantity":1}],"paymentMethod":"cash","taxRate":0,"branch":"Main","recordedOffline":true}]}` |
| `GET /sync/pull` | Query: `?since=2026-10-01T00:00:00.000Z` |
| `GET /reports/dashboard` | No body. |
| `GET /reports/sales` | Query: `?period=daily&source=all&from=2026-10-01&to=2026-10-31` |
| `GET /reports/categories` | Query: `?source=all&from=2026-10-01&to=2026-10-31` |
| `GET /promotions/active` | No body. |
| `GET /promotions` | No body. |
| `POST /promotions` | `{"name":"Test Stationery Sale","description":"Sample promotion","discountType":"percent","discountValue":10,"categories":["stationery"],"products":[],"startDate":"2026-10-04T00:00:00.000Z","endDate":"2026-11-04T00:00:00.000Z","isActive":true}` |
| `PATCH /promotions/<PROMOTION_ID>` | `{"discountValue":15,"isActive":true}` |
| `POST /orders` | `{"items":[{"product":"<PRODUCT_ID>","quantity":1}],"paymentMethod":"cash_on_delivery","delivery":{"isHomeDelivery":true,"address":{"line1":"1 Test Street","city":"Lahore","phone":"03001234567"},"window":"10:00-12:00"}}` |
| `GET /orders/mine` | No body. Customer token required. |
| `GET /orders/mine/<ORDER_ID>` | No body. Replace `<ORDER_ID>` with your order ID. |
| `GET /orders` | Query: `?status=pending&page=1&limit=20` |
| `GET /orders/<ORDER_ID>` | No body. Replace `<ORDER_ID>` with an order ID. |
| `PATCH /orders/<ORDER_ID>/status` | `{"status":"confirmed","note":"Test status update"}` |
| `POST /payments/stripe/webhook` | Stripe-only endpoint; no manual sample. Stripe must sign the raw request with `Stripe-Signature`. |
| `POST /payments/orders/<ORDER_ID>/receipt` | Body type **form-data**; key `receipt`, type **File**, select a receipt image. Customer token required. |
| `GET /payments/pending-review` | No body. |
| `POST /payments/<PAYMENT_ID>/review` | `{"approve":true,"note":"Test receipt approved"}` (set `approve` to `false` to reject). |
| `POST /shifts/open` | `{"openingCash":5000,"branch":"Main","note":"Test shift"}` |
| `POST /shifts/close` | `{"closingCashActual":7500,"note":"Test shift close"}` |
| `GET /shifts/current` | No body. |
| `GET /shifts` | No body. |
| `GET /shifts/<SHIFT_ID>` | No body. Replace `<SHIFT_ID>` with a shift ID. |
| `GET /notifications` | Query: `?unreadOnly=true&page=1&limit=20` |
| `GET /notifications/unread-count` | No body. |
| `POST /notifications/read-all` | No body. |
| `PATCH /notifications/<NOTIFICATION_ID>/read` | No body. Replace `<NOTIFICATION_ID>` with a notification ID. |
| `POST /inventory/discrepancies` | `{"product":"<PRODUCT_ID>","countedQty":18,"note":"Test stock count"}` |
| `GET /inventory/discrepancies` | Query: `?status=open&page=1&limit=20` |
| `PATCH /inventory/discrepancies/<DISCREPANCY_ID>/resolve` | `{"applyAdjustment":true,"dismiss":false,"resolution":"Count verified; apply stock adjustment"}` |
| `GET /audit-logs` | Query: `?action=user.create&entityType=User&page=1&limit=20` |

Requests that create records should use fresh, unique test emails/SKUs/transaction
IDs as appropriate. Product, order, sale, payment, and other `<..._ID>` values
must be replaced with real IDs from your API responses. The API writes to the
database configured in `.env`; use test data or a separate development
database when experimenting.

## Configuration notes

- Configure MongoDB and secrets in `.env`; start from `.env.example`.
- Use strong, unique values for `JWT_ACCESS_SECRET` and `JWT_REFRESH_SECRET`.
- `SUPERADMIN_EMAIL` and `SUPERADMIN_PASSWORD` configure the account created by
  `npm run seed`; enter those account credentials in Postman when testing.
- Stripe variables are optional unless testing Stripe checkout/webhooks.
- Product images use Cloudinary when configured and local upload storage as a
  fallback. Receipt uploads use the configured `UPLOAD_DIR` and
  `MAX_UPLOAD_MB`.
- The FBR integration is not currently implemented; FBR fields are reserved
  for a future integration.
