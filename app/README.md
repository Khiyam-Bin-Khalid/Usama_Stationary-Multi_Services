# Usama Book Depot — Flutter App

One Flutter codebase covering desktop (Windows/Linux/macOS), mobile (Android/iOS), and web,
talking to the Node/Express/MongoDB backend in `../backend`. After login it mounts one of two
"shells" based on role:

- **POS/Admin shell** (`superadmin` / `admin` / `staff`) — POS sale screen, inventory, reports,
  and (admin/superadmin only) staff management, promotions, order management, and payment review.
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

## Payments in the UI

Checkout offers all three methods the backend supports:
- **Stripe** — opens the hosted checkout page in the browser (`url_launcher`). Only works once
  the backend has real Stripe keys configured; until then it returns a clear error.
- **Manual receipt upload** — order is placed, then the order-detail screen lets the customer
  pick an image (`image_picker`) to upload as proof of payment; status shows "payment under
  review" until an admin approves/rejects it from the Admin/POS shell's Payments screen.
- **Cash on delivery** — no upfront payment step.

## Theme

The whole palette derives from the brand page gradient
`linear-gradient(135deg, #fdfcfb 0%, #e2d1c3 100%)` (cream → tan). It is painted once behind
every route by `lib/core/theme/app_background.dart` (mounted in `main.dart` via
`MaterialApp.builder`), and every `Scaffold` is transparent so it shows through. `web/index.html`
paints the same gradient in CSS so there is no white flash while the engine loads.

Text and UI colors are deep warm browns chosen against the *darkest* stop of the gradient
(`#e2d1c3`) so they pass WCAG AA everywhere along it — the ratios are listed in
`lib/core/theme/app_colors.dart`. Dark mode uses the same hue family inverted (espresso →
cocoa). `test/theme_smoke_test.dart` pumps a representative screen in both brightnesses.

## Not yet wired up

- Receipt/invoice **printing** to a physical POS printer — needs a platform printing plugin (e.g.
  ESC/POS over USB/Bluetooth) once real hardware is available; out of scope for this build.
- Live **FBR** e-invoicing — postponed per the SRS (see `../backend/README.md`).
