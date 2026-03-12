# smartcard

Experimental Zig library for smart card communication on macOS. This is a personal project for playing around with card readers and is provided as-is with no guarantees.

- **pcsc** -- direct card access via macOS PCSC.framework (no dependencies)
- **pkcs11** -- bindings for [PKCS#11](https://docs.oasis-open.org/pkcs11/pkcs11-spec/v3.1/os/pkcs11-spec-v3.1-os.html) v3.1 middleware

## Platform

macOS only (aarch64-darwin). Links against the built-in PCSC.framework.

## Usage

### PC/SC (direct card access)

```zig
const pcsc = @import("smartcard").pcsc;

const ctx = try pcsc.Context.establish(pcsc.SCARD_SCOPE_SYSTEM);
defer ctx.release();

const readers = try ctx.listReaders(allocator);
const card = try ctx.connect(readers[0], pcsc.SCARD_SHARE_SHARED, pcsc.SCARD_PROTOCOL_ANY);
defer card.disconnect(pcsc.SCARD_LEAVE_CARD);

// Send an APDU
var recv_buf: [256]u8 = undefined;
const response = try card.transmit(&apdu, &recv_buf);
```

### PKCS#11 (middleware)

```zig
const pkcs11 = @import("smartcard").pkcs11;

var lib = try pkcs11.Library.load("/path/to/pkcs11-middleware.so");
defer lib.close();

try lib.initialize(null);
defer lib.finalize() catch {};

const info = try lib.getInfo();
```

## Testing

```sh
zig build test
```

PKCS#11 tests run against [SoftHSM2](https://github.com/opendnssec/SoftHSMv2) if available. If `softhsm2-util` is not on PATH, those tests are skipped.
