const std = @import("std");

// ISO 7816-4 APDU (Application Protocol Data Unit) building and parsing.

// Command APDU header fields.
pub const CommandHeader = struct {
    cla: u8, // Class byte
    ins: u8, // Instruction byte
    p1: u8, // Parameter 1
    p2: u8, // Parameter 2
};

// Standard instruction bytes (ISO 7816-4, Table 4).
pub const INS = struct {
    pub const SELECT: u8 = 0xA4;
    pub const READ_BINARY: u8 = 0xB0;
    pub const READ_RECORD: u8 = 0xB2;
    pub const GET_RESPONSE: u8 = 0xC0;
    pub const WRITE_BINARY: u8 = 0xD0;
    pub const UPDATE_BINARY: u8 = 0xD6;
    pub const PUT_DATA: u8 = 0xDA;
    pub const APPEND_RECORD: u8 = 0xE2;
    pub const UPDATE_RECORD: u8 = 0xDC;
    pub const GET_DATA: u8 = 0xCA;
    pub const VERIFY: u8 = 0x20;
    pub const INTERNAL_AUTHENTICATE: u8 = 0x88;
    pub const EXTERNAL_AUTHENTICATE: u8 = 0x82;
    pub const MANAGE_SECURITY_ENVIRONMENT: u8 = 0x22;
    pub const PERFORM_SECURITY_OPERATION: u8 = 0x2A;
    pub const CHANGE_REFERENCE_DATA: u8 = 0x24;
    pub const RESET_RETRY_COUNTER: u8 = 0x2C;
};

// Status word categories.
pub const SW = struct {
    pub const SUCCESS: u16 = 0x9000;

    pub fn isSuccess(sw1: u8, sw2: u8) bool {
        return sw1 == 0x90 and sw2 == 0x00;
    }

    pub fn hasMoreData(sw1: u8) bool {
        return sw1 == 0x61;
    }

    pub fn remainingBytes(sw1: u8, sw2: u8) ?u8 {
        if (hasMoreData(sw1)) return sw2;
        return null;
    }

    pub fn isWarning(sw1: u8) bool {
        return sw1 == 0x62 or sw1 == 0x63;
    }

    pub fn isError(sw1: u8) bool {
        return sw1 == 0x64 or sw1 == 0x65 or
            sw1 == 0x67 or sw1 == 0x68 or
            sw1 == 0x69 or sw1 == 0x6A or
            sw1 == 0x6B or sw1 == 0x6C or
            sw1 == 0x6D or sw1 == 0x6E or
            sw1 == 0x6F;
    }

    pub fn wrongLength(sw1: u8, sw2: u8) ?u8 {
        if (sw1 == 0x6C) return sw2;
        return null;
    }

    pub fn toU16(sw1: u8, sw2: u8) u16 {
        return @as(u16, sw1) << 8 | sw2;
    }
};

// A parsed response APDU.
pub const Response = struct {
    data: []const u8,
    sw1: u8,
    sw2: u8,

    pub fn parse(raw: []const u8) error{ResponseTooShort}!Response {
        if (raw.len < 2) return error.ResponseTooShort;
        return .{
            .data = raw[0 .. raw.len - 2],
            .sw1 = raw[raw.len - 2],
            .sw2 = raw[raw.len - 1],
        };
    }

    pub fn sw(self: Response) u16 {
        return SW.toU16(self.sw1, self.sw2);
    }

    pub fn isSuccess(self: Response) bool {
        return SW.isSuccess(self.sw1, self.sw2);
    }
};

