#!/bin/bash
set -e

#######################################
# CONFIGURATION
#######################################

# Colors (with fallback for non-color terminals)
if [[ -t 1 ]] && [[ -n "$TERM" ]] && tput colors &>/dev/null; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  BLUE='\033[0;34m'
  DIM='\033[2m'
  NC='\033[0m'
else
  RED='' GREEN='' YELLOW='' BLUE='' DIM='' NC=''
fi

# Files
STATE_FILE=".release-state"
LOCK_FILE=".release-lock"
LOG_FILE=".release-log"
CONFIG_FILE=".releaserc"

# Defaults
DRY_RUN=false
VERBOSE=false
YES=false
BUMP_TYPE="patch"
EDIT_CHANGELOG=true

# Step order
STEPS=(
  "preflight"
  "init"
  "show_commits"
  "create_changeset"
  "edit_changeset"
  "build"
  "version"
  "git_commit"
  "npm_publish"
  "git_push"
  "gh_release"
  "cleanup"
)

#######################################
# LOGGING
#######################################

log() {
  local msg="[$(date '+%H:%M:%S')] $1"
  echo -e "$msg"
  echo "$msg" >> "$LOG_FILE"
}

log_verbose() {
  if $VERBOSE; then
    log "${DIM}$1${NC}"
  fi
}

log_success() { log "${GREEN}✅ $1${NC}"; }
log_info() { log "${BLUE}ℹ️  $1${NC}"; }
log_warn() { log "${YELLOW}⚠️  $1${NC}"; }
log_error() { log "${RED}❌ $1${NC}"; }
log_skip() { log "${DIM}⏭️  Skipping $1 (already done)${NC}"; }

log_dry() {
  if $DRY_RUN; then
    log "${YELLOW}[DRY RUN]${NC} Would: $1"
    return 0
  fi
  return 1
}

#######################################
# PURE FUNCTIONS
#######################################

get_pkg_name() {
  node -p "require('./package.json').name" 2>/dev/null || echo ""
}

get_pkg_version() {
  node -p "require('./package.json').version" 2>/dev/null || echo ""
}

get_repo() {
  node -p "require('./package.json').repository?.url?.replace('git+', '')?.replace('.git', '')?.split('github.com/')[1] || ''" 2>/dev/null || echo ""
}

get_last_tag() {
  git describe --tags --abbrev=0 2>/dev/null || echo ""
}

get_commits_since_tag() {
  local tag=$1
  if [ -n "$tag" ]; then
    git log "$tag"..HEAD --pretty=format:"- %s" 2>/dev/null
  else
    git log --oneline -10 --pretty=format:"- %s" 2>/dev/null
  fi
}

get_commit_count_since_tag() {
  local tag=$1
  if [ -n "$tag" ]; then
    git rev-list "$tag"..HEAD --count 2>/dev/null || echo "0"
  else
    git rev-list HEAD --count 2>/dev/null || echo "0"
  fi
}

get_current_commit() {
  git rev-parse HEAD 2>/dev/null || echo ""
}

get_current_branch() {
  git rev-parse --abbrev-ref HEAD 2>/dev/null || echo ""
}

get_default_branch() {
  # Try config, then common defaults
  if [ -f "$CONFIG_FILE" ]; then
    local branch=$(grep "^branch:" "$CONFIG_FILE" 2>/dev/null | cut -d: -f2 | tr -d ' ')
    [ -n "$branch" ] && echo "$branch" && return
  fi
  git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main"
}

has_uncommitted_changes() {
  [ -n "$(git status --porcelain 2>/dev/null)" ]
}

is_npm_logged_in() {
  npm whoami &>/dev/null
}

is_gh_logged_in() {
  gh auth status &>/dev/null
}

random_string() {
  # Cross-platform random string
  if command -v openssl &>/dev/null; then
    openssl rand -hex 4
  else
    echo "$RANDOM$RANDOM" | md5sum | head -c 8
  fi
}

