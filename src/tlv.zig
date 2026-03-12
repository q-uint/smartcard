const std = @import("std");

// BER-TLV (Basic Encoding Rules - Tag Length Value) as used in ISO 7816-4.

pub const Tag = struct {
    bytes: []const u8,

    pub fn class(self: Tag) Class {
        return @enumFromInt((self.bytes[0] >> 6) & 0x03);
    }

    pub fn isConstructed(self: Tag) bool {
        return (self.bytes[0] & 0x20) != 0;
    }

    pub fn number(self: Tag) u28 {
        if ((self.bytes[0] & 0x1F) != 0x1F) {
            return @intCast(self.bytes[0] & 0x1F);
        }
        var n: u28 = 0;
        for (self.bytes[1..]) |b| {
            n = (n << 7) | @as(u28, b & 0x7F);
            if (b & 0x80 == 0) break;
        }
        return n;
    }

    pub fn eql(self: Tag, other: Tag) bool {
        return std.mem.eql(u8, self.bytes, other.bytes);
    }

    pub const Class = enum(u2) {
        universal = 0,
        application = 1,
        context_specific = 2,
        private = 3,
    };
};

pub const Node = struct {
    tag: Tag,
    value: []const u8,

    pub fn children(self: Node) Iterator {
        if (!self.tag.isConstructed()) return .{ .data = &.{} };
        return .{ .data = self.value };
    }

    pub fn find(self: Node, tag_bytes: []const u8) ?Node {
        const needle = Tag{ .bytes = tag_bytes };
        var it = self.children();
        while (it.next()) |child| {
            if (child.tag.eql(needle)) return child;
        }
        return null;
    }
};

// Parse a single tag from the beginning of data.
// Returns the tag and the number of bytes consumed.
fn parseTag(data: []const u8) error{InvalidTlv}!struct { Tag, usize } {
    if (data.len == 0) return error.InvalidTlv;
    if ((data[0] & 0x1F) != 0x1F) {
        return .{ Tag{ .bytes = data[0..1] }, 1 };
    }
    // Multi-byte tag.
    var i: usize = 1;
    while (i < data.len) : (i += 1) {
        if (data[i] & 0x80 == 0) {
            i += 1;
            return .{ Tag{ .bytes = data[0..i] }, i };
        }
    }
    return error.InvalidTlv;
}

// Parse the length field.
// Returns the length value and number of bytes consumed.
fn parseLength(data: []const u8) error{InvalidTlv}!struct { usize, usize } {
    if (data.len == 0) return error.InvalidTlv;
    if (data[0] < 0x80) {
        return .{ data[0], 1 };
    }
    if (data[0] == 0x80) {
        // Indefinite length not supported.
        return error.InvalidTlv;
    }
    const n = data[0] & 0x7F;
    if (n > 4 or 1 + n > data.len) return error.InvalidTlv;
    var len: usize = 0;
    for (data[1 .. 1 + n]) |b| {
        len = (len << 8) | b;
    }
    return .{ len, 1 + n };
}

// Parse one TLV node from the beginning of data.
// Returns the node and the total bytes consumed.
pub fn parseNode(data: []const u8) error{InvalidTlv}!struct { Node, usize } {
    const tag_result = try parseTag(data);
    const tag = tag_result[0];
    const tag_len = tag_result[1];

    const len_result = try parseLength(data[tag_len..]);
    const value_len = len_result[0];
    const len_bytes = len_result[1];

    const total = tag_len + len_bytes + value_len;
    if (total > data.len) return error.InvalidTlv;

    const value_start = tag_len + len_bytes;
    return .{
        Node{ .tag = tag, .value = data[value_start..total] },
        total,
    };
}

// Iterator over consecutive TLV nodes in a byte slice.
pub const Iterator = struct {
    data: []const u8,
    pos: usize = 0,

    pub fn next(self: *Iterator) ?Node {
        if (self.pos >= self.data.len) return null;
        const result = parseNode(self.data[self.pos..]) catch return null;
        self.pos += result[1];
        return result[0];
    }

    pub fn reset(self: *Iterator) void {
        self.pos = 0;
    }
};

// Parse all top-level TLV nodes from a byte slice.
pub fn parse(data: []const u8) Iterator {
    return .{ .data = data };
}

// Encode a TLV tag into the buffer. Returns bytes written.
pub fn encodeTag(tag_bytes: []const u8, buf: []u8) error{BufferTooSmall}!usize {
    if (buf.len < tag_bytes.len) return error.BufferTooSmall;
    @memcpy(buf[0..tag_bytes.len], tag_bytes);
    return tag_bytes.len;
}

