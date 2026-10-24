import sys
from pathlib import Path
import unittest

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from research_sleep_marked_survival import marginal_survival, survival_points


def feed_model(p_before, p_after, p_feed):
    def predict(step, states):
        return np.where(states[:, 0] > 0, p_after, p_before), np.full((len(states), 1), p_feed)
    def evolve(states, marks):
        return np.maximum(states, marks)
    return predict, evolve


class MarkedSurvivalTests(unittest.TestCase):
    def test_no_care_reduces_to_exact_geometric_survival(self):
        predict, evolve = feed_model(.08, .5, 0.)
        actual = marginal_survival([0.], predict, evolve, horizon=40, particles=7)
        np.testing.assert_allclose(actual, .92**np.arange(41), rtol=0, atol=1e-14)

    def test_forced_care_cannot_change_same_minute_sleep(self):
        predict, evolve = feed_model(.02, .4, 1.)
        actual = marginal_survival([0.], predict, evolve, horizon=30, particles=3)
        expected = np.r_[1., .98 * .6**np.arange(30)]
        np.testing.assert_allclose(actual, expected, rtol=0, atol=1e-14)

    def test_marginalization_matches_exact_two_state_chain(self):
        for before, after in [(.01, .2), (.2, .01)]:
            predict, evolve = feed_model(before, after, .12)
            actual = marginal_survival([0.], predict, evolve, horizon=60, particles=32768)
            u, v = 1., 0.
            expected = [1.]
            for _ in range(60):
                u, v = u*(1-before)*.88, v*(1-after) + u*(1-before)*.12
                expected.append(u+v)
            self.assertLess(np.max(abs(actual-np.array(expected))), .006)
            # Ignoring the unknown event is a different distribution.
            self.assertGreater(np.max(abs(actual-(1-before)**np.arange(61))), .05)

    def test_seeded_prefix_and_input_state_preserved(self):
        predict, evolve = feed_model(.03, .1, .2)
        initial = np.array([0.])
        full = marginal_survival(initial, predict, evolve, horizon=60, particles=64, seed=123)
        short = marginal_survival(initial, predict, evolve, horizon=20, particles=64, seed=123)
        np.testing.assert_array_equal(full[:21], short)
        np.testing.assert_array_equal(initial, [0.])

    def test_points_match_exact_discrete_probability_mass(self):
        survival = np.array([1., .8, .4, .1, .05])
        # All remaining tail mass is assigned to the horizon, rather than lost.
        masses = np.r_[survival[:-2]-survival[1:-1], survival[-2]]
        points = survival_points(survival)
        self.assertEqual(points['median'], 2)
        self.assertAlmostEqual(points['mean'], np.dot(np.arange(1, 5), masses))
        self.assertEqual(survival_points(np.ones(5)), dict(median=4, mean=4.))
        self.assertEqual(survival_points(np.r_[1., np.zeros(4)]), dict(median=1, mean=1.))

    def test_invalid_probabilities_or_states_fail_without_dropping_paths(self):
        for probability in [np.nan, -.01, 1.01]:
            predict = lambda step, states: (np.full(len(states), probability), np.zeros((len(states), 1)))
            with self.assertRaises(ValueError):
                marginal_survival([0.], predict, lambda state, mark: state, horizon=2)
        predict, evolve = feed_model(.1, .2, .3)
        with self.assertRaises(ValueError):
            marginal_survival([0.], predict, lambda state, mark: state[:-1], horizon=2)
        for survival in [[1., .4, .5], [.9, .5], [1., np.nan], [1., -.1]]:
            with self.assertRaises(ValueError):
                survival_points(survival)


if __name__ == '__main__':
    unittest.main()