detect_bump_type() {
  local tag=$1
  local commits
  
  if [ -n "$tag" ]; then
    commits=$(git log "$tag"..HEAD --pretty=format:"%s" 2>/dev/null)
  else
    commits=$(git log --pretty=format:"%s" -20 2>/dev/null)
  fi
  
  # Check for breaking changes
  if echo "$commits" | grep -qiE "^(BREAKING CHANGE|.*!:)"; then
    echo "major"
    return
  fi
  
  # Check for features
  if echo "$commits" | grep -qiE "^(feat|feature|📦 NEW)"; then
    echo "minor"
    return
  fi
  
  # Default to patch
  echo "patch"
}

#######################################
# CONFIG FILE
#######################################

load_config() {
  if [ -f "$CONFIG_FILE" ]; then
    log_verbose "Loading config from $CONFIG_FILE"
    
    local val
    val=$(grep "^bump:" "$CONFIG_FILE" 2>/dev/null | cut -d: -f2 | tr -d ' ')
    [ -n "$val" ] && BUMP_TYPE="$val"
    
    val=$(grep "^edit:" "$CONFIG_FILE" 2>/dev/null | cut -d: -f2 | tr -d ' ')
    [ "$val" = "false" ] && EDIT_CHANGELOG=false
  fi
}

#######################################
# LOCK FILE
#######################################

acquire_lock() {
  if [ -f "$LOCK_FILE" ]; then
    local pid=$(cat "$LOCK_FILE")
    if kill -0 "$pid" 2>/dev/null; then
      log_error "Another release is in progress (PID: $pid)"
      exit 1
    else
      log_warn "Stale lock file found, removing..."
      rm -f "$LOCK_FILE"
    fi
  fi
  echo $$ > "$LOCK_FILE"
  trap 'rm -f "$LOCK_FILE"' EXIT
}

#######################################
# STATE MANAGEMENT
#######################################

save_state() {
  local key=$1
  local value=$2
  if [ -f "$STATE_FILE" ]; then
    grep -v "^$key:" "$STATE_FILE" > "${STATE_FILE}.tmp" 2>/dev/null || true
    mv "${STATE_FILE}.tmp" "$STATE_FILE"
  fi
  echo "$key:$value" >> "$STATE_FILE"
}

get_state() {
  local key=$1
  grep "^$key:" "$STATE_FILE" 2>/dev/null | cut -d: -f2- || echo ""
}

clear_state() {
  rm -f "$STATE_FILE"
}

has_state() {
  [ -f "$STATE_FILE" ]
}

is_step_done() {
  local step=$1
  local done_steps=$(get_state "completed_steps")
  [[ ",$done_steps," == *",$step,"* ]]
}

mark_step_done() {
  local step=$1
  local done_steps=$(get_state "completed_steps")
  if [ -z "$done_steps" ]; then
    save_state "completed_steps" "$step"
  else
    save_state "completed_steps" "$done_steps,$step"
  fi
  save_state "last_step" "$step"
}

get_step_index() {
  local step=$1
  for i in "${!STEPS[@]}"; do
    if [[ "${STEPS[$i]}" == "$step" ]]; then
      echo "$i"
      return
    fi
  done
  echo -1
}

#######################################
# VERIFICATION FUNCTIONS
#######################################

verify_preflight() { return 0; }
verify_init() { [ -n "$(get_state 'original_commit')" ]; }
verify_show_commits() { [ -n "$(get_state 'last_tag')" ] || [ "$(get_state 'no_previous_tag')" = "true" ]; }
verify_create_changeset() { local f=$(get_state "changeset_file"); [ -n "$f" ] && [ -f "$f" ]; }
verify_edit_changeset() { return 0; }
verify_build() { [ -d "dist" ]; }
verify_version() { [ -f "CHANGELOG.md" ] && grep -q "$(get_pkg_version)" CHANGELOG.md 2>/dev/null; }
verify_git_commit() { local v=$(get_state "version"); [ -n "$v" ] && git log -1 --pretty=%B 2>/dev/null | grep -q "RELEASE: v$v"; }
verify_npm_publish() { local p=$(get_pkg_name); local v=$(get_state "version"); npm view "$p@$v" version 2>/dev/null | grep -q "$v"; }
verify_git_push() { local t=$(get_state "tag"); git ls-remote --tags origin 2>/dev/null | grep -q "refs/tags/$t"; }
verify_gh_release() { local t=$(get_state "tag"); gh release view "$t" &>/dev/null; }
verify_cleanup() { ! has_state; }