// Encode a TLV length into the buffer. Returns bytes written.
pub fn encodeLength(length: usize, buf: []u8) error{BufferTooSmall}!usize {
    if (length < 0x80) {
        if (buf.len < 1) return error.BufferTooSmall;
        buf[0] = @intCast(length);
        return 1;
    }
    if (length <= 0xFF) {
        if (buf.len < 2) return error.BufferTooSmall;
        buf[0] = 0x81;
        buf[1] = @intCast(length);
        return 2;
    }
    if (length <= 0xFFFF) {
        if (buf.len < 3) return error.BufferTooSmall;
        buf[0] = 0x82;
        buf[1] = @intCast(length >> 8);
        buf[2] = @intCast(length & 0xFF);
        return 3;
    }
    if (length <= 0xFFFFFF) {
        if (buf.len < 4) return error.BufferTooSmall;
        buf[0] = 0x83;
        buf[1] = @intCast(length >> 16);
        buf[2] = @intCast((length >> 8) & 0xFF);
        buf[3] = @intCast(length & 0xFF);
        return 4;
    }
    if (buf.len < 5) return error.BufferTooSmall;
    buf[0] = 0x84;
    buf[1] = @intCast(length >> 24);
    buf[2] = @intCast((length >> 16) & 0xFF);
    buf[3] = @intCast((length >> 8) & 0xFF);
    buf[4] = @intCast(length & 0xFF);
    return 5;
}

// Encode a complete TLV node. Returns bytes written.
pub fn encode(tag_bytes: []const u8, value: []const u8, buf: []u8) error{BufferTooSmall}!usize {
    var pos: usize = 0;
    pos += try encodeTag(tag_bytes, buf[pos..]);
    pos += try encodeLength(value.len, buf[pos..]);
    if (buf.len - pos < value.len) return error.BufferTooSmall;
    @memcpy(buf[pos..][0..value.len], value);
    return pos + value.len;
}

// Tests

test "parse single-byte tag, short length" {
    // Tag 0x80, length 2, value 0x01 0x02
    const data = [_]u8{ 0x80, 0x02, 0x01, 0x02 };
    const result = try parseNode(&data);
    const node = result[0];
    try std.testing.expectEqualSlices(u8, &.{0x80}, node.tag.bytes);
    try std.testing.expectEqualSlices(u8, &.{ 0x01, 0x02 }, node.value);
    try std.testing.expectEqual(Tag.Class.context_specific, node.tag.class());
    try std.testing.expect(!node.tag.isConstructed());
    try std.testing.expectEqual(@as(u28, 0), node.tag.number());
}

test "parse multi-byte tag" {
    // Tag 0x9F 0x27 (context-specific, tag number 39), length 1, value 0x80
    const data = [_]u8{ 0x9F, 0x27, 0x01, 0x80 };
    const result = try parseNode(&data);
    const node = result[0];
    try std.testing.expectEqualSlices(u8, &.{ 0x9F, 0x27 }, node.tag.bytes);
    try std.testing.expectEqual(@as(u28, 39), node.tag.number());
    try std.testing.expectEqual(Tag.Class.context_specific, node.tag.class());
    try std.testing.expectEqualSlices(u8, &.{0x80}, node.value);
}

test "parse long length (two-byte)" {
    // Tag 0x82, length 0x81 0x80 (128 bytes)
    var data: [2 + 1 + 128]u8 = undefined;
    data[0] = 0x82; // tag
    data[1] = 0x81; // length: long form, 1 subsequent byte
    data[2] = 0x80; // 128
    for (data[3..]) |*b| b.* = 0xAB;
    const result = try parseNode(&data);
    const node = result[0];
    try std.testing.expectEqual(@as(usize, 128), node.value.len);
}

test "parse constructed tag with children" {
    // Constructed tag 0x6E containing two primitive TLVs:
    //   0x4F 0x02 0x01 0x02
    //   0x50 0x01 0xFF
    const data = [_]u8{
        0x6E, 0x07, // constructed, length 7
        0x4F, 0x02, 0x01, 0x02, // child 1
        0x50, 0x01, 0xFF, // child 2
    };
    const result = try parseNode(&data);
    const node = result[0];
    try std.testing.expect(node.tag.isConstructed());
    try std.testing.expectEqual(Tag.Class.application, node.tag.class());

    var it = node.children();
    const c1 = it.next().?;
    try std.testing.expectEqualSlices(u8, &.{0x4F}, c1.tag.bytes);
    try std.testing.expectEqualSlices(u8, &.{ 0x01, 0x02 }, c1.value);

    const c2 = it.next().?;
    try std.testing.expectEqualSlices(u8, &.{0x50}, c2.tag.bytes);
    try std.testing.expectEqualSlices(u8, &.{0xFF}, c2.value);

    try std.testing.expectEqual(@as(?Node, null), it.next());
}

