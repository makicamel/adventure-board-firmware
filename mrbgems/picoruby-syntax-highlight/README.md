# picoruby-syntax-highlight

`SyntaxHighlight.tokenize(source)` returns a byte string as long as `source`,
one category per source byte, from the Prism that the compiler already
carries (a lexer pass, then a walk over the tree for method names and symbols).

| | | | |
|---|---|---|---|
| 0 default | 1 keyword | 2 string | 3 comment |
| 4 number | 5 symbol | 6 constant | 7 `@ivar` `$gvar` |
| 8 method name | | | |

A syntax error still gives a table (Prism recovers), which is what an editor
needs while someone is typing. `nil` for a source over 32 KiB.

Taken unchanged from family-mruby
(`fmruby-core/lib/add/picoruby-syntax-highlight`, MIT, Shunsuke Michii).
Here it is only built into the simulator's wasm (`rake sim:wasm`), where it
colours the code box; the firmware does not include it.
