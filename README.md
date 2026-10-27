# Previews

Images for open pull requests, one folder each, and for the latest run on `main`: `preview` holds the flower GIFs
from the Preview workflow (`.github/workflows/preview.yml`) and `e2e-<runner>` the screenshots from the end-to-end
journeys on each macOS runner (`.github/workflows/e2e.yml`). Every run replaces this branch with a single commit, so
cloning Bloom stays small.
