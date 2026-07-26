#!/usr/bin/env python3
"""D-identity gate: for each arm prefab, every Skin bind of every MeshInstance3D
must satisfy D = G_bone_pose_global * bind ~= identity:
  |D.origin| < 1cm, per-axis scale in [0.99, 1.01], rotation angle < 1 deg.
Also checks adjacent-bone probe gaps < 1cm for weighted pairs.

Usage: python3 gate_arms.py <godot_prefab_root>
  e.g. gate_arms.py .../import_test/Unidot/Assets/Synty/PolygonPrototype/Prefabs/Characters/FPS_Hands
"""
import re
import math
import sys
import os

PREFABS = [
    ("FiveFinger", "Character_FPS_Arms_FiveFinger_01"),
    ("FiveFinger", "Character_FPS_Arms_FiveFinger_02"),
    ("FiveFinger", "Character_FPS_Arms_FiveFinger_03"),
    ("FiveFinger", "Character_FPS_Hands_FiveFinger_01"),
    ("Standard", "Character_FPS_Arms_Standard_01"),
    ("Standard", "Character_FPS_Arms_Standard_02"),
    ("Standard", "Character_FPS_Arms_Standard_03"),
    ("Standard", "Character_FPS_Hands_Standard_01"),
]

ORIGIN_TOL = 0.01
SCALE_TOL = 0.01
ROT_TOL_DEG = 1.0
GAP_TOL = 0.01


def mat_mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]

def mat_vec(m, v):
    return [sum(m[i][k] * v[k] for k in range(3)) for i in range(3)]

def aff_mul(A, B):
    (Ma, oa), (Mb, ob) = A, B
    return (mat_mul(Ma, Mb), [x + y for x, y in zip(mat_vec(Ma, ob), oa)])

def mat_inv(m):
    d = (m[0][0]*(m[1][1]*m[2][2]-m[1][2]*m[2][1])
         - m[0][1]*(m[1][0]*m[2][2]-m[1][2]*m[2][0])
         + m[0][2]*(m[1][0]*m[2][1]-m[1][1]*m[2][0]))
    c = [[(m[(i+1)%3][(j+1)%3]*m[(i+2)%3][(j+2)%3]
           - m[(i+1)%3][(j+2)%3]*m[(i+2)%3][(j+1)%3]) for j in range(3)] for i in range(3)]
    return [[c[j][i] / d for j in range(3)] for i in range(3)]

def aff_inv(A):
    M, o = A
    Mi = mat_inv(M)
    return (Mi, [-x for x in mat_vec(Mi, o)])

def quat_mat(x, y, z, w):
    return [
        [1-2*(y*y+z*z), 2*(x*y-w*z),   2*(x*z+w*y)],
        [2*(x*y+w*z),   1-2*(x*x+z*z), 2*(y*z-w*x)],
        [2*(x*z-w*y),   2*(y*z+w*x),   1-2*(x*x+y*y)],
    ]

def trs(pos, quat, scale):
    R = quat_mat(*quat)
    return ([[R[i][j]*scale[j] for j in range(3)] for i in range(3)], list(pos))

def dist(a, b):
    return math.sqrt(sum((x-y)**2 for x, y in zip(a, b)))

def basis_scales(m):
    return [math.sqrt(sum(m[i][j]**2 for i in range(3))) for j in range(3)]

def rot_angle_deg(m):
    # orthonormalize columns roughly (divide by scale), then angle from trace
    sc = basis_scales(m)
    r = [[m[i][j]/sc[j] for j in range(3)] for i in range(3)]
    tr = r[0][0] + r[1][1] + r[2][2]
    c = max(-1.0, min(1.0, (tr - 1.0) / 2.0))
    return math.degrees(math.acos(c))

def floats(s):
    m = re.search(r'\((.*)\)', s)
    if m:
        s = m.group(1)
    return [float(x) for x in re.findall(r'-?\d+\.?\d*(?:e[+-]?\d+)?', s)]


