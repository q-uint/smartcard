const std = @import("std");
const builtin = @import("builtin");
const native_os = builtin.os.tag;

// Platform-specific PC/SC types.
// macOS PCSC.framework uses fixed 32-bit types.
// Linux pcsclite uses C long/unsigned long (64-bit on LP64).
// Windows winscard uses ULONG_PTR for handles, 32-bit LONG/DWORD.

pub const LONG = switch (native_os) {
    .macos => i32,
    .linux => c_long,
    .windows => c_long,
    else => @compileError("unsupported platform for PC/SC"),
};

pub const DWORD = switch (native_os) {
    .macos => u32,
    .linux => c_ulong,
    .windows => c_ulong,
    else => @compileError("unsupported platform for PC/SC"),
};

pub const SCARDCONTEXT = switch (native_os) {
    .macos => i32,
    .linux => c_long,
    .windows => usize,
    else => @compileError("unsupported platform for PC/SC"),
};

pub const SCARDHANDLE = switch (native_os) {
    .macos => i32,
    .linux => c_long,
    .windows => usize,
    else => @compileError("unsupported platform for PC/SC"),
};

pub const BYTE = u8;
pub const LPSTR = [*:0]u8;
pub const LPCSTR = [*:0]const u8;
pub const LPBYTE = [*]BYTE;
pub const LPCBYTE = [*]const BYTE;
pub const LPDWORD = *DWORD;
pub const LPVOID = *anyopaque;
pub const LPCVOID = *const anyopaque;
pub const LPSCARDCONTEXT = *SCARDCONTEXT;
pub const LPSCARDHANDLE = *SCARDHANDLE;

const MAX_ATR_SIZE = if (native_os == .linux) 33 else 36;

pub const SCARD_IO_REQUEST = extern struct {
    dwProtocol: DWORD,
    cbPciLength: DWORD,
};

pub const SCARD_READERSTATE = extern struct {
    szReader: LPCSTR,
    pvUserData: ?LPVOID,
    dwCurrentState: DWORD,
    dwEventState: DWORD,
    cbAtr: DWORD,
    rgbAtr: [MAX_ATR_SIZE]BYTE,
};

// Scope values for SCardEstablishContext.
pub const SCARD_SCOPE_USER: DWORD = 0x0000;
pub const SCARD_SCOPE_TERMINAL: DWORD = 0x0001;
pub const SCARD_SCOPE_SYSTEM: DWORD = 0x0002;

// Share mode values for SCardConnect.
pub const SCARD_SHARE_EXCLUSIVE: DWORD = 0x0001;
pub const SCARD_SHARE_SHARED: DWORD = 0x0002;
pub const SCARD_SHARE_DIRECT: DWORD = 0x0003;

// Protocol values.
pub const SCARD_PROTOCOL_T0: DWORD = 0x0001;
pub const SCARD_PROTOCOL_T1: DWORD = 0x0002;
pub const SCARD_PROTOCOL_RAW: DWORD = 0x0004;
pub const SCARD_PROTOCOL_ANY: DWORD = SCARD_PROTOCOL_T0 | SCARD_PROTOCOL_T1;

// Disposition values for SCardDisconnect.
pub const SCARD_LEAVE_CARD: DWORD = 0x0000;
pub const SCARD_RESET_CARD: DWORD = 0x0001;
pub const SCARD_UNPOWER_CARD: DWORD = 0x0002;
pub const SCARD_EJECT_CARD: DWORD = 0x0003;

// Reader state flags.
pub const SCARD_STATE_UNAWARE: DWORD = 0x0000;
pub const SCARD_STATE_IGNORE: DWORD = 0x0001;
pub const SCARD_STATE_CHANGED: DWORD = 0x0002;
pub const SCARD_STATE_UNKNOWN: DWORD = 0x0004;
pub const SCARD_STATE_UNAVAILABLE: DWORD = 0x0008;
pub const SCARD_STATE_EMPTY: DWORD = 0x0010;
pub const SCARD_STATE_PRESENT: DWORD = 0x0020;
pub const SCARD_STATE_ATRMATCH: DWORD = 0x0040;
pub const SCARD_STATE_EXCLUSIVE: DWORD = 0x0080;
pub const SCARD_STATE_INUSE: DWORD = 0x0100;
pub const SCARD_STATE_MUTE: DWORD = 0x0200;

