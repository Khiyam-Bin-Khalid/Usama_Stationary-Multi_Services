# Usama Book Depot — POS System

Built from `Usama_Book_Depot_POS_SRS.docx`. Two parts:

- **`backend/`** — Node.js + Express + MongoDB REST API: role-based auth (superadmin/admin/staff/
  customer), inventory with event-sourced stock logging, POS sales with offline-sync idempotency,
  online ordering, seasonal promotions, payments (Stripe + manual receipt-upload + cash on
  delivery), and daily/weekly/monthly/yearly analytical reporting.
- **`app/`** — one Flutter codebase for desktop, mobile, and web, with a POS/Admin shell (in-store
  staff/admin/superadmin) and a Storefront shell (online customers). Uses a local SQLite cache
  (via drift) on non-web platforms so the POS screen keeps working through short network
  interruptions and syncs back automatically.

See `backend/README.md` and `app/README.md` for setup. Quick start:

```bash
# Terminal 1 — backend (needs a MongoDB instance — see backend/README.md)
cd backend
npm install
cp .env.example .env   # edit MONGODB_URI etc.
npm run seed            # creates the superadmin account + sample products
npm run dev

# Terminal 2 — app
cd app
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run -d chrome    # or -d windows / -d linux / -d macos / an Android device
```

## How to access each part

There is **one** Flutter app. It does not have a "POS build" and a "web build" — the target
device only decides *where it runs*, and the **role of the account that logs in** decides *what
it shows*:

| Who logs in                      | What they get                                    |
|----------------------------------|--------------------------------------------------|
| `superadmin`, `admin`, `staff`   | POS/Admin shell (counter sales, inventory, reports, admin) |
| `customer` (self-registered)     | Storefront shell (catalog, cart, checkout, my orders)     |

So `flutter run -d linux` on the shop PC is the POS, and the hosted web build is what end
users open in a browser — but an admin can also log in from the browser and get the admin
shell, and a customer logging in on the desktop build gets the storefront.

| Part                          | Command (from `app/`)                                             |
|-------------------------------|-------------------------------------------------------------------|
| POS on the shop desktop (Linux)   | `flutter run -d linux`                                        |
| POS on Windows / macOS            | `flutter run -d windows` / `flutter run -d macos`             |
| POS on an Android tablet/phone    | `flutter run -d <device-id>` (`flutter devices` lists ids)    |
| Web app, dev (Chrome)             | `flutter run -d chrome`                                       |
| Web app, dev (any browser)        | `flutter run -d web-server --web-port 5173` then open http://localhost:5173 |
| Web app, production               | `flutter build web --release` → serve `build/web/` (nginx, Apache, Netlify, Firebase Hosting…) |
| Desktop installer/binary          | `flutter build linux` / `flutter build windows` → `build/<platform>/…/release/` |
| Android APK for staff devices     | `flutter build apk --release` → `build/app/outputs/flutter-apk/app-release.apk` |

Every one of these needs the backend reachable. Point a build at a non-local backend with
`--dart-define=API_BASE_URL=http://<host>:4000/api` (see `app/README.md`). For the production web
app also add its public origin to `CLIENT_ORIGIN` in `backend/.env`.

Only desktop and mobile builds keep the offline SQLite cache; the web build talks to the API
directly and needs a connection (per the SRS).

## Roles and who manages them (spec §2)

Roles live in the backend (`backend/src/utils/constants.js`) and are mirrored in
`app/lib/core/roles.dart` (`Permissions`). The server enforces every rule with one central
`requireRole` middleware per route; the app only decides what to *show*.

| Capability | Super Admin | Admin | Staff | Customer |
|---|:---:|:---:|:---:|:---:|
| Register / delete Admin & Staff accounts, change roles | ✅ | ❌ | ❌ | — |
| Add / edit / delete products, adjust stock | ✅ | ✅ | ❌ | — |
| Record counter sales (POS), open/close shift | ✅ | ✅ | ✅ | — |
| View inventory (read-only) + report discrepancies | ✅ | ✅ | ✅ | — |
| Daily sales report | ✅ | ✅ | own sales only | — |
| Weekly / monthly / yearly + category reports | ✅ | ✅ | ❌ | — |
| Orders, payment review, promotions | ✅ | ✅ | ❌ | own orders |
| Low-stock / out-of-stock / new-customer / sync alerts | ✅ | ✅ | ❌ (new-order alerts only) | — |
| Audit log | ✅ | ❌ | ❌ | — |
| Register / browse / order online | — | — | — | ✅ |

- **superadmin** is created once by `npm run seed` from `SUPERADMIN_EMAIL` / `SUPERADMIN_PASSWORD` in
  `backend/.env`. Only that email may act as superadmin, and the account cannot be edited or deleted
  through the API.
- **admin** / **staff** are created only by the superadmin in **Accounts & roles → New account**
  (`POST /api/auth/register-admin` / `register-staff`). Role changes and deletes are audit-logged;
  deletes are soft (the account can no longer sign in, history is kept).
- **customer** self-registers from the login screen ("New customer? Create an account"), which
  notifies Admin/Super Admin. The public form hard-codes the customer role.

### Login flow (spec §1)

The desktop/mobile POS login shows a **role selector** (Super Admin / Admin / Staff) before the
credentials. The selected role is sent to `POST /api/auth/login`; the server compares it with the
account's real role and rejects a mismatch with 403 (and writes an `auth.login_failed` audit entry).
Each role then lands on its **own dashboard** (`/dashboard`) with its own navigation. The web build
opens in the customer sign-in flow, with a "Staff / admin sign-in" link for admins using a browser.

