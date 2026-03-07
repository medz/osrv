# Node Request Bridge

## Purpose

This document defines the current request bridge for the `node` runtime family.

The request bridge is now implemented.
It no longer stops at request-head extraction.

## Current Shape

The current bridge does all of the following:
- reads method from `IncomingMessage`
- reads URL from `IncomingMessage`
- reads raw headers from `IncomingMessage`
- resolves the request URL against the active listener origin
- bridges the request body into `ht.Request`
- preserves stream bodies
- propagates request `error` and `aborted` failures

Conceptually:

```text
IncomingMessage
  -> nodeRequestHeadFromHost(...)
  -> nodeRequestFromHost(...)
  -> ht.Request
```

## Body Behavior

Current body behavior is:
- `null` when the request has no body
- `String` and `List<int>` when materialized bodies are used in stub tests
- `Stream<List<int>>` on the real Node host path

This distinction matters because:
- `GET` requests must not be forced into fake empty-body requests
- real Node request bodies should remain stream-based

## Header Behavior

Current header normalization is intentionally conservative:
- string header values are preserved
- `List<String>` header values are preserved
- unsupported raw header shapes are ignored at the bridge layer

This keeps the portable `ht` request model clean without pretending every host header shape is meaningful.

## Failure Behavior

Current failure behavior:
- `readNodeIncomingMessageBody(...)` may fail before `nodeRequestFromHost(...)`
  finishes constructing the `ht.Request`
- request body `error` can become a Dart error on the bridged request body stream
- request `aborted` can become a Dart error on the bridged request body stream
- in practice, failures can surface either during bridge creation or later while
  the request body is being consumed

## Why This Boundary Matters

This bridge keeps Node host values below the `Server.fetch(...)` contract.

Upper layers see:
- `ht.Request`
- `RequestContext`

They do not see:
- raw Node `IncomingMessage`
- JS interop objects

## Current Limits

Still not covered explicitly:
- multipart-aware host optimizations
- raw socket upgrade paths
- Node-specific request metadata beyond the current extension surface
