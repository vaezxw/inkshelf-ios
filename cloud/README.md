# InkShelf API (Cloudflare Workers)

Optional account + cloud sync backend for the InkShelf iOS app.

## Stack

- **Workers** — HTTPS API
- **D1** — users, books metadata, bookmarks, prefs, sources
- **R2** — optional local TXT backups
- **Email OTP** — 6-digit code (dev mode echoes code in JSON when `OTP_ECHO=true`)

## Setup

```bash
cd cloud
npm install

# Create real D1 + R2 in your Cloudflare account, then put IDs into wrangler.jsonc:
# Replace the placeholder database_id (00000000-...) with the id from `wrangler d1 create`.
npx wrangler d1 create inkshelf
npx wrangler r2 bucket create inkshelf-books

# Set JWT secret
npx wrangler secret put JWT_SECRET

# Migrate schema (remote production D1)
npm run db:migrate

# Deploy
npm run deploy
```

Copy the deployed `*.workers.dev` URL into the iOS app Settings → 云同步 → API 地址.

## Dev

```bash
npm run db:migrate:local
npm run dev
```

With `OTP_ECHO=true`, `POST /auth/request-otp` returns `{ ok, echoCode }` so you can verify without SMTP.

## Auth

| Method | Path | Body |
|--------|------|------|
| POST | `/auth/request-otp` | `{ "email": "a@b.com" }` |
| POST | `/auth/verify` | `{ "email": "a@b.com", "code": "123456" }` |
| GET | `/auth/me` | Bearer JWT |

## Sync

| Method | Path | Notes |
|--------|------|------|
| GET | `/sync/pull?since=ISO8601` | LWW snapshots since timestamp (`since=0` = full) |
| POST | `/sync/push` | `{ books, bookmarks, sources, prefs }` each item has `id`, `updatedAt`, `payload` |

## Files (R2)

| Method | Path | Notes |
|--------|------|------|
| PUT | `/files/:bookId` | raw body = TXT bytes; requires auth |
| GET | `/files/:bookId` | download TXT |

## Conflict policy

**Last-Write-Wins** on `updated_at` (ISO-8601 UTC).
