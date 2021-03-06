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

is.less_flags <-
  function(x) is.chr.1L(x) && isTRUE(grepl("^[[:alpha:]]*$", x))

# for checking the limits, if successful returns an integer(2L) vector,
# otherwise a character vector to sprintf as an error

check_limit <- function(limit) {
  if(
    !is.numeric(limit) || any(is.na(limit)) ||
    !length(limit) %in% 1:2 ||
    !is.finite(limit) ||
    round(limit) != limit ||
    (length(limit) == 2L && diff(limit) > 0)
  ) {
    return(
      paste0(
        "Argument `%s` must be an integer vector of length 1 or 2 ",
        "and if length 2, with the first value larger than or equal to ",
        "the second%s"
  ) ) }
  limit <- as.integer(limit)
  if(length(limit) == 1L) limit <- rep(limit, 2L)
  limit
}
# requires a value to be a scalar character and match one of the provided
# options

string_in <- function(x, valid.x) is.chr.1L(x) && x %in% valid.x

# Simple validation functions

is.int.1L <- function(x)
  is.numeric(x) && length(x) == 1L && !is.na(x) && x ==  round(x) &&
  is.finite(x)

is.int.2L <- function(x)
  is.numeric(x) && length(x) == 2L && !anyNA(x) && x ==  round(x) &&
  is.finite(x)

is.TF <- function(x) isTRUE(x) || identical(x, FALSE)

is.chr.1L <- function(x) is.character(x) && length(x) == 1L && !is.na(x)

is.valid.palette.param <- function(x, param, palette) {
  stopifnot(is(palette, "PaletteOfStyles"))
  stopifnot(isTRUE(param %in% c("brightness", "color.mode")))
  valid.formats <- dimnames(palette@data)$format
  valid.params <- dimnames(palette@data)[[param]]

  if(!is.character(x) || anyNA(x))
    paste0("Argument `", param, "` must be character and not contain NAs")
  else if(!all(x %in% valid.params))
    paste0(
      "Argument `", param, "` may only contain values in `", dep(valid.params),
      "`"
    )
  else if(
    (length(x) > 1L && is.null(names(x))) ||
    (!is.null(names(x)) && !"" %in% names(x)) ||
    !all(names(x) %in% c("", valid.formats))
  )
    paste0(
      "Argument `", param, "` must have names if it has length > 1, and those ",
      "names must include at least an empty name `\"\"` as well as names only ",
      "from `", dep(valid.formats), "`."
    )
  else TRUE
}
is.one.arg.fun <- function(x) {
  if(!is.function(x)) {
    "is not a function"
  } else if(length(formals(x)) < 1L) {
    "does not have at least one arguments"
  } else if("..." %in% names(formals(x))[1]) {
    "cannot have `...` as the first argument"
  } else {
    nm.forms <- vapply(formals(x), is.name, logical(1L))
    forms.chr <- character(length(nm.forms))
    forms.chr[nm.forms] <- as.character(formals(x)[nm.forms])
    if(any(tail(!nzchar(forms.chr) & nm.forms, -1L)))
      "cannot have any non-optional arguments other than first one" else TRUE
  }
}
is.valid.guide.fun <- is.two.arg.fun <- function(x) {
  if(!is.function(x)) {
    "is not a function"
  } else if(length(formals(x)) < 2L) {
    "does not have at least two arguments"
  } else if("..." %in% names(formals(x))[1:2]) {
    "cannot have `...` as one of the first two arguments"
  } else {
    nm.forms <- vapply(formals(x), is.name, logical(1L))
    forms.chr <- character(length(nm.forms))
    forms.chr[nm.forms] <- as.character(formals(x)[nm.forms])
    if(any(tail(!nzchar(forms.chr) & nm.forms, -2L)))
      "cannot have any non-optional arguments other than first two" else TRUE
} }
is.valid.width <- function(x)
  if(!is.int.1L(x) || (x != 0L && (x < 10L || x > 10000))) {
    "must be integer(1L) and 0, or between 10 and 10000"
  } else TRUE

# Checks common arguments across functions

