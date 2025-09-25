pub const v2 = struct {
    pos: [3]f32,
};
pub const v2c = struct {
    pos: [3]f32,
    color: [4]f32,
};
pub const wall_segment = struct {
    pos: [4]f32, // x1, y1 (Start-point) x2, y2 (End-point)
};
pub const sector = struct {
    floor_height: f32,
    ceil_height: f32,
    walls: wall_segment,
};

pub fn mat4_identity() [16]f32 { return [_]f32{
    1,0,0,0,
    0,1,0,0,
    0,0,1,0,
    0,0,0,1,
}; }

pub fn perspective(fov: f32, aspect: f32, near: f32, far: f32) [16]f32 {
    const f = 1.0 / @tan(fov * 0.5);
    return [_]f32{
        f/aspect,0,0,0,
        0,f,0,0,
        0,0,(far+near)/(near-far),-1,
        0,0,(2*far*near)/(near-far),0,
    };
}
pub fn lookAt(eye: [3]f32, center: [3]f32, up: [3]f32) [16]f32 {
    const f = normalize([3]f32{
        center[0] - eye[0],
        center[1] - eye[1],
        center[2] - eye[2],
    });
    const s = normalize(cross(f, up));
    const u = cross(s, f);

    return [_]f32{
        s[0], u[0], -f[0], 0,
        s[1], u[1], -f[1], 0,
        s[2], u[2], -f[2], 0,
        -dot(s, eye), -dot(u, eye), dot(f, eye), 1,
    };
}

pub fn rotateY(angle: f32) [16]f32 {
    const c = @cos(angle);
    const s = @sin(angle);
    return [_]f32{
        c, 0, s, 0,
        0, 1, 0, 0,
        -s, 0, c, 0,
        0, 0, 0, 1,
    };
}

fn normalize(v: [3]f32) [3]f32 {
    const len = @sqrt(v[0]*v[0] + v[1]*v[1] + v[2]*v[2]);
    return [3]f32{ v[0]/len, v[1]/len, v[2]/len };
}

fn cross(a: [3]f32, b: [3]f32) [3]f32 {
    return [3]f32{
        a[1]*b[2] - a[2]*b[1],
        a[2]*b[0] - a[0]*b[2],
        a[0]*b[1] - a[1]*b[0],
    };
}

fn dot(a: [3]f32, b: [3]f32) f32 {
    return a[0]*b[0] + a[1]*b[1] + a[2]*b[2];
}

pub fn mul4(a: [16]f32, b: [16]f32) [16]f32 {
    var r: [16]f32 = undefined;
    for (0..4) |i| {
        for (0..4) |j| {
            var sum: f32 = 0;
            for (0..4) |k| {
                sum += a[i*4 + k] * b[k*4 + j];
            }
            r[i*4 + j] = sum;
        }
    }
    return r;
}

