# External sleep prediction replay

Run the app's Swift prediction code against an external care-history CSV without importing it into the app or adding personal data to the repository:

```sh
python3 Scripts/replay_sleep_predictions.py /path/to/history.csv \
  --birth-date YYYY-MM-DD --time-zone America/Los_Angeles \
  --output /tmp/sleep-replay-results.json \
  --ios-input /tmp/sleep-replay-input.json
```

Requires macOS, Xcode's Swift compiler, and Python 3.9 or later. The CSV needs `Type`, `Start`, `End`, and `Start Location` columns. Dates use `YYYY-MM-DD HH:MM`. Supply the history's actual birth date and time zone; daylight saving time follows the named zone.

The runner compiles `SleepPredictionEngine.swift` and the learning coordinator directly. Only the engine's UserDefaults persistence facade is omitted. It awaits preparation for each chronological query, then calls the public prediction method. The conservative bias function is extracted from `PredictionTuningService.swift`. `Support.swift` supplies storage-free model adapters and a no-op reconciliation callback; it contains no prediction calculations. The optional iOS parity test checks predicted start, window width, and confidence against real app models for every scored transition. Add `--uncombined` to evaluate the preserved v6 baseline; for its optional iOS replay, also set `LW_SLEEP_REPLAY_UNCOMBINED=1`. Preserved older engines supplied through `--engine` retain their own direct prediction path.

Forecasts are issued once, immediately after each completed sleep, using completed history and resolved predictions available at that wake. Completed feeds/nursing enter causal learning when enabled and may affect confidence. Other care categories do not affect the current engine. Each forecast is scored against the immediately following recorded sleep, including brief returns to sleep; it is never shifted toward the actual start by advancing the evaluation clock. Overlapping/duplicate transitions and wakes occurring inside another recorded sleep are counted separately as ambiguous. All remaining positive gaps are scored, including large errors. Nap/night classification matches the existing legacy converter because the CSV has no explicit sleep-kind column.

The target is the next sleep timer's recorded start; the forecast origin is the preceding sleep timer's recorded end. The current app recomputes personalization from the selected profile's rolling history: similar wake clock times and preceding sleep lengths receive more weight, with a 60-day cutoff and ten-day recency half-life. This is individual-history learning rather than a single schedule fitted across profiles. Increasing history can improve support, but schedule changes and observation variability can worsen an individual forecast; accuracy is not expected to improve monotonically.

`--limit` evaluates a chronological prefix; split boundaries remain based on the complete sleep count. The development/validation/final split is 60/20/20 by sleep row. To score the final wake in a prefix, include its following sleep as the target row. `--engine /path/to/Engine.swift` evaluates a preserved candidate. Reports include source and engine hashes, signed bias (late predictions positive), mean/median/p90 absolute errors, rates within 15/30 minutes, interval coverage, and interval width. Raw reports and optional parity inputs must stay outside the repository.

For app parity, build the simulator test bundle, copy its generated `.xctestrun` file beside the original, and set `EnvironmentVariables.LW_SLEEP_REPLAY_INPUT` on the `LittleWindowsTests` test target to the external parity-input path. Run `testExternalSleepHistoryReplayMatchesAppEngine` through `xcodebuild test-without-building -xctestrun <copy>` on an isolated simulator. Without that environment variable, the external-data test skips. Ordinary `testContextual…` tests use neutral synthetic fixtures.

Replay assumes records were logged at the recorded times: the CSV lacks logging/edit timestamps. This is an observational backtest of one history, not independent evidence across profiles. Keep final-period data untouched during model selection; any refinements after inspecting it must be reported as retrospective. Do not infer high nap accuracy from aggregate gains driven by overnight resettling, and report interval width alongside coverage.

## Research models

`Scripts/research_sleep_predictions.py` benchmarks stronger models without changing the app. Its optional dependencies are in `requirements-research.txt`; they are not iOS runtime dependencies. First generate a full Swift replay for the same archive, then run:

```sh
python3 Scripts/research_sleep_predictions.py /path/to/history.csv \
  --birth-date YYYY-MM-DD --time-zone America/Los_Angeles \
  --baseline /tmp/sleep-replay-results.json \
  --models hist_absolute_error_7_10 mixture_0.5 twoProcess dailyPatternDay \
  --output /tmp/sleep-research.json
```

Every candidate scores exactly the same transitions as the Swift replay. Early forecasts use the Swift result until there are 40 available historical labels. Training repeats chronologically, by default every 24 sleep transitions, using at most 60 days of completed observations. No random train/test split or future-label early stopping is used. `--feature-set compact` selects 25 inputs rather than the complete 99-input set. `--feature-cache /tmp/features.npz` optionally exports private features for local analysis. Feature caches and raw results must remain outside the repository.

For histogram-boosting candidates, `--training-half-life-days 7` or `14` weights each training example by its age at that fit, within the lookback window. This changes base-model fitting, independently of any later forecast calibration. The runner rejects unsupported model families and nonpositive half-lives. A synthetic check verifies that newer examples receive greater weight and unresolved outcomes remain excluded. Result metadata records the half-life; no target from after the forecast enters the weights or fit.

Inputs include the preceding sleep, time of day, age, previous wake/sleep lengths, recent sleep totals, already-observed sleep interruptions, past care timing, rolling past wake-window summaries, and observed sleep-pressure state estimates. Default care exposure uses completed events. `--care-exposure started` adds 18 timer-start/elapsed-time inputs, assuming events were logged when started; eventual timer duration is never exposed. This stronger availability assumption must be labeled separately because the CSV lacks creation timestamps.

Available families include median-loss gradient boosting, extremely randomized trees, support-vector regression, ridge regression, short-return/full-wake mixtures, fitted two-process models (`twoProcess`, `twoProcessLocal`), daily-pattern models (`dailyPattern`, `dailyPatternDay`), and discrete next-event hazard models (`hazardMedian`, `hazardMode`). Models that trade average error against fixed-tolerance precision must be judged on both metrics. Average error is mean absolute error, not signed errors that cancel. Do not report a target as achieved by selecting only overnight cases, dropping early history, widening intervals, or predicting closer to the eventual sleep start.

Past-wake analog models include `analog_uniform_15`, `analog_metric_15`, `analog_metric_30`, `analog_forest_5`, and `analog_forest_15`. Uniform and learned distances scale features by the past interquartile range. Learned distance weights fit nonnegative regression to pairwise historical feature differences and outcome differences; neighbor forecasts are weighted medians. Forest similarity uses the historical observations sharing terminal leaves, normalizes each tree's contribution, and takes the weighted median of their outcomes. It does not average terminal-leaf means. All scaling, distance fitting, and tree fitting use the same available-label training boundary as the other models.

`portable_40_5` and `portable_80_5` use an independent small randomized-tree learner, with 40/80 trees, minimum leaf size five, depth at most 12, and a fixed reproducible random stream. Each node tries a random threshold for each selected feature and selects the best squared-error split. Leaf distributions then produce a weighted median rather than an average of leaf means. A relative tolerance makes exact median ties select the lower value consistently across languages. This implementation is inspired by randomized trees; it does not reproduce a library's tree-growing code or random stream. [General reference](https://scikit-learn.org/stable/modules/generated/sklearn.ensemble.ExtraTreesRegressor.html).

The native components are `LittleWindows/Services/PortableSleepFeatures.swift` and `LittleWindows/Services/PortableSleepForest.swift`. They use value inputs for one profile, Foundation, and the Swift standard library. Both belong to the app target; `PersonalizedSleepLearning.swift` connects them to app events. No trained personal model is bundled. `PortableReplay.swift` supplies a standalone macOS evaluation executable. Generate the matching reference with `--models portable_40_5 portable_80_5 --feature-set compact --refit-every 48`, then verify:

```sh
python3 Scripts/check_portable_sleep_model.py /path/to/history.csv \
  --birth-date YYYY-MM-DD --time-zone America/Los_Angeles \
  --baseline /tmp/sleep-replay-results.json --reference /tmp/portable-results.json \
  --output /tmp/native-component-check.json
```

This compiles the actual Swift components, compares every feature and scored forecast with the reference, and checks that removing future sleeps/feeds leaves prefix-query features unchanged. Raw intermediate data is confined to a temporary folder; the saved report contains aggregate checks, metrics, and source hashes. It verifies native macOS components, not iOS integration or phone performance.

After that check passes, evaluate retraining after every wake:

```sh
python3 Scripts/check_portable_sleep_model.py /path/to/history.csv \
  --birth-date YYYY-MM-DD --time-zone America/Los_Angeles \
  --baseline /tmp/sleep-replay-results.json --reference /tmp/portable-results.json \
  --refit-every 1 --native-only --component-check /tmp/native-component-check.json \
  --forecast-output /tmp/native-online-forecasts.json --output /tmp/native-online-check.json
```

Native-only mode requires the successful current-source component certificate. It still verifies all features, targets, cohorts, and prefix invariance, then scores the actual native forecasts. It explicitly reports that the different-cadence predictions were not compared point-for-point with the batched Python reference. The first 40 available labels remain app-fallback forecasts. Subsequent fits use only labels available at that wake and the preceding 60-day history. Optional per-event output must stay outside the repository. A passed component check does not mean that the accuracy objective is achieved.

