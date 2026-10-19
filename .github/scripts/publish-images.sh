#!/bin/bash
# Puts a run's GIFs and PNGs on the previews branch, where pull requests and Claude can show them, then
#   preview: posts <folder>/preview.md as a comment on the pull request, editing the earlier one;
#   e2e: adds <folder>/summary.md to the job summary.
# Usage: .github/scripts/publish-images.sh preview|e2e <folder>
# Needs GH_TOKEN, GITHUB_REPOSITORY, PR_NUMBER and HEAD_SHA in the environment.
set -euo pipefail
shopt -s nullglob

KIND="$1"
SOURCE="$2"
FOLDER="pr-$PR_NUMBER/$KIND/${HEAD_SHA:0:7}"
IMAGES=("$SOURCE"/*.gif "$SOURCE"/*.png)
if [ ${#IMAGES[@]} -eq 0 ]; then
  echo "No images in $SOURCE to publish."
  exit 0
fi
AUTH="AUTHORIZATION: basic $(printf 'x-access-token:%s' "$GH_TOKEN" | base64 | tr -d '\n')"
echo "::add-mask::${AUTH#AUTHORIZATION: basic }"
export GIT_AUTHOR_NAME="github-actions[bot]" GIT_COMMITTER_NAME="github-actions[bot]"
export GIT_AUTHOR_EMAIL="41898282+github-actions[bot]@users.noreply.github.com"
export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"

OPEN="$(gh pr list --repo "$GITHUB_REPOSITORY" --state open --limit 500 --json number --jq '.[].number')"

# Builds the branch's next tree in a fresh clone: these images replace the pull request's last ones of the same
# kind, and closed pull requests' images are dropped. Sets WORK, BASE (the commit it started from) and COMMIT.
prepare() {
  WORK="$(mktemp -d)"
  git -C "$WORK" init --quiet
  git -C "$WORK" remote add origin "https://github.com/$GITHUB_REPOSITORY.git"
  BASE=""
  if git -C "$WORK" -c "http.https://github.com/.extraheader=$AUTH" fetch --quiet --depth 1 origin previews; then
    BASE="$(git -C "$WORK" rev-parse FETCH_HEAD)"
    git -C "$WORK" checkout --quiet --detach FETCH_HEAD
  fi
  for dir in "$WORK"/pr-*; do
    [ -d "$dir" ] || continue
    if ! grep -qx "${dir##*/pr-}" <<<"$OPEN"; then rm -rf "$dir"; fi
  done
  rm -rf "$WORK/pr-$PR_NUMBER/$KIND"
  mkdir -p "$WORK/$FOLDER"
  cp "${IMAGES[@]}" "$WORK/$FOLDER/"
  cat >"$WORK/README.md" <<'EOF'
# Previews

Images for open pull requests, one folder each: `preview` holds the flower GIFs from the Preview workflow
(`.github/workflows/preview.yml`) and `e2e` the screenshots from the end-to-end journeys
(`.github/workflows/e2e.yml`). Every run replaces this branch with a single commit, so cloning Bloom stays small.
EOF
  git -C "$WORK" add -A
  COMMIT="$(git -C "$WORK" commit-tree "$(git -C "$WORK" write-tree)" -m "Images for open pull requests")"
}

# Another run can land between the fetch and the push; the lease catches that and the loop retries.
for attempt in 1 2 3 4 5; do
  prepare
  if git -C "$WORK" -c "http.https://github.com/.extraheader=$AUTH" push --quiet \
    --force-with-lease="refs/heads/previews:$BASE" origin "$COMMIT:refs/heads/previews"; then
    break
  fi
  if [ "$attempt" -eq 5 ]; then
    echo "::error::Couldn't update the previews branch."
    exit 1
  fi
  sleep $((attempt * 3))
done

BASE_URL="https://raw.githubusercontent.com/$GITHUB_REPOSITORY/previews/$FOLDER"
# Points the relative image paths in a run's Markdown at the published copies.
absolute() {
  sed -e "s#src=\"#src=\"$BASE_URL/#g" -e "s#](#]($BASE_URL/#g" "$1"
}

case "$KIND" in
  preview)
    MARKER="<!-- bloom-preview -->"
    BODY="$(mktemp)"
    {
      echo "$MARKER"
      echo "### Flower preview"
      echo
      echo "Rendered on a macOS runner from $HEAD_SHA by the Preview workflow. Each moment loops; the stills show six instants."
      echo
      absolute "$SOURCE/preview.md"
    } >"$BODY"
    COMMENT="$(gh api --paginate "repos/$GITHUB_REPOSITORY/issues/$PR_NUMBER/comments" \
      --jq ".[] | select(.user.login == \"github-actions[bot]\" and (.body | startswith(\"$MARKER\"))) | .id" | tail -n 1)"
    if [ -n "$COMMENT" ]; then
      gh api --method PATCH "repos/$GITHUB_REPOSITORY/issues/comments/$COMMENT" -F "body=@$BODY" >/dev/null
    else
      gh api --method POST "repos/$GITHUB_REPOSITORY/issues/$PR_NUMBER/comments" -F "body=@$BODY" >/dev/null
    fi
    ;;
  e2e)
    if [ -f "$SOURCE/summary.md" ]; then
      absolute "$SOURCE/summary.md" >>"$GITHUB_STEP_SUMMARY"
    fi
    ;;
esac
echo "Published: $BASE_URL"
