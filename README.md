# worten_autoposting_create_offers

Daily cron job (Coolify, core-code.app) — Worten Mirakl autoposting Pending -> Active.

Owner: Vitaliy Dyedukh.

## What it does

Each day at 06:30 Europe/Kiev:

1. Reads `x_auto_posting` tasks in `STAGE_PENDING` (6) on Worten website `117`
   (Worten PT | HAJUS) from Odoo prod, then groups them by `x_studio_product`
   to get unique product ids.
2. Fetches the whole-shop MCM status dump
   (`GET /api/mcm/products/sources/status/export?shop_id=5553`) in a single request.
3. Classifies each unique product locally by matching `default_code`/`barcode`
   against `provider_unique_identifier`/`unique_identifiers` from the dump:
   `LIVE` / `NOT_LIVE` / `NOT_IN_MCM`.
4. For LIVE products: builds offer rows (multi-channel:
   `price[channel=WRT_PT_ONLINE]` + `price[channel=WRT_ES_ONLINE]`,
   pricelists 20 PT / 24 ES), uploads XLSX to `/api/offers/imports`
   (blind import, idempotent on `(shop_id, shop_sku)`), polls until COMPLETE.
5. For every accepted product, activates its tasks on website `117`
   that are not yet ACTIVE.
6. `NOT_LIVE` tasks stay in Pending (the next daily run will pick them up
   once MCM catches up). `NOT_IN_MCM` -> New Task.
7. Failures and timeouts notify Bitrix24 (single rolling task with comments).

## Optimization — n8n vs Coolify V3

This script replaces an older n8n cron workflow that polled Mirakl per-product
to detect Pending->LIVE transitions. Each Pending product required 1-3 Mirakl
API calls (`/api/products`, `/api/offers?product_id=...`, optional MCM status)
executed sequentially with `Retry-After` backoff on 429.

The V3 strategy uses **one MCM dump instead of N per-product checks**, **blind
import instead of per-product create**, and **local classification + batched
Odoo reads**.

## Schedule

The container itself just stays alive (`tail -f /dev/null`).
The schedule is configured in **Coolify -> Application -> Scheduled Tasks**:

| Field | Value |
| --- | --- |
| Name | `worten-autoposting-daily` |
| Command | `python /app/script.py` |
| Frequency | `30 6 * * *` |
| Timezone | `Europe/Kiev` |

Coolify runs the command via `docker exec` inside the running container. Logs go to the
**Scheduled Tasks -> Logs** tab in the UI.

## Required environment variables

| Variable | Description |
| --- | --- |
| `ODOO_URL` | Odoo JSON-RPC endpoint, e.g. `https://odoo.boni.tools/jsonrpc` |
| `ODOO_DB` | Odoo database name |
| `ODOO_UID` | Odoo user id |
| `ODOO_API_KEY` | Odoo API key |
| `WORTEN_BASE_URL` | `https://marketplace.worten.pt` |
| `WORTEN_API_KEY` | Mirakl API key |
| `WORTEN_SHOP_ID` | `5553` |

Optional:

| Variable | Default |
| --- | --- |
| `BATCH_LIMIT` | `0` (no limit) |
| `BITRIX_WEBHOOK` | hardcoded production webhook |
| `ALERT_ACCOMPLICE_ID` | `584` |

Set these in Coolify -> Application -> Environment Variables. Never commit `.env`.

## Manual run (debug)

Inside the container:

```bash
docker exec -it <container> python /app/script.py
```

Or trigger a fresh deploy via Coolify API:

```bash
curl -s -X POST "$COOLIFY_BASE/deploy?uuid=$APP_UUID&force=true" \
  -H "Authorization: Bearer $COOLIFY_TOKEN"
```

## Local files

- `script.py` — the autoposting logic (resources read from env)
- `requirements.txt` — `aiohttp`, `requests`, `openpyxl`
- `Dockerfile` — `python:3.12-slim`, container stays alive; schedule is in Coolify UI
