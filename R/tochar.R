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

# @include S4.R

NULL

# Compute the ranges of a hunk group based on atomic hunk ids
#
# rng.o is a matrix where each column represents `c(tar.rng, cur.rng)`
# and rng.o has the original untrimmed values

find_rng <- function(ids, rng.o) {
  with.rng <- ids[which(rng.o[1L, ids] > 0L)]
  if(!length(with.rng)) {
    # Find previous earliest originally existing item we want to insert
    # after; note we need to look at the non-trimmed ranges, and we include
    # the first context atomic hunk in the group as a potential match
    prev <- rng.o[
      2L, seq_len(ncol(rng.o)) <= max(ids[[1L]], 0L) &
        rng.o[1L, ] > 0L
    ]
    if(!length(prev)) integer(2L) else c(max(prev), 0L)
  } else {
    c(min(rng.o[1L, intersect(ids, with.rng)]), max(rng.o[2L, ids]))
  }
}
# Create a text representation of a file line range to use in the hunk header

rng_as_chr <- function(range) {
  if(length(range) < 2L) "0" else {
    a <- range[[1L]]
    b <- if(diff(range))
      paste0(",", if(range[[2L]]) diff(range) + 1L else 0)
    paste0(a, b)
  }
}
# Finalization function should return a list with two character vectors for
# diff contents, and two factor vectors denoting the type of content for
# each of the character vectors where valid data types are ins, del, mtc, hdr,
# ctx; chrt is just a helper function to generate factors with those possible
# values

chrt <- function(...)
  factor(
    c(...),
    levels=c(
      "insert", "delete", "match", "header", "context.sep",
      "banner.insert", "banner.delete", "guide", "fill"
    )
  )
hunkl <- function(col.1=NULL, col.2=NULL, type.1=NULL, type.2=NULL)
  c(
    list(
      if(is.null(col.1)) list(dat=character(), type=chrt()) else
        list(dat=col.1, type=type.1)
      ),
    if(!is.null(col.2)) list(list(dat=col.2, type=type.2))
  )

# finalization functions take aligned data and juxtapose it according to
# selected display mode.  Note that _context must operate on all the hunks
# in a hunk group, whereas the other two operate on each hunk atom.  Padding
# is identified in two forms: as actual A.fill and B.fill values when there
# was a wrapped diff, and in side by side mode when the lengths of A and B
# are not the same and end up adding NAs.  Padding is really only meaningful
# for side by side mode so is removed in the other modes

# The A.fill and B.fill business is a bit of a mess, because ideally we woudl
# want a structure parallel to the data structure instead of just vectors that
# we need to line up with the data lists, but this is all a result of trying
# to shoehorn new functionality in...

