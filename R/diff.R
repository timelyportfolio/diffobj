# diffobj - Compare R Objects with a Diff
# Copyright (C) 2016  Brodie Gaslam
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# Go to <https://www.r-project.org/Licenses/GPL-3> for a copy of the license.

#' Compare R Objects with a Diff
#'
#' Colorized diffs to quickly identify _and understand_ differences between R
#' objects.  See `vignette("diffobj")` for details.
#'
#' @import crayon
#' @import methods
#' @importFrom utils capture.output file_test packageVersion read.csv
#' @importFrom stats ave frequency is.ts setNames
#' @importFrom grDevices rgb
#' @name diffobj-package
#' @docType package

NULL

# Because all these functions are so similar, we have constructed them with a
# function factory.  This allows us to easily maintain consisten formals during
# initial development process when they have not been set in stone yet.

make_diff_fun <- function(capt_fun) {
  # nocov start
  function(
    target, current,
    mode=gdo("mode"),
    context=gdo("context"),
    format=gdo("format"),
    brightness=gdo("brightness"),
    color.mode=gdo("color.mode"),
    word.diff=gdo("word.diff"),
    pager=gdo("pager"),
    guides=gdo("guides"),
    trim=gdo("trim"),
    rds=gdo("rds"),
    unwrap.atomic=gdo("unwrap.atomic"),
    max.diffs=gdo("max.diffs"),
    disp.width=gdo("disp.width"),
    ignore.white.space=gdo("ignore.white.space"),
    convert.hz.white.space=gdo("convert.hz.white.space"),
    tab.stops=gdo("tab.stops"),
    line.limit=gdo("line.limit"),
    hunk.limit=gdo("hunk.limit"),
    align=gdo("align"),
    style=gdo("style"),
    palette.of.styles=gdo("palette"),
    frame=par_frame(),
    interactive=gdo("interactive"),
    term.colors=gdo("term.colors"),
    tar.banner=NULL,
    cur.banner=NULL,
    extra=list()
  ) {
  # nocov end
    frame # force frame so that `par_frame` called in this context
    call.dat <- extract_call(sys.calls(), frame)

    # Check args and evaluate all the auto-selection arguments

    etc.proc <- check_args(
      call=call.dat$call, tar.exp=call.dat$tar, cur.exp=call.dat$cur,
      mode=mode, context=context, line.limit=line.limit, format=format,
      brightness=brightness, color.mode=color.mode, pager=pager,
      ignore.white.space=ignore.white.space, max.diffs=max.diffs,
      align=align, disp.width=disp.width,
      hunk.limit=hunk.limit, convert.hz.white.space=convert.hz.white.space,
      tab.stops=tab.stops, style=style, palette.of.styles=palette.of.styles,
      frame=frame, tar.banner=tar.banner, cur.banner=cur.banner, guides=guides,
      rds=rds, trim=trim, word.diff=word.diff, unwrap.atomic=unwrap.atomic,
      extra=extra, interactive=interactive, term.colors=term.colors
    )
    # If in rds mode, try to see if either target or current reference an RDS

    if(rds) {
      target <- get_rds(target)
      current <- get_rds(current)
    }
    # Force crayon to whatever ansi status we chose; note we must do this after
    # touching vars in case someone passes `options(crayon.enabled=...)` as one
    # of the arguments

    old.crayon.opt <-
      options(crayon.enabled=is(etc.proc@style, "StyleAnsi"))
    on.exit(options(old.crayon.opt), add=TRUE)
    err <- make_err_fun(sys.call())

    # Compute gutter values so that we know correct widths to use for capture,
    # etc. If not a base text type style, assume gutter and column padding are
    # zero even though that may not always be correct

    nc_fun <- if(is(etc.proc@style, "StyleAnsi")) crayon_nchar else nchar
    etc.proc@gutter <- gutter_dat(etc.proc)

    col.pad.width <- gutt.width <- 0L
    if(is(etc.proc@style, "StyleRaw")) {
      col.pad.width <- nc_fun(etc.proc@style@text@pad.col)
      gutt.width <- etc.proc@gutter@width
    }
    half.width <- as.integer((etc.proc@disp.width - col.pad.width) / 2)
    etc.proc@line.width <-
      max(etc.proc@disp.width, .min.width + gutt.width)
    etc.proc@text.width <- etc.proc@line.width - gutt.width
    etc.proc@line.width.half <- max(half.width, .min.width + gutt.width)
    etc.proc@text.width.half <- etc.proc@line.width.half - gutt.width

    # If in side by side mode already then we know we want half-width, and if
    # width is less than 80 we know we want unitfied

    if(etc.proc@mode == "auto" && etc.proc@disp.width < 80L)
      etc.proc@mode <- "unified"
    if(etc.proc@mode == "sidebyside") etc.proc <- sideBySide(etc.proc)

    # Capture and diff

    diff <- capt_fun(target, current, etc=etc.proc, err=err, extra)
    diff
  }
}
#' Diff \code{print}ed Objects
#'
#' Runs the diff between the \code{print} or \code{show} output produced by
#' \code{target} and \code{current}.
#'
#' @description This documentation page is intended as a reference document
#' for all the \code{diff*} methods.  For a high level introduction see
#' \code{vignette("diffobj")} and the examples.  Almost all aspects of how the
#' diffs are computed and displayed are controllable through the \code{diff*}
#' methods parameters.  This results in a lengthy parameter list, but in
#' practice, you should rarely need to adjust anything past the
#' \code{color.mode} parameter.  Default values are specified
#' as options so that users may configure diffs in a persistent manner.
#' \code{\link{gdo}} is a shorthand function to access \code{diffobj} options.
#'
#' This and other \code{diff*} functions are S4 generics that dispatch on the
#' \code{target} and \code{current} parameters.  Methods with signature
#' \code{c("ANY", "ANY")} are defined and act as the default methods.  You can
#' use this to set up methods to pre-process or set specific parameters for
#' selected clases that can then \code{callNextMethod} for the actual diff.
#' Note that while the generics include \code{...} as an argument, none of the
#' methods do.
#'
#' @export
#' @param target the reference object
#' @param current the object being compared to \code{target}
#' @param mode character(1L), one of:
#'   \itemize{
#'     \item \dQuote{unified}: diff mode used by \code{git diff}
#'     \item \dQuote{sidebyside}: line up the differences side by side
#'     \item \dQuote{context}: show the target and current hunks in their
#'       entirety; this mode takes up a lot of screen space but makes it easier
#'       to see what the objects actually look like
#'     \item \dQuote{auto}: default mode; pick one of the above, will favor
#'       \dQuote{sidebyside} unless \code{getOption("width")} is less than 80,
#'       or in \code{diffPrint} and objects are dimensioned and do not fit side
#'       by side, or in \code{diffChr}, \code{diffDeparse}, \code{diffFile} and
#'       output does not fit in side by side without wrapping
#'   }
#' @param context integer(1L) how many lines of context are shown on either side
#'   of differences (defaults to 2).  Set to \code{-1L} to allow as many as
#'   there are.  Set to \dQuote{auto}  to display as many as 10 lines or as few
#'   as 1 depending on whether total screen lines fit within the number of lines
#'   specified in \code{line.limit}.  Alternatively pass the return value of
#'   \code{\link{auto_context}} to fine tune the parameters of the auto context
#'   calculation.
#' @param format character(1L), controls the diff output format, one of:
#'   \itemize{
#'     \item \dQuote{auto}: to select output format based on terminal
#'       capabilities; will attempt to use one of the ANSI formats if they
#'       appear to be supported, and if not will attempt to use HTML and
#'       browser output if in interactive mode.
#'     \item \dQuote{raw}: plain text
#'     \item \dQuote{ansi8}: color and format diffs using basic ANSI escape
#'       sequences
#'     \item \dQuote{ansi256}: like \dQuote{ansi8}, except using the full range
#'       of ANSI formatting options
#'     \item \dQuote{html}: color and format using HTML markup
#'   }
#'   Defaults to \dQuote{auto}.  See \code{\link{PaletteOfStyles}} for details
#'   on customization, \code{\link{style}} for full control of output format.
#' @param brightness character, one of \dQuote{light}, \dQuote{dark},
#'   \dQuote{neutral}, useful for adjusting color scheme to light or dark
#'   terminals.  \dQuote{neutral} by default.  See \code{\link{PaletteOfStyles}}
#'   for details and limitations.  Advanced: you may specify brightness as a
#'   function of \code{format}.  For example, if you typically wish to use a
#'   \dQuote{dark} color scheme, except for when in \dQuote{html} format when
#'   you prefer the \dQuote{light} scheme, you may use
#'   \code{c("dark", html="light")} as the value for this parameter.  This is
#'   particularly useful if \code{format} is set to \dQuote{auto} or if you
#'   want to specify a default value for this parameter via options.  Any names
#'   you use should correspond to a \code{format}.  You must have one unnamed
#'   value which will be used as the default for all \code{format}s that are
#'   not explicitly specified.
#' @param color.mode character, one of \dQuote{rgb} or \dQuote{yb}.
#'   Defaults to \dQuote{yb}.  \dQuote{yb} stands for \dQuote{Yellow-Blue} for
#'   color schemes that rely primarily on those colors to style diffs.
#'   Those colors can be easily distinguished by individuals with
#'   limited red-green color sensitivity.  See \code{\link{PaletteOfStyles}} for
#'   details and limitations.  Also offers the same advanced usage as the
#'   \code{brightness} paramter.
#' @param word.diff TRUE (default) or FALSE, whether to run a secondary word
#'   diff on the in-hunk diferences
#' @param pager character(1L), one of \dQuote{auto}, \dQuote{on},
#'   \dQuote{off}, or a \code{\link{Pager}} object; controls whether and how a
#'   pager is used to display the diff output.  If \dQuote{on} will use the
#'   pager associated with the \code{\link{Style}} specified via the
#'   \code{\link{style}} parameters.  if \dQuote{auto} (default) will behave
#'   like \dQuote{on} but only if in interactive mode.  If the pager is
#'   enabled, default behavior is to pipe output to \code{\link{file.show}} if
#'   output is taller than the estimated terminal height and your terminal
#'   supports ANSI escape sequences.  If not, the default is to attempt to pipe
#'   output to a web browser with \code{\link{browseURL}}.  See
#'   \code{\link{Pager}}, \code{\link{Style}}, and \code{\link{PaletteOfStyles}}
#'   for more details.
#' @param guides TRUE (default), FALSE, or a function that accepts at least two
#'   arguments and requires no more than two arguments.  Guides
#'   are additional context lines that are not strictly part of a hunk, but
#'   provide important contextual data (e.g. column headers).  If TRUE, the
#'   context lines are shown in addition to the normal diff output, typically
#'   in a different color to inidicate they are not part of the hunk.  If a
#'   function, the function should accept as the first argument the object
#'   being diffed, and the second the character representation of the object.
#'   The function should return the indices of the elements of the second
#'   character representation that should be treated as guides.  See
#'   \code{\link{guides}} for more details.
#' @param trim TRUE (default), FALSE, or a function that accepts at least two
#'   arguments and requires no more than two arguments.  Function should compute
#'   for each line in captured output what portion of those lines should be
#'   diffed.  By default, this is used to remove row meta data differences
#'   (e.g. \code{[1,]}) so they alone do not show up as differences in the
#'   diff.  See \code{\link{trim}} for more details.
#' @param rds TRUE (default) or FALSE, if TRUE will check whether
#'   \code{target} and/or \code{current} point to a file that can be read with
#'   \code{\link{readRDS}} and if so, loads the R object contained in the file
#'   and carries out the diff on the object instead of the original argument.
#'   Currently there is no mechanism for specifying additional arguments to
#'   \code{readRDS}
#' @param unwrap.atomic TRUE (default) or FALSE.  Only relevant for
#'   \code{diffPrint}, if TRUE, and \code{word.diff} is also TRUE, and both
#'   \code{target} and \code{current} are \emph{unnamed} and atomic, the vectors
#'   are unwrapped and diffed element by element, and then re-wrapped.  Since
#'   \code{diffPrint} is fundamentally a line diff, the re-wrapped lines are
#'   lined up in a manner that is as consistent as possible with the unwrapped
#'   diff.  Lines that contain the location of the word differences will be
#'   paired up.  Since the vectors may well be wrapped with different
#'   periodicities this will result in lines that are paired up that look like
#'   they should not be paired up, though the locations of the differences
#'   should be.
#' @param line.limit integer(2L) or integer(1L), if length 1 how many lines of
#'   output to show, where \code{-1} means no limit.  If length 2, the first
#'   value indicates the threshold of screen lines to begin truncating output,
#'   and the second the number of lines to truncate to, which should be fewer
#'   than the threshold.  Note that this parameter is implemented on a
#'   best-efforts basis and should not be relied on to produce the exact
#'   number of lines requested.  If you want a specific number of lines use
#'   \code{[} or \code{head}/\code{tail}.  One advantage of \code{line.limit}
#'   over these other options is that you can combine it with
#'   \code{context="auto"} and auto \code{max.level} selection (the latter for
#'   \code{diffStr}), which allows the diff to dynamically adjust to make best
#'   use of the available display lines.  \code{[}, \code{head}, and \code{tail}
#'   just subset the text of the output.
#' @param hunk.limit integer(2L) or integer (1L), how many diff hunks to show.
#'   Behaves similarly to \code{line.limit}.  How many hunks are in a
#'   particular diff is a function of how many differences, and also how much
#'   \code{context} is used since context can cause two hunks to bleed into
#'   each other and become one.
#' @param max.diffs integer(1L), number of \emph{differences} after which we
#'   abandon the \code{O(n^2)} diff algorithm in favor of a linear one.  Set to
#'   \code{-1L} to always stick to the original algorithm (defaults to 10000L).
#' @param disp.width integer(1L) number of display columns to take up; note that
#'   in \dQuote{sidebyside} \code{mode} the effective display width is half this
#'   number (set to 0L to use default widths which are \code{getOption("width")}
#'   for normal styles and \code{120L} for HTML styles.
#' @param ignore.white.space TRUE or FALSE, whether to consider differences in
#'   horizontal whitespace (i.e. spaces and tabs) as differences (defaults to
#'   FALSE)
#' @param convert.hz.white.space TRUE or FALSE, whether modify input strings
#'   that contain tabs and carriage returns in such a way that they display as
#'   they would \bold{with} those characters, but without using those
#'   characters (defaults to TRUE).  The conversion assumes that tab stops are
#'   spaced evenly eight characters apart on the terminal.  If this is not the
#'   case you may specify the tab stops explicitly with \code{tab.stops}.
#' @param tab.stops integer, what tab stops to use when converting hard tabs to
#'   spaces.  If not integer will be coerced to integer (defaults to 8L).  You
#'   may specify more than one tab stop.  If display width exceeds that
#'   addressable by your tab stops the last tab stop will be repeated.
#' @param align numeric(1L) between 0 and 1, proportion of
#'   words in a line of \code{target} that must be matched in a line of
#'   \code{current} in the same hunk for those lines to be paired up when
#'   displayed (defaults to 0.25), or an \code{\link{AlignThreshold}} object.
#'   Set to \code{1} to turn off alignment which will cause all lines in a hunk
#'   from \code{target} to show up first, followed by all lines from
#'   \code{current}.
#' @param style \dQuote{auto}, or a \code{\link{Style}} object.
#'   \dQuote{auto} by default.  If a \code{Style} object, will override the
#'   the \code{format}, \code{brightness}, and \code{color.mode} parameters.
#'   The \code{Style} object provides full control of diff output styling.
#'   See \code{\link{Style}} for more details.
#' @param palette.of.styles \code{\link{PaletteOfStyles}} object; advanced usage,
#'   contains all the \code{\link{Style}} objects that are selected by
#'   specifying the \code{format}, \code{brightness}, and \code{color.mode}
#'   parameters.  See \code{\link{PaletteOfStyles}} for more details.
#' @param frame an environment to use as the evaluation frame for the
#'   \code{print/show/str}, calls and for \code{diffObj}, the evaluation frame
#'   for the \code{diffPrint}/\code{diffStr} calls.  Defaults to the return
#'   value of \code{\link{par_frame}}.
#' @param interactive TRUE or FALSE whether the function is being run in
#'   interactive mode, defaults to the return value of
#'   \code{\link{interactive}}.  If in interactive mode, pager will be used if
#'   \code{pager} is \dQuote{auto}, and if ANSI styles are not supported and
#'   \code{style} is \dQuote{auto}, output will be send to browser as HTML.
#' @param term.colors integer(1L) how many ANSI colors are supported by the
#'   terminal.  This variable is provided for when
#'   \code{\link[=num_colors]{crayon::num_colors}} does not properly detect how
#'   many ANSI colors are supported by your terminal. Defaults to return value
#'   of \code{\link[=num_colors]{crayon::num_colors}} and should be 8 or 256 to
#'   allow ANSI colors, or any other number to disallow them.  This only
#'   impacts output format selection when \code{style} and \code{format} are
#'   both set to \dQuote{auto}.
#' @param tar.banner character(1L) or NULL, text to display ahead of the diff
#'   section representing the target output.  If NULL will be
#'   inferred from \code{target} and \code{current} expressions.
#' @param cur.banner character(1L) like \code{tar.banner}, but for
#'   \code{current}
#' @param extra list additional arguments to pass on to the functions used to
#'   create text representation of the objects to diff (e.g. \code{print},
#'   \code{str}, etc.)
#' @param ... unused, for compatibility of generics with methods
#' @seealso \code{\link{diffObj}}, \code{\link{diffStr}},
#'   \code{\link{diffChr}} to compare character vectors directly,
#'   \code{\link{diffDeparse}} to compare deparsed objects
#' @return a \code{Diff} object; this object has a \code{show}
#'   method that will display the diff to screen or pager, as well as
#'   \code{summary}, \code{any}, and \code{as.character} methods.
#'   If you store the return value instead of displaying it to screen, and
#'   display it later, it is possible for the display to be thrown off if
#'   there are environment changes (e.g. display width changes) in between
#'   the time you compute the diff and the time you display it.
#' @rdname diffPrint
#' @name diffPrint
#' @export
#' @examples
#' diffPrint(letters, letters[-5])