### Inventory, notifications, shifts (spec §4–§6)

- Categories are data (`GET/POST/PATCH /api/categories`), each with a unit type and default
  low-stock threshold (5). Stock is always changed within the product's own category.
- Reaching **0** marks a product out of stock: hidden from the POS quick-sell grid and storefront,
  never deleted. Crossing **≤ threshold** raises a low-stock alert. Both are audit-logged.
- The **Notification Service** (`backend/src/services/notificationService.js`) subscribes to domain
  events (`services/events.js`) — low stock, out of stock, customer registered, order placed,
  payment failed, POS sync failure, staff discrepancy report — and stores role-addressed in-app
  notifications (`GET /api/notifications`). Email delivery is logged until an SMTP provider is
  configured in `services/mailer.js`.
- Staff **report discrepancies** from the Stock screen (`POST /api/inventory/discrepancies`); an
  admin resolves them, optionally applying the shelf count as an adjustment.
- **Shifts**: staff open a shift with a cash float and close it with the counted cash; the server
  computes expected cash from the shift's cash sales and records the variance (Z-report).
  Sales record the open shift; staff reports and sale lists are scoped to their own transactions.

### Products, orders and payment review (consolidated spec)

- **Three separate identifiers.** Product ID = the database `_id`; **SKU** = system-generated
  business code (`STN-00001`, `GRO-00001`, … per category — the admin never types one, though an
  explicit value is still accepted for imports); **Barcode** = optional physical scan code, unique
  when present. Inventory rows show image · name · SKU · barcode · price · stock · reorder level ·
  status, and the search box accepts a scanned barcode.
- **Image continuity.** Every order item (and POS sale item) stores a snapshot — name, SKU,
  barcode, image reference, unit price — so the image the customer selected is shown identically
  in the cart, checkout summary, confirmation, payment review, admin order detail, processing /
  packing / dispatch / delivery queues, tracking and order history, regardless of later catalog
  edits or soft-deletes. One widget (`app/lib/widgets/product_image.dart`) renders it everywhere.
- **Checkout summary** comes from `POST /api/orders/quote`: images, names, SKUs, quantities, unit
  prices, item totals, subtotal, discount, delivery charge (`DELIVERY_FEE`), tax (`ORDER_TAX_RATE`)
  and grand total, then delivery details and payment method.
- **Receipt verification is mandatory.** Uploading a receipt moves the order to *Payment
  submitted → Payment under review* and notifies admins; only an explicit admin **Approve** moves
  it to *Payment approved → Order confirmed*. **Reject** moves it to *Payment rejected*, notifies
  the customer with the reason, and lets them upload a corrected receipt. Fulfilment statuses are
  refused by the server until payment is approved (or the order is cash on delivery).
- **Order lifecycle & queues.** Pending → Payment submitted → Under review → Approved → Confirmed
  → Processing → Packing → Dispatched → Out for delivery → Delivered → Completed (plus Payment
  rejected / Cancelled). The admin Orders screen has a queue per stage; *Processing & delivery*
  opens on the fulfilment queues; cancelling returns reserved stock.
- **Stock movements.** Every change (sale, order reservation, adjustment, return, initial stock)
  is logged with product, SKU, previous stock, delta, resulting stock, type, related order/sale,
  user and time (`GET /api/inventory/movements`, admin *Stock movement* screen). POS sales and
  online orders share the same stock, so both sides always see the same counts.
- **Reports** support daily / weekly / monthly / yearly presets or any custom date range, filtered
  by source, category and product, drawn as line graphs, plus category and top-product breakdowns.
- **Storefront** navigation: Home, Products, Categories, Deals, Cart, Orders, Profile — top links on
  tablet/desktop, bottom navigation on phones. Content sits in a 1200 px max-width container with
  16 / 24 / 32 px side gutters (phone / tablet / desktop) defined once in
  `app/lib/core/responsive.dart`.

### Theme

`app/lib/core/theme/app_colors.dart` holds the exact brand tokens (primaryOrange `#FF6A00`,
primaryDark `#E65E00`, accentRed `#FF4D4D`, success `#16A34A`, background `#FFFFFF`, surface
`#F7F7F7`, textPrimary `#1A1A1A`, textSecondary `#6B6B6B`, border `#E5E5E5`) and the usage map;
`app_theme.dart` applies them (orange primary buttons / selected tabs / selected role, primaryDark
on hover/press and focused inputs, accentRed for low-stock, deals, delete and errors, success for
paid/synced/confirmation toasts, surface for cards/sidebar/inputs, border for outlines/dividers).

## What's postponed (by design, confirmed with the client)

- **FBR (Pakistan tax authority) e-invoicing** — the SRS itself makes this conditional ("if/when
  the business becomes subject to mandatory FBR POS integration"). The data model already carries
  the fields FBR integration would need (invoice numbering, tax breakdown, QR payload, sync
  status); the live PRAL API call itself isn't wired up.
- **Real Stripe payments** — the Checkout Session + webhook integration is fully implemented and
  will work as soon as real `STRIPE_SECRET_KEY`/`STRIPE_WEBHOOK_SECRET` values are added to
  `backend/.env`. Until then, checkout falls back to manual receipt-upload (admin-reviewed) or
  cash on delivery, so the app is usable end-to-end today without any payment gateway account.
- **Physical receipt/invoice printing** — needs a platform printing plugin once real POS hardware
  (receipt printer) is available.
