data {
  int<lower=1> N;
  vector[N] x_T;              // normalized module temperature in [0, 1]
  real<lower=0> T_range_C;    // T_max - T_min in degC
}

generated quantities {
  real alpha;
  real beta_T_10C;
  real beta_T_norm;

  real sigma;
  real nu_min5;
  real nu;

  real effect_10C_pct;
  real effect_1C_pct;
  real effect_full_range_pct;

  vector[N] mu;
  vector[N] y_prior;
  vector[N] PR_prior;

  alpha = normal_rng(log(0.8), 0.3);

  beta_T_10C = normal_rng(-0.035, 0.05);

  // Convert to coefficient for x_T in [0, 1]
  beta_T_norm = beta_T_10C * T_range_C / 10.0;

  sigma = exponential_rng(10);
  while (sigma <= 0.001 || sigma >= 1) {
    sigma = exponential_rng(10);
  }

  nu_min5 = exponential_rng(0.1);
  while (nu_min5 <= 0 || nu_min5 >= 45) {
    nu_min5 = exponential_rng(0.1);
  }
  nu = 5 + nu_min5;

  for (i in 1:N) {
    mu[i] = alpha + beta_T_norm * x_T[i];

    y_prior[i] = student_t_rng(nu, mu[i], sigma);
    PR_prior[i] = exp(y_prior[i]);
  }
}