setGeneric(
  "diffPrint", function(target, current, ...) standardGeneric("diffPrint")
)
#' @rdname diffPrint

setMethod("diffPrint", signature=c("ANY", "ANY"), make_diff_fun(capt_print))

#' Diff Object Structures
#'
#' Compares the \code{str} output of \code{target} and \code{current}.  If
#' the \code{max.level} parameter to \code{str} is left unspecified, will
#' attempt to find the largest \code{max.level} that fits within
#' \code{line.limit} and shows at least one difference.
#'
#' Due to the seemingly inconsistent nature of \code{max.level} when used with
#' objects with nested attributes, and also due to the relative slowness of
#' \code{str}, this function simulates the effect of \code{max.level} by hiding
#' nested lines instead of repeatedly calling \code{str} with varying values of
#' \code{max.level}.
#'
#' @inheritParams diffPrint
#' @seealso \code{\link{diffPrint}} for details on the \code{diff*} functions,
#'   \code{\link{diffObj}}, \code{\link{diffStr}},
#'   \code{\link{diffChr}} to compare character vectors directly,
#'   \code{\link{diffDeparse}} to compare deparsed objects
#' @return a \code{Diff} object; see \code{\link{diffPrint}}.
#' @rdname diffStr
#' @export

setGeneric("diffStr", function(target, current, ...) standardGeneric("diffStr"))

