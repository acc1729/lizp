A Lisp interpreter written in Zig.

Inspired by [Risp](https://stopa.io/post/222), which in turn was inspired by
[Lispy](http://norvig.com/lispy.html).

This was a learning project to get my feet wet with Zig. Consider it a
'Hello, World!' project. The interpreter itself isn't perfect -- it only
implements a REPL, with no way to read from a file. Additionally, lambdas
leak memory.

Hopefully these two issues will be fixed in time!
