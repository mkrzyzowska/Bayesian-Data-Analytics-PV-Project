data {
  int<lower=1> N;
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
  alpha ~ normal(log(0.90), 0.12);
  beta_T ~ normal(0, 0.04);
  sigma ~ normal(0, 0.05);
  nu ~ normal(15, 10);
}

generated quantities {
  vector[N] y_prior;
  vector[N] PR_prior;

  for (i in 1:N) {
    y_prior[i] = student_t_rng(nu, mu[i], sigma);
    PR_prior[i] = exp(y_prior[i]);
  }
}