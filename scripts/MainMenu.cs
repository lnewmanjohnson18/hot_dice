using Godot;

public partial class MainMenu : Control
{
	public override void _Ready()
	{
		GetNode<Button>("VBoxContainer/PlayButton").Pressed += OnPlayPressed;
		GetNode<Button>("VBoxContainer/MultiplayerButton").Pressed += OnMultiplayerPressed;
		GetNode<Button>("VBoxContainer/SettingsButton").Pressed += OnSettingsPressed;
		GetNode<Button>("VBoxContainer/QuitButton").Pressed += OnQuitPressed;
	}

	private void OnPlayPressed()
	{
	}

	private void OnMultiplayerPressed()
	{
	}

	private void OnSettingsPressed()
	{
	}

	private void OnQuitPressed()
	{
		GetTree().Quit();
	}
}
