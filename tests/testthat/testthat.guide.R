context("Guides")

test_that("detect_2d_guides", {
   iris.dply <- c("Source: local data frame [150 x 5]", "Groups: Species [3]", "", "   Sepal.Length Sepal.Width", "          (dbl)       (dbl)", "1           5.1         3.5", "2           4.9         3.0", "3           4.7         3.2", "4           4.6         3.1", "5           5.0         3.6", "6           5.4         3.9", "7           4.6         3.4", "8           5.0         3.4", "9           4.4         2.9", "10          4.9         3.1", "..          ...         ...", "Variables not shown: Petal.Length", "  (dbl), Petal.Width (dbl), Species", "  (fctr)")
   expect_equal(diffobj:::detect_2d_guides(iris.dply), 4:5)
   old.opt <- options(width=40)
   on.exit(options(old.opt))
   expect_equal(diffobj:::detect_2d_guides(capture.output(iris)), c(1, 152))
   expect_equal(
     diffobj:::detect_2d_guides(capture.output(USAccDeaths)), c(1, 8, 15)
   )
   # Time series
   expect_equal(diffobj:::detect_2d_guides(capture.output(UKgas)), 1)
})
test_that("detect_list_guides", {
  l.1 <- list(1, 1:3, matrix(1:3, 1))
  l.2 <- list(a=1, list(1:3, b=4, c=list(1, b=2)), matrix(1:3, 1))
  c.l.1 <- capture.output(l.1)
  c.l.2 <- capture.output(l.2)
  # cbind(c.l.2, seq_along(c.l.2) %in% diffobj:::detect_list_guides(c.l.2))
  expect_equal(diffobj:::detect_list_guides(capture.output(l.1)), c(1, 4, 7))
  expect_equal(
    diffobj:::detect_list_guides(capture.output(l.2)),
    c(1, 5, 8, 12, 15, 20)
  )
})
test_that("detect_matrix_guides", {
  mx3 <- mx4 <- mx5 <- mx5a <- mx11 <- matrix(
   c(
      "averylongwordthatcanlahblah", "causeasinglewidecolumnblah",
      "matrixtowrapseveraltimes", "inarrowscreen", "onceuponatime",
      "agreenduckflew", "overthemountains", "inalongofantelopes",
      "ineedthreemore", "entriesactually", "nowonlytwomore", "iwaswrongearlier"
    ),
    nrow=3, ncol=4
  )
  mx3.c <- capture.output(mx3)
  expect_equal(diffobj:::detect_matrix_guides(mx3.c, NULL), c(1, 5))

  dimnames(mx4) <- list(A=NULL, B=NULL)
  mx4.c <- capture.output(mx4)
  expect_equal(
    diffobj:::detect_matrix_guides(mx4.c, dimnames(mx4)), c(1, 2, 6, 7)
  )
  attr(mx5, "blah") <- letters[1:10]
  mx5.c <- capture.output(mx5)
  expect_equal(
    diffobj:::detect_matrix_guides(mx5.c, dimnames(mx5)), c(1, 5)
  )
  # Simple matrices that don't wrap

  mx6 <- mx7 <- mx7.1 <- matrix(1:4, 2)

  mx6.c <- capture.output(mx6)
  expect_equal(diffobj:::detect_matrix_guides(mx6.c, dimnames(mx6)), 1)

  dimnames(mx7) <- list(A=letters[1:2], B=LETTERS[25:26])
  mx7.c <- capture.output(mx7)
  expect_equal(diffobj:::detect_matrix_guides(mx7.c, dimnames(mx7)), c(1, 2))

  dimnames(mx7.1) <- list(letters[1:2], B=LETTERS[25:26])
  mx7.1.c <- capture.output(mx7.1)
  expect_equal(diffobj:::detect_matrix_guides(mx7.1.c, dimnames(mx7.1)), c(1, 2))

  # Single col matrix

  mx8 <- matrix(1:2, 2)

  mx8.c <- capture.output(mx8)
  expect_equal(diffobj:::detect_matrix_guides(mx8.c, dimnames(mx8)), 1)

  # Wrapping matrices with colnames

  mx9 <- mx3
  dimnames(mx9) <- list(A=letters[1:3], B=LETTERS[20:23])
  mx9.c <- capture.output(mx9)
  expect_equal(
    diffobj:::detect_matrix_guides(mx9.c, dimnames(mx9)), c(1:2, 6:7)
  )

  mx10 <- mx9
  attr(mx10, "blah") <- matrix(1:4, 2)
  mx10.c <- capture.output(mx10)
  expect_equal(
    diffobj:::detect_matrix_guides(mx10.c, dimnames(mx10)), c(1:2, 6:7)
  )

  old.opt <- options(width=30L)
  on.exit(options(old.opt))
  attr(mx11, "blah") <- letters[1:15]
  mx11.c <- capture.output(mx11)

  expect_equal(
    diffobj:::detect_matrix_guides(mx11.c, dimnames(mx11)), c(1, 5, 9, 13)
  )
})
test_that("detect_array_guides", {
  a.1 <- array(1:6, dim=c(2, 1, 3))
  a.2 <- array(1:6, dim=c(2, 1, 3), dimnames=list(NULL, "X", LETTERS[1:3]))
  a.3 <- array(
    1:6, dim=c(2, 1, 3),
    dimnames=list(rows=NULL, cols="X", LETTERS[1:3])
  )
  a.4 <- `attr<-`(a.3, "hello", "random attribute")
  a.5 <- array(1:36, dim=c(6, 2, 3))
  a.6 <- array(1:2, c(2, 1, 1))
  c.a.1 <- capture.output(a.1)
  c.a.2 <- capture.output(a.2)
  c.a.3 <- capture.output(a.3)
  c.a.4 <- capture.output(a.4)
  c.a.5 <- capture.output(a.5)
  c.a.6 <- capture.output(a.6)
  # helper funs to vizualize the guide line detection
  # viz_dag <- function(capt, obj)
  #   cbind(
  #     capt,
  #     seq_along(capt) %in% diffobj:::detect_array_guides(capt, dimnames(obj))
  #   )
  # viz_dag(c.a.1, a.1)
  # viz_dag(c.a.2, a.2)
  # viz_dag(c.a.3, a.3)
  # viz_dag(c.a.4, a.4)
  # viz_dag(c.a.5, a.5)
  # viz_dag(c.a.6, a.6)
  expect_equal(
    diffobj:::detect_array_guides(c.a.1, dimnames(a.1)),
    c(1L, 2L, 7L, 8L, 13L, 14L)
  )
  expect_equal(
    diffobj:::detect_array_guides(c.a.2, dimnames(a.2)),
    c(1L, 2L, 7L, 8L, 13L, 14L)
  )
  expect_equal(
    diffobj:::detect_array_guides(c.a.3, dimnames(a.3)),
    c(1L, 2L, 8L, 9L, 15L, 16L)
  )
  expect_equal(
    diffobj:::detect_array_guides(c.a.4, dimnames(a.4)),
    c(1L, 2L, 8L, 9L, 15L, 16L)
  )
  expect_equal(
    diffobj:::detect_array_guides(c.a.5, dimnames(a.5)),
    c(1L, 2L, 11L, 12L, 21L, 22L)
  )
  expect_equal(
    diffobj:::detect_array_guides(c.a.6, dimnames(a.6)),
    c(1L, 2L)
  )
})
