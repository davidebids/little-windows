"""Deterministic randomized trees suitable for an independent native implementation.

This is a compact research algorithm, not a replication of a library's RNG or
tree-growing code. Leaf-distribution aggregation predicts a weighted median.
"""
import numpy as np


class PortableRandom:
    def __init__(self, seed=42):
        self.state = seed

    def uniform(self):
        self.state = self.state * 48271 % 2147483647
        return self.state / 2147483647


class PortableForest:
    def __init__(self, trees=40, minimum_leaf=5):
        if trees <= 0 or minimum_leaf <= 0:
            raise ValueError("Tree count and minimum leaf size must be positive")
        self.tree_count, self.minimum_leaf = trees, minimum_leaf

    def fit(self, x, y):
        x, y = np.asarray(x, dtype=float), np.asarray(y, dtype=float)
        if x.ndim != 2 or not x.shape[0] or not x.shape[1] or len(y) != len(x) or not np.all(np.isfinite(y)):
            raise ValueError("Expected a nonempty feature matrix and matching finite targets")
        self.medians = np.array([np.median(c[np.isfinite(c)]) if np.any(np.isfinite(c)) else 0. for c in x.T])
        self.x = np.where(np.isfinite(x), x, self.medians)
        self.y = y.copy()
        self.order = sorted(range(len(y)), key=lambda i: (y[i], i))
        self.random = PortableRandom()
        self.trees = [self.grow(np.arange(len(y)), 0) for _ in range(self.tree_count)]
        return self

    def grow(self, indices, depth):
        if len(indices) < 2 * self.minimum_leaf or depth >= 12:
            return (indices,)
        values = self.y[indices]
        total = float(np.sum(values))
        parent = total * total / len(indices)
        features = list(range(self.x.shape[1]))
        count = max(1, int(len(features) * .8))
        for k in range(count):
            other = k + int(self.random.uniform() * (len(features) - k))
            features[k], features[other] = features[other], features[k]
        best, split = 1e-8, None
        for feature in features[:count]:
            column = self.x[indices, feature]
            low, high = float(np.min(column)), float(np.max(column))
            if high <= low:
                continue
            threshold = low + (high - low) * self.random.uniform()
            left = column <= threshold
            left_count = int(np.sum(left))
            right_count = len(indices) - left_count
            if min(left_count, right_count) < self.minimum_leaf:
                continue
            left_sum = float(np.sum(values[left]))
            right_sum = total - left_sum
            gain = left_sum * left_sum / left_count + right_sum * right_sum / right_count - parent
            if gain > best:
                best, split = gain, (feature, threshold, indices[left], indices[~left])
        if split is None:
            return (indices,)
        feature, threshold, left, right = split
        return (feature, threshold, self.grow(left, depth + 1), self.grow(right, depth + 1))

    def predict(self, x):
        x = np.asarray(x, dtype=float)
        if x.ndim != 2 or x.shape[1] != len(self.medians):
            raise ValueError("Query feature count differs from the fitted model")
        x = np.where(np.isfinite(x), x, self.medians)
        output = []
        for row in x:
            weights = np.zeros(len(self.y))
            for tree in self.trees:
                while len(tree) > 1:
                    tree = tree[2] if row[tree[0]] <= tree[1] else tree[3]
                leaf = tree[0]
                weights[leaf] += 1 / len(leaf)
            total = 0.
            for j in self.order:
                total += float(weights[j])
            running = 0.
            for j in self.order:
                running += float(weights[j])
                if running >= total / 2 - total * 1e-12:
                    output.append(self.y[j])
                    break
        return np.asarray(output)