Conditional-density candidates `density_3_log`, `density_6_log`, `density_3_raw`, and `density_6_raw` fit a regularized full-covariance joint Gaussian mixture over nine wake-context inputs and the future gap. They then condition only on the current context and forecast the median of the resulting gap distribution. The log variants transform the gap before fitting; component counts are capped for small training sets. This is a general density-model experiment, not a reproduction of a published infant-specific predictor. The underlying mixture implementation is described in the [official scikit-learn documentation](https://scikit-learn.org/stable/modules/mixture.html).

The corresponding `sequence_3_log`, `sequence_6_log`, `sequence_3_raw`, and `sequence_6_raw` candidates estimate soft-state transition counts from past joint-mixture memberships, with smoothing toward the fitted state prior. Forward filtering on up to 32 available past outcomes supplies the next-state prior; current wake context then conditions the gap distribution. Missing/ambiguous sleep-row links reset the state prior rather than creating artificial adjacent transitions. This is an independently fitted mixture plus a Markov filter, not a joint Baum–Welch fit or a validated infant physiological model. General forward-filtering background: [Rabiner's hidden Markov model tutorial](https://www.cs.ubc.ca/~murphyk/Bayes/rabiner.pdf). No backward smoothing uses the target outcome.

Target-representation experiments include `loghist_7`, `loghist_15`, `clockPhase_7`, and `clockPhase_15`. Log-gap models transform the target during historical fitting and convert the result back to minutes. Clock-phase models learn sine/cosine coordinates of the next timer start, then select the closest attainable minute in the following eight hours. Public time-zone rules determine future clock phase, including daylight saving transitions; no future care events enter the forecast. A poorly determined phase falls back to the app prediction. All targets enter fitting only after their recorded start is available.

Gaussian-process candidates `gp_rbf_log`, `gp_matern_log`, `gp_rbf_raw`, and `gp_matern_raw` use the same nine context inputs as the density models. They fit feature similarity scales and a noise term from available past labels, with raw or logarithmic gap targets. Kernel fitting uses bounded deterministic optimization with at most 50 iterations per refit; no random holdout or future-label early stopping is used. The benchmark's lookback/refit arguments still apply. This is a general modeling experiment, not a claim of published infant-specific performance. Reference: [official Gaussian-process documentation](https://scikit-learn.org/stable/modules/gaussian_process.html).

Neural candidates `neural_huber_16`, `neural_huber_32`, `neural_squared_16`, and `neural_squared_32` use one tanh hidden layer, deterministic initialization, and weight regularization. They append 60 ordered-history features: the preceding 12 available transitions' sleep duration, resolved wake length, clock coordinates, and elapsed time. This is a feedforward network with ordered lag inputs, not an RNN/LSTM replication. Scaling, imputation, and target normalization use only available training history. The Huber objective approximates absolute loss outside a transition region of 0.1 normalized target units; squared loss supplies a comparison. Analytic gradients are checked against finite differences.

These default neural candidates use regularization 0.01 and at most 200 optimization iterations. Adding `_regularized` to a 16-unit candidate increases regularization to 0.1 and the limit to 1,000 iterations. `_compact` uses those stronger settings without the appended history, retaining only the base feature set. Results include each refit's convergence status, iteration count, training objective, input count, and regularization. A capped or converged numerical fit does not establish a global optimum. Synthetic checks cover ordered-history availability and forecast-prefix invariance for both sequence-augmented and compact neural variants.

`--structured-context` adds 128 fixed hash features from the last completed sleep's start/end conditions and location, plus recency-weighted structured fields from completed records in the prior 12 hours. Hashing uses a fixed digest, rather than learning a vocabulary from future records. Target fields, running events, notes, and caregiver fields are excluded. It follows the same completed-record availability assumption as other care features; the archive lacks creation/edit timestamps. Source text is not retained in the feature cache. The cache still contains private event-level timing data and must remain outside the repository.

The two-process adaptation independently implements exponential awake accumulation and sleep decay, with sinusoidal onset thresholds. It fits a bank of parameters using available past labels; it is not the complete neuronal/light-response simulation. References: [mathematical model comparison](https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0103877) and [infancy physiology study](https://pmc.ncbi.nlm.nih.gov/articles/PMC11527290/).

The daily-pattern adaptation fits nonnegative daily onset patterns on complete previous days, infers current-day coefficients from only already-observed starts, and forecasts the next event. It is inspired by [low-rank infant-sleep forecasting](https://arxiv.org/html/1904.04780); it does not reproduce that paper's multi-infant, 100-day trend forecast. In particular, smoothing a future onset backward into the observed current-day prefix would leak the answer and is forbidden.

The hazard adaptation expands completed historical wakes into event-time intervals and learns a conditional onset probability. Future clock phase and pressure evolve deterministically from the wake-time state; future care events never enter a forecast. The distribution formulation follows the general [discrete-time event-prediction strategy](https://arxiv.org/abs/1910.06724); this implementation uses boosted trees rather than that paper's neural networks.

Run the synthetic causality checks with the research dependencies available:

```sh
python3 -m unittest discover -s Scripts/SleepReplay -p 'test_research_*.py'
```

These checks cover future-row invariance, withholding target time/kind/duration, label availability during training, censoring active timer duration, and the daily-pattern smoothing boundary. They validate the research harness; they do not establish clinical validity or accuracy across other profiles.

`Scripts/research_sleep_ensemble.py` combines previously issued research forecasts with the app baseline. Supply the same private feature cache, baseline, and completed-event research results:

```sh
python3 Scripts/research_sleep_ensemble.py --features /tmp/features.npz \
  --baseline /tmp/sleep-replay-results.json \
  --members /tmp/compact-results.json /tmp/mixture-results.json /tmp/hazard-results.json \
  --output /tmp/ensemble-results.json
```

At each wake, calibration and expert selection use only outcomes already available, with a 30-day history and ten-day recency half-life. Context weighting uses wake clock time and the preceding sleep duration when enough effective examples exist. Each expert's median residual correction is capped at 30 minutes. Selection scores past calibrated forecasts as originally issued, rather than recalibrating them in hindsight. Additional synthetic checks cover unavailable outcomes, future forecasts, and prefix invariance. Candidate selection after inspecting the archive remains exploratory, even when every individual forecast obeys the information boundary. This script evaluates research combinations independently of the app engine.

Add `--learned` to evaluate three additional stacking candidates: direct prediction with context, residual correction with context, and residual correction from expert forecasts alone. These fit only past prequential expert forecasts and available outcomes, using a 60-day window, 14-day recency half-life, and refits every 24 transitions. Predictions use the calibrated combination until 40 historical labels are available. The learner has no random validation split or future-label early stopping. Synthetic checks verify outcome availability and prefix invariance for the fitted learner as well.

Add `--adaptive-windows` to compare 7-, 14-, 28-, and 60-day calibration histories with corresponding recency half-lives of 3, 5, 10, and 14 days. An additional adaptive candidate combines their originally issued forecasts using only resolved errors from the past 14 days, with a five-day half-life and contextual similarity weights. Each history belongs to one profile; outcomes from other profiles must never enter that profile's learner. This tests adapting the learning window as well as the forecast. Tests verify different individual routines produce different estimates, changed recent routines replace stale ones, and unavailable outcomes/future rows cannot change earlier forecasts. This remains a research option until it demonstrates a useful gain and passes native app validation.

`Scripts/diagnose_sleep_model_pool.py --baseline /tmp/sleep-replay-results.json --members /tmp/research-results.json /tmp/ensemble-results.json --output /tmp/pool-diagnostic.json` measures an explicit hindsight-only limit of the supplied forecasts. Selecting the closest candidate uses the actual outcome. Allowing a convex combination can additionally interpolate anywhere between the smallest and largest candidate forecast. The distance from the actual outcome to that interval bounds how well any convex mixture of those specific forecasts could possibly score. These diagnostic numbers are not predictions, are not included in the progress curve as achieved accuracy, and do not bound untested models or new information. Duplicate forecast vectors are counted once; archive hashes, exact cohorts, and targets must match.

`Scripts/summarize_sleep_uncertainty.py --baseline /tmp/sleep-replay-results.json --candidate /tmp/ensemble-results.json --model localCalibratedSoft --time-zone America/Los_Angeles --output /tmp/uncertainty.json` compares a fixed research candidate with the app using 5,000 paired bootstrap resamples of entire wake-date blocks. Optional `--reference /tmp/other-results.json --reference-model <name>` compares two research candidates. Output contains aggregate intervals only. Day resampling retains within-day clustering; it does not account for model-selection optimism, dependence across days, other profiles, or future changes. A narrow interval on a retrospective mean is not evidence of independent two-minute prediction accuracy.


## App learning integration (preserved v6 baseline)

The v6 engine fits 80 randomized trees after at least 40 resolved wake intervals are available in the preceding 60 days. Training and the query are anchored to the last completed sleep end, including when a screen refresh occurs later. Care inputs respect the feed/nursing settings and must already be completed at that origin. Custom baselines retain the existing path; insufficient history uses the preceding contextual/baseline logic. Sleep pressure uses the same learned target; its under-four-month learning state is unchanged.

A lock-protected four-profile memory cache stores value snapshots and estimates, not SwiftData references. Profile, birth date, calendar, completed sleep history, exclusions, and enabled care inputs determine the key. History edits therefore rebuild the estimate. Explicit foreign-profile events are filtered before prediction and pressure calculations; unassigned events retain the existing caller-scoped compatibility behavior. No personal weights are persisted or exported.

The full-history feature calculation skips vectors older than the training window while retaining their raw context. Prefix sums supply occupied sleep time without repeatedly scanning the entire archive; overlapping recorded intervals preserve additive semantics. Feature equivalence, forecast equivalence, history-prefix isolation, profile isolation, and edit invalidation require verification before handoff. Confidence is conservatively capped for this learner; training sample count alone does not establish timing certainty.


## Wake-context specialists and calibration ablation

`Scripts/research_sleep_regimes.py` tests separate forests selected using only the preceding sleep kind, wake clock, and already-completed nap count. Each specialist requires 40 available labels in a 60-day fitting window and refits after 24 global transitions; otherwise it uses the supplied app forecast. The following sleep's kind or target never selects its specialist. All source labels, wake times, and cohorts must match the external app replay.

```sh
python3 Scripts/research_sleep_regimes.py --features /tmp/features.npz \
  --baseline /tmp/app-results.json --source /path/to/history.csv \
  --output /tmp/specialists.json
```

Add `--native` to compile and fit the actual app forest with the storage-free `RegimeReplay.swift` driver rather than using the research library forest. Those implementations intentionally use different random streams/tree rules; they are separate experiments. `Scripts/check_sleep_regime_native.py --output /tmp/native-specialist-check.json` verifies native fitting against the Python portable learner on synthetic data, including unavailable-label and forecast-prefix checks. It does not validate a new production integration.

Use the existing combination runner with `--members /tmp/specialists.json` to score all combination variants from previously issued expert forecasts. Use `--baseline-only` instead of members to isolate local versus global residual calibration of the app alone. This ablation prevents attributing a gain from calibration to specialized models. Source hashes and baseline algorithm labels are preserved in reports. These evaluations preceded v7 integration; their archived metrics remain retrospective. The preserved uncombined v6 path is still available for baseline comparisons.


## Conditional short-return distributions

`Scripts/research_sleep_distribution.py --features /tmp/features.npz --baseline /tmp/app-results.json --source /path/to/history.csv --output /tmp/distributions.json` compares short-return/full-wake conditional distributions with forest or boosted class probabilities. It uses all transitions, 60-day fits, 24-transition refits, and the supplied app fallback before 40 available labels. The point decision is either the mixture median or a center maximizing probability inside the fixed 30-minute tolerance. After-nap-only variants retain the baseline for other wakes. The runner does not modify app models or care data.

The distributional foundation follows the general idea in [Quantile Regression Forests](https://www.jmlr.org/beta/papers/v7/meinshausen06a.html); the mixture and tolerance decision here are independent adaptations, not a published infant-specific performance claim.

`Scripts/sleep_research_metadata.py` recognizes older started-care artifacts from their running-timer feature names when explicit exposure metadata is missing. Both combination and pool diagnostics reject them from completed-event-only analyses. Contradictory explicit metadata raises an error. Candidate file hashes are recorded in finite-pool diagnostics to make the supplied vector set auditable.


## Native calibration and specialist chain

`PortableSleepCalibration.swift` ports the existing five calibration/combination policies as a value-only, per-profile component. It preserves each expert's adjusted forecasts as originally issued. A target enters fitting or risk scoring only when its availability time is at or before the current wake. Calibration uses 30 days of resolved errors with a ten-day half-life; clock/duration context is used only with enough effective support.

```sh
python3 Scripts/check_sleep_calibration_native.py --features /tmp/features.npz \
  --baseline /tmp/app-results.json --members /tmp/native-specialists.json \
  --reference /tmp/native-combinations.json --source /path/to/history.csv \
  --output /tmp/native-calibration-check.json
```

The reference must have been generated from the same baseline and expert order. Add `--fit-specialists` to fit all three specialist families with `PortableSleepSpecialists.swift` before calibration, using `ExpertCalibrationReplay.swift`. That mode compares raw experts, fit counts, all five combined forecast vectors, shorter history prefixes, unavailable-label mutations, and delayed-outcome streaming against the batch replay. The v6 baseline forecasts and causal features remain external inputs; these are component checks, not a new production integration or a new accuracy trial.

The value components now live under `LittleWindows/Services` and belong to the app target; standalone replay drivers remain under `Scripts/SleepReplay`. The public app predictor now uses v7, with background preparation and input-signature cache validation. Publishing a combination requires safe history preparation, cache invalidation on edits/exclusions/profile changes, and live prediction/pressure/system-surface validation. No personal forecasts or trained weights should be added to app resources.

`ReferenceSleepForest.swift` reproduces the research library's 1.9.1 random-split behavior for the unweighted, scalar, mean-imputed configuration used by these specialists. Its forecast uses historical leaf weights and a weighted median. `LittleWindows/Resources/ReferenceForest-LICENSE.txt` preserves the upstream redistribution notice and belongs to the app's resource phase. This port does not claim compatibility with other library versions or arbitrary estimator settings.

```sh
python3 Scripts/check_reference_sleep_forest.py --features /tmp/features.npz \
  --output /tmp/reference-forest-check.json
python3 Scripts/check_sleep_calibration_native.py --features /tmp/features.npz \
  --baseline /tmp/app-results.json --members /tmp/library-specialists.json \
  --reference /tmp/library-combinations.json --source /path/to/history.csv \
  --fit-specialists --reference-forest --output /tmp/reference-chain-check.json
```

The tree checker compares structures, node statistics, training/query leaf memberships, and weighted-median estimates at synthetic and historical fit snapshots. The chain checker compares the full expert/combination trajectories. Its bounded-history probes retain raw forecasts only from the preceding 60 days while preserving the original specialist refit schedule and training snapshots. Two nested 30-day calibration/risk windows suffice for the final current forecast. Intermediate combined outputs during that warm-up are placeholders and must never be scored or persisted as historical issued predictions.

Add `--fit-baseline` to reconstruct the v6 learned baseline with `PortableSleepBaseline.swift`. That mode fits the original portable forest independently at each requested wake with at least 40 available labels in the preceding 60 days. Only sparse-history fallbacks still use the external uncombined app points, which carry the app's age rules and historical bias feedback. Causal features remain external verified inputs. The checker also withholds the supplied baseline wherever the native learner can reconstruct it. This is another preparation/component check; production integration and full app preparation latency remain separate requirements.

## Raw-history combination frontend

`RawSleepCombinationReplay.swift` composes native feature extraction, baseline fitting, specialist fitting, and calibration from primitive sleep/care history. No feature cache or learned baseline forecast vector is supplied to the native executable. The verification script reads the external archive and checks native features, targets, expert points, and all five combination policies against the existing reference:

```sh
python3 Scripts/check_sleep_raw_chain.py --source /path/to/history.csv \
  --birth-date YYYY-MM-DD --time-zone America/Los_Angeles \
  --baseline /tmp/app-results.json --members /tmp/library-specialists.json \
  --reference /tmp/library-combinations.json --output /tmp/raw-chain-check.json
```

The default supplies external app points only for queries with fewer than 40 available labels in the preceding 60 days. Add `--app-fallbacks` to generate those points through `AppSleepFallbackReplay.swift`, compiling the actual uncombined v6 engine and bias correction with the existing storage-free adapters. That mode supplies no external forecasts or feature arrays to the native executable. It preserves virtual v6 feedback independently of the chosen combined forecasts. For a sparse query after dense history, the fallback replay includes earlier dense v6 predictions through that query; this is potentially expensive but preserves the original rules rather than approximating their feedback.

Five current-query probes physically omit the following sleep record. Each native feature vector, requested recent expert vector, and final combined point must match full-history replay. Earlier intermediate combined outputs during bounded preparation are not certified or scored. The full archive still supplies nap/night classifications derived by the existing import convention because it lacks an explicit kind field.

Add `--session` to verify `PersonalizedSleepSession`, the app's value-only incremental calculation component, against the same reference. Every query enters with an unknown outcome; the following step resolves the originally issued query before advancing. The session preserves original adjusted expert points rather than recalibrating historical forecasts after the answer arrives. Copies own independent learning state, and failed forecast/outcome updates commit no partial changes. All components conform to `Sendable`; background coordination must still snapshot model values on their owning thread and reject stale results before publication.

Aggregate reports include elapsed preparation time inside the native executable, excluding compilation and file serialization. These are single-run macOS measurements, not iOS startup benchmarks or device guarantees. These measurements do not verify app background coordination, snapshot/version guards, record invalidation or system-surface publication; those behaviors require separate integration checks. These standalone drivers do not import data into the app, alter SwiftData, or replace the production predictor.


## Production background preparation

The public v7 predictor requests a per-profile primitive snapshot through `SleepLearningCoordinator`. Initial history preparation runs in a utility task. A prepared session advances on new completed sleeps when the existing history is an unchanged prefix and care known by the previous wake is unchanged. Historical edits, deletion, exclusions, settings, birth date and calendar changes rebuild the state. Completion checks the current generation before publishing; deleted profiles invalidate their pending work. Four heavy model sessions are retained, with per-profile point estimates independent of that eviction limit.

The existing v6 forecast is a temporary fallback during preparation. The factors data blob carries optional input-signature and preparation metadata; old factor values decode without those fields, and no SwiftData schema field is added. An open fallback becomes stale when preparation for its exact input finishes. Existing reconciliation then refreshes the record and system snapshots. A previously issued prepared record remains usable during memory warm-up after restart. Resolved records retain the forecast actually issued.

Custom baselines retain the uncombined path, including signature validation, and cancel unneeded learned preparation. Child/dog behavior, explicit foreign-profile filtering, completed-care settings, fixed wake origins and under-four-month pressure learning remain separate safeguards. Pressure derives its target from the selected public forecast. Running sleep suppresses display while allowing preparation of completed history. Full simulator replay awaits each snapshot and verifies point/window/confidence values as well as the prepared marker; default single-call behavior can initially return the temporary fallback. Signed-device startup, notifications, Watch and widget behavior still need physical-device validation.


## Further calendar and regression experiments

`research_sleep_weekly.py` adds fixed local-calendar weekday indicators or weekly clock harmonics to the compact specialist inputs. It validates its cache against raw-history features and retains the v6 expert and five original combination policies. Supply `--source`, `--features`, `--baseline`, `--incumbent`, `--birth-date`, `--time-zone`, and an external `--output`. The larger complete feature set already included weekday information; this experiment isolates calendar representations in the compact specialist model.

`research_sleep_correction_limits.py` holds the four issued experts fixed and compares residual-correction caps of 60, 120 and unrestricted minutes. The existing `combine` function defaults to 30 exactly as before; the scoring tolerance stays 30 minutes in every experiment. All five default policies must retain their original forecast vectors. Supply `--source`, `--features`, `--baseline`, `--members`, `--incumbent`, and an external `--output`.

`research_sleep_local_regression.py` tests local ridge mean and penalized median fits over forest neighborhood weights, with nine continuous slope inputs. The general idea follows equation (3) of [Local Linear Forests](https://arxiv.org/abs/1807.11408). This adaptation keeps ordinary randomized-tree splits and omits the paper's honest/residual-aware construction; it is not a full reproduction or an infant-specific performance claim. Supply `--source`, `--features`, `--baseline`, `--incumbent`, and an external `--output`. Solver failures are counted and retain the original forest median for that query rather than dropping a case.

Each candidate scores the same complete scorable cohort at the preceding timer end. Fixed-calendar features, unavailable outcomes, prefix isolation, constant/missing inputs and analytic local trends have synthetic checks. These experiments do not change production code; keep raw results and models outside the repository.

## Upstream generalized random forest research

`build_sleep_grf.py --source <external-checkout> --output <external-build>` compiles the authors' C++ core and runs its local-linear forest tests. The evaluated checkout is revision `5bee99b51471f76cb2d63acbc8a9b0ffec408ba0` of [GRF](https://github.com/grf-labs/grf). Its GPL dependency, binaries and trained states stay outside this repository and the app target. `SleepReplay/GRFReplay.cpp` is a research bridge, not an app implementation or a claim of bit-for-bit R-interface compatibility.

`check_sleep_grf.py --build <external-build> --features <external-cache> --output <external-report>` checks constant/missing data, analytic trends and query-prefix isolation. Add `--nonhonest` to check the alternate training setting. Here honesty means separating split-selection observations from leaf-estimation observations; both settings use only outcomes available at the historical forecast origin.

`research_sleep_grf.py` accepts `--source`, `--features`, `--baseline`, `--members`, `--incumbent`, `--build` and `--output`, with optional `--nonhonest`. It evaluates upstream median forests, ordinary and residual-split local-linear forests, the same-forest mean control, context median specialists and calibrated combinations. It uses 2,000 trees, a 60-day history and 24-transition refits. Local-linear penalties are selected by past training-snapshot out-of-bag error. Training-only imputation and query batching must preserve earlier issued forecasts when later queries are appended. Nonfinite predictions retain the baseline and are counted; no scored transition is discarded. Results record the exact source, bridge and executable hashes.

These experiments follow the [official local-linear reference](https://grf-labs.github.io/grf/reference/ll_regression_forest.html) and [paper](https://arxiv.org/abs/1807.11408). They test these particular settings, not every possible forest configuration. They do not replace the integrated predictor.

## Ordered boosting and post-selection research

`research_sleep_ordered_boosting.py --source <external-csv> --features <external-cache> --baseline <issued-app-results> --output <external-report>` evaluates CatBoost 1.2.10 locally. It compares Ordered/Plain absolute-error training, Ordered squared-error training, and Ordered corrections to the originally issued app forecasts, each at depths four and six. Parameters are fixed at 400 iterations, learning rate 0.05 and L2 leaf regularization 10. Chronological training uses `has_time=True`, one thread, 60-day histories, 14-day weight half-life and refits every 24 transitions after 40 available labels. There is no future evaluation set or early stopping. Five causal combination policies are also scored. The library and trained models stay outside the app; the script records version and input/source hashes.

`check_sleep_ordered_boosting.py --output <external-report>` checks every configuration's prefix and unavailable-label behavior against the native library. Its separate constant-target fixture enables `allow_const_label=True`, because native defaults reject constant training targets; scored archive runs retain the explicitly recorded original parameters. The checks cover replay behavior, not predictive accuracy. See the [official parameter reference](https://catboost.ai/docs/en/references/training-parameters/common) and [objectives](https://catboost.ai/docs/en/concepts/loss-functions-regression).

The existing `research_sleep_ensemble.py` can also accept issued v7 results as its baseline. `--baseline-only` tests final-forecast residual correction. A members file containing previously issued forecast vectors can test second-stage expert selection, adaptive histories and learned combinations. Choosing those members after inspecting the archive is retrospective model selection, even when every subsequent fit uses only available past labels. Report that limitation; do not label it independent validation. Any extra stage must retain the original issued forecasts when calculating historical errors. `summarize_sleep_uncertainty.py` provides paired wake-date bootstrap intervals that exclude model-selection uncertainty.

## Local tabular-prior research

`research_sleep_tabular_prior.py` accepts `--source`, `--features`, `--baseline`, `--bootstrap` and `--output`. It uses the public TabPFN-v2 regressor weights with TabPFN 9.2.0 and PyTorch 2.14.1, eight estimators, two CPU threads, fixed seed 42 and cached training context. Each fit uses only resolved earlier labels within 60 days, with 40-label warmup and 24-transition refits. Every issued forecast is a separate single-row query; later query features are never supplied with it. It evaluates distribution mean, median and mode points, followed by five causal combinations with the original app expert. This is a tabular-method evaluation, not a published infant-sleep accuracy claim.

`--lookback-days` changes the training window at each refit; the default remains 60. Shorter windows retain the same cohort, 40-label requirement and issued-app fallback. Check actual support before comparing windows, and distinguish the training-row window from historical summaries already present in each feature row. Compact inputs contain 25 columns; the completed-care complete input set contains 99. Reconstruct complete inputs from the raw archive and check truncated histories before using an older cache. Preserve source snapshots for long-running experiments when changing the research interface, so result hashes still identify the code actually loaded.

Keep its isolated environment, public weights and private results outside the repository. The bootstrap report must certify neutral local inference and provide the exact weight-file hashes; the script verifies those before using history. Pre-download weights using neutral data, then run history replay with `HF_HUB_OFFLINE=1`, separate temporary model/cache directories and no hosted inference. The public v2 weights have separate attribution terms; they are not included in the app. See the [published study](https://www.nature.com/articles/s41586-024-08328-6) and [official implementation](https://github.com/PriorLabs/TabPFN). Newer default model versions are not substitutes for the explicitly selected v2 weights.

## Constrained forecast combinations

`research_sleep_convex.py --features <external-cache> --baseline <issued-app-results> --members <external-issued-experts> --output <external-report>` learns nonnegative forecast weights that sum to one by linear programming. It minimizes weighted absolute error over resolved earlier outcomes, optionally adding a one-minute coefficient on the L1 distance from the original app expert. The eight settings compare 30/60-day histories, global/context observation weighting and zero/one-minute regularization. Every eligible wake fits fresh weights after at least 40 known labels; forecasts remain inside the current experts' range and the existing planning bounds. There is no fitted intercept, future label, or discarded solver failure.

This is a median/point adaptation of [constrained quantile regression averaging](https://arxiv.org/abs/1803.06730). Recency/context weighting and baseline shrinkage are explicit research extensions. The cited paper evaluates a different forecasting domain; it provides no infant-sleep accuracy guarantee. Members selected after inspecting the archive remain retrospective choices. Keep model-pool hindsight diagnostics separate: even a perfect selector or convex blend knowing every answer is a bound only for those supplied forecast vectors, not an achieved prediction or a limit on untested methods.

## Structured care-value inputs

`research_sleep_care_values.py --source <external-csv> --features <external-cache> --baseline <issued-app-results> --time-zone <named-zone> --output <external-report>` adds 13 fixed inputs derived from completed structured care fields. These represent recorded nursing-side durations, side proportions, segment counts and rolling diaper attributes. The duration/side grammar follows the converter's hour/minute format; the parser rejects invalid minute fields and zero-length segments. There is no text-vocabulary fit or use of notes. Features describe recorded attributes, without interpreting them as diagnoses.

The experiment compares histogram absolute-error boosting and absolute-error extra trees with their unchanged input controls, then evaluates five combinations with the issued app expert. Optional `--feature-cache` writes the expanded numeric matrix outside the repository for later local experiments. All fits retain the original 60-day/24-transition schedule and cohort. Unit checks cover parsing, future-record isolation and rolling expiration; a neutral end-to-end command check verifies native model-return handling, serialized forecasts and fit counts. Raw structured values and personal observations must remain outside source, test fixtures and reports.

## Pretrained sequence research

`research_sleep_sequence_prior.py --source <external-csv> --features <external-cache> --baseline <issued-app-results> --bootstrap <neutral-bootstrap-report> --model <external-weights> --output <external-report>` evaluates local Chronos-2 forecasts. Three fixed configurations compare the last 128 or 512 resolved gaps and a 512-gap version with seven wake-time covariates. Gaps are indexed by event order, with a 60-day cutoff and at least 40 available labels; they are not described as uniformly spaced clock observations. The contextual version supplies only age, current clock phase, preceding sleep duration/kind and observed episode history already known at the forecast origin. API `future_covariates` refers to that next event index, not future recorded care or its target.

Each wake makes one query with cross-learning disabled. Native median and a custom discrete-quantile decision rule are scored, followed by five causal combinations with the issued app expert. The custom rule minimizes approximate expected absolute error plus a 30-minute miss penalty; its quadrature is not a calibrated probability claim. Warmup retains the app forecast and every scored case. The pretrained weights are fixed; resolved rolling context supplies personalization without fine-tuning.

Run private inference offline after downloading public weights with neutral data. Weights, libraries, numeric caches and per-event results stay outside the repository and app. The bootstrap records exact model-file hashes, repeated inference and unrelated-query isolation. Synthetic tests cover unavailable labels and prefix isolation; a physically truncated native replay checks the actual library outputs. This is an adaptation of a general forecasting model, with no infant accuracy guarantee. See the [official implementation](https://github.com/amazon-science/chronos-forecasting) and [paper](https://arxiv.org/abs/2510.15821).

`research_sleep_sequence_head.py` tests supervised adaptation of frozen Chronos-2 representations, rather than updating the pretrained weights. It uses `--source`, `--features`, `--baseline`, `--bootstrap`, `--model`, `--cache` and `--output`, with the same external-only privacy rules. Each single query encodes up to 128 resolved gaps, optionally with the seven past wake-context series. The target channel's masked output token becomes a 768-dimensional representation. The official `embed` method has no known-current covariate input, so the prediction head separately receives the 25 already-known current-wake inputs.

Representations require eight past resolved gaps. Four head settings per representation compare direct versus residual weighted ridge and penalties 0.1/1. Missing head inputs use weighted means from eligible training rows (zero if a column is entirely missing); query inputs use those same fitted values. Scaling fits only eligible training rows, with equal total scale assigned to the encoder and current-input blocks. Both an intercept and weights are fitted after 40 labeled representations, on 60-day histories with a 14-day half-life; fits refresh every 24 transitions. Residual targets use the app forecasts as originally issued. Early cases retain the app forecast. Five causal combinations complete thirteen candidates. This custom supervised-head adaptation is separate from the library's native fine-tuning API and does not claim to reproduce it.

## Native full-weight sequence adaptation

`research_sleep_sequence_finetune.py` accepts `--source`, `--features`, `--baseline`, `--bootstrap`, `--fit-bootstrap`, `--context-bootstrap`, `--model`, `--work` and `--output`, all personal outputs outside the repository. It compares 10/30 full-weight optimization steps at learning rate 0.00001, batch size eight, AdamW, CPU float32 and seed 42. Each refresh trains a fresh copy of the fixed base weights using only the last 128 resolved gaps and seven associated past covariates, within 60 days. Training future-covariate values are explicitly `None`: the upstream sampler constructs every supervised slice from the resolved history. Prediction receives only the current known wake covariates. Native training uses its documented quantile objective; the experiment does not use a future validation set or early stopping.

At least 40 labels are required; 48-transition refreshes and all warmup app forecasts remain in the score. The adapted model is explicitly placed in evaluation mode before each single-query forecast. Median/custom quantile-risk points plus five causal combinations produce nine configurations, each evaluated on the full cohort. Neutral bootstraps must verify finite native adaptation, repeated seeded fits and preservation of the base-model forecasts. The script records model-file and source hashes, settings and refit counts. Weights and checkpoints stay local and are never app resources. These two bounded fine-tuning settings are research candidates, not an exhaustive search or an accuracy guarantee.

## Current-wake-conditioned sequence representations

`research_sleep_conditioned_head.py` accepts `--source`, `--features`, `--baseline`, `--bootstrap`, `--model`, `--cache` and `--output`. It captures the target forecast token from a frozen public single-query prediction, after the encoder has seen the seven already-known current-wake covariates. Unlike the earlier `embed` experiment, this representation includes those values inside the encoder. Passive hooks also retain the target's location and scale. Every captured state must reconstruct the public quantiles within 0.00001 minutes; hooks are removed after each query. Neutral bootstrap checks require unchanged public forecasts, repeatability and sensitivity to current known covariates.

Forty resolved gaps are required to encode a query, with a 128-gap cap and 60-day cutoff. The head learns after 40 eligible labeled representations, retaining the app forecast during its additional warmup. Six weighted ridge heads compare direct/residual minute targets and inverse-arcsinh-normalized direct targets at penalties 0.1/1. Two nonlinear heads use absolute-error histogram boosting, 150 iterations, seven leaves, minimum leaf size 15, L2 penalty 10 and learning rate 0.05, without early stopping. All heads refresh every 24 transitions on resolved 60-day history with a 14-day half-life. Scalers/imputation fit past training rows only; boosting handles missing inputs natively. Two native point controls and five causal combinations complete fifteen full-cohort configurations. CPU thread counts are bounded at two.

This is a custom frozen-representation adaptation, not native pretrained-weight training or an infant-specific performance claim. Raw states, normalization values, caches and forecasts remain external to source and app resources. Exact source, helper, model and cache hashes are recorded.

Native thread limits are discovered after importing the boosting implementation, so later-loaded OpenMP runtimes are included. The replay records the actual pools while the limit is active. An interrupted head fit can reuse completed frozen states with `--reuse-cache-certificate` and `--reuse-extraction-source`: hashes must match the archive, feature cache, model, helpers and state cache, and the two extraction functions must have identical syntax trees. Reuse also validates all array shapes, availability masks and scale values. If the interrupted process did not persist its measured reconstruction maximum, diagnostics explicitly report the unchanged extraction guard's certified upper bound instead. A new independent prefix replay checks the reused states and fitted forecasts.

Optional `--fast-bin-certificate` enables a scoped exact specialization for weighted histogram bins. The installed binner calls a scalar weighted-percentile helper repeatedly on the same column; `sleep_weighted_bins.py` sorts and accumulates positive float64 weights once, evaluates the same 255-bin rank grid, and reuses those values within each worker. Other input forms use the unmodified native helper. The dependency binding is restored on exit, and installed library files remain unchanged. The certificate must pin the helper and native source hashes and verify identical bin boundaries, fitted tree structures and predictions. This optimization changes runtime, not the study's model parameters or cohort.

## Recent cycle alignment

`research_sleep_cycle_alignment.py --source <external-csv> --features <external-cache> --baseline <issued-app-results> --output <external-report>` compares the last six or twelve resolved scored cycles. Each cycle contains fixed log transforms of the preceding sleep duration and following resolved gap, plus the historical wake's clock phase. Patterns are frozen as known at their own origin, restricted to seven days, and reset across unavailable or ambiguous links. The current target never enters its pattern. Current-wake clock phase, duration, recorded night flag, episode segments and age provide a separate anchor.

The dynamic program adds squared local differences to the minimum of its three permitted predecessor costs. A band of two cycle positions permits limited alignment; a zero-band Euclidean control permits none. Neighbor distance divides the sequence cost by its fixed length before adding the current anchor cost. These are event-indexed patterns, not uniformly spaced clock measurements. Background: [official DTW formulation](https://tslearn.readthedocs.io/en/stable/user_guide/dtw.html) and [time-series neighbor regression](https://tslearn.readthedocs.io/en/stable/gen_modules/neighbors/tslearn.neighbors.KNeighborsTimeSeriesRegressor.html).

At each wake, fifteen nearest eligible patterns from sixty days receive inverse-distance weights with a fourteen-day recency half-life. At least forty resolved labeled patterns are required. Weighted median and a custom absolute-error-plus-thirty-minute-miss decision produce eight individual candidates; five causal combinations with the app complete thirteen. This is an independent NumPy adaptation, not a reproduction of the library's default mean regressor or an infant accuracy claim. Warmup and reset cases retain the app forecast, and every scored transition remains in the metrics. Tests compare the batched recurrence against exhaustive paths and verify prefix/unavailable-label isolation. Raw patterns and forecasts stay outside the repository.

## Clock-grid controls

`research_sleep_minute_grid.py --source <external-csv> --features <external-cache> --baseline <issued-app-results> --parent <issued-research-results> --parent-model <model-key> --output <external-report>` evaluates fixed five-minute rounding of already-issued forecasts. It compares nearest (half up), floor and ceil rules for the app and a supplied research parent, retaining the existing one-to-480-minute planning bounds. A three-microsecond boundary tolerance handles floating timestamp reconstruction. Actual target starts are never rounded or relabeled; the UTC five-minute grid agrees with local minute boundaries in the supplied Pacific-time history.

Five causal combination policies compare the app's four experts, and five more compare the expanded eight-expert pool, completing sixteen configurations. Adaptation scores past issued predictions only after their outcomes resolve, using the existing thirty-day/ten-day-half-life combination policy and bounded residual correction. Static rules do not read the current target's minute. All cases and warmup remain in the score. The grid and research parent were chosen after archive inspection, so these are retrospective research choices, not prespecified independent validation. Reports record both parent-result hashes. A higher within-thirty rate with worse mean error is a tradeoff, not overall dominance or achievement of the original two-minute/98% objective.

## Learning small periodic timing corrections

`research_sleep_phase_calibration.py --source <external-csv> --features <external-cache> --baseline <issued-app-results> --output <external-report>` uses the issued app forecast's minute phase modulo five as a known input. Four candidates compare circular Gaussian phase bandwidths of 0.5/1.5 minutes and maximum shifts of 2.5/5 minutes. At each wake, they learn a weighted median of resolved past unrounded app errors from sixty days, with a fourteen-day half-life. A zero-correction prior with the weight of ten recent observations shrinks weak evidence toward the app. Forty labels and effective support eight are required. The actual next start's minute never enters its forecast's input.

Two uncalibrated selectors also compare the app and its nearest/floor/ceil rounded forecasts, using past local or global risk. Two controls use the same shrinkage and caps without phase weighting. Five causal combinations complete thirteen candidates, each scoring the same full cohort. The selectors and combinations retain their existing eight-label warmup; the phase models use forty. Original issued app errors remain the feedback source, so a correction does not retroactively become its own training baseline. This is a retrospective minute-heaping adaptation, not independent validation or a change to timer-start labels. Private forecasts remain external to the repository and app resources.

## Six-state model clock templates

`SleepReplay/NeuralSleepCore.cpp` translates the public model's neuronal switch, homeostatic pressure, photoreceptor and two circadian equations. It uses the executable example's assumed 20/1000-lux daily light curve, not measured exposure. The upstream code and Methods use 1000 lux; the article table lists a different daytime value. The MIT notice is in `SleepReplay/NeuralDynamics-LICENSE.txt`; this research bridge is outside the app target. [Published model](https://journals.plos.org/ploscompbiol/article?id=10.1371/journal.pcbi.1012541), [authors' code](https://github.com/brain-modelling-group/infant-sleep-trajectory).

`check_sleep_neural_core.py --binary <external-binary> --output <external-check>` compares neutral derivatives and onset times with an independent direct-equation SciPy Radau calculation and a half-step integration. MATLAB is not executed, so this is not MATLAB runtime parity. `build_sleep_neural_bank.py --binary <external-binary> --core-check <external-check> --upstream <external-code-folder> --output <external-bank> --check-output <external-report>` checks a coarse 56-setting grid at one- and half-second steps before private evaluation. It uses four weeks of warmup, then a trailing fourteen-day model window and one extra lookahead day. Numerically inconsistent settings are excluded from the neutral bank; scored history cases are retained.

`research_sleep_neural_dynamics.py --source <external-csv> --features <external-cache> --baseline <issued-app-results> --bank <external-bank> --bank-check <external-check> --output <external-report>` adapts these generic clock templates to the fixed timer-start benchmark. Three explicit decisions use the fourteen simulated days: lower-median next onset, a sleep-opportunity prior returning one minute when the model expected sleep, and lower-median next onset conditioned on model days being awake (with the ordinary onset median as fallback). Clock offsets of minus two, zero and plus two hours are candidate template phases. These are forecast adaptations, not observed neuronal states, measured light inputs or a replication of the paper's weekly half-hour probability fit.

Global/local selection minimizes past absolute error or absolute error plus the existing thirty-minute miss penalty, using sixty-day histories, fourteen-day weighting and at least forty resolved labels. Every wake selects afresh; the app supplies warmup. Twelve selected-template candidates plus five causal combinations score the full cohort. Source, binary, bank, helper and upstream-file hashes are recorded. No personal observations or trained parameters are app resources, and no infant-specific accuracy is assumed from the publication.

## Completed-history model observer

`SleepReplay/NeuralSleepObserver.cpp` reuses the six-state equations but introduces a separate observation rule. At each wake it integrates seven elapsed days of the union of completed sleep intervals. Assumed fixed firing voltages, awake `(1.3, -6.7)` and asleep `(-15, 1.3)`, drive the pressure and gated light/circadian states. These are assumptions rather than measured neuronal values. The window begins with the source example's fixed state, without a fitted clock phase or latent-state distribution. At the query, fast states reset to awake and the full equations run freely to the next downward switch, capped to the existing one-to-480-minute planning range. Known calendar time-zone offsets preserve daylight saving transitions. Future care intervals are never used in the forcing history.

`research_sleep_neural_observer.py --source <external-csv> --features <external-cache> --baseline <issued-app-results> --binary <external-observer-binary> --output <external-report>` compares fourteen pressure/circadian parameter settings. Four global/local past-error selections and five causal combinations score all cases with app warmup. Selection uses the same sixty-day history, fourteen-day weighting, forty-label minimum and absolute-error/miss losses as the clock-template study. Optional `--cached-result` reuse checks source, binary, equations, observer, exact input, raw state, feature and baseline hashes and both integration steps before using native states. Private intervals, latent states and predictions stay outside the repository. The feature cache retains the separately supplied age inputs; the observer only reads intervals from its loader.

`check_sleep_neural_observer.py --binary <external-observer-binary> --output <external-check>` compares assumed forced states and released onsets with independent Radau integration and checks pressure against its analytic exponential solution. Half-step comparisons test numerical consistency, not physiological or forecast accuracy. Unit checks cover completed-only union construction, future-row isolation and DST metadata. Prefix checks compare separately generated native states and causal forecasts. This observer is a new research adaptation, not the authors' weekly probability fitting procedure, and its initialization/observation assumptions remain limitations.

## Matched model-state feature ablation

`research_sleep_state_features.py --source <external-csv> --features <external-cache> --baseline <issued-app-results> --observer-result <external-observer-results> --observer-check <external-certificate> --fast-bin-check <external-check> --output <external-report>` checks whether the assumed observer states help a learned mapping instead of using the model's switch time directly. The observer result, its certificate and raw states must match source, feature and baseline hashes. Every head includes the same compact context and originally issued app forecast. Augmented heads append seventy columns: fourteen models' switch forecasts and four slow states at each wake. These are derived inputs, not physiological measurements.

Four matched control/augmented pairs cross direct next-start interval versus residual targets with fourteen-/sixty-day training half-lives. They use absolute-error gradient boosting, 150 iterations, seven leaves, minimum fifteen samples per leaf, regularization ten, learning rate 0.05 and a fixed random seed. Training uses sixty elapsed days, at least forty resolved labels and refits every twenty-four queries; early stopping is disabled. All fitting and residual targets use past issued forecasts and labels already available at the query. Native threads are bounded after importing the estimator, and the optional exact weighted-bin fast path is hash checked against its neutral parity certificate.

Eight individual heads plus five causal combinations score the entire cohort. Individual warmup retains the app forecast; the combination service can calibrate after eight resolved outcomes using its existing thirty-day/ten-day weighting. Combined results include controls and cannot attribute gains specifically to added states. Neutral tests and real-data prefix replay check causal isolation. Paired date-block summaries, if reported, are conditional retrospective comparisons and do not create independent future validation. Observer initialization, light and observation assumptions remain limitations.

## Completed-care path signatures

`research_sleep_care_signatures.py --source <external-csv> --features <external-cache> --baseline <issued-app-results> --fast-bin-check <external-check> --output <external-report>` adds event-stream summaries using the [signature method](https://arxiv.org/html/1603.03788v2), specifically Chen concatenation and level-two signed areas. This is an independent general-purpose sequence adaptation, not a published infant sleep accuracy claim. Only event type and completed start/end timestamps enter the path; no notes, names or fitted vocabulary are used. Seven fixed care types and an `Other` bucket form eight mark dimensions, plus elapsed time.

For six-, twenty-four- and forty-eight-hour completion windows, the path advances normalized elapsed time to each distinct completion timestamp, then jumps the cumulative mark counts. Simultaneous completions share one mark increment, so source row order does not invent a within-timestamp sequence. Time advances to the query at the end. A straight increment contributes half its outer product to level two; Chen concatenation adds earlier/later increment products. The level-two antisymmetric part is the signed-area summary. This finite truncation is lossy and does not preserve every detail of a complete event sequence.

Three matched input sets append level-one counts, counts plus time/mark areas, or counts plus all time/mark and mark/mark areas to the same compact context and issued app forecast. Their added widths are twenty-seven, fifty-one and 135. Direct/residual targets and fourteen-/sixty-day training half-lives yield twelve heads; five combinations complete seventeen configurations. Learner settings and sixty-day, forty-label, twenty-four-query refitting follow the preceding matched study. Combinations retain their existing eight-label calibration threshold. All scored transitions and warmup remain in the score.

Inputs require start and completion at or before the wake. Missing or nonpositive sleep/feed completions are omitted as uncertain timer history; other missing ends retain the export's instantaneous-record interpretation. This changes input evidence only and excludes no scored prediction case. Tests cover a published mathematical example, independent all-pairs integrals, shuffle/subdivision identities, order sensitivity, simultaneous-event invariance, future/unavailable-label isolation and prefix replay. Private derived paths and per-event forecasts stay outside the repository and app resources.

## Direct care-group alignment

`research_sleep_care_alignment.py --source <external-csv> --features <external-cache> --baseline <issued-app-results> --output <external-report>` compares the latest eight or sixteen distinct completed-event timestamp groups within forty-eight hours. The same completed-only reader and mark dictionary as the signature study are reused. Each group contains eight mark fractions scaled by the square root of two, plus half the `log1p` completion age in minutes, mean completed duration in minutes and group size. Simultaneous completions remain grouped. These patterns preserve a finite recent sequence directly instead of reducing it to level-two areas; rare mark types and within-timestamp order remain coarsened.

The [documented DTW recurrence](https://tslearn.readthedocs.io/en/stable/user_guide/dtw.html) and existing independent NumPy implementation compare fixed row alignment (band zero) with a band of two groups. This is a general alignment adaptation, not a sleep-specific validation of the library. Squared sequence cost divided by pattern length is added to the prior sleep-cycle experiment's fixed context cost for wake clock, last sleep duration/type, episode segments and age, then square-rooted. Fifteen nearest eligible prior query patterns from sixty days receive inverse-distance and fourteen-day recency weights. Forty resolved labels are required. Chronological tie breaking, weighted medians and the existing absolute-error-plus-thirty-minute-miss decision are retained.

Eight direct forecasts plus five combinations with the app score the full cohort. Optional `--parent <external-report> --parent-model <model-key>` adds five more combinations of the app, that originally issued research parent and the eight direct forecasts. Parent source/target lineage is checked, and the parent was selected retrospectively, so this expanded comparison supplies no independent future validation. Current or future target labels never enter the matching patterns or neighbor decisions. Insufficient histories keep the app forecast; no scored cases are dropped. Pattern and result caches remain external. Unit checks cover grouped marks/durations, translation and tie invariance, future records, unavailable outcomes and prefix behavior; the inherited DTW tests compare recurrence values against exhaustive paths.

## Recurrent completed-care learner

`research_sleep_care_recurrent.py --source <external-csv> --features <external-cache> --baseline <issued-app-results> --output <external-report>` learns from the same sixteen completed care groups instead of using a fixed alignment metric. A single [GRU](https://docs.pytorch.org/docs/2.14/generated/torch.nn.GRU.html) layer of width sixteen feeds a sixteen-unit tanh decoder alongside known current context and missingness indicators. Three matched inputs use a zero sequence, the repeated mean group, or actual chronological groups. They share the same architecture, cold seed, optimization budget and direct/residual target options. Zero and pooled inputs remove sequence information in different ways; they do not prove that every possible event summary is controlled.

Each cold refit uses only resolved labels from sixty days with a fourteen-day weight half-life, at least eighty examples and refits every forty-eight queries. Training uses normalized weighted absolute error, AdamW learning rate/weight decay 0.01, gradient norm cap one and sixty-four full-batch steps. Target centering uses the training weighted median and fixed sixty-minute scale. Input means/scales are training-only, with scale floor 0.05 and standardized inputs clipped to plus/minus ten. CPU execution uses two threads, deterministic algorithms and seed 42; forecasts retain the one-to-480-minute planning range. Six base forecasts and five causal combinations score all cases, with app warmup retained.

`research_sleep_care_recurrent_validation.py` accepts the same source/feature/baseline/output arguments and adds past-only training-duration selection. At each outer refit the latest `max(16, floor(n/5))` already-resolved rows validate cold fits of sixteen, sixty-four or 128 steps trained on the older rows. Validation scaling is fitted on that older part only. Weighted validation absolute error selects the duration, with ties favoring fewer steps. A separate cold fit then uses all currently available training rows at the chosen duration. The selected durations are counted in aggregate; no current or future target is used. This yields six adaptive base forecasts plus five combinations.

These are small, fixed-architecture research adaptations, not a published infant sleep forecasting guarantee or independent future validation. Tests check matched sequence views, train-only normalization, cold-fit determinism, chronological nested splits, selection ties and current/unavailable-label and prefix isolation. Private patterns, weights in process memory and per-event forecasts are not app resources.

## Frozen completed-care reservoirs

`research_sleep_care_reservoir.py --source <external-csv> --features <external-cache> --baseline <issued-app-results> --output <external-report>` tests a readout-only alternative inspired by the [practical reservoir-computing guide](https://mantas.info/get-publication/?f=Practical_ESN.pdf). It independently adapts the leaky tanh recurrence to the same finite sixteen-group care history. A seed-42 orthogonal matrix scaled to norm 0.9, fixed Gaussian input weights/bias and leak rates 0.3/1 produce sixty-four final-state features. State resets to zero for each query window. Eight mark fractions are restored to unit sum; the three logged age/duration/count channels are divided by four. Encoding arithmetic is query-local, with no fitted encoder statistics, labels or future-query batch dependence. This finite-window adaptation is not an estimate of physiology or a sleep-specific guarantee.

Controls use a zero latent coordinate or pooled group means. Every head also sees the same compact context and issued app forecast. Weighted ridge with penalty one learns direct/residual outputs jointly. Two normalized weighted absolute-error readouts use L1 slope penalties 0.001/0.01 and an unpenalized intercept. The target center is the training weighted median with fixed sixty-minute scale; feature blocks use training-only weighted means/std and equal total block scaling. A HiGHS dual-simplex solution must succeed, remain finite and satisfy its equality constraints within `1e-6`; failure stops the experiment rather than dropping cases. Controls and reservoirs differ in latent width, so this is not a claim to control all representation or capacity effects.

Four feature blocks, three readout settings and two targets complete twenty-four individual forecasts; five existing causal combinations complete twenty-nine. Training uses sixty-day windows, fourteen-day recency weights, forty resolved labels and refits every twenty-four queries. All scored cases and warmup are retained. Tests cover orthogonal contraction, independent scalar recurrence, bounded states, query-prefix encoding, weighted-median constants, linear extrapolation and unavailable-label/prefix forecasting. Private encodings and predictions stay external; no trained reservoir/readout is bundled in the app.

## Low-label updates and mature handoff

`research_sleep_few_shot.py --source <external-csv> --features <external-cache> --baseline <issued-app-results> --output <external-report>` compares prior-shrunk additive residual, logarithmic ratio and direct-gap updates starting with the first resolved label. The current issued app forecast is the prior; its earlier issued forecasts define past residuals/ratios. It already contains age/history feedback, so this is not a comparison against an app that ignores early history. Sixty-day history and fourteen-day recency weights use only labels resolved at the current wake. Local weights add the existing circular-clock/duration kernels and a 0.2 night-type mismatch factor. Prior masses two/eight are defaults; `--prior-masses` can specify explicit alternatives such as 0.25/0.5. These are modeling pseudo-observations, not calibrated Bayesian uncertainty estimates.

Every update form has a continuous version and a handoff version that returns the app forecast once forty resolved labels are available. The handoff depends on available sample count, not query index or realized current error. Predictions retain the planning bounds but do not add a residual-correction cap. Five existing combination policies compare all members with the app. The default panel has twenty-four individual forecasts and five combinations. An expanded four-prior panel retains the twenty-four unchanged individuals, adds twenty-four weaker-prior individuals and recomputes five combinations. Keep initial combinations in the experiment history and count unchanged individuals once. Every configuration scores all cases; cold/mature subgroups are explanatory only.

`research_sleep_cold_handoff.py --source <external-csv> --features <external-cache> --cold-result <external-report> --cold-model <model-key> --mature-result <external-report> --mature-model <model-key> --output <external-report>` composes two already-issued component forecasts at the same forty-resolved-label boundary. It verifies source/target lineage and records both result hashes and selected model keys. Component selection can be retrospective and must be reported as such; this does not supply independent future validation or make research dependencies production-ready. Unit and separate real-data prefix checks cover one-label formulas, hidden outcomes, exact mature handoff and composition. Private per-event results remain external.

## Online residual change points

`research_sleep_changepoints.py --source <external-csv> --features <external-cache> --baseline <issued-app-results> --output <external-report>` tests run-length filtering inspired by [Bayesian online change-point detection](https://arxiv.org/abs/0710.3742). The older sequence filter tracks fixed mixture states; it does not implement this run-length posterior. This independent adaptation models additive errors or logged ratios against the originally issued app forecast. Normal-inverse-gamma sufficient statistics give Student-t predictive components. Priors use mean zero, kappa 0.5, alpha two and beta chosen for predictive standard deviations sixty minutes or 0.75 log units. No run-length pruning or minimum sample threshold is used; unresolved/current labels never update a stream.

Global, last-night-type and four wake-role streams compare no-change controls with seven-/twenty-eight-day exponential hazard settings. The default paper-style convention resets after the observation, using the preceding elapsed gap as a step-hazard proxy; this proxy is not the same as a pure continuous-time calendar change process. `--reset-before` instead places a possible change in the elapsed interval before the next observation, scores that reset branch with the prior predictive, and updates its sufficient statistics with the observation. Its posterior conditions the change probability on that new evidence. Both use only labels available at the query, processed in stable arrival order, and an unobserved idle-interval mixture at forecast time. The first observation has no preceding elapsed interval, so its step hazard is zero.

Forecasts use component-location means or numerical roots of the full Student-t mixture CDF for predictive medians. In logged-ratio space, exponentiating the location mean gives a geometric center, not an arithmetic expected duration. No-change predictive distributions are symmetric, so their mean and median are one equivalent control rather than two configurations. Each timing panel has thirty individuals plus five combinations; the six no-change controls shared between panels are counted once, totaling sixty-four distinct configurations. Every configuration retains all scored cases and the same planning range. This is a general error-stream adaptation, not an infant physiology model or a replication of the paper's demonstration data.

Tests compare sufficient statistics with independent batch suffix formulas, densities/CDFs with SciPy, both reset conventions with exhaustive partition enumeration, and a synthetic shift with a no-change control. They also check constant post-reset mass, surprise-conditioned pre-reset evidence, calendar hazard composition, exact-minute role boundaries, hidden outcomes and query prefixes. Separate private full/prefix replays verify every forecast, normalization and default-convention preservation. Private per-event results stay outside source and app resources.

## Categorical residual alternative

`research_sleep_categorical_changes.py` takes the same external source, feature cache,
issued baseline, output and optional prefix limit arguments. It replaces the normal
observation model with a Dirichlet-categorical model over five-minute residual cells
from minus 480 to plus 480 minutes. A symmetric truncated Laplace prior has scale
sixty minutes and total pseudocount two or eight. Each resolved earlier residual
updates a full, unpruned run-length posterior. Reset occurs before the observation,
using its prior predictive likelihood, with no-change controls and calendar hazards
of seven or twenty-eight days. Streams are global, preceding-night, or four known
clock/nap roles. No current or unresolved label can update any stream.

The predictive distribution is uniform within each cell. Decisions minimize expected
absolute error through its exact median, or maximize probability within thirty minutes
through all piecewise-linear breakpoints, using the median-nearest tie break. Decisions
respect the existing one-to-480-minute planning bounds. These are independent
adaptations of [run-length filtering](https://arxiv.org/abs/0710.3742) and
[Dirichlet-categorical conjugacy](https://www.cs.ubc.ca/~fwood/teaching/C19_hilary_2016_2017/c19.pdf),
not published infant sleep formulas. Thirty-six raw candidates and five existing
past-only combination policies are compared on the same scored transitions.
Neutral checks enumerate all small partitions, verify the no-change conjugate
posterior, check median and coverage decisions against dense integration, demonstrate
synthetic shift adaptation, and isolate prefixes and unavailable labels.

## Changing conditional residual regressions

`research_sleep_regression_changes.py` uses the same external source, feature,
issued-baseline and output arguments, with an optional prefix limit. It tests
changes in regression coefficients as well as residual variance, rather than
independent scalar residual levels or cell probabilities. The general strategy is
inspired by [online change-point filtering](https://arxiv.org/abs/0710.3742) and
the conditional regression construction in [this methods paper](https://arxiv.org/html/2112.12899v2).
This is an independent scalar adaptation. It does not implement the latter paper's
multivariate response, outlier-removal mechanism or application-specific priors.

Two fixed pointwise designs use clock harmonics, age and missingness, or add
completed sleep/wake/feeding summaries, homeostat values and past timing summaries.
Non-clock numeric values use fixed tanh scales, missing values become zero plus
an indicator, and the non-intercept block is divided by the square root of its
dimension. No current target or future-query batch statistics enter these designs.
The designs have seven and thirty-three coefficients respectively.

Normal/inverse-gamma priors have zero coefficient means, intercept precision 0.5,
slope precision two or sixteen, alpha two and beta one-third. Residuals against
originally issued app predictions are modeled in sixty-minute units. Full
unpruned run-length hypotheses use exact rank-one conjugate updates. Reset is
before the newly available observation, scored with its prior predictive;
calendar hazards are disabled, seven days or twenty-eight days. Forecasts mix
the fresh prior over the idle interval since the last resolved outcome.

Predictive Student-t mixtures supply location means and numerical medians. The
symmetric no-change mean/median controls are counted once, producing twenty raw
forecasts plus five existing past-only combinations. All scored transitions and
the one-to-480-minute planning bounds remain. Tests compare every suffix's
statistics with independent batch regression, enumerate small partitions, verify
mixture CDFs, reproduce the scalar intercept-only model, exercise synthetic slope
changes, and isolate fixed designs, query prefixes and unavailable labels. Private
coefficients and forecasts remain external; the app receives no model changes.

## Heavy-tail observation filters

`research_sleep_robust_filter.py` takes the same external source, feature cache,
issued baseline and output arguments, with an optional prefix limit. It compares
ordinary normal, Laplace and three-degree Student-t observation likelihoods for
additive residuals. This differs from a conditionally normal likelihood whose
unknown variance merely produces Student-t predictive components. Conditional
observation standard deviations are matched at sixty minutes: normal scale sixty,
Laplace scale sixty divided by the square root of two, and Student-t scale sixty
divided by the square root of three.

Latent locations use a fixed one-minute grid from minus 480 to plus 480, with
discrete Laplace prior weights of scale sixty. A possible pre-observation reset
draws a fresh location from that prior. With fixed location hypotheses, run lengths
can be marginalized analytically: multiply the observation likelihood by
`(1 - hazard) * previousPosterior + hazard * prior`, then normalize in log space.
This is exact for the declared finite-location model; it is not an exact solution
for a continuous unknown location/scale model. No posterior pruning or removed
observations are involved. Calendar reset hazards are disabled, seven days or
twenty-eight days; global, last-night-type and four-role streams are separate.
Forecast queries mix the fresh prior over the idle interval without mutating state.

All fifty-four raw forecasts use either the posterior location mean or the
numerical median of the full predictive observation mixture. Five existing causal
combination policies complete fifty-nine configurations. Targets, bounds and
scoring are unchanged. Neutral tests check densities, CDFs and matched variances
against SciPy; enumerate every small reset partition; verify no-change batch
likelihoods; demonstrate reduced influence from one far observation and adaptation
to a sustained shift; and isolate queries, prefixes and unavailable labels.

This independent ordinary-Bayes likelihood experiment is motivated by the general
robustness issue discussed in [robust online change detection](https://arxiv.org/abs/2302.04759).
It does not implement that paper's generalized Bayes or diffusion score matching,
nor supply a published infant accuracy guarantee. The distribution definitions
follow the [Laplace](https://docs.scipy.org/doc/scipy/reference/generated/scipy.stats.laplace.html)
and [Student-t](https://docs.scipy.org/doc/scipy/reference/generated/scipy.stats.t.html)
reference formulas. All scored outcomes remain, including brief and unusual gaps;
private per-event results remain external.

## Interpretable behavior schedules

`research_sleep_behavior_schedule.py` compares a recent empirical timing baseline
with a separate return-to-sleep, nap and bedtime gate. It accepts external source,
features, issued baseline, output, optional zone and prefix limit arguments.
The gate is a depth-three classification tree fitted on twenty-eight days of
already-resolved labels, with seven-day weight half-life and eight-row minimum
leaves. At least twenty labels over five distinct dates are required; earlier
queries retain the app forecast.

Return labels cover gaps of twenty minutes or less and night-to-night transitions;
other daytime starts are naps and other night starts are bedtime proxies. These
are research labels, not confirmed caregiver intent. Since the imported night
classification may depend on the target sleep's end, its gate label is unavailable
until that sleep finishes. Future kind never selects the current forecast branch.

Completed daytime timer segments separated by no more than twenty minutes inform
a logical nap ordinal. Current completed segment length, episode sleep total and
segment count are also available to the gate. This only summarizes past cycles:
individual timer starts remain distinct forecast targets and every scored case
remains in the denominator. All eleven input features are available at wake.

Five- and fourteen-day component windows learn empirical gap distributions with
fixed recency, clock, episode-duration, night-type and nap-ordinal weights. Sparse
branches back off to the gate's twenty-eight-day history. Each window compares a
pooled empirical median, hard-routed gap medians, hard routing with a bedtime clock
distribution, and a median of the probability-weighted branch distributions.
Bedtime clock offsets use the nearest signed circular difference and the original
one-to-480-minute bounds. This transparent strategy is an independent experiment;
it is not a reconstruction of any proprietary prediction formula.

Tests verify that prior nap segments inform ordinals without merging targets,
delay type labels to their actual availability, and isolate prefixes and unresolved
labels. Private source data, per-event outputs and detailed behavior audits remain
outside the repository and app resources.

## Loss-based brief-return decisions

`research_sleep_return_decision.py` tests the brief-nap-return problem while
retaining the issued app forecast elsewhere. Eligible queries follow a completed
nap, fall between 06:00 and 21:00, and have an issued gap over twenty minutes.
All ineligible queries retain the app prediction and remain in the full score.
This is a component experiment; it does not redefine the overall accuracy goal.

Each original wake freezes an alternative short-return point: an ordinal-weighted,
seven-day-half-life median of already-known eligible gaps at most twenty minutes
over twenty-eight days. At least three such labels are needed; otherwise the
fixed research prior is eight minutes. No later outcome recomputes that earlier
alternative. The target is the app's realized absolute loss minus the alternative's
realized loss, with optional thirty-minute-miss penalty thirty. Positive predicted
expected benefit selects the return point. This independently adapts the general
[cost-sensitive decision principle](https://scikit-learn.org/stable/auto_examples/model_selection/plot_cost_sensitive_learning.html),
without reproducing a proprietary algorithm or claiming future accuracy.

Depth-three squared-error trees with twelve-row leaves and ridge regression with
penalty ten compare the eleven episode-context inputs plus both issued points,
against those inputs augmented by frozen recent-return behavior. The latter uses
five-/fourteen-day weighted rates for global, ordinal, episode-duration and local
clock/duration histories, their effective counts, and the last three available
eligible outcomes. Rates have pseudocount one over five; this is regularization,
not a measured infant prior. Ridge standardization uses training data only.
Thirty prior eligible labels within twenty-eight days are required, sample weights
have seven-day half-life, and refits occur at eligible queries after eight overall
query indices. Two feature sets, two learners and two loss definitions produce
eight matched configurations.

Gap labels become available when the next timer starts; future sleep kind is not
used by this decision. Earlier script-derived type labels remain only for source
alignment, while current completed episode information is known at wake. Tests
verify loss arithmetic, frozen alternatives/history, prefix and unavailable-label
isolation, a neutral learnable decision, and unchanged ineligible queries.
Diagnostics separate corrected brief returns from switches on longer wake periods,
new/lost thirty-minute hits and net minutes saved. Private outputs remain external.

## Prior cycles in the brief-return decision

`research_sleep_return_cycles.py` adds `--control-result <issued-return-decision-report>`
to the original source/feature/baseline/output/zone/prefix arguments. It reproduces
all eight original return-decision controls exactly, then compares the same learner,
action points, eligibility, losses, training windows and refit cadence with three
preceding completed sleep/wake cycles added. The current completed sleep remains
in the original context and is not counted as an extra prior cycle.

Each previous sleep supplies its duration, the following already-completed awake
gap, sine/cosine of its wake clock, a simple completed clock/night flag and a missing
indicator. Eighteen fixed features preserve lag order. Only history completed at
the current wake within seven days is considered. A negative gap stops older links
and fills missing indicators; it does not exclude a scored forecast or change any
timer-start target. Source sorting and completed end times follow the replay reader.
This clock/night feature is a simple known-history descriptor, not confirmed intent.

Both original core and personal-rate feature blocks are compared with the added
cycles, for trees/ridge and both loss definitions. All eight controls are retained
as verified references, and only eight new configurations enter the progress count.
Tests check manual cycle durations/gaps, future records, missing/overlapping links,
query prefixes and unavailable labels, plus a neutral example where the added lag
information improves a decision. These cycle features were motivated by a prior
archive audit, so retrospective differences are post-selected rather than independent
future validation. Private inputs, detailed controls and per-event outputs stay external.

## Additive median timing curves

`research_sleep_timing_curves.py` takes external source, feature, issued-baseline
and output arguments with optional zone/prefix limit. It learns timing points
directly, or residual corrections, instead of choosing between two fixed points.
Fixed additive linear spline components cover age, periodic wake clock, completed
episode sleep duration and logical nap ordinal. Additional fixed linear terms
cover segment length, segment count, preceding night type, previous awake gap and
six-/twenty-four-hour sleep totals. These are known at the forecast wake; future
sleep type never selects a curve.

Weighted mean absolute residuals are minimized with L1 penalties on hinge slope
changes and cyclic clock second differences. Small slope/coefficient penalties
regularize otherwise unobserved directions. Sparse HiGHS dual-simplex fits must
succeed with finite coefficients and equality error at most `1e-6`; cases are not
dropped on a solver failure. Alpha 0.05/0.5 compares two regularization strengths.
There is no imposed monotonic age rule: observed night-return and daytime trends
can differ. Linear age/duration hinges extrapolate their fitted terminal slopes;
the clock basis is exactly periodic.

Pooled fits compare with four independently fitted, known wake contexts: 21:00–06:00,
a preceding-night wake before noon, other daytime wakes before 16:00, and remaining
late-day wakes. A third design jointly fits a shared base and four context-deviation
curves. Deviations have four times the base curvature penalty plus 0.1 times their
coefficient L1 norm, including offsets. Zero deviations exactly recover the pooled
model and its penalty. This is penalized partial pooling, not a Bayesian hierarchy.

Training uses at most eighty-four days, fourteen-day recency
half-life, twenty resolved labels per context and refits after twenty-four query
indices. Earlier queries keep the issued app point. Pooled/independent/shared,
direct/residual and two penalties give twelve matched forecasts, retaining all targets
and one-to-480-minute bounds.

This independently combines the [additive regularization principle](https://www.stat.cmu.edu/~ryantibs/papers/additivetf-aos.pdf)
with [absolute-loss conditional-median regression](https://scikit-learn.org/stable/modules/generated/sklearn.linear_model.QuantileRegressor.html).
Fixed coarse knots and absolute loss differ from the cited paper's full adaptive
trend-filtering estimator. No theoretical infant accuracy or commercial formula
is implied. Tests check the optimizer against independent quantile regression,
weighted-median constants, periodic/fixed bases, context boundaries, prefixes and
unavailable labels. Private age/ordinal summaries and forecasts remain external.


## Distinct nap and bedtime planning

`Scripts/research_sleep_planning.py` changes the research objective to the next distinct nap or bedtime. The primary cohort contains next-timer gaps over 20 minutes, excluding night-to-night resettling. Brief returns and longer night-to-night gaps remain in separate diagnostics, and every wake receives an issued forecast. The next timer is never skipped or relabeled as a later target. Sleep kind follows the external converter's timing/continuity inference.

Matched pooled and wake-context forests differ only in whether they train on all resolved transitions or resolved planning transitions. A separate experiment learns nap intervals and bedtime clock times, with a wake-known classifier choosing the point. Training membership and inferred kind become usable only when the target sleep has ended. Models use a 60-day sliding history, at least 40 eligible labels and a 24-query refit cadence; insufficient history retains the supplied app forecast. Extra completed-episode features describe only interruptions already observed.

```sh
python3 Scripts/research_sleep_planning.py \
  --source /path/to/history.csv --features /tmp/features.npz \
  --baseline /tmp/app-replay.json --output /tmp/planning-replay.json
```

Reports distinguish `planning`, `naps`, `bedtime`, `briefReturns`, `nightReturns`, and `allTimers`. A plot rebased to the planning cohort must not reuse the all-timer accuracy line without rescoring every point. These exploratory models do not change the production prediction engine. A planning-only forecast should not be substituted for overnight resettling behavior without a separate integration policy.

`Scripts/SleepReplay/PlanningReplay.swift` replays the selected pooled planning learner using the app's actual reference forest. Compile it with `LittleWindows/Services/ReferenceSleepForest.swift`, then use `Scripts/check_sleep_planning_native.py` with `--source`, `--features`, `--baseline`, `--research`, `--executable`, and `--output` for a full chronological comparison. This verifies numerical parity, separately from app integration and iOS validation. The replay tests cover the 20-minute boundary, resolved-label eligibility, current/future outcome isolation, and prefix stability.

### Planning curves, recent patterns, and warmup

`research_sleep_planning_curves.py` fits the existing fixed additive age/clock/episode/nap-order design using only resolved planning labels. It compares pooled curves with shared curves and shrunk wake-context deviations, either predicting the interval directly or correcting the originally issued planning forest. The two penalty strengths are fixed before replay. Fits use 84 days, a 14-day weight half-life, at least 20 resolved planning labels and a 24-query cadence. This is an absolute-loss fixed-knot adaptation inspired by additive trend filtering, not the source paper's full estimator or an infant-specific accuracy guarantee.

`research_sleep_planning_history.py` adds 20 summaries frozen at each original wake: counts, recent intervals, and target clocks among previously resolved planning transitions. It compares compact inputs with a supplied completed-care feature matrix. Current target gap/kind never enters its features. Target clocks are unwrapped relative to the known current wake; historical training rows retain their own originally computed summaries. Both forests keep the planning replay's original 60-day window, minimum 40 labels, and refit cadence.

`research_sleep_planning_warmup.py` tests earlier personalization while preserving every mature planning forecast. Before 40 resolved planning labels in 60 days it uses either a recent weighted median after three labels or the supplied pooled direct age curve after 20 labels. Warmup versus mature selection depends only on resolved historical counts. This explicitly tests initial learning rather than discarding early records from the accuracy score.

All three accept `--source`, `--features`, `--baseline`, `--planning`, `--output`, and optional `--limit`. The curves runner also takes the preserved planning result as its correction/fallback; the history runner additionally requires `--complete`, and the warmup runner requires `--curves`. Keep result JSON files outside the repository. A 200-query independent prefix and full-target/source checks should precede updating progress charts. Archive-selected mean-error gains that worsen 30-minute coverage are tradeoffs; do not describe them as unqualified accuracy upgrades.

### Nap / bedtime distribution mixtures

`Scripts/research_sleep_planning_mixture.py` tests whether retaining uncertainty over the next sleep type improves timing. The classifier uses wake-known features, while separate forests learn nap intervals and bedtime intervals or clocks from resolved planning examples. Forest leaf weights form each conditional distribution; classifier probabilities mix their mass. The issued point is either the mixture median or the minimizer of expected absolute error plus a fixed 30- or 90-minute penalty for missing by more than 30 minutes. These penalties are research objectives, not confidence intervals. The latter optimizer checks sample knots and coverage endpoints in the allowed action range, using sorted cumulative mass; tests compare it with an exhaustive independent minute grid and check inclusive 30-minute boundaries.

The runner takes `--source`, `--features`, `--baseline`, `--planning`, `--warmup`, `--output`, and optional `--limit`. All six candidates retain the supplied warmup forecasts exactly. The hard type-selection control must exactly reproduce the original planning experiment before results are written. Every training row's type becomes available only after its target sleep ends; the next actual type never selects a current forecast. Tests cover normalized forest mass, existing median parity, mixture arithmetic, unavailable labels, current/future outcome isolation and prefix stability. Compare mean error and 30-minute coverage separately; a lower mean with lower coverage is a tradeoff. Hindsight choice between the two already-issued component points is only an analysis of that particular action set and is never a forecast or a bound on other models.


### App planning integration

The app's v8 preparation uses `PortableSleepPlanning.swift` for daytime wakes (06:00 through 20:59) once 40 completed distinct planning labels are available. It reconstructs the same 60-day / 24-query fitting cadence from the immutable feature rows, fits the latest required forest once, and appends completed-episode minutes, segment count and logical nap order to the compact inputs. This preserves cadence after restart or history edits without replaying every historical forest fit. The existing combined learner continues to supply sparse-history and overnight forecasts. Profile selection, prediction exclusions, custom baselines, running timer suppression and background-generation checks remain with the existing coordinator and engine.

Use the full Swift runner and optional iOS parity test to evaluate the app policy; its overnight forecasts can differ from an unrestricted all-hours research model. Report the frozen distinct-planning cohort alongside all-timer and brief-return diagnostics. Compare the actual new app output with the preserved prior app output, and verify unchanged overnight points, windows and confidence. An independent chronological prefix must retain the same issued forecasts. The algorithm-version change invalidates old prediction cache keys; it does not rewrite resolved prediction records.


The planning fit is retained between preparation calls when the selected fit origin, full training feature matrix, and target vector still match. Missing values compare as missing rather than forcing a refit. A new fit origin or any changed training input clears reuse. The cached forest is value-only, profile-scoped through the coordinator, and never persisted; clearing memory or rebuilding an edited history produces the same forecast. The existing background-generation check still decides whether a result may be published.

### Planning-only boosting and five-day diary experiment

The research_sleep_planning_boost.py runner compares six fixed candidates against the current app replay. Histogram boosting and LightGBM use absolute-error loss, 200 iterations, seven leaves, a 60-day training window, 14-day recency weights, 40 resolved planning labels and a 24-query refit cadence. Each learner compares compact28 inputs with an additional69 diary features. Training columns that are entirely missing are dropped based only on the current training set and retained as that selection until refit. Remaining missing values use the learner's own handling. All fitting and prediction is single-threaded.

The diary representation aligns recent intervals by six known logical nap positions (position5 pools later positions). It includes previous-five-calendar-day and yesterday summaries, completed night/day anchors and counts. Calendar-day membership uses the selected zone and night duration uses elapsed time across daylight-saving changes. Two additional controls fit separate LightGBM models by position with at least20 within-position labels, or use the five-day same-position mean after three observations. All six retain the actual app's sparse-history and overnight forecasts. Current outcome type never selects a model.

    python3 Scripts/research_sleep_planning_boost.py --source /path/to/history.csv --features /tmp/features.npz --baseline /tmp/app-replay.json --output /tmp/planning-boost.json

LightGBM is an optional research-only dependency. On macOS it requires an available OpenMP runtime; set the process library path to an existing compatible runtime if the wheel cannot locate one. Neither research library nor fitted models are app dependencies. The implementation independently tests ideas from public application US20250292903A1. Its population-trained weights and expert fallback tables are unavailable to this experiment. The study retains every archive query, reports the frozen planning cohort, checks an independent chronological prefix and preserves original controls when adding candidates. A negative result does not establish the accuracy of another product.

### External diary transfer experiment

The research_sleep_planning_transfer.py runner tests a separately obtained age-grid diary as a prior. It accepts 96 quarter-hour clock rows with contiguous age-day columns, sleep marked S, awake/feed marked E and awake marked by an empty cell. Other annotations interrupt known history. Sleep runs touching an unknown state or file edge are censored; examples require 48 hours of preceding known states. Only distinct resolved nap/bedtime examples train the external model. This format corresponds to one diary described in the methods of DOI 10.1371/journal.pcbi.1012541. That study fits seven-day sleep probabilities in half-hour bins; its results do not establish next-timer forecast accuracy.

Keep the original diary, its supplied MIT license and source provenance outside the repository. This runner neither downloads data nor redistributes it. Sleep-only inputs omit feeding features whose logging conventions differ. Four fixed candidates compare the external model alone, a matched personal-only control, personal residual learning over the external model, and a pooled model with external examples within 21 age days carrying total weight equivalent to 20 personal examples. Personal fits use the existing 60-day, 40-resolved-label, 24-query cadence with a 14-day recency half-life. The external dataset is independent of the evaluated child; all its labels can be available before deployment. Personal labels remain unavailable until their target sleep ends.

    python3 Scripts/research_sleep_planning_transfer.py --source /path/to/history.csv --features /tmp/features.npz --baseline /tmp/app-replay.json --donor /tmp/external-diary.csv --license /tmp/external-LICENSE --output /tmp/transfer-replay.json

All candidates preserve supplied app points outside daytime wakes and the external diary's observed age range. The primary score still includes every original planning case, including those unchanged points. Use an independent prefix long enough to include the external age range, verify unchanged overnight points and source hashes, and report mean error and 30-minute coverage separately. A single coarse diary is not a population dataset or two-minute timing ground truth. These research candidates do not change app behavior.

### Mechanistic banks fitted to distinct planning transitions

The research_sleep_planning_mechanistic.py runner reuses the original two-process threshold-crossing bank and the independently verified completed-history six-state observer outputs. It changes the fitting population to past resolved distinct nap/bedtime labels. Current target type never chooses a member. Global or clock/duration-local absolute loss selects a member at each wake, with the same 60-day history, 14-day recency half-life and minimum 40 labels. Local weighting requires effective sample size at least eight. Overnight and sparse-history app points are preserved.

Two additional blends fit a convex weight between originally issued app points and local two-process points. The constrained absolute-error optimum is a clipped weighted median of historical residual-to-forecast-difference ratios, weighted by recency and absolute forecast difference. The local variant adds the same wake-clock/duration weighting. The fit uses only resolved past errors; it never substitutes newly refitted predictions for previously issued training points.

    python3 Scripts/research_sleep_planning_mechanistic.py --source /path/to/history.csv --features /tmp/compact.npz --complete /tmp/complete.npz --baseline /tmp/app-replay.json --observer /tmp/verified-observer.json --output /tmp/mechanistic-planning.json

The runner validates raw archive, native core, observer, feature cache, native input and state hashes before reuse. It regenerates the completed-history native inputs to ensure that they match the recorded state lineage. This tests a new causal fitting objective; it does not refit the published model's latent initial conditions, light exposure or physiological parameters continuously. An independent chronological prefix, fixed-cohort rescore and current app source hash check are required before charting results. Lower mean error accompanied by lower 30-minute coverage remains a tradeoff rather than an unqualified upgrade.

### Continuous reduced pressure fit

The research_sleep_planning_pressure_fit.py runner tests continuous fitting rather than a fixed parameter bank. PlanningPressureFit.cpp integrates a normalized pressure state from the completed raw sleep union: exponential accumulation toward one while awake and decay toward zero while asleep. The initial pressure is 0.5 at the first observed sleep start. It fits two log time constants plus the intercept and sine/cosine coefficients of a daily onset threshold, clipped to [0.01, 0.99]. The phase advances by elapsed minutes from the known local wake clock. This is an independent reduced-model adaptation, not a reproduction of the full neuronal model or an estimate validated against measured physiology.

    xcrun clang++ -O3 -std=c++17 -dynamiclib Scripts/SleepReplay/PlanningPressureFit.cpp -o /tmp/planning-pressure-fit.dylib
    python3 Scripts/research_sleep_planning_pressure_fit.py --source /path/to/history.csv --features /tmp/compact.npz --baseline /tmp/app-replay.json --binary /tmp/planning-pressure-fit.dylib --output /tmp/pressure-fit.json

Two direct candidates optimize absolute timing error or absolute error plus a fixed 30-minute penalty for misses beyond 30 minutes. Each uses 60 days of past resolved planning labels, a 14-day recency half-life, at least 40 labels and a 24-query refit cadence. Bounded Powell optimization retains the best evaluated point, including the previous fit and neutral starting point, with at most 400 optimizer evaluations. Nonconverged fits are counted explicitly; no global optimum is claimed. Two additional candidates blend the originally issued absolute-loss forecasts with app points using the previously described past-error convex fit, globally or with local context weights.

The native core only integrates the raw prefix ending at the requested historical wake. Overlapping intervals contribute their union once; future records cannot change that state. Onset is the first crossing detected in one-minute brackets, with sub-minute linear interpolation. Tests compare native states and forecasts with independent analytic pressure calculations and a fine-grid/root reference, and cover overlapping records, future history removal, chronological prefixes, unresolved labels and overnight fallback. Use an independent 1,200-query prefix and frozen-cohort/hash audit before charting results. These research files have no app target membership and do not alter stored care records.

### Neutral local-clock initialization of the neuronal observer

The research_sleep_planning_entrained.py runner isolates the observer's starting-state assumption. NeuralSleepEntrainedObserver.cpp shares the existing six-state equations, but initializes the slow states from a 56-day neutral simulation under an assumed daily wake interval from 07:00 to 19:00. It samples the resulting daily trace at the known local clock at the beginning of each completed-history window. The same seven days of completed sleep union then force the slow states, and the full model is released from an awake state at the query. The neutral schedule is an explicit assumption; it is not a future record, a measurement, or a fitted individual circadian phase. The upstream example's four-week transient warmup motivated this initialization check; this fixed-schedule initialization is a separate adaptation.

    xcrun clang++ -O3 -std=c++17 Scripts/SleepReplay/NeuralSleepEntrainedObserver.cpp -o /tmp/initialized-observer
    python3 Scripts/research_sleep_planning_entrained.py --source /path/to/history.csv --features /tmp/compact.npz --baseline /tmp/app-replay.json --binary /tmp/initialized-observer --output /tmp/initialized-replay.json

Four candidates use global or clock/duration-local member selection on resolved planning labels, or global/local past-error convex blending of the originally issued local observer points with app points. They preserve the existing daytime/sparse-history/overnight policy and the complete primary evaluation cohort. Tests independently integrate neutral warmup, observed forcing and released onsets with SciPy Radau, compare half-step results, check calendar-phase consistency and native prefix equality, and cover unresolved/current/future labels in the selection and blending stages. Numerical agreement verifies the implementation of the assumed model, not the accuracy of the assumptions about an infant. Keep native inputs, states and forecasts outside the repository.

### Personal schedule clock from completed sleep occupancy

The research_sleep_planning_phase_clock.py runner estimates an empirical schedule phase from the completed sleep union in the last seven elapsed days. It integrates the first circular clock-time moment exactly, weighted with a three-day recency half-life. Integrals split at local UTC-offset changes so daylight-saving transitions use actual elapsed duration and the correct local clock. At least three observed calendar days and three elapsed days are required; earlier queries retain the wall clock. A zero phase is used when no estimate is available, with availability recorded as a separate input. The estimate is not a measured physiological circadian phase.

Four new candidates append the phase information to existing inputs, replace clock harmonics with phase-relative harmonics, or predict an unwrapped future clock coordinate using wall-clock or phase-relative anchors. The clock targets are the known wake coordinate plus the observed interval; they do not expose a current target as an input. Historical phases and anchors remain frozen at their own original wakes. Every forest keeps the original 80-tree, minimum-leaf-five, 60-day, minimum-40-label and 24-query fitting policy. The matched unmodified interval control must reproduce the actual app points within 1e-6 minutes before the report can be written. Sparse-history and overnight points remain the app's original values.

    python3 Scripts/research_sleep_planning_phase_clock.py --source /path/to/history.csv --features /tmp/compact.npz --baseline /tmp/app-replay.json --output /tmp/personal-phase.json

Tests compare exact moments with independent one-second integration, include Pacific daylight-saving changes, and verify completed-only history, future-history removal, target isolation, prefix stability and overnight preservation. Keep the phase array beside the private report outside the repository. Require an independent 1,200-query phase/forecast prefix and fixed-cohort rescore before updating plots. Tiny retrospective gains whose day-block uncertainty includes no improvement do not establish an app upgrade or performance on another child.

### Unexpectedly late planning-start experts

The research_sleep_planning_late_errors.py runner tests whether a dedicated model can detect next-sleep starts more than 30 minutes later than the originally issued app point. It adds that issued point to the compact/episode inputs. A matched pooled residual forest supplies the control. Two conditional residual forests learn ordinary and late-start errors, with at least 20 resolved examples in each group. Two classifiers select between these experts with ordinary or inverse-frequency-balanced class weights. A fourth candidate mixes the unweighted classifier's conditional leaf distributions and minimizes absolute error plus a fixed 30-minute miss penalty. Balanced classifier outputs are cost-weighted scores, not calibrated event probabilities.

    python3 Scripts/research_sleep_planning_late_errors.py --source /path/to/history.csv --features /tmp/compact.npz --baseline /tmp/app-replay.json --output /tmp/late-start-experts.json

All training uses only resolved planning labels in the preceding 60 days, a minimum of 40 labels, and a 24-query refit cadence. Every gate and residual model has 80 trees, minimum leaf five and maximum feature fraction 0.8. Current realized error never chooses a forecast. Sparse histories, unavailable conditional experts and overnight queries retain the existing app points. The report scores the full original cohort, records gate confusion only after outcomes resolve, and stores private scores and component points beside the report. A separate true-class hindsight diagnostic estimates the limitations of these particular two component points; it is explicitly not a forecast, a new candidate, or a bound on other algorithms. Check an independent 1,200-query prefix for scores, component points and all issued forecasts, and preserve initial candidate vectors when adding diagnostic output. Research candidates do not modify app behavior or recorded care data.

For a matched broader-context comparison, supply the completed-history complete feature cache with `--design complete`. This changes the input columns only; expert definitions, fitting cadence, sample minimums, gates and decision rules are identical. The report records the supplied design and feature names. With the current caches, 99 supplied features plus three episode values and the issued app point produce 103 model inputs, compared with 29 for compact inputs. Verify all shared feature columns and target/index/wake arrays match, preserve the original compact reports and replay their forecasts exactly before attributing differences to broader context. The complete representation includes additional completed-care recency, counts, durations and sleep-history summaries; it does not imply that every raw text field is used.

### Recent completed-day wake roles and nap-count transitions

The research_sleep_planning_day_roles.py runner independently tests schedule-pooling ideas from a public implementation, without reproducing that app's morning resolver, caregiver choices, sleep-duration filters or bedtime safeguards. It uses up to seven previous local calendar days within a 14-day lookback. A historical day qualifies only after a bedtime planning label has resolved and its observed logical nap count is at least one; at least three qualifying days are needed. Current-day outcomes never establish a completed training day. Historical nap windows must belong to the same local date as their target nap. These are training rules only; every original evaluation case remains in the score.

    python3 Scripts/research_sleep_planning_day_roles.py --source /path/to/history.csv --features /tmp/compact.npz --baseline /tmp/app-replay.json --output /tmp/day-roles.json

Four fixed candidates compare ordinary nap-order medians, medians with a shared role before the last nap, a weighted median over the recent empirical nap-count distribution, and a separate historical bedtime-clock anchor. The modal nap count uses the most recent tied count. It is inferred from completed historical days, never from the current day's eventual number of naps. This simple method can learn before the app's usual 40-label warmup; sparse histories and overnight queries otherwise retain app points. Tests cover manual role arithmetic, ties, current/unresolved outcome isolation, future nap-count isolation, chronological prefixes, minimum support and history expiry. A new outcome range from an aggressive anchor is not evidence of improved accuracy. Report performance as this independent adaptation, not as another app's measured accuracy.

### Delayed expert tracking for planning

The `research_sleep_planning_tracking.py` runner compares static multiplicative weighting with off-diagonal fixed sharing from [Tracking the Best Expert](https://mwarmuth.bitbucket.io/pubs/J39.pdf). Members are originally issued app, bedtime-clock risk mixture, and phase-aligned interval points. Each resolved planning outcome updates weights once in target-completion order. A fixed learning scale of 60 minutes and share rate of 1/28 compare global tracking with three known-wake contexts. The first eight resolved labels are warmup; overnight queries retain the app point. Absolute-loss and absolute-loss-plus-30-minute-miss-penalty variants use weighted mean forecasts. The latter nonconvex loss does not inherit the paper's convex-loss guarantees. Members were selected retrospectively; causal replay is not prospective validation.

    python3 Scripts/research_sleep_planning_tracking.py --source /path/to/history.csv --features /tmp/compact.npz --baseline /tmp/app.json --mixture /tmp/mixture.json --phase /tmp/phase.json --output /tmp/tracking.json

Keep private results outside source. Verify independent prefix equality and unchanged overnight points. Tests cover the multiplicative/share arithmetic, delayed and current/future outcome isolation, prefix invariance, and context-specific weight changes. The runner changes no app behavior or recorded history.

### Morning-relative elapsed and cumulative awake targets

The `research_sleep_planning_morning_budget.py` runner tests a different regression target with matched inputs and training rules. The latest completed overnight end before local noon anchors the observed day. Four features describe that morning clock, elapsed time, completed sleep union minutes, and cumulative awake minutes since the anchor. The three models predict either the next wake gap directly, total elapsed time at the next sleep start, or total awake time at that start. The latter two subtract the known elapsed or awake time to recover the next gap. No fixed physiological awake budget is imposed.

    python3 Scripts/research_sleep_planning_morning_budget.py --source /path/to/history.csv --features /tmp/compact.npz --baseline /tmp/app.json --output /tmp/morning-budget.json

Every model uses the same 60-day resolved planning history, minimum 40 anchored examples, 24-query refit cadence, and 80-tree leaf-five forest. Missing anchors and overnight queries retain the app forecast; all original evaluation cases remain. Overlapping completed sleeps count once in the sleep union. Tests verify manual elapsed/awake arithmetic, missing anchors, daylight-saving elapsed time, unresolved/future history isolation, real-forest prefix equality, and target translation. Reports and feature arrays remain private and outside source. These are retrospective empirical comparisons, not measured sleep-pressure models or prospective accuracy evidence.

### Planning-only sleep onset hazards

The `research_sleep_planning_hazard.py` runner compares a binary next-sleep hazard with separate nap and bedtime hazards sharing a still-awake class. Unlike earlier all-transition hazard trials, it trains only resolved distinct-planning intervals and uses a one-minute grid from 21 through 480 minutes. Each interval contributes still-awake rows until its recorded next timer start, followed by one event row. Current query inputs contain origin context, elapsed awake time, projected clock phase, and deterministic continued-awake homeostatic features; future care records never enter a curve. Nap versus bedtime is a historical training label, never a supplied current outcome.

    python3 Scripts/research_sleep_planning_hazard.py --source /path/to/history.csv --features /tmp/compact.npz --baseline /tmp/app.json --output /tmp/planning-hazard.json

Both fixed histogram classifiers use log loss, 150 iterations, 15 leaves, minimum leaf 30, and L2 penalty 10. They use the same 60-day resolved planning history, minimum 40 labels, and 24-query refit cadence. Survival-weighted event mass produces either its median or the existing expected-absolute-error-plus-30-minute-miss-penalty decision. Remaining tail mass is placed at the 480-minute support endpoint. This conditional planning distribution does not estimate short-return probability. Sparse and overnight queries retain app points, and every original evaluation case remains. Tests cover exact event exposure, future phase, probability conservation, event-label permutations, real-classifier prefix invariance, unresolved/current/future outcome isolation, and overnight fallback. Private per-event outputs stay outside source; this is an independent empirical model rather than a published infant accuracy claim.

### Planning-conditioned pretrained tabular prior

The `research_sleep_planning_prior.py` runner reuses the existing local TabPFN-v2 weights with compact inputs plus the three completed-episode values. Unlike the earlier all-transition prior benchmark, only resolved distinct-planning labels enter its 60-day history. It requires 40 labels, refits every 24 valid wake origins, and supplies each current query individually. The three reported actions are the model's mean, median and mode. Sparse and overnight queries retain app points, with all original evaluation cases retained. This is a general tabular prior, not an infant-specific pretrained sleep model.

    HF_HUB_OFFLINE=1 python3 Scripts/research_sleep_planning_prior.py --source /path/to/history.csv --features /tmp/compact.npz --baseline /tmp/app.json --bootstrap /tmp/local-bootstrap-check.json --output /tmp/planning-prior.json

The runner requires the previously verified cached weights and offline mode; no history is sent to hosted inference. It explicitly requests v2 with eight estimators, two CPU threads, cached fitting, and seed 42. Bootstrap weight hashes are verified before inference. Keep forecasts and private data outside source. Tests cover label eligibility and maturity, single-query calls, history expiry, sparse/overnight fallback, current/future outcome isolation, prefix invariance, and failing on nonfinite output rather than dropping evaluation cases. Validate an independent real-model chronological prefix as well as the injected-model unit tests. Retrospective model selection is not prospective validation, and research weights are not bundled into the app.

### Local TabICLv2 planning prior

The `research_sleep_planning_tabicl.py` runner tests the authors' general synthetic-data pretrained regression model from [TabICLv2](https://arxiv.org/abs/2602.11139). It uses compact inputs plus three completed-episode values, resolved distinct-planning labels only, a 60-day history, minimum 40 labels, and a 24-query refit cadence. Each current query is issued separately using training-only KV caches. The reported actions are mean and median; no unsupported mode is invented. Sparse and overnight queries retain the existing app points, and the full original evaluation cohort remains.

    HF_HUB_OFFLINE=1 python3 Scripts/research_sleep_planning_tabicl.py --source /path/to/history.csv --features /tmp/compact.npz --baseline /tmp/app.json --bootstrap /tmp/local-tabicl-bootstrap.json --output /tmp/planning-tabicl.json

Use the locally cached, hash-verified `tabicl-regressor-v2-20260212.ckpt` weights, eight estimators, CPU with two threads, seed 42, KV caching, and full precision. Automatic downloads are disabled during private inference. The neutral bootstrap checks finite predictions and exact repeat-query behavior after an intervening query; it does not measure sleep accuracy. Tests cover single-query calls, resolved planning-label eligibility, current/future outcome isolation, chronological prefix invariance, history expiry, sparse/overnight fallbacks, and failing on invalid output without dropping cases. Also validate an independent real-model prefix. Code, public weights, dependencies, and private results remain outside app resources. These are retrospective comparisons with a general table model, not infant-specific pretraining or prospective accuracy evidence.

### Personal gradient adaptation of the tabular prior

The `research_sleep_planning_adaptation.py` runner compares a frozen, zero-epoch TabICLv2 control with personal adaptation of its in-context prediction layers. Column and row encoders stay frozen. The authors' pinball-loss training uses up to 30 epochs, AdamW at 1e-5, gradient clipping at one, two training/validation estimators, and eight final inference estimators. Training remains local, starts from the public checkpoint at each refit, and writes no personal model checkpoints or hosted logs.

The latest 20% of resolved labels (at least eight) form a chronological validation set. Earlier training labels are purged if their outcomes had not matured at the first validation wake. Single-query median MAE selects the baseline or a later epoch, with patience eight. Both controls retain the same older-training imputer, then expand their final context to all currently resolved labels. The wrapper preserves the selected model object during expansion: calling the finalized inner estimator's normal `fit` would reload public weights in the tested API and discard adaptation. A neutral-data probe verifies selected-weight hashes before/after expansion and actual changes from gradient training.

    HF_HUB_OFFLINE=1 python3 Scripts/research_sleep_planning_adaptation.py --source /path/to/history.csv --features /tmp/compact.npz --baseline /tmp/app.json --bootstrap /tmp/local-tabicl-bootstrap.json --output /tmp/planning-adaptation.json

The outer replay uses the same 60-day planning-label history, minimum 40 labels, 24-query refit cadence, individual current queries, and sparse/overnight app fallback. All original cases remain. Tests cover chronological validation/purging, full-known context expansion, preservation of selected weights, resolved-label eligibility, current/future outcome isolation, prefix invariance, support expiry and invalid-output failure. Run the neutral gradient/weight-preservation probe before private inference and independently replay a chronological prefix. Private arrays, outputs and any optional checkpoints must stay outside source. This independent wrapper uses non-public methods in the tested TabICL API; it is a research experiment, not app integration or prospective validation.

### Regular minute-state forecasts and next-start decoding

The `research_sleep_planning_regular_state.py` runner gives the frozen recurrent prior a regularly spaced recorded sleep/wake history. Each minute is one or zero according to the union of completed sleep timers, including start boundaries and excluding end boundaries. The history ends at the current observed wake, where the state is zero. Up to 2,048 minute samples enter the model; no awake history is invented before the first completed record. Two variants use state alone or add deterministic wall-clock sine/cosine for historical and future minutes.

    HF_HUB_OFFLINE=1 python3 Scripts/research_sleep_planning_regular_state.py --source /path/to/history.csv --features /tmp/compact.npz --baseline /tmp/app.json --control /tmp/planning-care-pretraining.json --model /tmp/local-model --bootstrap /tmp/public-bootstrap.json --horizon-bootstrap /tmp/public-horizon-bootstrap.json --runtime /tmp/local-runtime --output /tmp/planning-regular-state.json

The native checkpoint supports 320 forecast steps per call. To cover all 480 future minutes, forecast 320 steps, append only the clipped predicted median states, retain the latest context and forecast another 160 steps. Known clock covariates remain aligned through this extension. No actual future sleep state enters either request. Decode the first predicted numeric median at least 0.5, or 480 minutes when there is no crossing. Numeric state medians are not calibrated sleep probabilities, and this decoder is not guaranteed to produce the conditional median onset time.

Before private inference, require the existing neutral bootstrap plus a public-only full-horizon probe using this exact adapter, with repeated/cross-mode and short-context checks. Tests cover overlapping timer unions, exact start/end edges, physical removal of future/unfinished records, one-minute sleep sessions, autoregressive use of predicted states only, current-minute wake alignment, Pacific daylight-saving covariates, finite trajectories and prefixes. A separate representation audit reconstructs recorded starts from actual future states, then discards those states; it is a format check, not an issued forecast or achieved accuracy. Necessary fallback/output-bound capacity must also pass before model evaluation.

The query remains at the recorded wake. All original cases and the frozen distinct-planning scoring cohort remain. Fewer than three observed minute points use the independently verified planning forest; this is a state-context requirement, not a planning-label warmup. Run real independent full/prefix forecasts and compare history caches and forecasts exactly. Keep private arrays/results and public weights outside source and the app. This tests a different representation from event-indexed gap sequences; it remains retrospective research rather than physiology or app integration.

### Pretrained recurrent sequence forecasts

The `research_sleep_planning_recurrent_prior.py` runner tests the native median from a frozen TiRex-2 checkpoint. It compares a sequence of resolved planning gaps alone with the same sequence conditioned on seven wake-known inputs: age, first clock sine/cosine, preceding duration/night indicator, 24-hour sleep total and completed nap ordinal. Historical inputs align with their original wakes. The only forecast-step inputs describe the current known wake; no future sleep, feeding or eventual next-sleep clock enters a request.

    HF_HUB_OFFLINE=1 python3 Scripts/research_sleep_planning_recurrent_prior.py --source /path/to/history.csv --features /tmp/compact.npz --baseline /tmp/app.json --control /tmp/planning-care-pretraining.json --model /tmp/local-model --bootstrap /tmp/public-bootstrap.json --runtime /tmp/local-runtime --output /tmp/planning-recurrent-prior.json

Download public weights/dependencies separately, then run neutral-only checks before private inference. The bootstrap must verify short contexts, repeated forecasts, isolation across preceding unrelated queries and univariate/conditioned calls, current-covariate sensitivity, and model/library hashes. The private runner checks these hashes and installed versions, requires offline mode and uses local model files only. Frozen inference runs in evaluation/inference mode with two CPU threads, dense attention, no compilation and the checkpoint defaults for context padding and differencing. Personal history enters as context, without private gradient training. Each wake is queried separately. See the [official implementation](https://github.com/NX-AI/tirex-2) and [paper](https://arxiv.org/abs/2607.01204).

Only historical planning outcomes whose target sleeps have ended are available. The rolling window is 60 days, with three mature labels required. Before that, retain the independently verified earlier/all-clock forest. All original scoring cases remain. Before a real run, check that fixed sparse fallbacks and prediction bounds do not themselves make the accuracy target unattainable; that capacity calculation is not achieved accuracy. These sequences are indexed by sleep transitions rather than evenly spaced calendar observations, an explicit domain adaptation.

Tests cover current-step alignment, unresolved/current/future label isolation, chronological prefixes, support expiry, finite inputs/output failure and bootstrap tamper rejection. Require independent native full/prefix forecasts before reporting a completed result or adding a chart point. Keep public weights/libraries, private results and any caches outside source and the app. This general forecasting model has no established infant-sleep accuracy guarantee. All-clock distinct planning remains research-only and does not model overnight resettling.

### Predicting an intermediate feeding before sleep

The `research_sleep_planning_feed_path.py` runner predicts whether a feeding will finish before the next sleep, the distribution of its completion delay, and the conditional remaining time to sleep. The final forecast integrates over the predicted feeding delays. Actual future feeding times are never supplied at inference. This is a predictive intermediate-event model, not a causal claim about feeding or a clinical recommendation.

    python3 Scripts/research_sleep_planning_feed_path.py --source /path/to/history.csv --features /tmp/compact.npz --baseline /tmp/app.json --control /tmp/planning-care-pretraining.json --output /tmp/planning-feed-path.json

The first valid feeding completion strictly after the wake and at or before the target sleep start defines historical targets. Its delay plus the post-feeding gap reconstructs the original sleep gap. Feeding occurrence and timing are labels that can train only after the historical target sleep ends. A classifier predicts feeding occurrence from the original 28 wake-known inputs. One forest predicts the delay distribution; a second forest predicts the post-feeding gap conditional on those inputs and a possible delay. Exact discrete marginalization weights each possible delay by its predicted probability and each conditional outcome by its leaf-neighborhood mass. The model does not assume independent feeding and post-feeding delays.

Controls include the exact earlier/all-clock planning forest, a feeding/no-feeding mixture with direct gap predictions, and a conditional direct-gap forest integrated over the same predicted feeding delays. The latter isolates the target decomposition from access to the predicted intermediate event. All forests/classifier use 80 trees, leaf size five, feature fraction 0.8 and seed 42. The 60-day mature planning-label window, minimum three labels, early per-query refits below 40, forced fit at the first crossing of 40, then 24-query cadence remain shared. The feeding path starts after its first mature example. Sparse branches use unsplit leaves; if no non-feeding example exists, that branch has zero gate mass and its unused distribution is the global forest. Without any feeding examples, all variants retain the global forest. Every original case remains scored. The current outcome never selects a branch.

Tests cover target arithmetic and future completion truncation, exact forest-distribution medians, conditional marginalization with dependent components, real learned prefix/current/future-label isolation, maturity and expired history. Independently replay a real prefix with the independently replayed global control, and compare target caches and all forecasts exactly. Private targets/results stay outside source. This is retrospective all-clock distinct-planning research, not overnight-resettling integration; the app is unchanged.

### Personal day/night categories for planning history

The `research_sleep_planning_personal_day.py` runner tests whether fixed imported day/night categories obscure useful planning examples. It infers the center of night from the first circular moment of completed sleep occupancy over seven days, with a three-day half-life and at least three elapsed days. A completed sleep is classified by whether its midpoint lies within six hours of that center. The center is frozen at the historical wake; a future target's midpoint only forms a training label after that target ends. The method infers a category rather than reproducing family-configured day hours or measuring physiological circadian phase.

    python3 Scripts/research_sleep_planning_personal_day.py --source /path/to/history.csv --features /tmp/compact.npz --baseline /tmp/app.json --control /tmp/planning-care-pretraining.json --output /tmp/planning-personal-day.json

A matched two-by-two comparison changes the historical planning cohort, four night-derived inputs, or both. The four inputs are the preceding-night indicator, raw and logical nap counts today, and the recent same-kind median wake gap. Other inputs and the 28-column design stay unchanged. Missing phase support retains the original inputs/categories. The fixed-day control must exactly reproduce the earlier/all-clock forest. All variants use 80 trees, leaf size five, seed 42, a 60-day mature-label window, three-label warmup, early per-query fits below 40, a forced fit at the first crossing of 40 and subsequent 24-query refits.

The primary evaluation cohort remains frozen at the original distinct nap/bedtime cases. Changes in inferred category never drop or relabel evaluation rows, and the current outcome never routes a prediction. All-clock research forecasts do not model overnight resettling. Tests cover circular midpoint classification, physical truncation of future sleep, missing phase, current target-end isolation, real forest prefix/current-outcome isolation, maturity and expired history. Independently replay a real prefix and compare cached designs, label eligibility and forecast vectors exactly. Private arrays/results stay outside source. This is retrospective research; the app is unchanged.

### Joint timing-error and tolerance-risk forest training

The `research_sleep_planning_joint_forest.py` runner minimizes empirical absolute timing error plus a fixed 30-minute cost per error greater than 30 minutes. The loss guides both tree splits and the final decision from the forest's leaf-neighborhood distribution. Two controls isolate the effects: absolute-error splits with a median decision, and the same absolute-error trees with the joint decision. The custom randomization differs from the native/scikit-learn forest; comparisons between these matched custom controls isolate the objective change.

    python3 Scripts/research_sleep_planning_joint_forest.py --source /path/to/history.csv --features /tmp/compact.npz --baseline /tmp/app.json --output /tmp/planning-joint-forest.json

All forests use 80 trees, minimum leaf size five, feature fraction 0.8 and node-keyed seed 42. Candidate feature/threshold draws at a given tree/node path are matched across split criteria. The empirical risk optimizer examines target values and their 30-minute boundaries, including inward neighboring floating-point values, within the feasible 1-to-480-minute range. Prefix-count loss calculations agree with the scorer's inclusive 30-minute condition. This is an independent decision-focused extension of [forest-neighborhood conditional distributions](https://www.jmlr.org/papers/v7/meinshausen06a.html), not a reproduction or a published infant-performance claim. A weighted joint loss does not guarantee either requested accuracy constraint.

The shared 28-feature design, 60-day mature planning-label window, three-label warmup, early per-query refits below 40, forced fit at 40 crossing and subsequent 24-query refits match the earlier/all-clock planning protocol. Current target type/gap never enters a forecast. Each resolved label matures at target sleep end. All original scoring cases and initial app fallbacks remain. These all-clock research heads target distinct sleep plans rather than overnight resettling.

Tests compare batched empirical risk to direct per-observation loss at floating-point boundaries, decisions against a dense independent grid, neighborhood mass/determinism, real learned prefix/current-outcome isolation and sparse/mature/expired-label behavior. Independently replay a real chronological prefix. Keep private forecasts outside source. Retrospective comparisons do not establish prospective accuracy; the app is unchanged.

### Matching forest splits to absolute timing error

The `research_sleep_planning_split_loss.py` runner changes only the forest split criterion from squared error to absolute error. Both variants keep the existing leaf-neighborhood weighted-median output, 80 trees, minimum leaf size five, feature fraction 0.8 and seed 42. The matched squared-split control must reproduce the earlier/all-clock planning forest exactly. Earlier absolute-loss boosting and ExtraTrees trials averaged tree outputs; this experiment isolates split loss within the current median-neighborhood model.

    python3 Scripts/research_sleep_planning_split_loss.py --source /path/to/history.csv --features /tmp/compact.npz --baseline /tmp/app.json --control /tmp/planning-care-pretraining.json --output /tmp/planning-split-loss.json

The shared 28-feature design uses only wake-known inputs. Training uses mature planning labels in a 60-day window, starting at three labels, with per-query early fits below 40 and a forced fit at the first crossing of 40. Later refits occur every 24 queries. All-clock predictions target distinct naps/bedtime, not overnight returns. All original cases and early app fallbacks remain scored. See the documented [absolute-error split criterion](https://scikit-learn.org/stable/modules/generated/sklearn.ensemble.ExtraTreesRegressor.html); this provides no infant-specific accuracy guarantee.

Tests verify exact legacy-control output, weighted-median behavior under missing features and an extreme target, real learned prefix/current-outcome isolation, sparse/mature/expired labels. Independently replay a real prefix using the independently replayed control input. Keep private results outside source. This is retrospective research and does not change the app.

### Temporary states in planning forecast errors

The `research_sleep_planning_error_state.py` runner tests whether recent errors in previously issued planning forecasts reveal a temporary schedule shift. It uses two independent stationary Gaussian states with six-hour and three-day decay times, plus a constant bias and independent observation noise. At each refit, marginal likelihood learns the state/noise variances from resolved prequential errors. A nested zero-state fit is always considered. Errors are clipped at 90 minutes for this robust research adaptation. This is an independent irregular-time covariance implementation of the general [linear Gaussian state-space approach](https://www.statsmodels.org/stable/statespace.html).

    python3 Scripts/research_sleep_planning_error_state.py --source /path/to/history.csv --features /tmp/compact.npz --baseline /tmp/app.json --issued /tmp/planning-care-pretraining.json --output /tmp/planning-error-state.json

The input forecast is the earlier/all-clock planning forest control from the care-pretraining study, with no care encoder. Its original issued points remain fixed. A matched clipped-mean bias control separates overall calibration from transient state effects. Only completed distinct-planning targets in the preceding 60 days may provide errors. Twelve mature labels are needed; parameters refit every 24 queries, while all newly mature labels condition the state at each query. Late feedback is conditioned at its original wake time, rather than pretending it was available at that wake. Current target type and future labels never route or update a forecast. All-clock planning heads remain research-only and do not model overnight resettling.

Tests check a closed-form observation update and decay, zero-state selection, deterministic learned states, real fitted chronological prefix/current-outcome isolation, sparse history, label maturity and expiry. Independently replay a prefix using the independently replayed issued input. Keep private results outside source. Retrospective likelihood fitting and archive-selected comparisons do not establish prospective accuracy.

### Predictive pretraining on completed care

The `research_sleep_planning_care_pretraining.py` runner learns a 16-dimensional recurrent state by predicting the next completed care group's event-type fractions and waiting time. Training examples come from completed care groups, rather than only sleep transitions. Each input contains the last 16 completion groups within 48 hours. Only next-group targets already completed at the refit wake may train the encoder. The 60-day training window uses eight full passes, batch size 128, AdamW at 0.01 with 0.01 weight decay, and gradient clipping at one. Frozen encoder states augment the existing planning forest.

    python3 Scripts/research_sleep_planning_care_pretraining.py --source /path/to/history.csv --features /tmp/compact.npz --baseline /tmp/app.json --output /tmp/planning-care-pretraining.json

The command-line experiment deliberately starts personal planning after three resolved planning labels and issues a planning forecast at every wake clock. It refits every query below 40 labels, at the first crossing of 40, then every 24 queries. Its context-only forest control isolates these policy changes from encoder effects. Random-encoder and shuffled-next-target controls share the same training budget and policy. These all-clock research heads predict a distinct nap or bedtime; their secondary overnight-return performance must be disclosed before considering integration. The app policy is unchanged. All original cases remain in scoring, including early-history cases.

This is inspired by [predictive representation learning](https://arxiv.org/abs/1807.03748), but uses direct next-mark/time losses rather than reproducing contrastive predictive coding. Tests cover physical truncation of future care, deterministic training, current/future outcome isolation, real learned prefix invariance, early/all-clock policy and sparse/invalid inputs. Independently replay a real chronological prefix and verify mature daytime control forecasts match the app. Keep private representations and per-event results outside source. Retrospective comparisons do not establish prospective accuracy.

### Planning supervision for completed-care sequences

The `research_sleep_planning_care_sequence.py` runner tests whether removing short-return and overnight-return targets helps a small recurrent care-history model. It compares planning-only ordered groups with three matched controls: all-label ordered groups, planning-only context with no care sequence, and planning-only pooled groups without event order. Each group summarizes completed event types, completion age, duration and simultaneous count. Sixteen groups from the preceding 48 hours are inputs; no future or still-running care event enters a query.

    python3 Scripts/research_sleep_planning_care_sequence.py --source /path/to/history.csv --features /tmp/compact.npz --baseline /tmp/app.json --output /tmp/planning-care-sequence.json

All variants use the same planning-driven 24-query refit cadence, minimum 40 resolved planning labels, 60-day history and 14-day half-life. They share the latest 20% (minimum eight) resolved planning labels as a chronological validation set. Older training labels must mature by the first validation wake. The all-label control differs only in which older labels train its recurrent model. Validation selects the app baseline or 16, 64 or 128 training epochs using weighted absolute error of clipped forecasts; ties prefer fewer epochs. Selected networks are cold-refitted on their own full-known cohorts. The architecture and AdamW settings match the earlier small recurrent study; inputs add the completed episode values and originally issued app point. Sparse, invalid-pattern and overnight queries retain app points, with every original scoring case retained.

Training checkpoints are captured along one deterministic trajectory to avoid repeated optimization. Tests verify their predictions and final loss match independent cold fits exactly, exercise learned forecasts under prefix/future-outcome changes, and cover shared validation, maturity purging, baseline selection, clipping, invalid-pattern/night fallback and nonfinite failure. Keep pattern arrays and per-event results outside source; independently validate a real full/prefix replay. This is an empirical sequence experiment, not measured physiology or prospective accuracy evidence.

### Weekly calendar context for distinct planning

The `research_sleep_planning_calendar.py` runner isolates a known calendar input from the wider feature experiments. Its three matched forests use the compact planning inputs alone, add seven weekday indicators, or add four weekly-clock harmonics. Calendar values come from the current wake timestamp in Pacific time, including daylight saving changes. They require no fitted encoder or future events.

    python3 Scripts/research_sleep_planning_calendar.py --source /path/to/history.csv --features /tmp/compact.npz --baseline /tmp/app.json --control /tmp/planning-care-pretraining.json --output /tmp/planning-calendar.json

All variants use the same 60-day history, target-end label maturity, minimum three resolved planning labels, early refits below 40 labels, then 24-query cadence. The compact control must reproduce the existing early/all-clock planning forest exactly. Every original evaluation case remains, and these planning heads do not solve overnight resettling. Tests cover local midnight and daylight saving, label maturity and expiry, current/future outcome isolation, prefix invariance and nonfinite failure. Independently replay a real prefix before interpreting results. Keep private history and results outside source. Retrospective comparisons do not establish future accuracy.

### Joint care-event hazards

The `research_sleep_planning_care_process.py` runner models the minute-by-minute presence of feeding, diaper and other completed care events while awake. Regularized logit hazards learn from historical distinct-planning intervals after the target sleep has ended. Inputs combine compact wake context, elapsed awake time, the clock, and care histories decaying over 30, 120 and 480 minutes. The sleep hazard starts from a Gaussian prior around the originally issued app point; its scale comes from mature historical residuals. A 60-day training window and 14-day recency weighting adapt the model to the profile's recent history.

    python3 Scripts/research_sleep_planning_care_process.py --source /path/to/history.csv --features /tmp/compact.npz --baseline /tmp/app.json --output /tmp/planning-care-process.json

At a query, the forecaster receives only wake-known context and completed-care state. It generates 512 possible future care paths and averages their probabilities of no sleep. It never receives the current actual future risk path. Controls omit dynamic care state or assume no new care events occur. The same early learning and refit policy as the calendar experiment retains every original evaluation case. Same-type completions within a minute are represented as presence rather than multiplicity.

The survival calculation follows the principle of [averaging over unobserved marks](https://proceedings.mlr.press/v216/boyd23a.html), adapted to conditionally independent Bernoulli events within each minute. It is not a reproduction of a continuous-time neural architecture or an infant-specific accuracy claim. Analytical checks compare it with exact geometric survival and a two-state interacting event model. Further tests cover the Gaussian prior, learned hazards, historical label maturity, physical future-care truncation, prefix invariance and numerical failure. Keep private risk paths and results outside source; independently replay a real prefix. Monte Carlo and archive-selected results do not establish prospective accuracy.

### Smooth residual trends for planning

The `research_sleep_planning_drift_gp.py` runner compares two residual Gaussian processes around the originally issued app prediction. Both learn a Matérn covariance with separate input scales and an observation-noise term. The candidate adds a linear covariance component, allowing a learned trend to continue beyond nearby observations. This isolates the trend component from the stationary process rather than repeating the earlier all-transition, nine-input process experiments.

    python3 Scripts/research_sleep_planning_drift_gp.py --source /path/to/history.csv --features /tmp/compact.npz --baseline /tmp/app.json --output /tmp/planning-drift-gp.json

Both models use compact planning context and the same 60-day, target-end-mature training cohort, early three-label policy and 24-query refit cadence. Imputation, scaling and covariance fitting use historical training rows only. Every query is issued individually; all original evaluation cases remain. Bounded likelihood optimization uses up to 500 iterations with no random restarts. Iteration limits, fitted-objective values and covariance-bound warnings are retained in the private diagnostics.

Tests verify extrapolation on a neutral linear example, deterministic optimized fitting with missing inputs, historical label maturity and expiry, prefix/current-outcome isolation and nonfinite failure. Independently replay a real prefix before interpreting scores. This uses general [Gaussian-process regression](https://scikit-learn.org/stable/modules/gaussian_process.html), not an infant-specific accuracy guarantee. Keep private results outside source; retrospective comparisons do not establish prospective accuracy.

### Learned response to completed sleep history

The `research_sleep_planning_sleep_kernel.py` runner adds a learned distributed-lag contribution to the minute sleep hazard. Ninety-six occupancy fractions cover the previous 24 hours in 15-minute lag intervals. Their boundaries shift by one minute at each forecast step. Only timers completed by the query's own wake enter these features. Overlapping timers form a union, and history before the first known timer remains missing. During forecasting, no new sleep is inserted before the target event.

    python3 Scripts/research_sleep_planning_sleep_kernel.py --source /path/to/history.csv --features /tmp/compact.npz --baseline /tmp/app.json --control /tmp/planning-care-process.json --output /tmp/planning-sleep-kernel.json

The model retains the compact context and Gaussian prior of the static care-process control, which must reproduce its earlier median predictions exactly. Smoothness penalizes second differences of physical lag coefficients, with a small lag ridge. A Cholesky reparameterization makes this the same quadratic penalty in better-conditioned coordinates; it does not change the model. Historical labels mature at sleep end, with the same 60-day window, 14-day recency weighting and early learning policy. Outputs are the median and mean of the capped minute survival distribution, with all original evaluation cases retained.

This is an independent linear sleep-occupancy adaptation of [penalized distributed-lag modeling](https://doi.org/10.1111/biom.12645), using fixed smoothness rather than reproducing the paper's nonlinear cross-basis and REML procedure. Tests check overlap integration, one-minute shifts, future-timer truncation, penalty gradients, the exact reparameterization, real learned prefix invariance and current-outcome isolation. Independently replay the full and truncated histories before interpreting results. Minute output resolution does not establish minute accuracy. Keep private history and results outside source; the app remains unchanged until an improvement is validated.

### Detailed sleep history in the planning forest

The `research_sleep_planning_history_forest.py` runner tests the same completed-sleep history representation in the existing nonlinear planning forest. Its compact control must reproduce the earlier planning forest exactly. A second control appends 96 zero columns, while the candidate appends the actual 24-hour occupancy inputs. Both wider models therefore have the same column count; adding columns can still affect the forest's random split proposals.

    python3 Scripts/research_sleep_planning_history_forest.py --source /path/to/history.csv --features /tmp/compact.npz --baseline /tmp/app.json --control /tmp/planning-care-pretraining.json --output /tmp/planning-history-forest.json

All models use the same 80 trees, minimum leaf size five, feature fraction 0.8, seed, historical label maturity and early learning/refit policy. This isolates a nonlinear use of timer history from the weaker linear hazard experiment. Tests cover completed-only history, padded dimensions, maturity and expiry, current/future target isolation, prefix invariance and invalid-output failure. Independently replay a real prefix and compare the history arrays as well as forecasts. Keep private arrays and predictions outside source; retrospective results do not establish prospective accuracy.

### Numeric care context for distinct planning

The `research_sleep_planning_care_values.py` runner tests completed nursing-duration and diaper details in the same planning forest. Nursing duration represents recorded time, not milk volume. Missing or nonpositive feeding intervals are excluded; instantaneous diaper records remain usable. Each query receives only care records completed by its own wake. Inputs summarize recent nursing duration, segment patterns and diaper timing over sliding windows.

    python3 Scripts/research_sleep_planning_care_values.py --source /path/to/history.csv --features /tmp/compact.npz --baseline /tmp/app.json --control /tmp/planning-care-pretraining.json --output /tmp/planning-care-values.json

The compact control must reproduce the earlier planning forest exactly. A second control appends 13 zero columns; the candidate appends the 13 numeric care fields. All variants share the 80-tree configuration, 60-day training window, target-end maturity and early learning/refit policy. They retain every original evaluation case and do not route forecasts using the actual future sleep type. Tests cover completed-only care, future completions, padded dimensions, historical maturity, prefix/current-outcome isolation and invalid-output failure. Independently replay a real prefix and compare the care arrays as well as predictions. Keep private records and results outside source; retrospective differences require prospective confirmation before changing the app.

### Partial-cycle alignment for distinct planning

The `research_sleep_planning_alignment.py` runner adapts the earlier cycle-neighbor experiment to resolved distinct nap/bedtime training labels. Each wake receives a frozen suffix of up to six resolved sleep/gap cycles from the previous seven days. Missing or ambiguous links reset the suffix; shorter histories remain usable. Comparisons use the common observed suffix, and a missing suffix contributes no sequence cost. Wake context still supplies a distance, so missing patterns do not force an app fallback after three mature labels are available.

    python3 Scripts/research_sleep_planning_alignment.py --source /path/to/history.csv --features /tmp/compact.npz --baseline /tmp/app.json --output /tmp/planning-alignment.json

Three matched neighbors use wake context alone, fixed cycle positions, or a dynamic-warping band of two. Fifteen nearest past queries receive inverse-distance and 14-day recency weights, with their weighted median as the point forecast. The training window remains 60 days; sleep-end maturity applies to training labels and type. Every original query remains scored, and the current actual future type never routes a forecast. The [DTW recurrence](https://tslearn.readthedocs.io/en/stable/user_guide/dtw.html) is reused from the independently tested cycle-alignment helper; this is a general adaptation rather than a published infant-specific accuracy claim. Tests cover partial suffixes, missing links, future outcomes, maturity, real prefix forecasts and invalid numerical inputs. Keep private results outside source and independently check full/prefix parity before interpreting scores.
