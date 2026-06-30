Hot Dice is a game built in Godot 4.5. It is a 3D multiplayer game built off of the basic rules of Farkle.

At the start of every session read the last few entries of the PROGRESS.md file if there are any.
You will add update to the PROGRESS.md file in the form of short one sentence updates.

## GDScript Strict Typing

This project treats type inference warnings as errors. Always use explicit type annotations — never rely on `:=` when the right-hand side returns a Variant or an untyped value. Common cases that cause parse errors:

- `Dictionary.get()` always returns Variant. Use `as int` (or the appropriate type) on the result, or declare with an explicit type: `var x: int = dict.get(key, default) as int`.
- Array indexing always returns Variant, even on typed arrays like `Array[float]`. Use `var x: float = my_array[i]`, not `var x := my_array[i]`.
- `round()`, `floor()`, `ceil()`, `abs()` return Variant. Always declare the variable with an explicit type: `var x: float = round(...)`.
- `as` casts infer a nullable type but should still be declared explicitly: `var mb: InputEventMouseButton = event as InputEventMouseButton`.
- Array literals assigned with `:=` are inferred as untyped `Array`. Use `var x: Array[Vector3] = [...]` so element access doesn't return Variant.
- `Array.duplicate()` returns untyped `Array` regardless of the source array's type. Use `var x: Array[int] = my_typed_array.duplicate()`.
- Any function that returns an untyped value or a base class (e.g. `RigidBody3D` when the actual type is a subclass) needs a cast before being assigned with `:=`.
- Prefer `: TypeName =` over `:=` whenever the inferred type would be Variant.