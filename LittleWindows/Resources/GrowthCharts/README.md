# Growth Chart Reference Data

This directory contains the official CDC-hosted WHO Child Growth Standards data
for infants from birth through 24 months.

Source page:
https://www.cdc.gov/growthcharts/who-data-files.htm

Included charts:

- Weight-for-age, kilograms
- Recumbent length-for-age, centimeters
- Head circumference-for-age, centimeters
- Boys and girls

The CSV files contain monthly L, M, and S parameters plus selected percentile
values. Little Windows linearly interpolates the LMS parameters between age
points, then uses the standard LMS equations documented by CDC to calculate
z-scores, percentiles, and reference curves.

Update process:

1. Visit the CDC source page above.
2. Download the six birth-to-24-month CSV files.
3. Replace the corresponding files in this directory without changing their
   bundled filenames.
4. Run the growth-reference unit tests and the full app test suite.

CDC 2-to-20-year support is intentionally not bundled yet. The service returns
an unsupported-range result after 24 months so a future release can add CDC
reference files without presenting WHO infant curves outside their intended
range.