fin_fun_context <- function(dat) {
  dat_wo_fill <- function(x, ind) unlist(x[[ind]])[!x[[sprintf("%s.fill", ind)]]]
  A.dat <- lapply(dat, dat_wo_fill, "A")
  B.dat <- lapply(dat, dat_wo_fill, "B")

  A.lens <- vapply(A.dat, function(x) length(unlist(x)), integer(1L))
  B.lens <- vapply(B.dat, function(x) length(unlist(x)), integer(1L))

  A.ul <- unlist(A.dat)
  B.ul <- unlist(B.dat)

  context <- vapply(dat, "[[", logical(1L), "context")
  guide <- vapply(dat, "[[", logical(1L), "guide")
  A.ctx <- rep(context, A.lens)
  A.guide <- rep(guide, A.lens)
  B.ctx <- rep(context, B.lens)
  B.guide <- rep(guide, B.lens)
  A.types <- ifelse(A.guide, "guide", ifelse(A.ctx, "match", "delete"))
  B.types <- ifelse(B.guide, "guide", ifelse(B.ctx, "match", "insert"))

  # return in list so compatible with post `lapply` return values for other
  # finalization functions

  list(
    hunkl(
      col.1=c(A.ul,  if(length(B.ul)) NA, B.ul),
      type.1=chrt(A.types, if(length(B.ul)) "context.sep", B.types)
    )
  )
}
fin_fun_unified <- function(A, B, A.fill, B.fill, context, guide) {
  A.lens <- vapply(A, length, integer(1L))
  B.lens <- vapply(B, length, integer(1L))
  A.ord <- rep(seq_along(A.lens), A.lens)[!A.fill]
  B.ord <- rep(seq_along(B.lens), B.lens)[!B.fill]
  A <- unlist(A)[!A.fill]
  B <- unlist(B)[!B.fill]

  ord <- order(c(A.ord, B.ord))
  types <- c(
    rep(if(guide) "guide" else if(context) "match" else "delete", sum(A.lens)),
    rep(if(guide) "guide" else if(context) "match" else "insert", sum(B.lens))
  )
  hunkl(
    col.1=unlist(c(A, B)[ord]), type.1=chrt(unlist(types[ord]))
  )
}
fin_fun_sidebyside <- function(A, B, A.fill, B.fill, context, guide) {
  for(i in seq_along(A)) {
    A.ch <- A[[i]]
    B.ch <- B[[i]]
    A.l <- length(A.ch)
    B.l <- length(B.ch)
    max.l <- max(A.l, B.l)
    length(A.ch) <- length(B.ch) <- max.l

    A[[i]] <- A.ch
    B[[i]] <- B.ch
  }
  A.ul <- unlist(A)
  B.ul <- unlist(B)
  A.fill.u <- B.fill.u <- !logical(length(A.ul))
  A.fill.u[!is.na(A.ul)] <- A.fill
  B.fill.u[!is.na(B.ul)] <- B.fill

  A.len <- length(A.ul)
  B.len <- length(B.ul)
  hunkl(
    col.1=ifelse(is.na(A.ul), "", A.ul),
    col.2=ifelse(is.na(B.ul), "", B.ul),
    type.1=chrt(
      ifelse(
        rep(guide, A.len), "guide",
        ifelse(A.fill.u, "fill",
          ifelse(context, "match", "delete")
    ) ) ),
    type.2=chrt(
      ifelse(
        rep(guide, B.len), "guide",
        ifelse(B.fill.u, "fill",
          ifelse(context, "match", "insert")
  ) ) ) )
}
# Compute the character representation of a hunk header

make_hh <- function(h.g, x, ranges.orig) {
  stopifnot(is(x, "Diff"))

  etc <- x@etc
  mode <- etc@mode

  h.ids <- vapply(h.g, "[[", integer(1L), "id")
  h.head <- vapply(h.g, "[[", logical(1L), "guide")

  # exclude header hunks from contributing to range, and adjust ranges for
  # possible fill lines added to the data

  h.ids.nh <- h.ids[!h.head]
  tar.rng <- find_rng(h.ids.nh, ranges.orig[1:2, , drop=FALSE])
  tar.rng.f <- cumsum(!x@tar.dat$fill)[tar.rng]
  cur.rng <- find_rng(h.ids.nh, ranges.orig[3:4, , drop=FALSE])
  cur.rng.f <- cumsum(!x@cur.dat$fill)[cur.rng]

  hh.a <- paste0(rng_as_chr(tar.rng.f))
  hh.b <- paste0(rng_as_chr(cur.rng.f))

  if(mode == "sidebyside") sprintf("@@ %s @@", c(hh.a, hh.b)) else {
    sprintf("@@ %s / %s @@", hh.a, hh.b)
  }
}

# Convert a hunk group into text representation