// Return values.
// On macOS/Windows LONG is 32-bit so high-bit codes need @bitCast.
// On Linux LONG is 64-bit so the values fit as positive integers.
fn scardCode(comptime val: u32) LONG {
    return if (@bitSizeOf(LONG) == @bitSizeOf(u32))
        @bitCast(val)
    else
        @intCast(val);
}

pub const SCARD_S_SUCCESS: LONG = 0x00000000;
pub const SCARD_F_INTERNAL_ERROR: LONG = scardCode(0x80100001);
pub const SCARD_E_CANCELLED: LONG = scardCode(0x80100002);
pub const SCARD_E_INVALID_HANDLE: LONG = scardCode(0x80100003);
pub const SCARD_E_INVALID_PARAMETER: LONG = scardCode(0x80100004);
pub const SCARD_E_INVALID_TARGET: LONG = scardCode(0x80100005);
pub const SCARD_E_NO_MEMORY: LONG = scardCode(0x80100006);
pub const SCARD_E_INSUFFICIENT_BUFFER: LONG = scardCode(0x80100008);
pub const SCARD_E_UNKNOWN_READER: LONG = scardCode(0x80100009);
pub const SCARD_E_TIMEOUT: LONG = scardCode(0x8010000A);
pub const SCARD_E_SHARING_VIOLATION: LONG = scardCode(0x8010000B);
pub const SCARD_E_NO_SMARTCARD: LONG = scardCode(0x8010000C);
pub const SCARD_E_UNKNOWN_CARD: LONG = scardCode(0x8010000D);
pub const SCARD_E_PROTO_MISMATCH: LONG = scardCode(0x8010000F);
pub const SCARD_E_NOT_READY: LONG = scardCode(0x80100010);
pub const SCARD_E_INVALID_VALUE: LONG = scardCode(0x80100011);
pub const SCARD_E_READER_UNAVAILABLE: LONG = scardCode(0x80100017);
pub const SCARD_E_NO_SERVICE: LONG = scardCode(0x8010001D);
pub const SCARD_E_SERVICE_STOPPED: LONG = scardCode(0x8010001E);
pub const SCARD_E_NO_READERS_AVAILABLE: LONG = scardCode(0x8010002E);
pub const SCARD_W_UNSUPPORTED_CARD: LONG = scardCode(0x80100065);
pub const SCARD_W_UNRESPONSIVE_CARD: LONG = scardCode(0x80100066);
pub const SCARD_W_UNPOWERED_CARD: LONG = scardCode(0x80100067);
pub const SCARD_W_RESET_CARD: LONG = scardCode(0x80100068);
pub const SCARD_W_REMOVED_CARD: LONG = scardCode(0x80100069);

