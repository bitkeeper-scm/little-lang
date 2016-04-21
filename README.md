# INTRODUCTION

Little is a compiled-to-byte-code language that draws heavily from
C and Perl.  From C, Little gets C syntax, simple types (int, float,
string), and complex types (arrays, structs).  From Perl, Little gets
associative arrays and regular expressions (PCRE).  And from neither,
Little gets its own simplistic form of classes.

The name "Little", abbreviated as simply "L", alludes to the language's
simplicity.  The idea was to distill the useful parts of other languages
and combine them into a scripting language, with type checking,
classes (not full-blown OO but useful none the less), direct access to
a cross-platform graphical toolkit, and a library drawn from Perl and
the standard C library.

L is built on top of the Tcl/Tk system.  The L compiler generates Tcl byte
codes and uses the Tcl calling convention.  This means that L and Tcl code
may be intermixed.  More importantly, it means that Little may use all
of the Tcl API and libraries as well as TK widgets.  The net result is a
type-checked scripting language which may be used for cross-platform GUIs.

Little is open source under the same license as Tcl/TK (BSD like) with
any bits that are unencumbered by the Tcl license also being available
under the Apache License, Version 2.0.

Little is based on interim Tcl and Tk releases
http://core.tcl.tk/tcl/info/497b93405b3435aa and
http://core.tcl.tk/tk/info/407bae5e576b5ef7.

## PREREQUISITES

* bison
* flex
* libxft2-dev

## COMPILING L

Little can be built with or without Tk.  Without Tk, you get only an tclsh
executable named "L".  With Tk, you get that and a version of wish
with Little named "L-gui" (on OS X, an application bundle is created instead).
The accompanying Makefile builds L and L-gui for Linux, OS X, and Windows.

Because Little is integrated into Tcl/Tk, the instructions for configuring
and compiling Tcl and Tk apply. See `tcl/README` and `tk/README` if you
need to tweak anything.  L adds Perl-compatible regular expressions
(PCRE) and the `--with-pcre=<path>` configure option to Tcl.

A Windows build wants msys or cygwin.  A `make help` explains the make
targets.

L uses git submodules to distribute Tcl, Tk, and PCRE. To compile from
source:

```
$ git submodule init
$ git submodule update
$ make
```

## INSTALLING

On Linux and Windows, a `make install` will install L and L-gui in
`/usr/local/bin` (can be overridden with `L_INSTALL_DIR=$DIR`).

**WARNING:** If you have Tcl/Tk version 8.6 installed in `/usr/local`,
  running `make install` will stump on your installation.

For OS X, Little is similarly installed, but the L-gui application bundle
is copied to `LGUI_OSX_INSTALL_DIR` which defaults to `/Applications`.

## DOCUMENTATION

On Linux, make install will create `$(INSTALL_DIR)/doc/L/L.html` but
not on macos or windows (yet, it needs L to build and the path to Little
is hard coded in `tcl/doc/L/pod2html.l`.  Someone should fix this :)  

See `tcl/doc/l-paper` for ["The L Programming language"](http://www.tcl.tk/community/tcl2006/papers/Larry_McVoy/l.pdf) published in the
Proceedings of the [13th Annual Tcl/Tk Conference](http://www.tcl.tk/community/tcl2006/schedule.html).