hunk_atom_as_char <- function(h.a, x) {
  etc <- x@etc
  mode <- x@etc@mode
  if(mode=="context") {
    ghd.mode.1 <- "A"
    ghd.mode.2 <- "B"
    ghd.type.1 <- ghd.type.2 <- "both"
  } else if(mode == "unified") {
    ghd.mode.1 <- ghd.mode.2 <-"A"
    ghd.type.1 <- "pos"
    ghd.type.2 <- "neg"
  } else if(mode == "sidebyside") {
    ghd.mode.1 <- "A"
    ghd.mode.2 <- "B"
    ghd.type.1 <- "pos"
    ghd.type.2 <- "neg"
  }
  A.ind <- get_hunk_ind(h.a, mode=ghd.mode.1, ghd.type.1)
  B.ind <- get_hunk_ind(h.a, mode=ghd.mode.2, ghd.type.2)

  # Align the lines accounting for partial matching post word-diff,
  # each diff style has a different finalization function

  dat.align <- align_eq(A.ind, B.ind, x=x, context=h.a$context)
  list(
    A=dat.align$A, B=dat.align$B,
    A.fill=dat.align$A.fill, B.fill=dat.align$B.fill,
    context=h.a$context, guide=h.a$guide
  )
}
hunk_as_char <- function(h.g, h.h, x) {
  stopifnot(is(x, "Diff"))

  etc <- x@etc
  mode <- etc@mode

  hunk.head <- if(length(h.g) && !h.g[[1L]]$completely.empty) {
    list(
      if(mode == "sidebyside") {
        hunkl(
          col.1=h.h[1L], col.2=h.h[2L],
          type.1=chrt("header"), type.2=chrt("header")
        )
      } else {
        hunkl(col.1=h.h, type.1=chrt("header"))
  } ) }
  # Generate hunk contents in aligned form

  hunk.res <- lapply(h.g, hunk_atom_as_char, x=x)

  # Run finalization functions; context mode is different because we need to
  # re-order across atomic hunks

  fin_fun <- switch(
    mode, unified=fin_fun_unified, sidebyside=fin_fun_sidebyside,
    context=fin_fun_context
  )
  hunk.fin <- if(mode != "context") {
    lapply(hunk.res, function(x) do.call(fin_fun, x))
  } else {
    fin_fun_context(hunk.res)
  }
  # Add header and return; this a list of lists, though all sub-lists should
  # have same format

  c(hunk.head, hunk.fin)
}
# Helper functions for 'as.character'

# Get trimmed character ranges; positives are originally from target, and
# negatives from current

get_hunk_ind <- function(h.a, mode, type="both") {
  stopifnot(
    mode %in% LETTERS[1:2], length(mode) == 1L,
    is.chr.1L(type), type %in% c("both", "pos", "neg")
  )
  rng.raw <- c(
    if(type %in% c("pos", "both"))
      seq(h.a$tar.rng.trim[[1L]], h.a$tar.rng.trim[[2L]]),
    if(type %in% c("neg", "both"))
      -seq(h.a$cur.rng.trim[[1L]], h.a$cur.rng.trim[[2L]])
  )
  rng.raw[rng.raw %in% h.a[[mode]]]
}
#' @rdname diffobj_s4method_doc

