import 'dart:math';
import 'package:flutter/material.dart';

void main() {
  runApp(const SaatAanthhApp());
}

class SaatAanthhApp extends StatelessWidget {
  const SaatAanthhApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Saat – Aanthh',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3949AB)),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

enum Suit { spades, hearts, diamonds, clubs }

enum Rank { seven, eight, nine, ten, jack, queen, king, ace }

int rankValue(Rank r) {
  switch (r) {
    case Rank.ace:
      return 14;
    case Rank.king:
      return 13;
    case Rank.queen:
      return 12;
    case Rank.jack:
      return 11;
    case Rank.ten:
      return 10;
    case Rank.nine:
      return 9;
    case Rank.eight:
      return 8;
    case Rank.seven:
      return 7;
  }
}

String suitSymbol(Suit s) {
  switch (s) {
    case Suit.spades:
      return '♠';
    case Suit.hearts:
      return '♥';
    case Suit.diamonds:
      return '♦';
    case Suit.clubs:
      return '♣';
  }
}

String suitName(Suit s) {
  switch (s) {
    case Suit.spades:
      return 'Spades';
    case Suit.hearts:
      return 'Hearts';
    case Suit.diamonds:
      return 'Diamonds';
    case Suit.clubs:
      return 'Clubs';
  }
}

String rankLabel(Rank r) {
  switch (r) {
    case Rank.ace:
      return 'A';
    case Rank.king:
      return 'K';
    case Rank.queen:
      return 'Q';
    case Rank.jack:
      return 'J';
    case Rank.ten:
      return '10';
    case Rank.nine:
      return '9';
    case Rank.eight:
      return '8';
    case Rank.seven:
      return '7';
  }
}

class GameCard {
  final Suit suit;
  final Rank rank;
  GameCard(this.suit, this.rank);

  @override
  String toString() => '${rankLabel(rank)}${suitSymbol(suit)}';
}

enum AiLevel { aggressive, strategic, relentless }

class PlayerZone {
  /// Private cards.
  final List<GameCard> hand = [];

  /// Visible row cards. Index 0..4, each may have an under card.
  final List<GameCard?> rowUp = List.filled(5, null);
  final List<GameCard?> rowDown = List.filled(5, null);

  /// For convenience: all playable cards (hand + rowUp)
  List<GameCard> playableCards() {
    final cards = <GameCard>[];
    cards.addAll(hand);
    for (final c in rowUp) {
      if (c != null) cards.add(c);
    }
    return cards;
  }

  bool hasSuitPlayable(Suit suit) {
    return playableCards().any((c) => c.suit == suit);
  }

  /// Remove a card from where it is (hand or rowUp). If from rowUp, reveal under card.
  /// Returns true if removal succeeded.
  bool playCard(GameCard card) {
    final idxHand = hand.indexWhere((c) => identical(c, card) || (c.suit == card.suit && c.rank == card.rank));
    if (idxHand != -1) {
      hand.removeAt(idxHand);
      return true;
    }
    for (int i = 0; i < 5; i++) {
      final up = rowUp[i];
      if (up != null && up.suit == card.suit && up.rank == card.rank) {
        rowUp[i] = rowDown[i];
        rowDown[i] = null;
        return true;
      }
    }
    return false;
  }
}

class GameState {
  final Random rng;
  final AiLevel aiLevel;

  final PlayerZone human = PlayerZone();
  final PlayerZone ai = PlayerZone();

  Suit? trump;

  /// caller = player who chose trump in this 15-round game.
  /// true => human is caller, false => AI is caller.
  bool humanIsCaller = true;

  int round = 1; // 1..15
  int humanTricks = 0;
  int aiTricks = 0;

  int humanPoints = 0; // match points across games
  int aiPoints = 0;

  /// leader: true => human leads, false => AI leads
  bool humanLeads = true;

  GameCard? leadCard;
  GameCard? responseCard;

  String message = '';

  GameState({required this.aiLevel, required int seed}) : rng = Random(seed);

