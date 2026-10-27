# Value-at-Risk and Expected Shortfall for a single stock
# Daily data from Yahoo Finance, Jan 2000 to Dec 2025 (default: JP Morgan, JPM)
#
# Methods: normal distribution, historical simulation, Student-t,
# 10-day simulations, GARCH(1,1) with t errors, and a rolling 1-day VaR for 2025.
# Based on the Duke "Financial Risk Management with R" course (Coursera).
#
# Packages needed:
# install.packages(c("quantmod", "moments", "metRology", "rugarch"))
#
# Plots are saved in the plots folder, tables in the results folder.

library(quantmod)
library(moments)
library(MASS)
library(metRology)
library(rugarch)

dir.create("plots", showWarnings = FALSE)
dir.create("results", showWarnings = FALSE)

ticker <- "JPM"   # change to any Yahoo ticker, e.g. "BRK-B", "AAPL", "^GSPC"
alpha <- 0.05     # 5% tail = 95% VaR, used for every method below


#### 1. Data ####

# getSymbols doesn't include the "to" date, so 2026-01-01 gets data up to 31 Dec 2025
data <- getSymbols(ticker, src = "yahoo", from = "1999-12-31", to = "2026-01-01",
                   auto.assign = FALSE)

# adjusted close, so splits and dividends are taken into account
data <- Ad(data)
data <- na.omit(data)
names(data) <- c("price")

head(data, 3)
tail(data, 3)

# daily log returns (first one is NA so remove it) and simple returns
logret <- diff(log(data))[-1]
ret <- exp(logret) - 1

head(logret, 3)
head(ret, 3)

# plain vector version, sample() and jarque.test() need this
rvec <- as.vector(logret)

# weekly, monthly, quarterly and yearly returns
logret.w <- apply.weekly(logret, sum)
logret.m <- apply.monthly(logret, sum)
logret.q <- apply.quarterly(logret, sum)
logret.y <- apply.yearly(logret, sum)

ret.w <- exp(logret.w) - 1
ret.m <- exp(logret.m) - 1
ret.q <- exp(logret.q) - 1
ret.y <- exp(logret.y) - 1

head(ret.w, 3)
head(ret.m, 3)
head(ret.q, 3)
tail(ret.y, 3)

# crisis periods to mark on the charts
crises <- data.frame(
  name = c("Dot-com crash", "Financial crisis", "London Whale", "COVID crash",
           "Regional bank failures"),
  start = as.Date(c("2000-03-10", "2007-10-09", "2012-04-06", "2020-02-19", "2023-03-08")),
  end = as.Date(c("2002-10-09", "2009-03-09", "2012-07-13", "2020-03-23", "2023-05-01"))
)
# London Whale = JP Morgan's own $6bn trading loss in 2012, partly hidden by a change
# to its VaR model. JPM also bought First Republic in the 2023 bank failures.
if (ticker != "JPM") crises <- crises[crises$name != "London Whale", ]

# draws the crisis periods as shaded areas on the current plot
shade.crises <- function() {
  y <- par("usr")[3:4]
  if (par("ylog")) y <- 10^y
  rect(crises$start, y[1], crises$end, y[2], col = rgb(1, 0, 0, 0.15), border = NA)
  text(crises$start, y[2], crises$name, pos = 1, cex = 0.7, col = "darkred")
}

# price on a log scale (equal % moves look the same size) and daily returns
png("plots/1_price_returns.png", width = 900, height = 700)
par(mfrow = c(2, 1))
plot(as.zoo(data), log = "y", main = paste(ticker, "adjusted close (log scale)"),
     xlab = "", ylab = "Price")
shade.crises()
plot(as.zoo(logret), main = paste(ticker, "daily log returns"), xlab = "", ylab = "Log return")
shade.crises()
par(mfrow = c(1, 1))
dev.off()

# yearly returns
png("plots/2_yearly_returns.png", width = 900, height = 500)
barplot(as.numeric(ret.y) * 100, names.arg = format(index(ret.y), "%Y"),
        col = ifelse(ret.y > 0, "darkgreen", "red"), las = 2,
        main = paste(ticker, "yearly returns"), ylab = "Return (%)")
dev.off()


#### 2. VaR and ES with a normal distribution ####

