using Godot;
using System;
using System.Collections.Generic;
using System.Linq;

public partial class GameScene : Control
{
    private const int PlayerCount = 2;
    private const int WinScore = 10000;
    private const int DiceCount = 6;

    private int[] _playerScores = new int[PlayerCount];
    private int _currentPlayer;
    private int _turnScore;
    private int[] _diceValues = new int[DiceCount];
    private bool[] _diceKept = new bool[DiceCount];
    private bool[] _diceSelected = new bool[DiceCount];
    private bool _hasRolled;
    private bool _gameOver;

    private Label[] _playerScoreLabels = new Label[PlayerCount];
    private Label _turnLabel = null!;
    private Label _turnScoreLabel = null!;
    private Label _messageLabel = null!;
    private Button[] _diceButtons = new Button[DiceCount];
    private Button _rollButton = null!;
    private Button _bankButton = null!;

    private readonly RandomNumberGenerator _rng = new();

    public override void _Ready()
    {
        SetAnchorsPreset(LayoutPreset.FullRect);
        BuildUI();
        StartTurn();
    }

    private void BuildUI()
    {
        var bg = new ColorRect { Color = new Color(0.12f, 0.12f, 0.18f) };
        bg.SetAnchorsPreset(LayoutPreset.FullRect);
        AddChild(bg);

        BuildScorePanel();
        BuildGameUI();
    }

    private void BuildScorePanel()
    {
        var panel = new PanelContainer { Position = new Vector2(10, 10) };
        AddChild(panel);

        var vbox = new VBoxContainer();
        vbox.AddThemeConstantOverride("separation", 6);
        vbox.CustomMinimumSize = new Vector2(190, 0);
        panel.AddChild(vbox);

        var title = new Label
        {
            Text = "── SCORES ──",
            HorizontalAlignment = HorizontalAlignment.Center
        };
        title.AddThemeFontSizeOverride("font_size", 16);
        vbox.AddChild(title);

        for (int i = 0; i < PlayerCount; i++)
        {
            _playerScoreLabels[i] = new Label();
            _playerScoreLabels[i].AddThemeFontSizeOverride("font_size", 15);
            vbox.AddChild(_playerScoreLabels[i]);
        }

        var winNote = new Label
        {
            Text = $"First to {WinScore:N0}",
            HorizontalAlignment = HorizontalAlignment.Center,
            Modulate = new Color(0.75f, 0.75f, 0.75f)
        };
        winNote.AddThemeFontSizeOverride("font_size", 12);
        vbox.AddChild(winNote);
    }