  void newGame({required bool humanCaller}) {
    humanIsCaller = humanCaller;
    trump = null;
    round = 1;
    humanTricks = 0;
    aiTricks = 0;
    humanLeads = true; // as per rule: player 1 leads round 1. In our app, human is Player 1.
    leadCard = null;
    responseCard = null;
    message = '';

    // Build the 30-card deck: A,K,Q,J,10,9,8 of all suits + 7♠ and 7♥.
    final deck = <GameCard>[];
    final ranks = [Rank.ace, Rank.king, Rank.queen, Rank.jack, Rank.ten, Rank.nine, Rank.eight];
    for (final s in Suit.values) {
      for (final r in ranks) {
        deck.add(GameCard(s, r));
      }
    }
    deck.add(GameCard(Suit.spades, Rank.seven));
    deck.add(GameCard(Suit.hearts, Rank.seven));

    deck.shuffle(rng);

    // Deal: first 5 to P1(human), next 5 to P2(ai)
    human.hand
      ..clear()
      ..addAll(deck.sublist(0, 5));
    ai.hand
      ..clear()
      ..addAll(deck.sublist(5, 10));

    // Face-down rows: 11-15 for human, 16-20 for AI
    for (int i = 0; i < 5; i++) {
      human.rowDown[i] = deck[10 + i];
      ai.rowDown[i] = deck[15 + i];
    }

    // Face-up rows depend on how we generalize the caller postponement.
    // Original rules: 21-25 face-up on human row, 26-30 face-up on AI row.
    // In our app we always place these face-up rows; for caller postponement we allow the *caller* to peek 2
    // from their own upcoming face-up set before committing trump.

    for (int i = 0; i < 5; i++) {
      human.rowUp[i] = deck[20 + i]; // 21-25
      ai.rowUp[i] = deck[25 + i]; // 26-30
    }

    // Trump selection
    if (humanIsCaller) {
      message = 'You are the Caller (target 8). Choose trump now or tap Postpone.';
    } else {
      // AI chooses trump immediately (aggressive) using only its known cards: hand + face-up row.
      trump = _aiChooseTrump();
      message = 'AI is the Caller (target 8). Trump is ${suitName(trump!)}.';
    }
  }

  int targetForHuman() => humanIsCaller ? 8 : 7;
  int targetForAi() => humanIsCaller ? 7 : 8;

  /// The app's generalized postponement: caller can peek 2 cards from their own face-up row set
  /// (already visible in our layout). For faithfulness to your rule, if human is caller and postpones,
  /// we require picking exactly 2 cards to base trump selection on.
  ///
  /// Because our face-up row is already visible (as per rules after trump selection),
  /// the postponement UI will temporarily hide those 5 and allow peeking 2.

  Suit _aiChooseTrump() {
    // Evaluate suit strength from AI playable known at start: hand + rowUp.
    // Aggressive: prefers suits with more cards and higher ranks.
    final scores = <Suit, double>{
      for (final s in Suit.values) s: 0.0,
    };
    final all = [...ai.hand, ...ai.rowUp.whereType<GameCard>()];
    for (final c in all) {
      scores[c.suit] = (scores[c.suit] ?? 0) + (rankValue(c.rank) / 14.0) + 0.35;
    }
    // Add small randomness to avoid predictability
    for (final s in Suit.values) {
      scores[s] = (scores[s] ?? 0) + rng.nextDouble() * 0.05;
    }
    Suit best = Suit.spades;
    double bestScore = -1;
    for (final e in scores.entries) {
      if (e.value > bestScore) {
        bestScore = e.value;
        best = e.key;
      }
    }
    return best;
  }

  /// Determine winner of a trick.
  /// - If response is trump and lead isn't, response wins.
  /// - If both same suit, higher rank wins.
  /// - If both trump, higher trump wins.
  /// - If off-suit and not trump, lead wins.
  bool humanWinsTrick(GameCard lead, GameCard resp) {
    final t = trump;
    if (t != null) {
      final leadTrump = lead.suit == t;
      final respTrump = resp.suit == t;
      if (respTrump && !leadTrump) return false;
      if (leadTrump && !respTrump) return true;
      if (leadTrump && respTrump) {
        return rankValue(lead.rank) > rankValue(resp.rank);
      }
    }
    if (lead.suit == resp.suit) {
      return rankValue(lead.rank) > rankValue(resp.rank);
    }
    return true; // lead wins if responder did not follow suit and did not trump
  }