#' @rdname diffStr

setMethod("diffStr", signature=c("ANY", "ANY"), make_diff_fun(capt_str))

#' Diff Character Vectors Element By Element
#'
#' Will perform the diff on the actual string values of the character vectors
#' instead of capturing the printed screen output. Each vector element is
#' treated as a line of text.
#'
#' @inheritParams diffPrint
#' @seealso \code{\link{diffPrint}} for details on the \code{diff*} functions,
#'   \code{\link{diffObj}}, \code{\link{diffStr}},
#'   \code{\link{diffDeparse}} to compare deparsed objects
#' @return a \code{Diff} object; see \code{\link{diffPrint}}.
#' @export
#' @rdname diffChr
#' @examples
#' diffChr(LETTERS[1:5], LETTERS[2:6])

setGeneric("diffChr", function(target, current, ...) standardGeneric("diffChr"))

#' @rdname diffChr

setMethod("diffChr", signature=c("ANY", "ANY"), make_diff_fun(capt_chr))

#' Diff Deparsed Objects
#'
#' Perform diff on the character vectors produced by \code{\link{deparse}}ing
#' the objects.  Each element counts as a line.  If an element contains newlines
#' it will be split into elements new lines by the newlines.
#'
#' @export
#' @inheritParams diffPrint
#' @seealso \code{\link{diffPrint}} for details on the \code{diff*} functions,
#'   \code{\link{diffObj}}, \code{\link{diffStr}},
#'   \code{\link{diffChr}} to compare character vectors directly
#' @return a \code{Diff} object; see \code{\link{diffPrint}}.
#' @export
#' @rdname diffDeparse
#' @examples
#' diffDeparse(matrix(1:9, 3), 1:9)

