# Honors Thesis 

As tensions continue to rise between China and the US, much of the constructive dialogue has been crowded out by virulent insult-hurling from both sides. This paper seeks to explore the patterns of interaction between US and Chinese foreign policy discourse in the context of this trend. Specifically, it applies data-driven methodologies to investigate whether Chinese political discourse vis-à-vis the US is reactive to US rhetoric about China—and vice versa—between 2002 and 2022. 

## Data

Chinese Ministry of Foreign Affairs press conference transcripts compiled by Mochtak and Turcsanyi, as well as People’s Daily publications collected by Fisher et. al., are paired with an original dataset with over 35,000 US documents mentioning China from the Presidential Library and Congressional databases. 

All data used in this project can be found in the "data" folder, while the Python Selenium Chrome webdriver code is in the "data collection and processing" folder. 

## Methodology

These textual data are then quantified based on sentiments by a support vector machine model, a random forest model, as well as the Bing Liu lexicon. Sentiment analysis code will be in the "sentiment and ts analysis" folder. The computed sentiments, transformed into a time series dyad representing the discursive tones of the US and China, are subsequently fitted with a Granger causality model (relevant time series analysis R script can be found in the same folder)

## Results

This paper finds strong evidence for unidirectional Granger causality with US data as a response, indicating that China seems to initiate rhetorical reconciliation and hostilities more often, while the US plays a more reactive role in bilateral discourse. The Granger models also suggest that the correlation between negative sentiment discourse is much more significant than that between positive sentiment discourse. 



