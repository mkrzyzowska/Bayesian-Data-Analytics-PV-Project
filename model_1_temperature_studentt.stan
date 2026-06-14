data {
  int<lower=1> N;
  vector[N] y;
  vector[N] x_T;
}

parameters {
  real alpha;
  real beta_T;
  real<lower=0.001, upper=0.15> sigma;
  real<lower=5, upper=50> nu;
}

transformed parameters {
  vector[N] mu;
  mu = alpha + beta_T * x_T;
}

model {
  alpha ~ normal(log(0.5), 0.3);
  beta_T ~ normal(0, 0.04);
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