test "find child by tag" {
    const data = [_]u8{
        0x6E, 0x07,
        0x4F, 0x02,
        0x01, 0x02,
        0x50, 0x01,
        0xFF,
    };
    const result = try parseNode(&data);
    const node = result[0];

    const found = node.find(&.{0x50}).?;
    try std.testing.expectEqualSlices(u8, &.{0xFF}, found.value);

    try std.testing.expectEqual(@as(?Node, null), node.find(&.{0x99}));
}

test "iterator over multiple top-level nodes" {
    const data = [_]u8{
        0x80, 0x01, 0xAA,
        0x81, 0x02, 0xBB,
        0xCC,
    };
    var it = parse(&data);

    const n1 = it.next().?;
    try std.testing.expectEqualSlices(u8, &.{0x80}, n1.tag.bytes);
    try std.testing.expectEqualSlices(u8, &.{0xAA}, n1.value);

    const n2 = it.next().?;
    try std.testing.expectEqualSlices(u8, &.{0x81}, n2.tag.bytes);
    try std.testing.expectEqualSlices(u8, &.{ 0xBB, 0xCC }, n2.value);

    try std.testing.expectEqual(@as(?Node, null), it.next());
}

test "encode short length" {
    var buf: [1]u8 = undefined;
    const n = try encodeLength(0x7F, &buf);
    try std.testing.expectEqual(@as(usize, 1), n);
    try std.testing.expectEqual(@as(u8, 0x7F), buf[0]);
}

test "encode two-byte length" {
    var buf: [2]u8 = undefined;
    const n = try encodeLength(0x80, &buf);
    try std.testing.expectEqual(@as(usize, 2), n);
    try std.testing.expectEqualSlices(u8, &.{ 0x81, 0x80 }, &buf);
}

test "encode three-byte length" {
    var buf: [3]u8 = undefined;
    const n = try encodeLength(0x0100, &buf);
    try std.testing.expectEqual(@as(usize, 3), n);
    try std.testing.expectEqualSlices(u8, &.{ 0x82, 0x01, 0x00 }, &buf);
}

test "encode complete TLV" {
    var buf: [10]u8 = undefined;
    const n = try encode(&.{0x80}, &.{ 0x01, 0x02, 0x03 }, &buf);
    try std.testing.expectEqual(@as(usize, 5), n);
    try std.testing.expectEqualSlices(u8, &.{ 0x80, 0x03, 0x01, 0x02, 0x03 }, buf[0..n]);
}

test "encode roundtrip" {
    // Build a TLV, then parse it back.
    var buf: [64]u8 = undefined;
    const value = [_]u8{ 0xDE, 0xAD, 0xBE, 0xEF };
    const n = try encode(&.{ 0x9F, 0x27 }, &value, &buf);
    const result = try parseNode(buf[0..n]);
    const node = result[0];
    try std.testing.expectEqualSlices(u8, &.{ 0x9F, 0x27 }, node.tag.bytes);
    try std.testing.expectEqualSlices(u8, &value, node.value);
}

test "invalid: truncated data" {
    // Length says 5 bytes but only 2 available.
    const data = [_]u8{ 0x80, 0x05, 0x01, 0x02 };
    try std.testing.expectError(error.InvalidTlv, parseNode(&data));
}

test "invalid: empty input" {
    try std.testing.expectError(error.InvalidTlv, parseNode(&.{}));
}

test "tag equality" {
    const t1 = Tag{ .bytes = &.{ 0x9F, 0x27 } };
    const t2 = Tag{ .bytes = &.{ 0x9F, 0x27 } };
    const t3 = Tag{ .bytes = &.{0x80} };
    try std.testing.expect(t1.eql(t2));
    try std.testing.expect(!t1.eql(t3));
}

test "universal class tag" {
    const data = [_]u8{ 0x30, 0x00 }; // SEQUENCE, constructed, universal
    const result = try parseNode(&data);
    const node = result[0];
    try std.testing.expectEqual(Tag.Class.universal, node.tag.class());
    try std.testing.expect(node.tag.isConstructed());
    try std.testing.expectEqual(@as(u28, 0x10), node.tag.number());
}