def parse_tscn(path):
    text = open(path).read()
    sk = re.search(r'\[node name="GeneralSkeleton".*?\](.*?)(?=\n\[node)', text, re.S).group(1)
    bones = {}
    for idx, key, val in re.findall(r'bones/(\d+)/(\w+) = (.+)', sk):
        bones.setdefault(int(idx), {})[key] = val
    for b in bones.values():
        b['name'] = b['name'].strip('"')
        b['parent'] = int(b['parent'])
        b['pose_local'] = trs(floats(b['position']), floats(b['rotation']), floats(b['scale']))
    order = sorted(bones)
    out = {}
    pending = list(order)
    while pending:
        nxt = []
        for i in pending:
            p = bones[i]['parent']
            if p == -1:
                out[i] = bones[i]['pose_local']
            elif p in out:
                out[i] = aff_mul(out[p], bones[i]['pose_local'])
            else:
                nxt.append(i)
        if len(nxt) == len(pending):
            raise RuntimeError("cycle")
        pending = nxt
    G = out
    # all meshes with skins (visible or not)
    mesh_skins = []
    for nm, body in re.findall(r'\[node name="([^"]+)" type="MeshInstance3D"[^\]]*\](.*?)(?=\n\[|\Z)', text, re.S):
        m = re.search(r'skin = SubResource\("([^"]+)"\)', body)
        if m:
            mesh_skins.append((nm, m.group(1), 'visible = false' in body))
    skins = {}
    for sid, body in re.findall(r'\[sub_resource type="Skin" id="([^"]+)"\](.*?)(?=\n\[)', text, re.S):
        binds = {}
        for m in re.finditer(r'bind/(\d+)/(\w+) = (.+)', body):
            binds.setdefault(int(m.group(1)), {})[m.group(2)] = m.group(3)
        out2 = {}
        for b in binds.values():
            f = floats(b['pose'])
            out2[b['name'].strip('&"')] = {
                'bone': int(b['bone']),
                'bind': ([f[0:3], f[3:6], f[6:9]], f[9:12]),
            }
        skins[sid] = out2
    return bones, G, skins, mesh_skins


def main():
    root = sys.argv[1]
    total_fail = 0
    total_checked = 0
    for sub, name in PREFABS:
        path = os.path.join(root, sub, name + ".prefab.tscn")
        if not os.path.exists(path):
            print(f"MISSING  {name}: {path}")
            total_fail += 1
            continue
        bones, G, skins, mesh_skins = parse_tscn(path)
        prefab_fail = 0
        for mesh_name, sid, hidden in mesh_skins:
            skin = skins[sid]
            BG = {nm: aff_inv(d['bind']) for nm, d in skin.items()}
            for nm, d in skin.items():
                bi = d['bone']
                D = aff_mul(G[bi], d['bind'])
                sc = basis_scales(D[0])
                o = D[1]
                ang = rot_angle_deg(D[0])
                bad = []
                if dist(o, [0, 0, 0]) >= ORIGIN_TOL:
                    bad.append(f"origin={o[0]:.3f},{o[1]:.3f},{o[2]:.3f}")
                if max(abs(s - 1) for s in sc) >= SCALE_TOL:
                    bad.append(f"scale={sc[0]:.3f},{sc[1]:.3f},{sc[2]:.3f}")
                if ang >= ROT_TOL_DEG:
                    bad.append(f"rot={ang:.2f}deg")
                total_checked += 1
                if bad:
                    prefab_fail += 1
                    total_fail += 1
                    vis = " (hidden mesh)" if hidden else ""
                    print(f"FAIL {name} / {mesh_name}{vis} / {nm}: " + "; ".join(bad))
            # probe gaps between weighted parent-child pairs
            for nm, d in skin.items():
                bi = d['bone']
                pi = bones[bi]['parent']
                if pi < 0:
                    continue
                pn = bones[pi]['name']
                if pn not in skin:
                    continue
                Da = aff_mul(G[skin[pn]['bone']], skin[pn]['bind'])
                Db = aff_mul(G[bi], d['bind'])
                probe = BG[nm][1]
                pa = [x + y for x, y in zip(mat_vec(Da[0], probe), Da[1])]
                pb = [x + y for x, y in zip(mat_vec(Db[0], probe), Db[1])]
                g = dist(pa, pb)
                total_checked += 1
                if g >= GAP_TOL:
                    prefab_fail += 1
                    total_fail += 1
                    print(f"FAIL {name} / {mesh_name} / gap {pn}<->{nm}: {g:.4f} m")
        status = "OK  " if prefab_fail == 0 else "BAD "
        print(f"{status} {name}: skins={len(mesh_skins)} failures={prefab_fail}")
    print(f"\nTOTAL: {total_checked} checks, {total_fail} failures")
    sys.exit(1 if total_fail else 0)


if __name__ == '__main__':
    main()
