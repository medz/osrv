# Node HTTP Host

## Purpose

This document defines the current Node host entry used by `osrv`.

The selected host entry is:

- `node:http`
- `createServer((req, res) => ...)`

This is the serving surface that backs the current `node` runtime family.

## Why This Entry

This host entry gives `osrv` one concrete and official Node serving shape:
- request receipt
- response writing
- listen/close lifecycle
- streaming bodies

Official references:
- Node HTTP docs: [nodejs.org/api/http.html](https://nodejs.org/api/http.html)
- `http.createServer(...)`: [nodejs.org/api/http.html#httpcreateserveroptions-requestlistener](https://nodejs.org/api/http.html#httpcreateserveroptions-requestlistener)
- `http.IncomingMessage`: [nodejs.org/api/http.html#class-httpincomingmessage](https://nodejs.org/api/http.html#class-httpincomingmessage)
- `http.ServerResponse`: [nodejs.org/api/http.html#class-httpserverresponse](https://nodejs.org/api/http.html#class-httpserverresponse)

## Current Host Types

The current Node HTTP host layer models these objects:
- HTTP module
- HTTP server
- incoming request
- outgoing response

Current members used by `osrv`:

### HTTP Module

- `createServer`

### HTTP Server

- `listen`
- `close`
- `on`
- `address`

### Incoming Request

- `method`
- `url`
- `headers`
- `on`
- `once`

### Outgoing Response

- `statusCode`
- `statusMessage`
- `setHeader`
- `once`
- `write`
- `end`

## Current Serving Flow

The current serving path is:

```text
node:http
  -> createServer((req, res) => ...)
  -> nodeRequestFromHost(...)
  -> Server.fetch(...)
  -> writeHtResponseToNodeServerResponse(...)
```

This is no longer just a selected direction.
It is the actual implementation boundary.

## What The Host Layer Is Responsible For

The host layer is responsible for:
- locating `node:http`
- creating and listening on the Node server
- reading request events
- writing response events
- surfacing host errors during request and response IO

It is not responsible for:
- business routing
- app semantics
- `Server.fetch` behavior

## Current Limits

The host layer still does not cover:
- websocket upgrades
- raw socket escape hatches
- advanced timeout tuning
- trailers
- compression policy
- full event-emitter exposure to upper layers
