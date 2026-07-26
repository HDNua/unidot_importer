# Several packages in one project

The other files here each measure one `.unitypackage` in isolation. This one is
about what happens when several land in the same project, which is what a real
project does and the only case where packages that share a GUID contend for the
same output path.

Tested on Godot `4.7.1-stable.mono` for macOS at importer revision `69bd28a`,
with `tools/checks/package_overlap.py` for the static comparison and
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

## Open: bone/skin failures on the PolygonGeneric character prefabs

Running the checker over this project also put it over content no gate had
covered before, and it reports `22,737` bone/skin failures on the `39`
PolygonGeneric character prefabs — a constant `115.17°` across whole bone
chains. These are **not** an integration finding: they are identical before and
after the second package, come from a Prototype-only project, and reproduce with
the unmodified checker at revision `69bd28a`.

No prior gate covered these prefabs. The Prototype report's `3,600` checks come
from a gate written for the `8` FPS arm prefabs, and the Starter report's `200`
come from that pack's `4` skinned prefabs. In the same combined project the FPS
arm prefabs still pass every one of their checks.

Whether this is a defect or a limit of the check is **not established** here.

## Recommendation

Before importing packages together, run the static comparison — it is quick, it
needs no Godot, and it names what will contend:

```bash
tools/checks/package_overlap.py "A.unitypackage" "B.unitypackage"
```

Where a model conflicts, prefer the package holding the **larger** build if it is
a superset, by importing it last. For the Synty packs measured here that means
importing Town or War *before* Prototype, Sci-Fi City or Fantasy Kingdom, and
importing Starter first of all. Then verify the packages imported earlier, not
just the last one:

```bash
tools/validate_package.py "A.unitypackage" "B.unitypackage" --run --verify
```

Unidot has no way to resolve this on its own. Two packages assert different
content for one identity, and nothing in the archives says which is intended —
the `.meta` files are byte-identical in the case measured here. Choosing for the
user would be guessing; reporting it is not.
