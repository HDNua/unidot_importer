# Several packages in one project

The other files here each measure one `.unitypackage` in isolation. This one is
about what happens when several land in the same project, which is what a real
project does and the only case where packages that share a GUID contend for the
same output path.

The static comparison was rerun at importer revision `e5e93b3`. The measured
Prototype-then-Town import used Godot `4.7.1-stable.mono` for macOS at revision
`69bd28a`, with `tools/checks/package_overlap.py` for the static comparison and
`tools/validate_package.py A B --run --verify` for the import.

**Result: importing several packages together is order-dependent, and one
observed case loses content.** Where two packages ship the same GUID with
different bytes, the package imported last replaces the file. Nothing warns
during the import, and content already converted from the earlier package that
referenced a part the replacement does not have is left incomplete.

## What the packages disagree about

Across the six Synty POLYGON packs:

| | Count |
| --- | ---: |
| Distinct GUIDs across all six packs | `14,733` |
| Carried by more than one pack | `1,257` |
| — identical bytes everywhere | `1,122` |
| — **different bytes per pack** | `135` |
| — different `.meta` per pack | `58` |
| Pathname collisions between different GUIDs | `0` |

The `1,122` identical ones are the benign case: the packs agree, and it does not
matter which supplies the file. The `135` are the problem, and they are not
evenly spread — most are materials and collision meshes, but four are models:

| Conflicting model | Versions |
| --- | --- |
| `PolygonGeneric/Models/Base/SM_Bld_Base_Floor_Round_01.fbx` | Starter vs the other five |
| `PolygonGeneric/Models/Base/SM_Bld_Base_Wall_Half_Angle_02.fbx` | Starter vs the other five |
| `PolygonGeneric/Models/Base/SM_Bld_Base_Wall_Round_01.fbx` | Starter vs the other five |
| `PolygonGeneric/Models/Generic_Characters.fbx` | Fantasy Kingdom, Prototype, Sci-Fi City (`7,326,192` B) vs Town, War (`6,712,624` B) |

Models matter more than their count suggests. Other assets reference a mesh or a
bone *inside* a model by file ID, so replacing one can invalidate references held
by assets that converted perfectly.

That there are `0` pathname collisions is worth stating: the packs never disagree
about *which* asset a GUID names, only about its content.

## Directional static screen across all 15 pairs

The extended comparison makes a second archive pass over supported text assets
and groups the file IDs they reference by conflicting model build. For each
replacement direction it reports IDs observed only among consumers accompanying
the displaced build, then names those consumer assets as heuristic review
candidates.

This is a **consumer-reference heuristic**, not an import result or a model
inventory. It does not inspect whether the winning model actually contains an
ID. A non-zero result names what to review; zero means only that no directional
consumer-reference asymmetry was observed. Neither result establishes
compatibility, a lossless order, or a superset relationship.

The table covers all `6 choose 2 = 15` pairs. `S/C/M` means shared GUIDs,
conflicting GUIDs, and meta-conflicting GUIDs. A directional cell is
`consumer-only file IDs / candidate assets`; for pair `A / B`, “A later” means
A's model build wins and consumers accompanying B are the displaced side. A
dash means the pair has no differing model build to analyze. No import was run
for this table, and every pair had zero pathname collisions.

| Pair (A / B) | S / C / M | Differing models | A later | B later |
| --- | ---: | ---: | ---: | ---: |
| Fantasy Kingdom / Prototype | `1257 / 0 / 0` | `0` | — | — |
| Fantasy Kingdom / Sci-Fi City | `1257 / 1 / 0` | `0` | — | — |
| Fantasy Kingdom / Starter | `1054 / 75 / 58` | `3` | `0 / 0` | `0 / 0` |
| Fantasy Kingdom / Town | `1255 / 1 / 0` | `1` | `0 / 0` | `57 / 2` |
| Fantasy Kingdom / War | `1255 / 61 / 0` | `1` | `0 / 0` | `57 / 2` |
| Prototype / Sci-Fi City | `1257 / 1 / 0` | `0` | — | — |
| Prototype / Starter | `1054 / 75 / 58` | `3` | `0 / 0` | `0 / 0` |
| Prototype / Town | `1255 / 1 / 0` | `1` | `0 / 0` | `57 / 2` |
| Prototype / War | `1255 / 61 / 0` | `1` | `0 / 0` | `57 / 2` |
| Sci-Fi City / Starter | `1054 / 76 / 58` | `3` | `0 / 0` | `0 / 0` |
| Sci-Fi City / Town | `1255 / 2 / 0` | `1` | `0 / 0` | `57 / 2` |
| Sci-Fi City / War | `1255 / 62 / 0` | `1` | `0 / 0` | `57 / 2` |
| Starter / Town | `1054 / 75 / 58` | `3` | `0 / 0` | `0 / 0` |
| Starter / War | `1054 / 74 / 58` | `3` | `0 / 0` | `0 / 0` |
| Town / War | `1255 / 60 / 0` | `0` | — | — |