mu <- mean(rvec)
sig <- sd(rvec)
mu
sig

# using the formula
VaR.norm <- qnorm(alpha, mu, sig)
ES.norm <- mu - sig * dnorm(qnorm(alpha, 0, 1), 0, 1) / alpha
VaR.norm
ES.norm

# what that means for a $1000 position
round(1000 * (exp(VaR.norm) - 1), 1)
round(1000 * (exp(ES.norm) - 1), 1)

# same thing by simulating 100,000 normal returns, as a check
set.seed(123789)
rvec1 <- rnorm(100000, mu, sig)
VaR1 <- quantile(rvec1, alpha)
ES1 <- mean(rvec1[rvec1 < VaR1])
round(VaR1, 6)
round(ES1, 6)


#### 3. Historical simulation ####

# sample 100,000 returns from the actual past returns, with replacement
set.seed(123789)
rvec2 <- sample(rvec, 100000, replace = TRUE)
VaR2 <- quantile(rvec2, alpha)
ES2 <- mean(rvec2[rvec2 < VaR2])
round(VaR2, 6)
round(ES2, 6)


#### 4. Are the returns normal? ####

# normal distribution has skewness 0 and kurtosis 3
round(skewness(rvec), 2)
round(kurtosis(rvec), 2)

# Jarque-Bera test, small p-value = not normal
jarque.test(rvec)

# returns measured in standard deviations from the mean
z.ret <- (rvec - mu) / sig


#### 5. Student-t distribution ####

# fit a t distribution (fat tails) to the returns
t.fit <- fitdistr(rvec, "t")
m <- t.fit$estimate[1]
s <- t.fit$estimate[2]
df <- t.fit$estimate[3]
round(t.fit$estimate, 6)

# a low df means much fatter tails than the normal
set.seed(123789)
rsim <- rt.scaled(100000, mean = m, sd = s, df = df)
VaR3 <- quantile(rsim, alpha)
ES3 <- mean(rsim[rsim < VaR3])
round(VaR3, 6)
round(ES3, 6)

# histogram with the normal and t curves, plus QQ plot
png("plots/3_distribution.png", width = 1100, height = 500)
par(mfrow = c(1, 2))
hist(rvec, breaks = 150, freq = FALSE, xlim = c(-6 * sig, 6 * sig),
     main = "Daily returns vs normal and t", xlab = "Log return", col = "grey")
curve(dnorm(x, mu, sig), add = TRUE, col = "red", lwd = 2)
curve(dt.scaled(x, df = df, mean = m, sd = s), add = TRUE, col = "blue", lwd = 2)
legend("topright", c("Normal", "Student-t"), col = c("red", "blue"), lwd = 2)
qqnorm(rvec, main = "Normal QQ plot")
qqline(rvec, col = "red")
par(mfrow = c(1, 1))
dev.off()

# zoom into the left tail: the data has more big losses than the normal predicts
png("plots/4_left_tail.png", width = 900, height = 500)
plot(density(rvec), xlim = c(min(rvec), -1.5 * sig), ylim = c(0, dnorm(2.2) / sig),
     main = "Left tail: actual returns vs normal", xlab = "Log return", lwd = 2)
curve(dnorm(x, mu, sig), add = TRUE, col = "red", lwd = 2)
abline(v = VaR.norm, lty = 2, col = "red", lwd = 2)
legend("topleft", c("Actual (density)", "Normal", "Normal 95% VaR"),
       col = c("black", "red", "red"), lty = c(1, 1, 2), lwd = 2)
dev.off()


#### 6. 10-day VaR and ES ####

# Method 1: add up ten 1-day returns from the fitted t distribution
set.seed(123789)
rsim1 <- rep(0, 100000)
for (i in 1:10) {
  rsim1 <- rsim1 + rt.scaled(100000, mean = m, sd = s, df = df)
}
VaR10.t <- quantile(rsim1, alpha)
ES10.t <- mean(rsim1[rsim1 < VaR10.t])
round(VaR10.t, 6)
round(ES10.t, 6)