// Command APDU builder.
//
// Supports all four ISO 7816-4 command cases:
//   Case 1: Header only (no data, no Le)
//   Case 2: Header + Le (no data, expects response)
//   Case 3: Header + Lc + data (no Le)
//   Case 4: Header + Lc + data + Le
//
// Only short encoding (Lc/Le in one byte, max 255) is supported.
pub const Command = struct {
    header: CommandHeader,
    data: []const u8 = &.{},
    le: ?u16 = null,

    // Convenience constructors for common commands.

    pub fn select(data: []const u8) Command {
        return .{
            .header = .{ .cla = 0x00, .ins = INS.SELECT, .p1 = 0x04, .p2 = 0x00 },
            .data = data,
        };
    }

    pub fn readBinary(offset: u16, le: u8) Command {
        return .{
            .header = .{
                .cla = 0x00,
                .ins = INS.READ_BINARY,
                .p1 = @intCast(offset >> 8),
                .p2 = @intCast(offset & 0xFF),
            },
            .le = le,
        };
    }

    pub fn getResponse(le: u8) Command {
        return .{
            .header = .{ .cla = 0x00, .ins = INS.GET_RESPONSE, .p1 = 0x00, .p2 = 0x00 },
            .le = le,
        };
    }

    pub fn getData(tag_hi: u8, tag_lo: u8, le: u8) Command {
        return .{
            .header = .{ .cla = 0x00, .ins = INS.GET_DATA, .p1 = tag_hi, .p2 = tag_lo },
            .le = le,
        };
    }

    pub fn verify(p2: u8, pin: []const u8) Command {
        return .{
            .header = .{ .cla = 0x00, .ins = INS.VERIFY, .p1 = 0x00, .p2 = p2 },
            .data = pin,
        };
    }

    // Encode the command APDU into the provided buffer.
    // Returns the slice of buf that was written.
    pub fn encode(self: Command, buf: []u8) error{BufferTooSmall}![]u8 {
        const needed = self.encodedLen();
        if (buf.len < needed) return error.BufferTooSmall;

        buf[0] = self.header.cla;
        buf[1] = self.header.ins;
        buf[2] = self.header.p1;
        buf[3] = self.header.p2;

        var pos: usize = 4;

        if (self.data.len > 0) {
            buf[pos] = @intCast(self.data.len);
            pos += 1;
            @memcpy(buf[pos..][0..self.data.len], self.data);
            pos += self.data.len;
        }

        if (self.le) |le| {
            buf[pos] = @intCast(le & 0xFF);
            pos += 1;
        }

        return buf[0..pos];
    }

    pub fn encodedLen(self: Command) usize {
        var len: usize = 4; // header
        if (self.data.len > 0) {
            len += 1 + self.data.len; // Lc + data
        }
        if (self.le != null) {
            len += 1; // Le
        }
        return len;
    }
};

test "command case 1: header only" {
    const cmd = Command{
        .header = .{ .cla = 0x00, .ins = 0xA4, .p1 = 0x04, .p2 = 0x00 },
    };
    var buf: [256]u8 = undefined;
    const encoded = try cmd.encode(&buf);
    try std.testing.expectEqualSlices(u8, &.{ 0x00, 0xA4, 0x04, 0x00 }, encoded);
    try std.testing.expectEqual(@as(usize, 4), cmd.encodedLen());
}

test "command case 2: header + Le" {
    const cmd = Command.getResponse(0x10);
    var buf: [256]u8 = undefined;
    const encoded = try cmd.encode(&buf);
    try std.testing.expectEqualSlices(u8, &.{ 0x00, 0xC0, 0x00, 0x00, 0x10 }, encoded);
    try std.testing.expectEqual(@as(usize, 5), cmd.encodedLen());
}

test "command case 3: header + Lc + data" {
    const aid = [_]u8{ 0xA0, 0x00, 0x00, 0x00, 0x30 };
    const cmd = Command.select(&aid);
    var buf: [256]u8 = undefined;
    const encoded = try cmd.encode(&buf);
    try std.testing.expectEqualSlices(u8, &.{
        0x00, 0xA4, 0x04, 0x00, // header
        0x05, // Lc
        0xA0, 0x00, 0x00, 0x00, 0x30, // data
    }, encoded);
    try std.testing.expectEqual(@as(usize, 10), cmd.encodedLen());
}

