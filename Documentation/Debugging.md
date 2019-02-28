# Debugging `swift-format`

## Command Line Options

`swift-format` provides some hidden command line options to facilitate
debugging the tool during development:

* `--debug-disable-pretty-print`: Disables the pretty-printing pass of the
  formatter, causing only the syntax tree transformations in the first phase
  pipeline to run.

* `--debug-dump-token-stream`: Dumps a human-readable indented structure
  representing the pseudotoken stream constructed by the pretty printing
  phase.
