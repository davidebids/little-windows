// Research-only reduced pressure model. No app target membership.
// Exponential awake accumulation/sleep decay with a bounded daily threshold.
// The observation rule, threshold clipping, and continuous fit are adaptations;
// they are not the full neuronal model or a physiological measurement.
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <vector>

struct PressureContext {
    std::vector<double> starts, ends, sine, cosine;
    std::vector<int32_t> indices;
};

extern "C" void* pressure_create(const double* starts, const double* ends, int ns,
                                const int32_t* indices, const double* clocks, int nq) {
    if (ns <= 0 || nq <= 0) return nullptr;
    auto* c = new PressureContext;
    c->starts.assign(starts, starts + ns); c->ends.assign(ends, ends + ns);
    c->indices.assign(indices, indices + nq);
    c->sine.resize(nq * 481); c->cosine.resize(nq * 481);
    const double rate = 2 * std::acos(-1.) / 1440;
    for (int i = 0; i < ns; ++i) {
        if (!std::isfinite(starts[i]) || !std::isfinite(ends[i]) || ends[i] <= starts[i] ||
            (i && starts[i] < starts[i-1])) { delete c; return nullptr; }
    }
    for (int i = 0; i < nq; ++i) {
        if (indices[i] < 0 || indices[i] >= ns || !std::isfinite(clocks[i])) { delete c; return nullptr; }
        for (int t = 0; t <= 480; ++t) {
            c->sine[i * 481 + t] = std::sin(rate * (clocks[i] + t));
            c->cosine[i * 481 + t] = std::cos(rate * (clocks[i] + t));
        }
    }
    return c;
}

extern "C" void pressure_destroy(void* ptr) { delete static_cast<PressureContext*>(ptr); }

extern "C" double pressure_evaluate(void* ptr, const int32_t* positions, int n,
    const double* targets, const double* weights, const double* p, double penalty,
    double* predictions, double* wakeStates) {
    auto* c = static_cast<PressureContext*>(ptr);
    if (!c || n <= 0) return NAN;
    for (int j = 0; j < 5; ++j) if (!std::isfinite(p[j])) return NAN;
    const double awake = std::exp(p[0]), asleep = std::exp(p[1]);
    if (awake <= 0 || asleep <= 0 || !std::isfinite(awake + asleep)) return NAN;
    int last = 0;
    for (int j = 0; j < n; ++j) {
        if (positions[j] < 0 || positions[j] >= static_cast<int>(c->indices.size())) return NAN;
        last = std::max(last, c->indices[positions[j]]);
    }
    // Integrate only the raw prefix needed by these query positions. Union
    // overlapping completed intervals, so they cannot double count pressure.
    std::vector<double> states(last + 1);
    double state = .5, cursor = c->starts[0];
    for (int j = 0; j <= last; ++j) {
        const double a = c->starts[j], b = c->ends[j];
        if (a > cursor) state = 1 - (1-state) * std::exp(-(a-cursor)/(awake*60));
        state *= std::exp(-std::max(0., b-std::max(a,cursor))/(asleep*60));
        cursor = std::max(cursor,b); states[j] = state;
    }
    double loss = 0, mass = 0;
    for (int j = 0; j < n; ++j) {
        const int q = positions[j], raw = c->indices[q];
        const double s = states[raw];
        if (wakeStates) wakeStates[j] = s;
        auto threshold = [&](int t) {
            return std::clamp(p[2] + p[3]*c->sine[q*481+t] + p[4]*c->cosine[q*481+t], .01, .99);
        };
        double point = 480;
        if (s >= threshold(0)) point = 1;
        else {
            double previous = s-threshold(0);
            for (int t = 1; t <= 480; ++t) {
                const double difference = 1-(1-s)*std::exp(-t/awake)-threshold(t);
                if (difference >= 0) {
                    // Sub-minute interpolation within the first crossing's
                    // bracket; the independent reference checks its accuracy.
                    point = std::clamp(t-1-previous/(difference-previous), 1., 480.);
                    break;
                }
                previous = difference;
            }
        }
        if (predictions) predictions[j] = point;
        if (targets) {
            const double w = weights ? weights[j] : 1;
            const double e = std::abs(point-targets[j]);
            loss += w*(e + (e > 30 ? penalty : 0)); mass += w;
        }
    }
    return targets ? (mass > 0 ? loss/mass : NAN) : 0;
}
