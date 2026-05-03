# scenes/die.tscn

Prefab for a single die. Root: `RigidBody3D` (starts frozen), `PhysicsMaterial` (bounce=0, friction=0.8, linear_damp=0.5, angular_damp=1.5). Children: `Mesh` (MeshInstance3D with 0.4³ BoxMesh, beige material) and `Collision` (BoxShape3D 0.4³). Script: `scripts/die.gd`.
