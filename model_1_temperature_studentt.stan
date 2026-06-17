data {
  int<lower=1> N;
  vector[N] y;
  vector[N] x_T;
  real<lower=0> temp_range;
}

parameters {
  real alpha;
  real beta_T_per_10C;
  real<lower=0.001, upper=0.15> sigma;
  real<lower=5, upper=50> nu;
}

transformed parameters {
  real beta_T;
  vector[N] mu;

  beta_T = beta_T_per_10C * temp_range / 10;
  mu = alpha + beta_T * x_T;
}

model {
  alpha ~ normal(log(0.75), 0.3);
  beta_T_per_10C ~ normal(0, 0.5);
  sigma ~ normal(0, 0.05);
  nu ~ normal(15, 10);

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
