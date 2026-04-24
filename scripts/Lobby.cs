using Godot;

public partial class Lobby : Control
{
    private MultiplayerManager _manager;
    private LineEdit _playerNameInput;
    private LineEdit _portInput;
    private LineEdit _ipInput;
    private LineEdit _joinPortInput;
    private ItemList _playerList;
    private Label _statusLabel;
    private Button _startButton;
    private Control _hostSection;
    private Control _joinSection;
    private Control _lobbySection;

    public override void _Ready()
    {
        _manager = GetNode<MultiplayerManager>("/root/MultiplayerManager");

        var vbox = GetNode("Panel/MarginContainer/VBoxContainer");
        _playerNameInput = vbox.GetNode<LineEdit>("PlayerNameRow/PlayerNameInput");
        _portInput       = vbox.GetNode<LineEdit>("HostSection/PortRow/PortInput");
        _hostSection     = vbox.GetNode<Control>("HostSection");
        _ipInput         = vbox.GetNode<LineEdit>("JoinSection/JoinIPRow/IPInput");
        _joinPortInput   = vbox.GetNode<LineEdit>("JoinSection/JoinIPRow/JoinPortInput");
        _joinSection     = vbox.GetNode<Control>("JoinSection");
        _lobbySection    = vbox.GetNode<Control>("LobbySection");
        _playerList      = vbox.GetNode<ItemList>("LobbySection/PlayerList");
        _startButton     = vbox.GetNode<Button>("LobbySection/StartButton");
        _statusLabel     = vbox.GetNode<Label>("StatusLabel");

        vbox.GetNode<Button>("HostSection/HostButton").Pressed      += OnHostPressed;
        vbox.GetNode<Button>("JoinSection/JoinButton").Pressed      += OnJoinPressed;
        vbox.GetNode<Button>("LobbySection/DisconnectButton").Pressed += OnDisconnectPressed;
        _startButton.Pressed += OnStartPressed;

        _manager.PlayerConnected     += OnPlayerConnected;
        _manager.PlayerDisconnected  += OnPlayerDisconnected;
        _manager.ConnectionFailed    += OnConnectionFailed;
        _manager.ServerDisconnected  += OnServerDisconnected;

        SetLobbyVisible(false);
    }

    private void SetLobbyVisible(bool connected)
    {
        _hostSection.Visible = !connected;
        _joinSection.Visible = !connected;
        _lobbySection.Visible = connected;
        _playerNameInput.Editable = !connected;
    }

    private void OnHostPressed()
    {
        _manager.LocalPlayerName = SanitizeName(_playerNameInput.Text);

        int port = ParsePort(_portInput.Text);
        var error = _manager.HostGame(port);
        if (error == Error.Ok)
        {
            _statusLabel.Text = $"Hosting on port {port} — waiting for players...";
            SetLobbyVisible(true);
            _startButton.Visible = true;
            RefreshPlayerList();
        }
        else
        {
            _statusLabel.Text = $"Failed to host: {error}";
        }
    }

    private void OnJoinPressed()
    {
        if (Multiplayer.MultiplayerPeer != null) return;

        _manager.LocalPlayerName = SanitizeName(_playerNameInput.Text);

        string ip = _ipInput.Text.Trim();
        if (string.IsNullOrEmpty(ip))
            ip = "127.0.0.1";

        int port = ParsePort(_joinPortInput.Text);
        _statusLabel.Text = $"Connecting to {ip}:{port}…";

        var error = _manager.JoinGame(ip, port);
        if (error != Error.Ok)
            _statusLabel.Text = $"Failed to connect: {error}";
    }

    private void OnDisconnectPressed()
    {
        _manager.Disconnect();
        SetLobbyVisible(false);
        _playerList.Clear();
        _statusLabel.Text = "Disconnected.";
    }

    private void OnStartPressed()
    {
        if (!_manager.IsHost) return;
        if (_manager.Players.Count < 2)
        {
            _statusLabel.Text = "Need at least 2 players to start.";
            return;
        }
        Rpc(MethodName.StartGame);
    }

    [Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true,
         TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
    private void StartGame()
    {
        GetTree().ChangeSceneToFile("res://scenes/Game.tscn");
    }

    private void OnPlayerConnected(long id, string playerName)
    {
        RefreshPlayerList();

        if (_manager.IsHost)
        {
            _statusLabel.Text = $"{playerName} joined the lobby.";
        }
        else if (!_lobbySection.Visible)
        {
            SetLobbyVisible(true);
            _startButton.Visible = false;
            _statusLabel.Text = "Connected! Waiting for host to start…";
        }
        else
        {
            _statusLabel.Text = $"{_manager.Players.Count} player(s) in lobby.";
        }
    }

    private void OnPlayerDisconnected(long id)
    {
        RefreshPlayerList();
        _statusLabel.Text = "A player left the lobby.";
    }

    private void OnConnectionFailed()
    {
        SetLobbyVisible(false);
        _statusLabel.Text = "Connection failed. Check IP and port.";
    }

    private void OnServerDisconnected()
    {
        SetLobbyVisible(false);
        _playerList.Clear();
        _statusLabel.Text = "Disconnected from server.";
    }

    private void RefreshPlayerList()
    {
        _playerList.Clear();
        foreach (var (id, name) in _manager.Players)
            _playerList.AddItem(id == 1 ? $"{name} (Host)" : name);
    }

    private static string SanitizeName(string raw)
    {
        string trimmed = raw?.Trim() ?? "";
        return string.IsNullOrEmpty(trimmed) ? "Player" : trimmed;
    }

    private static int ParsePort(string raw)
    {
        if (int.TryParse(raw?.Trim(), out int p) && p >= 1 && p <= 65535)
            return p;
        return MultiplayerManager.DefaultPort;
    }
}
