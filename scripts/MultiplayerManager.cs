using Godot;
using System.Collections.Generic;

/// <summary>
/// Autoload singleton — manages ENet peer lifecycle and player registry.
/// Host calls HostGame(); clients call JoinGame(ip, port).
/// All peers share the Players dictionary, kept in sync via ReceivePlayerInfo RPC.
/// </summary>
public partial class MultiplayerManager : Node
{
    public const int DefaultPort = 7777;
    public const int MaxPlayers = 8;

    [Signal] public delegate void PlayerConnectedEventHandler(long id, string playerName);
    [Signal] public delegate void PlayerDisconnectedEventHandler(long id);
    [Signal] public delegate void ConnectionFailedEventHandler();
    [Signal] public delegate void ServerDisconnectedEventHandler();

    public Dictionary<long, string> Players { get; private set; } = new();
    public string LocalPlayerName { get; set; } = "Player";
    public bool IsHost => Multiplayer.IsServer();

    public override void _Ready()
    {
        Multiplayer.PeerDisconnected += OnPeerDisconnected;
        Multiplayer.ConnectedToServer += OnConnectedToServer;
        Multiplayer.ConnectionFailed += OnConnectionFailed;
        Multiplayer.ServerDisconnected += OnServerDisconnected;
    }

    public Error HostGame(int port = DefaultPort)
    {
        var peer = new ENetMultiplayerPeer();
        var error = peer.CreateServer(port, MaxPlayers);
        if (error != Error.Ok)
            return error;

        Multiplayer.MultiplayerPeer = peer;
        Players.Clear();
        Players[1] = LocalPlayerName;
        EmitSignal(SignalName.PlayerConnected, 1L, LocalPlayerName);
        return Error.Ok;
    }

    public Error JoinGame(string address, int port = DefaultPort)
    {
        var peer = new ENetMultiplayerPeer();
        var error = peer.CreateClient(address, port);
        if (error != Error.Ok)
            return error;

        Multiplayer.MultiplayerPeer = peer;
        return Error.Ok;
    }

    public void Disconnect()
    {
        Players.Clear();
        if (Multiplayer.MultiplayerPeer != null)
        {
            Multiplayer.MultiplayerPeer.Close();
            Multiplayer.MultiplayerPeer = null;
        }
    }

    private void OnPeerDisconnected(long id)
    {
        Players.Remove(id);
        EmitSignal(SignalName.PlayerDisconnected, id);
    }

    private void OnConnectedToServer()
    {
        long myId = (long)Multiplayer.GetUniqueId();
        Players[myId] = LocalPlayerName;
        EmitSignal(SignalName.PlayerConnected, myId, LocalPlayerName);
        // Introduce ourselves to the host; host will distribute all current players back.
        RpcId(1, MethodName.ReceivePlayerInfo, myId, LocalPlayerName);
    }

    private void OnConnectionFailed()
    {
        Multiplayer.MultiplayerPeer = null;
        EmitSignal(SignalName.ConnectionFailed);
    }

    private void OnServerDisconnected()
    {
        Players.Clear();
        Multiplayer.MultiplayerPeer = null;
        EmitSignal(SignalName.ServerDisconnected);
    }

    /// <summary>
    /// Called by any peer to register a player. Only the host processes the
    /// fan-out logic; clients just update their local registry.
    /// </summary>
    [Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false,
         TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
    private void ReceivePlayerInfo(long peerId, string playerName)
    {
        // Reject spoofed registrations: the claimed peerId must match the actual sender.
        if (Multiplayer.IsServer() && peerId != (long)Multiplayer.GetRemoteSenderId())
            return;

        Players[peerId] = playerName;
        EmitSignal(SignalName.PlayerConnected, peerId, playerName);

        if (!Multiplayer.IsServer())
            return;

        // Send all currently known players (except the new one) to the new peer.
        foreach (var (id, name) in Players)
        {
            if (id != peerId)
                RpcId(peerId, MethodName.ReceivePlayerInfo, id, name);
        }

        // Broadcast the new peer to all existing connected clients (not self/host).
        foreach (var existingId in Multiplayer.GetPeers())
        {
            long lid = (long)existingId;
            if (lid != peerId)
                RpcId(lid, MethodName.ReceivePlayerInfo, peerId, playerName);
        }
    }
}