    private void BuildGameUI()
    {
        var center = new VBoxContainer();
        center.SetAnchorsPreset(LayoutPreset.FullRect);
        center.Alignment = BoxContainer.AlignmentMode.Center;
        center.AddThemeConstantOverride("separation", 18);
        AddChild(center);

        _turnLabel = new Label { HorizontalAlignment = HorizontalAlignment.Center };
        _turnLabel.AddThemeFontSizeOverride("font_size", 32);
        center.AddChild(_turnLabel);

        _turnScoreLabel = new Label { HorizontalAlignment = HorizontalAlignment.Center };
        _turnScoreLabel.AddThemeFontSizeOverride("font_size", 22);
        center.AddChild(_turnScoreLabel);

        var diceRow = new HBoxContainer { Alignment = BoxContainer.AlignmentMode.Center };
        diceRow.AddThemeConstantOverride("separation", 10);
        center.AddChild(diceRow);

        for (int i = 0; i < DiceCount; i++)
        {
            _diceButtons[i] = new Button
            {
                Text = "?",
                CustomMinimumSize = new Vector2(70, 70)
            };
            _diceButtons[i].AddThemeFontSizeOverride("font_size", 30);
            diceRow.AddChild(_diceButtons[i]);
            int idx = i;
            _diceButtons[i].Pressed += () => OnDiePressed(idx);
        }

        _messageLabel = new Label
        {
            HorizontalAlignment = HorizontalAlignment.Center,
            AutowrapMode = TextServer.AutowrapMode.Word
        };
        _messageLabel.AddThemeFontSizeOverride("font_size", 18);
        _messageLabel.CustomMinimumSize = new Vector2(500, 0);
        center.AddChild(_messageLabel);

        var buttonRow = new HBoxContainer { Alignment = BoxContainer.AlignmentMode.Center };
        buttonRow.AddThemeConstantOverride("separation", 20);
        center.AddChild(buttonRow);

        _rollButton = new Button
        {
            Text = "Roll Dice",
            CustomMinimumSize = new Vector2(150, 55)
        };
        _rollButton.AddThemeFontSizeOverride("font_size", 20);
        _rollButton.Pressed += OnRollPressed;
        buttonRow.AddChild(_rollButton);

        _bankButton = new Button
        {
            Text = "Bank Score",
            CustomMinimumSize = new Vector2(150, 55),
            Disabled = true
        };
        _bankButton.AddThemeFontSizeOverride("font_size", 20);
        _bankButton.Pressed += OnBankPressed;
        buttonRow.AddChild(_bankButton);

        var hint = new Label
        {
            Text = "1=100  5=50  Three-of-a-kind: face×100 (three 1s=1000)  Straight/3-pairs=1500",
            HorizontalAlignment = HorizontalAlignment.Center,
            Modulate = new Color(0.65f, 0.65f, 0.65f),
            AutowrapMode = TextServer.AutowrapMode.Word
        };
        hint.AddThemeFontSizeOverride("font_size", 13);
        center.AddChild(hint);
    }

    private void StartTurn()
    {
        _turnScore = 0;
        _hasRolled = false;
        Array.Fill(_diceKept, false);
        Array.Fill(_diceSelected, false);
        Array.Fill(_diceValues, 0);
        _messageLabel.Text = $"Player {_currentPlayer + 1}: press Roll Dice to begin!";
        UpdateUI();
    }

    private void OnRollPressed()
    {
        if (_gameOver) return;

        int selectedScore = CalculateSelectedScore();
        if (_hasRolled && selectedScore == 0)
        {
            _messageLabel.Text = "Select at least one scoring die before rolling again!";
            return;
        }

        if (_hasRolled && selectedScore > 0)
        {
            for (int i = 0; i < DiceCount; i++)
                if (_diceSelected[i]) _diceKept[i] = true;
            _turnScore += selectedScore;
            Array.Fill(_diceSelected, false);
        }

        // Hot Dice: all dice kept — free them all and roll fresh
        if (_diceKept.All(k => k))
            Array.Fill(_diceKept, false);

        for (int i = 0; i < DiceCount; i++)
        {
            if (!_diceKept[i])
                _diceValues[i] = _rng.RandiRange(1, 6);
        }

        _hasRolled = true;

        if (!AnyFreeDiceCanScore())
        {
            _messageLabel.Text = $"Farkle! No scoring dice. Player {_currentPlayer + 1} scores nothing this turn.";
            _turnScore = 0;
            NextPlayer();
            return;
        }

        _messageLabel.Text = _turnScore > 0
            ? $"Accumulated: {_turnScore} pts. Select more dice, then roll or bank."
            : "Select scoring dice, then roll again or bank.";

        UpdateUI();
    }

    private void OnBankPressed()
    {
        if (_gameOver || !_hasRolled) return;

        int selectedScore = CalculateSelectedScore();
        if (selectedScore == 0 && _turnScore == 0)
        {
            _messageLabel.Text = "Select scoring dice before banking!";
            return;
        }

        int totalBanked = _turnScore + selectedScore;
        _playerScores[_currentPlayer] += totalBanked;

        if (_playerScores[_currentPlayer] >= WinScore)
        {
            _gameOver = true;
            _rollButton.Disabled = true;
            _bankButton.Disabled = true;
            _messageLabel.Text = $"Player {_currentPlayer + 1} wins with {_playerScores[_currentPlayer]:N0} points!";
            UpdateScorePanel();
            return;
        }

        _messageLabel.Text = $"Player {_currentPlayer + 1} banks {totalBanked} pts. Total: {_playerScores[_currentPlayer]:N0}";
        NextPlayer();
    }