test "command case 4: header + Lc + data + Le" {
    const cmd = Command{
        .header = .{ .cla = 0x00, .ins = INS.SELECT, .p1 = 0x04, .p2 = 0x00 },
        .data = &.{ 0xA0, 0x00 },
        .le = 0x00,
    };
    var buf: [256]u8 = undefined;
    const encoded = try cmd.encode(&buf);
    try std.testing.expectEqualSlices(u8, &.{
        0x00, 0xA4, 0x04, 0x00, // header
        0x02, // Lc
        0xA0, 0x00, // data
        0x00, // Le (0 = 256)
    }, encoded);
    try std.testing.expectEqual(@as(usize, 8), cmd.encodedLen());
}

test "readBinary" {
    const cmd = Command.readBinary(0x0100, 0xFF);
    var buf: [256]u8 = undefined;
    const encoded = try cmd.encode(&buf);
    try std.testing.expectEqualSlices(u8, &.{ 0x00, 0xB0, 0x01, 0x00, 0xFF }, encoded);
}

test "getData" {
    const cmd = Command.getData(0x00, 0x6E, 0x00);
    var buf: [256]u8 = undefined;
    const encoded = try cmd.encode(&buf);
    try std.testing.expectEqualSlices(u8, &.{ 0x00, 0xCA, 0x00, 0x6E, 0x00 }, encoded);
}

test "verify PIN" {
    const pin = [_]u8{ 0x31, 0x32, 0x33, 0x34 }; // "1234"
    const cmd = Command.verify(0x01, &pin);
    var buf: [256]u8 = undefined;
    const encoded = try cmd.encode(&buf);
    try std.testing.expectEqualSlices(u8, &.{
        0x00, 0x20, 0x00, 0x01, // header
        0x04, // Lc
        0x31, 0x32, 0x33, 0x34, // PIN
    }, encoded);
}

test "encode buffer too small" {
    const cmd = Command.getResponse(0x10);
    var buf: [3]u8 = undefined;
    const result = cmd.encode(&buf);
    try std.testing.expectError(error.BufferTooSmall, result);
}

test "response parse success" {
    const raw = [_]u8{ 0x01, 0x02, 0x03, 0x90, 0x00 };
    const resp = try Response.parse(&raw);
    try std.testing.expectEqualSlices(u8, &.{ 0x01, 0x02, 0x03 }, resp.data);
    try std.testing.expectEqual(@as(u16, 0x9000), resp.sw());
    try std.testing.expect(resp.isSuccess());
}

test "response parse status only" {
    const raw = [_]u8{ 0x6A, 0x82 };
    const resp = try Response.parse(&raw);
    try std.testing.expectEqual(@as(usize, 0), resp.data.len);
    try std.testing.expectEqual(@as(u16, 0x6A82), resp.sw());
    try std.testing.expect(!resp.isSuccess());
}

test "response parse too short" {
    const raw = [_]u8{0x90};
    try std.testing.expectError(error.ResponseTooShort, Response.parse(&raw));
    try std.testing.expectError(error.ResponseTooShort, Response.parse(&.{}));
}

test "SW helpers" {
    try std.testing.expect(SW.isSuccess(0x90, 0x00));
    try std.testing.expect(!SW.isSuccess(0x90, 0x01));

    try std.testing.expect(SW.hasMoreData(0x61));
    try std.testing.expectEqual(@as(?u8, 0x20), SW.remainingBytes(0x61, 0x20));
    try std.testing.expectEqual(@as(?u8, null), SW.remainingBytes(0x90, 0x00));

    try std.testing.expect(SW.isWarning(0x62));
    try std.testing.expect(SW.isWarning(0x63));
    try std.testing.expect(!SW.isWarning(0x90));

    try std.testing.expect(SW.isError(0x6A));
    try std.testing.expect(!SW.isError(0x90));

    try std.testing.expectEqual(@as(?u8, 0x10), SW.wrongLength(0x6C, 0x10));
    try std.testing.expectEqual(@as(?u8, null), SW.wrongLength(0x90, 0x00));
}
