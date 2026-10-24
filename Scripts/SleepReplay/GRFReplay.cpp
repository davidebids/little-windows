// Research-only bridge to an externally supplied upstream GRF checkout.
// No third-party implementation or personal model is bundled with the app.
#include <algorithm>
#include <cmath>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <numeric>
#include <stdexcept>
#include <string>
#include <vector>
#include "commons/Data.h"
#include "forest/ForestOptions.h"
#include "forest/ForestTrainers.h"
#include "forest/ForestPredictors.h"
#include "Eigen/Dense"

int main(int argc, char** argv) {
  try {
    if (argc != 3) throw std::runtime_error("Expected input and output paths");
    std::ifstream in(argv[1]);
    size_t n, p, q;
    unsigned int trees, seed;
    int honest;
    std::string method;
    if (!(in >> n >> p >> q >> method >> trees >> seed >> honest) || n < 10 || p == 0 || q == 0 || trees < 2 || (honest != 0 && honest != 1))
      throw std::runtime_error("Invalid replay dimensions/options");
    if (method != "median" && method != "ll_standard" && method != "ll_residual")
      throw std::runtime_error("Unknown GRF method");
    std::vector<double> training(n * (p + 1)), queries(q * p);
    for (size_t r = 0; r < n; ++r) {
      for (size_t c = 0; c <= p; ++c) {
        double value;
        if (!(in >> value) || !std::isfinite(value)) throw std::runtime_error("Invalid training value");
        training[c * n + r] = value;
      }
    }
    for (size_t r = 0; r < q; ++r) {
      for (size_t c = 0; c < p; ++c) {
        double value;
        if (!(in >> value) || !std::isfinite(value)) throw std::runtime_error("Invalid query value");
        queries[c * q + r] = value;
      }
    }
    grf::Data train(training, n, p + 1), test(queries, q, p);
    train.set_outcome_index(p);
    std::vector<size_t> columns(p);
    std::iota(columns.begin(), columns.end(), 0);
    // Training defaults from the upstream R API; seed and threads are fixed.
    grf::ForestOptions options(trees, 2, .5, std::min(p, size_t(std::ceil(std::sqrt(p) + 20))),
      5, honest == 1, .5, true, .05, 0, 1, seed, false, {}, 0);
    std::vector<double> beta;
    if (method == "ll_residual") {
      Eigen::MatrixXd design(n, p + 1);
      Eigen::VectorXd y(n);
      for (size_t r = 0; r < n; ++r) {
        design(r, 0) = 1;
        y(r) = train.get_outcome(r);
        for (size_t c = 0; c < p; ++c) design(r, c + 1) = train.get(r, c);
      }
      Eigen::MatrixXd penalty = Eigen::MatrixXd::Identity(p + 1, p + 1);
      penalty(0, 0) = 0;
      Eigen::VectorXd fitted = (design.transpose() * design + .1 * penalty).ldlt().solve(design.transpose() * y);
      beta.assign(fitted.data(), fitted.data() + fitted.size());
    }
    auto trainer = method == "median" ? grf::quantile_trainer({.5}) :
      (method == "ll_residual" ? grf::ll_regression_trainer(.1, false, beta, size_t(std::floor(std::sqrt(n))), columns) :
       grf::regression_trainer());
    auto forest = trainer.train(train, options);
    std::vector<double> errors;
    double chosen = 0;
    std::vector<grf::Prediction> predictions;
    std::vector<grf::Prediction> base_predictions;
    if (method == "median") {
      auto predictor = grf::quantile_predictor(1, {.5});
      predictions = predictor.predict(forest, train, test, false);
    } else {
      // Match upstream's default local-linear penalty path and past OOB MSE
      // choice. Current/future query outcomes never enter this selection.
      std::vector<double> lambdas{0, .001, .01, .05, .1, .3, .5, .7, 1, 10};
      auto tuner = grf::ll_regression_predictor(1, lambdas, false, columns);
      auto oob = tuner.predict_oob(forest, train, false);
      double best = std::numeric_limits<double>::infinity();
      for (size_t k = 0; k < lambdas.size(); ++k) {
        double mse = 0;
        for (size_t r = 0; r < n; ++r) {
          const double point = oob[r].get_predictions().at(k);
          if (!std::isfinite(point)) { mse = std::numeric_limits<double>::infinity(); break; }
          mse += std::pow(point - train.get_outcome(r), 2) / n;
        }
        errors.push_back(mse);
        if (mse < best) { best = mse; chosen = lambdas[k]; }
      }
      if (!std::isfinite(best)) throw std::runtime_error("No finite OOB penalty score");
      auto predictor = grf::ll_regression_predictor(1, {chosen}, false, columns);
      predictions = predictor.predict(forest, train, test, false);
      if (method == "ll_standard") {
        auto base = grf::regression_predictor(1);
        base_predictions = base.predict(forest, train, test, false);
      }
    }
    std::ofstream out(argv[2]);
    out << std::setprecision(17) << "{\"predictions\":[";
    size_t nonfinite = 0;
    for (size_t r = 0; r < predictions.size(); ++r) {
      double point = predictions[r].get_predictions().at(0);
      if (r) out << ',';
      if (std::isfinite(point)) out << point; else { out << "null"; ++nonfinite; }
    }
    out << "],\"lambda\":" << chosen << ",\"oobMSE\":[";
    for (size_t k = 0; k < errors.size(); ++k) {
      if (k) out << ',';
      if (std::isfinite(errors[k])) out << errors[k]; else out << "null";
    }
    out << "],\"nonfiniteQueryCount\":" << nonfinite << ",\"basePredictions\":[";
    for (size_t r = 0; r < base_predictions.size(); ++r) {
      if (r) out << ',';
      double point = base_predictions[r].get_predictions().at(0);
      if (std::isfinite(point)) out << point; else out << "null";
    }
    out << "]}";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
