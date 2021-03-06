% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/s4.R
\docType{class}
\name{AlignThreshold-class}
\alias{AlignThreshold}
\alias{AlignThreshold-class}
\title{Controls How Lines Within a Diff Hunk Are Aligned}
\description{
Controls How Lines Within a Diff Hunk Are Aligned
}
\section{Slots}{

\describe{
\item{\code{threshold}}{numeric(1L) between 0 and 1, what proportion of words
in the lines must match in order to align them.  Set to 1 to effectively
turn aligning off.  Defaults to 0.25.}

\item{\code{min.chars}}{integer(1L) positive, minimum number of characters that must
match across lines in order to align them.  This requirement is in addition
to \code{threshold} and helps minimize spurious alignments.  Defaults to
3.}

\item{\code{count.alnum.only}}{logical(1L) modifier for \code{min.chars}, whether to
count alpha numeric characters only.  Helps reduce spurious alignment
caused by meta character sequences such as \dQuote{[[1]]} that would
otherwise meet the \code{min.chars} limit}
}}