#######################################
# ROLLBACK FUNCTIONS
#######################################

rollback_git_commit() {
  local original_commit=$(get_state "original_commit")
  if [ -n "$original_commit" ]; then
    log_warn "Rolling back to commit $original_commit"
    $DRY_RUN || git reset --hard "$original_commit"
  fi
}

rollback_changeset() {
  local changeset_file=$(get_state "changeset_file")
  if [ -n "$changeset_file" ] && [ -f "$changeset_file" ]; then
    log_warn "Removing changeset $changeset_file"
    $DRY_RUN || rm -f "$changeset_file"
  fi
}

rollback_remote_tag() {
  local tag=$(get_state "tag")
  if [ -n "$tag" ]; then
    log_warn "Removing remote tag $tag"
    $DRY_RUN || git push origin ":refs/tags/$tag" 2>/dev/null || true
  fi
}

rollback_gh_release() {
  local tag=$(get_state "tag")
  if [ -n "$tag" ]; then
    log_warn "Deleting GitHub release $tag"
    $DRY_RUN || gh release delete "$tag" --yes 2>/dev/null || true
  fi
}

rollback() {
  log_error "Rolling back..."
  
  local last_step=$(get_state "last_step")
  
  case $last_step in
    "gh_release")
      rollback_gh_release
      rollback_remote_tag
      rollback_git_commit
      ;;
    "git_push")
      rollback_remote_tag
      rollback_git_commit
      ;;
    "npm_publish")
      local pkg=$(get_pkg_name)
      local ver=$(get_state 'version')
      log_error "Cannot auto-unpublish from npm."
      log_info "Within 72hrs run: npm unpublish $pkg@$ver"
      rollback_git_commit
      ;;
    "git_commit"|"version")
      rollback_git_commit
      ;;
    "create_changeset"|"edit_changeset")
      rollback_changeset
      ;;
    *)
      log_warn "Nothing to rollback"
      ;;
  esac
  
  $DRY_RUN || clear_state
  log_success "Rollback complete"
}

#######################################
# STEP FUNCTIONS
#######################################

step_preflight() {
  if is_step_done "preflight"; then
    log_skip "preflight"
    return 0
  fi
  
  log_info "Running preflight checks..."
  local errors=0
  
  # Check package.json exists
  if [ ! -f "package.json" ]; then
    log_error "package.json not found"
    ((errors++))
  fi
  
  # Check package name
  local pkg_name=$(get_pkg_name)
  if [ -z "$pkg_name" ]; then
    log_error "Could not read package name"
    ((errors++))
  else
    log_verbose "Package: $pkg_name"
  fi
  
  # Check repo URL
  local repo=$(get_repo)
  if [ -z "$repo" ]; then
    log_warn "No repository.url in package.json (GitHub release will fail)"
  else
    log_verbose "Repository: $repo"
  fi
  
  # Check npm login
  if ! is_npm_logged_in; then
    log_error "Not logged into npm. Run: npm login"
    ((errors++))
  else
    log_verbose "npm: logged in as $(npm whoami)"
  fi
  
  # Check gh login
  if ! is_gh_logged_in; then
    log_warn "Not logged into GitHub CLI. Run: gh auth login"
  else
    log_verbose "gh: authenticated"
  fi
  
  # Check git status
  if has_uncommitted_changes; then
    log_error "Uncommitted changes detected. Commit or stash first."
    ((errors++))
  else
    log_verbose "git: working tree clean"
  fi
  
  # Check branch
  local current_branch=$(get_current_branch)
  local default_branch=$(get_default_branch)
  if [ "$current_branch" != "$default_branch" ]; then
    log_warn "Not on $default_branch branch (currently on $current_branch)"
  fi
  
  # Check for commits to release
  local last_tag=$(get_last_tag)
  local commit_count=$(get_commit_count_since_tag "$last_tag")
  if [ "$commit_count" -eq 0 ]; then
    log_error "No commits since last release ($last_tag)"
    ((errors++))
  else
    log_verbose "Commits to release: $commit_count"
  fi
  
  # Check changeset directory
  if [ ! -d ".changeset" ]; then
    log_warn ".changeset directory not found. Run: npx changeset init"
  fi
  
  if [ $errors -gt 0 ]; then
    log_error "Preflight failed with $errors error(s)"
    exit 1
  fi
  
  log_success "Preflight checks passed"
  mark_step_done "preflight"
}