check_args <- function(
  call, tar.exp, cur.exp, mode, context, line.limit, format, brightness,
  color.mode, pager, ignore.white.space, max.diffs, align, disp.width,
  hunk.limit, convert.hz.white.space, tab.stops, style, palette.of.styles,
  frame, tar.banner, cur.banner, guides, rds, trim, word.diff, unwrap.atomic,
  extra, interactive, term.colors
) {
  err <- make_err_fun(call)

  # Check extra

  if(!is.list(extra)) err("Argument `extra` must be a list.")

  # Check context

  msg.base <- paste0(
    "Argument `%s` must be integer(1L) and not NA, an object produced ",
    "by `auto_context`, or \"auto\"."
  )
  if(
    !is.int.1L(context) && !is(context,"AutoContext") &&
    !identical(context, "auto")
  )
    err(sprintf(msg.base, "context"))

  if(!is(context, "AutoContext")) {
    context <- if(identical(context, "auto")) auto_context() else
      auto_context(as.integer(context), as.integer(context))
  }
  # any 'substr' of them otherwise these checks fail

  val.modes <- c("auto", "unified", "context", "sidebyside")
  fail.mode <- FALSE
  if(!is.character(mode) || length(mode) != 1L || is.na(mode) || !nzchar(mode))
    fail.mode <- TRUE
  if(!fail.mode && !any(mode.eq <- substr(val.modes, 1, nchar(mode)) == mode))
    fail.mode <- TRUE
  if(fail.mode)
    err(
      "Argument `mode` must be character(1L) and in `", deparse(val.modes), "`."
    )

  # Tab stops

  tab.stops <- as.integer(tab.stops)
  if(
    !is.integer(tab.stops) || !length(tab.stops) >= 1L || anyNA(tab.stops) ||
    !all(tab.stops > 0L)
  )
    stop(
      "Argument `tab.stops` must be integer containing at least one value and ",
      "with all values strictly positive"
    )
  # Limit vars

  hunk.limit <- check_limit(hunk.limit)
  if(!is.integer(hunk.limit)) err(sprintf(hunk.limit, "hunk.limit", "."))
  if(!is.integer(line.limit <- check_limit(line.limit)))
    err(
      sprintf(
        line.limit, "line.limit",
        ", or \"auto\" or the result of calling `auto_line_limit`"
    ) )
  # guides

  if(!is.TF(guides) && !is.function(guides))
    err("Argument `guides` must be TRUE, FALSE, or a function")
  if(is.function(guides) && !isTRUE(g.f.err <- is.two.arg.fun(guides)))
    err("Argument `guides` ", g.f.err)
  if(!is.function(guides) && !guides)
    guides <- function(obj, obj.as.chr) integer(0L)

  if(!is.TF(trim) && !is.function(trim))
    err("Argument `trim` must be TRUE, FALSE, or a function")
  if(is.function(trim) && !isTRUE(t.f.err <- is.two.arg.fun(trim)))
    err("Argument `trim` ", t.f.err)
  if(!is.function(trim) && !trim) trim <- trim_identity

  # check T F args

  if(is.null(interactive)) interactive <- interactive()
  TF.vars <- c(
    "ignore.white.space", "convert.hz.white.space", "rds", "word.diff",
    "unwrap.atomic", "interactive"
  )
  msg.base <- "Argument `%s` must be TRUE or FALSE."
  for(x in TF.vars) if(!is.TF(get(x, inherits=FALSE))) err(sprintf(msg.base, x))

  # int 1L vars

  msg.base <- "Argument `%s` must be integer(1L) and not NA."
  int.1L.vars <- c("max.diffs", "term.colors")
  for(x in int.1L.vars) {
    if(!is.int.1L(int.val <- get(x, inherits=FALSE)))
      err(sprintf(msg.base, "max.diffs"))
    assign(x, as.integer(int.val))
  }
  # char or NULL vars

  chr1LorNULL.vars <- c("tar.banner", "cur.banner")
  msg.base <- "Argument `%s` must be character(1L) and not NA, or NULL"
  for(x in chr1LorNULL.vars) {
    y <- get(x, inherits=FALSE)
    if(!is.chr.1L(y) && !is.null(y)) err(sprintf(msg.base, x))
  }
  # Align threshold

  if(!is(align, "AlignThreshold")) {
    align <- if(
      is.numeric(align) && length(align) == 1L &&
      !is.na(align) && align %bw% c(0, 1)
    ) {
      AlignThreshold(threshold=align)
    } else if(is.null(align)) {
      AlignThreshold()
    } else err(
      "Argument `align` must be an \"AlignThreshold\" object or numeric(1L) ",
      "and between 0 and 1."
    )
  }
  # style

  if(!is(style, "Style") && !string_in(style, "auto"))
    err("Argument `style` must be \"auto\" or a `Style` object.")

  # pager

  valid.pagers <- c("auto", "off", "on")
  if(!is(pager, "Pager") && !string_in(pager, valid.pagers))
    err(
      "Argument `pager` must be one of `", dep(valid.pagers),
      "` or a `Pager` object."
    )
  if(!is(pager, "Pager") && string_in(pager, "off"))
    pager <- PagerOff()

  # palette and arguments that reference palette dimensions

  if(is.null(palette.of.styles)) palette.of.styles <- PaletteOfStyles()
  if(!is(palette.of.styles, "PaletteOfStyles"))
    err("Argument `palette.of.styles` must be a `PaletteOfStyles` object.")

  palette.params <- c("brightness", "color.mode")
  for(x in palette.params)
    if(
      !isTRUE(
        msg <- is.valid.palette.param(
          get(x, inherits=FALSE), x, palette.of.styles
      ) )
    ) err(msg)

  # Figure out whether pager is allowable or not; note that "auto" pager just
  # means let the pager that comes built into the style be the pager

  if(!is(pager, "Pager")) {
    pager <- if(
      (pager == "auto" && interactive) || pager == "on"
    ) {
      "on"
    } else PagerOff()
  }
  # format; decide what format to use

  if(!is(style, "Style") && string_in(style, "auto")) {
    if(!is.chr.1L(format))
      err("Argument `format` must be character(1L) and not NA")
    valid.formats <- c("auto", dimnames(palette.of.styles@data)$format)
    if(!format %in% valid.formats)
      err("Argument `format` must be one of `", dep(valid.formats) , "`.")
    if(format == "auto") {
      if(!is.int.1L(term.colors))
        err(
          "Logic Error: unexpected return from `crayon::num_colors()`; ",
          "contact maintainer."
        )
      # No recognized color alternatives, try to use HTML if we can

      format <- if(!term.colors %in% c(8, 256)) {
        if(
          interactive && (identical(pager, "on") || is(pager, "PagerBrowser"))
        ) "html" else "raw"
      } else if (term.colors == 8) {
        "ansi8"
      } else if (term.colors == 256) {
        "ansi256"
      } else stop("Logic error: unhandled format; contact maintainer.")
    }
    style <- palette.of.styles[[
      format, get_pal_par(format, brightness), get_pal_par(format, color.mode)
    ]]
    if(is(style, "classRepresentation")) style <- new(style)
  } else if(!is(style, "Style"))
    stop("Logic Error: unexpected style state; contact maintainer.")

  # Attach specific pager if it was requested generated; if "auto" just let the
  # existing pager on the style be, which is done by not modifying @pager

  if(is(pager, "Pager")) style@pager <- pager
  else if(!identical(pager, "on"))
    stop("Logic Error: Unexpected pager state; contact maintainer.")

  # Check display width

  if(!isTRUE(d.w.err <- is.valid.width(disp.width)))
    err("Arugment `disp.width` ", d.w.err)
  disp.width <- as.integer(disp.width)
  if(disp.width) {
    style@disp.width <- disp.width
  } else if(!style@disp.width) {
    d.w <- getOption("width")
    if(!is.valid.width(d.w)) {
      # nocov start this should never happen
      warning("`getOption(\"width\") returned an invalid width, using 80L")
      d.w <- 80L
      # nocov end
    }
    style@disp.width <- d.w
  }
  disp.width <- style@disp.width

  # instantiate settings object

  etc <- new(
    "Settings", mode=val.modes[[which(mode.eq)]], context=context,
    line.limit=line.limit, ignore.white.space=ignore.white.space,
    max.diffs=max.diffs, align=align, disp.width=disp.width,
    hunk.limit=hunk.limit, convert.hz.white.space=convert.hz.white.space,
    tab.stops=tab.stops, style=style, frame=frame,
    tar.exp=tar.exp, cur.exp=cur.exp, guides=guides, tar.banner=tar.banner,
    cur.banner=cur.banner, trim=trim, word.diff=word.diff,
    unwrap.atomic=unwrap.atomic
  )
  etc
}
