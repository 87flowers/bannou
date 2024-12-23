## Bannou

Bannou is a work-in-progress chess engine written in Zig.

### UCI commands

Bannou aims to follow the Universal Chess Interface protocol, and communicates through stdin and stdout.

The following UCI commands are supported:

```
uci
debug [on|off]
isready
ucinewgame
go wtime <x> btime <x> winc <x> binc <x>
position [fen <fenstring> | startpos] [moves <move_1> ... <move_i>]
quit
```

Notably `stop` is not currently supported.

In addition to the above UCI commands, the following non-standard commands are supported:

```
d                            Print board state
move <move_1> ... <move_i>   Make move(s) from the current position
undo [<plys>]                Unmove specified number of plys of moves; defaults to depth of 1
perft [<depth>]              Divided perft to specified depth; defaults to depth of 1
bench                        Run benchmark
eval                         Evaluation of current position
history                      Display information about move history
auto [<depth>]               Equivalent to `go depth <depth>` followed by making the resulting
                             bestmove on the board; defaults to depth of 1
```

### Feature List

* Board representation
  * 0x88 mailbox board representation
  * BCH hashing
* Search
  * Negamax search
  * Alpha-beta pruning (fail-soft)
  * Principal Variation Search
  * Aspiration windows
  * Quiesence search
  * Basic time management with soft and hard timeouts
  * Swiss-like transposition table (14-way)
  * Transposition table cutoffs
  * Null move reduction (followed by pruning on second NMR)
  * Reverse futility pruning
  * Late move pruning
* Move ordering
  * MVV-LVA
  * Killer move heuristic
  * Counter move heuristic
  * History heuristic
* Evaluation
  * Tapered piece-square tables
