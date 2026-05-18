Hot Dice is a game built in Godot 4.5. It is a 3D multiplayer game built off of the basic rules of Farkle.

At the start of every session read the last few entries of the PROGRESS.md file if there are any.
You will add update to the PROGRESS.md file in the form of short one sentence updates.

## GDScript Strict Typing

This project treats type inference warnings as errors. Always use explicit type annotations — never rely on `:=` when the right-hand side returns a Variant or an untyped value. Common cases that cause parse errors:

- `Dictionary.get()` always returns Variant. Use `as int` (or the appropriate type) on the result, or declare with an explicit type: `var x: int = dict.get(key, default) as int`.
- Any function that returns an untyped value or a base class (e.g. `RigidBody3D` when the actual type is a subclass) needs a cast before being assigned with `:=`.
- Prefer `: TypeName =` over `:=` whenever the inferred type would be Variant.