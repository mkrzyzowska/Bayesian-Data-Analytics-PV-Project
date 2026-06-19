data {
  int<lower=1> N;
  vector[N] y;                // log(PR)
  vector[N] x_T;              // normalized module temperature in [0, 1]
  real<lower=0> T_range_C;    // T_max - T_min in degC
}

parameters {
  real alpha;

  // Interpretable coefficient:
  // effect on log(PR) for +10 degC module temperature increase
  real beta_T_10C;

  real<lower=0.001, upper=1> sigma;
  real<lower=0, upper=45> nu_min5;
}

transformed parameters {
  real beta_T_norm;
  real<lower=5, upper=50> nu;
  vector[N] mu;

  // Convert +10 degC coefficient to coefficient for x_T in [0, 1]
  // If x_T changes from 0 to 1, temperature changes by T_range_C.
  beta_T_norm = beta_T_10C * T_range_C / 10.0;
  nu = 5 + nu_min5; // liczba stopni swobody dla rozkładu t-Studenta - mniejsza wartość oznacza grubsze ogony, większą odporność na obserwacje odstające

  mu = alpha + beta_T_norm * x_T;
}

model {
  // Baseline log(PR) at the lowest module temperature in the dataset.
  // Broad weakly informative prior.
  alpha ~ normal(log(0.8), 0.3);
  beta_T_10C ~ normal(-0.035, 0.05);
  sigma ~ exponential(10); // rozrzut log(PR) wokół wartości oczekiwanej, większa wartość oznacza większy rozrzut, musi być dodatnie
  nu_min5 ~ exponential(0.1);

  y ~ student_t(nu, mu, sigma);
}
generated quantities {
  vector[N] y_pred;
  vector[N] PR_pred;
  vector[N] log_lik;

  real effect_10C_pct;
  real effect_1C_pct;
  real effect_full_range_pct;

  effect_10C_pct = 100 * (exp(beta_T_10C) - 1);
  effect_1C_pct = 100 * (exp(beta_T_10C / 10.0) - 1);
  effect_full_range_pct = 100 * (exp(beta_T_norm) - 1);

  for (i in 1:N) {
    y_pred[i] = student_t_rng(nu, mu[i], sigma);
    PR_pred[i] = exp(y_pred[i]);

    log_lik[i] = student_t_lpdf(y[i] | nu, mu[i], sigma);
  }
}
