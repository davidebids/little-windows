# Body anatomy source meshes

This directory contains the higher-detail USD source meshes used to generate
the mobile runtime LODs in `LittleWindows/Resources/BodyAnatomy`. It is outside
the app resource directory so these source-only files are not copied into the
installed application bundle.

Registered whole-body muscle, skeleton, joint, nerve, arterial, and venous
inputs for `generate_full_body_hand_lod.py` also live here. Keep their
non-`FullBodyLOD` filenames in this directory; only the generated LOD outputs
belong in the app resource directory.

Use `Scripts/generate_body_lod.mjs` to regenerate the skin `Medium` and `Low`
runtime meshes. The muscular and nervous system runtime assets intentionally
retain the complete topology from the matching source files in this directory.
Whole-system simplification removes small facial muscles and peripheral branches
in the hands and feet even when the total triangle target appears generous.
Generate the muscular source with the `muscles` profile of
`Scripts/generate_skeleton_assets.mjs`; it preserves every included muscle while
removing superficial fascia, aponeuroses, sheaths, and retinacula that otherwise
hide the intrinsic hand and foot anatomy. The `nerves` profile preserves every
nerve group without simplification.

Use `Scripts/generate_skeleton_assets.mjs` with the upstream
`systems/iskelet.glb` for skeleton LODs; it simplifies each bone independently
and preserves hand and foot bones at source fidelity so small disconnected
structures are not collapsed by a whole-body simplification pass. The same
component-preserving generator is used with `systems/eklem.glb` for the joint
system so small ligaments, capsules, menisci, and hand/foot joint structures
remain present. Use
`Scripts/generate_vascular_assets.mjs` with the upstream Z-Anatomy circulation
GLB and the registered runtime skin mesh to regenerate the arterial and venous
meshes. The skin argument is used to fit superficial veins inside the local
body surface after atlas registration. Circulation is simplified per connected
branch and preserves small vessels in full; do not replace this with a single
whole-system simplification pass because it fragments the vascular tree.

Focused left/right hand mode uses the NIMBLE parametric hand atlas instead of a
crop of the whole-body meshes. Run `Scripts/generate_nimble_hand_assets.py`
with the upstream `NIMBLE_DICT_9137.pkl` parameter file to regenerate the hand
skin, intrinsic muscles, tendons, bones, joint capsules, nerve sheaths, and
nerve fascicles. The large upstream parameter file is deliberately not stored
in this repository. The generator transforms every system with the same matrix
and derives tendon and nerve depth from the generated skin surface, so do not
register or scale the hand systems independently afterward.

After generating a system mesh, use `Scripts/register_anatomy_volume.py` with
the matching `RegistrationControlsFemale.npz` or
`RegistrationControlsMale.npz` cage and runtime skin. It applies a smooth
sex-specific volumetric registration and measures every vertex against the
actual skin triangles. Skeleton and joint assets use the component-preserving
mode so whole bones, ligaments, capsules, and small extremity structures move
together before any final surface correction. Flexible muscle, nerve, and
vascular surfaces can use the outside-only correction for isolated superficial
crossings. `Scripts/register_vascular_pose.mjs` is retained only as the legacy
envelope-registration implementation; its axis-aligned checks are not sufficient
for production assets.

Install the Python packages in `Scripts/requirements-anatomy.txt`, then run
`Scripts/audit_anatomy_alignment.py` after regeneration. The audit checks every
runtime muscle, bone, joint, nerve, vessel, and organ vertex against the exact
female or male skin mesh rendered by the app. Critical hand systems also sample
edge midpoints and face interiors so geometry cannot bridge across finger gaps.

The full-body internal views use generated `*FullBodyLOD.usdc` assets. Run
`Scripts/generate_full_body_hand_lod.py` after changing any registered muscle,
skeleton, joint, nerve, vascular, hand, or body-skin mesh. The generator removes
the atlas's crowded hand geometry and registers compact NIMBLE muscles, tendons,
bones, joints, nerve sheaths, and nerve fascicles inside the exact low-detail
ghost skin rendered by the app. It preserves the original vessel networks
through the wrist, then replaces their crowded hand geometry with separate,
skin-fitted palmar and dorsal arterial/venous networks. Dedicated hand views
continue to use the original high-detail NIMBLE assets.

Focused left/right foot mode uses an exact crop of the registered runtime skin
for its lateral foot-and-ankle profile. The sole uses a foot-only plantar shell:
the body-area surface comes from the CC0 MakeHuman base foot, while internal
layers use the registered runtime skin cropped above the tarsals, straightened,
and fitted to that same plantar frame. The focused sole muscles and nerves are
purpose-built mobile presentations sampled from the exact internal shell
cross-section at every longitudinal position, so their volume follows the
individual female or male, left or right foot instead of being independently
stretched into it.

Run `Scripts/generate_foot_surface_assets.py` to regenerate the surfaces and
plantar soft tissue. The muscle plate includes the three superficial intrinsic
muscles, quadratus plantae, both flexor hallucis brevis heads, both adductor
hallucis heads, four lumbricals, and four interosseous bellies. Flexor tendons
are separate meshes and divide into paired distal slips. The nerve plate keeps
the tibial split, medial and lateral plantar trunks, deep lateral arch, common
digital branches, paired proper digital branches, and medial calcaneal
branches. Branch radius falls by order, and every nerve uses a bright fascicle
inside a translucent epineurial sheath. This avoids the atlas-slice shards,
parallel wires, and tangled strands that are unsuitable for a close mobile
view while retaining the recognizable anatomical hierarchy.

Focused bones are generated directly from the named, full-resolution Z-Anatomy
tibia, fibula, tarsals, metatarsals, sesamoids, and phalanges with
`Scripts/generate_focused_foot_skeleton_assets.py`. Side and sole assets each
register the complete named assembly directly to their exact presentation
shell. Plantar registration preserves all 27 foot-bone nodes as one assembly,
orients the hallux medially, smoothly centers the hindfoot without moving the
toe rays, then fits every bone's face interiors inside the shell. Generation
fails if a ray is missing, mirrored, compressed, or if the calcaneus leaves the
heel centerline. The same script derives compact joint markers from adjacent
bone surfaces. Run
`Scripts/generate_foot_detail_assets.rb` after changing a registered side-view
muscle or nerve source, then run `Scripts/fit_focused_foot_assets.py`. The final
audit samples vertices, edge midpoints, and face interiors so a large triangle
cannot bridge outside a concave toe or arch boundary. The complete source
systems stay outside the app bundle.

See `LittleWindows/Resources/BodyAnatomy/ATTRIBUTION.md` for sources and
licenses.
