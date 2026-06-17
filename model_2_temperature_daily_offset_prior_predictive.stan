data {
  int<lower=1> N;
  int<lower=1> J;
  vector[N] x_T;
  real<lower=0> temp_range;
  array[N] int<lower=1, upper=J> day_id;
}

generated quantities {
  real alpha;
  real beta_T;
  real sigma;
  real sigma_day;
  real nu;
  real beta_T_per_10C;

  vector[J] z_day_raw;
  vector[J] delta_day;

  vector[N] mu;
  vector[N] y_prior;
  vector[N] PR_prior;

  alpha = normal_rng(log(0.75), 0.3);
  beta_T_per_10C = normal_rng(-0.05, 0.5);
  beta_T = beta_T_per_10C * temp_range / 10;

  // Controlled prior predictive scales. This avoids rare absurd PR values.
  sigma = uniform_rng(0.005, 0.12);
  sigma_day = uniform_rng(0.000, 0.08);
  nu = uniform_rng(8, 50);

  for (j in 1:J) {
    z_day_raw[j] = normal_rng(0, 1);
  }

  delta_day = sigma_day * (z_day_raw - mean(z_day_raw));

  for (i in 1:N) {
    mu[i] = alpha + beta_T * x_T[i] + delta_day[day_id[i]];
    y_prior[i] = student_t_rng(nu, mu[i], sigma);
    PR_prior[i] = exp(y_prior[i]);
  }
}