  /// Perform one full trick once human has chosen a lead if human leads, otherwise AI leads.
  void playLead(GameCard chosenByLeader) {
    if (trump == null) {
      message = 'Trump not selected yet.';
      return;
    }

    leadCard = null;
    responseCard = null;

    if (humanLeads) {
      // Human plays lead
      if (!human.playCard(chosenByLeader)) {
        message = 'Invalid play.';
        return;
      }
      leadCard = chosenByLeader;

      // AI responds
      final aiPlay = _aiRespondToLead(chosenByLeader);
      ai.playCard(aiPlay);
      responseCard = aiPlay;

      final humanWin = humanWinsTrick(chosenByLeader, aiPlay);
      _applyTrickResult(humanWin);
    } else {
      // AI plays lead
      final aiLead = chosenByLeader;
      if (!ai.playCard(aiLead)) {
        message = 'AI error: invalid play.';
        return;
      }
      leadCard = aiLead;

      // Human must respond (enforced by UI filtering outside)
      // In this function we only set lead, and wait for UI to call playResponse.
      message = 'AI led ${aiLead}. Your turn to respond.';
    }
  }

  /// Called when AI leads and human responds.
  void playResponseToAiLead(GameCard humanResponse) {
    if (leadCard == null || trump == null) {
      message = 'No active lead.';
      return;
    }
    if (!human.playCard(humanResponse)) {
      message = 'Invalid response.';
      return;
    }
    responseCard = humanResponse;

    // Determine winner: lead is AI's, response is human
    final humanWin = !humanWinsTrick(leadCard!, humanResponse) ? false : true;
    // Wait, humanWinsTrick expects lead by human and response by ai.
    // So invert using the same rules:
    final aiWins = _aiWinsTrick(leadCard!, humanResponse);
    _applyTrickResult(!aiWins);
  }

  bool _aiWinsTrick(GameCard leadByAi, GameCard humanResp) {
    // Mirror of humanWinsTrick: return true if AI wins
    final t = trump;
    if (t != null) {
      final leadTrump = leadByAi.suit == t;
      final respTrump = humanResp.suit == t;
      if (respTrump && !leadTrump) return false;
      if (leadTrump && !respTrump) return true;
      if (leadTrump && respTrump) {
        return rankValue(leadByAi.rank) > rankValue(humanResp.rank);
      }
    }
    if (leadByAi.suit == humanResp.suit) {
      return rankValue(leadByAi.rank) > rankValue(humanResp.rank);
    }
    return true;
  }

  void _applyTrickResult(bool humanWon) {
    if (humanWon) {
      humanTricks++;
      humanLeads = true;
      message = 'You won Round $round.';
    } else {
      aiTricks++;
      humanLeads = false;
      message = 'AI won Round $round.';
    }

    // Advance round
    round++;
    leadCard = null;
    responseCard = null;

    if (round > 15) {
      // End of game: compute points (extra wins beyond target)
      final hExtra = max(0, humanTricks - targetForHuman());
      final aExtra = max(0, aiTricks - targetForAi());
      humanPoints += hExtra;
      aiPoints += aExtra;
      message = 'Game over. You: $humanTricks tricks (extra $hExtra). AI: $aiTricks tricks (extra $aExtra).\n'
          'Points — You: $humanPoints | AI: $aiPoints. Tap New Game.';
    } else {
      // If AI leads next, it should auto-lead.
      if (!humanLeads) {
        final aiLead = _aiChooseLead();
        playLead(aiLead);
      }
    }
  }

  List<GameCard> _aiPlayable() {
    return ai.playableCards();
  }

