using Godot;

public partial class Game : Control
{
    private MultiplayerManager _manager;

    public override void _Ready()
    {
        _manager = GetNode<MultiplayerManager>("/root/MultiplayerManager");
        GetNode<Button>("VBoxContainer/BackButton").Pressed += OnBackPressed;
    }

    private void OnBackPressed()
    {
        _manager.Disconnect();
        GetTree().ChangeSceneToFile("res://scenes/Lobby.tscn");
    }
}
