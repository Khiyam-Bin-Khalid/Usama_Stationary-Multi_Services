# Postman testing

## Automated (recommended)

```
cd backend
npm run test:postman
```

This spins up a throwaway in-memory MongoDB and a real server on port 4100,
seeds a superadmin, runs `UsamaStationary.postman_collection.json` against it
with Newman, and tears everything down afterwards. It **never touches the
real `MONGODB_URI`** in `.env` — safe to run any time.

It exercises: the SKU validation-error fix, product image upload (falls back
to local disk when Cloudinary isn't configured — see below), image
visibility on the public storefront, the "who added this product"
`createdBy` field (and that it's hidden from the public), RBAC (Staff still
can't create products), and the Daily Sale / New Sale flow including the
inventory stock deduction.

To test the real Cloudinary path instead of the local-disk fallback, export
your Cloudinary credentials before running:

```
export CLOUDINARY_CLOUD_NAME=your_cloud_name
export CLOUDINARY_API_KEY=...
export CLOUDINARY_API_SECRET=...
npm run test:postman
```

(the "imageUrl is set" assertion accepts either a `/uploads/...` path or a
`https://res.cloudinary.com/...` URL, so it passes either way).

## Manual, in the Postman app

1. Import `UsamaStationary.postman_collection.json`,
   `UsamaStationary_API_Examples.postman_collection.json`, and
   `UsamaStationary.postman_environment.json`.
2. Select the "Usama Stationary - Local" environment, set `superadminEmail`
   / `superadminPassword` to match your real `backend/.env`, and make sure
   the backend is running (`npm run dev`) against your real database.
3. To run the regression walkthrough, run
   `UsamaStationary.postman_collection.json` top-to-bottom in Collection
   Runner — later requests depend on variables set by earlier ones (tokens,
   product id, etc). Use the complete API examples collection for individual
   manual requests instead.
4. The "Upload Product Image" request needs its form-data file re-attached
   the first time you open it on a new machine (Postman stores absolute
   file paths, which don't carry over) — point it at
   `postman/fixtures/sample-product.png`.

The **Usama Stationary — Complete API Examples** collection is for manual,
endpoint-by-endpoint testing; it includes request bodies, query examples,
role-specific bearer auth, and file-upload placeholders for every mounted
endpoint. Log in with each role to populate its token variable, and replace
the `REPLACE_WITH_*` ID variables with IDs from your API responses. Attach an
image or receipt file to the corresponding form-data request when needed.
Do not run this examples collection top-to-bottom against production: sample
write requests create or change database records. The Stripe webhook example
requires a real Stripe-signed request and cannot be sent as an unsigned dummy
event.

Careful: running this against your real `.env` database creates real test
accounts/products/sales. Prefer the automated script above unless you
specifically want to poke at your real data by hand.
