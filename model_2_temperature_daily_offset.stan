data {
  int<lower=1> N;
  int<lower=1> J;
  vector[N] y;
  vector[N] x_T;
  array[N] int<lower=1, upper=J> day_id;
}

parameters {
  real alpha;
  real beta_T;
  real<lower=0.001, upper=0.15> sigma;
  real<lower=0.000, upper=0.10> sigma_day;
  real<lower=5, upper=50> nu;
  vector[J] z_day_raw;
}

transformed parameters {
  vector[J] delta_day;
  vector[N] mu;

  delta_day = sigma_day * (z_day_raw - mean(z_day_raw));

  for (i in 1:N) {
    mu[i] = alpha + beta_T * x_T[i] + delta_day[day_id[i]];
  }
}

model {
  alpha ~ normal(log(0.90), 0.12);
  beta_T ~ normal(0, 0.04);
  sigma ~ normal(0, 0.05);
  sigma_day ~ normal(0, 0.03);
  nu ~ normal(15, 10);
  z_day_raw ~ normal(0, 1);

  y ~ student_t(nu, mu, sigma);
}

generated quantities {
  vector[N] y_pred;
  vector[N] PR_pred;
  vector[N] log_lik;

  for (i in 1:N) {
    y_pred[i] = student_t_rng(nu, mu[i], sigma);
    PR_pred[i] = exp(y_pred[i]);
    log_lik[i] = student_t_lpdf(y[i] | nu, mu[i], sigma);
  }
}