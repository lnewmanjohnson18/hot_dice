# scripts/table.gd

Attached to the `Table` StaticBody3D. On `_ready`, procedurally generates 16 wall segments around a circle (WALL_RADIUS=4.25, so inner face flush with felt edge at radius 4.2). Each segment gets both a `CollisionShape3D` (BoxShape3D) and a `MeshInstance3D` (BoxMesh) in brown. Wall is 1.0 unit tall, centered at Y=0.5, so it runs from Y=0 (felt surface) to Y=1.0 with no gap.
