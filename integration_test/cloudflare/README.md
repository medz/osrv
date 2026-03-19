## Cloudflare Integration

`integration_test/cloudflare/app/` is the single Cloudflare Worker fixture used
for both automated process tests and manual local e2e checks.

Manual verification lives alongside that app so it exercises the same
`wrangler dev --local` setup as CI:

```sh
integration_test/cloudflare/app/manual_e2e.sh
```

That script will:

- build the worker bundle;
- start `wrangler dev --local`;
- verify `GET /hello`;
- connect to `/chat`;
- verify websocket echo plus a clean close handshake.
