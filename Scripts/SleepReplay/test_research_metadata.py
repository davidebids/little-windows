import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).parents[1]))
from sleep_research_metadata import care_exposure


class MetadataTests(unittest.TestCase):
    def test_legacy_running_features_cannot_default_to_completed(self):
        self.assertEqual(care_exposure(dict(audit={}, featureNames=["FeedRunningElapsed"])), "started")
        self.assertEqual(care_exposure(dict(audit={}, featureNames=["lastFeedMinutes"])), "completed")

    def test_explicit_metadata_and_feature_names_must_agree(self):
        self.assertEqual(care_exposure(dict(audit=dict(careExposure="started"))), "started")
        self.assertEqual(care_exposure(dict(audit=dict(careExposure="completed"))), "completed")
        with self.assertRaises(ValueError):
            care_exposure(dict(audit=dict(careExposure="completed"), featureNames=["FeedRunning"]))
        with self.assertRaises(ValueError):
            care_exposure(dict(audit=dict(careExposure="unknown")))


if __name__ == "__main__":
    unittest.main()
