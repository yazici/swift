# SwiftFormat Pretty Printer

## Introduction

The algorithm used in the SwiftFormat pretty printer is based on the "simple"
version of the algorithm described by Derek Oppen in his paper [*Pretty
Printing*](http://i.stanford.edu/pub/cstr/reports/cs/tr/79/770/CS-TR-79-770.pdf)
(1979). It employs two functions: *scan* and *print*. The *scan* function
accepts a stream of tokens and calculates the lengths of these tokens. It then
passes the tokens and their computed lengths to *print*, which handles the
actual printing of the tokens, automatically inserting line breaks and indents
to obey a given maximum line length. We describe in detail how these functions
have been implemented in SwiftFormat.

## Tokens

### Token Groups

It is often necessary to group a series of tokens together into logical groups
that we want to avoid splitting with line break if possible. The algorithm tries
to break as few groups as possible when printing. Groups begin with *open*
tokens and end with *close* tokens. These tokens must always be paired.

### Token Types

The different types of tokens are represented as a Token `enum` within the code.
The available cases are: `syntax`, `break`, `open`, `close`, `newlines`,
`comment`, and `reset`. The behavior of each of them is described below with
pseudocode examples.

See: [`Token.swift`](../Sources/SwiftFormatPrettyPrint/Token.swift)

#### Syntax

The *syntax* tokens contain the segments of text that need to be printed (e.g.
`}`, `func`, `23`, `while`, etc.). The length of a token is the number of
columns needed to print it. For example, `func` would have a length of 4.

#### Break

The *break* tokens indicate where line breaks are allowed to occur. These
frequently occur as the whitespace in between syntax tokens. The breaks contain
two associated values that can be specified when creating the break token:
*size* and *offset*. The size indicates how many columns of whitespace should
be printed when the token is encountered. If a line break should occur at the
break token, the offset indicates how many spaces should be used for indentation
of the next token. The length of a break is its size plus the length of the
token that immediately come after it. If a break immediately precedes a group,
its length will be its size plus the size of the group.

```
# break(size, offset)
Tokens = ["one", break(1, 2), "two", break(1, 2), "three"]
Lengths = [3, 4, 3, 6, 5]

# Maximum line length of 10
Output =
"""
one two
  three
"""
```

#### Open

An *open* token indicates the start of a group.

```
# break(size=1, offset=0)
Token = ["one", break, open, "two", break, "three", break, open, "four", break, "five", close, close]

# Maximum line length of 20
Output =
"""
one
two three four five
"""

# Maximum line length of 10
Output =
"""
one
two three
four five
"""
```

Open tokens have a *break style* and an *offset*. The break style is either
*consistent* or *inconsistent*. If a group is too large to fit on the remaining
space on a line, and it is labeled as *consistent*, then the break tokens it
contains will all produce line breaks. (In the case of nested groups, the break
style affects a group's immediate children.) The default behavior is
*inconsistent*, in which case the break tokens only produce line breaks when
their lengths exceed the remaining space on the line.

```
# open(consistent/inconsistent), break(size, offset)
Tokens = ["one", break(1, 0), open(C), "two", break(1, 0), "three", close]

# Maximum line length of 10 (consistent breaking)
Output =
"""
one
two
three
"""

# With inconsistent breaking
Tokens = ["one", break(1, 0), open(I), "two", break(1, 0), "three", close]
Output =
"""
one
two three
"""
```

The open token's offset applies an offset to the breaks contained within the
group. A break token's offset value is added to the offset of its group. In the
case of nested groups, the group offsets add together. If an outer group has an
offset of 2, and an inner group an offset 3, any break tokens that produce line
breaks in the inner group will offset by 5 spaces (plus the break's offsets).
Additionally, a break that produces a line break immediately before an open
token will also increase the offset. For example, if a break has an offset of 2
immediately before an open with an offset of 3, the breaks within the group will
be offset by 5.

```
# open(consistent/inconsistent, offset)
Tokens = ["one", break, open(C, 2), "two", break, "three", close]

# Maximum line length of 10
Output =
"""
one
two
  three
"""

Tokens = ["one", break(offset=2), open(C, 0), "two", break, "three", close]

# Maximum line length of 10
Output =
"""
one
  two
  three
"""
```

The open token of a group is assigned the total size of the group as its length.
Open tokens must always be paired with a *close* token.

```
Tokens = ["one", break(1, 2), open(C, 2), "two", break(1, 2), "three", close]
Lengths = [3, 11, 10, 3, 1, 5, 0]
```

#### Close

The *close* tokens indicate the end of a group, and they have a length of zero.
They must always be paired with an *open* token.

#### Newline

The *newline* tokens behave much the same way as *break* tokens, except that
they always produce a line break. They can be assigned an offset, in the same
way as a break. They can also be given an integer number of line breaks to
produce.

These tokens are given a length equal to the maximum allowed line width. The
reason for this is to indicate that any enclosing groups are too large to fit on
a single line.

```
# Assume maximum line length of 50
# break(size)
Tokens = ["one", break(1), "two", break(1), open, "three", newline, "four", close]
Lengths = [3, 4, 3, 60, 59, 5, 50, 4, 0]
```

#### Reset

Reset tokens are used to reset the state created by break tokens if needed, and
are rarely used. A primary use-case is to prevent an entire group from moving to
a new line, but you still want the group to break internally. Reset tokens have
a length of zero.

A reset token makes whatever follows it behave as if it was at the beginning of
the line.

```
Tokens = ["one", break(1), "two", reset]
Lengths = [3, 4, 3, 0]

# Normal breaking behavior of a consistent group
Tokens = ["one", break(1), open(C, 2), "two", break(1), "three", break(1), "four", close]
Output =
"""
one
  two
  three
  four
"""

# Breaking behavior of a consistent group with a reset token
Tokens = ["one", break(1), reset, open(C, 2), "two", break(1), "three", break(1), "four", close]
Output =
"""
one two
  three
  four
"""
```

#### Comment

Comment tokens represent Swift source comments, and they come in four types:
`line`, `docLine`, `block`, and `docBlock`. Their length is equal to the number
of characters needed to print them, including whitespace and delimiters. Line
comments produce one comment token per line. If other comment types span
multiple lines, their content is represented as a single comment token.

```
# Line comment
// comment 1
// comment 2
Tokens = [line(" comment 1"), newline, line(" comment 2")]

/// Doc comment 1
/// Second line
Tokens = [docLine(" Doc comment 1\n Second line")]

/* Block comment
   Second line */
Tokens = [block(" Block comment\n   Second Line ")]

/** Doc Block comment
  * Second line **/
Tokens = [docBlock(" Doc Block comment\n  * Second line *")]
```

### Token Generation

Token generation begins with the abstract syntax tree (AST) of the Swift source
file, provided by the [SwiftSyntax](https://github.com/apple/swift-syntax)
library. We have a `visit` method for each of the different syntax node types
(e.g. `FunctionDeclSyntax`, `GenericWhereClause`, etc.). Within each of these
visit methods, we can attach pretty-printer `Token` objects before and after
syntax tokens from the AST. For example, if we wanted a group after the opening
brace of a function declaration, it might look like:

```
# node: FunctionDeclSyntax
after(node.body?.leftBrace, tokens: .break(size: 1, offset: 2), .open(.consistent, 0))
```

All of the tokens are placed into an array, which are then passed on to the
*scan* phase of the pretty printer.

See: [`TokenStreamCreator.swift`](../Sources/SwiftFormatPrettyPrint/TokenStreamCreator.swift)
