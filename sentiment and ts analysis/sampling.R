library(readxl)
library(writexl)

peoplesdaily <- read_excel("~/PycharmProjects/thesis/PeoplesDailyUSA.xlsx")[,-1]
mofa <- read_excel("~/PycharmProjects/thesis/MFA_US.xlsx")[,-c(1:2)]



#taking samples for manual coding 

mofa_sample <- mofa[sample(nrow(mofa), 300),]
peoplesdaily_sample <- peoplesdaily[sample(nrow(peoplesdaily), 300),]
pres_sample <- pres[sample(nrow(pres), 300),]
congress_sample <- congress[sample(nrow(congress), 300),]

write_xlsx(mofa_sample, "mofa_sample.xlsx")
write_xlsx(peoplesdaily_sample, "peoplesdaily_sample.xlsx")
write_xlsx(pres_sample, "pres_sample.xlsx")
write_xlsx(congress_sample, "congress_sample.xlsx")


