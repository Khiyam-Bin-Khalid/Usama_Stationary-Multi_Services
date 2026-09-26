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

## Roles and who manages them

Roles live in the backend (`backend/src/utils/constants.js`) and are mirrored in
`app/lib/core/roles.dart`. Accounts are managed from the **Staff** screen of the POS/Admin shell
(`/admin/staff`), which only `admin` and `superadmin` can open.

| Role         | How the account is created                                       | Can manage                                     |
|--------------|------------------------------------------------------------------|------------------------------------------------|
| `superadmin` | Once, by `npm run seed` from `SUPERADMIN_EMAIL` / `SUPERADMIN_PASSWORD` in `backend/.env`. Only that one email may act as superadmin. | Everything: create/disable `admin` and `staff`, change roles, all admin screens |
| `admin`      | Created by the superadmin in **Staff → New account** (Role = Admin) | Create/disable `staff` only; orders, payments, promotions, inventory, reports, POS |
| `staff`      | Created by an admin or superadmin in **Staff → New account**      | POS sales, stock view, reports only            |
| `customer`   | Self-registers from the login screen ("New customer? Create an account") — usually on the web app | Their own cart and orders |

Nobody can register as staff/admin from the public form: the register endpoint hard-codes the
`customer` role, and the create-account endpoint requires an `admin`/`superadmin` token.

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