All six non-zero directions are the same `Generic_Characters.fbx` split. If
Town or War supplies the winning build after Fantasy Kingdom, Prototype, or
Sci-Fi City, the screen finds `57` consumer-only IDs and the same two underwear
prefabs already confirmed by the Prototype-then-Town import below. Reversing
that order produces `0 / 0`, but that remains “no observed asymmetry,” not a
compatibility proof.

Starter's three differing base models produce `0 / 0` in both directions across
all five of its pairs. This method therefore does not validate “Starter first.”
It also does not establish the broader assumption that a larger model build is
a superset. A reliable verdict on that question would require a separate model
sub-object/file-ID inventory.

## The measured case: Prototype, then Town

`Generic_Characters.fbx` carries the same GUID and a byte-identical `.meta` in
both packs, but the Prototype build contains two skinned meshes the Town build
does not — `SM_Gen_Chr_Underwear_Female_01` and `SM_Gen_Chr_Underwear_Male_01`,
with their two corresponding bind poses. Only Prototype ships prefabs for them.

Importing Prototype and then Town into one project:

| | After Prototype | After Town |
| --- | ---: | ---: |
| Scenes that load and instantiate | `989/989` | `1693/1693` |
| Declared node paths missing after instantiation | `0` | **`4`** |
| `MeshInstance3D` with no mesh | `0` | `0` |

Stage 2 rewrote `Generic_Characters.fbx` with the Town build. Town ships no
underwear prefabs, so Prototype's two were left untouched, pointing at a model
that no longer contains their meshes. Godot's inherited-scene recovery then
dropped the nodes:

```
WARNING: SM_Gen_Chr_Underwear_Female_01.prefab.scn: A node in the scene this one
         inherits from has been removed or moved, so a recovery process needs to
         take place.
WARNING: Node 'GeneralSkeleton/SM_Gen_Chr_Underwear_Male_01' was modified from
         inside an instance, but it has vanished.
```

The damage is confined to the two prefabs whose content was removed from under
them. Skin deformation was measured before and after and was identical, so the
second import changed nothing there.

## Why this needed a new check

The scene still loads. It still instantiates. Every `MeshInstance3D` it contains
still has a mesh. The node is not empty — it is **gone**, and nothing that counts
what is present can see that. Run against this project, the checker as it stood
reported the integration defect not at all.

`verify_output.gd` now also asserts that every node path a scene declares still
resolves after instantiation, comparing the scene against its own `SceneState`
rather than against an expectation of what should be there. On the combined
project that is `4` findings out of `15,262` declared node paths, all four on the
two prefabs identified in advance by the static comparison, with no false
positives across `1,693` scenes.

The recurring shape is a check that enumerates what exists and asserts something
about each item: absence is invisible to it.

## A source-pose gate reaches the same verdict

The source-pose gate added at revision `0ac70a7` provides a second structural
check on this case. For direct-YAML prefabs it compares authored bone transforms
with the converted scene; its weaker inherited-FBX branch requires every Unity
prefab modification target to resolve through the persisted model file-ID map.
It was run against both the clean Prototype-only project and the measured
Prototype-then-Town project, using the same Prototype package as the source:

