# 12, 28 — Thesis Figures 12 and 28: the tree of Granger causality specifications, and
# the same tree with the result of every specification that was run.
#
# Tree (as Figure 12 of the thesis, redrawn): filter -> data -> time series ->
# bivariate Granger test, both directions. Specifications that were run are dark;
# those that were not are dashed outlines. As in the thesis, topic series are built
# only from the full data and by month (by week, or from MFA/Presidential
# documents alone, too many periods have no document). The thesis's backward-dating
# windows are struck out: they are not part of the rebuilt analysis. The thesis's
# sentiment-polarity branch (counts of positive / negative documents) is dropped.
#
# Results (Figure 28 only), one cell per test; colour = which response is
# significant at p < 0.05:
#   Topic:    monthly mean score of each topic's documents (topic_months() in
#             setup.R), full data, 3 lags; all months after 1 January 2002 (the full
#             overlap, Figure 24) and after 1 January 2015 (Figure 25), drawn as two
#             branches off the topic / full data / month leaf.
#   Time:     forward dating: periods after 1 January of each year 2002-2020, 3 lags.
#             Weekly series as Figures 13 (MFA/Pres) and 14 (full data); monthly
#             series the same way by calendar month.
# Every pair goes through the ADF rule in setup.R (stationarity_method()): levels if
# both series are stationary, first differences if neither is, Toda-Yamamoto if only
# one is; decided on the pair's full sample and kept for every window.
#
# Input:  honors-thesis-original-data/sentiments/05_*_scored.csv (score: SCORE_VERSION)
# Output: figures/output/12_granger_tree.pdf, 28_granger_tree_findings.pdf

source(if (file.exists("figures/setup.R")) "figures/setup.R" else "setup.R")

LAG_ORDER <- 3
START_YEARS <- 2002:2020
WINDOWS <- c(All = "2002-01-01", "2015+" = "2015-01-01")
WINDOW_LABELS <- c(All = "All years", "2015+" = "2015 onward")
TOPIC_SHORT <- c(trade = "Trade & finance", domestic_periphery = "Domestic periphery", tw = "Taiwan",
                 multi = "Multilateral", scs = "South China Sea", epidem = "Global health", russia = "Russia")

# ---- Results ---------------------------------------------------------------------------------
docs <- read_documents()
dated <- filter(docs, dated)
pairs <- list(mfa_pres = list(us = filter(dated, source == "pres"), ch = filter(dated, source == "mofa")),
              full = list(us = filter(dated, in_series, country == "US"),
                          ch = filter(dated, in_series, country == "China")))
builders <- list(week = weekly_series, month = monthly_series)

time_res <- bind_rows(lapply(names(pairs), function(p) bind_rows(lapply(names(builders), function(b) {
  granger_by_start(builders[[b]](pairs[[p]]$us), builders[[b]](pairs[[p]]$ch),
                   as.Date(paste0(START_YEARS, "-01-01")), LAG_ORDER) %>%
    mutate(row = format(start, "%Y"), data = p, interval = b)
})))) %>% mutate(family = "time", col = "")

series <- filter(dated, in_series)
topic_series <- lapply(c(US = "US", China = "China"), function(ctry) {
  topic_months(filter(series, country == ctry)) %>% transmute(topic, period = month, senti = topic_sentiment)
})
topic_res <- bind_rows(lapply(names(TOPIC_SHORT), function(t) {
  granger_by_start(filter(topic_series$US, topic == t) %>% select(-topic),
                   filter(topic_series$China, topic == t) %>% select(-topic), as.Date(WINDOWS), LAG_ORDER) %>%
    mutate(row = TOPIC_SHORT[[t]], col = names(WINDOWS)[match(start, as.Date(WINDOWS))])
})) %>% mutate(family = "topic", data = "full", interval = "month")

results <- bind_rows(time_res, topic_res) %>%
  mutate(outcome = granger_outcome(us_response, china_response))

# ---- Layout (all coordinates in inches; the figure is drawn 1:1) ------------------------------
FIG_W <- 6.5
X0 <- 0.12                      # left edge of the tree
FAMILIES <- c(topic = "Topic", time = "Time window")
LEAF_GAP <- 0.06; PAIR_GAP <- 0.14; FAM_GAP <- 0.34
FAM_W <- (FIG_W - 2 * X0 - (length(FAMILIES) - 1) * FAM_GAP) / length(FAMILIES)
PAIR_W <- (FAM_W - PAIR_GAP) / 2
LEAF_W <- (PAIR_W - LEAF_GAP) / 2
DATA <- c(mfa_pres = "MFA / Presidential", full = "Full data")
INTERVALS <- c(week = "Week", month = "Month")
RUN <- function(family, data = NULL, interval = NULL) {
  family == "time" || ((is.null(data) || data == "full") && (is.null(interval) || interval == "month"))
}