setGeneric(
  "diffDeparse", function(target, current, ...) standardGeneric("diffDeparse")
)
#' @rdname diffDeparse

setMethod("diffDeparse", signature=c("ANY", "ANY"), make_diff_fun(capt_deparse))

#' Diff Files
#'
#' Reads text files with \code{\link{readLines}} and performs a diff on the
#' resulting character vectors.
#'
#' @export
#' @param target character(1L) or file connection with read capability; if
#'   character should point to a text file
#' @param current like \code{target}
#' @inheritParams diffPrint
#' @seealso \code{\link{diffPrint}} for details on the \code{diff*} functions,
#'   \code{\link{diffObj}}, \code{\link{diffStr}},
#'   \code{\link{diffChr}} to compare character vectors directly
#' @return a \code{Diff} object; see \code{\link{diffPrint}}.
#' @export
#' @rdname diffFile
#' @examples
#' url.base <- "https://raw.githubusercontent.com/wch/r-source"
#' f1 <- file.path(url.base, "29f013d1570e1df5dc047fb7ee304ff57c99ea68/README")
#' f2 <- file.path(url.base, "daf0b5f6c728bd3dbcd0a3c976a7be9beee731d9/README")
#' diffFile(f1, f2)

setGeneric(
  "diffFile", function(target, current, ...) standardGeneric("diffFile")
)
#' @rdname diffFile