| | Prototype only | Prototype, then Town |
| --- | ---: | ---: |
| Skin-prefab inventories (source/output) | `39/39` | `39/39` |
| Prefabs checked | `39` | `37` |
| Direct YAML | `37` / `1,826` bones | `37` / `1,826` bones |
| Persisted-FBX composition | `2` / `154` bones | `0` |
| Unsupported prefabs | `0` | **`2`** |
| Negative controls detected | `2/2` | `1/1` |
| Numeric pose mismatches | `0` | `0` |
| Result | **PASS** | **FAIL** |

Both unsupported entries are the female and male underwear prefabs. In the
combined project their Unity modification target file ID
`-8799741579280556076` no longer resolves against the persisted Town build of
`Generic_Characters.fbx`, so the gate fails closed instead of silently skipping
them. The clean project resolves both prefabs and compares all `154` inherited
bones with zero error.

This is not an independent Unity data oracle: both checks ultimately examine
artifacts derived from the same packages. It is nevertheless a different
invariant and failure mechanism. `verify_output.gd` finds four declared Godot
`SceneState` paths that vanish after instantiation; the source-pose gate finds
two unresolved Unity prefab targets in the persisted FBX mapping. Both identify
the same two prefabs, while the clean baseline has zero declared-path findings
and passes both source-pose comparison branches.

## What this run also settled: the skinning check was not vendor-neutral

Running this comparison put `tools/checks/verify_output.gd` over content no gate
had covered before, and it reported `22,737` bone/skin failures while scanning
`39` skin-bearing prefabs in total. Those `39` already included the `8` FPS arm
prefabs that passed. The failures came from `20` posed PolygonGeneric full-
character prefabs plus one check in `Fov_01`; the other `10` non-FPS prefabs
also passed. Across the affected character chains the constant angle looked
like the signature of the Root-hijack defect fixed for the FPS arms.

The character failures were a false alarm. **The characters render correctly.**
Rendering
`SM_Gen_Chr_Business_Female_01` and `SM_Gen_Chr_Peasent_Male_01` from this
project shows clean, undistorted T-poses with correct proportions and materials.

Four candidate mechanisms were measured and rejected: stale skeleton poses
before the first frame (identical results after), binds with no vertex weight
(weighted binds fail too), bind-to-bone resolution picking the wrong bone of a
duplicated name (index and name agree on all `1,150`), and an uncompensated mesh
transform (identity). What remains is the check's own precondition. The identity
`D = global_bone_pose * bind_pose = I` holds only when the skeleton sits at the
pose its meshes were bound in; the affected character prefabs are deliberately
stored in another pose, so they miss the identity and render correctly, which is
what skinning does. The FPS arm prefabs happen to sit at bind pose, which is why
the same test is meaningful for them.

That precondition cannot be tested independently — the identity *is* the test.
So the check needs outside knowledge of how a publisher authors prefabs, which
makes it a publisher gate wearing a vendor-neutral costume, precisely the thing
[tools/README.md](../../tools/README.md) warns against. It has been moved to
`tools/publishers/synty/polygon-prototype/gate_fps_arms.gd`, and
`verify_output.gd` no longer asserts anything about skinning.

Counting this, three checks in this repository have now reported something other
than reality: the skeleton lookup that found no skins and passed, the posed
authored scenes that failed, and this one. All three share a shape — a check
that is confident about a precondition it never measured.

## Recommendation

Before importing packages together, run the static comparison — it is quick, it
needs no Godot, and it names what will contend:

```bash
tools/checks/package_overlap.py "A.unitypackage" "B.unitypackage"
```

The only order constraint supported by the directional screen is to import Town
and War before Fantasy Kingdom, Prototype, or Sci-Fi City. That minimizes the
one observed consumer-reference signal. For the six-pack integration validation,
use this deterministic order:

1. Starter
2. Town
3. War
4. Prototype
5. Sci-Fi City
6. Fantasy Kingdom

Starter's position and the order within the two model-build groups are
tie-breakers, not proven safety properties. This is a validation order chosen to
minimize the observed heuristic signal, not a guaranteed lossless order. Verify
the packages imported earlier after every stage, not only the last one:

```bash
tools/validate_package.py "A.unitypackage" "B.unitypackage" --run --verify
```

Unidot has no way to resolve this on its own. Two packages assert different
content for one identity, and nothing in the archives says which is intended —
the `.meta` files are byte-identical in the case measured here. Choosing for the
user would be guessing; reporting it is not.