  GameCard _aiRespondToLead(GameCard lead) {
    final playable = _aiPlayable();

    final canFollow = playable.where((c) => c.suit == lead.suit).toList();
    if (canFollow.isNotEmpty) {
      // Must follow suit. Choose according to AI level.
      // Determine which of these can win (higher rank).
      final winning = canFollow.where((c) => rankValue(c.rank) > rankValue(lead.rank)).toList();
      if (winning.isNotEmpty) {
        // Aggressive: play lowest winning to conserve strength
        winning.sort((a, b) => rankValue(a.rank).compareTo(rankValue(b.rank)));
        return winning.first;
      }
      // Can't win with suit; decide sacrifice. Aggressive/relentless may still dump lowest.
      canFollow.sort((a, b) => rankValue(a.rank).compareTo(rankValue(b.rank)));
      return canFollow.first;
    }

    // Can't follow suit.
    final t = trump!;
    final trumps = playable.where((c) => c.suit == t).toList();

    // Decide whether to trump or discard.
    final shouldTrump = _aiShouldTrump(lead);

    if (shouldTrump && trumps.isNotEmpty) {
      // Play lowest trump that still wins (any trump wins vs non-trump)
      trumps.sort((a, b) => rankValue(a.rank).compareTo(rankValue(b.rank)));
      return trumps.first;
    }

    // Discard lowest non-trump
    final nonTrumps = playable.where((c) => c.suit != t).toList();
    nonTrumps.sort((a, b) => rankValue(a.rank).compareTo(rankValue(b.rank)));
    return nonTrumps.isNotEmpty ? nonTrumps.first : (trumps..sort((a, b) => rankValue(a.rank).compareTo(rankValue(b.rank)))).first;
  }

  bool _aiShouldTrump(GameCard lead) {
    // Aggressive strategy aiming for more rounds.
    // Basic heuristic uses: current trick counts vs targets, remaining rounds.
    final remaining = 16 - round; // inclusive-ish
    final aiTarget = targetForAi();

    final aiNeeds = max(0, aiTarget - aiTricks);

    // Relentless: trump more often to control lead.
    if (aiLevel == AiLevel.relentless) {
      if (aiNeeds > 0) return true;
      // Even if target met, keep winning for points.
      return true;
    }

    // Strategic: trump if it meaningfully advances toward target or denies opponent.
    if (aiLevel == AiLevel.strategic) {
      // If human is close to target, deny by winning.
      final humanClose = humanTricks >= targetForHuman() - 1;
      if (humanClose) return true;
      // If AI still needs wins and rounds are getting low.
      if (aiNeeds >= (remaining / 2).ceil()) return true;
      // Otherwise conserve trumps unless late.
      return remaining <= 5;
    }

    // Aggressive: trump if AI still needs wins OR late game.
    return aiNeeds > 0 || remaining <= 6;
  }

  GameCard _aiChooseLead() {
    final playable = _aiPlayable();
    final t = trump!;

    // Aggressive lead selection: try to win and/or force opponent to waste trumps.
    // We'll pick a suit where AI is strong or where opponent likely can't follow (unknown).

    // Compute suit strength in playable cards.
    final strength = <Suit, double>{ for (final s in Suit.values) s: 0.0 };
    for (final c in playable) {
      strength[c.suit] = (strength[c.suit] ?? 0) + rankValue(c.rank) / 14.0 + 0.25;
    }

    // If relentless: often lead non-trump to try to pull out trumps, unless trump is very strong.
    if (aiLevel == AiLevel.relentless) {
      // Prefer a strong non-trump suit if available.
      Suit? bestNon;
      double best = -1;
      for (final s in Suit.values) {
        if (s == t) continue;
        final v = strength[s] ?? 0;
        if (v > best) { best = v; bestNon = s; }
      }
      if (bestNon != null && playable.any((c) => c.suit == bestNon)) {
        // Lead highest in that suit to maximize win chance.
        final list = playable.where((c) => c.suit == bestNon).toList();
        list.sort((a,b) => rankValue(b.rank).compareTo(rankValue(a.rank)));
        return list.first;
      }
    }

    // Otherwise: lead with a high card in a strong suit; if strategic, prefer opening row cards when possible.
    Suit bestSuit = Suit.spades;
    double bestScore = -1;
    for (final e in strength.entries) {
      if (e.value > bestScore) { bestScore = e.value; bestSuit = e.key; }
    }

    final candidates = playable.where((c) => c.suit == bestSuit).toList();
    candidates.sort((a,b) => rankValue(b.rank).compareTo(rankValue(a.rank)));

    // In strategic mode, sometimes lead mid card to conserve.
    if (aiLevel == AiLevel.strategic && candidates.length >= 2) {
      return candidates[candidates.length ~/ 2];
    }
    return candidates.first;
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  AiLevel _level = AiLevel.strategic;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Saat – Aanthh')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Play Player vs Computer', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Choose AI difficulty (all are aggressive and aim to win extra rounds):'),
            const SizedBox(height: 12),
            SegmentedButton<AiLevel>(
              segments: const [
                ButtonSegment(value: AiLevel.aggressive, label: Text('Aggressive')),
                ButtonSegment(value: AiLevel.strategic, label: Text('Strategic')),
                ButtonSegment(value: AiLevel.relentless, label: Text('Relentless')),
              ],
              selected: {_level},
              onSelectionChanged: (s) => setState(() => _level = s.first),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start'),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => GameScreen(level: _level)),
                );
              },
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            const Text('Rules snapshot', style: TextStyle(fontWeight: FontWeight.bold)),
            const Text('• 30 cards: A,K,Q,J,10,9,8 (all suits) + 7♠,7♥\n'
                '• Caller chooses trump; targets 8 wins vs 7\n'
                '• 15 rounds; winner leads next round\n'
                '• Must follow suit if possible; trump beats non-trump\n'
                '• Playing an open row card reveals the face-down card beneath it'),
          ],
        ),
      ),
    );
  }
}