step_init() {
  if is_step_done "init" && verify_init; then
    log_skip "init"
    return 0
  fi
  
  log_info "Initializing release..."
  
  # Auto-detect bump type from commits
  local last_tag=$(get_last_tag)
  local detected_bump=$(detect_bump_type "$last_tag")
  
  if [ "$BUMP_TYPE" = "auto" ]; then
    BUMP_TYPE="$detected_bump"
    log_info "Auto-detected bump type: $BUMP_TYPE"
  elif [ "$detected_bump" != "$BUMP_TYPE" ]; then
    log_verbose "Detected: $detected_bump, using: $BUMP_TYPE"
  fi
  
  save_state "original_commit" "$(get_current_commit)"
  save_state "bump_type" "$BUMP_TYPE"
  mark_step_done "init"
}

step_show_commits() {
  if is_step_done "show_commits" && verify_show_commits; then
    log_skip "show_commits"
    return 0
  fi
  
  local last_tag=$(get_last_tag)
  echo ""
  log_info "Commits since ${last_tag:-beginning}:"
  echo "════════════════════════════════════════"
  get_commits_since_tag "$last_tag"
  echo ""
  echo "════════════════════════════════════════"
  echo ""
  
  if [ -n "$last_tag" ]; then
    save_state "last_tag" "$last_tag"
  else
    save_state "no_previous_tag" "true"
  fi
  mark_step_done "show_commits"
}

step_create_changeset() {
  if is_step_done "create_changeset" && verify_create_changeset; then
    log_skip "create_changeset"
    return 0
  fi
  
  local pkg_name=$(get_pkg_name)
  local last_tag=$(get_state "last_tag")
  local commits=$(get_commits_since_tag "$last_tag")
  local bump_type=$(get_state "bump_type")
  local filename=$(random_string)
  local filepath=".changeset/$filename.md"
  
  if log_dry "Create changeset at $filepath"; then
    save_state "changeset_file" "$filepath"
    mark_step_done "create_changeset"
    return 0
  fi
  
  mkdir -p .changeset
  cat > "$filepath" << EOF
---
"$pkg_name": $bump_type
---

$commits
EOF
  
  log_success "Created changeset ($bump_type)"
  save_state "changeset_file" "$filepath"
  mark_step_done "create_changeset"
}

step_edit_changeset() {
  if is_step_done "edit_changeset"; then
    log_skip "edit_changeset"
    return 0
  fi
  
  if ! $EDIT_CHANGELOG; then
    log_verbose "Skipping changelog edit (disabled)"
    mark_step_done "edit_changeset"
    return 0
  fi
  
  local filepath=$(get_state "changeset_file")
  
  if $DRY_RUN; then
    log_dry "Open editor for $filepath"
    mark_step_done "edit_changeset"
    return 0
  fi
  
  if [ -n "$EDITOR" ]; then
    log_info "Opening changeset in editor..."
    $EDITOR "$filepath"
  elif command -v code &>/dev/null; then
    code --wait "$filepath"
  elif command -v vim &>/dev/null; then
    vim "$filepath"
  else
    log_warn "No editor found. Edit manually: $filepath"
    log_info "Press Enter to continue..."
    read -r
  fi
  
  mark_step_done "edit_changeset"
}

step_build() {
  if is_step_done "build" && verify_build; then
    log_skip "build"
    return 0
  fi
  
  log_info "Building..."
  
  if log_dry "Run pnpm build"; then
    mark_step_done "build"
    return 0
  fi
  
  pnpm build
  log_success "Build complete"
  mark_step_done "build"
}

