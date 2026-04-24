using Godot;

/// <summary>
/// A single die that displays pips for values 1–6.
/// Roll() randomises the value; IsHeld highlights the die as held.
/// </summary>
[Tool]
public partial class Dice : Control
{
	private int _value = 1;
	private bool _isHeld;

	[Export(PropertyHint.Range, "1,6")]
	public int Value
	{
		get => _value;
		set
		{
			_value = Mathf.Clamp(value, 1, 6);
			QueueRedraw();
		}
	}

	[Export]
	public bool IsHeld
	{
		get => _isHeld;
		set
		{
			_isHeld = value;
			QueueRedraw();
		}
	}

	public void Roll()
	{
		Value = GD.RandRange(1, 6);
	}

	public override void _Draw()
	{
		float w = Size.X;
		float pad = w * 0.12f;

		// Background
		var bgColor = _isHeld ? new Color(0.98f, 0.95f, 0.55f) : new Color(0.97f, 0.97f, 0.97f);
		DrawRect(new Rect2(Vector2.Zero, Size), bgColor);

		// Border
		var borderColor = _isHeld ? new Color(0.75f, 0.65f, 0.0f) : new Color(0.25f, 0.25f, 0.25f);
		DrawRect(new Rect2(Vector2.Zero, Size), borderColor, false, 2.5f);

		// Pips
		float pipR = w * 0.08f;
		var pipColor = new Color(0.1f, 0.1f, 0.1f);
		float inner = w - pad * 2f;

		foreach (var n in PipNormalized(_value))
		{
			var pos = new Vector2(pad + n.X * inner, pad + n.Y * inner);
			DrawCircle(pos, pipR, pipColor);
		}
	}

	// Normalised (0..1) pip positions for each face value.
	private static Vector2[] PipNormalized(int value) => value switch
	{
		1 => new[] { new Vector2(0.5f, 0.5f) },
		2 => new[] { new Vector2(0.25f, 0.25f), new Vector2(0.75f, 0.75f) },
		3 => new[] { new Vector2(0.25f, 0.25f), new Vector2(0.5f, 0.5f), new Vector2(0.75f, 0.75f) },
		4 => new[] { new Vector2(0.25f, 0.25f), new Vector2(0.75f, 0.25f), new Vector2(0.25f, 0.75f), new Vector2(0.75f, 0.75f) },
		5 => new[] { new Vector2(0.25f, 0.25f), new Vector2(0.75f, 0.25f), new Vector2(0.5f, 0.5f), new Vector2(0.25f, 0.75f), new Vector2(0.75f, 0.75f) },
		6 => new[] { new Vector2(0.25f, 0.2f), new Vector2(0.75f, 0.2f), new Vector2(0.25f, 0.5f), new Vector2(0.75f, 0.5f), new Vector2(0.25f, 0.8f), new Vector2(0.75f, 0.8f) },
		_ => System.Array.Empty<Vector2>(),
	};
}
