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

From the repository root, `npm run dev` starts the backend API. Complete the
backend setup below first; the Flutter app is run separately from `app/`.

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

## Testing on several devices (same Wi-Fi / LAN)

One PC runs the backend; every other device (desktop POS, phone browser, Android APK) talks to
it over the local network. The app's default API URL is `http://localhost:4000/api` (Android
emulator: `http://10.0.2.2:4000/api`), so the backend must listen on **port 4000** and any other
device must be given the PC's LAN IP via `--dart-define=API_BASE_URL=...`.

### 1. Find the backend PC's LAN IP

```bash
hostname -I | awk '{print $1}'     # Linux, e.g. 10.181.237.77
ipconfig                           # Windows: "IPv4 Address"
```

The examples below use `10.181.237.77`; replace it with yours. The IP can change after a reboot
or a Wi-Fi reconnect — if it does, rebuild the web app / APK with the new IP.

### 2. Start the backend on port 4000

Pick **one** — they use different databases, so data added in one won't show in the other.

```bash
# Option A — npm, uses MONGODB_URI from backend/.env (e.g. Atlas). PORT=4000 in .env.
cd backend
npm install                 # first time only
npm run seed                # first time only: superadmin + default categories + sample products
npm run dev                 # type `rs` + Enter to restart after editing .env

# Option B — Docker, API + its own MongoDB (data kept in Docker volumes)
cd backend
docker compose up -d --build
docker compose run --rm api node src/utils/seed.js   # first time only
docker compose logs -f api
docker compose down         # stop (add -v to also wipe the database + uploads)
```

Check it from the PC **and** from another device's browser:

```bash
curl http://localhost:4000/health          # {"status":"ok",...}
curl http://10.181.237.77:4000/health
```

Allow browsers on other devices to call the API — in `backend/.env` (then restart the backend):

```
CLIENT_ORIGIN=http://10.181.237.77:8080,http://localhost:8080,http://localhost:5173
```

If other devices can't connect, open the ports on the backend PC's firewall:

```bash
sudo ufw allow 4000 && sudo ufw allow 8080
```

### 3. Run the app on each device (commands from `app/`)

| Device | Command |
|---|---|
| **Linux desktop POS — same PC as backend** (dev) | `flutter run -d linux` |
| Linux desktop POS — same PC (release binary) | `flutter build linux --release` → `./build/linux/x64/release/bundle/usama_book_depot` |
| Linux / Windows desktop — **another PC** | `flutter build linux --release --dart-define=API_BASE_URL=http://10.181.237.77:4000/api` (or `flutter build windows ...`), copy the whole `bundle/` (or `Release/`) folder and run it there |
| **Customer web app** for phones / other PCs (release) | `flutter build web --release --dart-define=API_BASE_URL=http://10.181.237.77:4000/api` then `cd build/web && python3 -m http.server 8080 --bind 0.0.0.0` → open **http://10.181.237.77:8080** on any device |
| Web app, dev with hot reload, reachable from the LAN | `flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8080 --dart-define=API_BASE_URL=http://10.181.237.77:4000/api` |
| Web app in Chrome on the same PC | `flutter run -d chrome` |
| **Android phone** via USB (debug) | `flutter devices` then `flutter run -d <device-id> --dart-define=API_BASE_URL=http://10.181.237.77:4000/api` |
| Android phone — install an APK | `flutter build apk --release --dart-define=API_BASE_URL=http://10.181.237.77:4000/api` → copy `build/app/outputs/flutter-apk/app-release.apk` to the phone and install |
| Android emulator | `flutter run -d emulator-5554` (uses `10.0.2.2:4000` automatically) |

Typical two-device test: the **Linux PC** runs the backend plus the desktop POS (log in as
**Super Admin** with `SUPERADMIN_EMAIL` / `SUPERADMIN_PASSWORD` from `backend/.env`); a **phone**
opens `http://10.181.237.77:8080`, registers as a customer and places an order. Products added
on the POS appear in the storefront and the order appears in the POS *Orders* screen.