step_version() {
  if is_step_done "version" && verify_version; then
    log_skip "version"
    save_state "version" "$(get_pkg_version)"
    save_state "tag" "v$(get_pkg_version)"
    return 0
  fi
  
  log_info "Bumping version..."
  
  if log_dry "Run changeset version"; then
    save_state "version" "X.X.X"
    save_state "tag" "vX.X.X"
    mark_step_done "version"
    return 0
  fi
  
  pnpm changeset version
  
  local version=$(get_pkg_version)
  save_state "version" "$version"
  save_state "tag" "v$version"
  log_success "Version: $version"
  mark_step_done "version"
}

step_git_commit() {
  if is_step_done "git_commit" && verify_git_commit; then
    log_skip "git_commit"
    return 0
  fi
  
  local version=$(get_state "version")
  log_info "Committing v$version..."
  
  if log_dry "Commit release"; then
    mark_step_done "git_commit"
    return 0
  fi
  
  git add -A
  git commit -m "🚀 RELEASE: v$version"
  log_success "Committed"
  mark_step_done "git_commit"
}

step_npm_publish() {
  if is_step_done "npm_publish" && verify_npm_publish; then
    log_skip "npm_publish"
    return 0
  fi
  
  local pkg_name=$(get_pkg_name)
  local version=$(get_state "version")
  
  # Confirmation prompt (unless --yes)
  if ! $YES && ! $DRY_RUN; then
    echo ""
    log_warn "About to publish $pkg_name@$version to npm (irreversible after 72hrs)"
    read -p "Continue? [y/N] " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      log_error "Aborted by user"
      exit 1
    fi
  fi
  
  log_info "Publishing to npm..."
  
  if log_dry "Publish $pkg_name@$version to npm"; then
    mark_step_done "npm_publish"
    return 0
  fi
  
  pnpm changeset publish
  log_success "Published to npm"
  mark_step_done "npm_publish"
}

step_git_push() {
  if is_step_done "git_push" && verify_git_push; then
    log_skip "git_push"
    return 0
  fi
  
  log_info "Pushing to git..."
  
  if log_dry "Push commits and tags"; then
    mark_step_done "git_push"
    return 0
  fi
  
  git push --follow-tags
  log_success "Pushed"
  mark_step_done "git_push"
}

step_gh_release() {
  if is_step_done "gh_release" && verify_gh_release; then
    log_skip "gh_release"
    return 0
  fi
  
  local version=$(get_state "version")
  local repo=$(get_repo)
  local tag="v$version"
  
  if [ -z "$repo" ]; then
    log_warn "Skipping GitHub release (no repository.url)"
    mark_step_done "gh_release"
    return 0
  fi
  
  if ! is_gh_logged_in; then
    log_warn "Skipping GitHub release (not logged in)"
    mark_step_done "gh_release"
    return 0
  fi
  
  log_info "Creating GitHub release..."
  
  if log_dry "Create GitHub release $tag"; then
    mark_step_done "gh_release"
    return 0
  fi
  
  gh release create "$tag" --generate-notes
  gh release edit "$tag" --notes "$(gh release view "$tag" --json body -q .body)

[Full Changelog](https://github.com/$repo/blob/main/CHANGELOG.md)"
  
  log_success "GitHub release created"
  mark_step_done "gh_release"
}

step_cleanup() {
  if $DRY_RUN; then
    log_dry "Clean up state files"
    return 0
  fi
  
  clear_state
  rm -f "$LOG_FILE"
  
  local pkg_name=$(get_pkg_name)
  local version=$(get_pkg_version)
  echo ""
  echo "════════════════════════════════════════"
  log_success "Released $pkg_name@$version"
  echo "════════════════════════════════════════"
}

#######################################
# RUNNERS
#######################################

run_step() {
  local step=$1
  case $step in
    "preflight") step_preflight ;;
    "init") step_init ;;
    "show_commits") step_show_commits ;;
    "create_changeset") step_create_changeset ;;
    "edit_changeset") step_edit_changeset ;;
    "build") step_build ;;
    "version") step_version ;;
    "git_commit") step_git_commit ;;
    "npm_publish") step_npm_publish ;;
    "git_push") step_git_push ;;
    "gh_release") step_gh_release ;;
    "cleanup") step_cleanup ;;
    *) log_error "Unknown step: $step"; exit 1 ;;
  esac
}