setMethod("diffFile", signature=c("ANY", "ANY"), make_diff_fun(capt_file))

#' Diff CSV Files
#'
#' Reads CSV files with \code{\link{read.csv}} and passes the resulting data
#' frames onto \code{\link{diffPrint}}.  \code{extra} values are passed as
#' arguments are passed to both \code{read.csv} and \code{print}.  To the
#' extent you wish to use different \code{extra} arguments for each of those
#' functions you will need to \code{read.csv} the files and pass them to
#' \code{diffPrint} yourself.
#'
#' @export
#' @param target character(1L) or file connection with read capability;
#'   if character should point to a CSV file
#' @param current like \code{target}
#' @inheritParams diffPrint
#' @seealso \code{\link{diffPrint}} for details on the \code{diff*} functions,
#'   \code{\link{diffObj}}, \code{\link{diffStr}},
#'   \code{\link{diffChr}} to compare character vectors directly
#' @return a \code{Diff} object; see \code{\link{diffPrint}}.
#' @export
#' @rdname diffCsv
#' @examples
#' iris.2 <- iris
#' iris.2$Sepal.Length[5] <- 99
#' f1 <- tempfile()
#' f2 <- tempfile()
#' write.csv(iris, f1, row.names=FALSE)
#' write.csv(iris.2, f2, row.names=FALSE)
#' diffCsv(f1, f2)
#' unlink(c(f1, f2))