# Method 2: add up ten 1-day returns sampled from past returns
set.seed(123789)
rsim2 <- rep(0, 100000)
for (i in 1:10) {
  rsim2 <- rsim2 + sample(rvec, 100000, replace = TRUE)
}
VaR10.hist <- quantile(rsim2, alpha)
ES10.hist <- mean(rsim2[rsim2 < VaR10.hist])
round(VaR10.hist, 6)
round(ES10.hist, 6)

# Method 3: take 10 consecutive days from past returns
# (keeps any clustering of good/bad days that method 2 loses)
set.seed(123789)
rsim3 <- rep(0, 100000)
posn <- seq(from = 1, to = length(rvec) - 9, by = 1)
rpos <- sample(posn, 100000, replace = TRUE)
for (i in 1:10) {
  rsim3 <- rsim3 + rvec[rpos]
  rpos <- rpos + 1
}
VaR10.block <- quantile(rsim3, alpha)
ES10.block <- mean(rsim3[rsim3 < VaR10.block])
round(VaR10.block, 6)
round(ES10.block, 6)


#### 7. Serial correlation and volatility clustering ####

# returns: little autocorrelation (prices are hard to predict)
# absolute returns: strong autocorrelation = volatility clustering
# shuffled absolute returns: the pattern disappears, so the order of days matters
set.seed(123789)
abs.shuffled <- sample(abs(rvec))

png("plots/5_acf.png", width = 1400, height = 450)
par(mfrow = c(1, 3))
acf(rvec, main = "ACF of log returns")
acf(abs(rvec), main = "ACF of |log returns|")
acf(abs.shuffled, main = "ACF of |log returns|, shuffled")
par(mfrow = c(1, 1))
dev.off()


#### 8. GARCH(1,1) with t errors ####

uspec <- ugarchspec(variance.model = list(model = "sGARCH", garchOrder = c(1, 1)),
                    mean.model = list(armaOrder = c(0, 0), include.mean = TRUE),
                    distribution.model = "std")

fit.garch <- ugarchfit(spec = uspec, data = logret, solver = "hybrid")
round(fit.garch@fit$coef, 6)

# standardised residuals z = return / GARCH volatility
z <- fit.garch@fit$z

save1 <- cbind(logret = rvec, s = fit.garch@fit$sigma, z = z)
head(save1)

# check the model: if GARCH works, z should have mean 0, sd 1 and no clustering left
# kurtosis of a t distribution with nu degrees of freedom is 3 + 6 / (nu - 4)
nu <- fit.garch@fit$coef["shape"]

garch.check <- data.frame(
  measure = c("Mean", "Standard deviation", "Skewness", "Kurtosis",
              "Autocorrelation (lag 1)", "Autocorrelation of absolute value (lag 1)"),
  expected.if.model.works = c(0, 1, 0, ifelse(nu > 4, 3 + 6 / (nu - 4), Inf), 0, 0),
  returns.before.GARCH = c(mean(z.ret), sd(z.ret), skewness(z.ret), kurtosis(z.ret),
                           acf(z.ret, plot = FALSE)$acf[2], acf(abs(z.ret), plot = FALSE)$acf[2]),
  z.after.GARCH = c(mean(z), sd(z), skewness(z), kurtosis(z),
                    acf(z, plot = FALSE)$acf[2], acf(abs(z), plot = FALSE)$acf[2])
)
garch.check[, 2:4] <- round(garch.check[, 2:4], 3)
garch.check

jarque.test(z)

png("plots/6_garch_residuals_acf.png", width = 1100, height = 450)
par(mfrow = c(1, 2))
acf(z, main = "ACF of z (GARCH residuals)")
acf(abs(z), main = "ACF of |z|, clustering removed?")
par(mfrow = c(1, 1))
dev.off()

# GARCH volatility over time (annualised): spikes in 2008, 2020 etc.
garch.vol <- xts(fit.garch@fit$sigma * sqrt(252), order.by = index(logret))

png("plots/7_garch_volatility.png", width = 900, height = 500)
plot(as.zoo(garch.vol), col = "blue", main = paste(ticker, "GARCH(1,1) volatility, annualised"),
     xlab = "", ylab = "Volatility")
shade.crises()
dev.off()

# what happened in each crisis: worst day, peak volatility, and how often the
# normal 95% VaR was broken (about 5% of days if the normal model was right)
in.crisis <- function(i) index(logret) >= crises$start[i] & index(logret) <= crises$end[i]