> Android release builds block plain `http://` traffic by default (Android 9+). For an APK talking
> to a LAN backend over HTTP, add `android:usesCleartextTraffic="true"` to the `<application>` tag
> in `app/android/app/src/main/AndroidManifest.xml`, or put the backend behind HTTPS.

### 4. Stop everything

```bash
# Ctrl+C in the `npm run dev` terminal   (or: cd backend && docker compose down)
pkill -f "http.server 8080"              # web server
# close the desktop app window / press `q` in the `flutter run` terminal
```

### Troubleshooting

| Symptom | Cause / fix |
|---|---|
| "The connection errored: Connection refused" on the dashboard and other screens | The backend isn't on the port the app uses. Check `ss -ltnp \| grep 4000` and `PORT=4000` in `backend/.env`; a build made with `--dart-define` must match the running backend's host and port. |
| Web app loads but login fails with a network / CORS error | The web app's origin (e.g. `http://10.181.237.77:8080`) is missing from `CLIENT_ORIGIN`; add it and restart the backend. |
| Works on the PC, not on the phone | Different Wi-Fi network, firewall (`ufw allow 4000 8080`), the PC's IP changed, or the build still points at `localhost`. |
| Product photo upload says "File upload failed" | Cloudinary rejected the upload. The backend log shows the reason, e.g. `403` = the API key in `.env` lacks upload ("create") permission; fix it in Cloudinary → Settings → API Keys. |
| `GVFS-RemoteVolumeMonitor-WARNING ... GoaVolumeMonitor is not supported` in the Linux terminal | Harmless GTK message, not an app error. Hide it with `GIO_USE_VOLUME_MONITOR=unix flutter run -d linux`. |
| Super admin login rejected on a fresh database | Run the seed once (`npm run seed`, or the `docker compose run ... seed.js` command above). |

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

## Working offline (desktop and mobile apps)

The web build needs a connection. Desktop and mobile keep working when the internet or the server
is down; the red banner says so, and everything syncs by itself when the server is back (it retries
every 30 seconds, or use **Sync now** on the sync queue).

| Works offline | Needs the server |
|---|---|
| Sign-in (Super Admin, Admin, Staff) | Orders and payment review |
| Sales (POS) and Daily Sale | Promotions |
| Add, edit, delete products, adjust stock (Admin up) | Staff accounts and audit log |
| Product photos (held on the device, uploaded on sync) | Shifts, stock movement history, discrepancy reports |
| Dashboard figures, **Daily records** | Consolidated reports and charts |

- **Offline sign-in:** an account must have signed in online on that device once. Several accounts
  can share a device. Five wrong passwords lock the account for 5 minutes, and offline access
  expires if the server hasn't seen the account for 30 days.
- **Daily records** (`/records`, Admin up) keeps the last 31 days on the device: revenue per date
  (cash, card, invoices, items, tap a date for every line sold) and a stock record of what sold,
  what remains and what has sold out. The server keeps every sale permanently; only the device copy
  is limited. Anything not yet synced is never removed.
- **Sync queue** (sidebar sync status, `/sync`) lists what's waiting. Sales and product changes reach
  the server dated when they happened, credited to whoever made them. A change the server refuses,
  such as a sale of stock another till already sold, waits there for an Admin to retry or discard.

## Automated tests

```bash
cd backend && npm test          # API tests, in-memory MongoDB
cd app && flutter test          # unit, migration and widget tests

# End-to-end, against a throwaway stack (never touches the database in backend/.env):
node backend/scripts/e2e-stack.js                                      # leave running
cd app
E2E_STACK=1 flutter test test/e2e/backend_e2e_test.dart                # real client, real API, connection cut
flutter test --platform chrome test/e2e/web_upload_test.dart           # web upload in a real browser
flutter test integration_test/offline_admin_flow_test.dart -d linux    # real screens, full offline session

# One real photo to the Cloudinary account in backend/.env:
node backend/scripts/e2e-stack.js --real-cloudinary                    # leave running
REAL_CLOUDINARY=1 flutter test test/e2e/real_cloudinary_test.dart      # from app/
```

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