run_from_step() {
  local start_step=$1
  local start_index=$(get_step_index "$start_step")
  
  if [ "$start_index" -eq -1 ]; then
    log_error "Unknown step: $start_step"
    echo "Available steps: ${STEPS[*]}"
    exit 1
  fi
  
  for ((i=start_index; i<${#STEPS[@]}; i++)); do
    run_step "${STEPS[$i]}"
  done
}

resume() {
  if ! has_state; then
    log_info "Starting new release..."
    run_from_step "preflight"
    return
  fi
  
  log_info "Resuming release..."
  local last_step=$(get_state "last_step")
  local last_index=$(get_step_index "$last_step")
  local next_index=$((last_index + 1))
  
  if [ $next_index -ge ${#STEPS[@]} ]; then
    log_success "Release already complete"
    clear_state
    return
  fi
  
  local next_step="${STEPS[$next_index]}"
  log_info "Continuing from: $next_step"
  run_from_step "$next_step"
}

#######################################
# STATUS
#######################################

status() {
  if ! has_state; then
    log_warn "No release in progress"
    return
  fi
  
  echo ""
  log_info "Release Status"
  echo "════════════════════════════════════════"
  
  local version=$(get_state "version")
  local tag=$(get_state "tag")
  local bump=$(get_state "bump_type")
  
  [ -n "$version" ] && echo "  Version: $version"
  [ -n "$tag" ] && echo "  Tag: $tag"
  [ -n "$bump" ] && echo "  Bump: $bump"
  echo ""
  
  for step in "${STEPS[@]}"; do
    if is_step_done "$step"; then
      echo -e "  ${GREEN}✅ $step${NC}"
    else
      echo -e "  ⬜ $step"
    fi
  done
  echo "════════════════════════════════════════"
}

#######################################
# HELP
#######################################

show_help() {
  cat << EOF
Usage: pnpm release [options]

Options:
  --patch         Patch release (default)
  --minor         Minor release
  --major         Major release
  --auto          Auto-detect from commits
  
  --dry-run       Show what would happen
  --yes, -y       Skip confirmation prompts
  --no-edit       Skip changelog editing
  --verbose, -v   Verbose output
  
  --step <name>   Run a specific step only
  --from <name>   Run from a specific step
  --status        Show release progress
  --rollback      Rollback failed release
  --help, -h      Show this help

Steps: ${STEPS[*]}

Config file (.releaserc):
  branch: main
  bump: patch|minor|major|auto
  edit: true|false

Examples:
  pnpm release              # Run/resume release
  pnpm release --minor      # Minor release
  pnpm release --dry-run    # Preview release
  pnpm release --status     # Check progress
  pnpm release --rollback   # Undo failed release
EOF
}

#######################################
# MAIN
#######################################

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --patch) BUMP_TYPE="patch"; shift ;;
    --minor) BUMP_TYPE="minor"; shift ;;
    --major) BUMP_TYPE="major"; shift ;;
    --auto) BUMP_TYPE="auto"; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --yes|-y) YES=true; shift ;;
    --no-edit) EDIT_CHANGELOG=false; shift ;;
    --verbose|-v) VERBOSE=true; shift ;;
    --step) RUN_STEP="$2"; shift 2 ;;
    --from) RUN_FROM="$2"; shift 2 ;;
    --status) ACTION="status"; shift ;;
    --rollback) ACTION="rollback"; shift ;;
    --help|-h) ACTION="help"; shift ;;
    *) log_error "Unknown option: $1"; show_help; exit 1 ;;
  esac
done

# Load config
load_config

# Error trap
trap 'log_error "Failed at step: $(get_state "last_step")"; echo "Run: pnpm release (to resume) or pnpm release --rollback"; exit 1' ERR

# Execute
case "${ACTION:-}" in
  "help")
    show_help
    ;;
  "status")
    status
    ;;
  "rollback")
    if has_state; then
      rollback
    else
      log_warn "No release in progress"
    fi
    ;;
  *)
    acquire_lock
    
    if [ -n "${RUN_STEP:-}" ]; then
      run_step "$RUN_STEP"
    elif [ -n "${RUN_FROM:-}" ]; then
      run_from_step "$RUN_FROM"
    else
      resume
    fi
    ;;
esac