fam_x <- setNames(X0 + (seq_along(FAMILIES) - 1) * (FAM_W + FAM_GAP), names(FAMILIES))
leaves <- expand.grid(interval = names(INTERVALS), data = names(DATA), family = names(FAMILIES),
                      stringsAsFactors = FALSE) %>%
  mutate(xmin = fam_x[family] + (data == "full") * (PAIR_W + PAIR_GAP) + (interval == "month") * (LEAF_W + LEAF_GAP),
         xmax = xmin + LEAF_W, x = (xmin + xmax) / 2,
         run = mapply(RUN, family, data, interval))
data_nodes <- leaves %>% group_by(family, data) %>%
  summarise(xmin = min(xmin), xmax = max(xmax), run = any(run), .groups = "drop") %>% mutate(x = (xmin + xmax) / 2)

# Ink
INK <- "grey20"; OFF <- "grey62"; BAND <- "grey95"
OUTCOME_FILLS <- c("US as response" = COUNTRY_COLORS[["US on China"]],
                   "China as response" = COUNTRY_COLORS[["China on the US"]],
                   "Both" = NA, "Neither" = "white")
FONT <- "serif"

# Text width in inches (for the strike-through and the legend), at ggplot text size `size`.
text_w <- function(label, size, face = 1) {
  grDevices::pdf(NULL); on.exit(grDevices::dev.off())
  graphics::par(family = FONT, ps = size * .pt, font = face)
  graphics::strwidth(label, units = "inches")
}

# Rounded rectangle as a polygon (radius r, inches).
round_rect <- function(xmin, xmax, ymin, ymax, r = 0.035, n = 6) {
  a <- seq(0, pi / 2, length.out = n)
  corner <- function(cx, cy, from) tibble(x = cx + r * cos(from + a), y = cy + r * sin(from + a))
  bind_rows(corner(xmax - r, ymax - r, 0), corner(xmin + r, ymax - r, pi / 2),
            corner(xmin + r, ymin + r, pi), corner(xmax - r, ymin + r, 3 * pi / 2))
}
boxes_df <- function(b) {   # b: one row per box with xmin..ymax, fill, colour, linetype
  bind_rows(lapply(seq_len(nrow(b)), function(i) {
    round_rect(b$xmin[i], b$xmax[i], b$ymin[i], b$ymax[i]) %>%
      mutate(id = i, fill = b$fill[i], colour = b$colour[i], linetype = b$linetype[i])
  }))
}
node_style <- function(run) tibble(fill = ifelse(run, INK, "white"), colour = ifelse(run, INK, OFF),
                                   linetype = ifelse(run, "solid", "22"), text = ifelse(run, "white", OFF))

# Elbow connectors from a parent (x, bottom) to children (x, top).
elbow <- function(px, pbottom, cx, ctop, crun) {
  ymid <- (pbottom + ctop) / 2
  bind_rows(tibble(x = px, y = pbottom, xend = px, yend = ymid, run = any(crun)),
            tibble(x = px, y = ymid, xend = cx, yend = ymid, run = crun),
            tibble(x = cx, y = ymid, xend = cx, yend = ctop, run = crun))
}

