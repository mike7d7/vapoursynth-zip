const std = @import("std");
const math = std.math;

const vszip = @import("vszip.zig");
const vs = vszip.vs;
const vsh = vszip.vsh;
const zapi = vszip.zapi;

pub const BPSType = enum {
    U8,
    U9,
    U10,
    U12,
    U14,
    U16,
    U32,
    F16,
    F32,

    pub fn select(map: zapi.ZMapRW, node: ?*vs.Node, vi: *const vs.VideoInfo, comptime name: []const u8) !BPSType {
        var err_msg: ?[]const u8 = null;
        errdefer {
            map.setError(err_msg.?);
            map.vsapi.?.freeNode.?(node);
        }

        if (vi.format.sampleType == .Integer) {
            switch (vi.format.bitsPerSample) {
                8 => return .U8,
                9 => return .U9,
                10 => return .U10,
                12 => return .U12,
                14 => return .U14,
                16 => return .U16,
                32 => return .U32,
                else => return {
                    err_msg = name ++ ": not supported Int format.";
                    return error.format;
                },
            }
        } else {
            switch (vi.format.bitsPerSample) {
                16 => return .F16,
                32 => return .F32,
                else => return {
                    err_msg = name ++ ": not supported Float format.";
                    return error.format;
                },
            }
        }
    }
};

pub const DataType = enum {
    U8,
    U16,
    F16,
    F32,

    pub fn select(map: zapi.ZMapRW, node: ?*vs.Node, vi: *const vs.VideoInfo, comptime name: []const u8) !DataType {
        var err_msg: ?[]const u8 = null;
        errdefer {
            map.setError(err_msg.?);
            map.vsapi.?.freeNode.?(node);
        }

        if (vi.format.sampleType == .Integer) {
            switch (vi.format.bytesPerSample) {
                1 => return .U8,
                2 => return .U16,
                else => return {
                    err_msg = name ++ ": not supported Int format.";
                    return error.format;
                },
            }
        } else {
            switch (vi.format.bytesPerSample) {
                2 => return .F16,
                4 => return .F32,
                else => return {
                    err_msg = name ++ ": not supported Float format.";
                    return error.format;
                },
            }
        }
    }
};

pub fn absDiff(x: anytype, y: anytype) @TypeOf(x) {
    return if (x > y) (x - y) else (y - x);
}

pub fn mapGetPlanes(in: zapi.ZMapRO, out: zapi.ZMapRW, nodes: []?*vs.Node, process: []bool, num_planes: c_int, comptime name: []const u8, vsapi: ?*const vs.API) !void {
    const num_e = in.numElements("planes") orelse return;
    @memset(process, false);

    var err_msg: ?[]const u8 = null;
    errdefer {
        out.setError(err_msg.?);
        for (nodes) |node| vsapi.?.freeNode.?(node);
    }

    var i: u32 = 0;
    while (i < num_e) : (i += 1) {
        const e = in.getInt2(i32, "planes", i).?;
        if ((e < 0) or (e >= num_planes)) {
            err_msg = name ++ ": plane index out of range";
            return error.ValidationError;
        }

        const ue: u32 = @intCast(e);
        if (process[ue]) {
            err_msg = name ++ ": plane specified twice.";
            return error.ValidationError;
        }

        process[ue] = true;
    }
}

pub fn compareNodes(out: zapi.ZMapRW, node1: ?*vs.Node, node2: ?*vs.Node, vi1: *const vs.VideoInfo, vi2: *const vs.VideoInfo, comptime name: []const u8, vsapi: ?*const vs.API) !void {
    if (node2 == null) {
        return;
    }

    var err_msg: ?[]const u8 = null;
    errdefer {
        out.setError(err_msg.?);
        vsapi.?.freeNode.?(node1);
        vsapi.?.freeNode.?(node2);
    }

    if (!vsh.isSameVideoInfo(vi1, vi2) or !vsh.isConstantVideoFormat(vi2)) {
        err_msg = name ++ ": both input clips must have the same format.";
        return error.node;
    }
}

pub fn getPeak(vi: *const vs.VideoInfo) u16 {
    if (vi.format.sampleType == .Integer) {
        return @intCast(math.shl(u32, 1, vi.format.bitsPerSample) - 1);
    } else {
        return math.maxInt(u16);
    }
}

pub fn toRGBS(node: ?*vs.Node, core: ?*vs.Core, vsapi: ?*const vs.API) ?*vs.Node {
    const vi = vsapi.?.getVideoInfo.?(node);
    if ((vi.format.colorFamily == .RGB) and (vi.format.sampleType == .Float)) {
        return node;
    }

    const matrix: i32 = if (vi.height > 650) 1 else 6;
    const args = vsapi.?.createMap.?();
    _ = vsapi.?.mapConsumeNode.?(args, "clip", node, .Replace);
    _ = vsapi.?.mapSetInt.?(args, "matrix_in", matrix, .Replace);
    _ = vsapi.?.mapSetInt.?(args, "format", @intFromEnum(vs.PresetVideoFormat.RGBS), .Replace);

    const vsplugin = vsapi.?.getPluginByID.?(vsh.RESIZE_PLUGIN_ID, core);
    const ret = vsapi.?.invoke.?(vsplugin, "Bicubic", args);
    const out = vsapi.?.mapGetNode.?(ret, "clip", 0, null);
    vsapi.?.freeMap.?(ret);
    vsapi.?.freeMap.?(args);
    return out;
}

pub fn getVal(comptime T: type, ptr: anytype, dist: isize) T {
    const adr: isize = @intCast(@intFromPtr(ptr));
    const uadr: usize = @intCast(adr + dist);
    const ptr2: [*]const T = @ptrFromInt(uadr);
    return ptr2[0];
}

pub fn getVal2(comptime T: type, ptr: anytype, x: u32, y: u32) T {
    const ix: i32 = @intCast(x);
    const iy: i32 = @intCast(y);
    const adr: isize = @intCast(@intFromPtr(ptr));
    const uadr: usize = @intCast(adr + ix - iy);
    const ptr2: [*]const T = @ptrFromInt(uadr);
    return ptr2[0];
}