crisis.table <- data.frame(
  crisis = crises$name,
  from = crises$start,
  to = crises$end,
  worst.day.pct = sapply(1:nrow(crises), function(i) round(100 * min(ret[in.crisis(i)]), 1)),
  peak.volatility.pct = sapply(1:nrow(crises), function(i) round(100 * max(garch.vol[in.crisis(i)]), 1)),
  days.worse.than.normal.VaR.pct = sapply(1:nrow(crises), function(i)
    round(100 * mean(rvec[in.crisis(i)] < VaR.norm), 1))
)
crisis.table

write.csv(crisis.table, "results/crisis_table.csv", row.names = FALSE)

# compare with the VIX (implied volatility from S&P 500 options)
vix <- getSymbols("^VIX", src = "yahoo", from = "1999-12-31", to = "2026-01-01",
                  auto.assign = FALSE)
vix <- Cl(vix)

vol.vix <- na.omit(merge(garch.vol * 100, vix))   # both in % per year
names(vol.vix) <- c("garch", "vix")
cor(as.numeric(vol.vix$garch), as.numeric(vol.vix$vix))

png("plots/8_garch_vs_vix.png", width = 650, height = 600)
plot(log(as.numeric(vol.vix$vix)), log(as.numeric(vol.vix$garch)), pch = 20, cex = 0.4,
     main = paste(ticker, "GARCH volatility vs VIX"), xlab = "log(VIX)", ylab = "log(GARCH volatility)")
abline(0, 1, col = "red", lwd = 2)
dev.off()

# simulate tomorrow's return 100,000 times from the fitted model
set.seed(123789)
boot.garch <- ugarchboot(fit.garch, method = "Partial", sampling = "raw",
                         n.ahead = 1, n.bootpred = 100000, solver = "solnp")
rsim.garch <- as.vector(boot.garch@fseries)
VaR.garch <- quantile(rsim.garch, alpha)
ES.garch <- mean(rsim.garch[rsim.garch < VaR.garch])
round(VaR.garch, 6)
round(ES.garch, 6)


#### 9. Rolling 1-day VaR during 2025 ####

# for each day of 2025, re-estimate GARCH with all data up to the day before
# and forecast the next day's 95% VaR (this takes a few minutes)
n.2025 <- sum(index(logret) >= as.Date("2025-01-01"))

roll <- ugarchroll(uspec, data = logret, n.ahead = 1, forecast.length = n.2025,
                   refit.every = 1, refit.window = "recursive",
                   calculate.VaR = TRUE, VaR.alpha = alpha, solver = "hybrid")

VaR.roll <- roll@forecast$VaR[, 1]
actual.2025 <- roll@forecast$VaR[, 2]
dates.2025 <- as.Date(rownames(roll@forecast$VaR))

# % of days in 2025 that were worse than VaR, should be close to 5%
breach <- actual.2025 < VaR.roll
round(100 * mean(breach), 1)

# Kupiec test (right number of breaches) and Christoffersen test (breaches not clustered)
# p-value above 0.05 = the model is fine
VaRTest(alpha, actual.2025, VaR.roll)

png("plots/9_rolling_var_2025.png", width = 1000, height = 550)
plot(dates.2025, actual.2025, type = "h", col = "blue",
     ylim = range(c(actual.2025, VaR.roll)),
     main = paste0(ticker, " 1-day 95% VaR during 2025 (", round(100 * mean(breach), 1),
                   "% of days worse than VaR)"),
     xlab = "", ylab = "Log return")
lines(dates.2025, VaR.roll, col = "red", lwd = 2)
points(dates.2025[breach], actual.2025[breach], pch = 19, col = "red", cex = 0.8)
legend("bottomleft", c("Actual log return", "1-day 95% VaR", "Worse than VaR"),
       col = c("blue", "red", "red"), lty = c(1, 1, NA), pch = c(NA, NA, 19), lwd = 2)
dev.off()


#### 10. Comparing the simulations ####

# 10-day normal (formula) as the baseline for the 10-day simulations
VaR10.norm <- qnorm(alpha, 10 * mu, sqrt(10) * sig)
ES10.norm <- 10 * mu - sqrt(10) * sig * dnorm(qnorm(alpha, 0, 1), 0, 1) / alpha