build_tree <- function(with_results) {
  BAND_GAP <- 0.08
  heights <- c(filter = 1.02, data = 0.56, series = 0.56, test = 0.56,
               result = if (with_results) 0.34 + 0.125 * length(START_YEARS) + 0.06 else 0)
  heights <- heights[heights > 0]
  LEGEND_H <- if (with_results) 0 else 0.34   # Figure 28: legend sits inside the results band
  fig_h <- sum(heights) + BAND_GAP * (length(heights) - 1) + LEGEND_H + 0.04
  tops <- fig_h - 0.02 - c(0, cumsum(heights + BAND_GAP))[seq_along(heights)]
  names(tops) <- names(heights)
  bands <- tibble(name = names(heights), ymax = tops, ymin = tops - heights,
                  label = c(filter = "1  Filter", data = "2  Data", series = "3  Time series",
                            test = "4  Granger test", result = "5  Result")[names(heights)])

  # Nodes
  head_top <- tops[["filter"]] - 0.2; head_h <- 0.22; body_h <- 0.52
  cards <- tibble(family = names(FAMILIES), xmin = fam_x, xmax = fam_x + FAM_W)
  card_heads <- cards %>% mutate(ymax = head_top, ymin = head_top - head_h, label = FAMILIES[family])
  card_bodies <- cards %>% mutate(ymax = head_top - head_h, ymin = head_top - head_h - body_h)
  NODE_H <- 0.25
  dn <- data_nodes %>% mutate(ymax = tops[["data"]] - 0.2, ymin = ymax - NODE_H, label = DATA[data])
  lv <- leaves %>% mutate(ymax = tops[["series"]] - 0.2, ymin = ymax - NODE_H, label = INTERVALS[interval])
  test_box <- tibble(xmin = X0, xmax = X0 + length(FAMILIES) * FAM_W + (length(FAMILIES) - 1) * FAM_GAP,
                     ymax = tops[["test"]] - 0.2, ymin = tops[["test"]] - 0.2 - 0.27)

  box_rows <- bind_rows(
    card_bodies %>% mutate(fill = "white", colour = INK, linetype = "solid"),
    card_heads %>% mutate(fill = INK, colour = INK, linetype = "solid"),
    bind_cols(select(dn, xmin, xmax, ymin, ymax), select(node_style(dn$run), -text)),
    bind_cols(select(lv, xmin, xmax, ymin, ymax), select(node_style(lv$run), -text)),
    test_box %>% mutate(fill = "white", colour = INK, linetype = "solid"))
  node_text <- bind_rows(
    card_heads %>% transmute(x = (xmin + xmax) / 2, y = (ymin + ymax) / 2, label, colour = "white", face = "bold"),
    dn %>% transmute(x, y = (ymin + ymax) / 2, label, colour = node_style(run)$text, face = "plain"),
    lv %>% transmute(x, y = (ymin + ymax) / 2, label, colour = node_style(run)$text, face = "plain"),
    test_box %>% transmute(x = (xmin + xmax) / 2, y = (ymin + ymax) / 2, colour = INK, face = "plain",
                           label = sprintf("ADF unit root check, then bivariate Granger causality test in both directions (%d lags)", LAG_ORDER)))

  # Options listed in each filter card
  OPT_SIZE <- 2.15
  body_mid <- (card_bodies$ymin + card_bodies$ymax) / 2
  opt_text <- tibble(
    x = fam_x + FAM_W / 2, y = body_mid,
    label = c("Trade & finance  ·  Domestic periphery  ·  Taiwan\nMultilateral negotiations  ·  South China Sea\nGlobal health  ·  Russia",
              "Forward dating: data after 1 January\nof each year, 2002 to 2020\n "))
  struck <- "Backward dating"
  strike_y <- body_mid[2] - 0.13
  strike_w <- text_w(struck, OPT_SIZE)
  strike <- tibble(x = fam_x[["time"]] + FAM_W / 2, y = strike_y, label = struck)

  # Edges
  card_bottom <- card_bodies$ymin[1]
  edges <- bind_rows(
    bind_rows(lapply(names(FAMILIES), function(f) {
      d <- filter(dn, family == f)
      elbow(fam_x[[f]] + FAM_W / 2, card_bottom, d$x, d$ymax, d$run)
    })),
    bind_rows(lapply(seq_len(nrow(dn)), function(i) {
      l <- filter(lv, family == dn$family[i], data == dn$data[i])
      elbow(dn$x[i], dn$ymin[i], l$x, l$ymax, l$run)
    })),
    lv %>% filter(run) %>% transmute(x, y = ymin, xend = x, yend = test_box$ymax, run = TRUE))

  # Results band
  cells <- tibble(family = character(), data = character(), interval = character(), xmin = numeric(),
                  xmax = numeric(), ymin = numeric(), ymax = numeric(), outcome = character())
  cell_text <- tibble()
  if (with_results) {
    CELL_H <- 0.105; PITCH <- 0.125; CELL_W <- 0.36; WIN_OFFSET <- 0.36
    row_top <- tops[["result"]] - 0.36
    lab_size <- 2.05
    place <- function(r, x, width) {
      r %>% mutate(xmin = x - width / 2, xmax = x + width / 2,
                   ymax = row_top - (row_i - 1) * PITCH, ymin = ymax - CELL_H)
    }
    leaf_x <- function(f, d, i) filter(leaves, family == f, data == d, interval == i)$x
    # topic: the run leaf branches into two windows (all years, 2015 onward)
    topic_x <- leaf_x("topic", "full", "month")
    r <- filter(results, family == "topic") %>% mutate(row_i = match(row, unname(TOPIC_SHORT)))
    # (both columns sit left of the leaf, clear of the year labels of the time results)
    topic_cells <- bind_rows(place(filter(r, col == "All"), topic_x - 0.10 - 2 * WIN_OFFSET, CELL_W),
                             place(filter(r, col == "2015+"), topic_x - 0.10, CELL_W))
    time_cells <- bind_rows(lapply(seq_len(nrow(filter(leaves, family == "time"))), function(i) {
      l <- filter(leaves, family == "time")[i, ]
      filter(results, family == "time", data == l$data, interval == l$interval) %>%
        mutate(row_i = match(row, as.character(START_YEARS))) %>% place(l$x, CELL_W)
    }))
    cells <- bind_rows(topic_cells, time_cells)

    row_labels <- bind_rows(
      topic_cells %>% filter(col == "All") %>% transmute(x = xmin - 0.04, y = (ymin + ymax) / 2, label = row),
      time_cells %>% filter(data == "mfa_pres", interval == "week") %>%
        transmute(x = xmin - 0.04, y = (ymin + ymax) / 2, label = row)) %>% mutate(hjust = 1, size = lab_size)
    col_heads <- topic_cells %>% filter(row_i == 1) %>%
      transmute(x = (xmin + xmax) / 2, y = ymax + 0.07, label = WINDOW_LABELS[col], hjust = 0.5, size = 1.95)
    year_head <- time_cells %>% filter(row_i == 1, data == "mfa_pres", interval == "week") %>%
      transmute(x = xmin - 0.04, y = ymax + 0.07, label = "After", hjust = 1, size = 1.95)
    cell_text <- bind_rows(row_labels, col_heads, year_head)

    # connectors from the test box to each block of results
    blocks <- cells %>% group_by(family, data, interval, col) %>%
      summarise(x = (min(xmin) + max(xmax)) / 2, top = max(ymax), .groups = "drop") %>%
      mutate(top = top + ifelse(family == "time", 0.03, 0.14))
    time_blocks <- filter(blocks, family == "time")
    topic_blocks <- filter(blocks, family == "topic")
    edges <- bind_rows(edges,
                       time_blocks %>% transmute(x, y = test_box$ymin, xend = x, yend = top, run = TRUE),
                       elbow(topic_x, test_box$ymin, topic_blocks$x, topic_blocks$top, rep(TRUE, nrow(topic_blocks))))
  }

  # Legend: one row below the tree (Figure 12), or two columns in the empty lower left
  # of the results band (Figure 28)
  LEG_SIZE <- 2.2; KEY_H <- 0.12
  keys <- tibble(label = c("Run", "Not run"), kind = c("run", "off"))
  if (with_results) keys <- bind_rows(keys, tibble(label = unname(GRANGER_OUTCOMES), kind = "outcome"))
  keys$key_w <- ifelse(keys$kind == "outcome", 0.17, 0.30)
  leg_titles <- tibble(x = numeric(), y = numeric(), label = character())
  if (with_results) {
    step <- 0.17
    base <- tops[["result"]] - heights[["result"]] + 0.12
    keys <- keys %>% mutate(col = ifelse(kind == "outcome", 2, 1), k = ave(seq_along(col), col, FUN = seq_along),
                            xmin = ifelse(col == 1, X0 + 0.25, X0 + 1.45),
                            y = base + (4 - k) * step)   # both columns hang from the same top
    leg_titles <- keys %>% group_by(col) %>% summarise(x = first(xmin), y = max(y) + step) %>%
      mutate(label = c("Specification", "Significant Granger causality (p < 0.05)")[col]) %>% select(x, y, label)
  } else {
    widths <- keys$key_w + 0.05 + sapply(keys$label, text_w, size = LEG_SIZE) + ifelse(keys$kind == "off", 0.35, 0.16)
    keys <- keys %>% mutate(xmin = FIG_W / 2 - sum(widths) / 2 + c(0, cumsum(widths)[-length(widths)]),
                            y = 0.02 + 0.34 / 2)
  }
  keys <- keys %>% mutate(xmax = xmin + key_w, ymin = y - KEY_H / 2, ymax = y + KEY_H / 2,
                          outcome = ifelse(kind == "outcome", label, NA_character_))
  leg_boxes <- keys %>% filter(kind != "outcome") %>%
    mutate(fill = ifelse(kind == "run", INK, "white"), colour = ifelse(kind == "run", INK, OFF),
           linetype = ifelse(kind == "run", "solid", "22"))
  leg_cells <- keys %>% filter(kind == "outcome")

  # Outcome cells: rectangles, with "Both" split along the diagonal
  draw_cells <- bind_rows(cells %>% select(xmin, xmax, ymin, ymax, outcome),
                          leg_cells %>% select(xmin, xmax, ymin, ymax, outcome))
  both <- filter(draw_cells, outcome == "Both")
  both_tri <- tibble(x = numeric(), y = numeric(), fill = character(), id = character())
  if (nrow(both) > 0) both_tri <- bind_rows(lapply(seq_len(nrow(both)), function(i) {
    b <- both[i, ]
    bind_rows(tibble(x = c(b$xmin, b$xmax, b$xmin), y = c(b$ymin, b$ymin, b$ymax),
                     fill = OUTCOME_FILLS[["US as response"]]),
              tibble(x = c(b$xmax, b$xmax, b$xmin), y = c(b$ymin, b$ymax, b$ymax),
                     fill = OUTCOME_FILLS[["China as response"]])) %>% mutate(id = paste(i, rep(1:2, each = 3)))
  }))

  g <- ggplot() +
    geom_rect(data = bands, aes(xmin = 0, xmax = FIG_W, ymin = ymin, ymax = ymax), fill = BAND) +
    geom_segment(data = filter(edges, !run), aes(x, y, xend = xend, yend = yend),
                 colour = OFF, linewidth = 0.35, linetype = "22") +
    geom_segment(data = filter(edges, run), aes(x, y, xend = xend, yend = yend),
                 colour = INK, linewidth = 0.5, lineend = "square") +
    # band labels drawn over the connectors, on the band colour, so no line runs through them
    geom_label(data = bands, aes(X0, ymax - 0.05, label = label), hjust = 0, vjust = 1,
               family = FONT, fontface = "bold", size = 2.4, colour = "grey35", fill = BAND,
               linewidth = 0, label.padding = unit(0.6, "pt"), label.r = unit(0, "pt")) +
    geom_polygon(data = boxes_df(bind_rows(box_rows, leg_boxes)),
                 aes(x, y, group = id, fill = fill, colour = colour, linetype = linetype), linewidth = 0.4) +
    geom_text(data = node_text, aes(x, y, label = label, colour = colour, fontface = face),
              family = FONT, size = 2.4) +
    geom_text(data = opt_text, aes(x, y, label = label), family = FONT, size = OPT_SIZE,
              colour = "grey15", lineheight = 1.15) +
    geom_text(data = strike, aes(x, y, label = label), family = FONT, size = OPT_SIZE, colour = OFF) +
    annotate("segment", x = strike$x - strike_w / 2 - 0.02, xend = strike$x + strike_w / 2 + 0.02,
             y = strike_y - 0.008, yend = strike_y - 0.008, colour = OFF, linewidth = 0.35) +
    geom_rect(data = draw_cells, aes(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax,
                                     fill = OUTCOME_FILLS[outcome]), colour = NA) +
    geom_polygon(data = both_tri, aes(x, y, group = id, fill = fill), colour = NA) +
    geom_rect(data = draw_cells, aes(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax),
              fill = NA, colour = ifelse(draw_cells$outcome == "Neither", "grey65", "white"), linewidth = 0.25) +
    geom_text(data = keys, aes(xmax + 0.05, y, label = label), hjust = 0, family = FONT,
              size = LEG_SIZE, colour = "grey15") +
    geom_text(data = leg_titles, aes(x, y, label = label), hjust = 0, family = FONT, fontface = "bold",
              size = LEG_SIZE, colour = "grey15") +
    scale_fill_identity() + scale_colour_identity() + scale_linetype_identity() +
    coord_fixed(xlim = c(0, FIG_W), ylim = c(0, fig_h), expand = FALSE) +
    theme_void(base_family = FONT) +
    theme(plot.margin = ggplot2::margin(0, 0, 0, 0))
  if (nrow(cell_text) > 0) {
    g <- g + geom_text(data = cell_text, aes(x, y, label = label, hjust = hjust, size = size),
                       family = FONT, colour = "grey15") + scale_size_identity()
  }
  list(plot = g, height = fig_h)
}

fig12 <- build_tree(FALSE)
save_fig("12_granger_tree.pdf", fig12$plot, width = FIG_W, height = fig12$height)
fig28 <- build_tree(TRUE)
save_fig("28_granger_tree_findings.pdf", fig28$plot, width = FIG_W, height = fig28$height)

options(width = 120)
print(results %>% count(family, data, interval, col, outcome) %>% as.data.frame())
cat("Done: 12_28_granger_tree\n")
