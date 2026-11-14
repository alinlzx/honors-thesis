# 29 — Thesis Figure 29: significant events along the four sentiment series.
#
# Curves: as the last Data Viz chunk of "sentiment analysis & EDA.Rmd" (the same data
# as Figure 9): documents grouped into 7-day weeks counted from 2000-01-01, the weekly
# mean hybrid score per corpus, and a LOESS curve (span 0.08) through the weekly
# means. Every dated scored document is used (Congress: congress_week, not only the
# 2,000-document draw). The thesis drew geom_smooth()'s default 80-point grid, hence
# its jagged look; here the curves are evaluated on 400 points.
#
# Annotations (drawn by hand outside R in the thesis, rebuilt here):
#   - bands above the plot: US administrations and Chinese leaders (CCP general
#     secretaries), from Bush and Hu as in the thesis;
#   - dotted lines at the thesis's seven events, at the event's date;
#   - gray shading from the Section 301 memorandum (22 March 2018) to the end of
#     the data: the US-China trade war.
# Not added: per-document dots. On one panel with four corpora they would need the
# +/-2 axis of Figure 9 and would flatten the curves the events are read against;
# Figure 9 shows the same documents. Set SHOW_DOTS <- TRUE to draw them anyway.
#
# Input:  honors-thesis-original-data/sentiments/05_*_scored.csv (score: SCORE_VERSION)
# Output: figures/output/29_event_map.pdf

source(if (file.exists("figures/setup.R")) "figures/setup.R" else "setup.R")

SHOW_DOTS <- FALSE

EVENTS <- tribble(
  ~date,                     ~label,
  as.Date("2005-03-20"),     "Rice visits Beijing",
  as.Date("2011-01-19"),     "Hu state visit to US",
  as.Date("2012-11-15"),     "Xi takes power",
  as.Date("2014-11-10"),     "APEC Beijing; AIIB",
  as.Date("2016-07-12"),     "South China Sea ruling",
  as.Date("2017-11-08"),     "Trump visits Beijing",
  as.Date("2021-01-20"),     "Biden inauguration"
)
TRADE_WAR_START <- as.Date("2018-03-22")

docs <- read_documents() %>% filter(dated)
data_end <- max(docs$date)
LEADERS <- tribble(
  ~row,    ~start,                 ~end,                   ~label,           ~fill,     ~text,
  "US",    as.Date("2001-01-20"),  as.Date("2009-01-20"),  "George W. Bush", "#C9D6EE", "black",
  "US",    as.Date("2009-01-20"),  as.Date("2017-01-20"),  "Barack Obama",   "#93AEDD", "black",
  "US",    as.Date("2017-01-20"),  as.Date("2021-01-20"),  "Donald Trump",   "#4F78C0", "white",
  "US",    as.Date("2021-01-20"),  data_end,               "Joe Biden",      "#1F3F80", "white",
  "China", as.Date("2002-11-15"),  as.Date("2012-11-15"),  "Hu Jintao",      "#F2C4C4", "black",
  "China", as.Date("2012-11-15"),  data_end,               "Xi Jinping",     "#C8323C", "white"
)
ROW_LABELS <- c(US = "US", China = "China")

curves <- docs %>% group_by(source_label) %>%
  group_modify(~ loess_curve(group_week(.x), "week", "mean_sentiment", span = 0.08)) %>% ungroup()

# Vertical layout, in data units: the panel spans the curves, with empty space below
# them for the event labels; the leader bands sit above it, in the plot margin
# (clip = "off").
ylim <- if (SHOW_DOTS) SENTI_YLIM else range(curves$fit) + c(-0.33, 0.08) * diff(range(curves$fit))
h <- diff(ylim)
band_h <- 0.075 * h
gap <- 0.015 * h
row_bottom <- c(China = ylim[2] + 2 * gap, US = ylim[2] + 3 * gap + band_h)
bands <- LEADERS %>% mutate(ymin = row_bottom[row], ymax = ymin + band_h, mid = start + (end - start) / 2)
row_text <- tibble(row = names(ROW_LABELS), label = ROW_LABELS, y = row_bottom[names(ROW_LABELS)] + band_h / 2)

fig29 <- ggplot() +
  annotate("rect", xmin = TRADE_WAR_START, xmax = data_end, ymin = -Inf, ymax = Inf, fill = "grey90") +
  annotate("text", x = TRADE_WAR_START + 40, y = ylim[2] - 0.03 * h, label = "Trade war",
           hjust = 0, vjust = 1, family = "serif", size = 2.6, colour = "grey30") +
  geom_hline(yintercept = 0, colour = "grey70", linewidth = 0.3) +
  geom_vline(data = EVENTS, aes(xintercept = date), linetype = "dotted", linewidth = 0.35, colour = "grey25") +
  geom_text(data = EVENTS, aes(date, ylim[1] + 0.02 * h, label = label), angle = 90, hjust = 0,
            vjust = -0.45, family = "serif", size = 2.3, colour = "grey20") +
  { if (SHOW_DOTS) doc_dots(docs, colour = source_label) } +
  geom_line(data = curves, aes(date, fit, colour = source_label), linewidth = 0.6) +
  geom_rect(data = bands, aes(xmin = start, xmax = end, ymin = ymin, ymax = ymax), fill = bands$fill,
            colour = "white", linewidth = 0.4) +
  geom_text(data = bands, aes(mid, ymin + band_h / 2, label = label), colour = bands$text,
            family = "serif", size = 2.3, fontface = "bold") +
  geom_text(data = row_text, aes(as.Date("2000-12-20"), y, label = label), hjust = 1,
            family = "serif", size = 2.2, colour = "grey30") +
  scale_colour_manual(values = SOURCE_COLORS) +
  scale_x_years() +
  scale_y_continuous("Hybrid sentiment score", breaks = seq(-2, 2, 0.5)) +
  coord_cartesian(ylim = ylim, clip = "off") +
  guides(colour = guide_legend(nrow = 1, override.aes = list(linewidth = 0.9))) +
  theme_paper() +
  theme(plot.margin = ggplot2::margin(t = 40, r = 6, b = 4, l = 4))
save_fig("29_event_map.pdf", fig29, height = 4.8)

cat(sprintf("Curve range: %.2f to %.2f\n", min(curves$fit), max(curves$fit)))
cat("Done: 29_event_map\n")