setGeneric(
  "diffCsv", function(target, current, ...) standardGeneric("diffCsv")
)
#' @rdname diffCsv

setMethod("diffCsv", signature=c("ANY", "ANY"), make_diff_fun(capt_csv))

#' Diff Objects
#'
#' Compare either the \code{print}ed or \code{str} screen representation of
#' R objects depending on which is estimated to produce the most useful
#' diff.  The selection process tries to minimize screen lines while maximizing
#' differences shown subject to display constraints.  The decision algorithm is
#' likely to evolve over time, so do not rely on this function making
#' a particular selection under specific circumstances.  Instead, use
#' \code{\link{diffPrint}} or \code{\link{diffStr}} if you require one or the
#' other output.
#'
#' @inheritParams diffPrint
#' @seealso \code{\link{diffPrint}} for details on the \code{diff*} functions,
#'   \code{\link{diffStr}},
#'   \code{\link{diffChr}} to compare character vectors directly
#'   \code{\link{diffDeparse}} to compare deparsed objects
#' @return a \code{Diff} object; see \code{\link{diffPrint}}.
#' @export

setGeneric("diffObj", function(target, current, ...) standardGeneric("diffObj"))

diff_obj <- make_diff_fun(identity) # we overwrite the body next
body(diff_obj) <- quote({
  if(length(extra))
    stop("Argument `extra` must be empty in `diffObj`.")

  frame # force frame so that `par_frame` called in this context
  call.raw <- extract_call(sys.calls(), frame)$call
  call.raw[["frame"]] <- frame
  call.str <- call.print <- call.raw
  call.str[[1L]] <- quote(diffStr)
  call.str[["extra"]] <- list(max.level="auto")
  call.print[[1L]] <- quote(diffPrint)

  # Run both the print and str versions, and then decide which to use based
  # on some weighting of various factors including how many lines needed to be
  # omitted vs. how many differences were reported

  res.print <- eval(call.print, frame)
  res.str <- eval(call.str, frame)

  diff.p <- count_diff_hunks(res.print@diffs)
  diff.s <- count_diff_hunks(res.str@diffs)
  diff.l.p <- diff_line_len(
    res.print@diffs, res.print@etc, tar.capt=res.print@tar.dat$raw,
    cur.capt=res.print@cur.dat$raw
  )
  diff.l.s <- diff_line_len(
    res.str@diffs, res.str@etc, tar.capt=res.str@tar.dat$raw,
    cur.capt=res.str@cur.dat$raw
  )

  # How many lines of the input are in the diffs, vs how many lines of input

  diff.line.ratio.p <- lineCoverage(res.print)
  diff.line.ratio.s <- lineCoverage(res.str)

  # Only show the one with differences

  res <- if(!diff.s && diff.p) {
    res.print
  } else if(!diff.p && diff.s) {
    res.str

  # If one fits in full and the other doesn't, show the one that fits in full
  } else if(
    !res.str@trim.dat$lines[[1L]] &&
    res.print@trim.dat$lines[[1L]]
  ) {
    res.str
  } else if(
    res.str@trim.dat$lines[[1L]] &&
    !res.print@trim.dat$lines[[1L]]
  ) {
    res.print
  # Calculate the trade offs between the two options
  } else {
    s.score <- diff.s / diff.l.s * diff.line.ratio.s
    p.score <- diff.p / diff.l.p * diff.line.ratio.p
    if(p.score >= s.score) res.print else res.str
  }
  res
})
#' @export
setMethod("diffObj", signature=c("ANY", "ANY"), diff_obj)
