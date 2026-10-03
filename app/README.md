# Usama Book Depot — Flutter App

One Flutter codebase covering desktop (Windows/Linux/macOS), mobile (Android/iOS), and web,
talking to the Node/Express/MongoDB backend in `../backend`. After login it mounts one of two
"shells" based on role:

- **POS/Admin shell** (`superadmin` / `admin` / `staff`) — role-specific dashboard, POS sale
  screen, inventory (read-only for staff, who report discrepancies instead), reports (staff: own
  sales only), shift open/close, alerts; admin/superadmin add orders, payments, promotions and
  discrepancy resolution; superadmin alone gets accounts & roles and the audit log. Navigation is
  built from `Permissions` in `lib/core/roles.dart`, and the router blocks direct navigation.
- **Storefront shell** (`customer`) — catalog browsing, cart/checkout, order tracking.

## Offline storage

The POS/Admin shell caches the product catalog and promotions locally via **drift** (a SQLite
ORM) on every platform except web, and queues POS sales made while offline in a local
`pending_sales` table. `SyncService` (`lib/data/repositories/sync_service.dart`) pushes the queue
and pulls catalog changes automatically whenever connectivity returns (`connectivity_plus`), so a
short network interruption at the counter doesn't stop sales. Each offline sale carries a
client-generated `clientTxnId`; the backend dedupes on that key, so a retried sync push is safe.

Web has no local SQLite cache by design — the SRS requires the web app to have an internet
connection, so the storefront (and an admin browsing the shell from a browser) talk to the API
directly. See `lib/data/local/connection/connection_web.dart`.

## Setup

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # generates app_database.g.dart (drift)
```

Point the app at your backend (defaults to `http://localhost:4000/api`, or `http://10.0.2.2:4000/api`
on the Android emulator):

```bash
flutter run --dart-define=API_BASE_URL=http://<your-backend-host>:4000/api
```

Run for a specific target:

```bash
flutter run -d windows   # or -d linux / -d macos / -d chrome / -d <android-device-id>
```

## Storefront layout

Customer pages (`features/catalog`, `cart_checkout`, `orders`, `profile`) wrap their content in
`ResponsiveContainer` from `lib/core/responsive.dart`: a centred column capped at 1200 px with a
16 px gutter on phones (< 600 px), 24 px on tablets (600–1023 px) and 32 px on desktop. The product
grid picks 2 / 3 / 4 / 5 columns from the same breakpoints. Change those numbers in one place to
retune the whole storefront. `StorefrontShell` switches between a top navigation bar and a bottom
`NavigationBar` at the phone breakpoint.

`lib/widgets/product_image.dart` is the single product-image widget (catalog, product page, cart,
checkout, order detail, admin order detail, payment review, POS, inventory, stock movements) so a
product's image — or the order item's stored image snapshot — looks the same everywhere.

## Payments in the UI

Checkout offers all three methods the backend supports:
- **Stripe** — opens the hosted checkout page in the browser (`url_launcher`). Only works once
  the backend has real Stripe keys configured; until then it returns a clear error.
- **Manual receipt upload** — order is placed, then the order-detail screen lets the customer
  pick an image (`image_picker`) to upload as proof of payment. The uploaded receipt and its
  review state stay visible on the order; the order sits in "Payment under review" until an admin
  explicitly approves or rejects it from *Payment review* (or the admin order page). A rejection
  shows the admin's reason and an "Upload corrected receipt" button.
- **Cash on delivery** — no upfront payment step.

## Theme

The palette is the exact brand token set in `lib/core/theme/app_colors.dart` (see the usage map
in that file); `lib/core/theme/app_theme.dart` maps every Material component onto it and the app
runs light-only, as the spec palette is a white-background system. `web/index.html` paints the
same white base so there is no flash before the engine loads. `test/theme_smoke_test.dart`
asserts the token values and that the theme hands them out.

## Not yet wired up

- Receipt/invoice **printing** to a physical POS printer — needs a platform printing plugin (e.g.
  ESC/POS over USB/Bluetooth) once real hardware is available; out of scope for this build.
- Live **FBR** e-invoicing — postponed per the SRS (see `../backend/README.md`).
