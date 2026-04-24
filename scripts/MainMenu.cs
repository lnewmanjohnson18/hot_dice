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
		// TODO: Load game scene when implemented
		GD.Print("Play pressed");
	}

	private void OnMultiplayerPressed()
	{
		// TODO: Load multiplayer scene when implemented
		GD.Print("Multiplayer pressed");
	}

	private void OnSettingsPressed()
	{
		// TODO: Load settings scene when implemented
		GD.Print("Settings pressed");
	}

	private void OnQuitPressed()
	{
		GetTree().Quit();
	}
}
