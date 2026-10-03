# Technology stack & offline/online sync — how it actually works

> **Note on "Supabase":** this codebase does not use Supabase anywhere — no
> package, no config, no environment variable references it. The database is
> **MongoDB** (via Mongoose), accessed only through the Node/Express REST API
> in `backend/`. The thing that behaves like a "sync with a cloud database"
> is the **Flutter desktop app's local SQLite cache syncing with that
> MongoDB-backed API**, described in full below. If a Supabase integration
> was actually intended (e.g. as a second/alternate backend), that doesn't
> exist yet and would need to be scoped separately — this document describes
> what's really in the repo today.

---

## 1. Technologies used in the Flutter app (desktop + web, one codebase)

The Flutter app in `app/` targets **desktop** (Windows/macOS/Linux, as the
POS/Admin terminal) and **web** (as the customer storefront + a
browser-accessible Admin/POS build) from the same source tree, using
conditional imports (`if (dart.library.js_interop) ...`) to swap out
platform-specific pieces like the local database connection.

| Concern | Package | What it's doing here |
|---|---|---|
| UI framework | `flutter` (SDK) | Renders the same widget tree on desktop and web; `MediaQuery` width checks (e.g. `isWide` in `pos_admin_shell.dart`) switch between a sidebar (desktop-width) and a drawer (narrow window/web). |
| State management / DI | `flutter_riverpod` ^2.6.1 | Every API client, repository, and piece of screen state is a Riverpod `Provider`/`FutureProvider`/`StreamProvider` (see `core/providers.dart`). No `setState`-only global state — screens `ref.watch()` providers and Riverpod handles rebuilds and disposal. |
| Routing | `go_router` ^14.6.2 | Declarative route table (`core/router/app_router.dart`) with a `redirect` callback that checks `Permissions.canAccessPath(role, path)` on every navigation — this is the client-side half of the RBAC system (the server enforces the same rules independently on every request). |
| HTTP client | `dio` ^5.7.0 | `ApiClient` (`data/remote/api_client.dart`) wraps a `Dio` instance with an interceptor that (a) attaches the JWT access token to every request, and (b) on a `401`, transparently calls `/auth/refresh` once and retries the original request — callers never see the token expiry. |
| Local database (offline cache) | `drift` ^2.21.0 + `sqlite3`/`sqlite3_flutter_libs` | A real embedded SQLite database on-device — see §2. **Desktop/mobile only**; never constructed on web (`appDatabaseProvider` returns `null` when `kIsWeb`). |
| Local DB storage location | `path_provider` + `path` | Resolves the OS-appropriate app-data directory (e.g. `~/.local/share/<app>` on Linux) to put `usama_book_depot.sqlite` in. |
| Connectivity detection | `connectivity_plus` ^6.1.0 | `SyncService` listens to `Connectivity().onConnectivityChanged` and triggers a sync the moment the OS reports the network is back. |
| Secure token storage | `flutter_secure_storage` ^9.2.2 | JWT access/refresh tokens and the last-used role live in the OS keychain (Keychain/DPAPI/libsecret depending on platform), not `SharedPreferences`/plain files. On web it degrades to the package's own browser-storage fallback. |
| Client-generated IDs | `uuid` ^4.5.1 | Generates the `clientTxnId` idempotency key for every sale (`pos-<uuid>`), so retried/offline-replayed sales can never be double-counted server-side. |
| Formatting | `intl` ^0.19.0 | Currency (`Rs. `, en_PK locale) and date/time formatting (`core/format.dart`). |
| Charts | `fl_chart` ^0.69.2 | The revenue-over-time bar chart on the Reports screen. |
| Image capture | `image_picker` ^1.1.2 | Product photo picking (Inventory "Add/Edit Product") and payment-receipt photo picking, on every platform including desktop/web via the gallery/file picker. |
| File picking | `file_picker` ^8.1.4 | Installed for more general file-selection needs alongside `image_picker`. |
| Links | `url_launcher` ^6.3.1 | Opening external links (e.g. from notifications/receipts). |
| Code generation | `build_runner` + `drift_dev` (dev-only) | Generates `app_database.g.dart` (typed table classes, companions, queries) from the `Table` definitions in `tables.dart`. Re-run `dart run build_runner build` after changing a table. |

### Backend stack (for context — the app talks to this over HTTP)

Node.js + Express + **Mongoose/MongoDB** (`backend/`), JWT auth
(`jsonwebtoken`), request validation with `joi`, file uploads with
`multer`, and — as of this change — product photos optionally pushed to
**Cloudinary** (`cloudinary` SDK) with a local-disk fallback. See
`backend/src/services/productImageService.js`.

---

## 2. The local SQLite cache (Drift) — what it stores

