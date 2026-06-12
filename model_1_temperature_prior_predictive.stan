
data {
  int<lower=1> N;
  vector[N] x_T;
}

generated quantities {
  real alpha;
  real beta_T;
  real<lower=0> sigma;
  real<lower=2> nu;

  vector[N] mu;
  vector[N] y_prior;
  vector[N] PR_prior;

  alpha = normal_rng(log(0.85), 0.3); // zakłada że sprawność przy 25 stopniach wynosi średnio 50% z odchyleniem 20%
  beta_T = normal_rng(0, 0.08);
  sigma = exponential_rng(10);
  nu = 2 + exponential_rng(0.1);

  for (i in 1:N) {
    mu[i] = alpha + beta_T * x_T[i];
    y_prior[i] = student_t_rng(nu, mu[i], sigma);
    PR_prior[i] = exp(y_prior[i]);
  }
}
