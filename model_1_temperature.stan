
data {
  int<lower=1> N;
  vector[N] x_T;
  vector[N] y;
}

parameters {
  real alpha;
  real beta_T;
  real<lower=0> sigma;
  real<lower=0> nu_minus_two;
}

transformed parameters {
  real<lower=2> nu;
  vector[N] mu;

  nu = 2 + nu_minus_two;
  mu = alpha + beta_T * x_T;
}

model {
  alpha ~ normal(log(0.85), 0.3);
  beta_T ~ normal(0, 0.08);
  sigma ~ exponential(10);
  nu_minus_two ~ exponential(0.1);

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