// Imported functions from the platform PC/SC library.
const pcsc = switch (native_os) {
    .macos => struct {
        extern "PCSC" fn SCardEstablishContext(dwScope: DWORD, pvReserved1: ?LPCVOID, pvReserved2: ?LPCVOID, phContext: LPSCARDCONTEXT) callconv(.c) LONG;
        extern "PCSC" fn SCardReleaseContext(hContext: SCARDCONTEXT) callconv(.c) LONG;
        extern "PCSC" fn SCardListReaders(hContext: SCARDCONTEXT, mszGroups: ?LPCSTR, mszReaders: ?[*]u8, pcchReaders: LPDWORD) callconv(.c) LONG;
        extern "PCSC" fn SCardConnect(hContext: SCARDCONTEXT, szReader: LPCSTR, dwShareMode: DWORD, dwPreferredProtocols: DWORD, phCard: LPSCARDHANDLE, pdwActiveProtocol: LPDWORD) callconv(.c) LONG;
        extern "PCSC" fn SCardDisconnect(hCard: SCARDHANDLE, dwDisposition: DWORD) callconv(.c) LONG;
        extern "PCSC" fn SCardTransmit(hCard: SCARDHANDLE, pioSendPci: *const SCARD_IO_REQUEST, pbSendBuffer: LPCBYTE, cbSendLength: DWORD, pioRecvPci: ?*SCARD_IO_REQUEST, pbRecvBuffer: LPBYTE, pcbRecvLength: LPDWORD) callconv(.c) LONG;
        extern "PCSC" fn SCardGetStatusChange(hContext: SCARDCONTEXT, dwTimeout: DWORD, rgReaderStates: [*]SCARD_READERSTATE, cReaders: DWORD) callconv(.c) LONG;
    },
    .linux => struct {
        extern "pcsclite" fn SCardEstablishContext(dwScope: DWORD, pvReserved1: ?LPCVOID, pvReserved2: ?LPCVOID, phContext: LPSCARDCONTEXT) callconv(.c) LONG;
        extern "pcsclite" fn SCardReleaseContext(hContext: SCARDCONTEXT) callconv(.c) LONG;
        extern "pcsclite" fn SCardListReaders(hContext: SCARDCONTEXT, mszGroups: ?LPCSTR, mszReaders: ?[*]u8, pcchReaders: LPDWORD) callconv(.c) LONG;
        extern "pcsclite" fn SCardConnect(hContext: SCARDCONTEXT, szReader: LPCSTR, dwShareMode: DWORD, dwPreferredProtocols: DWORD, phCard: LPSCARDHANDLE, pdwActiveProtocol: LPDWORD) callconv(.c) LONG;
        extern "pcsclite" fn SCardDisconnect(hCard: SCARDHANDLE, dwDisposition: DWORD) callconv(.c) LONG;
        extern "pcsclite" fn SCardTransmit(hCard: SCARDHANDLE, pioSendPci: *const SCARD_IO_REQUEST, pbSendBuffer: LPCBYTE, cbSendLength: DWORD, pioRecvPci: ?*SCARD_IO_REQUEST, pbRecvBuffer: LPBYTE, pcbRecvLength: LPDWORD) callconv(.c) LONG;
        extern "pcsclite" fn SCardGetStatusChange(hContext: SCARDCONTEXT, dwTimeout: DWORD, rgReaderStates: [*]SCARD_READERSTATE, cReaders: DWORD) callconv(.c) LONG;
    },
    .windows => struct {
        // Windows SCard functions that take strings are exported with A/W
        // suffixes. We use the ANSI (A) variants since our types use u8.
        extern "winscard" fn SCardEstablishContext(dwScope: DWORD, pvReserved1: ?LPCVOID, pvReserved2: ?LPCVOID, phContext: LPSCARDCONTEXT) callconv(.c) LONG;
        extern "winscard" fn SCardReleaseContext(hContext: SCARDCONTEXT) callconv(.c) LONG;
        extern "winscard" fn SCardListReadersA(hContext: SCARDCONTEXT, mszGroups: ?LPCSTR, mszReaders: ?[*]u8, pcchReaders: LPDWORD) callconv(.c) LONG;
        extern "winscard" fn SCardConnectA(hContext: SCARDCONTEXT, szReader: LPCSTR, dwShareMode: DWORD, dwPreferredProtocols: DWORD, phCard: LPSCARDHANDLE, pdwActiveProtocol: LPDWORD) callconv(.c) LONG;
        extern "winscard" fn SCardDisconnect(hCard: SCARDHANDLE, dwDisposition: DWORD) callconv(.c) LONG;
        extern "winscard" fn SCardTransmit(hCard: SCARDHANDLE, pioSendPci: *const SCARD_IO_REQUEST, pbSendBuffer: LPCBYTE, cbSendLength: DWORD, pioRecvPci: ?*SCARD_IO_REQUEST, pbRecvBuffer: LPBYTE, pcbRecvLength: LPDWORD) callconv(.c) LONG;
        extern "winscard" fn SCardGetStatusChangeA(hContext: SCARDCONTEXT, dwTimeout: DWORD, rgReaderStates: [*]SCARD_READERSTATE, cReaders: DWORD) callconv(.c) LONG;

        const SCardListReaders = SCardListReadersA;
        const SCardConnect = SCardConnectA;
        const SCardGetStatusChange = SCardGetStatusChangeA;
    },
    else => @compileError("unsupported platform for PC/SC"),
};

