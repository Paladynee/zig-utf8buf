pub fn main() !void {
    const rodata_str: str = str.fromUtf8Unchecked("haha!");
    const res = str.fromUtf8("ecksdee!");
    const rodata_str2: str = blk: {
        switch (res) {
            .err => |_| {
                unreachable;
            },
            .ok => |r| {
                break :blk r;
            },
        }
    };

    std.debug.print("rodata 1: {s}\n", .{rodata_str.inner});
    std.debug.print("rodata 2: {s}\n", .{rodata_str2.inner});

    const gpa = std.heap.smp_allocator;

    // infallible!
    var string = String.new(gpa);
    defer string.deinit();

    try string.pushStr(str.fromUtf8Unchecked(hamlet));
    const as_str = string.asStr();

    std.debug.print("&str: {s}\n", .{as_str.inner[0..10]});

    const as_bytes = string.asBytes();
    std.debug.print("&[u8]: {s}\n", .{as_bytes[0..10]});

    const my_char = char{ .code = 'ü' };
    try string.push(my_char);

    std.debug.print("+ü: {s}\n", .{string.vec.items[string.vec.items.len - 10 .. string.vec.items.len]});
}

const hamlet: []const u8 =
    \\I have of late—but wherefore I know not—lost all my mirth, forgone all custom of exercises;
    \\and indeed it goes so heavily with my disposition that this goodly frame, the earth,
    \\seems to me a sterile promontory; this most excellent canopy, the air, look you,
    \\this brave o’erhanging firmament, this majestical roof fretted with golden fire,
    \\why, it appears no other thing to me than a foul and pestilent congregation of vapours.
    \\What a piece of work is man! how noble in reason! how infinite in faculty!
    \\in form and moving how express and admirable! in action how like an angel!
    \\in apprehension how like a god! the beauty of the world, the paragon of animals!
    \\And yet, to me, what is this quintessence of dust? Man delights not me: no, nor woman neither,
    \\though by your smiling you seem to say so.
    \\
    \\O! what a rogue and peasant slave am I! Is it not monstrous that this player here,
    \\but in a fiction, in a dream of passion, could force his soul so to his own conceit
    \\that from her working all his visage wann'd; tears in his eyes, distraction in 's aspect,
    \\a broken voice, and his whole function suiting with forms to his conceit?
    \\And all for nothing! For Hecuba! What’s Hecuba to him, or he to Hecuba,
    \\that he should weep for her? What would he do, had he the motive and the cue
    \\for passion that I have? He would drown the stage with tears, and cleave the general ear
    \\with horrid speech; make mad the guilty, and appal the free, confound the ignorant,
    \\and amaze indeed the very faculties of eyes and ears. Yet I, a dull and muddy-mettled rascal,
    \\peak like John-a-dreams, unpregnant of my cause, and can say nothing;
    \\no, not for a king, upon whose property and most dear life a damn’d defeat was made.
    \\Am I a coward? Who calls me villain? breaks my pate across? Plucks off my beard,
    \\and blows it in my face? Tweaks me by the nose? Gives me the lie i’ th’ throat,
    \\as deep as to the lungs? Who does me this? Ha! ‘Swounds, I should take it; for it cannot be
    \\but I am pigeon-liver’d and lack gall to make oppression bitter, or ere this
    \\I should have fatted all the region kites with this slave’s offal.
    \\Bloody, bawdy villain! Remorseless, treacherous, lecherous, kindless villain!
    \\O! vengeance! Why, what an ass am I! This is most brave, that I, the son of a dear father murder’d,
    \\prompted to my revenge by heaven and hell, must, like a whore, unpack my heart with words,
    \\and fall a-cursing, like a very drab, a scullion! Fie upon’t! foh! About, my brain!
    \\I have heard that guilty creatures sitting at a play have, by the very cunning of the scene,
    \\been struck so to the soul that presently they have proclaim’d their malefactions;
    \\for murder, though it have no tongue, will speak with most miraculous organ.
    \\I'll have these players play something like the murder of my father before mine uncle:
    \\I’ll observe his looks; I’ll tent him to the quick: if he but blench, I know my course.
    \\The spirit that I have seen may be the devil: and the devil hath power to assume
    \\a pleasing shape; yea, and perhaps, out of my weakness and my melancholy,
    \\as he is very potent with such spirits, abuses me to damn me: I’ll have grounds
    \\more relative than this. The play’s the thing wherein I’ll catch the conscience of the king.
;

const std = @import("std");
const lib = @import("zigstring_lib");
const String = lib.String;
const str = lib.str;
const char = lib.char;

test "fuzz String" {
    const Context = struct {
        fn fuzz(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            std.debug.print("got here {s}\n", .{input});
            const r = str.fromUtf8(input);
            const res = blk: {
                switch (r) {
                    .ok => |v| {
                        break :blk v;
                    },
                    .err => {
                        return;
                    },
                }
            };
            const string = String.fromStr(std.heap.smp_allocator, res) catch {
                return;
            };
            defer string.deinit();
        }
    };
    try std.testing.fuzz(Context{}, Context.fuzz, .{});
}

test "lol" {
    const gpa = std.heap.smp_allocator;
    _ = gpa;
}