`app/lib/data/local/tables.dart` defines four tables, compiled by Drift into
a typed API (`AppDatabase` in `app_database.dart`):

- **`ProductsCache`** — a mirror of the product catalog (id, name, sku,
  category, price, stock, thresholds, flags, `updatedAt`). Lets the POS
  screen render and be sold from with zero network calls.
- **`PromotionsCache`** — active promotions, same idea.
- **`PendingSales`** — one row per sale made **while offline**, keyed by the
  client-generated `clientTxnId`, with a `synced` flag and `syncError` text.
  This is the offline queue.
- **`SyncMeta`** — a tiny key/value table; currently holds `lastSyncTime` so
  the next pull only asks the server for deltas.

The connection itself is swapped per platform via a conditional import in
`app_database.dart`:
- **Native** (`connection/connection.dart`): `NativeDatabase.createInBackground` against a real `.sqlite` file under the OS app-data directory.
- **Web** (`connection/connection_web.dart`): throws if ever called — web builds never construct `AppDatabase` in the first place (`appDatabaseProvider` short-circuits to `null` when `kIsWeb`), because the storefront/web build is always online and has no offline requirement.

---

## 3. How syncing with MongoDB actually works, end to end

There is no continuous replication or change-stream subscription — sync is
a deliberate, on-demand **pull deltas + push queue** cycle, triggered by
`SyncService` (`app/lib/data/repositories/sync_service.dart`):

**When it runs:**
1. Once at app start (`SyncService.start()` calls `syncNow()` immediately).
2. Every time the OS reports connectivity changed *to* online (`connectivity_plus` stream listener).
3. It is **not** polled on a timer — it's event-driven off connectivity changes, plus the one-shot at startup.

**Each `syncNow()` cycle does two things, in order:**

### a) Push — drain the offline sales queue
1. `db.unsyncedSales()` reads every `PendingSales` row where `synced = false`.
2. If any exist, they're POSTed in one batch to `POST /api/sync/push` (`syncController.pushSales`, `backend/src/routes/syncRoutes.js`).
3. The server loops each queued sale through the **same** `createSale()` service function used by the normal online "New Sale" endpoint — same stock-deduction logic, same validation. `clientTxnId` is a unique+indexed field on the `Sale` model, so if the same sale is pushed twice (e.g. a retry after a dropped response), the second attempt is detected and reported back as `alreadyExisted: true` instead of creating a duplicate sale or double-deducting stock.
4. The server also fires a `SYNC_FAILED` domain event (→ notifies Admin/Super Admin) if any queued sale is genuinely rejected (e.g. insufficient stock by the time it synced) — that's a real conflict a human needs to resolve, not something the app can silently paper over.
5. Back on the client, each result marks that row `synced` (deleted from the pending queue) or records `syncError` against it (stays queued, surfaced to the user rather than silently retried forever).

### b) Pull — refresh the local catalog cache
1. `db.lastSyncTime()` reads the watermark from `SyncMeta`.
2. `GET /api/sync/pull?since=<that timestamp>` (`syncController.pullDeltas`) returns every `Product` and `Promotion` document with `updatedAt >= since` — a simple delta query, not a full re-sync every time.
3. The client `insertAllOnConflictUpdate`s those rows into `ProductsCache`/`PromotionsCache` (upsert by primary key `id`), then writes the server's returned `serverTime` back into `SyncMeta` as the new watermark for next time.

**Between syncs**, a sale made offline is not "lost" waiting for permission
to proceed — `PosRepository.recordSale()` (`app/lib/data/repositories/pos_repository.dart`) tries the online endpoint first; if that specific failure is a *network* error (not a real rejection like "insufficient stock" — that distinction is `ApiException.isNetworkError`), it immediately (a) decrements the local `ProductsCache` stock optimistically so the next sale on the same terminal has correct numbers, and (b) queues the sale into `PendingSales` right there, without waiting for the next sync cycle. The next connectivity-restored event then pushes it for real.

**Status visible to the user:** `SyncService.statusStream` (`idle` /
`syncing` / `offline`) drives the small colored dot in the desktop sidebar
and the red "Offline — sales are being saved locally" banner
(`pos_admin_shell.dart`), so the cashier always knows which state they're in.

### Why this design, not something like Supabase realtime/replication
- The spec's actual requirement (SRS "Availability") is: *a POS terminal
  keeps working through a short network blip, and reconciles once it's
  back* — not multi-device realtime collaboration. A pull-deltas/push-queue
  cycle satisfies that with a fraction of the moving parts a
  realtime-subscription system would need, and it works uniformly across
  desktop/mobile without a different code path per platform.
- Idempotency (`clientTxnId`) rather than distributed-transaction/conflict-resolution machinery is enough because sales are create-only events, not documents multiple people edit concurrently.