setMethod("as.character", "Diff",
  function(x, ...) {
    old.crayon.opt <-
      options(crayon.enabled=is(x@etc@style, "StyleAnsi"))
    on.exit(options(old.crayon.opt), add=TRUE)

    # These checks should never fail since presumably the inputs have been
    # checked earlier; here just in case we mess something up in devel or
    # testing

    hunk.limit <- x@etc@hunk.limit
    line.limit <- x@etc@line.limit
    hunk.limit <- x@etc@hunk.limit
    disp.width <- x@etc@disp.width
    mode <- x@etc@mode
    tab.stops <- x@etc@tab.stops
    ignore.white.space <- x@etc@ignore.white.space

    # legacy from when we had different max diffs for different parts of diff
    max.diffs <- x@etc@max.diffs
    max.diffs.in.hunk <- x@etc@max.diffs
    max.diffs.wrap <- x@etc@max.diffs

    s <- x@etc@style  # shorthand

    len.max <- max(length(x@tar.dat$raw), length(x@cur.dat$raw))
    no.diffs <- if(!suppressWarnings(any(x))) {
      # This needs to account for "trim" effects

      msg <- "No visible differences between objects"
      msg.extra <- if(
        (ignore.white.space || x@etc@convert.hz.white.space) &&
        !isTRUE(all.equal(x@tar.dat$orig, x@cur.dat$orig)) &&
        isTRUE(all.equal(x@tar.dat$comp, x@cur.dat$comp))
      ) {
        paste0(
          ", but there are white space differences; re-run diff with ",
          "`ignore.white.space=FALSE` and `convert.hz.white.space=FALSE` ",
          "to show them.", collapse=""
        )
      } else if (!isTRUE(all.equal(x@target, x@current))) {
        ", but objects are _not_ `all.equal`."
      } else "."
      res <- paste0(msg, msg.extra)
    }
    # Basic width computation and banner size; start by computing gutter so we
    # can figure out what's left

    gutter.dat <- x@etc@gutter
    banner.len <- banner_len(mode)
    max.w <- x@etc@text.width

    line.limit.a <- if(line.limit[[1L]] >= 0L)
      pmax(integer(2L), line.limit - banner.len) else line.limit

    # Trim hunks to the extented needed to make sure we fit in lines

    x@etc@line.limit <- line.limit.a
    hunk.grps <- trim_hunks(x)
    hunks.flat <- unlist(hunk.grps, recursive=FALSE)

    # Compact to width of widest element, so retrieve all char values; also
    # need to generate all the hunk headers b/c we need to use them in width
    # computation as well; under no circumstances are hunk headers allowed to
    # wrap as they are always assumed to take one line

    chr.ind <- unlist(lapply(hunks.flat, "[", c("A", "B")))
    chr.dat <- get_dat(x, chr.ind, "raw")
    chr.size <- integer(length(chr.dat))

    ranges <- vapply(
      hunks.flat, function(h.a) c(h.a$tar.rng.trim, h.a$cur.rng.trim),
      integer(4L)
    )
    ranges.orig <- vapply(
      hunks.flat, function(h.a) c(h.a$tar.rng.sub, h.a$cur.rng.sub), integer(4L)
    )
    hunk.heads <- lapply(hunk.grps, make_hh, x, ranges.orig)
    h.h.chars <- nchar(chr_trim(unlist(hunk.heads), x@etc@line.width))

    if(s@wrap) {
      is.ansi <- is(x@etc@style, "StyleAnsi") &
        grepl(ansi_regex, chr.dat, perl=TRUE)
      if(any(is.ansi)) chr.size[is.ansi] <- crayon_nchar(chr.dat)
      chr.size[!is.ansi] <- nchar(chr.dat)
      max.col.w <- max(
        max(0L, chr.size, .min.width) + gutter.dat@width, h.h.chars
      )
      max.w <- if(max.col.w < max.w) max.col.w else max.w

      # future calculations should assume narrower display

      x@etc@text.width <- max.w
      x@etc@line.width <- max.w + gutter.dat@width
      s <- x@etc@style
      etc <- x@etc
    }
    # Make the object banner and compute more detailed widths post trim

    tar.banner <- if(!is.null(x@etc@tar.banner)) x@etc@tar.banner else
      deparse(x@etc@tar.exp)[[1L]]
    cur.banner <- if(!is.null(x@etc@cur.banner)) x@etc@cur.banner else
      deparse(x@etc@cur.exp)[[1L]]
    ban.A.trim <-
      if(s@wrap) chr_trim(tar.banner, x@etc@text.width) else tar.banner
    ban.B.trim <-
      if(s@wrap) chr_trim(cur.banner, x@etc@text.width) else cur.banner
    banner.A <- s@funs@word.delete(ban.A.trim)
    banner.B <- s@funs@word.insert(ban.B.trim)

    # Trim banner if exceeds line limit, currently we're implicitly assuming
    # that each banner line does not exceed 1 in length; may change in future

    if(line.limit[[1L]] >= 0) {
      if(line.limit[[2L]] < 2L && mode != "sidebyside") banner.A <- NULL
      if(line.limit[[2L]] < 1L) banner.B <- banner.A <- NULL
    }
    # Post trim, figure out max lines we could possibly be showing from capture
    # strings; careful with ranges,

    trim.meta <- attr(hunk.grps, "meta")
    lim.line <- trim.meta$lines
    lim.hunk <- trim.meta$hunks
    ll <- !!lim.line[[1L]]
    lh <- !!lim.hunk[[1L]]
    diff.count <- count_diffs(hunk.grps)
    str.fold.out <- if(x@capt.mode == "str" && x@diff.count.full > diff.count) {
      paste0(
        x@diff.count.full - diff.count,
        " differences are hidden by our use of `max.level`"
      )
    }
    limit.out <- if(ll || lh) {
      if(!is.null(str.fold.out)) {
        # nocov start
        stop(
          "Logic Error: should not be str folding when limited; contact ",
          "maintainer."
        )
        # nocov end
      }
      paste0(
        "... omitted ",
        if(ll) sprintf("%d/%d lines", lim.line[[1L]], lim.line[[2L]]),
        if(ll && lh) ", ",
        if(lh) sprintf("%d/%d hunks", lim.hunk[[1L]], lim.hunk[[2L]])
      )
    }
    tar.max <- max(ranges[2L, ], 0L)
    cur.max <- max(ranges[4L, ], 0L)

    # At this point we need to actually reconstitute the final output string by:
    # - Applying word diffs
    # - Reconstructing untrimmed strings
    # - Substitute appropriate values for empty strings

    f.f <- x@etc@style@funs
    tar.w.c <- word_color(x@tar.dat$trim, x@tar.dat$word.ind, f.f@word.delete)
    cur.w.c <- word_color(x@cur.dat$trim, x@cur.dat$word.ind, f.f@word.insert)

    x@tar.dat$fin <- untrim(x@tar.dat, tar.w.c, x@etc)
    x@cur.dat$fin <- untrim(x@cur.dat, cur.w.c, x@etc)

    # Generate the pre-rendered hunk data as text columns; a bit complicated
    # as we need to unnest stuff; use rbind to make it a little easier.

    pre.render.raw <- unlist(
      Map(hunk_as_char, hunk.grps, hunk.heads, x=list(x)),
      recursive=FALSE
    )
    pre.render.mx <- do.call(rbind, pre.render.raw)
    pre.render.mx.2 <- lapply(
      split(pre.render.mx, col(pre.render.mx)), do.call, what="rbind"
    )
    pre.render <- lapply(
      unname(pre.render.mx.2),
      function(mx) list(
        dat=unlist(mx[, 1L]),
        type=unlist(mx[, 2L], recursive=FALSE)
    ) )
    # Add the banners; banners are rendered exactly like normal text, except
    # for the line level functions

    if(mode == "sidebyside") {
      pre.render[[1L]]$dat <- c(banner.A, pre.render[[1L]]$dat)
      pre.render[[1L]]$type <- c(chrt("banner.delete"), pre.render[[1L]]$type)
      pre.render[[2L]]$dat <- c(banner.B, pre.render[[2L]]$dat)
      pre.render[[2L]]$type <- c(chrt("banner.insert"), pre.render[[2L]]$type)
    } else {
      pre.render[[1L]]$dat <- c(banner.A, banner.B, pre.render[[1L]]$dat)
      pre.render[[1L]]$type <- c(
        chrt("banner.delete", "banner.insert"), pre.render[[1L]]$type
      )
    }
    # Generate wrapped version of the text; if in sidebyside, make sure that
    # all elements are same length

    pre.render.w <- if(s@wrap) {
      pre.render.w <- replicate(
        length(pre.render),
        vector("list", length(pre.render[[1L]]$dat)), simplify=FALSE
      )
      for(i in seq_along(pre.render)) {
        hdr <- pre.render[[i]]$type == "header"
        pre.render.w[[i]][hdr] <-
          wrap(pre.render[[i]]$dat[hdr], x@etc@line.width)
        pre.render.w[[i]][!hdr] <-
          wrap(pre.render[[i]]$dat[!hdr], x@etc@text.width)
      }
      pre.render.w
    } else lapply(pre.render, function(y) as.list(y$dat))

    line.lens <- lapply(pre.render.w, vapply, length, integer(1L))
    types.raw <- lapply(pre.render, "[[", "type")
    types <- lapply(
      types.raw, function(y) sub("^banner\\.", "", as.character(y))
    )
    if(mode == "sidebyside") {
      line.lens.max <- replicate(2L, do.call(pmax, line.lens), simplify=FALSE)
      pre.render.w <- lapply(
        pre.render.w, function(y) {
          Map(
            function(dat, len) {
              length(dat) <- len
              dat
            },
            y, line.lens.max[[1L]]
      ) } )
    } else line.lens.max <- line.lens

    # Substitute NA elements with the appropriate values as dictated by the
    # styles; also record lines NA positions

    lines.na <- lapply(pre.render.w, lapply, is.na)
    pre.render.w <- lapply(
      pre.render.w, lapply,
      function(y) {
        res <- y
        res[is.na(y)] <- x@etc@style@na.sub
        res
    } )

    # Compute gutter, padding, and continuations

    pads <- lapply(
      line.lens, function(y) lapply(y, rep, x=gutter.dat@pad)
    )
    gutters <- render_gutters(
      types=types, lens=line.lens, lens.max=line.lens.max, etc=x@etc
    )
    # Pad text

    pre.render.w.p <- if(s@pad) {
      Map(
        function(col, type) {
          diff.line <- type %in% c("insert", "delete", "match", "guide", "fill")
          col[diff.line] <- lapply(col[diff.line], rpad, x@etc@text.width)
          col[!diff.line] <- lapply(col[!diff.line], rpad, x@etc@line.width)
          col
        },
        pre.render.w, types
      )
    } else pre.render.w

    # Apply text level styles; make sure that all types are defined here
    # otherwise you'll get lines missing in output; note that fill lines were
    # represented by NAs originally and we indentify them within each aligned
    # group with `lines.na`

    es <- x@etc@style
    funs.ts <- list(
      insert=function(x) es@funs@text(es@funs@text.insert(x)),
      delete=function(x) es@funs@text(es@funs@text.delete(x)),
      match=function(x) es@funs@text(es@funs@text.match(x)),
      guide=function(x) es@funs@text(es@funs@text.guide(x)),
      fill=function(x) es@funs@text(es@funs@text.fill(x)),
      context.sep=function(x) 
        es@funs@text(es@funs@context.sep(es@text@context.sep)),
      header=es@funs@header
    )
    pre.render.s <- Map(
      function(dat, type, l.na) {
        res <- vector("list", length(dat))
        for(i in names(funs.ts))  # really need to loop through all?
          res[type == i] <- Map(
            function(y, l.na.i) {
              res.s <- y
              if(any(l.na.i))
                res.s[l.na.i] <- funs.ts$fill(y[l.na.i])
              res.s[!l.na.i | i == "context.sep"] <- funs.ts[[i]](y[!l.na.i])
              res.s
            },
            dat[type == i],
            l.na[type == i]
          )
        res
      },
      pre.render.w.p, types, lines.na
    )
    # Reconstruct 'types.raw' with the appropriate lenghts, and replacing
    # types with 'fill' if elements were extended due to wrap

    types.raw.x <- Map(
      function(y, z) {
        Map(
          function(y.s, z.s) {
            res <- rep(y.s, length(z.s))
            res[z.s] <- "fill"
            res
          },
          y, z
      ) },
      types.raw, lines.na
    )
    # Render columns; note here we use 'types.raw' to distinguish banner lines

    cols <- render_cols(
      cols=pre.render.s, gutters=gutters, pads=pads, types=types.raw.x,
      etc=x@etc
    )
    # Render rows

    rows <- render_rows(cols, etc=x@etc)

    # Collect all the pieces, and for the meta pieces wrap, pad, and format

    pre.fin.l <- list(no.diffs, rows, limit.out, str.fold.out)
    meta.elem <- c(1L, 3:4)
    pre.fin.l[meta.elem] <- lapply(
      pre.fin.l[meta.elem],
      function(m) es@funs@meta(strwrap(m, width=disp.width))
    )
    pre.fin <- unlist(pre.fin.l)

    # Apply subsetting as needed

    ind <- seq_along(pre.fin)
    ind <- if(length(x@sub.index)) ind[x@sub.index] else ind
    if(length(x@sub.head)) ind <- head(ind, x@sub.head)
    if(length(x@sub.tail)) ind <- tail(ind, x@sub.tail)

    # Do the finalization

    pre.fin <- pre.fin[ind]
    res.len <- length(pre.fin)

    finalize(pre.fin, x@etc@style, res.len)
} )

# Finalizing fun used by both Diff and DiffSummary as.character methods

finalize <- function(txt, style, len) {
  pager <- if(use_pager(style@pager, len))
    style@pager else PagerOff()

  in.cont <- style@funs@container(txt)
  fin <- style@finalizer(in.cont, pager)

  attr(fin, "len") <- len
  fin
}