pub const SCARD_PCI_T0 = SCARD_IO_REQUEST{ .dwProtocol = SCARD_PROTOCOL_T0, .cbPciLength = @sizeOf(SCARD_IO_REQUEST) };
pub const SCARD_PCI_T1 = SCARD_IO_REQUEST{ .dwProtocol = SCARD_PROTOCOL_T1, .cbPciLength = @sizeOf(SCARD_IO_REQUEST) };

pub const Context = struct {
    handle: SCARDCONTEXT,

    pub fn establish(scope: DWORD) !Context {
        var ctx: SCARDCONTEXT = undefined;
        const rv = pcsc.SCardEstablishContext(scope, null, null, &ctx);
        if (rv != SCARD_S_SUCCESS) return error.EstablishContextFailed;
        return .{ .handle = ctx };
    }

    pub fn release(self: Context) void {
        _ = pcsc.SCardReleaseContext(self.handle);
    }

    pub const ReaderList = struct {
        names: []const [:0]const u8,
        buf: []u8,
        allocator: std.mem.Allocator,

        pub fn deinit(self: *ReaderList) void {
            self.allocator.free(self.names);
            self.allocator.free(self.buf);
            self.* = undefined;
        }
    };

    pub fn listReaders(self: Context, allocator: std.mem.Allocator) !ReaderList {
        var len: DWORD = 0;
        var rv = pcsc.SCardListReaders(self.handle, null, null, &len);
        if (rv != SCARD_S_SUCCESS) return error.ListReadersFailed;
        if (len == 0) return .{ .names = &.{}, .buf = &.{}, .allocator = allocator };

        const buf = try allocator.alloc(u8, len);
        errdefer allocator.free(buf);
        rv = pcsc.SCardListReaders(self.handle, null, buf.ptr, &len);
        if (rv != SCARD_S_SUCCESS) return error.ListReadersFailed;

        // Multi-string: null-separated, double-null terminated.
        var readers: std.ArrayListUnmanaged([:0]const u8) = .empty;
        errdefer readers.deinit(allocator);
        var start: usize = 0;
        for (buf[0..len], 0..) |c, i| {
            if (c == 0) {
                if (i == start) break;
                try readers.append(allocator, buf[start..i :0]);
                start = i + 1;
            }
        }
        return .{
            .names = try readers.toOwnedSlice(allocator),
            .buf = buf,
            .allocator = allocator,
        };
    }

    pub fn connect(self: Context, reader: [:0]const u8, share_mode: DWORD, preferred_protocols: DWORD) !Card {
        var card_handle: SCARDHANDLE = undefined;
        var active_protocol: DWORD = 0;
        const rv = pcsc.SCardConnect(self.handle, reader.ptr, share_mode, preferred_protocols, &card_handle, &active_protocol);
        if (rv != SCARD_S_SUCCESS) return error.ConnectFailed;
        return .{
            .handle = card_handle,
            .active_protocol = active_protocol,
        };
    }
};

pub const Card = struct {
    handle: SCARDHANDLE,
    active_protocol: DWORD,

    pub fn disconnect(self: Card, disposition: DWORD) void {
        _ = pcsc.SCardDisconnect(self.handle, disposition);
    }

    pub fn transmit(self: Card, send: []const u8, recv_buf: []u8) ![]u8 {
        const pci = if (self.active_protocol == SCARD_PROTOCOL_T0)
            &SCARD_PCI_T0
        else
            &SCARD_PCI_T1;
        var recv_len: DWORD = @intCast(recv_buf.len);
        const rv = pcsc.SCardTransmit(self.handle, pci, send.ptr, @intCast(send.len), null, recv_buf.ptr, &recv_len);
        if (rv != SCARD_S_SUCCESS) return error.TransmitFailed;
        return recv_buf[0..recv_len];
    }

    pub fn sw(response: []const u8) [2]u8 {
        if (response.len < 2) return .{ 0, 0 };
        return .{ response[response.len - 2], response[response.len - 1] };
    }
};

test "establish context and list readers" {
    const ctx = Context.establish(SCARD_SCOPE_SYSTEM) catch return;
    defer ctx.release();

    var readers = ctx.listReaders(std.testing.allocator) catch |err| {
        if (err == error.ListReadersFailed) return;
        return err;
    };
    defer readers.deinit();
}