# loss on a $1000 position, as a positive number
loss <- function(x) round(-1000 * (exp(as.numeric(x)) - 1), 2)

comparison <- data.frame(
  horizon = c(rep("1 day", 5), rep("10 days", 4)),
  method = c("Normal (formula)", "Normal (simulation)", "Historical simulation",
             "Student-t simulation", "GARCH(1,1)-t simulation",
             "Normal (formula)", "Student-t simulation",
             "Historical (10 random days)", "Historical (10 consecutive days)"),
  VaR.loss = loss(c(VaR.norm, VaR1, VaR2, VaR3, VaR.garch,
                    VaR10.norm, VaR10.t, VaR10.hist, VaR10.block)),
  ES.loss = loss(c(ES.norm, ES1, ES2, ES3, ES.garch,
                   ES10.norm, ES10.t, ES10.hist, ES10.block))
)

# ES / VaR = how much worse the average bad day is than the VaR line
# about 1.25 for a normal distribution, higher means fatter tails
comparison$ES.VaR.ratio <- round(comparison$ES.loss / comparison$VaR.loss, 2)

# difference from the normal formula with the same horizon
# (GARCH also depends on how volatile the market was at the end of 2025)
base.VaR <- ifelse(comparison$horizon == "1 day", comparison$VaR.loss[1], comparison$VaR.loss[6])
base.ES <- ifelse(comparison$horizon == "1 day", comparison$ES.loss[1], comparison$ES.loss[6])
comparison$VaR.vs.normal <- paste0(round(100 * (comparison$VaR.loss / base.VaR - 1)), "%")
comparison$ES.vs.normal <- paste0(round(100 * (comparison$ES.loss / base.ES - 1)), "%")
comparison

write.csv(comparison, "results/var_es_comparison.csv", row.names = FALSE)


#### 11. Normal distribution vs our data ####

# what a normal distribution would give for each feature, next to what the stock actually has
n <- length(rvec)

normal.vs.data <- data.frame(
  feature = c("Skewness",
              "Kurtosis",
              "Student-t degrees of freedom",
              "Days within 1 sd (%)",
              "Days within 2 sd (%)",
              "Days with loss beyond 3 sd",
              "Days with gain beyond 3 sd",
              "Days with loss beyond 4 sd",
              "Worst day (in sd)",
              "ES / VaR at 95%",
              "Autocorrelation of |returns| (lag 1)"),
  normal = c(0,
             3,
             Inf,
             100 * (pnorm(1) - pnorm(-1)),
             100 * (pnorm(2) - pnorm(-2)),
             n * pnorm(-3),
             n * pnorm(-3),
             n * pnorm(-4),
             qnorm(1 / n),                       # roughly the expected worst day in n days
             comparison$ES.VaR.ratio[1],         # normal formula
             0),
  stock = c(skewness(rvec),
            kurtosis(rvec),
            df,
            100 * mean(abs(z.ret) < 1),
            100 * mean(abs(z.ret) < 2),
            sum(z.ret < -3),
            sum(z.ret > 3),
            sum(z.ret < -4),
            min(z.ret),
            comparison$ES.VaR.ratio[3],          # historical simulation
            acf(abs(rvec), plot = FALSE)$acf[2]),
  meaning = c("0 = symmetric. Positive = big rises more common than big falls, negative = the opposite",
              "Above 3 = fatter tails and a sharper peak than normal",
              "Low df = fat tails. A normal is a t with infinite df",
              "Above 68% = most days are calmer than a normal predicts",
              "Close to 95% even with fat tails, the difference is further out",
              "More than expected = big crashes happen more often than normal predicts",
              "Same for big jumps up",
              "Very extreme days, almost impossible under a normal",
              "How extreme the single worst day was",
              "Above 1.25 = losses beyond VaR are bigger than normal predicts",
              "Above 0 = volatile days follow volatile days (clustering)")
)
normal.vs.data$normal <- round(normal.vs.data$normal, 2)
normal.vs.data$stock <- round(normal.vs.data$stock, 2)
normal.vs.data

write.csv(normal.vs.data, "results/normal_vs_data.csv", row.names = FALSE)
write.csv(garch.check, "results/garch_check.csv", row.names = FALSE)
