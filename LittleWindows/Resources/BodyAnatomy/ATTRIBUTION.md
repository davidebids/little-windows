# Body anatomy asset attribution

The bundled anatomy meshes are used locally by Little Windows. They are not uploaded or used for diagnosis.

## HuBMAP Human Reference Atlas

Male and female skin and organ meshes are adapted from the HuBMAP Human Reference Atlas (HRA) 3D Reference Object Library, version 1.2.

- Source: https://humanatlas.io/3d-reference-library
- Model repository: https://github.com/hubmapconsortium/ccf-releases/tree/main/v1.2/models
- License: Creative Commons Attribution 4.0 International (CC BY 4.0), https://creativecommons.org/licenses/by/4.0/

## Z-Anatomy muscular, skeletal, joint, nervous, and vascular systems

The full muscular, skeletal, joint, nervous, and vascular system meshes are adapted
from Z-Anatomy. The muscular and skeletal source model is distributed through the
open-source Body Anatomy 3D Viewer project by Hans-Peter Frei. The nervous,
joint, and vascular system source models are distributed through the open-source
Anatomy Simulator project by Murat Altun. These assets remain licensed under
Creative Commons Attribution-ShareAlike 4.0 International (CC BY-SA 4.0).

- Muscular and skeletal source project: https://github.com/hpfrei/body-anatomy-3d-viewer
- Nervous and vascular system source project: https://github.com/DrMuratAltun/anatomi-simulatoru
- Z-Anatomy model repository: https://github.com/Z-Anatomy/Models-of-human-anatomy
- Z-Anatomy: https://www.z-anatomy.com/
- License: https://creativecommons.org/licenses/by-sa/4.0/

The five systems were kept in their shared atlas coordinates and globally
registered to the female and male HuBMAP surface models. Each system then
receives a smooth sex-specific volumetric registration against the matching
skin. Final containment is measured against the actual skin triangles rather
than a two-dimensional or axis-aligned envelope. Skeleton and joint corrections
preserve connected components so individual bones, ligaments, capsules, and
small extremity structures retain their shape. Skeleton
simplification is performed per bone so the small wrist, finger, ankle, and
toe bones retain their source detail. Muscular and nervous system meshes retain
their complete source topology because whole-system simplification erases small
facial muscles and peripheral nerve branches in the hands and feet. The joint
system includes ligaments, capsules, menisci, labrums, and small wrist, hand,
ankle, and foot structures generated with the same component-preserving process.
Assets are
converted to Apple's USD format and reduced for mobile rendering only where the
anatomical structure remains intact. Vascular reduction is performed per
connected branch, preserving small vessels in full instead of fragmenting the
vascular tree. Arterial and venous structures are combined separately so the app
can render them with distinct materials. The modified assets are distributed
under CC BY-SA 4.0.

All runtime layer assets are checked vertex-by-vertex against the exact female
or male runtime skin after generation, including every separately bundled organ.

## MakeHuman focused plantar surface

The compact plantar foot meshes are adapted from the MakeHuman base mesh. The
lateral foot-and-ankle presentation uses the already-attributed registered HRA
runtime skin so its outline remains identical to the internal anatomy frame.

- Source: https://github.com/makehumancommunity/makehuman/blob/master/makehuman/data/3dobjs/base.obj
- License: CC0 1.0 Universal, https://github.com/makehumancommunity/makehuman/blob/master/LICENSE.md

The MakeHuman mesh is cropped, fitted to the registered female and male foot
frames, and converted to Apple's USD format. No source-only MakeHuman asset is
included in the installed application bundle.

## NIMBLE hand anatomy

The focused and full-body hand skin, bone, joint, and intrinsic-muscle meshes are
adapted from NIMBLE: A Non-rigid Hand Model with Bones and Muscles. The hand
atlas keeps all of those systems in a single native topology and pose. Little
Windows adds registered flexor/extensor tendon geometry and paired palmar and
dorsal nerve cords for the interactive views. The full-body hand systems replace
the less detailed atlas hands and are fitted inside the exact low-detail skin
shell rendered at runtime. The original arterial and venous systems are retained
through the wrist; compact palmar and dorsal hand networks replace the crowded
atlas branches and are fitted to that same runtime shell.

- Source: https://github.com/reyuwei/NIMBLE_model
- Paper: https://doi.org/10.1145/3528223.3530079
- License: MIT; the bundled notice is in `NIMBLE-LICENSE.md`.

The source meshes were converted to Apple's USD format, reduced where necessary for mobile rendering, aligned to a shared coordinate system, and assigned app-specific materials. Anatomical visualization is provided for location selection only and is not a diagnostic or clinical reference.
