# Sleep prediction research — paused review

Research is paused. Keep the existing app algorithm pending fresh forward validation. This branch archives research tools and aggregate results; it does not commit the existing uncommitted app integration or UI changes. Do not merge the research into master as a production improvement.

## Evaluation

Issue a prediction at the recorded end of sleep and compare it with the next recorded sleep timer start. The frozen planning cohort contains 1,104 distinct nap/bedtime outcomes: 858 naps and 246 bedtimes. Brief returns within 20 minutes and night-to-night resettling are outside this primary objective; preserve them in source history and evaluate them separately. Sleep kind is inferred from the records rather than caregiver-confirmed.

Training uses only outcomes whose target sleep has ended by the prediction time. These are retrospective walk-forward results from one archive, repeatedly used for model selection. They are not independent future validation or evidence across infants. The archive lacks event creation/edit timestamps.

| Method | Mean absolute error (minutes) | Within 30 minutes |
| --- | ---: | ---: |
| Existing app v8 | 29.4026 | 66.7572% |
| Lowest-error nap/bedtime mixture: bedtimeClockRisk30 | 28.4659 | 67.0290% |
| Best coverage shared recent-pattern forest: pooledForest | 28.9969 | 68.1159% |
| Six-scenario algorithm selection: scenarioChoice | 29.0150 | 67.8442% |

The lowest-error method mixes nap interval and bedtime clock distributions. Its fallback policy differs from the app; an audit retaining the app's daytime policy obtained 28.7413 minutes and 66.7572% within 30 minutes. The best MAE and best coverage above come from different models.

The shared forest uses a 60-day window, 14-day recency half-life, 80 trees, and past-only context. It starts learning with three resolved planning labels, refits each query while below 40 labels, then every 24 queries. It chooses a point using absolute error plus a 30-minute penalty for errors outside 30 minutes. The six-scenario router divides nap position (first, second, later) by preceding short/other sleep and chooses among previously issued algorithms using mature historical errors; it did not outperform the shared forest.

The best coverage candidate improves average error by 0.4057 minutes and adds 15 successes out of 1,104 versus the app. Paired day-bootstrap uncertainty for the MAE difference is [-1.0112, 0.1907] minutes; coverage difference is +1.3587 percentage points with interval [-0.2683, 3.0332]. These conditional, archive-selected intervals include no improvement and do not account fully for repeated model selection.

The app's nap-only result is 26.1498 minutes / 70.9790%; bedtime is 40.7476 minutes / 52.0325%. No method demonstrated the 2-minute average-error / 98%-within-30 goal. Further splitting and more complex models have not established a meaningful replacement. A physiological state-filter prototype remained at neutral numerical preflight, with no completed private-history accuracy result.

## Contents and reproduction limits

The existing replay guide documents the research runners and synthetic checks. `Scripts/lw_planning_scenario_experts.py` preserves the best coverage candidate and learned-bucket comparisons; `lw_planning_scenario_regret.py` preserves its related partition variant; `lw_planning_semantic_router.py` preserves six-scenario routing. These three archived runners now derive the repository root from their own location instead of a machine-specific path. Their command-line inputs include external feature caches, baseline forecasts, and for routing certified earlier candidate streams; these private intermediate inputs are deliberately not committed.

`planning-progress-130.png` tracks 130 primary checkpoints, not every control or every candidate. The strongest shared comparison model is reported in the table even though it is not a separate primary point on the chart.

Only aggregate scores and charts belong in this archive. Raw CSVs, event-level forecasts, feature caches, source hashes, birth dates, model fits, compiled outputs, and Python caches remain outside the commit. Some replay runners depend on the app integration that remains uncommitted; this branch is a research archive, not a standalone production release. A complete replay requires the matching app baseline and original external inputs.
