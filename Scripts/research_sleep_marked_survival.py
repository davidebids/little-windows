"""Minute-step survival with simulated intermediate marks, for local research.

The supplied model predicts sleep and care probabilities from a path's past.
Only care marks are sampled; each path retains its probability of no sleep.
This averages out the unobserved intermediate events without using their
recorded future values. It is a discrete independent-within-bin model, not a
reproduction of a continuous-time neural architecture.

Inference reference: https://proceedings.mlr.press/v216/boyd23a.html
"""
import numpy as np


def marginal_survival(initial_state, predict, evolve, *, horizon=480, particles=512, seed=42):
    """Return P(next sleep > minute m), including S(0)=1.

    predict(step, states) returns a sleep probability per path and a matrix of
    care probabilities. Those events are conditionally independent within the
    minute. evolve consumes sampled care at the minute's end, after accounting
    for sleep survival, so care never influences an earlier sleep probability.
    The model callbacks receive no future observations or forecast targets.
    """
    if not isinstance(horizon, int) or horizon < 1:
        raise ValueError('Expected a positive integer horizon')
    if not isinstance(particles, int) or particles < 1:
        raise ValueError('Expected a positive integer path count')
    initial_state = np.asarray(initial_state, float)
    if initial_state.ndim != 1 or not np.isfinite(initial_state).all():
        raise ValueError('Expected a finite state vector')
    states = np.repeat(initial_state[None, :], particles, axis=0)
    weights = np.ones(particles)
    survival = np.ones(horizon + 1)
    rng = np.random.default_rng(seed)
    marks = None
    for step in range(horizon):
        sleep, care = (np.asarray(x, float) for x in predict(step, states))
        if sleep.shape != (particles,) or care.ndim != 2 or len(care) != particles:
            raise ValueError('Probability dimensions must preserve every path')
        if not np.isfinite(sleep).all() or not np.isfinite(care).all():
            raise ValueError('Nonfinite event probability')
        if ((sleep < 0) | (sleep > 1)).any() or ((care < 0) | (care > 1)).any():
            raise ValueError('Event probabilities must lie in [0, 1]')
        if marks is None:
            marks = care.shape[1]
        if care.shape[1] != marks:
            raise ValueError('The event vocabulary must stay fixed')
        weights *= 1 - sleep
        survival[step+1] = weights.mean()
        sampled = rng.random(care.shape) < care
        updated = np.asarray(evolve(states, sampled), float)
        if updated.shape != states.shape or not np.isfinite(updated).all():
            raise ValueError('Invalid evolved state; do not drop failed paths')
        states = updated
    if not ((survival >= 0).all() and (survival <= 1).all() and (np.diff(survival) <= 1e-14).all()):
        raise RuntimeError('Invalid marginal survival function')
    return survival


def survival_points(survival):
    """Median and mean of min(next-sleep minute, horizon), on 1..horizon."""
    survival = np.asarray(survival, float)
    if survival.ndim != 1 or len(survival) < 2 or not np.isfinite(survival).all():
        raise ValueError('Expected a finite survival curve')
    if survival[0] != 1 or (survival < 0).any() or (survival > 1).any() or (np.diff(survival) > 1e-14).any():
        raise ValueError('Expected a normalized, nonincreasing survival curve')
    horizon = len(survival) - 1
    reached = np.flatnonzero(survival[1:] <= .5)
    return dict(median=int(reached[0]+1) if len(reached) else horizon,
                mean=float(survival[:-1].sum()))