class GameScreen extends StatefulWidget {
  final AiLevel level;
  const GameScreen({super.key, required this.level});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late GameState gs;

  bool _choosingTrump = false;
  bool _postponeMode = false;
  final Set<int> _peeked = {}; // indices 0..4 among human face-up row

  @override
  void initState() {
    super.initState();
    gs = GameState(aiLevel: widget.level, seed: DateTime.now().millisecondsSinceEpoch);
    gs.newGame(humanCaller: true);
    _choosingTrump = true;
  }

  void _startNextGame() {
    final nextCallerHuman = !gs.humanIsCaller; // alternate caller each 15-round game
    gs.newGame(humanCaller: nextCallerHuman);
    _choosingTrump = gs.humanIsCaller;
    _postponeMode = false;
    _peeked.clear();
    setState(() {});

    // If AI leads (possible after first round only) we auto-handle; start is always human lead.
  }

  List<GameCard> _humanPlayableForResponse() {
    final lead = gs.leadCard;
    final cards = gs.human.playableCards();
    if (lead == null) return cards;

    // Must follow suit if possible
    if (cards.any((c) => c.suit == lead.suit)) {
      return cards.where((c) => c.suit == lead.suit).toList();
    }
    return cards;
  }

  @override
  Widget build(BuildContext context) {
    final trump = gs.trump;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Saat – Aanthh'),
        actions: [
          IconButton(
            tooltip: 'New Game',
            icon: const Icon(Icons.refresh),
            onPressed: _startNextGame,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            _topStatus(trump),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _trickArea(),
                    const SizedBox(height: 12),
                    _aiArea(),
                    const SizedBox(height: 12),
                    _humanArea(),
                    const SizedBox(height: 8),
                    _messageBox(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topStatus(Suit? trump) {
    final caller = gs.humanIsCaller ? 'You' : 'AI';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Round: ${min(gs.round, 15)}/15', style: const TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('Caller: $caller  (Targets — You ${gs.targetForHuman()} / AI ${gs.targetForAi()})'),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text('Trump: ${trump == null ? '—' : suitName(trump)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('Tricks — You ${gs.humanTricks} : ${gs.aiTricks} AI'),
              ],
            ),
            const SizedBox(height: 4),
            Text('Match Points — You ${gs.humanPoints} : ${gs.aiPoints} AI'),
          ],
        ),
      ),
    );
  }

  Widget _trickArea() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Current Trick', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _bigCard('Lead', gs.leadCard)),
                const SizedBox(width: 10),
                Expanded(child: _bigCard('Response', gs.responseCard)),
              ],
            ),
            const SizedBox(height: 8),
            if (_choosingTrump && gs.humanIsCaller) _trumpChooser(),
          ],
        ),
      ),
    );
  }

  Widget _bigCard(String label, GameCard? card) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black26),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 8),
          Text(card?.toString() ?? '—', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _trumpChooser() {
    if (!_postponeMode) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Choose Trump', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: Suit.values.map((s) {
              return ElevatedButton(
                onPressed: () {
                  setState(() {
                    gs.trump = s;
                    _choosingTrump = false;
                    gs.message = 'Trump set to ${suitName(s)}. You lead Round 1.';
                  });
                },
                child: Text('${suitName(s)} ${suitSymbol(s)}'),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () {
              setState(() {
                _postponeMode = true;
                _peeked.clear();
                gs.message = 'Postponed: tap exactly 2 of your 5 top-row cards to peek, then pick trump.';
              });
            },
            child: const Text('Postpone (peek 2 row cards)'),
          ),
        ],
      );
    }

    // Postpone mode: hide the 5 top row cards; allow peeking 2.
    final hidden = List.generate(5, (i) => i);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Postpone Mode: Peek 2 cards', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: hidden.map((i) {
            final isPeeked = _peeked.contains(i);
            final display = isPeeked ? gs.human.rowUp[i]!.toString() : '🂠';
            return ElevatedButton(
              onPressed: () {
                if (_peeked.contains(i)) return;
                if (_peeked.length >= 2) return;
                setState(() {
                  _peeked.add(i);
                });
              },
              child: Text(display, style: const TextStyle(fontSize: 18)),
            );
          }).toList(),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: Suit.values.map((s) {
            return ElevatedButton(
              onPressed: _peeked.length == 2
                  ? () {
                      setState(() {
                        gs.trump = s;
                        _choosingTrump = false;
                        _postponeMode = false;
                        gs.message = 'Trump chosen as ${suitName(s)} based on 2 peeked cards. You lead Round 1.';
                      });
                    }
                  : null,
              child: Text('${suitName(s)} ${suitSymbol(s)}'),
            );
          }).toList(),
        ),
        const SizedBox(height: 6),
        Text('Peeked: ${_peeked.length}/2', style: const TextStyle(color: Colors.black54)),
      ],
    );
  }

  Widget _aiArea() {
    // AI hand is hidden; AI face-up row is visible.
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('AI', style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('Hand: ${gs.ai.hand.length} cards'),
              ],
            ),
            const SizedBox(height: 8),
            const Text('AI Face-up Row (playable):'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: List.generate(5, (i) {
                final c = gs.ai.rowUp[i];
                return Chip(label: Text(c?.toString() ?? '—'));
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _humanArea() {
    final canPlay = gs.trump != null && gs.round <= 15;

    final leadIsAi = !gs.humanLeads && gs.leadCard != null && gs.responseCard == null;

    final playable = leadIsAi ? _humanPlayableForResponse() : gs.human.playableCards();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('You', style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('Hand: ${gs.human.hand.length} cards'),
              ],
            ),
            const SizedBox(height: 8),
            const Text('Your Hand (private):'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: gs.human.hand.map((c) {
                final enabled = canPlay && (gs.humanLeads || leadIsAi) && playable.any((p) => p.suit == c.suit && p.rank == c.rank);
                return ElevatedButton(
                  onPressed: enabled
                      ? () {
                          setState(() {
                            _playHumanCard(c);
                          });
                        }
                      : null,
                  child: Text(c.toString()),
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
            const Text('Your Face-up Row (playable):'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: List.generate(5, (i) {
                final c = gs.human.rowUp[i];
                if (c == null) {
                  return const Chip(label: Text('—'));
                }
                final enabled = canPlay && (gs.humanLeads || leadIsAi) && playable.any((p) => p.suit == c.suit && p.rank == c.rank);
                return OutlinedButton(
                  onPressed: enabled
                      ? () {
                          setState(() {
                            _playHumanCard(c);
                          });
                        }
                      : null,
                  child: Text(c.toString()),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  void _playHumanCard(GameCard c) {
    if (gs.round > 15) return;
    if (gs.trump == null) return;

    // If AI has led already, this is a response.
    if (!gs.humanLeads && gs.leadCard != null && gs.responseCard == null) {
      gs.playResponseToAiLead(c);
      return;
    }

    // Otherwise human is leader of this trick.
    if (gs.humanLeads) {
      gs.playLead(c);
      return;
    }
  }

  Widget _messageBox() {
    return Card(
      color: const Color(0xFFF7F7F7),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Text(gs.message.isEmpty ? 'Ready.' : gs.message),
      ),
    );
  }
}
