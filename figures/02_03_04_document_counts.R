# 02-04 — Thesis Figures 2, 3 and 4: how many documents enter the analysis, over time.
#
# Figure 2: US documents mentioning China, by archive. The archive labels follow the
#   title/subhead keyword rule in time_series_analysis.Rmd ("Pub. Papers",
#   "Compilation", "Cong. Rec." + chamber); documents matching none of them are
#   "CRS Reports & Others". This includes 104 documents from the Presidential Library
#   corpus that are CRS reports.
# Figure 3: Chinese documents mentioning the US, MFA press conferences and People's
#   Daily. The thesis also drew the documents that do not mention the US (gray bars,
#   from the full MFA and People's Daily corpora); those corpora are not in
#   honors-thesis-original-data, so the gray bars are dropped.
# Figure 4: composition of all four corpora that enter the country time series. Here
#   each document keeps the corpus it came from (the thesis reused the Figure 2
#   labels, which put those 104 CRS reports under Congress).
#
# Documents: those in the country series of time_series_analysis.Rmd (scored and
# dated; Congress limited to the 2,000-document draw), i.e. `in_series`.
# Bins: calendar quarters (the thesis used 100 equal-width histogram bins, about
# 2.5 months each).
#
# Input:  honors-thesis-original-data/sentiments/05_*_scored.csv, 00_corpora.csv (titles)
# Output: figures/output/02_us_doc_frequency.pdf, 03_china_doc_frequency.pdf,
#         04_data_composition.pdf

source(if (file.exists("figures/setup.R")) "figures/setup.R" else "setup.R")

quarter_start <- function(date) {
  as.Date(paste0(format(date, "%Y-"), sprintf("%02d", (as.integer(format(date, "%m")) - 1) %/% 3 * 3 + 1), "-01"))
}
docs <- read_documents() %>% filter(in_series) %>% mutate(quarter = quarter_start(date))

plot_counts <- function(d, fill_values) {
  ggplot(d, aes(quarter + 45, n, fill = group)) +   # bar centered in its quarter
    geom_col(width = 80, colour = NA) +
    scale_fill_manual(values = fill_values) +
    scale_x_years() +
    scale_y_continuous("Documents per quarter", expand = expansion(mult = c(0, 0.05))) +
    theme_paper() +
    theme(panel.grid.major.x = element_blank())
}

# ---- Figure 2: US documents by archive ----------------------------------------------------
ARCHIVE_COLORS <- c("President: Public Papers" = "#1F4E9A",
                    "President: Daily Compilation" = "#6A9BD8",
                    "Congressional Record: House" = "#7B2D8E",
                    "Congressional Record: Senate" = "#B95FD3",
                    "Congressional Record: Daily Digest" = "#D9822B",
                    "CRS Reports & Others" = "#8C8C8C")
titles <- read_corpora() %>% select(source, doc_id, title, subhead)
us <- docs %>% filter(country == "US") %>% left_join(titles, by = c("source", "doc_id")) %>%
  mutate(group = case_when(   # same order of checks as the nested ifelse() in the Rmd
    grepl("Pub. Papers", title) ~ "President: Public Papers",
    grepl("Compilation", title) | grepl("Compilation", subhead) ~ "President: Daily Compilation",
    grepl("Cong. Rec.", title) & grepl("House", subhead) ~ "Congressional Record: House",
    grepl("Cong. Rec.", title) & grepl("Senate", subhead) ~ "Congressional Record: Senate",
    grepl("Cong. Rec.", title) & grepl("Daily Digest", subhead) ~ "Congressional Record: Daily Digest",
    TRUE ~ "CRS Reports & Others"),
    group = factor(group, levels = names(ARCHIVE_COLORS)))

fig2 <- plot_counts(count(us, group, quarter), ARCHIVE_COLORS) +
  guides(fill = guide_legend(nrow = 2, byrow = TRUE))
save_fig("02_us_doc_frequency.pdf", fig2, height = 3.3)

# ---- Figures 3 and 4: by corpus -------------------------------------------------------------
quarterly <- docs %>% count(country, group = source_label, quarter)
fig3 <- plot_counts(filter(quarterly, country == "China"), SOURCE_COLORS)
fig4 <- plot_counts(quarterly, SOURCE_COLORS) + guides(fill = guide_legend(nrow = 1))

save_fig("03_china_doc_frequency.pdf", fig3, height = 3)
save_fig("04_data_composition.pdf", fig4, height = 3.2)

print(table(us$source, us$group))
print(docs %>% count(source_label, name = "documents"))
cat("Done: 02_03_04_document_counts\n")