    private void OnDiePressed(int index)
    {
        if (!_hasRolled || _diceKept[index] || _gameOver) return;
        _diceSelected[index] = !_diceSelected[index];
        UpdateDiceDisplay();
        _turnScoreLabel.Text = $"Turn Score: {_turnScore + CalculateSelectedScore()}";
    }

    private void NextPlayer()
    {
        _currentPlayer = (_currentPlayer + 1) % PlayerCount;
        UpdateScorePanel();
        StartTurn();
    }

    private bool AnyFreeDiceCanScore()
    {
        var free = new List<int>(DiceCount);
        for (int i = 0; i < DiceCount; i++)
            if (!_diceKept[i]) free.Add(_diceValues[i]);

        if (free.Count == 0) return false;
        if (free.Contains(1) || free.Contains(5)) return true;
        return free.GroupBy(d => d).Any(g => g.Count() >= 3);
    }

    private int CalculateSelectedScore()
    {
        var selected = new List<int>(DiceCount);
        for (int i = 0; i < DiceCount; i++)
            if (_diceSelected[i] && !_diceKept[i])
                selected.Add(_diceValues[i]);
        return ScoreDice(selected);
    }

    private static int ScoreDice(List<int> dice)
    {
        if (dice.Count == 0) return 0;

        if (dice.Count == 6 && dice.OrderBy(d => d).SequenceEqual(new[] { 1, 2, 3, 4, 5, 6 }))
            return 1500;

        if (dice.Count == 6)
        {
            var grouped = dice.GroupBy(d => d).ToList();
            if (grouped.Count == 3 && grouped.All(g => g.Count() == 2))
                return 1500;
        }

        var counts = dice.GroupBy(d => d).ToDictionary(g => g.Key, g => g.Count());
        int score = 0;

        foreach (var (face, count) in counts)
        {
            if (count >= 3)
            {
                int baseScore = face == 1 ? 1000 : face * 100;
                score += baseScore * (1 << (count - 3));
            }
            else
            {
                if (face == 1) score += count * 100;
                else if (face == 5) score += count * 50;
            }
        }

        return score;
    }

    private void UpdateUI()
    {
        UpdateScorePanel();
        _turnLabel.Text = _gameOver ? "Game Over!" : $"Player {_currentPlayer + 1}'s Turn";
        _turnScoreLabel.Text = $"Turn Score: {_turnScore + CalculateSelectedScore()}";
        UpdateDiceDisplay();
        _bankButton.Disabled = !_hasRolled || (_turnScore == 0 && CalculateSelectedScore() == 0);
    }

    private void UpdateScorePanel()
    {
        for (int i = 0; i < PlayerCount; i++)
        {
            string arrow = !_gameOver && i == _currentPlayer ? " ◄" : "";
            _playerScoreLabels[i].Text = $"  P{i + 1}: {_playerScores[i]:N0}{arrow}";
        }
    }

    private void UpdateDiceDisplay()
    {
        for (int i = 0; i < DiceCount; i++)
        {
            var btn = _diceButtons[i];
            if (_diceValues[i] == 0)
            {
                btn.Text = "?";
                btn.Modulate = new Color(0.5f, 0.5f, 0.5f);
                btn.Disabled = true;
            }
            else if (_diceKept[i])
            {
                btn.Text = DiceFace(_diceValues[i]);
                btn.Modulate = new Color(0.4f, 1f, 0.4f);
                btn.Disabled = true;
            }
            else
            {
                btn.Text = DiceFace(_diceValues[i]);
                btn.Modulate = _diceSelected[i] ? new Color(1f, 1f, 0.3f) : Colors.White;
                btn.Disabled = !_hasRolled || _gameOver;
            }
        }
    }

    private static string DiceFace(int value) => value switch
    {
        1 => "⚀", 2 => "⚁", 3 => "⚂",
        4 => "⚃", 5 => "⚄", 6 => "⚅",
        _ => value.ToString()
    };
}
